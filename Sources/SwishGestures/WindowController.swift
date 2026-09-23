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
/// les deux fonctions de permission, sans état, restent `nonisolated`.
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

    public static func position(of window: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let axValue = value else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    public static func size(of window: AXUIElement) -> CGSize? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
              let axValue = value else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(axValue as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    public static func frame(of window: AXUIElement) -> CGRect? {
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

    // MARK: - Mapping gestes -> actions

    /// Fraction de l'écran occupée par la fenêtre lors d'un pinch in.
    private static let pinchInScale: CGFloat = 0.6

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

    /// Applique l'action correspondant au geste détecté sur la fenêtre
    /// actuellement au premier plan. Ne fait rien (sans planter) si la
    /// permission Accessibility manque, si aucune fenêtre n'est trouvée,
    /// si c'est notre propre fenêtre de test qui est au premier plan, ou
    /// si on est encore dans la période de cooldown suivant la dernière
    /// action.
    public static func handleGesture(_ gesture: Gesture) {
        guard isAccessibilityTrusted() else {
            requestAccessibilityPermission()
            return
        }

        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            debugLog("geste ignoré : notre propre fenêtre de test est au premier plan")
            return
        }

        guard let window = getFrontmostWindow(), let screen = NSScreen.main else { return }

        if case .tap = gesture { return }

        if let lastActionDate, Date().timeIntervalSince(lastActionDate) < actionCooldown {
            debugLog("geste ignoré : cooldown actif (\(Date().timeIntervalSince(lastActionDate))s < \(actionCooldown)s)")
            return
        }
        lastActionDate = Date()

        let screenFrame = screen.frame

        switch gesture {
        case .swipe(direction: .left, fingers: _):
            animatedMoveAndResize(
                window: window,
                x: 0,
                y: 0,
                width: screenFrame.width / 2,
                height: screenFrame.height
            )

        case .swipe(direction: .right, fingers: _):
            animatedMoveAndResize(
                window: window,
                x: screenFrame.width / 2,
                y: 0,
                width: screenFrame.width / 2,
                height: screenFrame.height
            )

        case .swipe(direction: .up, fingers: _):
            // Plein écran "classique" : redimensionne pour remplir
            // l'écran, reste sur le même bureau/Space. Différent de
            // pinch out, qui bascule le vrai plein écran natif macOS.
            animatedMoveAndResize(
                window: window,
                x: 0,
                y: 0,
                width: screenFrame.width,
                height: screenFrame.height
            )

        case .pinch(direction: .out, fingers: _):
            toggleNativeFullScreen(window: window)

        case .swipe(direction: .down, fingers: _):
            // Repose sur AXMinimizedAttribute : fonctionne pour la grande
            // majorité des apps AppKit, mais certaines fenêtres (panneaux
            // système, certaines apps non standard) peuvent l'ignorer
            // silencieusement — l'API ne donne aucun moyen fiable de le
            // détecter à l'avance.
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)

        case .pinch(direction: .in_, fingers: _):
            let width = screenFrame.width * pinchInScale
            let height = screenFrame.height * pinchInScale
            animatedMoveAndResize(
                window: window,
                x: (screenFrame.width - width) / 2,
                y: (screenFrame.height - height) / 2,
                width: width,
                height: height
            )

        case .tap:
            break
        }
    }
}
