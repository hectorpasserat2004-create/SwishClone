import CoreGraphics

/// La géométrie des écrans et des fenêtres, **en coordonnées AX** : origine
/// en haut à gauche de l'écran principal, y croissant vers le bas. C'est
/// l'espace dans lequel l'API Accessibility lit et écrit les fenêtres ; tout
/// ce qui vient d'AppKit (`NSScreen`, origine en bas à gauche) y est converti
/// une fois, à l'entrée, par `ScreenGeometry.axRect`.
public enum ScreenGeometry {

    /// Convertit un rectangle AppKit en rectangle AX.
    ///
    /// La référence est la hauteur de l'écran **principal** (celui qui porte
    /// la barre de menus, `NSScreen.screens.first`), ancre des deux espaces —
    /// pas `NSScreen.main`, qui désigne l'écran de la fenêtre active.
    public static func axRect(fromCocoa rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// L'inverse, pour poser une fenêtre AppKit à un cadre calculé en AX. La
    /// formule est la même : le changement d'origine est sa propre inverse.
    public static func cocoaRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        axRect(fromCocoa: rect, primaryScreenHeight: primaryScreenHeight)
    }

    /// L'écran qui porte la fenêtre : celui qui contient son centre, sinon
    /// celui qui en recouvre la plus grande part. `nil` si aucun (fenêtre
    /// entièrement hors écran).
    public static func screenIndex(for windowFrame: CGRect, among screens: [CGRect]) -> Int? {
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        if let index = screens.firstIndex(where: { $0.contains(center) }) {
            return index
        }
        let overlaps = screens.map { screen -> CGFloat in
            let intersection = screen.intersection(windowFrame)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        guard let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }),
              overlaps[best] > 0 else { return nil }
        return best
    }
}

/// Le cadre visé par une action, dans la zone utile d'un écran (sans la
/// barre de menus ni le Dock), en coordonnées AX.
public enum WindowLayout {

    /// Fraction de l'écran occupée par `centerReduced`.
    public static let reducedScale: CGFloat = 0.6

    /// `nil` pour les actions qui ne sont pas un cadre (réduire, plein écran
    /// natif, fermer) : `WindowController` les traite à part.
    public static func frame(for action: GestureAction, in visible: CGRect) -> CGRect? {
        let halfWidth = visible.width / 2
        let halfHeight = visible.height / 2
        let left = visible.minX
        let right = visible.minX + halfWidth
        let top = visible.minY
        let bottom = visible.minY + halfHeight

        switch action {
        case .leftHalf:
            return CGRect(x: left, y: top, width: halfWidth, height: visible.height)
        case .rightHalf:
            return CGRect(x: right, y: top, width: halfWidth, height: visible.height)
        case .topHalf:
            return CGRect(x: left, y: top, width: visible.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: left, y: bottom, width: visible.width, height: halfHeight)
        case .topLeftQuarter:
            return CGRect(x: left, y: top, width: halfWidth, height: halfHeight)
        case .topRightQuarter:
            return CGRect(x: right, y: top, width: halfWidth, height: halfHeight)
        case .bottomLeftQuarter:
            return CGRect(x: left, y: bottom, width: halfWidth, height: halfHeight)
        case .bottomRightQuarter:
            return CGRect(x: right, y: bottom, width: halfWidth, height: halfHeight)
        case .maximize:
            return visible
        case .centerReduced:
            let width = visible.width * reducedScale
            let height = visible.height * reducedScale
            return CGRect(
                x: visible.midX - width / 2,
                y: visible.midY - height / 2,
                width: width,
                height: height
            )
        case .minimize, .toggleFullScreen, .close, .quitApp:
            return nil
        }
    }
}
