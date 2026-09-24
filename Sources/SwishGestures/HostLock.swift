import Foundation

/// **Un seul hôte de détection à la fois, par session utilisateur.**
///
/// SwishClone et bran embarquent la même bibliothèque : lancés ensemble,
/// deux taps suivent le même geste et agissent chacun sur la même fenêtre.
/// Une fois le tap actif, ce serait pire qu'un doublon : deux hôtes qui
/// avalent les mêmes événements. Le second à démarrer doit donc refuser, et
/// le dire.
///
/// Un verrou `flock` sur un fichier : le système le libère à la mort du
/// processus, plantage compris — pas de verrou périmé à nettoyer. Le fichier
/// porte le pid et le nom du détenteur, pour que le refus dise QUI tient la
/// détection.
///
/// Deux `HostLock` du même chemin se gênent, même dans un seul processus :
/// c'est ce qui rend la garde testable.
final class HostLock {

    struct Holder: Equatable {
        var processID: Int32?
        var name: String?
    }

    enum Failure: Error, Equatable {
        case heldElsewhere(Holder)
    }

    static var defaultPath: String {
        // `NSTemporaryDirectory()` est propre à l'utilisateur : deux
        // sessions ouvertes en même temps ne se gênent pas.
        (NSTemporaryDirectory() as NSString).appendingPathComponent("com.swishclone.gesture-host.lock")
    }

    private let path: String
    private var descriptor: Int32 = -1

    init(path: String = HostLock.defaultPath) {
        self.path = path
    }

    var isHeld: Bool { descriptor >= 0 }

    /// Lève `Failure.heldElsewhere` si un autre hôte tient déjà le verrou.
    /// **Si le fichier de verrou lui-même est inutilisable** (disque,
    /// permissions), on laisse démarrer : une garde ne doit pas empêcher un
    /// usage normal pour une raison sans rapport, et un avertissement part
    /// dans la console.
    func acquire() throws {
        guard descriptor < 0 else { return }

        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            print("[HostLock] ⚠️ verrou inutilisable (\(String(cString: strerror(errno)))) — garde désactivée")
            return
        }

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let holder = Self.readHolder(from: fd)
            close(fd)
            throw Failure.heldElsewhere(holder)
        }

        descriptor = fd
        let identity = "\(getpid())\n\(ProcessInfo.processInfo.processName)\n"
        ftruncate(fd, 0)
        _ = identity.withCString { pwrite(fd, $0, strlen($0), 0) }
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit { release() }

    private static func readHolder(from fd: Int32) -> Holder {
        var buffer = [UInt8](repeating: 0, count: 256)
        let count = pread(fd, &buffer, buffer.count - 1, 0)
        guard count > 0 else { return Holder() }
        let lines = String(decoding: buffer.prefix(count), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
        return Holder(
            processID: lines.first.flatMap { Int32($0) },
            name: lines.count > 1 ? String(lines[1]) : nil
        )
    }
}
