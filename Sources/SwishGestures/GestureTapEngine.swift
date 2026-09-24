import CoreGraphics
import Foundation
import SwishCloneCore

/// **Le cœur du tap, sans thread ni tap : un événement entre, une décision
/// sort.**
///
/// Tient la machine à états, la cible du geste en cours et le curseur du
/// début du geste. **Tout se passe sur le thread du tap** — rien n'est
/// partagé, donc rien n'est verrouillé ; seuls les réglages, relus à chaque
/// événement dans leur copie verrouillée, viennent d'ailleurs.
///
/// Ce qui doit se faire sur le thread principal (aperçu, haptique, action
/// sur la fenêtre) n'est jamais appelé d'ici : l'engine émet des
/// `Delivery`, des valeurs, que l'hôte envoie où il veut. La décision
/// « avaler ou laisser passer » ne dépend que de la machine : le callback
/// n'attend donc jamais le thread principal.
///
/// Les dépendances sont injectées (horloge, test de cible, sortie) : tout se
/// rejoue dans `swift test`.
final class GestureTapEngine: @unchecked Sendable {

    /// Ce qui part vers le thread principal, en un seul paquet ordonné :
    /// les effets d'un événement, avec la cible et le curseur qu'ils
    /// supposent au moment où ils sont émis.
    struct Delivery: @unchecked Sendable {
        var effects: [GestureStateMachine.Effect]
        var target: GestureTarget.Target?
        var origin: CGPoint
    }

    /// Au-delà, le test de cible ferait sentir sa latence : une fois le tap
    /// actif, il retient tout le défilement du système pendant qu'il tourne.
    static let hitTestBudget: TimeInterval = 0.005

    typealias HitTest = (_ location: CGPoint, _ zoneHeight: Double) -> GestureTarget.Target?

    private var machine: GestureStateMachine
    private var target: GestureTarget.Target?
    private var origin: CGPoint = .zero

    private let settings: TapSettingsStore
    private let now: () -> TimeInterval
    private let hitTest: HitTest
    private let deliver: (Delivery) -> Void
    private let log: (String) -> Void
    private let probe: (TapStep, UInt64) -> Void

    init(
        settings: TapSettingsStore,
        now: @escaping () -> TimeInterval,
        hitTest: @escaping HitTest,
        deliver: @escaping (Delivery) -> Void,
        log: @escaping (String) -> Void = { _ in },
        probe: @escaping (TapStep, UInt64) -> Void = { _, _ in }
    ) {
        self.settings = settings
        self.now = now
        self.hitTest = hitTest
        self.deliver = deliver
        self.log = log
        self.probe = probe
        machine = GestureStateMachine(configuration: settings.read().machine)
    }

    var isTracking: Bool { machine.isTracking }
    var nextDeadline: TimeInterval? { machine.nextDeadline }

    func process(_ event: GestureStateMachine.Event, at location: CGPoint) -> GestureStateMachine.Disposition {
        // Relus à chaque événement : un réglage changé s'applique au geste
        // suivant, sans relancer.
        let current = settings.read()
        machine.configuration = current.machine

        let output = machine.handle(event, at: now()) { [self] in
            let started = now()
            target = hitTest(location, current.zoneHeight)
            origin = location
            let elapsed = now() - started
            probe(.hitTest, UInt64(max(0, elapsed) * 1_000_000_000))
            if elapsed > Self.hitTestBudget {
                log("test de cible lent : \(Int(elapsed * 1000)) ms (budget \(Int(Self.hitTestBudget * 1000)) ms)")
            }
            return target?.kind
        }
        publish(output.effects, settings: current)
        return output.disposition
    }

    func tick() {
        let current = settings.read()
        machine.configuration = current.machine
        let output = machine.handle(.tick, at: now()) { nil }
        publish(output.effects, settings: current)
    }

    /// Abandonne tout geste en cours. Pour un tap que macOS vient de couper :
    /// des événements ont été perdus, le geste n'a plus de fin fiable.
    func reset() {
        publish(machine.reset(), settings: settings.read())
        target = nil
    }

    /// Filtre ce que les réglages éteignent, puis émet d'un bloc.
    private func publish(_ effects: [GestureStateMachine.Effect], settings: TapSettings) {
        let kept = effects.filter { effect in
            switch effect {
            case .showPreview: return settings.previewEnabled
            case .haptic: return settings.hapticsEnabled
            default: return true
            }
        }
        guard kept.isEmpty == false else { return }
        let started = now()
        deliver(Delivery(effects: kept, target: target, origin: origin))
        probe(.deliver, UInt64(max(0, now() - started) * 1_000_000_000))
    }
}
