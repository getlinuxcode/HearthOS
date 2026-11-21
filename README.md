# Hearth (nom provisoire)

Distribution Linux **console de salon** : tout se pilote à la manette, de l'allumage au lancement du jeu.
Base Arch Linux, noyau linux-cachyos, gamescope, Steam + Proton-CachyOS, émulation libretro.

→ Choix techniques et architecture : [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Structure

| Dossier | Contenu |
|---|---|
| `console/` | **L'interface console native (Godot 4)** : allumage, manette, réseau, accueil, lancement, menu en jeu. |
| `daemon/` | Service local `127.0.0.1:7300` : Steam, émulation, FTP, réseau, disques, installation, alimentation. |
| `os/` | Recette de l'ISO (archiso) : paquets, session gamescope, utilisateur live, config RetroArch. |
| `scripts/` | Lancer l'interface, construire l'ISO (Docker), démarrer la VM (VirtualBox). |
| `shell/` | Ancien prototype web — **abandonné**, remplacé par `console/`, à supprimer. |

## Lancer l'interface sous Windows

```powershell
npm install
```

```powershell
.\scripts\run-console.ps1
```

Options : `-Fullscreen`, `-Scene home|pad|network|overlay`.
Manette : tout fonctionne. Clavier : flèches, Entrée, Échap, H = bouton PS/Xbox, M = Start, Pg↑/Pg↓ = L1/R1.

Godot portable (4.7.2) est attendu dans `tools\godot\` (non versionné). Le daemon tourne en mode **mock** sous
Windows pour le système (disques, Wi-Fi, alimentation) ; Steam, la boutique, le FTP et les ROM sont réels.

### Ce qui est natif
Tout le parcours : allumage animé · manette géante (dessins au trait par modèle) avec halo « appuyez sur le bouton PS » ·
réseau et clavier virtuel · installateur (disques, taille, maintien pour confirmer, progression) · comptes et connexion
Steam par QR · écran et Hz · accueil (jaquettes, fond vivant teinté) · fiche et boutique Steam (achat par QR ou client
Steam) · émulateurs (icônes des consoles, moteurs, dossiers surveillés, FTP) · réglages complets · test de manette ·
lancement animé · menu en jeu (bouton PS) · sons synthétisés propres.

Contrôle de compilation de tous les scripts : `bash scripts/check-console.sh`.
Crédits des ressources : [console/assets/CREDITS.md](console/assets/CREDITS.md).

## Publier une mise à jour (sans refaire d'ISO)

Les consoles installent les nouvelles versions de l'interface et du service depuis les **releases GitHub**
de [getlinuxcode/HearthOS](https://github.com/getlinuxcode/HearthOS) : Réglages → Mises à jour (vérification
automatique toutes les 6 h, notification sur l'accueil). Chaque archive est signée (Ed25519) : une console refuse
toute mise à jour qui n'est pas signée par la clé du projet. Les versions précédentes restent disponibles pour revenir en arrière.

Depuis n'importe quel PC qui a le dépôt, `gh` connecté au compte du projet et la clé de signature
(`~/.hearth/update-signing-key.pem`, **à copier à la main, jamais à versionner**) :

```powershell
node scripts/publish-update.mjs --version 0.2.1 --notes "Ce qui change" --publish
```

Pour tester sans publier : `--base http://<IP du PC>:8787 --serve` (canal local ; VirtualBox 7 bloque `10.0.2.2`),
puis Réglages → Mises à jour → Canal → `http://<IP du PC>:8787/manifest.json`.
Les paquets Arch (noyau, pilotes, Steam…) se mettent à jour séparément depuis le même écran, une fois Hearth installé.

## ISO et VM (VirtualBox, sans WSL ni Docker)

L'ISO est construite dans une VM Arch Linux temporaire (« Hearth-build »), puis démarrée dans la VM « Hearth ».

1. Première fois : télécharger l'ISO Arch officielle dans `vm/archlinux-x86_64.iso`, créer la VM « Hearth-build »
   (BIOS, 6 Go, disque de 80 Go, redirection SSH 127.0.0.1:2222 → 22), y déposer la clé `vm/ssh/id_ed25519.pub`
   dans `/root/.ssh/authorized_keys` et démarrer `sshd`.
2. Construire (≈ 15 min la première fois, paquets ensuite en cache) :

```powershell
npm run build -w daemon
```

```powershell
bash scripts/build-iso-vm.sh
```

3. Démarrer l'ISO dans la VM « Hearth » (UEFI, 8 Go, 3D, manettes USB Sony/Microsoft transmises) :

```powershell
.scriptsun-vm.ps1
```

En VM, pas de Vulkan ni de partage de tampons GPU : la session passe par `cage` en rendu logiciel
(llvmpipe) au lieu de gamescope. C'est fluide mais gourmand en processeur ; les vraies performances
(4K, FSR, ray tracing) se mesurent sur le matériel, depuis une clé USB.
Journal de session dans la VM : `/home/player/.local/share/hearth/session.log`.
