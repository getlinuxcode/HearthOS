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

## ISO et VM

Prérequis : WSL2 ou Docker Desktop (pour construire) et VirtualBox (pour la VM).
Il faut aussi exporter l'interface pour Linux (modèles d'export Godot) — pas encore fait.

```powershell
.\scripts\build-iso.ps1
```

```powershell
.\scripts\run-vm.ps1
```
