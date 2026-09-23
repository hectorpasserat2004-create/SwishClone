import Cocoa

// En Swift 5, le code de premier niveau n'est pas isolé sur l'acteur
// principal — il tourne pourtant sur le thread principal, et
// `AppDelegate` l'exige. `app.run()` ne rend la main qu'à la sortie :
// `delegate` (référence faible côté `NSApplication`) vit donc assez.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
