import Foundation

/// Une app lancée, réduite à ce qui permet de la reconnaître.
/// `GestureTarget` la remplit depuis `NSWorkspace.runningApplications`.
public struct RunningAppInfo: Equatable, Sendable {
    public var pid: Int32
    public var bundleURL: URL?
    public var bundleIdentifier: String?

    public init(pid: Int32, bundleURL: URL?, bundleIdentifier: String?) {
        self.pid = pid
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
    }
}

/// **Le curseur est-il sur l'icône d'une app qu'on peut quitter ?** La
/// décision, sans l'API qui la nourrit — le pendant de `TitlebarHitTest`
/// pour le Dock.
///
/// Le Dock est un processus comme un autre : AX renvoie ses éléments sous le
/// curseur. Les icônes y ont le rôle `AXDockItem` et un sous-rôle par
/// sorte (`AXApplicationDockItem`, `AXFolderDockItem`, `AXTrashDockItem`,
/// `AXMinimizedWindowDockItem`, `AXSeparatorDockItem` — relevés dans le
/// binaire de Swish, à confirmer au test manuel). Seules les icônes d'app
/// lancées sont des cibles.
public enum DockHitTest {

    public enum Verdict: Equatable, Sendable {
        case app(RunningAppInfo)
        /// Dossier, corbeille, fenêtre réduite, séparateur…
        case notAnAppItem(subrole: String?)
        /// Icône épinglée d'une app fermée, ou app lancée introuvable.
        case notRunning
        /// Notre propre processus : SwishClone n'a normalement pas d'icône
        /// (`.accessory`), mais bran en a une et embarque la même
        /// bibliothèque. Pincer sur l'icône de l'hôte ne doit jamais le
        /// quitter.
        case ownApp
        /// Une app que le Dock lui-même ne propose pas de quitter.
        case protectedApp(bundleIdentifier: String)
    }

    public static let protectedBundleIdentifiers: Set<String> = ["com.apple.finder"]

    /// - Parameters:
    ///   - item: l'élément `AXDockItem` sous le curseur.
    ///   - isRunning: l'attribut `AXIsApplicationRunning` de l'icône.
    ///   - itemURL: l'attribut `AXURL` de l'icône (le `.app`).
    ///   - itemBundleIdentifier: lu dans ce `.app`, si l'hôte a pu.
    public static func evaluate(
        item: AXNodeInfo,
        isRunning: Bool,
        itemURL: URL?,
        itemBundleIdentifier: String?,
        runningApps: [RunningAppInfo],
        ownPID: Int32
    ) -> Verdict {
        guard item.role == "AXDockItem", item.subrole == "AXApplicationDockItem" else {
            return .notAnAppItem(subrole: item.subrole)
        }
        guard isRunning,
              let app = runningApp(forItemURL: itemURL, bundleIdentifier: itemBundleIdentifier, among: runningApps)
        else {
            return .notRunning
        }
        guard app.pid != ownPID else {
            return .ownApp
        }
        if let identifier = app.bundleIdentifier, protectedBundleIdentifiers.contains(identifier) {
            return .protectedApp(bundleIdentifier: identifier)
        }
        return .app(app)
    }

    /// L'app lancée que désigne une icône.
    ///
    /// **Par l'URL d'abord** : c'est la seule clé qui distingue deux copies
    /// d'une même app à deux endroits, et qui marche pour une app sans
    /// identifiant. **Par l'identifiant ensuite**, parce que les chemins ne
    /// concordent pas toujours (`/Applications/TextEdit.app` dans un cas,
    /// `/System/Applications/TextEdit.app` dans l'autre).
    ///
    /// **Jamais au hasard** : plusieurs candidates pour la même clé, et
    /// c'est `nil`. Quitter est irréversible ; ne rien faire ne l'est pas.
    public static func runningApp(
        forItemURL url: URL?,
        bundleIdentifier: String?,
        among apps: [RunningAppInfo]
    ) -> RunningAppInfo? {
        if let url {
            let path = url.standardizedFileURL.path
            let byURL = apps.filter { $0.bundleURL?.standardizedFileURL.path == path }
            if byURL.count == 1 { return byURL[0] }
            if byURL.count > 1 { return nil }
        }
        if let bundleIdentifier {
            let byIdentifier = apps.filter { $0.bundleIdentifier == bundleIdentifier }
            if byIdentifier.count == 1 { return byIdentifier[0] }
        }
        return nil
    }
}
