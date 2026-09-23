import SwishCloneCore

/// Point d'entrée public de la détection globale : démarre et arrête
/// ensemble le swipe (`GlobalGestureMonitor`, `NSEvent`) et le pinch
/// (`EventTapGestureMonitor`, `CGEventTap`). Les deux moniteurs restent
/// internes — un hôte (l'app SwishClone, ou bran) n'a besoin que de ceci
/// et de `GestureSettings`.
///
/// **Tout ou rien.** Si le tap du pinch ne se crée pas, le swipe est
/// arrêté aussi : un état « à moitié démarré » ne se laisse pas afficher
/// honnêtement par un hôte qui n'a qu'un interrupteur.
///
/// Ne demande jamais la permission Accessibility lui-même : c'est à
/// l'hôte de décider quand montrer la fenêtre du système (voir
/// `WindowController.requestAccessibilityPermission()`).
@MainActor
public enum GestureMonitor {

    public enum StartError: Error {
        /// Sans elle, les deux moniteurs ne recevraient rien, sans erreur.
        case accessibilityNotTrusted
        /// `CGEventTapCreate` a échoué alors que l'Accessibilité est
        /// accordée — le plus souvent la permission « Contrôle de
        /// l'entrée » (Input Monitoring). Le détail est dans la console.
        case eventTapUnavailable
    }

    public private(set) static var isRunning = false

    /// Sans effet si la détection tourne déjà : appeler deux fois
    /// n'installe pas deux jeux de moniteurs.
    public static func start() throws {
        guard !isRunning else { return }
        guard WindowController.isAccessibilityTrusted() else {
            throw StartError.accessibilityNotTrusted
        }

        GlobalGestureMonitor.start()
        guard EventTapGestureMonitor.start() else {
            GlobalGestureMonitor.stop()
            throw StartError.eventTapUnavailable
        }
        isRunning = true
    }

    public static func stop() {
        guard isRunning else { return }
        GlobalGestureMonitor.stop()
        EventTapGestureMonitor.stop()
        isRunning = false
    }
}
