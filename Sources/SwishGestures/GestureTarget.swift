import AppKit
// `AXUIElement` n'est pas annoté `Sendable` par Apple ; `Target` le
// transporte entre le début et la fin d'un geste.
@preconcurrency import ApplicationServices
import SwishCloneCore

/// **La fenêtre sous le curseur**, si le curseur est sur sa barre de titre.
///
/// Remplace `GestureZone`, qui regardait la fenêtre *au premier plan* et
/// vérifiait *à la fin* du geste que le curseur était dans sa bande du haut.
/// Ici, on demande à AX l'élément sous le curseur, on remonte jusqu'à sa
/// fenêtre, et `TitlebarHitTest` (Core, testé) décide. L'appel se fait **une
/// fois, au début du geste** : la fenêtre trouvée est celle sur laquelle le
/// geste agira au lever, même si le curseur a bougé entre-temps.
///
/// La fenêtre visée n'est pas activée : elle peut être en arrière-plan, et
/// le reste (comme le réglage « Activate Window » de Swish, éteint par
/// défaut).
public enum GestureTarget {

    public struct Target: @unchecked Sendable {
        public let window: AXUIElement
        public let pid: pid_t
        /// En coordonnées AX.
        public let frame: CGRect
    }

    /// Délai maximal d'une réponse AX. **Il est global** : AX l'applique à
    /// tous les éléments dès qu'on le pose sur l'élément système. Sans lui,
    /// une app qui ne répond plus bloquerait le test jusqu'à six secondes —
    /// et, une fois le tap actif, tout le défilement du Mac avec lui.
    static let messagingTimeout: Float = 0.1

    /// Profondeur maximale de la remontée vers la fenêtre. Une barre
    /// d'outils est à quelques niveaux ; au-delà, on est dans un contenu.
    static let maxDepth = 25

    /// Le curseur, en coordonnées globales AX (origine en haut à gauche) —
    /// `CGEvent.location` les donne directement, sans conversion.
    @MainActor
    public static func underCursor() -> Target? {
        guard let point = CGEvent(source: nil)?.location else { return nil }
        return hitTest(at: point, zoneHeight: GestureSettings.shared.gestureZoneHeight)
    }

    /// `nonisolated` : n'utilise que des appels AX, sûrs depuis n'importe
    /// quel thread — le tap de l'étape 5 l'appellera depuis le sien.
    public static func hitTest(at point: CGPoint, zoneHeight: Double) -> Target? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)

        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit)
        guard result == .success, let hit else {
            debugLog("pas de cible : aucun élément AX en \(point) (erreur \(result.rawValue))")
            return nil
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success else {
            debugLog("pas de cible : processus de l'élément introuvable")
            return nil
        }
        guard pid != ProcessInfo.processInfo.processIdentifier else {
            debugLog("pas de cible : élément de notre propre app")
            return nil
        }

        var path: [AXNodeInfo] = []
        var current = hit
        for _ in 0 ..< maxDepth {
            let info = nodeInfo(current)
            if info.role == kAXWindowRole as String {
                guard let frame = WindowController.frame(of: current) else {
                    debugLog("pas de cible : cadre de la fenêtre illisible (chemin \(path.compactMap(\.role)))")
                    return nil
                }
                let verdict = TitlebarHitTest.evaluate(
                    path: path,
                    window: info,
                    windowFrame: frame,
                    point: point,
                    zoneHeight: zoneHeight
                )
                guard verdict == .titlebar else {
                    debugLog("pas de cible : \(verdict) (chemin \(path.compactMap(\.role)), fenêtre \(info.subrole ?? "sans sous-rôle"))")
                    return nil
                }
                debugLog("cible : fenêtre \(info.subrole ?? "sans sous-rôle") \(frame) (chemin \(path.compactMap(\.role)))")
                return Target(window: current, pid: pid, frame: frame)
            }
            path.append(info)
            guard let parent = element(current, kAXParentAttribute) else {
                debugLog("pas de cible : aucune fenêtre au-dessus de l'élément (chemin \(path.compactMap(\.role)))")
                return nil
            }
            current = parent
        }
        debugLog("pas de cible : fenêtre introuvable à moins de \(maxDepth) niveaux")
        return nil
    }

    private static func nodeInfo(_ element: AXUIElement) -> AXNodeInfo {
        AXNodeInfo(
            role: string(element, kAXRoleAttribute),
            subrole: string(element, kAXSubroleAttribute)
        )
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func debugLog(_ message: @autoclosure () -> String) {
        if GestureClassifier.debugLoggingEnabled {
            print("[GestureTarget] \(message())")
        }
    }
}
