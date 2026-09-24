import CoreGraphics

/// **Ce que le panneau d'aperçu dessine**, déduit de ce que la machine
/// annonce — sans AppKit, pour être testé.
///
/// Le rectangle d'une zone vient de `WindowLayout.frame(for:in:)` appliqué à
/// un écran unitaire : **le même calcul que l'action réelle**. L'aperçu ne
/// peut donc pas montrer autre chose que ce que fera le lever.
public enum PreviewContent: Equatable, Sendable {
    /// La zone visée, dans un écran unitaire (0…1, origine en haut à gauche).
    case zone(CGRect)
    case symbol(PreviewSymbol)
    /// L'icône de l'app, marquée « quitter ». L'hôte fournit l'icône.
    case quitApp
    /// Une séquence sans action : le lever ne fera rien.
    case unrecognized

    public init(_ preview: GestureStateMachine.Preview) {
        guard case let .action(action) = preview else {
            self = .unrecognized
            return
        }
        switch action {
        case .minimize: self = .symbol(.minimize)
        case .toggleFullScreen: self = .symbol(.fullScreen)
        case .close: self = .symbol(.close)
        case .quitApp: self = .quitApp
        default:
            let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
            self = WindowLayout.frame(for: action, in: unit).map(PreviewContent.zone) ?? .unrecognized
        }
    }
}

public enum PreviewSymbol: Equatable, Sendable {
    case minimize, fullScreen, close

    /// Nom SF Symbols.
    public var systemName: String {
        switch self {
        case .minimize: return "arrow.down.to.line"
        case .fullScreen: return "arrow.up.left.and.arrow.down.right"
        case .close: return "xmark"
        }
    }
}

extension GestureStateMachine.Preview {

    /// Ce que le panneau montre, dit en mots. Le panneau compact ne
    /// l'affiche pas ; c'est son étiquette VoiceOver, et le texte des logs.
    public func label(appName: String? = nil) -> String {
        guard case let .action(action) = self else { return "Aucune action" }
        switch action {
        case .leftHalf: return "Moitié gauche"
        case .rightHalf: return "Moitié droite"
        case .topHalf: return "Moitié haute"
        case .bottomHalf: return "Moitié basse"
        case .topLeftQuarter: return "Quart en haut à gauche"
        case .topRightQuarter: return "Quart en haut à droite"
        case .bottomLeftQuarter: return "Quart en bas à gauche"
        case .bottomRightQuarter: return "Quart en bas à droite"
        case .maximize: return "Remplir l'écran"
        case .minimize: return "Réduire dans le Dock"
        case .toggleFullScreen: return "Plein écran"
        case .close: return "Fermer la fenêtre"
        case .centerReduced: return "Centrer"
        case .quitApp: return "Quitter \(appName ?? "l'app")"
        }
    }
}

/// **Où poser le panneau** : près du curseur, décalé vers le centre de
/// l'écran. Sur une barre de titre (en haut), il tombe sous le curseur ; sur
/// le Dock du bas, au-dessus de l'icône ; sur un Dock latéral, à côté. Une
/// seule règle pour toutes les cibles, en coordonnées AX (origine en haut à
/// gauche).
public enum PreviewPlacement {

    /// Écart entre le curseur et le bord le plus proche du panneau.
    public static let gap: CGFloat = 20
    /// Marge minimale avec les bords de l'écran.
    public static let margin: CGFloat = 8

    public static func frame(size: CGSize, cursor: CGPoint, screen: CGRect) -> CGRect {
        var dx = screen.midX - cursor.x
        var dy = screen.midY - cursor.y
        let length = (dx * dx + dy * dy).squareRoot()
        if length < 1 {
            // Curseur au centre : sous lui, par défaut.
            dx = 0
            dy = 1
        } else {
            dx /= length
            dy /= length
        }

        // Assez loin pour que le panneau ne recouvre pas le curseur, quelle
        // que soit la direction : demi-taille projetée sur la direction, plus
        // l'écart.
        let reach = abs(dx) * size.width / 2 + abs(dy) * size.height / 2 + gap
        var frame = CGRect(
            x: cursor.x + dx * reach - size.width / 2,
            y: cursor.y + dy * reach - size.height / 2,
            width: size.width,
            height: size.height
        )

        let bounds = screen.insetBy(dx: margin, dy: margin)
        frame.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - size.width)
        frame.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - size.height)
        return frame
    }
}
