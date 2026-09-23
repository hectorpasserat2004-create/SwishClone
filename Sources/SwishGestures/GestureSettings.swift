import Foundation

/// Réglages des gestes, persistés dans `UserDefaults` à chaque changement
/// et lus à chaque geste par les moniteurs et `WindowController` — un
/// changement est donc pris en compte immédiatement, sans relancer l'app.
///
/// Vit dans `SwishGestures` (et non dans l'exécutable) parce que
/// `WindowController` et le code de gestes doivent pouvoir le lire, et
/// qu'une bibliothèque ne peut pas dépendre de l'exécutable qui l'embarque.
///
/// `ObservableObject` plutôt que `@Observable` : ce dernier demande
/// macOS 14, le package cible macOS 13.
///
/// `@MainActor` : lu par les moniteurs (thread principal) et écrit par
/// l'interface SwiftUI. Un consommateur en Swift 6 (bran) l'utilise
/// ainsi sans `@preconcurrency`.
@MainActor
public final class GestureSettings: ObservableObject {

    public static let shared = GestureSettings()

    private enum Key {
        static let swipeThreshold = "com.swishclone.swipeThreshold"
        static let pinchThreshold = "com.swishclone.pinchThreshold"
        static let gestureZoneHeight = "com.swishclone.gestureZoneHeight"
        static let animationDuration = "com.swishclone.animationDuration"
        static let swipeEnabled = "com.swishclone.swipeEnabled"
        static let pinchEnabled = "com.swishclone.pinchEnabled"
    }

    /// Somme cumulée de scroll en dessous de laquelle un swipe est ignoré.
    @Published public var swipeThreshold: Double {
        didSet { defaults.set(swipeThreshold, forKey: Key.swipeThreshold) }
    }

    /// Magnitude de pinch (pic, en valeur absolue) en dessous de laquelle
    /// un pinch est ignoré.
    @Published public var pinchThreshold: Double {
        didSet { defaults.set(pinchThreshold, forKey: Key.pinchThreshold) }
    }

    /// Hauteur, en points, de la zone active en haut de la fenêtre.
    @Published public var gestureZoneHeight: Double {
        didSet { defaults.set(gestureZoneHeight, forKey: Key.gestureZoneHeight) }
    }

    /// Durée, en secondes, de l'animation d'une fenêtre déplacée.
    @Published public var animationDuration: Double {
        didSet { defaults.set(animationDuration, forKey: Key.animationDuration) }
    }

    @Published public var swipeEnabled: Bool {
        didSet { defaults.set(swipeEnabled, forKey: Key.swipeEnabled) }
    }

    @Published public var pinchEnabled: Bool {
        didSet { defaults.set(pinchEnabled, forKey: Key.pinchEnabled) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        // `object(forKey:) as? T ?? défaut` plutôt que `double(forKey:)` :
        // ce dernier renvoie 0 pour une clé absente, ce qui désactiverait
        // silencieusement tous les seuils au premier lancement.
        swipeThreshold = defaults.object(forKey: Key.swipeThreshold) as? Double ?? 20
        pinchThreshold = defaults.object(forKey: Key.pinchThreshold) as? Double ?? 0.1
        gestureZoneHeight = defaults.object(forKey: Key.gestureZoneHeight) as? Double ?? 40
        animationDuration = defaults.object(forKey: Key.animationDuration) as? Double ?? 0.2
        swipeEnabled = defaults.object(forKey: Key.swipeEnabled) as? Bool ?? true
        pinchEnabled = defaults.object(forKey: Key.pinchEnabled) as? Bool ?? true
    }
}
