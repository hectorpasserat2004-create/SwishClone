import AppKit
import SwishCloneCore

/// **Le pont du thread du tap vers le thread principal.**
///
/// Sens unique : le tap envoie, il n'attend jamais de réponse. La file
/// principale est FIFO, donc l'ordre des effets est celui des événements —
/// un `hidePreview` ne peut pas passer devant un `showPreview` plus ancien.
enum MainDelivery {

    /// Remplaçable pour les tests.
    nonisolated(unsafe) static var handler: @MainActor @Sendable (GestureTapEngine.Delivery) -> Void = { delivery in
        TapDeliveryHandler.apply(delivery)
    }

    static func send(_ delivery: GestureTapEngine.Delivery) {
        let handler = handler
        DispatchQueue.main.async {
            MainActor.assumeIsolated { handler(delivery) }
        }
    }
}

/// Ce qui se fait sur le thread principal : l'aperçu, l'haptique, l'action
/// sur la fenêtre. Ancien `apply` de `GestureEventTap`, déplacé tel quel.
@MainActor
enum TapDeliveryHandler {

    static func apply(_ delivery: GestureTapEngine.Delivery) {
        for effect in delivery.effects {
            switch effect {
            case let .commit(action):
                debugLog("lever : \(action)")
                switch (delivery.target, action) {
                case let (.dockApp(pid, _), .quitApp):
                    AppController.quit(pid: pid)
                case (.window, .quitApp), (.dockApp, _), (nil, _):
                    // Impossible par construction de la table : la cible et
                    // l'action viennent du même type de cible.
                    debugLog("action \(action) incohérente avec la cible — ignorée")
                case let (.window(window, _), _):
                    WindowController.perform(action, on: window)
                }

            case let .showPreview(preview):
                var appName: String?
                var appIcon: NSImage?
                var targetFrame: CGRect?
                switch delivery.target {
                case let .dockApp(pid, name):
                    appName = name
                    appIcon = NSRunningApplication(processIdentifier: pid)?.icon
                case let .window(_, frame):
                    targetFrame = frame
                case nil:
                    break
                }
                GesturePreviewPanel.show(
                    preview,
                    targetFrame: targetFrame,
                    cursor: delivery.origin,
                    appName: appName,
                    appIcon: appIcon
                )

            case .hidePreview:
                GesturePreviewPanel.hide()

            case let .haptic(haptic):
                // Gardé dans le log le temps de vérifier, au toucher, que le
                // retour arrive bien quand le log le dit.
                debugLog("haptique : \(haptic)")
                let pattern: NSHapticFeedbackManager.FeedbackPattern = haptic == .step ? .alignment : .generic
                NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)

            case let .cancelled(reason):
                switch reason {
                case .stillness: debugLog("geste annulé (immobilité)")
                case .escape: debugLog("geste annulé (Échap)")
                case .interrupted: debugLog("geste annulé (interrompu par le système)")
                }
            }
        }
    }

    private static func debugLog(_ message: @autoclosure () -> String) {
        if GestureClassifier.debugLoggingEnabled {
            print("[GestureEventTap] \(message())")
        }
    }
}
