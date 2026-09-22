import Cocoa
import SwishCloneCore
import SwishGestures

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var toggleWindowItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let contentRect = NSRect(x: 0, y: 0, width: 600, height: 400)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "SwishClone — Phase 1 (core v\(SwishCloneCore.version))"
        // Sans ça, fermer la fenêtre la désalloue et le prochain "Afficher"
        // planterait en réutilisant une référence morte.
        window.isReleasedWhenClosed = false

        let gestureView = TouchGestureView(frame: contentRect)
        window.contentView = gestureView
        window.makeFirstResponder(gestureView)

        setUpStatusItem()

        // Prototype isolé (voir GlobalGestureMonitor.swift) : ne remplace
        // rien de l'existant, tourne en parallèle pour tester si les
        // gestes sont captables globalement, sans activer notre fenêtre.
        GlobalGestureMonitor.start()

        // Prototype isolé (voir TitlebarTrackingPanel.swift) : panel qui
        // suit la barre de titre de la fenêtre active, en parallèle de la
        // fenêtre de test fixe existante.
        TitlebarTrackingPanel.start()

        // Prototype isolé (voir EventTapGestureMonitor.swift) : capture
        // des gestes via CGEventTap, sans passer par aucune NSView/NSWindow.
        EventTapGestureMonitor.start()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "hand.draw",
            accessibilityDescription: "SwishClone"
        )

        let menu = NSMenu()
        menu.delegate = self

        toggleWindowItem = menu.addItem(
            withTitle: "Afficher la fenêtre de test",
            action: #selector(toggleTestWindow),
            keyEquivalent: ""
        )
        toggleWindowItem.target = self

        menu.addItem(.separator())

        let snapLeftItem = menu.addItem(
            withTitle: "Coller fenêtre active à gauche",
            action: #selector(snapFrontmostWindowLeft),
            keyEquivalent: ""
        )
        snapLeftItem.target = self

        menu.addItem(.separator())

        let quitItem = menu.addItem(
            withTitle: "Quitter",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        toggleWindowItem.title = window.isVisible
            ? "Cacher la fenêtre de test"
            : "Afficher la fenêtre de test"
    }

    @objc private func toggleTestWindow() {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Bouton de test de la Phase 3 : positionne la fenêtre au premier plan
    /// (de n'importe quelle app) sur la moitié gauche de l'écran principal.
    @objc private func snapFrontmostWindowLeft() {
        guard WindowController.isAccessibilityTrusted() else {
            WindowController.requestAccessibilityPermission()
            return
        }

        guard let frontmostWindow = WindowController.getFrontmostWindow(),
              let screen = NSScreen.main else { return }

        WindowController.moveAndResize(
            window: frontmostWindow,
            x: 0,
            y: 0,
            width: screen.frame.width / 2,
            height: screen.frame.height
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
