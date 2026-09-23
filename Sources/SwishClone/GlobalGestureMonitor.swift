import Cocoa
import SwishCloneCore
import SwishGestures

/// Capture le swipe globalement, via `NSEvent.addGlobalMonitorForEvents`
/// sur `.scrollWheel` — le signal déjà validé comme fiable pour un swipe
/// 2 doigts libre (par opposition à `.swipe`, qui correspond aux swipes
/// système de navigation). `.magnify`/`.swipe` restent aussi surveillés
/// pour référence/comparaison, mais seul `.scrollWheel` pilote une
/// action réelle ici — le pinch global est géré séparément par
/// `EventTapGestureMonitor` (CGEventTap), pas par ce fichier.
///
/// Un monitor global (`addGlobalMonitorForEvents`) est intrinsèquement
/// "observation seule" : il ne peut ni consommer ni modifier l'event, à
/// la différence d'un `CGEventTap` en mode actif. Le scroll normal
/// (page web, document...) continue donc de fonctionner partout, y
/// compris dans la bande du haut, sans rien à faire de plus pour ça.
///
/// Convention de signe confirmée empiriquement sur les deux axes :
/// `deltaX < 0` = swipe gauche (même sens que `GestureClassifier`),
/// `deltaY > 0` = swipe vers le BAS — l'axe Y va donc dans le sens
/// opposé à celui de `GestureClassifier` (touches directes), corrigé
/// après un test réel qui montrait les deux inversés.
enum GlobalGestureMonitor {

    /// Somme cumulée en dessous de laquelle un swipe est ignoré (scroll
    /// involontaire). À calibrer comme `EventTapGestureMonitor.pinchThreshold`.
    private static let swipeThreshold: Double = 20

    private static var scrollSessionActive = false
    private static var sumDeltaX: Double = 0
    private static var sumDeltaY: Double = 0

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
            handleScrollEvent(event)
        }

        print("[GlobalGestureMonitor] monitors démarrés (magnify / swipe / scrollWheel — "
            + "swipe global actif, seuil \(swipeThreshold))")
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
        scrollSessionActive = false
        sumDeltaX = 0
        sumDeltaY = 0
    }

    /// Session par phase, même principe que la fenêtre de fin de session
    /// du pinch (EventTapGestureMonitor) : .began démarre l'accumulation,
    /// .ended (phase OU momentumPhase, un scroll qui glisse termine sur
    /// la fin du momentum, pas sur .ended de la phase tactile) classe le
    /// geste sur le déplacement cumulé total.
    private static func handleScrollEvent(_ event: NSEvent) {
        if event.phase.contains(.began) {
            scrollSessionActive = true
            sumDeltaX = 0
            sumDeltaY = 0
        }

        guard scrollSessionActive else { return }

        sumDeltaX += event.deltaX
        sumDeltaY += event.deltaY

        let sessionEnding = event.phase.contains(.ended) || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)

        if sessionEnding {
            finishScrollSession()
        }
    }

    private static func finishScrollSession() {
        let dx = sumDeltaX
        let dy = sumDeltaY
        scrollSessionActive = false
        sumDeltaX = 0
        sumDeltaY = 0

        guard max(abs(dx), abs(dy)) >= swipeThreshold else {
            print("[GlobalGestureMonitor] swipe ignoré : sumDeltaX=\(dx) sumDeltaY=\(dy) "
                + "(< seuil \(swipeThreshold))")
            return
        }

        let direction: SwipeDirection
        if abs(dx) > abs(dy) {
            direction = dx < 0 ? .left : .right
        } else {
            // Inversé après test réel : un swipe physique vers le haut
            // donnait dy > 0, mais était classé .up alors qu'il fallait
            // .down — la convention scrollWheel sur cet axe va donc dans
            // le sens opposé à celle de GestureClassifier (touches
            // directes). Confirmé empiriquement, contrairement à l'axe X.
            direction = dy > 0 ? .down : .up
        }

        let gesture = Gesture.swipe(direction: direction, fingers: 2)
        print("[GlobalGestureMonitor] fin de session swipe : sumDeltaX=\(dx) sumDeltaY=\(dy) "
            + "-> retenu, \(gesture)")

        // Le diagnostic ci-dessus s'affiche toujours, où que soit le
        // curseur — seule l'action finale sur la fenêtre est conditionnée
        // à la zone (mode "Menubar" façon Swish), même principe que le
        // pinch dans EventTapGestureMonitor.
        guard GestureZone.isCursorInActiveWindowTitlebar() else {
            print("[GlobalGestureMonitor] swipe ignoré : curseur hors zone")
            return
        }

        WindowController.handleGesture(gesture)
    }
}
