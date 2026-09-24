/// Ce qu'un geste terminé demande de faire à la fenêtre visée.
///
/// Décrit l'intention, pas la géométrie : c'est `WindowController`, côté
/// SwishGestures, qui la traduit en coordonnées d'écran. La machine à états
/// et l'aperçu n'ont besoin que de savoir *quoi* montrer et *quoi* appliquer.
public enum WindowAction: Equatable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf

    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter

    /// Remplir l'écran, en restant sur le même bureau.
    case maximize
    case minimize
    /// Le plein écran natif (bouton vert, bureau à part).
    case toggleFullScreen
    /// Le bouton rouge, comme un clic : l'app garde la main (un document non
    /// enregistré ouvre sa feuille de dialogue, rien n'est perdu).
    case close
    /// Fenêtre recentrée à 60 %. Plus associée à aucun geste depuis que le
    /// pincement ferme la fenêtre ; réservée au double tap (P1).
    case centerReduced
}
