import AppKit
import SwiftUI
import SwishCloneCore

/// **Le panneau d'aperçu** : ce que fera le lever, affiché pendant le geste.
///
/// Deux styles, selon ce que l'aperçu dit :
///
/// - **Les feux tricolores** (fermer, réduire, plein écran, quitter) : un
///   disque de 22 pt, à la taille des vrais boutons de fenêtre, posé pile sur
///   le curseur — un feu, c'est « le bouton que je clique », et le curseur
///   n'a pas bougé pendant un geste à deux doigts. Sans fond ni cadre. Le
///   curseur système reste dessiné par-dessus (on ne peut pas le masquer
///   depuis une app en arrière-plan sans API privée) : sa pointe tombe au
///   centre du disque.
/// - **Le mini-écran** (moitié, quart, remplir) et le point d'interrogation :
///   un HUD de verre de 160 pt au centre de l'écran de la cible, façon HUD
///   système. Il montre une géométrie relative à l'écran, qui serait à
///   l'étroit — voire coupée — près d'une barre de titre en haut d'écran.
///
/// Un même geste peut passer de l'un à l'autre (↓ réduit, ↓ puis → vise un
/// quart) : chaque style a donc son propre panneau, et l'un s'efface quand
/// l'autre apparaît, au lieu de déplacer un panneau unique.
///
/// Des `NSPanel` qui ne deviennent jamais la fenêtre active, ignorent la
/// souris et restent visibles sur tous les bureaux, par-dessus le plein écran
/// et le Dock. Ils n'ont jamais besoin du focus — contrairement au
/// `TitlebarTrackingPanel` de la Phase 4, qui devait devenir *key* pour
/// recevoir des touches.
///
/// Le libellé (`Preview.label`) est l'étiquette VoiceOver. Rendu du HUD
/// validé sur la page d'aperçu du 24/09/2026 avant intégration.
@MainActor
enum GesturePreviewPanel {

    private static let hud = PreviewWindow(style: .hud)
    private static let cursorLight = PreviewWindow(style: .cursorLight)

    /// Affiche (ou met à jour) l'aperçu.
    ///
    /// - Parameters:
    ///   - targetFrame: le cadre de la fenêtre visée, en coordonnées AX —
    ///     c'est son écran qui accueille le HUD. `nil` pour une icône du
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
        let content = PreviewContent(preview)
        let shown: PreviewWindow
        let other: PreviewWindow
        switch content {
        case .light, .quitApp:
            shown = cursorLight
            other = hud
        case .zone, .unrecognized:
            shown = hud
            other = cursorLight
        }
        other.hide()
        shown.show(
            content: content,
            label: preview.label(appName: appName),
            appIcon: appIcon,
            targetFrame: targetFrame,
            cursor: cursor
        )
    }

    static func hide() {
        hud.hide()
        cursorLight.hide()
    }
}

// MARK: - Une fenêtre d'aperçu

@MainActor
private final class PreviewWindow {

    enum Style {
        /// Verre dépoli de 160 pt, centré sur l'écran de la cible.
        case hud
        /// Feu de 22 pt, centré sur le curseur, sans fond.
        case cursorLight

        var size: CGSize {
            switch self {
            case .hud: CGSize(width: 160, height: 160)
            // Le disque, plus la marge de l'ombre et du coin d'icône « quitter ».
            case .cursorLight: CGSize(width: 44, height: 44)
            }
        }
    }

    static let cornerRadius: CGFloat = 32
    static let lightDiameter: CGFloat = 22
    static let appearDuration: TimeInterval = 0.12
    static let disappearDuration: TimeInterval = 0.1
    static let appearScale: CGFloat = 0.95

    let style: Style
    private var panel: NSPanel?
    private let model = PreviewModel()
    /// Incrémenté à chaque affichage : un fondu de disparition en retard ne
    /// doit pas fermer le panneau d'un geste suivant.
    private var generation = 0
    private var isShown = false

    init(style: Style) {
        self.style = style
    }

    func show(
        content: PreviewContent,
        label: String,
        appIcon: NSImage?,
        targetFrame: CGRect?,
        cursor: CGPoint
    ) {
        model.content = content
        model.appIcon = appIcon
        model.label = label

        guard isShown == false else { return } // mise à jour : le fondu enchaîné est dans la vue

        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return }

        let targetAX: CGRect
        switch style {
        case .hud:
            let frames = screens.map { ScreenGeometry.axRect(fromCocoa: $0.frame, primaryScreenHeight: primaryHeight) }
            guard let index = PreviewPlacement.screenIndex(targetFrame: targetFrame, cursor: cursor, screens: frames) else { return }
            model.screenAspect = frames[index].width / max(frames[index].height, 1)
            let visible = ScreenGeometry.axRect(fromCocoa: screens[index].visibleFrame, primaryScreenHeight: primaryHeight)
            targetAX = PreviewPlacement.frame(size: style.size, centeredIn: visible)
        case .cursorLight:
            targetAX = CGRect(
                x: cursor.x - style.size.width / 2,
                y: cursor.y - style.size.height / 2,
                width: style.size.width,
                height: style.size.height
            )
        }
        let target = ScreenGeometry.cocoaRect(fromAX: targetAX, primaryScreenHeight: primaryHeight)

        isShown = true
        generation += 1

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let start = reduceMotion ? target : target.insetBy(
            dx: target.width * (1 - Self.appearScale) / 2,
            dy: target.height * (1 - Self.appearScale) / 2
        )
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.appearDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            if reduceMotion == false { panel.animator().setFrame(target, display: true) }
        }
    }

    func hide() {
        guard isShown, let panel else { return }
        isShown = false
        let hiding = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.disappearDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                // Un nouveau geste a pu rouvrir le panneau pendant le fondu.
                guard self.generation == hiding, self.isShown == false else { return }
                panel.orderOut(nil)
            }
        })
    }

    // MARK: Construction

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: style.size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu // au-dessus du Dock, pour l'aperçu « quitter »
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: PreviewView(model: model, style: style))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        switch style {
        case .hud:
            panel.hasShadow = true
            // Verre dépoli système : suit le mode clair/sombre et « Réduire la
            // transparence » sans rien à gérer.
            let background = NSVisualEffectView()
            background.material = .hudWindow
            background.blendingMode = .behindWindow
            background.state = .active
            background.wantsLayer = true
            background.layer?.cornerRadius = Self.cornerRadius
            background.layer?.cornerCurve = .continuous
            background.layer?.masksToBounds = true
            background.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: background.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            ])
            panel.contentView = background
        case .cursorLight:
            // Ni fond ni cadre : le disque seul, avec une ombre dessinée par
            // la vue (l'ombre de fenêtre suivrait un contenu transparent de
            // façon peu fiable).
            panel.hasShadow = false
            panel.contentView = hosting
        }
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
    let style: PreviewWindow.Style

    var body: some View {
        ZStack {
            content
                // Le libellé sert d'identité : un changement de contenu se
                // fait en fondu enchaîné, pas en saut.
                .id(model.label)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.1), value: model.label)
        .frame(width: style.size.width, height: style.size.height)
        .accessibilityElement()
        .accessibilityLabel(model.label)
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case let .zone(unit):
            MiniScreen(zone: unit, aspect: model.screenAspect)
        case let .light(light):
            switch style {
            case .hud:
                TrafficLightView(light: light, diameter: 72)
            case .cursorLight:
                TrafficLightView(light: light, diameter: PreviewWindow.lightDiameter)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
        case .quitApp:
            switch style {
            case .hud:
                QuitLightView(icon: model.appIcon, diameter: 72, iconSize: 30)
            case .cursorLight:
                QuitLightView(icon: model.appIcon, diameter: PreviewWindow.lightDiameter, iconSize: 16)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
        case .unrecognized:
            Image(systemName: "questionmark")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Le feu rouge, et l'icône de l'app en petit dans son coin bas droit. Le
/// décalage de l'icône suit le diamètre, pour que les proportions tiennent
/// à toutes les tailles.
private struct QuitLightView: View {
    let icon: NSImage?
    let diameter: CGFloat
    let iconSize: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TrafficLightView(light: .close, diameter: diameter)
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .offset(x: diameter * 0.17, y: diameter * 0.14)
            }
        }
        .frame(width: diameter, height: diameter)
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
