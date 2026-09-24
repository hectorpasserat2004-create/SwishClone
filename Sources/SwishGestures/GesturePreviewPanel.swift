import AppKit
import SwiftUI
import SwishCloneCore

/// **Le panneau d'aperçu** : ce que fera le lever, affiché pendant le geste,
/// au centre de l'écran de la cible — façon HUD système (l'ancien HUD de
/// volume de macOS).
///
/// Un `NSPanel` qui ne devient jamais la fenêtre active, ignore la souris et
/// reste visible sur tous les bureaux, par-dessus le plein écran et le Dock.
/// Il n'a jamais besoin du focus — contrairement au `TitlebarTrackingPanel`
/// de la Phase 4, qui devait devenir *key* pour recevoir des touches.
///
/// Contenu sans libellé : un mini-écran avec la zone visée, un feu
/// tricolore redessiné (rouge fermer, jaune réduire, vert plein écran), le
/// feu rouge avec l'icône de l'app pour « quitter », ou un point
/// d'interrogation. Le libellé existe quand même (`Preview.label`) : c'est
/// l'étiquette VoiceOver du panneau. Rendu validé sur la page d'aperçu du
/// 24/09/2026 avant intégration.
@MainActor
enum GesturePreviewPanel {

    static let size = CGSize(width: 160, height: 160)
    static let cornerRadius: CGFloat = 32
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
    ///   - targetFrame: le cadre de la fenêtre visée, en coordonnées AX —
    ///     c'est son écran qui accueille le panneau. `nil` pour une icône du
    ///     Dock : c'est alors l'écran du curseur.
    ///   - cursor: position du curseur au début du geste, en coordonnées AX.
    ///   - appIcon: pour `quitApp`, l'icône de l'app visée.
    static func show(
        _ preview: GestureStateMachine.Preview,
        targetFrame: CGRect?,
        cursor: CGPoint,
        appName: String?,
        appIcon: NSImage?
    ) {
        model.content = PreviewContent(preview)
        model.appIcon = appIcon
        model.label = preview.label(appName: appName)

        guard isShown == false else { return } // mise à jour : le fondu enchaîné est dans la vue
        isShown = true
        generation += 1

        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return }
        let frames = screens.map { ScreenGeometry.axRect(fromCocoa: $0.frame, primaryScreenHeight: primaryHeight) }
        guard let index = PreviewPlacement.screenIndex(targetFrame: targetFrame, cursor: cursor, screens: frames) else { return }

        model.screenAspect = frames[index].width / max(frames[index].height, 1)
        let visible = ScreenGeometry.axRect(fromCocoa: screens[index].visibleFrame, primaryScreenHeight: primaryHeight)
        let targetAX = PreviewPlacement.frame(size: size, centeredIn: visible)
        let target = ScreenGeometry.cocoaRect(fromAX: targetAX, primaryScreenHeight: primaryHeight)

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
        background.layer?.cornerRadius = cornerRadius
        background.layer?.cornerCurve = .continuous
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
        case let .light(light):
            TrafficLightView(light: light, diameter: 72)
        case .quitApp:
            QuitLightView(icon: model.appIcon)
        case .unrecognized:
            Image(systemName: "questionmark")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Le feu rouge, et l'icône de l'app en petit dans son coin bas droit.
private struct QuitLightView: View {
    let icon: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TrafficLightView(light: .close, diameter: 72)
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .offset(x: 12, y: 10)
            }
        }
        .frame(width: 72, height: 72)
    }
}

/// Un petit écran, aux proportions de l'écran réel, avec la zone visée
/// remplie à la couleur d'accent du système.
private struct MiniScreen: View {
    let zone: CGRect
    let aspect: CGFloat

    private static let maxSize = CGSize(width: 112, height: 70)

    var body: some View {
        let size = fitted
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary, lineWidth: 1.5)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor)
                .frame(width: max(zone.width * size.width - 6, 1), height: max(zone.height * size.height - 6, 1))
                .offset(x: zone.minX * size.width + 3, y: zone.minY * size.height + 3)
        }
        .frame(width: size.width, height: size.height)
    }

    private var fitted: CGSize {
        let width = min(Self.maxSize.width, Self.maxSize.height * aspect)
        return CGSize(width: width, height: width / max(aspect, 0.1))
    }
}

// MARK: - Feux tricolores

/// Un bouton de fenêtre de macOS, redessiné en vectoriel : disque en léger
/// dégradé, liseré un ton plus foncé, symbole toujours visible (c'est un
/// aperçu, pas un bouton — les vrais ne montrent le leur qu'au survol).
///
/// Les vrais boutons (`NSWindow.standardWindowButton`) ne servent pas ici :
/// 14 pt, flous une fois agrandis, et symbole seulement au survol.
/// Couleurs relevées à l'œil sur les boutons actuels.
struct TrafficLightView: View {
    let light: TrafficLight
    let diameter: CGFloat

    var body: some View {
        ZStack {
            // Haut du disque un peu plus clair : le dégradé de la maquette
            // validée, `fill.mix(with: .white, by: 0.14)` → `fill`.
            Circle().fill(LinearGradient(
                colors: [light.top, light.fill],
                startPoint: .top,
                endPoint: .bottom
            ))
            Circle().strokeBorder(light.rim, lineWidth: diameter * 0.035)
            glyph
        }
        .frame(width: diameter, height: diameter)
    }

    @ViewBuilder
    private var glyph: some View {
        let d = diameter
        let ink = light.glyph.opacity(0.85)
        let stroke = StrokeStyle(lineWidth: 0.095 * d, lineCap: .round)
        switch light {
        case .close:
            Path { p in
                p.move(to: CGPoint(x: 0.30 * d, y: 0.30 * d))
                p.addLine(to: CGPoint(x: 0.70 * d, y: 0.70 * d))
                p.move(to: CGPoint(x: 0.70 * d, y: 0.30 * d))
                p.addLine(to: CGPoint(x: 0.30 * d, y: 0.70 * d))
            }
            .stroke(ink, style: stroke)
        case .minimize:
            Path { p in
                p.move(to: CGPoint(x: 0.25 * d, y: 0.5 * d))
                p.addLine(to: CGPoint(x: 0.75 * d, y: 0.5 * d))
            }
            .stroke(ink, style: stroke)
        case .fullScreen:
            // Deux triangles opposés, pointés vers les coins haut gauche et
            // bas droit, de part et d'autre de la diagonale.
            Path { p in
                p.move(to: CGPoint(x: 0.28 * d, y: 0.28 * d))
                p.addLine(to: CGPoint(x: 0.61 * d, y: 0.28 * d))
                p.addLine(to: CGPoint(x: 0.28 * d, y: 0.61 * d))
                p.closeSubpath()
                p.move(to: CGPoint(x: 0.72 * d, y: 0.72 * d))
                p.addLine(to: CGPoint(x: 0.39 * d, y: 0.72 * d))
                p.addLine(to: CGPoint(x: 0.72 * d, y: 0.39 * d))
                p.closeSubpath()
            }
            .fill(ink)
        }
    }
}

private extension TrafficLight {
    var fill: Color {
        switch self {
        case .close: Color(red: 1.000, green: 0.373, blue: 0.341)      // #FF5F57
        case .minimize: Color(red: 0.996, green: 0.737, blue: 0.180)   // #FEBC2E
        case .fullScreen: Color(red: 0.157, green: 0.784, blue: 0.251) // #28C840
        }
    }

    /// Le haut du dégradé. **Figé en constantes** plutôt que calculé :
    /// `Color.mix(with:by:)` n'existe qu'à partir de macOS 15 (SwishClone
    /// vise 13), et il mélange dans un espace perceptuel — un voile blanc à
    /// 14 % s'en écartait jusqu'à 20/255 sur le vert. Valeurs résolues par
    /// `mix` lui-même, en sRGB étendu (le rouge dépasse 1).
    var top: Color {
        switch self {
        case .close: Color(.sRGB, red: 1.0138, green: 0.4762, blue: 0.4351)
        case .minimize: Color(.sRGB, red: 0.9987, green: 0.7766, blue: 0.3568)   // #FFC65B
        case .fullScreen: Color(.sRGB, red: 0.3459, green: 0.8181, blue: 0.3793) // #58D161
        }
    }

    var rim: Color {
        switch self {
        case .close: Color(red: 0.878, green: 0.267, blue: 0.243)      // #E0443E
        case .minimize: Color(red: 0.871, green: 0.631, blue: 0.137)   // #DEA123
        case .fullScreen: Color(red: 0.102, green: 0.671, blue: 0.161) // #1AAB29
        }
    }

    var glyph: Color {
        switch self {
        case .close: Color(red: 0.302, green: 0.000, blue: 0.000)      // #4D0000
        case .minimize: Color(red: 0.600, green: 0.341, blue: 0.000)   // #995700
        case .fullScreen: Color(red: 0.000, green: 0.396, blue: 0.000) // #006500
        }
    }
}
