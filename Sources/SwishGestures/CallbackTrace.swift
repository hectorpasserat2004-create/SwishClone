import Foundation

/// **Les sous-étapes d'un callback de tap**, pour localiser un pic plutôt que
/// le deviner.
enum TapStep: Int, CaseIterable, Sendable {
    /// Décodage de l'événement : `NSEvent(cgEvent:)` et lecture des champs.
    case decode
    /// Toute la machine à états, test de cible et envoi compris.
    case engine
    /// Le test de cible (AX), au début d'un geste. Compris dans `engine`.
    case hitTest
    /// L'envoi vers le thread principal. Compris dans `engine`.
    case deliver
    /// `CGEvent.tapEnable` : un aller-retour mach vers le serveur de fenêtres.
    case tapEnable
    /// La reprogrammation du timer d'échéance.
    case timer
    /// Les `print` de diagnostic.
    case diagnostics

    var label: String {
        switch self {
        case .decode: "décodage"
        case .engine: "machine"
        case .hitTest: "cible"
        case .deliver: "envoi"
        case .tapEnable: "tapEnable"
        case .timer: "timer"
        case .diagnostics: "diagnostics"
        }
    }

    /// Une étape imbriquée est déjà comptée dans une autre : elle s'affiche,
    /// mais ne se soustrait pas deux fois du temps non attribué.
    var isNested: Bool { self == .hitTest || self == .deliver }
}

/// Le temps passé, par étape, dans le callback en cours, et le pire vu
/// depuis le début.
struct CallbackTrace: Equatable {
    private var current = [UInt64](repeating: 0, count: TapStep.allCases.count)
    private var maxima = [UInt64](repeating: 0, count: TapStep.allCases.count)
    private var kind = ""
    private(set) var tapEnableCalls = 0
    private(set) var callbacks = 0

    mutating func begin(kind: String) {
        current = [UInt64](repeating: 0, count: TapStep.allCases.count)
        self.kind = kind
        callbacks += 1
    }

    mutating func add(_ step: TapStep, nanoseconds: UInt64) {
        current[step.rawValue] += nanoseconds
        if step == .tapEnable { tapEnableCalls += 1 }
    }

    /// Retient le pire de chaque étape ; à appeler une fois le callback fini.
    mutating func finish() {
        for index in current.indices { maxima[index] = max(maxima[index], current[index]) }
    }

    /// Le détail du callback en cours : les étapes non nulles, puis ce qui
    /// n'est attribué à aucune (« reste »).
    func breakdown(total: UInt64) -> String {
        var parts: [String] = []
        var accounted: UInt64 = 0
        for step in TapStep.allCases where current[step.rawValue] > 0 {
            let value = current[step.rawValue]
            parts.append("\(step.label) \(value / 1000) µs" + (step.isNested ? " (dans machine)" : ""))
            if step.isNested == false { accounted += value }
        }
        parts.append("reste \((total > accounted ? total - accounted : 0) / 1000) µs")
        return "[\(kind)] " + parts.joined(separator: " · ")
    }

    /// Le pire de chaque étape, et le nombre d'appels `tapEnable`.
    var summary: String {
        let steps = TapStep.allCases.map { "\($0.label) \(maxima[$0.rawValue] / 1000) µs" }
        return "max par étape : " + steps.joined(separator: ", ")
            + " ; \(tapEnableCalls) appels tapEnable pour \(callbacks) callbacks"
    }
}

/// `CallbackTrace` derrière une référence : l'engine et le runner
/// l'alimentent tous deux, depuis le thread du tap.
final class TraceRecorder: @unchecked Sendable {
    private var trace = CallbackTrace()

    func begin(kind: String) { trace.begin(kind: kind) }
    func add(_ step: TapStep, nanoseconds: UInt64) { trace.add(step, nanoseconds: nanoseconds) }
    func finish() { trace.finish() }
    func breakdown(total: UInt64) -> String { trace.breakdown(total: total) }
    var summary: String { trace.summary }
}
