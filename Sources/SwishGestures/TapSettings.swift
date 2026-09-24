import Foundation
import os
import SwishCloneCore

/// **Les réglages dont le tap a besoin, figés en une valeur.**
///
/// Le callback du tap tourne sur son propre thread : il ne doit jamais lire
/// `GestureSettings` (un `ObservableObject` du thread principal, dont les
/// `@Published` ne se lisent pas hors de lui). Il lit une copie de cette
/// struct, republiée par le thread principal à chaque changement de réglage.
struct TapSettings: Equatable, Sendable {
    var machine = GestureStateMachine.Configuration()
    var zoneHeight: Double = 40
    var previewEnabled = true
    var hapticsEnabled = true
}

extension GestureSettings {
    var tapSettings: TapSettings {
        TapSettings(
            machine: machineConfiguration,
            zoneHeight: gestureZoneHeight,
            previewEnabled: previewEnabled,
            hapticsEnabled: hapticsEnabled
        )
    }
}

/// Une copie verrouillée de `TapSettings`. Un verrou plutôt qu'une file :
/// le callback ne peut pas attendre, et une lecture est une copie de
/// quelques octets — une struct entière ou rien, jamais deux moitiés de deux
/// écritures.
final class TapSettingsStore: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<TapSettings>

    init(_ initial: TapSettings = TapSettings()) {
        lock = OSAllocatedUnfairLock(initialState: initial)
    }

    func read() -> TapSettings {
        lock.withLock { $0 }
    }

    func write(_ settings: TapSettings) {
        lock.withLock { $0 = settings }
    }
}
