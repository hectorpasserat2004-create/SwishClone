/// Classification pure d'un geste à partir des positions de doigts.
/// Aucune dépendance à AppKit : entièrement testable avec de simples valeurs.
public enum GestureClassifier {

    /// Active les logs de diagnostic ajoutés pendant la mise au point de la
    /// détection de gestes (session de touches, pinch). Verbeux — à ne
    /// réactiver que ponctuellement en cas de régression.
    public static let debugLoggingEnabled = false

    /// En dessous de cette distance (coordonnées normalisées 0...1),
    /// le déplacement du centre est considéré comme un tap plutôt qu'un swipe.
    public static let defaultTapThreshold: Double = 0.05

    /// En dessous de cette variation RELATIVE de l'écartement moyen entre
    /// les doigts (spreadDelta / startSpread), le signal pinch n'est pas
    /// considéré comme actif. 0.15 = 15% de variation.
    ///
    /// Séparé en deux seuils (out/in) plutôt qu'un seul symétrique : écarter
    /// les doigts a naturellement plus d'amplitude que les resserrer (ils
    /// sont souvent déjà proches au repos), un seuil unique sous-calibre
    /// donc systématiquement un des deux sens. À calibrer sur des essais
    /// réels séparés par direction.
    public static let defaultPinchOutThreshold: Double = 0.15
    public static let defaultPinchInThreshold: Double = 0.15

    public static func classify(
        startPositions: [FingerPosition],
        endPositions: [FingerPosition],
        fingerCount: Int,
        tapThreshold: Double = defaultTapThreshold,
        pinchOutThreshold: Double = defaultPinchOutThreshold,
        pinchInThreshold: Double = defaultPinchInThreshold
    ) -> Gesture {
        let startCenter = center(of: startPositions)
        let endCenter = center(of: endPositions)
        let centerDisplacement = distance(startCenter, endCenter)

        let startSpread = averagePairwiseDistance(startPositions)
        let endSpread = averagePairwiseDistance(endPositions)
        let spreadDelta = endSpread - startSpread
        // startSpread ne peut être 0 que si on a moins de 2 doigts, auquel
        // cas un pinch n'a de toute façon aucun sens : on l'exclut alors
        // du calcul plutôt que de diviser par zéro.
        let relativeSpreadChange = startSpread > 0 ? spreadDelta / startSpread : 0

        // Un vrai swipe humain fait toujours un peu varier l'écartement des
        // doigts, et un vrai pinch déplace toujours un peu le centre — les
        // deux signaux ne sont donc jamais parfaitement purs. Au lieu de
        // tester leurs seuils indépendamment (le premier qui passe gagne,
        // ce qui laissait un léger écartement voler la classification à un
        // swipe évident), on calcule pour chacun un score sans dimension —
        // "de combien il dépasse son propre seuil de détection" — et c'est
        // le signal proportionnellement le plus significatif qui l'emporte.
        let pinchThreshold = relativeSpreadChange >= 0 ? pinchOutThreshold : pinchInThreshold
        let pinchScore = pinchThreshold > 0 ? abs(relativeSpreadChange) / pinchThreshold : 0
        let swipeScore = tapThreshold > 0 ? centerDisplacement / tapThreshold : 0

        let gesture: Gesture
        let reason: String

        if pinchScore >= 1 && pinchScore >= swipeScore {
            let direction: PinchDirection = relativeSpreadChange > 0 ? .out : .in_
            gesture = .pinch(direction: direction, fingers: fingerCount)
            reason = "pinch retenu : pinchScore (\(pinchScore)) >= 1 et >= swipeScore (\(swipeScore))"
        } else if swipeScore >= 1 {
            let dx = endCenter.x - startCenter.x
            let dy = endCenter.y - startCenter.y
            let direction: SwipeDirection
            if abs(dx) > abs(dy) {
                direction = dx > 0 ? .right : .left
            } else {
                direction = dy > 0 ? .up : .down
            }
            gesture = .swipe(direction: direction, fingers: fingerCount)
            reason = "swipe retenu : swipeScore (\(swipeScore)) >= 1"
                + (pinchScore >= 1 ? " et > pinchScore (\(pinchScore))" : " (pinchScore \(pinchScore) < 1)")
        } else {
            gesture = .tap(fingers: fingerCount)
            reason = "tap retenu : pinchScore (\(pinchScore)) < 1 et swipeScore (\(swipeScore)) < 1"
        }

        if debugLoggingEnabled {
            print("""
            [DEBUG classify] fingers=\(fingerCount) \
            startSpread=\(startSpread) endSpread=\(endSpread) spreadDelta=\(spreadDelta) \
            relativeSpreadChange=\(relativeSpreadChange) \
            centerDisplacement=\(centerDisplacement) \
            tapThreshold=\(tapThreshold) pinchOutThreshold=\(pinchOutThreshold) pinchInThreshold=\(pinchInThreshold) \
            pinchScore=\(pinchScore) swipeScore=\(swipeScore) \
            -> \(gesture) (\(reason))
            """)
        }

        return gesture
    }

    private static func center(of positions: [FingerPosition]) -> FingerPosition {
        guard !positions.isEmpty else { return FingerPosition(x: 0, y: 0) }
        let count = Double(positions.count)
        let sumX = positions.reduce(0) { $0 + $1.x }
        let sumY = positions.reduce(0) { $0 + $1.y }
        return FingerPosition(x: sumX / count, y: sumY / count)
    }

    private static func distance(_ a: FingerPosition, _ b: FingerPosition) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Moyenne des distances entre chaque paire de doigts — représente
    /// l'écartement global de la main, indépendamment de sa position.
    private static func averagePairwiseDistance(_ positions: [FingerPosition]) -> Double {
        guard positions.count >= 2 else { return 0 }
        var total = 0.0
        var pairCount = 0
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                total += distance(positions[i], positions[j])
                pairCount += 1
            }
        }
        return total / Double(pairCount)
    }
}
