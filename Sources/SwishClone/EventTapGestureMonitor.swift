import Cocoa
import CoreGraphics
import SwishCloneCore
import SwishGestures

/// Prototype isolé (comme GlobalGestureMonitor.swift et
/// TitlebarTrackingPanel.swift) — ne touche à rien du pipeline existant
/// (TouchGestureView / GestureClassifier restent inchangés). Capture le
/// pinch globalement, via `CGEventTap`, sans passer par AUCUNE NSView ni
/// NSWindow — donc utilisable peu importe l'app au premier plan.
///
/// ⚠️ **Technique non documentée officiellement par Apple**, décodée
/// empiriquement à partir de deux gestes isolés et annoncés (un pinch out,
/// un swipe gauche), en balayant une large plage de `CGEventField` et en
/// corrélant à l'œil les valeurs qui bougeaient avec le geste physique
/// réel. Ce qui a été confirmé :
///
/// - Les gestes multi-touch remontent sous `CGEventType.rawValue == 29`
///   (parfois appelé en interne `kCGEventGesture`), un type absent de
///   l'enum publique `CGEventType`.
/// - Le champ **110** discrimine le sous-type : `8` = magnification
///   (pinch), `6` = swipe/pan.
/// - Le champ **113** porte la valeur utile, mais PAS comme un entier ni
///   via la conversion `CGEventGetDoubleValueField` : ce sont les 4 octets
///   bruts d'un `Float32` (IEEE-754), à réinterpréter par bit-cast direct
///   — jamais par une conversion numérique `Int -> Float`, qui donnerait
///   un nombre complètement différent. Pour un magnify (`field110 == 8`),
///   c'est la magnitude CUMULATIVE depuis le début du geste : positive en
///   écartant les doigts (pinch out), négative en les resserrant
///   (pinch in). Confirmé sur un pinch out isolé : croissance propre de
///   0.001 à 0.15, toujours positive.
///
/// Rien de tout ça n'est garanti stable d'une version de macOS à l'autre.
///
/// Le swipe n'est PAS redécodé ici : `GlobalGestureMonitor` (scrollWheel,
/// via `NSEvent`) le couvre déjà de façon fiable, pas besoin d'une
/// deuxième source pour la même chose.
enum EventTapGestureMonitor {

    /// rawValue non documenté du type d'event "gesture".
    ///
    /// `fileprivate`, pas `private` : accédé depuis `eventTapCallback`,
    /// une fonction top-level du même fichier (voir plus bas pourquoi ce
    /// callback ne peut pas être une closure littérale).
    fileprivate static let gestureEventTypeRawValue: UInt32 = 29

    /// Champ qui discrimine magnify (8) de swipe/pan (6) sur un event de
    /// type 29.
    private static let subtypeFieldRawValue: UInt32 = 110
    private static let magnifySubtype: Int64 = 8

    /// Champ qui porte la magnitude cumulative de magnification — à lire
    /// en Float32 par bit-cast, jamais en conversion numérique.
    private static let magnitudeFieldRawValue: UInt32 = 113

    /// En dessous de cette magnitude cumulative absolue, le pinch est
    /// ignoré (mouvement trop faible pour être volontaire). À calibrer.
    private static let pinchThreshold: Float = 0.1

    /// Silence après le dernier event magnify au-delà duquel on considère
    /// que les doigts ont levé et que le pinch est terminé — il n'y a pas
    /// d'équivalent à "touchesEnded" dans ce flux d'events, juste une
    /// absence de nouveaux events une fois les doigts levés.
    private static let pinchSessionGap: TimeInterval = 0.15

    private static var pinchSessionActive = false
    private static var lastPinchMagnitude: Float = 0
    /// Magnitude de plus grande amplitude (avec son signe d'origine) vue
    /// depuis le début de la session — c'est elle, pas la dernière valeur
    /// reçue, qui représente le pinch réellement effectué : en fin de
    /// geste, le relâchement naturel des doigts fait souvent retomber la
    /// magnitude sous le seuil juste avant que le silence ne déclenche la
    /// fin de session, ce qui rejetait à tort des pinchs pourtant nets.
    private static var peakPinchMagnitude: Float = 0
    private static var pinchSessionTimer: Timer?

    private static var eventTap: CFMachPort?
    private static var runLoopSource: CFRunLoopSource?

    static func start() {
        guard WindowController.isAccessibilityTrusted() else {
            print("[EventTapGestureMonitor] permission Accessibility manquante — "
                + "CGEventTapCreate échouerait silencieusement sans elle. "
                + "Demande de la permission…")
            WindowController.requestAccessibilityPermission()
            return
        }

        let eventsOfInterest = CGEventMask(1) << CGEventMask(gestureEventTypeRawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventsOfInterest,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            print("""
            [EventTapGestureMonitor] ⚠️ CGEventTapCreate a retourné nil — le tap \
            ne s'est PAS créé. Causes possibles, dans l'ordre le plus probable :
              1. Permission Accessibility accordée pour un build précédent mais \
                 pas pour celui-ci : `swift run` change le chemin du binaire à \
                 chaque recompilation, macOS peut redemander l'autorisation.
              2. Permission "Contrôle de l'entrée" (Input Monitoring) manquante — \
                 distincte d'Accessibility depuis macOS 10.15, potentiellement \
                 nécessaire même avec .cgSessionEventTap selon la version de \
                 macOS. À vérifier dans Réglages Système > Confidentialité et \
                 sécurité > Contrôle de l'entrée (Input Monitoring), en plus \
                 d'Accessibilité.
              3. Restriction liée à un exécutable non signé/notarisé en dehors \
                 d'un vrai bundle .app — peu probable via `swift run` en usage \
                 local, mais à garder en tête si les deux permissions ci-dessus \
                 sont accordées et que ça échoue quand même.
            """)
            return
        }

        eventTap = tap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            print("[EventTapGestureMonitor] ⚠️ le tap s'est créé mais "
                + "CFMachPortCreateRunLoopSource a échoué — abandon.")
            eventTap = nil
            return
        }

        runLoopSource = source
        CFRunLoopAddSource(RunLoop.current.getCFRunLoop(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[EventTapGestureMonitor] tap démarré — pinch global actif "
            + "(seuil \(pinchThreshold), fenêtre de fin de session \(Int(pinchSessionGap * 1000))ms)")
    }

    static func stop() {
        pinchSessionTimer?.invalidate()
        pinchSessionTimer = nil
        pinchSessionActive = false
        lastPinchMagnitude = 0
        peakPinchMagnitude = 0
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(RunLoop.current.getCFRunLoop(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Appelé pour chaque event de type 29. Ignore tout ce qui n'est pas
    /// un magnify (le swipe reste couvert par GlobalGestureMonitor).
    fileprivate static func handleGestureEvent(_ event: CGEvent) {
        let subtypeField = unsafeBitCast(subtypeFieldRawValue, to: CGEventField.self)
        guard event.getIntegerValueField(subtypeField) == magnifySubtype else { return }

        let magnitudeField = unsafeBitCast(magnitudeFieldRawValue, to: CGEventField.self)

        // DEBUG TEMPORAIRE : magnitude toujours à 0.0 en aval de la
        // classification. On compare ici les deux lectures possibles du
        // même champ, event par event, pour savoir laquelle est en cause
        // AVANT le stockage — plutôt que de deviner.
        let rawInt = event.getIntegerValueField(magnitudeField)
        let bitcastFloat = Float(bitPattern: UInt32(truncatingIfNeeded: rawInt))
        let viaDoubleField = event.getDoubleValueField(magnitudeField)
        print("[EventTapGestureMonitor] magnify event : rawInt=\(rawInt) "
            + "bitcastFloat32=\(bitcastFloat) getDoubleValueField=\(viaDoubleField)")

        // Suspect principal : `CGEventGetIntegerValueField` sur un champ
        // stocké en float ne renvoie probablement pas les octets bruts
        // mais une CONVERSION (troncature vers un entier, donc ~0 pour
        // 0.001…0.15) — ce que suggérait déjà le fait que la colonne
        // "entier" du balayage précédent n'était pas la bonne pour ce
        // champ, seule la colonne "décimal" (`getDoubleValueField`)
        // l'était. En attendant confirmation par les logs ci-dessus, on
        // utilise `getDoubleValueField`, la lecture déjà validée
        // empiriquement sur un vrai pinch out.
        let magnitude = Float(viaDoubleField)

        let isNewSession = !pinchSessionActive
        pinchSessionActive = true
        lastPinchMagnitude = magnitude
        // Remise à zéro propre du pic au tout premier event d'une
        // nouvelle session, puis mise à jour uniquement si l'amplitude
        // (en valeur absolue) dépasse le pic déjà enregistré.
        if isNewSession || abs(magnitude) > abs(peakPinchMagnitude) {
            peakPinchMagnitude = magnitude
        }

        pinchSessionTimer?.invalidate()
        pinchSessionTimer = Timer.scheduledTimer(withTimeInterval: pinchSessionGap, repeats: false) { _ in
            finishPinchSession()
        }
    }

    private static func finishPinchSession() {
        guard pinchSessionActive else { return }
        let peak = peakPinchMagnitude
        let last = lastPinchMagnitude
        pinchSessionActive = false
        lastPinchMagnitude = 0
        peakPinchMagnitude = 0
        pinchSessionTimer = nil

        // C'est le PIC, pas la dernière valeur, qui décide à la fois du
        // seuil et de la direction (signe d'origine du pic) — voir le
        // commentaire sur `peakPinchMagnitude`.
        guard abs(peak) >= pinchThreshold else {
            print("[EventTapGestureMonitor] fin de session pinch : peak=\(peak) (dernier=\(last)) -> ignoré (< seuil \(pinchThreshold))")
            return
        }

        // Le pinch est toujours à 2 doigts par construction physique du
        // geste — cette API ne donne de toute façon pas le nombre de
        // doigts, contrairement à NSTouch.
        let direction: PinchDirection = peak > 0 ? .out : .in_
        let gesture = Gesture.pinch(direction: direction, fingers: 2)
        print("[EventTapGestureMonitor] fin de session pinch : peak=\(peak) (dernier=\(last)) -> retenu, \(gesture)")

        // Le diagnostic ci-dessus s'affiche toujours, où que soit le
        // curseur — seule l'action finale sur la fenêtre est conditionnée
        // à la zone (mode "Menubar" façon Swish).
        guard GestureZone.isCursorInTopBand() else {
            print("[EventTapGestureMonitor] pinch ignoré : curseur hors zone")
            return
        }

        WindowController.handleGesture(gesture)
    }
}

/// Fonction top-level plutôt que closure littérale passée inline : un
/// `CGEventTapCallBack` doit pouvoir se former en pointeur de fonction C
/// (`@convention(c)`), et le compilateur refuse ça pour une closure qui
/// "capture du contexte" — y compris, en pratique, une closure qui se
/// contente de référencer un autre membre `static` du même type englobant.
/// Une fonction top-level n'a ce problème par construction.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type.rawValue == EventTapGestureMonitor.gestureEventTypeRawValue {
        EventTapGestureMonitor.handleGestureEvent(event)
    }
    // .listenOnly : on ne modifie jamais l'event, on le laisse continuer
    // son chemin inchangé.
    return Unmanaged.passUnretained(event)
}
