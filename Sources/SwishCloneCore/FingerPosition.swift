/// Position d'un doigt sur la surface tactile, normalisée entre 0 et 1
/// (0,0 = coin bas-gauche, 1,1 = coin haut-droit), indépendamment
/// de la résolution physique du trackpad.
public struct FingerPosition: Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
