public enum SwipeDirection: Equatable, Sendable {
    case left
    case right
    case up
    case down

    /// **Les diagonales** : un seul mouvement qui règle les deux axes à la
    /// fois — le quart, sans marquer de pause entre ↑ et →.
    case upLeft
    case upRight
    case downLeft
    case downRight

    /// La composante horizontale (`.left` ou `.right`), `nil` pour ↑ et ↓.
    public var horizontal: SwipeDirection? {
        switch self {
        case .left, .upLeft, .downLeft: return .left
        case .right, .upRight, .downRight: return .right
        case .up, .down: return nil
        }
    }

    /// La composante verticale (`.up` ou `.down`), `nil` pour ← et →.
    public var vertical: SwipeDirection? {
        switch self {
        case .up, .upLeft, .upRight: return .up
        case .down, .downLeft, .downRight: return .down
        case .left, .right: return nil
        }
    }

    public var isDiagonal: Bool { horizontal != nil && vertical != nil }
}
