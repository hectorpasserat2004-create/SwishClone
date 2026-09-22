import AppKit

/// Restreint le déclenchement d'une action de geste à une fine bande en
/// haut de l'écran (mode "Menubar" façon Swish) : un geste reste toujours
/// détecté et loggé où que soit le curseur, mais ne doit produire
/// d'action sur une fenêtre que si le curseur est dans cette bande au
/// moment où le geste se termine.
enum GestureZone {

    /// `true` si le curseur est actuellement dans les `height` premiers
    /// pixels en haut de l'écran qui le contient.
    ///
    /// `NSEvent.mouseLocation` est en coordonnées AppKit (origine en bas à
    /// gauche de l'écran, y croissant vers le haut) — "en haut de l'écran"
    /// correspond donc à un y PROCHE DU MAXIMUM de la hauteur de cet
    /// écran, pas proche de 0.
    ///
    /// `NSScreen.screens` (pas seulement `.main`) pour gérer plusieurs
    /// moniteurs : chaque `frame` est déjà exprimé dans le même espace de
    /// coordonnées global, donc `frame.maxY` donne le bord haut du bon
    /// écran même s'il n'est pas positionné à l'origine.
    static func isCursorInTopBand(height: CGFloat = 40) -> Bool {
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else {
            return false
        }
        return (screen.frame.maxY - location.y) <= height
    }
}
