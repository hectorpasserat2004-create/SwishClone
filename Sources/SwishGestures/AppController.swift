import AppKit
import SwishCloneCore

/// Les actions sur une app entière — pour l'instant, la quitter depuis son
/// icône du Dock.
public enum AppController {

    /// Quitte l'app comme ⌘Q ou « Quitter » dans le menu de son icône :
    /// `terminate()`, **jamais** `forceTerminate()`. L'app garde la main —
    /// elle peut demander d'enregistrer, ou refuser.
    ///
    /// **Second garde-fou.** `DockHitTest` a déjà écarté notre propre
    /// processus et les apps protégées au début du geste ; on le revérifie
    /// ici, juste avant l'action irréversible, pour qu'elle ne dépende
    /// jamais d'un seul contrôle.
    @MainActor
    public static func quit(pid: pid_t) {
        guard pid != ProcessInfo.processInfo.processIdentifier else {
            debugLog("quitter refusé : c'est notre propre processus")
            return
        }
        guard let app = NSRunningApplication(processIdentifier: pid), app.isTerminated == false else {
            debugLog("quitter : l'app (pid \(pid)) n'est plus lancée")
            return
        }
        if let identifier = app.bundleIdentifier, DockHitTest.protectedBundleIdentifiers.contains(identifier) {
            debugLog("quitter refusé : \(identifier) est protégée")
            return
        }
        let accepted = app.terminate()
        debugLog("quitter \(app.localizedName ?? "pid \(pid)") : " + (accepted ? "demande envoyée" : "demande refusée par macOS"))
    }

    private static func debugLog(_ message: @autoclosure () -> String) {
        if GestureClassifier.debugLoggingEnabled {
            print("[AppController] \(message())")
        }
    }
}
