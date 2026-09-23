import AppKit

/// Restreint le déclenchement d'une action de geste à la barre de titre de
/// la fenêtre active (mode "Windows" façon Swish) : un geste reste
/// toujours détecté et loggé où que soit le curseur, mais ne doit produire
/// d'action que si le curseur est sur la barre de titre de la fenêtre au
/// premier plan au moment où le geste se termine. Aucune fenêtre overlay
/// n'est nécessaire — c'est un simple test géométrique.
@MainActor
enum GestureZone {

    /// `true` si le curseur est dans la largeur de la fenêtre active et
    /// dans les `height` premiers pixels en partant du haut de CETTE
    /// fenêtre. `false` si aucune fenêtre valide n'est trouvée, ou si la
    /// fenêtre active est la nôtre.
    ///
    /// Conversion de coordonnées : l'Accessibility API (position AX) a son
    /// origine en HAUT à gauche de l'écran principal, y croissant vers le
    /// bas ; `NSEvent.mouseLocation` est en coordonnées Cocoa (origine en
    /// BAS à gauche, y croissant vers le haut). Même formule que celle
    /// validée dans `TitlebarTrackingPanel` :
    /// `cocoaY = hauteurÉcran - axY`. La hauteur de référence est celle de
    /// l'écran PRIMAIRE (`NSScreen.screens.first`, celui qui porte la barre
    /// de menus, ancre de l'espace AX) et non `NSScreen.main`, qui désigne
    /// l'écran de la fenêtre clé et peut différer en multi-moniteurs.
    ///
    /// `height` optionnel plutôt qu'un défaut lu dans `GestureSettings` :
    /// un argument par défaut est évalué hors de l'acteur principal.
    static func isCursorInActiveWindowTitlebar(height: CGFloat? = nil) -> Bool {
        let height = height ?? CGFloat(GestureSettings.shared.gestureZoneHeight)

        // `getFrontmostWindow()` n'exclut pas notre propre app (seul
        // `handleGesture` le fait) : on l'exclut ici explicitement.
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        guard frontmostApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return false
        }

        guard let window = WindowController.getFrontmostWindow(),
              let position = WindowController.position(of: window),
              let size = WindowController.size(of: window),
              let primaryScreenHeight = NSScreen.screens.first?.frame.height else {
            return false
        }

        let cocoaTop = primaryScreenHeight - position.y
        let cursor = NSEvent.mouseLocation

        let isWithinWidth = cursor.x >= position.x && cursor.x <= position.x + size.width
        let isWithinTitlebarBand = cursor.y <= cocoaTop && cursor.y >= cocoaTop - height
        return isWithinWidth && isWithinTitlebarBand
    }
}
