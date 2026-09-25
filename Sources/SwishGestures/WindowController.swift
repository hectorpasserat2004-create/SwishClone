import AppKit
// `AXUIElement` n'est pas annoté `Sendable` par Apple ; il est capturé
// par le timer d'animation, qui ne quitte jamais le thread principal.
@preconcurrency import ApplicationServices
import SwishCloneCore

/// Contrôle de fenêtres externes via l'Accessibility API (AXUIElement),
/// et mapping des gestes détectés vers des actions sur la fenêtre au
/// premier plan.
///
/// `@MainActor` : le timer d'animation et le cooldown sont un état
/// partagé sans verrou, et tout ce qui appelle ce type (moniteurs,
/// `TouchGestureView`, interface) est déjà sur le thread principal. Seules
/// les fonctions sans état — permission, lecture de position et de taille —
/// restent `nonisolated`, pour `GestureTarget` et le futur thread du tap.
@MainActor
public enum WindowController {

    // MARK: - Permission Accessibility

    nonisolated public static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Déclenche le prompt système qui envoie l'utilisateur vers
    /// Réglages Système > Confidentialité et sécurité > Accessibilité.
    @discardableResult
    nonisolated public static func requestAccessibilityPermission() -> Bool {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Fenêtre au premier plan

    /// Fenêtre actuellement focalisée de l'application frontmost,
    /// quelle qu'elle soit (jamais la nôtre en particulier).
    public static func getFrontmostWindow() -> AXUIElement? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)

        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard result == .success, let window = focusedWindow else { return nil }
        return (window as! AXUIElement)
    }

    // MARK: - Lecture position/taille

    nonisolated public static func position(of window: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let axValue = value else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    nonisolated public static func size(of window: AXUIElement) -> CGSize? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let axValue = value else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(axValue as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    nonisolated public static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = position(of: window), let size = size(of: window) else { return nil }
        return CGRect(origin: position, size: size)
    }

    // MARK: - Déplacement/redimensionnement

    @discardableResult
    public static func moveAndResize(
        window: AXUIElement,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> Bool {
        var position = CGPoint(x: x, y: y)
        var size = CGSize(width: width, height: height)

        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }

        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

        return positionResult == .success && sizeResult == .success
    }

    // MARK: - Déplacement/redimensionnement animé

    private static var animationTimer: Timer?

    /// Intervalle entre deux étapes (~75 fps). L'interpolation se base sur
    /// le temps écoulé réel et non sur un nombre d'étapes fixe : chaque
    /// écriture AX est un appel synchrone vers l'app cible, dont la durée
    /// varie, donc un compte d'étapes ferait dériver la durée totale.
    private static let animationTickInterval: TimeInterval = 0.013

    /// Comme `moveAndResize`, mais interpolé en ease-out sur `duration`
    /// secondes (l'Accessibility API n'a pas d'animation native : on
    /// simule en écrivant position/taille à intervalles rapprochés).
    ///
    /// Une animation déjà en cours est annulée avant d'en démarrer une
    /// nouvelle, qui part de la position RÉELLE actuelle de la fenêtre
    /// (relue ici), pas du point de départ de l'ancienne. Un seul timer
    /// existe à la fois : les gestes n'agissent que sur la fenêtre au
    /// premier plan, donc il n'y a jamais deux fenêtres à animer.
    public static func animatedMoveAndResize(
        window: AXUIElement,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        duration: TimeInterval? = nil
    ) {
        // Défaut lu ici et non dans la signature : un argument par défaut
        // est évalué hors de l'acteur principal.
        let duration = duration ?? GestureSettings.shared.animationDuration

        animationTimer?.invalidate()
        animationTimer = nil

        guard let startPosition = position(of: window), let startSize = size(of: window) else {
            // Impossible de lire l'état de départ : pas d'interpolation
            // possible, on applique directement.
            moveAndResize(window: window, x: x, y: y, width: width, height: height)
            return
        }

        let startTime = Date()
        let timer = Timer(timeInterval: animationTickInterval, repeats: true) { timer in
            // Timer ajouté à `RunLoop.main` ci-dessous : le bloc y tourne,
            // mais son type (`@Sendable`) ne le dit pas au compilateur.
            MainActor.assumeIsolated {
                let t = min(1, Date().timeIntervalSince(startTime) / duration)

                if t >= 1 {
                    // Dernière étape : valeurs exactes de la cible, sans
                    // erreur d'arrondi cumulée.
                    moveAndResize(window: window, x: x, y: y, width: width, height: height)
                    timer.invalidate()
                    if animationTimer === timer { animationTimer = nil }
                    return
                }

                // ease-out cubique : grands pas au début, petits à la fin.
                let eased = CGFloat(1 - pow(1 - t, 3))
                moveAndResize(
                    window: window,
                    x: startPosition.x + (x - startPosition.x) * eased,
                    y: startPosition.y + (y - startPosition.y) * eased,
                    width: startSize.width + (width - startSize.width) * eased,
                    height: startSize.height + (height - startSize.height) * eased
                )
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    // MARK: - Plein écran natif

    /// Attribut Accessibility non documenté officiellement par Apple,
    /// mais largement utilisé par les outils d'automatisation existants
    /// (équivalent de `kAXFullScreenAttribute`) : bascule le vrai plein
    /// écran natif macOS (bouton vert), qui donne son propre bureau/Space
    /// à la fenêtre — différent de `moveAndResize` qui redimensionne
    /// juste la fenêtre pour remplir l'écran sans changer de bureau.
    private static let fullScreenAttributeName = "AXFullScreen" as CFString

    /// Lit l'état actuel de `AXFullScreen` et le bascule (true -> false,
    /// false -> true) — un pinch out répété fait donc entrer ET sortir du
    /// plein écran natif, comme recliquer sur le bouton vert. Ne plante
    /// jamais : certaines apps ne supportent ni la lecture ni l'écriture
    /// de cet attribut, auquel cas on logge et on ne fait rien.
    @discardableResult
    public static func toggleNativeFullScreen(window: AXUIElement) -> Bool {
        var value: AnyObject?
        let readResult = AXUIElementCopyAttributeValue(window, fullScreenAttributeName, &value)

        guard readResult == .success, let currentValue = (value as? NSNumber)?.boolValue else {
            debugLog("AXFullScreen illisible sur cette fenêtre (result=\(readResult.rawValue)) — "
                + "app probablement non compatible, pas de bascule.")
            return false
        }

        let newValue: CFBoolean = currentValue ? kCFBooleanFalse : kCFBooleanTrue
        let setResult = AXUIElementSetAttributeValue(window, fullScreenAttributeName, newValue)

        guard setResult == .success else {
            debugLog("AXFullScreen non modifiable sur cette fenêtre (result=\(setResult.rawValue)) — "
                + "app probablement non compatible, pas de bascule.")
            return false
        }

        return true
    }

    // MARK: - Actions

    /// Délai minimum entre deux actions de fenêtre déclenchées par geste,
    /// pour éviter qu'une même intention ne se ré-applique en double si le
    /// classifieur ré-émet un geste très rapidement après le précédent.
    private static let actionCooldown: TimeInterval = 0.3
    private static var lastActionDate: Date?

    private static func debugLog(_ message: @autoclosure () -> String) {
        if GestureClassifier.debugLoggingEnabled {
            print("[WindowController] \(message())")
        }
    }

    /// Applique `action` à `window` — la fenêtre visée par le geste, pas
    /// forcément celle au premier plan. Ne fait rien (sans planter) si la
    /// permission Accessibility manque ou pendant le cooldown.
    ///
    /// **L'écran de référence est celui de la fenêtre**, et sa zone utile
    /// (`visibleFrame` : sans la barre de menus ni le Dock). Avant, c'était
    /// `NSScreen.main` — l'écran de la fenêtre *active* — et son cadre entier
    /// posé en (0, 0) : faux dès qu'on vise une fenêtre sur un autre écran.
    public static func perform(_ action: GestureAction, on window: AXUIElement) {
        guard isAccessibilityTrusted() else { return }

        if let lastActionDate, Date().timeIntervalSince(lastActionDate) < actionCooldown {
            debugLog("action ignorée : cooldown actif (\(Date().timeIntervalSince(lastActionDate))s < \(actionCooldown)s)")
            return
        }
        lastActionDate = Date()
        // Toute nouvelle action rend caduque la vérification de débordement
        // de la précédente.
        overflowCheckGeneration &+= 1

        switch action {
        case .minimize:
            // Repose sur AXMinimizedAttribute : fonctionne pour la grande
            // majorité des apps AppKit, mais certaines fenêtres (panneaux
            // système, certaines apps non standard) peuvent l'ignorer
            // silencieusement — l'API ne donne aucun moyen fiable de le
            // détecter à l'avance.
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)

        case .toggleFullScreen:
            toggleNativeFullScreen(window: window)

        case .close:
            pressCloseButton(of: window)

        case .quitApp:
            // Une action d'app, pas de fenêtre : `AppController.quit`.
            debugLog("quitApp reçu par WindowController — ignoré")

        default:
            guard let current = frame(of: window),
                  let visible = visibleFrame(forWindowAt: current),
                  let target = WindowLayout.frame(for: action, in: visible) else {
                debugLog("action \(action) impossible : cadre ou écran introuvable")
                return
            }
            animatedMoveAndResize(
                window: window,
                x: target.minX,
                y: target.minY,
                width: target.width,
                height: target.height
            )
            scheduleOverflowCheck(of: window, in: visible)
        }
    }

    // MARK: - Fenêtres qui refusent la taille demandée

    private static var overflowCheckGeneration = 0

    /// Relectures après l'animation : la première juste après, la seconde
    /// plus tard pour les apps qui se réajustent en différé.
    private static let overflowCheckDelays: [TimeInterval] = [0.1, 0.6]

    /// **Relit le cadre réel une fois l'animation finie et ramène la
    /// fenêtre dans la zone utile si elle en déborde** — sans toucher à sa
    /// taille. Voir `WindowLayout.correctedFrame(for:in:)`.
    ///
    /// Deux relectures, parce qu'une app peut se réajuster tout de suite ou
    /// un peu plus tard. La correction est idempotente : une fenêtre déjà
    /// remise en place ne bouge plus. Une nouvelle action entre-temps annule
    /// les relectures en attente (`overflowCheckGeneration`).
    private static func scheduleOverflowCheck(of window: AXUIElement, in visible: CGRect) {
        let generation = overflowCheckGeneration
        let animation = GestureSettings.shared.animationDuration
        for delay in overflowCheckDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + animation + delay) {
                MainActor.assumeIsolated {
                    guard generation == overflowCheckGeneration,
                          let actual = frame(of: window),
                          let corrected = WindowLayout.correctedFrame(for: actual, in: visible) else { return }
                    debugLog("fenêtre hors de l'écran après l'action (\(actual)) — ramenée en \(corrected), taille inchangée")
                    animatedMoveAndResize(
                        window: window,
                        x: corrected.minX,
                        y: corrected.minY,
                        width: corrected.width,
                        height: corrected.height
                    )
                }
            }
        }
    }

    /// Presse le bouton de fermeture par AX, plutôt que de fermer la fenêtre
    /// d'autorité : c'est le même chemin qu'un clic, donc l'app décide —
    /// feuille « Enregistrer ? » comprise. Une fenêtre sans bouton de
    /// fermeture (certains panneaux) n'est pas touchée.
    private static func pressCloseButton(of window: AXUIElement) {
        var button: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button, CFGetTypeID(button) == AXUIElementGetTypeID() else {
            debugLog("fermeture impossible : pas de bouton de fermeture exposé par AX")
            return
        }
        let result = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        if result != .success {
            debugLog("fermeture refusée par l'app (erreur AX \(result.rawValue))")
        }
    }

    /// La zone utile de l'écran qui porte la fenêtre, en coordonnées AX.
    static func visibleFrame(forWindowAt windowFrame: CGRect) -> CGRect? {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return nil }
        let frames = screens.map { ScreenGeometry.axRect(fromCocoa: $0.frame, primaryScreenHeight: primaryHeight) }
        guard let index = ScreenGeometry.screenIndex(for: windowFrame, among: frames) else { return nil }
        return ScreenGeometry.axRect(fromCocoa: screens[index].visibleFrame, primaryScreenHeight: primaryHeight)
    }

    /// Chemin de la fenêtre de test locale (`TouchGestureView`) : agit sur
    /// la fenêtre au premier plan, et jamais sur la nôtre.
    public static func handleGesture(_ gesture: Gesture) {
        guard isAccessibilityTrusted() else {
            requestAccessibilityPermission()
            return
        }

        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            debugLog("geste ignoré : notre propre fenêtre de test est au premier plan")
            return
        }

        let action: GestureAction?
        switch gesture {
        case let .swipe(direction, _): action = GestureSequence.resolve(swipes: [direction])
        case let .pinch(direction, _): action = GestureSequence.resolve(pinches: [direction])
        case .tap: action = nil
        }

        guard let action, let window = getFrontmostWindow() else { return }
        perform(action, on: window)
    }
}
