import Combine
import Cocoa
import CoreGraphics
import SwishCloneCore

/// **Un seul event tap pour le swipe et le pincement, sur un thread à lui,
/// branché sur `GestureStateMachine`.**
///
/// ```
///  thread du tap (GestureTapRunner)                          thread principal
///  ───────────────────────────────                          ────────────────
///  tap (scrollWheel + type 29) ─▶ Event ─▶ GestureTapEngine ─▶ Delivery ─▶ file FIFO ─▶ aperçu, haptique,
///  timer à nextDeadline ────────▶ .tick ──┘        │                                    action sur la fenêtre
///  tap clavier (Échap, actif pendant un geste) ────┘
///           ▲ réglages : copie verrouillée (TapSettingsStore), republiée par le thread principal
/// ```
///
/// **En écoute seule pour l'instant** (`.listenOnly`) : rien n'est avalé,
/// quoi que dise la machine. Le callback renvoie déjà sa décision, pour que
/// l'étape 5b n'ait qu'à changer l'option du tap.
@MainActor
enum GestureEventTap {

    private static var runner: GestureTapRunner?
    private static var settingsSubscription: AnyCancellable?

    /// `false` si l'un des deux taps n'a pas pu être créé. La permission
    /// Accessibility est vérifiée en amont par `GestureMonitor.start()`.
    static func start() -> Bool {
        let store = TapSettingsStore(GestureSettings.shared.tapSettings)
        let runner = GestureTapRunner(settings: store)
        guard runner.start() else { return false }

        self.runner = runner
        // `objectWillChange` part AVANT le changement : la relecture est
        // repoussée d'un tour de la file principale, pour voir la nouvelle
        // valeur.
        settingsSubscription = GestureSettings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { _ in store.write(GestureSettings.shared.tapSettings) }
        return true
    }

    static func stop() {
        settingsSubscription = nil
        runner?.stop()
        runner = nil
        // Après les livraisons déjà en file (FIFO) : sinon un aperçu en
        // attente s'afficherait après l'arrêt.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { GesturePreviewPanel.hide() }
        }
    }
}

// MARK: - Le thread du tap

/// Tout ce qui suit s'exécute sur le thread du tap, sauf `start()` et
/// `stop()`, qui l'appellent depuis le thread principal.
final class GestureTapRunner: @unchecked Sendable {

    // MARK: Décodage du type 29 (Phase 5)
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

    fileprivate static let gestureEventTypeRawValue: UInt32 = 29
    private static let subtypeFieldRawValue: UInt32 = 110
    private static let magnifySubtype: Int64 = 8
    private static let magnitudeFieldRawValue: UInt32 = 113
    private static let escapeKeyCode: Int64 = 53

    /// Au-delà, un callback se remarque : une fois le tap actif, il
    /// retiendrait le défilement du système d'autant.
    private static let slowCallbackNanoseconds: UInt64 = 5_000_000

    /// Les diagnostics de latence — callback lent et son détail par étape,
    /// test de cible lent, bilan par étape à l'arrêt — ne s'impriment que
    /// sur demande : `SWISHCLONE_TRACE=1 swift run`. En usage normal, un
    /// test de cible à froid (30 à 70 ms sur une app jamais touchée depuis
    /// un moment) est sans conséquence en écoute seule et ne mérite pas la
    /// console. Ce qui est anormal (tap coupé par macOS) s'imprime toujours.
    /// Lu une fois : la mesure elle-même (quelques dizaines de ns par
    /// étape) reste toujours active, seule son impression est conditionnée.
    static let traceEnabled = ProcessInfo.processInfo.environment["SWISHCLONE_TRACE"] == "1"

    private let loop = EventLoopThread(name: "SwishClone.gesture-tap")
    private let engine: GestureTapEngine

    // Touchés uniquement depuis le thread du tap.
    private var gestureTap: CFMachPort?
    private var gestureSource: CFRunLoopSource?
    private var keyTap: CFMachPort?
    private var keySource: CFRunLoopSource?
    private var deadlineTimer: Timer?
    private var scheduledDeadline: TimeInterval?
    private var metrics = CallbackMetrics()
    private let trace = TraceRecorder()

    /// Où l'on en est du tap clavier, pour ne l'allumer et l'éteindre qu'aux
    /// changements d'état.
    private var keySwitch = KeyTapSwitch()
    /// `CGEvent.tapEnable` est un aller-retour vers le serveur de fenêtres :
    /// mesuré hors app sous charge, allumer un tap dépasse 1 ms dans ~1 % des
    /// appels et atteint 10 ms — l'ordre de grandeur des 7 à 15 ms relevés en
    /// usage. On ne le fait donc jamais DANS le callback : cette file, à
    /// elle, porte l'appel. Sérielle, donc dans l'ordre.
    private let tapControlQueue = DispatchQueue(label: "SwishClone.gesture-tap.control", qos: .userInteractive)

    init(settings: TapSettingsStore) {
        let trace = trace
        engine = GestureTapEngine(
            settings: settings,
            now: { ProcessInfo.processInfo.systemUptime },
            hitTest: { GestureTarget.hitTest(at: $0, zoneHeight: $1) },
            deliver: MainDelivery.send,
            log: { if Self.traceEnabled { print("[GestureEventTap] \($0)") } },
            probe: { trace.add($0, nanoseconds: $1) }
        )
    }

    // MARK: Démarrage et arrêt

    func start() -> Bool {
        let started = loop.start { [self] in installTaps() }
        if started {
            print("[GestureEventTap] tap démarré (écoute seule, thread dédié) — swipe et pincement, action au lever")
        }
        return started
    }

    func stop() {
        loop.stop { [self] in tearDown() }
        print("[GestureEventTap] arrêté — \(metrics.summary)")
        if Self.traceEnabled { print("[GestureEventTap] par étape — \(trace.summary)") }
    }

    private func installTaps() -> Bool {
        let gestureMask = (CGEventMask(1) << CGEventType.scrollWheel.rawValue)
            | (CGEventMask(1) << CGEventMask(Self.gestureEventTypeRawValue))

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
        return true
    }

    private func tearDown() {
        // Les appels de tap déjà en file passent avant qu'on défasse les taps :
        // sinon l'un d'eux rallumerait un tap qu'on vient d'éteindre.
        tapControlQueue.sync {}
        keySwitch = KeyTapSwitch()
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        scheduledDeadline = nil
        engine.reset()

        for (tap, source) in [(gestureTap, gestureSource), (keyTap, keySource)] {
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        }
        gestureTap = nil
        gestureSource = nil
        keyTap = nil
        keySource = nil
    }

    private func createTap(mask: CGEventMask, callback: CGEventTapCallBack) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            // Le callback C retrouve ainsi son runner sans état global.
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func install(_ tap: CFMachPort) -> CFRunLoopSource? {
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return nil }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        return source
    }

    // MARK: Événements

    /// Rend la décision de la machine : avaler ou laisser passer. Ignorée
    /// tant que le tap est en écoute seule.
    fileprivate func handleGesture(type: CGEventType, event: CGEvent) -> GestureStateMachine.Disposition {
        let kind: String
        switch type {
        case .scrollWheel: kind = "scroll"
        case .tapDisabledByTimeout, .tapDisabledByUserInput: kind = "tap coupé"
        default: kind = "type \(type.rawValue)"
        }
        return traced(kind) { handleGestureBody(type: type, event: event) }
    }

    private func handleGestureBody(type: CGEventType, event: CGEvent) -> GestureStateMachine.Disposition {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            recoverFromDisabledTap(type)
            return .pass

        case .scrollWheel:
            let decoded: GestureStateMachine.Event? = timed(.decode) {
                NSEvent(cgEvent: event).map { scroll in
                    .scroll(
                        phase: Self.phase(scroll.phase),
                        momentum: Self.phase(scroll.momentumPhase),
                        dx: Double(scroll.deltaX),
                        dy: Double(scroll.deltaY)
                    )
                }
            }
            guard let decoded else { return .pass }
            return process(decoded, at: event.location)

        default:
            guard type.rawValue == Self.gestureEventTypeRawValue else { return .pass }
            return handleGestureEvent(event)
        }
    }

    private func handleGestureEvent(_ event: CGEvent) -> GestureStateMachine.Disposition {
        let subtypeField = unsafeBitCast(Self.subtypeFieldRawValue, to: CGEventField.self)
        let isMagnify = timed(.decode) { event.getIntegerValueField(subtypeField) == Self.magnifySubtype }
        guard isMagnify else { return .pass }

        let magnitudeField = unsafeBitCast(Self.magnitudeFieldRawValue, to: CGEventField.self)
        let magnitude = timed(.decode) { event.getDoubleValueField(magnitudeField) }

        // Diagnostic pour le P1 (pincer deux fois) : la machine ne peut
        // enchaîner des étapes de pincement que si l'événement porte une
        // phase. On relève ce que `NSEvent` en dit, sans encore s'en servir
        // — la fin du pincement reste détectée par le silence de 150 ms.
        timed(.diagnostics) {
            if GestureClassifier.debugLoggingEnabled, let ns = NSEvent(cgEvent: event) {
                print("[GestureEventTap] magnify NSEvent : type=\(ns.type.rawValue) phase=\(ns.phase.rawValue)")
            }
        }

        return process(.magnify(cumulative: magnitude, phase: nil), at: event.location)
    }

    fileprivate func handleKey(type: CGEventType, event: CGEvent) {
        traced("clavier") { handleKeyBody(type: type, event: event) }
    }

    private func handleKeyBody(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Le tap clavier est éteint hors geste : on ne le rallume que si
            // un geste est en cours.
            if let keyTap, engine.isTracking { CGEvent.tapEnable(tap: keyTap, enable: true) }
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKeyCode else { return }
            _ = process(.escape, at: event.location)
        default:
            break
        }
    }

    // MARK: La machine et le temps

    private func process(_ event: GestureStateMachine.Event, at location: CGPoint) -> GestureStateMachine.Disposition {
        let disposition = timed(.engine) { engine.process(event, at: location) }
        synchronize()
        return disposition
    }

    private func tick() {
        traced("réveil") {
            scheduledDeadline = nil
            deadlineTimer = nil
            timed(.engine) { engine.tick() }
            synchronize()
        }
    }

    /// Aligne le timer et le tap clavier sur l'état de la machine.
    ///
    /// Le timer n'est reprogrammé que si l'échéance **avance** : pendant un
    /// swipe, chaque événement la repousse, et recréer un timer cent fois par
    /// seconde ne servirait à rien. Un timer qui se réveille trop tôt envoie
    /// un `.tick` sans effet, puis se reprogramme sur la nouvelle échéance.
    private func synchronize() {
        // Seulement quand l'état change — pas à chaque événement, comme
        // avant : un geste de swipe en produit une centaine, chacun avec son
        // aller-retour vers le serveur de fenêtres.
        if let keyTap, let enable = keySwitch.transition(toTracking: engine.isTracking) {
            timed(.tapEnable) {
                tapControlQueue.async {
                    let started = DispatchTime.now().uptimeNanoseconds
                    CGEvent.tapEnable(tap: keyTap, enable: enable)
                    let elapsed = DispatchTime.now().uptimeNanoseconds - started
                    if Self.traceEnabled, elapsed > Self.slowCallbackNanoseconds {
                        print("[GestureEventTap] tapEnable(clavier, \(enable)) : \(elapsed / 1000) µs — hors callback, sans effet sur le défilement")
                    }
                }
            }
        }

        guard let deadline = engine.nextDeadline else {
            deadlineTimer?.invalidate()
            deadlineTimer = nil
            scheduledDeadline = nil
            return
        }
        if let scheduledDeadline, scheduledDeadline <= deadline { return }

        timed(.timer) {
            deadlineTimer?.invalidate()
            let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.tick() }
            // Ajouté à la run loop de CE thread (on y est) ; `.common` : sans ça,
            // le timer ne se déclencherait pas pendant qu'un menu est ouvert — et
            // le pincement ne finirait jamais.
            RunLoop.current.add(timer, forMode: .common)
            deadlineTimer = timer
            scheduledDeadline = deadline
        }
    }

    /// macOS coupe un tap dont le callback tarde, ou sur certaines saisies.
    /// Un tap coupé reste mort **sans rien dire** : il faut le rallumer. Des
    /// événements ont été perdus entre-temps, donc le geste en cours n'a plus
    /// de fin fiable — on l'abandonne.
    private func recoverFromDisabledTap(_ type: CGEventType) {
        print("[GestureEventTap] ⚠️ tap coupé par macOS (\(type == .tapDisabledByTimeout ? "délai" : "saisie")) — réactivé, geste en cours abandonné")
        if let gestureTap { CGEvent.tapEnable(tap: gestureTap, enable: true) }
        engine.reset()
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

    // MARK: Mesure

    /// Chronomètre un callback entier et, s'il est lent, dit OÙ le temps est
    /// passé — étape par étape — plutôt que de laisser deviner.
    ///
    /// Le corps tourne dans un `autoreleasepool` : la run loop d'un `Thread`
    /// Foundation n'en vide aucun, et chaque `NSEvent(cgEvent:)` laisse des
    /// objets autoreleasés derrière lui. Mesuré hors app : 200 000 événements
    /// sans pool font passer l'empreinte de 10 à 253 Mo (≈ 1,2 Ko par
    /// événement, donc de quoi grossir en continu pendant un défilement) ;
    /// avec pool, elle reste à 12 Mo. Le vidage du pool est compté dans le
    /// callback, donc visible dans « reste ».
    private func traced<T>(_ kind: String, _ body: () -> T) -> T {
        autoreleasepool {
            trace.begin(kind: kind)
            let started = DispatchTime.now().uptimeNanoseconds
            let result = body()
            let total = DispatchTime.now().uptimeNanoseconds - started

            metrics.record(total)
            if Self.traceEnabled, total > Self.slowCallbackNanoseconds {
                print("[GestureEventTap] ⚠️ callback lent : \(total / 1000) µs — \(trace.breakdown(total: total))")
            }
            trace.finish()
            return result
        }
    }

    private func timed<T>(_ step: TapStep, _ body: () -> T) -> T {
        let started = DispatchTime.now().uptimeNanoseconds
        let result = body()
        trace.add(step, nanoseconds: DispatchTime.now().uptimeNanoseconds - started)
        return result
    }
}

/// Quand allumer et éteindre le tap clavier : à chaque CHANGEMENT de l'état
/// « un geste est suivi », jamais entre deux.
struct KeyTapSwitch: Equatable {
    private var isEnabled = false

    /// L'état à appliquer au tap, ou `nil` s'il n'y a rien à faire.
    mutating func transition(toTracking tracking: Bool) -> Bool? {
        guard tracking != isEnabled else { return nil }
        isEnabled = tracking
        return tracking
    }
}

/// La durée des callbacks : de quoi juger, avant d'activer le tap, ce que
/// coûte d'être dans la chaîne d'entrée du système.
struct CallbackMetrics: Equatable {
    private(set) var count = 0
    private(set) var totalNanoseconds: UInt64 = 0
    private(set) var maxNanoseconds: UInt64 = 0

    mutating func record(_ nanoseconds: UInt64) {
        count += 1
        totalNanoseconds += nanoseconds
        maxNanoseconds = max(maxNanoseconds, nanoseconds)
    }

    var summary: String {
        guard count > 0 else { return "aucun callback" }
        return "\(count) callbacks, moyenne \(totalNanoseconds / UInt64(count) / 1000) µs, max \(maxNanoseconds / 1000) µs"
    }
}

// MARK: - Callbacks C

/// Fonctions top-level plutôt que closures littérales : un
/// `CGEventTapCallBack` doit pouvoir se former en pointeur de fonction C.
/// Le runner voyage dans `refcon` ; les sources des deux taps sont sur la run
/// loop de son thread : ces callbacks n'y sont appelés que là.
private func gestureTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let runner = Unmanaged<GestureTapRunner>.fromOpaque(refcon).takeUnretainedValue()
    let disposition = runner.handleGesture(type: type, event: event)
    // Sans effet en écoute seule ; à l'étape 5b, `nil` avalera l'événement.
    return disposition == .swallow ? nil : Unmanaged.passUnretained(event)
}

private func keyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        Unmanaged<GestureTapRunner>.fromOpaque(refcon).takeUnretainedValue().handleKey(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
