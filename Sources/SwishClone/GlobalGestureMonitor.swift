import Cocoa
import SwishGestures

/// Prototype isolé, séparé du pipeline existant (TouchGestureView /
/// GestureClassifier / WindowController — rien de tout ça n'est touché
/// ici). Sert uniquement à vérifier si `NSEvent.addGlobalMonitorForEvents`
/// peut capter des gestes trackpad pendant qu'une AUTRE app est au premier
/// plan, sans jamais activer une fenêtre de SwishClone.
///
/// Écoute trois types d'events en parallèle pour trancher une question
/// ouverte : `.swipe` correspond historiquement aux swipes "système"
/// (navigation par pages, 2-4 doigts avec accélération), alors qu'un swipe
/// libre façon Swish pourrait plutôt remonter via `.scrollWheel` avec
/// `momentumPhase`/`phase`. On logge les trois pour voir lequel réagit
/// réellement à un swipe 2 doigts volontaire en usage réel.
enum GlobalGestureMonitor {

    private static var magnifyMonitor: Any?
    private static var swipeMonitor: Any?
    private static var scrollMonitor: Any?

    static func start() {
        // Hypothèse à vérifier : sans la permission Accessibility,
        // addGlobalMonitorForEvents ne reçoit rien, sans erreur ni log —
        // silencieusement. On vérifie donc avant de démarrer, plutôt que
        // de se demander pourquoi la console reste vide.
        guard WindowController.isAccessibilityTrusted() else {
            print("[GlobalGestureMonitor] permission Accessibility manquante — "
                + "les monitors globaux ne recevraient probablement rien. "
                + "Demande de la permission…")
            WindowController.requestAccessibilityPermission()
            return
        }

        magnifyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .magnify) { event in
            print("[GlobalGestureMonitor] .magnify magnitude=\(event.magnification)")
        }

        swipeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .swipe) { event in
            print("[GlobalGestureMonitor] .swipe deltaX=\(event.deltaX) deltaY=\(event.deltaY)")
        }

        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { event in
            print("[GlobalGestureMonitor] .scrollWheel "
                + "phase=\(event.phase.rawValue) momentumPhase=\(event.momentumPhase.rawValue) "
                + "deltaX=\(event.deltaX) deltaY=\(event.deltaY)")
        }

        print("[GlobalGestureMonitor] monitors démarrés (magnify / swipe / scrollWheel)")
    }

    static func stop() {
        for monitor in [magnifyMonitor, swipeMonitor, scrollMonitor] {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        magnifyMonitor = nil
        swipeMonitor = nil
        scrollMonitor = nil
    }
}
