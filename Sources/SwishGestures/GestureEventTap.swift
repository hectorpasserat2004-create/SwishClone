import Cocoa
import CoreGraphics
import SwishCloneCore

/// **Un seul event tap pour le swipe et le pincement, branché sur
/// `GestureStateMachine`.**
///
/// ```
///   tap (scrollWheel + type 29) ──▶ Event ──▶ machine.handle ──▶ effets ──▶ WindowController.perform
///                                              │
///   timer à machine.nextDeadline ──▶ .tick ────┤
///   tap clavier (Échap, actif pendant un geste) ──▶ .escape
/// ```
///
/// Remplace les deux moniteurs de la Phase 5 : `GlobalGestureMonitor`
/// (`NSEvent`, swipe) et `EventTapGestureMonitor` (tap, pincement). Réunis,
/// ils passent par la même machine — déclenchement au lever, enchaînement,
/// annulation — et, à l'étape 5, par le même tap actif, puisqu'un moniteur
/// `NSEvent` ne peut rien bloquer.
///
/// **En écoute seule pour l'instant** (`.listenOnly`) : rien n'est avalé,
/// quoi que dise la machine. Le callback renvoie déjà sa décision, pour que
/// l'étape 5 n'ait qu'à changer l'option du tap.
///
/// Sur le thread principal, comme avant. L'étape 5 le déplacera sur un
/// thread à lui avant d'activer le blocage : en écoute seule, une latence
/// ici ne retarde que nous.
@MainActor
enum GestureEventTap {

    // MARK: - Décodage du type 29 (Phase 5)
    //
    // ⚠️ **Technique non documentée officiellement par Apple**, décodée
    // empiriquement en Phase 5 à partir de gestes isolés et annoncés :
    //
    // - Les gestes multi-touch remontent sous `CGEventType.rawValue == 29`
    //   (`kCGEventGesture` en interne), absent de l'enum publique.
    // - Le champ **110** discrimine le sous-type : `8` = magnification
    //   (pinch), `6` = swipe/pan.
    // - Le champ **113** porte la magnitude **cumulative** depuis le début
    //   du pincement, lue par `getDoubleValueField` (la lecture validée sur
    //   un vrai pinch out) : positive en écartant, négative en resserrant.
    //
    // Rien de tout ça n'est garanti stable d'une version de macOS à l'autre.

    /// `nonisolated` : lu depuis les callbacks C, hors de l'acteur.
    nonisolated fileprivate static let gestureEventTypeRawValue: UInt32 = 29
    private static let subtypeFieldRawValue: UInt32 = 110
    private static let magnifySubtype: Int64 = 8
    private static let magnitudeFieldRawValue: UInt32 = 113
    nonisolated fileprivate static let escapeKeyCode: Int64 = 53

    // MARK: - État

    private static var machine = GestureStateMachine()
    /// La fenêtre visée par le geste en cours, trouvée par `isOnTarget` au
    /// début du geste et utilisée au lever.
    private static var target: GestureTarget.Target?

    private static var deadlineTimer: Timer?
    private static var scheduledDeadline: TimeInterval?

    private static var gestureTap: CFMachPort?
    private static var gestureSource: CFRunLoopSource?
    private static var keyTap: CFMachPort?
    private static var keySource: CFRunLoopSource?

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: - Démarrage

    /// `false` si l'un des deux taps n'a pas pu être créé. La permission
    /// Accessibility est vérifiée en amont par `GestureMonitor.start()`.
    static func start() -> Bool {
        let gestureMask = (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
            | (CGEventMask(1) << CGEventMask(gestureEventTypeRawValue))

        guard let tap = createTap(mask: gestureMask, callback: gestureTapCallback) else {
            print("""
            [GestureEventTap] ⚠️ CGEventTapCreate a retourné nil — le tap \
            ne s'est PAS créé. Causes possibles, dans l'ordre le plus probable :
              1. Permission Accessibility accordée pour un build précédent mais \
                 pas pour celui-ci : `swift run` change le chemin du binaire à \
                 chaque recompilation, macOS peut redemander l'autorisation.
              2. Permission "Contrôle de l'entrée" (Input Monitoring) manquante — \
                 distincte d'Accessibility depuis macOS 10.15, potentiellement \
                 nécessaire pour un tap en écoute seule. À vérifier dans \
                 Réglages Système > Confidentialité et sécurité > Contrôle de \
                 l'entrée (Input Monitoring), en plus d'Accessibilité.
              3. Restriction liée à un exécutable non signé/notarisé en dehors \
                 d'un vrai bundle .app.
            """)
            return false
        }

        // Échap : un tap à part, **éteint hors d'un geste**. Le mettre dans le
        // tap principal ferait passer chaque frappe du système par ici.
        let keyMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let key = createTap(mask: keyMask, callback: keyTapCallback) else {
            print("[GestureEventTap] ⚠️ le tap clavier (Échap) ne s'est pas créé — abandon.")
            CGEvent.tapEnable(tap: tap, enable: false)
            return false
        }

        gestureTap = tap
        gestureSource = install(tap)
        keyTap = key
        keySource = install(key)
        CGEvent.tapEnable(tap: tap, enable: true)
        CGEvent.tapEnable(tap: key, enable: false)

        machine = GestureStateMachine(configuration: GestureSettings.shared.machineConfiguration)
        target = nil
        print("[GestureEventTap] tap démarré (écoute seule) — swipe et pincement, action au lever")
        return true
    }

    static func stop() {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        scheduledDeadline = nil
        _ = machine.reset()
        target = nil

        for (tap, source) in [(gestureTap, gestureSource), (keyTap, keySource)] {
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        }
        gestureTap = nil
        gestureSource = nil
        keyTap = nil
        keySource = nil
    }

    private static func createTap(mask: CGEventMask, callback: CGEventTapCallBack) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        )
    }

    private static func install(_ tap: CFMachPort) -> CFRunLoopSource? {
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return source
    }

    // MARK: - Événements

    /// Rend la décision de la machine : avaler ou laisser passer. Ignorée
    /// tant que le tap est en écoute seule.
    fileprivate static func handle(type: CGEventType, event: CGEvent) -> GestureStateMachine.Disposition {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            recoverFromDisabledTap(type)
            return .pass

        case .scrollWheel:
            guard let scroll = NSEvent(cgEvent: event) else { return .pass }
            logScroll(scroll, event)
            return process(
                .scroll(
                    phase: phase(scroll.phase),
                    momentum: phase(scroll.momentumPhase),
                    dx: Double(scroll.deltaX),
                    dy: Double(scroll.deltaY)
                ),
                at: event.location
            )

        default:
            guard type.rawValue == gestureEventTypeRawValue else { return .pass }
            return handleGestureEvent(event)
        }
    }

    private static func handleGestureEvent(_ event: CGEvent) -> GestureStateMachine.Disposition {
        let subtypeField = unsafeBitCast(subtypeFieldRawValue, to: CGEventField.self)
        guard event.getIntegerValueField(subtypeField) == magnifySubtype else { return .pass }

        let magnitudeField = unsafeBitCast(magnitudeFieldRawValue, to: CGEventField.self)

        // DEBUG TEMPORAIRE : magnitude toujours à 0.0 en aval de la
        // classification. On compare ici les deux lectures possibles du
        // même champ, event par event, pour savoir laquelle est en cause
        // AVANT le stockage — plutôt que de deviner.
        let rawInt = event.getIntegerValueField(magnitudeField)
        let bitcastFloat = Float(bitPattern: UInt32(truncatingIfNeeded: rawInt))
        let viaDoubleField = event.getDoubleValueField(magnitudeField)
        print("[GestureEventTap] magnify event : rawInt=\(rawInt) "
            + "bitcastFloat32=\(bitcastFloat) getDoubleValueField=\(viaDoubleField)")

        // Diagnostic pour le P1 (pincer deux fois) : la machine ne peut
        // enchaîner des étapes de pincement que si l'événement porte une
        // phase. On relève ce que `NSEvent` en dit, sans encore s'en servir
        // — la fin du pincement reste détectée par le silence de 150 ms.
        if GestureClassifier.debugLoggingEnabled, let ns = NSEvent(cgEvent: event) {
            print("[GestureEventTap] magnify NSEvent : type=\(ns.type.rawValue) phase=\(ns.phase.rawValue)")
        }

        return process(.magnify(cumulative: viaDoubleField, phase: nil), at: event.location)
    }

    fileprivate static func handleKey(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Le tap clavier est éteint hors geste : on ne le rallume que si
            // un geste est en cours.
            if let keyTap, machine.isTracking { CGEvent.tapEnable(tap: keyTap, enable: true) }
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventKeycode) == escapeKeyCode else { return }
            _ = process(.escape, at: event.location)
        default:
            break
        }
    }

    // MARK: - La machine

    private static func process(_ event: GestureStateMachine.Event, at location: CGPoint) -> GestureStateMachine.Disposition {
        // Relus à chaque événement, comme avant : un curseur déplacé dans les
        // préférences s'applique au geste suivant.
        machine.configuration = GestureSettings.shared.machineConfiguration
        let zoneHeight = GestureSettings.shared.gestureZoneHeight

        let output = machine.handle(event, at: now) {
            target = GestureTarget.hitTest(at: location, zoneHeight: zoneHeight)
            return target != nil
        }
        apply(output.effects)
        synchronize()
        return output.disposition
    }

    private static func tick() {
        scheduledDeadline = nil
        deadlineTimer = nil
        if let summary = machine.debugSummary(at: now) { debugLog("tick : \(summary)") }
        let output = machine.handle(.tick, at: now) { false }
        apply(output.effects)
        synchronize()
    }

    private static func apply(_ effects: [GestureStateMachine.Effect]) {
        for effect in effects {
            switch effect {
            case let .commit(action):
                guard let target else { continue }
                debugLog("lever : \(action)")
                WindowController.perform(action, on: target.window)
            case let .showPreview(preview):
                // Étape 4 : le panneau d'aperçu.
                debugLog("aperçu : \(preview)")
            case .hidePreview:
                debugLog("aperçu masqué")
            case let .haptic(haptic):
                // Étape 4 : le retour haptique.
                debugLog("haptique : \(haptic)")
            case let .cancelled(reason):
                switch reason {
                case .stillness: debugLog("geste annulé (immobilité)")
                case .escape: debugLog("geste annulé (Échap)")
                case .interrupted: debugLog("geste annulé (interrompu par le système)")
                }
            }
        }
    }

    /// Aligne le timer et le tap clavier sur l'état de la machine.
    ///
    /// Le timer n'est reprogrammé que si l'échéance **avance** : pendant un
    /// swipe, chaque événement la repousse, et recréer un timer cent fois par
    /// seconde ne servirait à rien. Un timer qui se réveille trop tôt envoie
    /// un `.tick` sans effet, puis se reprogramme sur la nouvelle échéance.
    private static func synchronize() {
        if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: machine.isTracking) }

        guard let deadline = machine.nextDeadline else {
            deadlineTimer?.invalidate()
            deadlineTimer = nil
            scheduledDeadline = nil
            return
        }
        if let scheduledDeadline, scheduledDeadline <= deadline { return }

        deadlineTimer?.invalidate()
        let timer = Timer(timeInterval: max(0, deadline - now), repeats: false) { _ in
            // Ajouté à la run loop principale ci-dessous.
            MainActor.assumeIsolated { tick() }
        }
        // `.common` : sans ça, le timer ne se déclencherait pas pendant qu'un
        // menu est ouvert — et le pincement ne finirait jamais.
        RunLoop.main.add(timer, forMode: .common)
        deadlineTimer = timer
        scheduledDeadline = deadline
    }

    /// macOS coupe un tap dont le callback tarde, ou sur certaines saisies.
    /// Un tap coupé reste mort **sans rien dire** : il faut le rallumer. Des
    /// événements ont été perdus entre-temps, donc le geste en cours n'a plus
    /// de fin fiable — on l'abandonne.
    private static func recoverFromDisabledTap(_ type: CGEventType) {
        print("[GestureEventTap] ⚠️ tap coupé par macOS (\(type == .tapDisabledByTimeout ? "délai" : "saisie")) — réactivé, geste en cours abandonné")
        if let gestureTap { CGEvent.tapEnable(tap: gestureTap, enable: true) }
        apply(machine.reset())
        target = nil
        synchronize()
    }

    /// `NSEvent.Phase` est un ensemble d'options ; un événement n'en porte
    /// qu'une. `stationary` (doigts posés, immobiles) devient un `changed`
    /// sans déplacement, que la machine ne compte pas comme un mouvement.
    private static func phase(_ phase: NSEvent.Phase) -> GestureStateMachine.Phase? {
        if phase.contains(.mayBegin) { return .mayBegin }
        if phase.contains(.began) { return .began }
        if phase.contains(.changed) || phase.contains(.stationary) { return .changed }
        if phase.contains(.ended) { return .ended }
        if phase.contains(.cancelled) { return .cancelled }
        return nil
    }

    /// Diagnostic du point 1 (enchaînement intermittent) : pour chaque
    /// événement de scroll pendant un geste suivi, les deltas que la machine
    /// reçoit (`NSEvent.deltaX/Y`), les deltas « précis »
    /// (`scrollingDeltaX/Y`) et les champs bruts du CGEvent — pour savoir si
    /// macOS écrase l'axe perpendiculaire après une première direction
    /// (verrouillage d'axe), et à quel niveau.
    private static func logScroll(_ scroll: NSEvent, _ event: CGEvent) {
        guard GestureClassifier.debugLoggingEnabled,
              machine.isTracking || scroll.phase.contains(.began) else { return }
        let rawVertical = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let rawHorizontal = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        print(String(
            format: "[GestureEventTap] scroll phase=%lu momentum=%lu delta=(%.2f, %.2f) scrollingDelta=(%.2f, %.2f) brut(h, v)=(%.1f, %.1f) | %@",
            scroll.phase.rawValue, scroll.momentumPhase.rawValue,
            scroll.deltaX, scroll.deltaY,
            scroll.scrollingDeltaX, scroll.scrollingDeltaY,
            rawHorizontal, rawVertical,
            machine.debugSummary(at: now) ?? "pas de geste suivi"
        ))
    }

    private static func debugLog(_ message: @autoclosure () -> String) {
        if GestureClassifier.debugLoggingEnabled {
            print("[GestureEventTap] \(message())")
        }
    }
}

// MARK: - Callbacks C

/// Fonctions top-level plutôt que closures littérales : un
/// `CGEventTapCallBack` doit pouvoir se former en pointeur de fonction C,
/// ce que le compilateur refuse pour une closure qui référence un autre
/// membre `static` du type englobant.
///
/// Les sources des deux taps sont sur la run loop principale : ces callbacks
/// y sont donc toujours appelés.
private func gestureTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let disposition = MainActor.assumeIsolated { GestureEventTap.handle(type: type, event: event) }
    // Sans effet en écoute seule ; à l'étape 5, `nil` avalera l'événement.
    return disposition == .swallow ? nil : Unmanaged.passUnretained(event)
}

private func keyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    MainActor.assumeIsolated { GestureEventTap.handleKey(type: type, event: event) }
    return Unmanaged.passUnretained(event)
}
