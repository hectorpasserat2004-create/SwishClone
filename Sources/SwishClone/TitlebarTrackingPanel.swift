import Cocoa
import SwishGestures

/// Prototype isolé (comme GlobalGestureMonitor.swift) — ne touche pas au
/// pipeline existant. Panel flottant qui suit la barre de titre de la
/// fenêtre active, où qu'elle soit et où qu'elle bouge (mode "Windows" de
/// Swish), plutôt qu'une bande fixe en haut de l'écran.
///
/// Contient notre `TouchGestureView` existante telle quelle comme
/// contentView : la détection de gestes elle-même n'est pas modifiée,
/// seule la POSITION de la zone qui les capte devient dynamique.
enum TitlebarTrackingPanel {

    /// Hauteur de la bande suivie, en haut de la fenêtre active — la zone
    /// typique d'une barre de titre.
    private static let bandHeight: CGFloat = 30
    private static let trackingInterval: TimeInterval = 0.15

    /// Largeur des feux tricolores (fermer/réduire/zoomer) en haut à
    /// gauche d'une fenêtre macOS standard — la bande commence après,
    /// pour ne pas leur voler les clics.
    private static let trafficLightsWidth: CGFloat = 80

    private static var panel: NSPanel?
    private static var trackingTimer: Timer?
    private static var lastLoggedFrontmostAppName: String?

    static func start() {
        let contentRect = NSRect(x: 0, y: 0, width: 200, height: bandHeight)
        let newPanel = NSPanel(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .floating
        newPanel.isOpaque = false
        // Couleur visible (temporaire, prototype) : pour vérifier à l'œil
        // que le panel suit bien la fenêtre ciblée pendant les tests.
        newPanel.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.25)
        newPanel.hasShadow = false
        newPanel.isMovable = false
        // Sans ça, le panel se cache dès que SwishClone n'est plus l'app
        // active — exactement le cas qu'on veut tester (une autre app au
        // premier plan).
        newPanel.hidesOnDeactivate = false

        let gestureView = TouchGestureView(frame: contentRect)
        newPanel.contentView = gestureView

        panel = newPanel

        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: trackingInterval, repeats: true) { _ in
            tick()
        }

        print("[TitlebarTrackingPanel] tracking démarré (intervalle \(Int(trackingInterval * 1000))ms)")
    }

    static func stop() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private static func tick() {
        let frontmostApp = NSWorkspace.shared.frontmostApplication

        // Log seulement au changement, pas à chaque tick — sert à la fois
        // à vérifier quelle app reste active pendant un geste (test 3) et
        // à voir un changement d'app se propager (test 4, ⌘Tab).
        if frontmostApp?.localizedName != lastLoggedFrontmostAppName {
            lastLoggedFrontmostAppName = frontmostApp?.localizedName
            print("[TitlebarTrackingPanel] app au premier plan : \(frontmostApp?.localizedName ?? "?")")
        }

        guard frontmostApp?.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            panel?.orderOut(nil)
            return
        }

        guard let window = WindowController.getFrontmostWindow(),
              let position = WindowController.position(of: window),
              let size = WindowController.size(of: window),
              let screenHeight = NSScreen.main?.frame.height else {
            panel?.orderOut(nil)
            return
        }

        // Conversion de coordonnées : l'Accessibility API (AXPosition)
        // utilise une origine en HAUT à gauche de l'écran, y croissant
        // vers le BAS. NSWindow/NSScreen utilisent une origine en BAS à
        // gauche, y croissant vers le HAUT. WindowController.moveAndResize
        // ne fait PAS cette conversion : il écrit des coordonnées AX
        // directement, et jusqu'ici tous nos rectangles (pleine hauteur,
        // ou centrés) étaient invariants par ce changement d'origine,
        // donc le problème ne s'était jamais posé. Une bande de 30px
        // ancrée en HAUT de la fenêtre (donc PAS centrée, PAS pleine
        // hauteur) est le premier cas où la conversion est réellement
        // nécessaire :
        //   position.y (AX, depuis le haut de l'écran)
        //   -> cocoaY = screenHeight - position.y - bandHeight
        //      (NSWindow, depuis le bas de l'écran)
        let cocoaY = screenHeight - position.y - bandHeight

        // Décalée après les feux tricolores : sans ça, la bande les
        // recouvre entièrement et le clic pour fermer/réduire/zoomer la
        // fenêtre cible n'atteint plus jamais la vraie fenêtre.
        let frame = NSRect(
            x: position.x + trafficLightsWidth,
            y: cocoaY,
            width: max(0, size.width - trafficLightsWidth),
            height: bandHeight
        )
        // `orderFront` reste nécessaire pour la visibilité à l'écran :
        // `makeKey()` seul ne rend PAS un panel visible s'il ne l'est pas
        // déjà (contrairement à `makeKeyAndOrderFront`, qu'on évite ici
        // exprès). Les deux appels sont donc complémentaires, pas
        // redondants : `orderFront` affiche, `makeKey()` rend key.
        //
        // Ce que `makeKey()` doit apporter par rapport à avant : une NSView
        // ne reçoit touchesBegan que si sa fenêtre EST key, et
        // `orderFront`/`orderFrontRegardless` affichent sans jamais rendre
        // key. `makeKey()` (jamais `makeKeyAndOrderFront`, et surtout
        // jamais `NSApp.activate`) est censé pouvoir rendre un panel
        // `.nonactivatingPanel` key SANS faire passer notre app au premier
        // plan à la place de celle ciblée — c'est précisément ce que le
        // log ci-dessous doit confirmer ou infirmer.
        panel?.setFrame(frame, display: true)
        panel?.orderFront(nil)
        panel?.makeKey()
        debugLogKeyState()
    }

    private static func debugLogKeyState() {
        print("[TitlebarTrackingPanel] panel.isKeyWindow=\(panel?.isKeyWindow ?? false) "
            + "app au premier plan=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
    }
}
