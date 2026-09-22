public enum Gesture: Equatable {
    case swipe(direction: SwipeDirection, fingers: Int)
    case pinch(direction: PinchDirection, fingers: Int)
    case tap(fingers: Int)
}
