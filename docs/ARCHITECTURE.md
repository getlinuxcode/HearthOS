# Architecture — nom de code « Hearth »

> Nom provisoire, défini à un seul endroit (`shell/src/brand.ts`, `daemon/src/config.ts`, `os/build.sh`).

Objectif : une distribution Linux qui se comporte comme une **console de salon**. Pas de bureau,
pas de « mode console » optionnel : du premier écran du live USB jusqu'au lancement d'un jeu,
tout se fait à la manette, sur une TV.

## 1. Choix techniques

| Sujet | Choix | Pourquoi |
|---|---|---|
| Base | **Arch Linux** (rolling) | C'est la base de SteamOS 3 et de CachyOS. Mesa, noyau et pilotes toujours récents : indispensable pour les GPU récents (ex. RX 9070 XT / RDNA4 → noyau ≥ 6.13, Mesa ≥ 25). `archiso` permet de produire l'ISO avec peu de code. |
| Noyau (système installé) | **linux-cachyos** (dépôt CachyOS) | Ordonnanceur BORE + sched-ext, réglages orientés latence, build optimisé. Paquets NVIDIA précompilés (`linux-cachyos-nvidia-open`). Outil `chwd` pour détecter le matériel. |
| Noyau (live USB) | `linux` stock Arch | Compatibilité matérielle maximale pour l'installation ; aucun risque lié à un dépôt tiers au moment du boot. |
| Compositeur | **gamescope** (mode embarqué `-e`) | Celui du Steam Deck : FSR/NIS, mise à l'échelle entière, VRR, HDR, choix de la fréquence, limiteur de FPS. Repli automatique sur `cage` si pas de Vulkan (VM). |
| Proton | **Proton-CachyOS** par défaut, **Proton-GE**, Proton Experimental | Choix par jeu. `umu-launcher` pour les jeux hors Steam (Epic, GOG). |
| Interface (« shell ») | **Godot 4** (`console/`), rendu GPU natif (OpenGL / Vulkan), aucun navigateur | Fond vivant en shader, particules, animations à ressort, manettes gérées nativement (base SDL), sons synthétisés. Tourne aussi en VM (rendu logiciel). L ancien prototype web (`shell/`) est abandonné. |
| Daemon | **Node.js / TypeScript**, HTTP local `127.0.0.1:7300` | Partage les types avec l'interface. `steam-session` (connexion Steam par QR code) n'existe de façon fiable qu'en Node. Tourne **dans la session utilisateur** (il hérite du `DISPLAY` de gamescope pour lancer Steam) ; les actions root passent par `sudo -n` / polkit. |
| Installateur | Interface maison (manette) + **archinstall** en backend | On ne réécrit pas le partitionnement ; on génère une config archinstall. |
| Chargeur de démarrage | **systemd-boot** | Détecte Windows Boot Manager tout seul ; « Redémarrer sous Windows » = `systemctl reboot --boot-loader-entry=auto-windows`. |
| Émulation | **Cœurs libretro** lancés par RetroArch en mode sans interface | « Seulement le moteur » : RetroArch démarre directement le jeu (`-L cœur rom --fullscreen`), menu désactivé. C'est notre interface qui gère bibliothèque, dossiers, jaquettes. |
| Transfert de fichiers | **Serveur FTP** intégré au daemon (activable dans Réglages) + Samba à venir | FTP : marche avec n'importe quel client (FileZilla, explorateur Windows). Samba plus tard pour un dossier réseau natif sous Windows. |

## 2. Vue d'ensemble

```
┌──────────────────────── gamescope (-e, FSR, VRR, HDR, Hz) ────────────────────────┐
│  Godot     ──HTTP──►  hearth-daemon (Node, utilisateur)                           │
│  (shell UI)            ├─ steam      : QR login, bibliothèque, boutique, lancement │
│                        ├─ emulation  : dossiers ROM surveillés, systèmes, cœurs    │
│                        ├─ ftp        : serveur FTP activable                       │
│                        ├─ network    : NetworkManager (nmcli)                      │
│                        ├─ disks/install : lsblk, parted, ntfsresize, archinstall   │
│                        ├─ display    : écrit display.env lu par la session          │
│                        └─ power      : systemctl (veille, reboot, Windows)          │
│  Steam (-silent), jeux Proton, RetroArch (cœurs libretro)                           │
└────────────────────────────────────────────────────────────────────────────────────┘
```

En développement sous Windows, le daemon tourne en **mode mock** pour tout ce qui touche au
système (disques, Wi-Fi, alimentation). Steam, la boutique, le FTP et le scan des ROM sont **réels**.

## 3. Steam, Epic, GOG

- **Connexion Steam** : QR code à scanner avec l'application Steam mobile (`steam-session`,
  la même API que le client officiel). On stocke le *refresh token* localement.
- **Bibliothèque** : `IPlayerService/GetOwnedGames` avec le jeton d'accès, plus la lecture des
  `appmanifest_*.acf` pour savoir ce qui est installé.
- **Lancer / installer** : via le client Steam en arrière-plan (`steam://rungameid/ID`,
  `steam://install/ID`). Steam reste obligatoire pour les DRM et les téléchargements.
- **Achat** : Valve ne fournit **aucune API d'achat pour une application tierce**. On affiche
  la fiche (prix, description) chez nous, puis on propose : *Ouvrir dans Steam* (boutique du client)
  ou *QR code → finir l'achat sur le téléphone*.
- **Epic** : la connexion par code d'appareil (type `epicgames.com/activate`, celle des consoles)
  s'affiche en QR code, puis la bibliothèque passe par Legendary. **GOG** : gogdl. Prévu pour la phase 2.

## 4. Manettes

- Identification par vendor/product USB (Sony `054c`, Microsoft `045e`, Nintendo `057e`, Valve `28de`) :
  DualShock 4, DualSense (Edge), Xbox / 360 / Elite, Switch Pro, Steam Controller / Deck, générique.
- Une illustration par famille et les glyphes des boutons adaptés (✕○□△ / ABXY / disposition Nintendo).
- Clavier et souris fonctionnent partout ; clavier virtuel AZERTY/QWERTY à la manette.
- Côté Linux : `hid-playstation`, `xpad`/`xpadneo`, `hid-nintendo` ; base SDL GameControllerDB
  pour les manettes inconnues (le daemon renverra un mapping normalisé — phase 2).

## 5. Émulation

- **Systèmes** déclarés dans `daemon/src/emulation/systems.ts` : extensions → système → cœur libretro
  (ex. `.sfc` → SNES → `snes9x`).
- **Dossiers ROM** : l'utilisateur ajoute un dossier (« ce dossier contient mes jeux SNES » ou « détecte
  automatiquement »). Le daemon le scanne puis le **surveille** (`fs.watch`) : un fichier déposé par
  FTP apparaît dans la bibliothèque sans action.
- **Lancement** : `retroarch -L <cœur> <rom> --fullscreen` avec une config qui masque le menu ; la touche
  Home de la manette rend la main au shell.
- **BIOS** : dossier `bios/` dédié, statut affiché par système (ex. PS1 a besoin d'un BIOS).
- Les ROM et BIOS proviennent de l'utilisateur ; la distribution n'en fournit aucun.

## 6. Installateur (live USB)

1. Choix du disque (le média USB de démarrage est exclu).
2. Mode : **à côté de Windows** (réduction NTFS + curseur de taille), **espace libre**, ou **disque entier**.
3. Récapitulatif + confirmation **en maintenant Ⓐ 3 secondes** (pas d'effacement par erreur).
4. Exécution : `ntfsresize` → `sgdisk` → btrfs (sous-volumes + snapshots) → archinstall → linux-cachyos → systemd-boot.

Garde-fous à implémenter avant le vrai branchement : détection de **BitLocker**, de l'**hibernation /
démarrage rapide** Windows (NTFS non sûr à redimensionner), vérification `ntfsresize --no-action`.

## 7. Risques / sujets de R&D

1. **Changement de focus dans gamescope** entre le shell et le jeu : Steam règle normalement
   `GAMESCOPECTRL_BASELAYER_APPID` ; sans Steam comme interface, c'est au shell de le faire.
   À prototyper dès qu'on a un vrai matériel.
2. Premier lancement de Steam (mise à jour ~300 Mo) : à faire tourner pendant l'onboarding.
3. NVIDIA anciennes générations (avant Turing) : `nvidia-open` ne les gère pas → `chwd` choisira le pilote.
4. Les VM n'ont pas de Vulkan accéléré : gamescope ne démarre pas, le shell passe par `cage`.
   Les performances réelles se mesurent uniquement sur le matériel.
