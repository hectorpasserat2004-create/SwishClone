// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwishClone",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Exposés pour être consommés comme dépendance par un autre
        // Swift Package (ex. l'app d'un autre projet qui veut réutiliser
        // la détection de gestes et le contrôle de fenêtres).
        .library(name: "SwishCloneCore", targets: ["SwishCloneCore"]),
        .library(name: "SwishGestures", targets: ["SwishGestures"])
    ],
    targets: [
        // Logique pure, sans AppKit : classification de gestes.
        // Facilement testable en isolation.
        .target(
            name: "SwishCloneCore",
            path: "Sources/SwishCloneCore"
        ),

        // Capture des événements trackpad (TouchGestureView) et contrôle
        // de fenêtres externes via l'Accessibility API (WindowController).
        // Dépend d'AppKit / ApplicationServices, mais pas de l'app hôte :
        // réutilisable telle quelle par un autre projet.
        .target(
            name: "SwishGestures",
            dependencies: ["SwishCloneCore"],
            path: "Sources/SwishGestures"
        ),

        // L'app macOS de test autonome : juste une fenêtre + une icône
        // menu bar pour exercer SwishGestures manuellement.
        .executableTarget(
            name: "SwishClone",
            dependencies: ["SwishCloneCore", "SwishGestures"],
            path: "Sources/SwishClone"
        ),

        // Tests unitaires — uniquement sur SwishCloneCore, jamais
        // besoin d'un vrai trackpad pour les faire passer.
        .testTarget(
            name: "SwishCloneCoreTests",
            dependencies: ["SwishCloneCore"],
            path: "Tests/SwishCloneCoreTests"
        ),

        // Le thread du tap, son moteur et le pont vers le thread principal :
        // tout ce qui se teste sans permission ni tap réel.
        .testTarget(
            name: "SwishGesturesTests",
            dependencies: ["SwishGestures", "SwishCloneCore"],
            path: "Tests/SwishGesturesTests"
        )
    ]
)
