import AppKit
import ApplicationServices
import SwishCloneCore

/// Contrôle de fenêtres externes via l'Accessibility API (AXUIElement),
/// et mapping des gestes détectés vers des actions sur la fenêtre au
/// premier plan.
public enum WindowController {

    // MARK: - Permission Accessibility

    public static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Déclenche le prompt système qui envoie l'utilisateur vers
    /// Réglages Système > Confidentialité et sécurité > Accessibilité.
    @discardableResult
    public static func requestAccessibilityPermission() -> Bool {
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
            moveAndResize(
                window: window,
                x: 0,
                y: 0,
                width: screenFrame.width / 2,
                height: screenFrame.height
            )

        case .swipe(direction: .right, fingers: _):
            moveAndResize(
                window: window,
                x: screenFrame.width / 2,
                y: 0,
                width: screenFrame.width / 2,
                height: screenFrame.height
            )

        case .swipe(direction: .up, fingers: _), .pinch(direction: .out, fingers: _):
            moveAndResize(
                window: window,
                x: 0,
                y: 0,
                width: screenFrame.width,
                height: screenFrame.height
            )

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
            moveAndResize(
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
