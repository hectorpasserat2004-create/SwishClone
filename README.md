# SwishClone

Utilitaire d'arrière-plan macOS qui contrôle les fenêtres au trackpad :
swipe/pinch pour déplacer, redimensionner, maximiser ou minimiser la
fenêtre active — inspiré de Swish.

## Structure
- `Sources/SwishCloneCore/` — logique pure, sans AppKit, testable en isolation :
  types de gestes (`FingerPosition`, `SwipeDirection`, `PinchDirection`,
  `Gesture`) et `GestureClassifier`, qui transforme des positions de doigts
  en geste détecté.
- `Sources/SwishClone/` — l'app macOS :
  - `TouchGestureView` capte les événements multi-touch du trackpad
    (`NSEvent.touches`) et délègue la classification au Core.
  - `WindowController` contrôle les fenêtres externes via l'Accessibility
    API (`AXUIElement`) et mappe chaque geste détecté vers une action.
  - `AppDelegate` fait tourner l'app en arrière-plan (icône menu bar, pas
    de Dock) et branche le tout.
- `Tests/SwishCloneCoreTests/` — tests unitaires sur le module core
  uniquement (classification de gestes).

## Commandes

Compiler :
```
swift build
```

Lancer l'app :
```
swift run
```

Lancer les tests unitaires :
```
swift test
```

## Prérequis
- Xcode Command Line Tools installés (`xcode-select --install`)
- Pas besoin de l'app Xcode complète
- Permission Accessibility accordée à l'app pour que le contrôle de
  fenêtres fonctionne (voir plus bas)

## État d'avancement

### Phase 1 — Détection de gestes ✅
Capture des événements trackpad (`NSEvent.touches`) et classification pure
côté Core : swipe (4 directions, tout nombre de doigts), pinch (in/out,
détecté via la variation relative de l'écartement moyen entre les doigts),
tap. Testé manuellement sur trackpad réel, seuils calibrés en conditions
réelles (voir `GestureClassifier.defaultTapThreshold` /
`defaultPinchThreshold`).

### Phase 2 — App d'arrière-plan ✅
`NSApp.setActivationPolicy(.accessory)` : pas d'icône Dock, pas de fenêtre
au lancement. Icône dans la menu bar (SF Symbol `hand.draw`) avec un menu :
afficher/cacher la fenêtre de test, quitter. Fermer la fenêtre de test ne
quitte plus l'app.

### Phase 3 — Contrôle de fenêtres (Accessibility API) ✅
`WindowController` : vérification/demande de la permission Accessibility
(`AXIsProcessTrusted(WithOptions:)`), lecture de la fenêtre au premier plan
de n'importe quelle app (`AXUIElement`), lecture et écriture de sa
position/taille.

### Phase 4 — Mapping gestes → actions ✅
Les gestes détectés déclenchent de vraies actions sur la fenêtre au
premier plan (jamais notre propre fenêtre de test, explicitement exclue) :
- swipe gauche/droite → moitié gauche/droite de l'écran
- swipe haut ou pinch out → plein écran
- swipe bas → minimise (`AXMinimizedAttribute` — fonctionne pour la
  plupart des apps AppKit standard, pas garanti pour toutes)
- pinch in → centre la fenêtre à ~60% de la taille de l'écran

Un cooldown de 300ms entre deux actions évite qu'un geste se ré-applique
en double si le classifieur ré-émet un résultat très rapidement.

Testé manuellement de bout en bout : geste sur le trackpad → action
visible sur une fenêtre d'une autre app.

### Logs de diagnostic
Des logs verbeux (`[DEBUG session]`, `[DEBUG classify]`) ont servi à
diagnostiquer plusieurs bugs de calibration et de tracking de session.
Ils sont désactivés par défaut mais gardés dans le code, dernière
`GestureClassifier.debugLoggingEnabled` : passer cette constante à `true`
et recompiler les réactive dans les deux modules.

## Accorder la permission Accessibility
1. `swift run`.
2. Depuis le menu de l'icône dans la menu bar, déclenche une action sur
   une fenêtre (ou utilise "Coller fenêtre active à gauche"). macOS ouvre
   Réglages Système > Confidentialité et sécurité > Accessibilité.
3. Active le toggle pour l'app, relance le geste.
