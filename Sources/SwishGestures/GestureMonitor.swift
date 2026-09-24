import SwishCloneCore

/// Point d'entrée public de la détection globale : démarre et arrête le
/// tap unique du swipe et du pincement (`GestureEventTap`), qui reste
/// interne — un hôte (l'app SwishClone, ou bran) n'a besoin que de ceci et
/// de `GestureSettings`.
///
/// **Tout ou rien.** Si l'un des deux taps (gestes, ou Échap) ne se crée
/// pas, rien ne tourne : un état « à moitié démarré » ne se laisse pas
/// afficher honnêtement par un hôte qui n'a qu'un interrupteur.
///
/// Ne demande jamais la permission Accessibility lui-même : c'est à
/// l'hôte de décider quand montrer la fenêtre du système (voir
/// `WindowController.requestAccessibilityPermission()`).
///
/// **Un seul hôte à la fois sur une même session.** Rien n'empêche deux
/// processus (l'app SwishClone et bran) de démarrer chacun leur détection :
/// les deux suivent alors le même geste et agissent sur la même fenêtre.
/// Pour les tests manuels, ne jamais les faire tourner ensemble — voir le
/// README.
@MainActor
public enum GestureMonitor {

    public enum StartError: Error {
        /// Sans elle, le tap ne recevrait rien, sans erreur.
        case accessibilityNotTrusted
        /// `CGEventTapCreate` a échoué alors que l'Accessibilité est
        /// accordée — le plus souvent la permission « Contrôle de
        /// l'entrée » (Input Monitoring). Le détail est dans la console.
        case eventTapUnavailable
    }

    public private(set) static var isRunning = false

    /// Sans effet si la détection tourne déjà : appeler deux fois
    /// n'installe pas deux taps.
    public static func start() throws {
        guard !isRunning else { return }
        guard WindowController.isAccessibilityTrusted() else {
            throw StartError.accessibilityNotTrusted
        }

        guard GestureEventTap.start() else {
            throw StartError.eventTapUnavailable
        }
        isRunning = true
    }

    public static func stop() {
        guard isRunning else { return }
        GestureEventTap.stop()
        isRunning = false
    }
}
