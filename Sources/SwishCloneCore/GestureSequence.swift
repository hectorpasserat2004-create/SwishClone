/// La table qui traduit une séquence d'étapes en action, selon la cible.
///
/// Séparée de la machine à états pour que le catalogue puisse grandir
/// (tiers, fermer, quitter…) sans toucher à la mécanique du geste : la
/// machine dit « l'utilisateur a fait ↓ puis → », cette table dit « quart
/// en bas à droite ».
public enum GestureSequence {

    public enum Family: Equatable, Sendable {
        case swipe, pinch
    }

    /// Une famille de gestes a-t-elle au moins une action sur cette cible ?
    /// Sinon, la machine ne capture pas le geste et le laisse à l'app (le
    /// Dock, pour un swipe sur une icône) — à l'étape 5, un geste capturé
    /// sera avalé.
    public static func accepts(_ family: Family, on kind: GestureTargetKind) -> Bool {
        switch (family, kind) {
        case (_, .titlebar): return true
        case (.pinch, .dockApp): return true
        case (.swipe, .dockApp): return false
        }
    }

    /// `nil` pour une séquence qui ne correspond à rien : l'aperçu l'annonce,
    /// et le lever ne fait rien.
    public static func resolve(swipes steps: [SwipeDirection], on kind: GestureTargetKind = .titlebar) -> GestureAction? {
        guard kind == .titlebar else { return nil }
        switch steps {
        case [.left]: return .leftHalf
        case [.right]: return .rightHalf
        case [.up]: return .maximize
        case [.down]: return .minimize
        case [.up, .up]: return .topHalf
        case [.down, .down]: return .bottomHalf
        default: break
        }

        // Quarts : une étape horizontale et une verticale, dans n'importe
        // quel ordre (« Both orders work », Swish).
        guard steps.count == 2 else { return nil }
        let horizontal = steps.first { $0 == .left || $0 == .right }
        let vertical = steps.first { $0 == .up || $0 == .down }
        switch (horizontal, vertical) {
        case (.left, .up): return .topLeftQuarter
        case (.right, .up): return .topRightQuarter
        case (.left, .down): return .bottomLeftQuarter
        case (.right, .down): return .bottomRightQuarter
        default: return nil
        }
    }

    public static func resolve(pinches steps: [PinchDirection], on kind: GestureTargetKind = .titlebar) -> GestureAction? {
        switch (kind, steps) {
        case (.titlebar, [.out]): return .toggleFullScreen
        // Comme Swish : resserrer ferme. Resserrer deux fois (quitter l'app)
        // attend le P1, et une phase de pincement lisible.
        case (.titlebar, [.in_]): return .close
        // Sur une icône du Dock, resserrer quitte l'app (Swish, onglet Apps).
        // Écarter (nouvelle fenêtre, chez Swish) viendra plus tard.
        case (.dockApp, [.in_]): return .quitApp
        default: return nil
        }
    }
}
