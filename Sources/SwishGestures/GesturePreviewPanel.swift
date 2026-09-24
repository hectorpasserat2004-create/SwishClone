import AppKit
import SwiftUI
import SwishCloneCore

/// **Le panneau d'aperçu** : ce que fera le lever, affiché pendant le geste,
/// près du curseur.
///
/// Un `NSPanel` qui ne devient jamais la fenêtre active, ignore la souris et
/// reste visible sur tous les bureaux, par-dessus le plein écran et le Dock.
/// Il n'a jamais besoin du focus — contrairement au `TitlebarTrackingPanel`
/// de la Phase 4, qui devait devenir *key* pour recevoir des touches.
///
/// Compact, sans libellé : un mini-écran avec la zone visée, un symbole, ou
/// l'icône de l'app à quitter. Le libellé existe quand même
/// (`Preview.label`) : c'est l'étiquette VoiceOver du panneau.
///
/// Posé **une fois**, au premier affichage d'un geste : un swipe à deux
/// doigts ne déplace pas le pointeur, et un panneau qui suivrait le contenu
/// en changeant de place serait plus difficile à lire.
@MainActor
enum GesturePreviewPanel {

    static let size = CGSize(width: 64, height: 48)
    static let appearDuration: TimeInterval = 0.12
    static let disappearDuration: TimeInterval = 0.1
    static let appearScale: CGFloat = 0.95

    private static var panel: NSPanel?
    private static var model = PreviewModel()
    /// Incrémenté à chaque affichage : un fondu de disparition en retard ne
    /// doit pas fermer le panneau d'un geste suivant.
    private static var generation = 0
    private static var isShown = false

    /// Affiche (ou met à jour) le panneau.
    ///
    /// - Parameters:
    ///   - cursor: position du curseur au début du geste, en coordonnées AX.
    ///   - appIcon: pour `quitApp`, l'icône de l'app visée.
    static func show(_ preview: GestureStateMachine.Preview, cursor: CGPoint, appName: String?, appIcon: NSImage?) {
        model.content = PreviewContent(preview)
        model.appIcon = appIcon
        model.label = preview.label(appName: appName)

        guard isShown == false else { return } // mise à jour : le fondu enchaîné est dans la vue
        isShown = true
        generation += 1

        guard let screens = screensAX(), let screen = screen(containing: cursor, among: screens.frames) else { return }
        model.screenAspect = screen.width / max(screen.height, 1)

        let targetAX = PreviewPlacement.frame(size: size, cursor: cursor, screen: screen)
        let target = ScreenGeometry.cocoaRect(fromAX: targetAX, primaryScreenHeight: screens.primaryHeight)

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let start = reduceMotion ? target : target.insetBy(
            dx: target.width * (1 - appearScale) / 2,
            dy: target.height * (1 - appearScale) / 2
        )
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = appearDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if reduceMotion == false { panel.animator().setFrame(target, display: true) }
        }
    }

    static func hide() {
        guard isShown, let panel else { return }
        isShown = false
        let hiding = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = disappearDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                // Un nouveau geste a pu rouvrir le panneau pendant le fondu.
                guard generation == hiding, isShown == false else { return }
                panel.orderOut(nil)
            }
        })
    }

    // MARK: - Construction

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu // au-dessus du Dock, pour l'aperçu « quitter »
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        // Verre dépoli système : suit le mode clair/sombre et « Réduire la
        // transparence » sans rien à gérer.
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: PreviewView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        return panel
    }

    // MARK: - Écrans

    private static func screensAX() -> (frames: [CGRect], primaryHeight: CGFloat)? {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return nil }
        return (screens.map { ScreenGeometry.axRect(fromCocoa: $0.frame, primaryScreenHeight: primaryHeight) }, primaryHeight)
    }

    private static func screen(containing point: CGPoint, among screens: [CGRect]) -> CGRect? {
        let probe = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        return ScreenGeometry.screenIndex(for: probe, among: screens).map { screens[$0] }
    }
}

// MARK: - Vue

@MainActor
private final class PreviewModel: ObservableObject {
    @Published var content: PreviewContent = .unrecognized
    @Published var appIcon: NSImage?
    @Published var label = ""
    @Published var screenAspect: CGFloat = 16 / 10
}

private struct PreviewView: View {
    @ObservedObject var model: PreviewModel

    var body: some View {
        ZStack {
            content
                // Le libellé sert d'identité : un changement de contenu se
                // fait en fondu enchaîné, pas en saut.
                .id(model.label)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.1), value: model.label)
        .frame(width: GesturePreviewPanel.size.width, height: GesturePreviewPanel.size.height)
        .accessibilityElement()
        .accessibilityLabel(model.label)
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case let .zone(unit):
            MiniScreen(zone: unit, aspect: model.screenAspect)
        case let .symbol(symbol):
            Image(systemName: symbol.systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
        case .quitApp:
            ZStack(alignment: .bottomTrailing) {
                if let icon = model.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "app")
                        .font(.system(size: 26))
                }
                Image(systemName: "power")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(Color.red))
                    .offset(x: 4, y: 4)
            }
        case .unrecognized:
            Image(systemName: "questionmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Un petit écran, aux proportions de l'écran réel, avec la zone visée
/// remplie.
private struct MiniScreen: View {
    let zone: CGRect
    let aspect: CGFloat

    private static let maxSize = CGSize(width: 48, height: 32)

    var body: some View {
        let size = fitted
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.secondary, lineWidth: 1)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: max(zone.width * size.width - 3, 1), height: max(zone.height * size.height - 3, 1))
                .offset(x: zone.minX * size.width + 1.5, y: zone.minY * size.height + 1.5)
        }
        .frame(width: size.width, height: size.height)
    }

    private var fitted: CGSize {
        let width = min(Self.maxSize.width, Self.maxSize.height * aspect)
        return CGSize(width: width, height: width / max(aspect, 0.1))
    }
}
