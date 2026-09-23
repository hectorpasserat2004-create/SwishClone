import CoreGraphics

/// Ce que l'API Accessibility dit d'un élément, réduit à ce dont la décision
/// a besoin. Les chaînes sont celles d'AX (`"AXToolbar"`,
/// `"AXStandardWindow"`…), recopiées ici pour que la décision reste testable
/// sans AppKit.
public struct AXNodeInfo: Equatable, Sendable {
    public var role: String?
    public var subrole: String?

    public init(role: String?, subrole: String? = nil) {
        self.role = role
        self.subrole = subrole
    }
}

/// **Le curseur est-il sur une barre de titre ?** La décision, sans l'API
/// qui la nourrit.
///
/// `GestureTarget` (SwishGestures) interroge AX : l'élément sous le curseur,
/// puis ses parents jusqu'à la fenêtre. Il passe ce chemin ici, et c'est
/// ici que se décide si un geste à cet endroit est pour nous ou pour l'app.
///
/// Trois règles, dans cet ordre :
///
/// 1. **Seules les vraies fenêtres** : standard ou dialogue (ou sans
///    sous-rôle, que certaines apps ne renseignent pas). Pas les panneaux
///    flottants ni les fenêtres système — Swish exclut de même popovers et
///    images incrustées.
/// 2. **Jamais sur ce qui défile ou se saisit** : zone de défilement, champ
///    texte, curseur, contenu web… n'importe où dans le chemin. Un swipe sur
///    la barre d'adresse de Safari ou sur la barre d'onglets défilante de
///    Firefox reste à l'app. C'est la règle qui compte le plus une fois les
///    événements avalés : se tromper ici, c'est voler un scroll.
/// 3. **Barre de titre** si le chemin passe par une barre d'outils (qui peut
///    être plus haute que la zone réglée — Finder, Mail), ou, à défaut, si le
///    curseur est dans les `zoneHeight` premiers points de la fenêtre. Ce
///    repli couvre les barres de titre dessinées à la main (Chrome,
///    applications Electron), qu'AX décrit comme de simples groupes.
public enum TitlebarHitTest {

    public enum Verdict: Equatable, Sendable {
        case titlebar
        case unsupportedWindow(subrole: String?)
        case excludedElement(role: String)
        case outsideZone
    }

    static let acceptedWindowSubroles: Set<String?> = [nil, "AXStandardWindow", "AXDialog"]

    static let excludedRoles: Set<String> = [
        "AXScrollArea", "AXScrollBar", "AXSlider", "AXIncrementor",
        "AXTextField", "AXTextArea", "AXComboBox",
        "AXWebArea", "AXPopover",
        "AXTable", "AXOutline", "AXList", "AXBrowser",
    ]

    /// - Parameters:
    ///   - path: de l'élément sous le curseur jusqu'à l'enfant direct de la
    ///     fenêtre. Vide si l'élément touché est la fenêtre elle-même.
    ///   - windowFrame: en coordonnées AX (origine en haut à gauche).
    ///   - point: le curseur, dans les mêmes coordonnées.
    public static func evaluate(
        path: [AXNodeInfo],
        window: AXNodeInfo,
        windowFrame: CGRect,
        point: CGPoint,
        zoneHeight: Double
    ) -> Verdict {
        guard acceptedWindowSubroles.contains(window.subrole) else {
            return .unsupportedWindow(subrole: window.subrole)
        }

        if let excluded = path.compactMap(\.role).first(where: excludedRoles.contains) {
            return .excludedElement(role: excluded)
        }

        if path.contains(where: { $0.role == "AXToolbar" }) {
            return .titlebar
        }

        let isWithinWidth = point.x >= windowFrame.minX && point.x <= windowFrame.maxX
        // Origine en haut : le haut de la fenêtre est `minY`.
        let isWithinBand = point.y >= windowFrame.minY && point.y <= windowFrame.minY + zoneHeight
        return isWithinWidth && isWithinBand ? .titlebar : .outsideZone
    }
}
