import Foundation
import os

/// **Un thread à nous, avec sa propre run loop.**
///
/// Un `CGEventTap` est une source de run loop : son callback s'exécute sur
/// le thread de la run loop qui la porte. Pour que le callback ne touche
/// jamais le thread principal (un menu ouvert, une animation, une alerte y
/// retarderaient chaque événement du système, une fois le tap actif), le tap
/// vit ici.
///
/// Séparé de `GestureTapRunner` pour se tester sans permission ni tap.
final class EventLoopThread: @unchecked Sendable {

    private let name: String
    private var thread: Thread?
    private let runLoop = OSAllocatedUnfairLock<CFRunLoop?>(initialState: nil)
    private let shouldStop = OSAllocatedUnfairLock(initialState: false)
    private let ready = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    /// Écrit par le thread avant `ready.signal()`, lu après `ready.wait()` :
    /// le sémaphore garantit l'ordre.
    private var setUpSucceeded = false

    init(name: String) {
        self.name = name
    }

    var isCurrent: Bool {
        thread != nil && Thread.current === thread
    }

    /// Démarre le thread et exécute `setUp` DESSUS ; rend son résultat. Bloque
    /// l'appelant le temps de l'installation, pour qu'un échec (un tap qui ne
    /// se crée pas) se rapporte tout de suite. Sur échec, le thread se
    /// termine.
    @discardableResult
    func start(setUp: @escaping () -> Bool) -> Bool {
        guard thread == nil else { return false }
        let thread = Thread { [self] in run(setUp) }
        thread.name = name
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()

        ready.wait()
        if setUpSucceeded == false {
            finished.wait()
            self.thread = nil
        }
        return setUpSucceeded
    }

    private func run(_ setUp: () -> Bool) {
        runLoop.withLock { $0 = CFRunLoopGetCurrent() }
        // Sans rien à surveiller, `CFRunLoopRunInMode` reviendrait tout de
        // suite : ce port garde la boucle en vie.
        RunLoop.current.add(NSMachPort(), forMode: .default)

        setUpSucceeded = setUp()
        ready.signal()

        if setUpSucceeded {
            while shouldStop.withLock({ $0 }) == false {
                CFRunLoopRunInMode(.defaultMode, 3600, false)
            }
        }
        runLoop.withLock { $0 = nil }
        finished.signal()
    }

    /// Exécute `block` sur le thread, à la suite de ce qui y tourne déjà.
    /// Sans effet une fois le thread arrêté.
    func async(_ block: @escaping () -> Void) {
        guard let loop = runLoop.withLock({ $0 }) else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(loop)
    }

    /// Exécute `tearDown` sur le thread (c'est là que les taps et les timers
    /// doivent être défaits), arrête la boucle, et attend la fin du thread.
    /// Sans effet si le thread n'est pas démarré.
    func stop(tearDown: @escaping () -> Void = {}) {
        guard thread != nil else { return }
        async { [self] in
            tearDown()
            shouldStop.withLock { $0 = true }
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        finished.wait()
        thread = nil
    }
}
