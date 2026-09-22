import Cocoa
import SwishCloneCore

/// Vue qui capte les événements multi-touch du trackpad (touches indirectes)
/// et les transmet à `GestureClassifier`. Ne contient aucune logique de
/// décision : elle regroupe juste les doigts d'une même session de geste
/// (du premier posé au dernier levé) et transmet le résultat classifié.
///
/// Réécriture complète de la gestion de session (la précédente, basée sur
/// des dictionnaires indexés par `touch.identity`, accumulait des entrées
/// fantômes en usage réel — `touch.identity` ne compare pas de façon
/// fiable d'un event à l'autre pour un même doigt physique). Plus aucune
/// tentative de faire correspondre un doigt individuel entre deux events :
/// à chaque event, on relit l'état complet et actuel via
/// `touches(matching: .touching, in:)` et on ne garde que deux tableaux
/// plats de positions (pas de clés). Trois informations suffisent :
/// combien de doigts sont là, où sont-ils, et est-ce que ce nombre vient
/// de passer de 0 à quelque chose (début de session) ou l'inverse (fin).
public final class TouchGestureView: NSView {

    /// Fenêtre pendant laquelle on continue d'accepter que de nouveaux
    /// doigts rejoignent la session (le nombre de doigts n'est pas figé
    /// dès le premier posé, car une main ne touche jamais tous ses doigts
    /// exactement en même temps).
    private let gatherWindow: TimeInterval = 0.09

    private var isSessionActive = false
    private var isLocked = false
    private var sessionFingerCount = 0
    private var startSnapshot: [FingerPosition] = []
    private var lastSnapshot: [FingerPosition] = []
    private var gatherTimer: Timer?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureTouches()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTouches()
    }

    private func configureTouches() {
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = false
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        if GestureClassifier.debugLoggingEnabled {
            print("[DEBUG session] \(message())")
        }
    }

    override public func touchesBegan(with event: NSEvent) {
        handle(event)
    }

    override public func touchesMoved(with event: NSEvent) {
        handle(event)
    }

    override public func touchesEnded(with event: NSEvent) {
        handle(event)
    }

    override public func touchesCancelled(with event: NSEvent) {
        handle(event)
    }

    /// Point d'entrée unique pour les 4 callbacks : la logique ne dépend
    /// jamais de savoir lequel a été déclenché, seulement de l'état actuel
    /// et complet des doigts en contact.
    private func handle(_ event: NSEvent) {
        let positions = event.touches(matching: .touching, in: self).map(FingerPosition.init(touch:))

        if !isSessionActive {
            guard !positions.isEmpty else { return }
            // Transition 0 -> N : début d'une nouvelle session.
            isSessionActive = true
            isLocked = false
            sessionFingerCount = positions.count
            startSnapshot = positions
            lastSnapshot = positions

            debugLog("nouvelle session : \(positions.count) doigt(s) pour l'instant "
                + "(fenêtre de \(Int(gatherWindow * 1000))ms)")

            gatherTimer?.invalidate()
            gatherTimer = Timer.scheduledTimer(withTimeInterval: gatherWindow, repeats: false) { [weak self] _ in
                self?.isLocked = true
                self?.debugLog("fin du regroupement, session figée avec \(self?.sessionFingerCount ?? -1) doigt(s)")
            }
            return
        }

        guard !positions.isEmpty else {
            // Transition N -> 0 : fin de la session.
            finishSession()
            return
        }

        // Un doigt supplémentaire rejoint la session : seul le passage à
        // un nombre STRICTEMENT plus élevé refige le départ. Une fois le
        // maximum atteint, startSnapshot ne bouge plus — sinon le point de
        // départ suivrait le mouvement pendant toute la fenêtre de
        // regroupement, effaçant un geste rapide fait pendant ce délai.
        if !isLocked && positions.count > sessionFingerCount {
            sessionFingerCount = positions.count
            startSnapshot = positions
            debugLog("doigt supplémentaire : départ refigé avec \(positions.count) doigt(s)")
        }

        lastSnapshot = positions
    }

    private func finishSession() {
        gatherTimer?.invalidate()
        gatherTimer = nil

        debugLog("fin de session : \(sessionFingerCount) doigt(s) au départ, "
            + "\(lastSnapshot.count) à la fin")

        let gesture = GestureClassifier.classify(
            startPositions: startSnapshot,
            endPositions: lastSnapshot,
            fingerCount: sessionFingerCount
        )
        print(gesture)
        WindowController.handleGesture(gesture)

        // Reset total, garanti vierge pour la session suivante.
        isSessionActive = false
        isLocked = false
        sessionFingerCount = 0
        startSnapshot = []
        lastSnapshot = []
    }
}

private extension FingerPosition {
    init(touch: NSTouch) {
        self.init(x: Double(touch.normalizedPosition.x), y: Double(touch.normalizedPosition.y))
    }
}
