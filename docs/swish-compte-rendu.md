# Swish (Highly Opinionated) : compte rendu pour un recodage (SwishClone)

Recherche du 23/09/2026. Version de référence : **Swish 1.13.3** (build 80), la dernière publiée.

**Légende de fiabilité**
- **[Confirmé]** : dit par une source publique citée (site, changelog officiel, capture d'écran officielle, page Setapp), ou lu tel quel dans le paquet de l'app distribué publiquement : textes d'interface, `Info.plist`, symboles importés.
- **[Binaire]** : déduit des chaînes et symboles de `Swish.app` 1.13.3. Le DMG a été téléchargé depuis le lien officiel et inspecté avec `strings`, `nm` et `otool`, sans être installé ni lancé. Le symbole existe bien, mais son usage exact reste une interprétation.
- **[Déduit]** / **[Incertain]** : mon raisonnement, sans source directe.

---

## 1. Résumé

- Swish est un gestionnaire de fenêtres **à gestes** pour macOS, écrit par **Christian Renninger** (Highly Opinionated, depuis 2019). Le site annonce « 30 gestes » pour les fenêtres, le Dock et la barre de menus ; Setapp en annonce 28. [Confirmé : site, Setapp]
- Tous les gestes trackpad se font **à deux doigts** : swipe, pinch, double tap, et « tap, hold » (poser, maintenir puis enchaîner). [Confirmé : Setapp « intuitive two-finger moves », textes de l'app « Double tap with two fingers », « Tap and hold with two fingers »]
- **Zones** : barre de titre ou barre d'outils des fenêtres, icônes du Dock, menu de l'app (à côté du  dans la barre de menus), zone vide de la barre de menus, fenêtres dans Mission Control et App Exposé, aperçus des Spaces dans Mission Control. Un « **Super Modifier** » (fn par défaut) permet de faire les gestes n'importe où sur la fenêtre. [Confirmé]
- **Modificateurs** : General (⌃), Screen (⌘), Secondary (⇧), Tertiary (⇧⌥) et Super (fn). Ce sont les valeurs visibles sur les captures officielles, donc très probablement les valeurs par défaut. [Confirmé : captures ; « défaut » = Déduit]
- **Aimantation (snapping)** : moitiés, moitiés haut/bas, quarts, tiers et deux-tiers, sixièmes, grille 3×3 (neuvièmes), « Maximize » ou « Almost Maximize », « Center ». Un geste peut **s'enchaîner** : on marque une pause jusqu'au retour haptique, puis on continue sans lever les doigts. [Confirmé]
- **Retour visuel** : une infobulle (« tooltip ») montre l'action prévue. Depuis la 1.8, une option « live tooltip » affiche aussi un aperçu animé, translucide et à taille réelle de la fenêtre cible. Le geste se déclenche **quand on lève les doigts** ; on l'annule avec Échap ou en restant immobile pendant le « Cancel Timeout » (0,8 s sur la capture). [Confirmé]
- **Technique** : Swift, AppKit et un peu de SwiftUI, API Accessibility (AXUIElement, AXObserver), `CGEventTap`, quelques API privées CoreGraphics/SkyLight (`CGSCopyManagedDisplaySpaces`, `_AXUIElementGetWindow`, `CGSSetConnectionProperty`). Le binaire **ne lie pas MultitouchSupport.framework**. Il dépend des gestes système (« Zoom in or out » et « Smart zoom » doivent être activés), ce qui laisse penser qu'il lit les événements de haut niveau (scroll, magnify, smart magnify) et non les contacts bruts. [Binaire + Confirmé pour les prérequis]
- **Distribution** : hors Mac App Store, car Swish ne peut pas être sandboxé. Licence de 16 $ via Paddle (deux Mac), essai de 14 jours, disponible aussi sur Setapp. macOS 12 minimum, binaire universel Intel et Apple Silicon. [Confirmé]

---

## 2. Catalogue complet des gestes

Notation : ↑↓←→ = swipe à deux doigts ; « pinch in/out » = pincer ou écarter ; « double tap » = double tap à deux doigts ; « tap-hold » = poser deux doigts, attendre, puis continuer. G, S, 2, 3 = modificateurs General, Screen, Secondary et Tertiary. La colonne « Alternative » reprend le second pictogramme affiché dans les réglages.
Sources : captures officielles `screenshot-2` à `screenshot-6` sur https://highlyopinionated.co/swish/, textes d'interface du binaire 1.13.3 et changelog officiel.

### 2.1 Onglet « Windows », barre de titre d'une fenêtre (« Control basic functionality by swiping and pinching on window titlebars »)

| Geste | Alternative | Action | Statut |
|---|---|---|---|
| Pinch in ×2 | G + ↓↓ (ou G + tap-hold puis ↓) | **Quit** : quitter l'application | Confirmé (capture + chaîne « Alternatively, while holding the general modifier, swipe down twice or tap, hold and swipe down once. ») |
| Pinch in ×1 | G + ↓ | **Close** : fermer la fenêtre | Confirmé |
| ↓ ×1 | tap-hold puis ↓ (en plein écran) | **Minimize** : réduire dans le Dock. En plein écran, il faut un tap-hold avant de swiper vers le bas pour éviter les accidents | Confirmé (capture + « In fullscreen mode, tap and hold before swiping down. ») |
| Pinch out | tap-hold puis ↑, ou G + ↑ | **Fullscreen** : entrer dans le plein écran natif ou en sortir | Confirmé |
| G + double tap | 2 + double tap | **Hide** : masquer l'app (⌘H) ; avec Secondary, masquer les autres apps | Confirmé |
| tap-hold puis ←/→ | G + ←/→ | **Spaces** : déplacer la fenêtre vers le Space (bureau Mission Control) voisin | Confirmé |

Une note d'interface précise : « Most Window and Snapping gestures also work in Mission Control & App Exposé. » [Confirmé : nib WindowsTab]

### 2.2 « Tabs », onglets natifs (Finder, Safari, et navigateurs pris en charge un par un)

| Geste | Alternative | Action | Statut |
|---|---|---|---|
| tap-hold sur un onglet | — | **Detach** : détacher l'onglet dans une nouvelle fenêtre, puis enchaîner n'importe quel autre geste (par exemple l'aimanter) | Confirmé |
| Pinch in sur un onglet | ↓ + G | **Close** : fermer l'onglet | Confirmé |

Apps prises en charge d'après le changelog : Safari, Finder, Chrome (y compris les onglets verticaux), Brave, Arc, Dia, Orion, Firefox (depuis la 1.13.1), VS Code, Xcode, UPDF. Edge n'est plus pris en charge depuis la 1.13. [Confirmé : changelog]

### 2.3 « Screens », multi-écrans

| Geste | Alternative | Action | Statut |
|---|---|---|---|
| S + ←↑↓→ | — | Déplacer la fenêtre vers l'écran suivant dans cette direction, selon la disposition physique des écrans | Confirmé |
| Pinch out ×2 | S + pinch out | Avec deux écrans : passer directement en plein écran **sur l'autre écran** | Confirmé |

### 2.4 « Snapping », barre de titre (« Snap windows to a 2×2, 2×3 or 3×3 grid. Unsnap by either dragging or via Swish's gestures. »)

| Geste | Action | Statut |
|---|---|---|
| double tap | **Center** : désaimanter et centrer. On peut régler séparément « Center » et/ou « Unsnap » (1.8) | Confirmé |
| ↑ ×1 | **Maximize** : « fill the entire desktop area ». Variante réglable « Almost Maximize » : « fill almost the entire desktop area » | Confirmé |
| ← / → | **Halves** : moitié gauche ou droite | Confirmé |
| ↑↑ / ↓↓ (double swipe vertical) | **Vertical** : moitié haute ou basse | Confirmé |
| swipe horizontal + vertical (dans n'importe quel ordre, enchaînés) | **Quarters** : « Swipe horizontally and vertically to snap to a quarter. Both orders work. » Setapp : « position a window in the lower right corner? just swipe down and right » | Confirmé (binaire + Setapp) |
| 2 + ← / → | **Thirds** (grille 3×2) : « Swipe horizontally to switch between thirds and two-thirds. Tap and hold to access the middle third directly. » | Confirmé (texte) ; que le modificateur 2 soit requis est **Déduit** de l'onglet Advanced (« unlock secondary (2×3 snapping…) ») |
| 2 + ← / → puis ↑ / ↓ | **Sixths** : « In addition, swipe vertically to access the upper and lower halves of those thirds. » / « You can still access the upper sixth by swiping up twice. » | Confirmé (texte) |
| 3 + swipes | **Ninths** (grille 3×3) : « Swipe to access ninths, two-ninths and four-ninths in a 3×3 grid » | Confirmé (texte, la fin de la chaîne est tronquée dans le binaire) |

Remarques confirmées :
- La 1.1 a changé le comportement : un simple swipe horizontal donne directement un tiers, et « tap, hold and swipe » donne directement les deux-tiers. Le texte actuel dit plutôt « switch between thirds and two-thirds » et « tap-hold = tiers central ». Le mapping exact a donc évolué ; se fier au texte 1.13.3 cité plus haut.
- Sur un écran en orientation verticale, les tiers et les sixièmes s'adaptent (1.8), et les axes X et Y sont inversés (« On vertical screen orientations, the X and Y axes are inverted. »).
- Pour répéter une direction (par exemple ↑↑) : « pause your finger movement momentarily (until you feel haptic feedback) and then continue the motion without lifting » (FAQ). Un geste complet se termine quand on lève les doigts.

### 2.5 Onglet « Apps », icône du Dock **ou** menu de l'app dans la barre de menus

« Control running applications by swiping and pinching on their dock icon or menubar menu. » Autre texte : « You can also invoke gestures on the app's menu, right next to the  symbol. » (option « Application Menu », case `appMenuCheckbox`).

| Geste | Alternative | Action | Statut |
|---|---|---|---|
| tap-hold | — | **Activate** : activer la fenêtre de premier plan de l'app et l'« enchaîner », pour appliquer ensuite n'importe quel geste de fenêtre | Confirmé |
| ← / → | — | **Cycle** : activer et enchaîner les fenêtres de l'app, dans un sens ou dans l'autre | Confirmé |
| Pinch in | G + ↓ | **Quit** : quitter l'app | Confirmé |
| ↓ | 2 + ↓ | **Minimize** : réduire la fenêtre de premier plan ; avec 2, toutes les fenêtres. Autre texte : « Alternatively, pinch in twice to minimize all windows. » | Confirmé |
| ↑ | 2 + ↑ | **Unminimize** : restaurer et enchaîner la dernière fenêtre ; avec 2, toutes. Autre texte : « pinch out twice to unminimize all windows » | Confirmé |
| double tap | 2 + double tap | **Hide** : masquer l'app ; avec 2, masquer les autres | Confirmé |
| Pinch out | G + ↑ | **New Tab** : ouvrir un nouvel onglet ou une nouvelle fenêtre (⌘N) | Confirmé |

Le **Super Modifier** permet aussi d'appliquer les gestes *de fenêtre* directement sur une icône du Dock (1.7). [Confirmé]

### 2.6 Onglet « Menubar », zone **vide** de la barre de menus (« Invoke global convenience functions on the empty menubar area »)

| Geste | Alternative | Action | Statut |
|---|---|---|---|
| tap-hold puis scroll | ← / → | **App Switcher** : ouvrir le sélecteur ⌘-Tab ; un swipe ←/→ active directement l'app précédente ou suivante | Confirmé |
| double tap | 2 + double tap | **Unsnap** : désaimanter toutes les fenêtres de l'écran courant ; avec 2, de tous les écrans | Confirmé |
| ↓ | 2 + ↓ (ou ↓↓) | **Minimize all** : écran courant ; deux fois ou avec 2, tous les écrans | Confirmé |
| ↑ | 2 + ↑ (ou ↑↑) | **Unminimize all** : même logique | Confirmé |
| S + ←↑↓→ | — | **Screens** : déplacer toutes les fenêtres aimantées vers l'écran suivant | Confirmé |

### 2.7 « Mission Control » (section du même onglet)

| Geste | Action | Statut |
|---|---|---|
| S + ←↑↓→ sur l'aperçu d'un Space dans Mission Control | Déplacer un Space (bureau ou app en plein écran) vers l'écran voisin (1.9). Avec la 1.13.3, **ne fonctionne pas sous macOS 27** à cause d'un bug d'Apple | Confirmé (texte + changelog) |

### 2.8 Gestes retirés (historique)
- « Scroll To Top », retiré en 1.2 parce qu'il n'était pas fiable. [Confirmé : changelog] (la clé `menubarScrollToTop` existe encore dans le binaire)

### 2.9 Clavier (pas un geste, mais fait partie de la même logique)
- « Arrow Hotkeys » : Super Modifier + flèches, WASD, IJKL, HJKL (Vim) ou Dvorak (,AOE) pour tous les gestes d'aimantation, d'écrans et de Spaces. Retour arrière (ou X) pour centrer et désaimanter. [Confirmé : Advanced + changelog 1.7, 1.7.1, 1.8.1]
- Magic Mouse : « swiping and double-tapping in conjunction with modifier keys » ; tout fonctionne sauf le tap-hold (Setapp). Option « Disable Magic Mouse (Beta) ». Souris tierces : via Mac Mouse Fix. [Confirmé]

---

## 3. Zones d'activation et modes

| Zone | Détail | Statut |
|---|---|---|
| Barre de titre / barre d'outils | « safe area » pour ne pas gêner le scroll et le zoom du système. Élargie aux barres d'outils non natives (1.1). Hauteur choisie par élément AX : chaînes « Origin: Default height used for » / « Origin: Special height », ce qui fait penser à une hauteur par défaut et à des cas spéciaux par app | Confirmé ; hauteur par app = **Binaire/Déduit** |
| Fenêtre entière | avec le Super Modifier (fn) ; option « Require Super Modifier for all gestures » (1.8, `requireSuperModCheckbox`) | Confirmé |
| Icône du Dock | gestes d'app ; le type d'élément du Dock est distingué (`AXApplicationDockItem`, `AXMinimizedWindowDockItem`, `AXFolderDockItem`, `AXTrashDockItem`, `AXSeparatorDockItem`) | Confirmé + Binaire |
| Menu de l'app (barre de menus, à côté de ) | mêmes gestes que le Dock (1.1) | Confirmé |
| Zone vide de la barre de menus | gestes globaux ; fonctionne aussi sur les écrans non actifs (1.2) | Confirmé |
| Mission Control / App Exposé | gestes de fenêtre sur les vignettes (1.4, 1.7) ; déplacement des Spaces | Confirmé |
| Exclusions automatiques | popovers et fenêtres PiP bloqués ; curseurs défilants dans les barres d'outils (Music.app, 1.11) ; éléments HTML d'onglets et vignettes PDF dans Chromium (1.10.2) ; barre d'onglets défilante de Firefox (1.13.2) ; toute zone où une barre de défilement est détectée via AX (FAQ Firefox) | Confirmé |

**« Modes »** : il n'existe pas de modes « Windows »/« Menubar » exclusifs. Ce sont des **onglets de réglages** qui correspondent chacun à une zone : General, Windows, Snapping, Apps, Menubar, Advanced, About. [Confirmé : captures]

**Modificateurs** (onglet Advanced) : Super `fn`, General `⌃`, Screen `⌘`, Secondary `⇧`, Tertiary `⇧⌥`. Texte : « Perform general functions (fullscreen, closing, spaces, etc.), invoke multi-screen actions, unlock secondary (2×3 snapping, all windows, etc.) and tertiary (3×3 snapping) functionality. » On définit un modificateur en appuyant sur les touches dans un popover (1.5). Les modificateurs fonctionnent même avec Verr. Maj activé (1.9). [Confirmé]

**Chaînage** : après Activate, Detach, Cycle, Unminimize, etc., la fenêtre est « chainée », c'est-à-dire que le geste suivant (sans lever les doigts, ou juste après) s'applique à elle. [Confirmé : textes]

---

## 4. Réglages et préférences

Fenêtre à barre latérale : **General / Windows / Snapping / Apps / Menubar / Advanced / About**, avec un bouton « Quit » en haut à droite. On active ou désactive chaque geste en cliquant sur son icône. Le survol d'une description affiche des détails (1.7). Il y a un tutoriel (« Show Tutorial ») et un onboarding. [Confirmé]

| Onglet | Réglage | Valeur visible / défaut | Statut |
|---|---|---|---|
| General › System | System Permissions (pastille verte ou rouge) | — | Confirmé |
| | Launch at Login | coché | Confirmé (capture) |
| | Show in Menubar | coché (« You can always access this window by clicking the app icon ») | Confirmé |
| General › Gestures | Haptic Feedback | coché (« if enabled via system preferences ») | Confirmé |
| | Touch Sensitivity (curseur, 4 niveaux depuis la 1.8.1) | « Really Snappy » sur la capture | Confirmé ; valeur par défaut **Incertaine** |
| | Cancel Timeout (curseur) | 0,8 s | Confirmé (capture) |
| General (probable) | Tooltips : activer, « Live » (aperçu à taille réelle), taille (curseur), masquer le curseur pendant l'infobulle, durée d'animation | — | **Binaire** (`tooltipEnableCheckbox`, `tooltipLiveCheckbox`, `tooltipSizeSlider`, `hideCursorCheckbox`, `tooltipAnimationTime`) + changelog 1.2/1.8 ; emplacement **Incertain** |
| General (probable) | Tap & Hold, Mission Control, App Menu (interrupteurs ajoutés en 1.8) | — | Confirmé (changelog), `tapHoldCheckbox`, `missionControlCheckbox`, `appMenuCheckbox` |
| Windows | General Modifier ⌃, Screen Modifier ⌘ | | Confirmé |
| Snapping | Grid Spacing (curseur, « Default ») : marge entre les fenêtres et les bords de l'écran. « Default » correspond à un décalage par défaut ; les décalages impairs et l'exclusion des bords de l'écran sont gérés (1.1) | Default | Confirmé |
| | Drag to Unsnap | coché ; Secondary désactive temporairement | Confirmé |
| | Activate Window | décoché | Confirmé |
| | Move Cursor (déplace le curseur avec la fenêtre) | décoché | Confirmé ; il existe aussi `screensMoveCursor` et `snappingMovingMoveCursor` (Binaire) |
| | Resize Adjacent Windows (faire glisser le séparateur pour redimensionner plusieurs fenêtres) | coché | Confirmé |
| | Native tiling (« Use macOS Sequoia's native window tiling for 2×2 snapping », 1.11) + popover qui reflète « System Settings › Desktop & Dock › Windows › Drag Windows to Edge » | — | Confirmé + Binaire (`EnableTilingByEdgeDrag`) |
| | Stage Manager : détection automatique + curseur de décalage pour la zone des apps récentes (1.12) | — | Confirmé |
| | Center action : Center et/ou Unsnap (1.8) | — | Confirmé |
| | Re-snap après branchement ou débranchement d'un écran : activable (1.6), délai exposé (1.1, `screenChangeTimeout`) | — | Confirmé |
| Apps | General ⌃, Secondary ⇧, case Application Menu | | Confirmé |
| Menubar | Secondary ⇧, Screens ⌘, section Mission Control | | Confirmé |
| Advanced › Keyboard | Super fn / General ⌃ / Screen ⌘ / Secondary ⇧ / Tertiary ⇧⌥ ; Arrow Hotkeys (coché, choix de disposition) ; les raccourcis flèches et Center sont indépendants (1.8) | | Confirmé |
| Advanced › Event Listener | Active Event Listener (coché) : « Swish can block scroll, flick and pinch events in the underlying window during gestures » | coché | Confirmé |
| Advanced | Disable Magic Mouse (Beta) | — | Binaire (nib) |
| Advanced (probable) | Mises à jour : bêta opt-in (1.7), diagnostics (1.8), « Restore all settings » (1.8) | — | Confirmé (changelog) |
| About | licence : activer ou délier | — | Confirmé |

Réglages accessibles depuis le **menubarlet** : état des permissions, « Ignoring "App" » (ignorer l'app active), compteur « N Swishes », « Fix Pinch & Swipe » (aussi en raccourci clavier), activer ou désactiver Stage Manager, Restart, Settings, Quit. [Binaire (MainMenu.nib) + Confirmé (FAQ Firefox « ignore via menubarlet », changelog 1.9 et 1.10)]

Clés de préférences visibles dans le binaire, utiles pour s'inspirer du schéma de données : `snappingNativeTiling`, `snappingStageManagerOffset`, `snappingDragUnsnap`, `snappingResizeAdjacent`, `snappingCenterAction`, `snappingMoveCursor`, `snappingActivateWindow`, `screensMoveCursor`, `screensChainGesture`, `originMissionControl`, `scrollingSensitivity`, `tooltipHideCursor`, `tooltipAnimationTime`, `gestureTimeout`, `cancelTimeout`, `screenChangeTimeout`. Identifiants d'actions : `windowQuit/Close/Minimize/Fullscreen/Hide`, `screensMove/Fullscreen`, `spacesMove`, `appChain/Cycle/Quit/Minimize/Unminimize/Hide/NewTab`, `menubarUnsnap/Minimize/Unminimize/Screens/AppSwitcher`, `missionControlSpace`, `ActionSnapHalves/Vertical/Quarters/Thirds/Sixths/Ninths/Almost/Unsnap`, `snappingState2x3/3x2/3x3`. [Binaire]

---

## 5. Retours visuels

- **Tooltip / bezel** : petite fenêtre flottante sous le curseur qui dessine la forme de la position cible, par exemple un rectangle à moitié rempli pour « moitié droite ». Elle apparaît pendant le geste, qui ne s'applique qu'au lever des doigts. [Confirmé : Digital Trends via les résultats de recherche, « You will see a small tool tip appear showing a half-filled rectangle; lift your fingers… »] Classes `TooltipWindow`, `BezelWindow`, `ScreensTooltipWindow`, `SpacesTooltipWindow`, flèches `TooltipArrowLeft/Right/Down`. [Binaire]
- **Live tooltip** (1.8) : « full-size animated and translucent preview » de la fenêtre à sa destination, en plus de l'infobulle (`LiveTooltipWindow`). Animation plus fluide en 1.10.4 et 1.11. [Confirmé]
- Thème clair ou sombre selon l'apparence (1.7), avec prise en compte de « Reduce transparency » (1.5). Tailles réglables ; les deux plus grandes et le monochrome ont été retirés en 1.1. [Confirmé]
- **Curseur masqué** pendant l'infobulle (option, 1.2 ; peut gêner Sidecar). Probablement via `CGSSetConnectionProperty(…"SetsCursorInBackground"…)`, l'astuce connue pour masquer le curseur depuis une app en arrière-plan. [Binaire + Déduit]
- **Retour haptique** au franchissement d'une étape ou de la confirmation, qui sert aussi de repère pour enchaîner les directions. [Confirmé : FAQ]
- Onboarding : il faut que Swish soit bien dans les Login Items pour que les infobulles s'affichent (« To display tooltips, Swish needs to be added to Login Items correctly »). [Binaire]
- Icône dans la barre de menus (menubarlet), qu'on peut masquer (« Show in Menubar »). [Confirmé]
- Déplacement des fenêtres : la 1.8 contourne un bug d'Apple où « windows would animate and resize instead of snapping », ce qui suggère que Swish **positionne directement**, sans animer la fenêtre réelle, l'animation étant portée par l'aperçu. [Déduit]

---

## 6. Multi-écrans, Spaces, Stage Manager, plein écran, exclusions

- **Écrans** : on déplace une fenêtre selon la position physique des écrans (S + direction) ; le plein écran peut être envoyé directement sur l'autre écran (configuration à deux écrans) ; le geste de la barre de menus déplace toutes les fenêtres aimantées ; les fenêtres sont ré-aimantées après un changement de configuration d'écrans (délai réglable, option pour désactiver) ; écrans verticaux gérés. [Confirmé]
- **Spaces** : on déplace une fenêtre vers le Space voisin (tap-hold + ←/→ ou G + ←/→). Cela exige que les **raccourcis Mission Control** (« Move left/right a space », ⌃← / ⌃→) soient actifs : « For switching Spaces to work, Mission Control keyboard shortcuts need to be set correctly » ; les raccourcis personnalisés sont gérés depuis la 1.8 (lecture via `CopySymbolicHotKeys`). [Confirmé + Binaire] **Technique probable** : saisir la barre de titre avec un événement souris synthétique (`CGEventCreateMouseEvent`, `CGEventPost`), puis envoyer ⌃→ pendant le « drag ». C'est la méthode classique (Rectangle et Amethyst font de même). Le correctif de la 1.5 (« cursor would disappear… after moving windows between spaces ») va dans ce sens. [Déduit]
- Déplacer des Spaces entre écrans via Mission Control (1.9). [Confirmé]
- **Stage Manager** : détection automatique et décalage de la zone des apps récentes (1.12) ; activation ou désactivation depuis le menubarlet (1.10). [Confirmé]
- **Tiling natif Sequoia** : option pour utiliser le tiling natif pour les grilles 2×2 ; espacement synchronisé (1.11, 1.12). Swish passe par les **éléments du menu Fenêtre** (« Snapping: Tiling menu item not found », bug corrigé avec les apps ayant un menu « Script »). [Confirmé + Binaire]
- **Plein écran** : Minimize exige un tap-hold en plein écran ; le plein écran sur l'autre écran fonctionne aussi pour une fenêtre déjà en plein écran ; un faux ré-aimantage après la sortie du plein écran a été corrigé (1.12). [Confirmé]
- **Exclusions d'apps** : « Ignore » par app depuis le menubarlet (liste noire). Le Super Modifier fonctionne quand même sur une app ignorée (1.8). Aucune liste d'exclusion éditable dans les réglages n'a été trouvée. [Confirmé / Incertain pour la liste]
- Les fenêtres sont désaimantées avant la fermeture pour ne pas se rouvrir aimantées (1.2). [Confirmé]

---

## 7. Permissions, versions macOS, distribution, prix

- **Accessibilité** (obligatoire) : « Swish needs accessibility permissions to function properly ». [Confirmé] Depuis la 1.10.2, il n'y a plus de pop-up « Input Monitoring » (Surveillance de l'entrée) pour les nouvelles installations. Le binaire appelle toutefois `IOHIDCheckAccess` (chaîne « No IODHIDListenAccess »). [Confirmé + Binaire]
- **Apple Events** vers Réglages Système : « Swish needs to control System Settings to fix a bug on Apple's side » (`NSAppleEventsUsageDescription`), pour « Fix Pinch & Swipe ». [Confirmé : Info.plist]
- Prérequis dans les réglages trackpad : « Zoom in or out » activé pour le pinch, « Smart zoom » pour le double tap, retour haptique activé ; Swish propose un diagnostic (1.8). [Binaire]
- App **LSUIElement** (pas d'icône dans le Dock), qui doit tourner depuis /Applications pour recevoir les mises à jour. Mises à jour **Sparkle** (appcast `https://highlyopinionated.co/swish/appcast`, vérification hebdomadaire), licences **Paddle**, DMG hébergé sur GitHub (`chrenn/swish-dl`). [Confirmé : Info.plist, otool, redirection du lien de téléchargement]
- macOS 12 et plus ; Intel et Apple Silicon (universel) ; « Ready for macOS 27 ». [Confirmé]
- Prix : **16 $** en achat unique (promotions à 15 $ et codes Black Friday), essai de **14 jours**, 2 Mac par licence, −33 % pour les étudiants. Setapp : le site indique 9,99 $/mois, la page Setapp indique « From $14.99/month », avec 7 jours gratuits. Pas sur le Mac App Store (pas de sandbox). [Confirmé]
- Historique : 1.0 (2019) → 1.13.3 (compatibilité macOS 27). Jalons : 1.1 (Super Modifier, Spaces, écrans, App Switcher), 1.2 (onglets, timeout d'annulation, tap-hold), 1.5 (3×3), 1.6 (Resize Adjacent, Setapp), 1.7 (Arrow Hotkeys, Mission Control/App Exposé), 1.8 (Live tooltips, Almost Maximize, diagnostics), 1.9 (Spaces entre écrans), 1.10 (Stage Manager), 1.11 (tiling Sequoia), 1.12 (décalage Stage Manager), 1.13 (macOS 26). [Confirmé : changelog]

---

## 8. Pistes techniques

### 8.1 Ce que révèle le binaire (Swish 1.13.3) [Binaire]
- Frameworks liés : AppKit, ApplicationServices, Carbon, CoreGraphics, IOKit, QuartzCore, SwiftUI, Combine, ServiceManagement, plus Paddle et Sparkle. **MultitouchSupport n'est pas lié**, et aucune chaîne `MTDevice`, `MultitouchSupport` ou `dlopen` n'apparaît. Il existe une classe interne `Swish.Multitouch.Engine` (`touchEngine`, `touchDispatchItem`), mais c'est un moteur maison qui travaille sur des événements.
- Les messages de diagnostic « For Pinching to work, Zoom In Or Out needs to be enabled » et « For Double Tap to work, Smart Zoom needs to be enabled » montrent que Swish **consomme les gestes déjà reconnus par macOS** : événements *magnify* (type 29, sous-type pinch), *smart magnify* (double tap à deux doigts, `NSEvent.EventType.smartMagnify`, type 32) et *scroll* à deux doigts avec `phase` et `momentumPhase` (chaînes présentes). Le « tap-hold » correspond très probablement à la phase **`mayBegin`** d'un scroll : deux doigts posés sans mouvement. [Déduit, cohérent avec le libellé « Tap and hold with two fingers »]
- `CGEventTapCreate` et `CGEventTapEnable` (« CGEventTap: initialized / interrupted / invalidated ») : un tap **actif** qui peut **avaler** les événements scroll, flick et pinch pendant un geste et bloquer l'inertie après (« Active Event Listener », `momentumBlock`, `gestureBlock`). Il gère la réactivation après `tapDisabledByTimeout` / `tapDisabledByUserInput`.
- AX : `AXUIElementCopyElementAtPosition` (élément sous le curseur : barre de titre, onglet, icône du Dock), `AXUIElementSetMessagingTimeout`, `AXObserverCreateWithInfoCallback` (suivi des déplacements et redimensionnements : Drag to Unsnap, Resize Adjacent, plein écran), privé `_AXUIElementGetWindow` (élément AX vers CGWindowID), repli sur `CGWindowListCopyWindowInfo` quand `SystemWideElement` renvoie nil (apps Adobe et Affinity). Utilise la bibliothèque **AXSwift** (chaîne « userData should be an AXSwift.Observer ») et **PromiseKit**.
- Privé CGS/SkyLight : `CGSCopyManagedDisplaySpaces` (liste des Spaces par écran), `_CGSDefaultConnection`, `CGSSetConnectionProperty` (masquage du curseur).
- Clavier : `CGEventCreateKeyboardEvent` et `CGEventPost` (⌘N, ⌘H, ⌃←/→, ⌘-Tab), `CopySymbolicHotKeys` (lecture des raccourcis Mission Control), `RegisterEventHotKey` (Arrow Hotkeys), `UCKeyTranslate` et TIS (dispositions clavier), paquet **KeyboardShortcuts** (sindresorhus).
- Souris : `CGEventCreateMouseEvent`, `CGWarpMouseCursorPosition` (option Move Cursor, drag synthétique pour les Spaces), `CGEventCreateScrollWheelEvent2`.
- Clic dans le Dock : lecture des éléments AX du processus Dock (`AXDockItem`…). La sensibilité peut entrer en conflit avec le clic droit sur les icônes du Dock (texte d'aide).
- Connexion au démarrage : `LSSharedFileList*` (API ancienne) + ServiceManagement.

### 8.2 Alternatives et code à étudier
| Projet | Intérêt | Licence |
|---|---|---|
| **Rectangle** (github.com/rxhanson/Rectangle) | calcul des positions (moitiés, quarts, tiers, sixièmes, neuvièmes, Almost Maximize), marges (« gaps »), multi-écrans, AX robuste (`AccessibilityElement`), Stage Manager, contournement de l'animation AX (`AXEnhancedUserInterface`) | MIT |
| **EasySwipe / Swindoo** (github.com/shortcutchris/easyswipe) | clone minimal très proche : swipes à deux doigts ←→↑↓ sur la barre de titre (Accessibility), trackpad et Magic Mouse, ignore l'inertie, normalise le défilement naturel | MIT |
| **Penc** (github.com/dgurkaynak/Penc) | gestes à deux doigts pour déplacer ou redimensionner après un double appui sur ⌘, overlay d'aperçu | open source |
| **Swoosh** (github.com/bwya77/swoosh) | équivalent de Swish pour Windows ; utile pour la logique de gestes et de grille | à vérifier |
| **Amethyst**, **yabai** | déplacement de fenêtres entre Spaces (drag synthétique + raccourcis, ou SkyLight privé) | MIT |
| **Mac Mouse Fix** | émulation d'événements de geste et de scroll (types 29 et 30, champs privés), utile pour comprendre le format des événements | GPL-3/MMF |
| **BetterTouchTool** | exemple de gestes par zone ; code fermé | — |

---

## 9. Écart avec SwishClone (classé par priorité)

État actuel de SwishClone : swipe via un moniteur global `.scrollWheel`, pinch via `CGEventTap` sur le type 29 ; barre de titre de la fenêtre active seulement ; ← → moitiés, ↑ remplir, ↓ réduire, pinch out = AXFullScreen, pinch in = fenêtre centrée à 60 % ; animation AX ; réglages : seuils, hauteur de zone, durée d'animation, swipe et pinch activables.

**Divergence de mapping à noter** : dans Swish, **pinch in = fermer la fenêtre** (×2 = quitter l'app) et **double tap = centrer / désaimanter**. SwishClone utilise pinch in pour « centrer à 60 % ». [Confirmé]

### P0, fondations qui changent l'architecture
1. **Machine à états des gestes, déclenchement au lever des doigts, annulation, enchaînement**
   Piste : suivre `NSEvent.phase` (`.mayBegin` → `.began` → `.changed` → `.ended`/`.cancelled`) et ignorer `momentumPhase != []`. L'action se déclenche sur `.ended`. On annule avec Échap (tap clavier) ou après une immobilité de plus de *cancelTimeout* (0,8 s). Pour enchaîner : une pause de *N* ms en `.changed` sans delta valide la direction courante (retour haptique) et ouvre une nouvelle étape. Une séquence (`[←, ↓]` → quart bas-gauche, `[↑, ↑]` → moitié haute) se résout au lever.
2. **Passer à un `CGEventTap` actif pour le scroll aussi** (en plus du pinch)
   Piste : `CGEventTapCreate(.cgSessionEventTap, .headInsertEventTap, .defaultTap, masque scrollWheel | type 29 | type 32 | keyDown | flagsChanged)`. Renvoyer `nil` pour avaler les événements tant que le geste est « capturé » (sur la barre de titre), bloquer l'inertie qui suit, et réactiver le tap sur `tapDisabledByTimeout`/`ByUserInput`. Le moniteur global `NSEvent` actuel ne peut pas bloquer, donc la fenêtre sous le curseur défile en même temps.
3. **Cible = fenêtre sous le curseur**, pas « la fenêtre au premier plan »
   Piste : `AXUIElementCopyElementAtPosition(systemWide, x, y)` puis remonter `kAXParentAttribute` jusqu'à `AXWindow`, et tester si l'élément est `AXToolbar`, un `AXGroup` de barre de titre ou `AXTabGroup`. Exclure si un ancêtre est `AXScrollArea`/`AXScrollBar`/`AXSlider`, et exclure popovers et PiP (`AXSubrole`). Garder la hauteur configurable comme repli. Utiliser `AXUIElementSetMessagingTimeout` (environ 0,1 s) pour ne pas bloquer sur une app qui ne répond pas.
4. **Tooltip / aperçu**
   Piste : `NSPanel` non activant, sans bordure, `level = .popUpMenu`, `ignoresMouseEvents = true`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`. On y dessine une mini-grille avec la zone cible, près du curseur. Pour le « live preview », un second panel de la taille du cadre cible, translucide (`NSVisualEffectView`), animé avec `NSAnimationContext`. On applique ensuite le cadre final **d'un seul coup** en AX, ce qui est plus fiable que l'animation AX image par image.
5. **Retour haptique**
   Piste : `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)` à chaque étape validée et à chaque changement de cible.

### P1, catalogue de fenêtres
6. **Pinch in = fermer, pinch in ×2 = quitter** : `AXUIElementPerformAction(closeButton, kAXPressAction)` via `kAXCloseButtonAttribute` ; quitter avec `NSRunningApplication.terminate()`. Double pinch = deux pinchs avant le lever, ou pinch, pause, pinch.
7. **Double tap = centrer / désaimanter** : `CGEventTap` sur le type 32 (smart magnify ; exige « Smart zoom » activé). On centre sur `visibleFrame` en restaurant la taille d'avant l'aimantation (mémoriser le cadre d'origine par `CGWindowID` via le privé `_AXUIElementGetWindow`, ou par hash d'élément AX).
8. **Grilles** : ↑↑/↓↓ moitiés verticales ; ←+↓ quarts ; modificateur ⇧ → tiers et deux-tiers (swipes horizontaux répétés), puis ↑/↓ → sixièmes ; ⇧⌥ → neuvièmes. Reprendre les calculateurs de Rectangle (MIT). Écrans verticaux : inverser X et Y.
9. **Grid spacing / marges**, **Almost Maximize** (par exemple 90 % centré), **exclusion Stage Manager** (décalage à gauche), en tenant compte de `NSScreen.visibleFrame` et de la conversion de coordonnées (origine AX en haut à gauche contre Cocoa en bas à gauche).
10. **Modificateurs** General, Screen, Secondary, Tertiary et Super : lire `CGEventFlags` dans le tap. Super = gestes sur toute la fenêtre. Réglables via un popover qui capture les touches.
11. **Minimize en plein écran uniquement après tap-hold** (garde-fou), **Hide** (G + double tap → `NSRunningApplication.hide()`).

### P2, zones supplémentaires
12. **Dock** : `AXUIElementCopyElementAtPosition` renvoie un `AXDockItem` (subrole `AXApplicationDockItem`) ; retrouver l'app avec `kAXURLAttribute` puis `NSRunningApplication`. Gestes : ↓ minimiser, ↑ restaurer (`kAXMinimizedAttribute = false` sur les fenêtres), ←/→ faire défiler les fenêtres (`kAXRaiseAction` + activation), pinch in = quitter, double tap = masquer, pinch out = ⌘N (`CGEventPostToPid`). Attention au conflit avec le clic droit sur le Dock.
13. **Zone vide de la barre de menus** : `y` du curseur dans `screen.frame.maxY - NSStatusBar.system.thickness` et élément AX = `AXMenuBar` sans `AXMenuBarItem`. Gestes : double tap → tout désaimanter, ↓/↑ → tout minimiser ou restaurer (écran courant, puis tous), ←/→ → app précédente ou suivante, tap-hold + scroll → ⌘-Tab synthétique (⌘ maintenu et Tab répété).
14. **Menu de l'app** (`AXMenuBarItem` d'index 1, à côté de ) → mêmes gestes que le Dock.
15. **Multi-écrans** : ⌘ + direction → écran voisin (tri des `NSScreen.screens` par position du centre), en conservant la position relative ou l'aimantation ; ré-aimantation sur `NSApplication.didChangeScreenParametersNotification` (après un délai).
16. **Spaces** : drag synthétique de la barre de titre (`CGEventCreateMouseEvent` leftMouseDown, puis `CGEventPost` de ⌃← ou ⌃→, puis mouseUp), après lecture des raccourcis réels avec `CopySymbolicHotKeys` (IDs 79 et 81). Sur macOS 15+ vérifier la fiabilité ; en alternative, SkyLight privé (`CGSMoveWindowsToManagedSpace`, fragile).

### P3, confort et finition
17. Onglets : tap-hold sur un `AXRadioButton` dans `AXTabGroup` → détacher (drag synthétique hors de la barre) ; pinch in → bouton de fermeture de l'onglet (`AXButton` enfant).
18. Drag to Unsnap et Resize Adjacent Windows : `AXObserver` sur `kAXMovedNotification`/`kAXResizedNotification` pour détecter un déplacement manuel d'une fenêtre aimantée et ajuster ses voisines.
19. Ignorer une app depuis le menu de la barre de menus (liste de bundle IDs) ; Arrow Hotkeys (`RegisterEventHotKey` ou le paquet KeyboardShortcuts) ; diagnostic des réglages trackpad (`defaults read com.apple.AppleMultitouchTrackpad TrackpadPinch / TrackpadTwoFingerDoubleTapGesture`, `com.apple.driver.AppleBluetoothMultitouch.trackpad`, clés que Swish lit : chaînes présentes) ; option « masquer le curseur pendant le geste » ; compteur de gestes ; Launch at Login via `SMAppService.mainApp` (macOS 13+).

---

## 10. Limites connues, bugs et critiques

- Les pinch et swipe système peuvent **cesser de fonctionner** à cause d'un bug d'Apple. Swish propose « Fix Pinch & Swipe », qui force une courte mise en veille de l'écran (1.9) et passe par Réglages Système en Apple Events. [Confirmé : changelog 1.1/1.9, Info.plist]
- Swish peut perdre silencieusement le droit Accessibilité ; il faut alors décocher puis recocher Swish dans les réglages. [Confirmé : FAQ]
- Firefox : défilement des onglets perturbé (l'API AX ne permettait pas de détecter la barre de défilement), en partie corrigé en 1.13.1 et 1.13.2. Microsoft Edge n'a plus la prise en charge des onglets. [Confirmé]
- macOS 27 : le geste Menubar › Mission Control › Screens est cassé (bug d'Apple). [Confirmé]
- Batterie : Swish doit écouter tous les mouvements de souris, moins de 1 % de CPU en moyenne, moins de 20 Mo de RAM. [Confirmé : FAQ]
- Utilisateurs : plantages sous Ventura, arrêts silencieux, conflits avec BetterTouchTool (conseil du développeur : désactiver « Active Event Listener »), grille jugée insuffisante pour les écrans ultra-larges (quarts horizontaux), support lent. [Confirmé : Product Hunt] Sur Reddit (résumé par BRNSFT) : « inutile avec une souris externe », prix jugé élevé pour un simple outil d'aimantation, versions espacées. [Confirmé, source secondaire]
- La Magic Mouse ne gère pas le tap-hold, et le pinch y est « fiddly » (tchgdns). [Confirmé]
- Personnalisation volontairement limitée : on ne peut pas réassigner les gestes, seulement les activer ou désactiver et changer les modificateurs. [Confirmé : FAQ BTT]

## Introuvable ou incertain
- Aucune documentation publique séparée (pas de manuel ni de wiki) : la documentation est dans la fenêtre de réglages elle-même.
- Valeurs exactes par défaut de Touch Sensitivity, de la taille des infobulles et de Grid Spacing (en pixels) : non trouvées.
- Seuils de détection (distance de swipe, durée du tap-hold) : non publiés.
- Les captures ne montrent pas la fin de la liste Snapping (tiers, sixièmes, neuvièmes) ; ces lignes sont reconstituées à partir des textes du binaire.
- Aucune interview du développeur sur l'implémentation n'a été trouvée.

---

## Sources
- Site officiel et FAQ : https://highlyopinionated.co/swish/
- Captures officielles (réglages) : https://highlyopinionated.co/swish/media/screenshot-1.png à screenshot-7.png
- Changelog officiel (Notion, lien depuis le site) : https://highlyopinionated.co/swish/changelog → https://app.notion.com/p/Changelog-6df36b8224b246cbbd7ceae0c831396a
- Téléchargement (DMG 1.13.3 inspecté) : https://highlyopinionated.co/swish/download → https://github.com/chrenn/swish-dl/releases/download/1.13.3/Swish.dmg
- Setapp : https://setapp.com/apps/swish
- Product Hunt, avis : https://www.producthunt.com/products/swish/reviews
- Digital Trends : https://www.digitaltrends.com/computing/swish-window-management-mac-app/ (citation reprise via les résultats de recherche ; la page n'a pas pu être chargée directement)
- sspai (en chinois) : https://sspai.com/post/55285
- tchgdns (en allemand) : https://tchgdns.de/swish-macos-trackpad-gesten-fenster-manager
- macOS WM Directory : https://macoswm.com/wm/swish (source secondaire, peu précise)
- Synthèse Reddit : https://www.brnsft.com/blog/according-to-reddit-the-best-mac-window-managers-in-2026 ; fil : https://www.reddit.com/r/mac/comments/ndt6s3/just_found_swish_window_manager_and_bought_it/
- EasySwipe : https://github.com/shortcutchris/easyswipe · Penc : https://github.com/dgurkaynak/Penc · Swoosh : https://github.com/bwya77/swoosh · Rectangle : https://github.com/rxhanson/Rectangle · Mac Mouse Fix : https://github.com/noah-nuebling/mac-mouse-fix
