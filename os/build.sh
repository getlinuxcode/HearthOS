#!/usr/bin/env bash
# Construit l'ISO live de Hearth à partir du profil « releng » d'archiso.
# À lancer en root dans un environnement Arch Linux (VM de construction, WSL Arch ou Docker).
#   Depuis Windows : scripts/build-iso-vm.ps1 (VM VirtualBox) ou scripts/build-iso.ps1 (Docker)
# Prérequis côté dépôt : daemon/dist compilé (npm run build -w daemon).
#
# Variables : WORK (dossier de travail, plusieurs Go), OUT (dossier de sortie), GODOT_VERSION.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${HEARTH_NAME:-hearth}"
WORK="${WORK:-/tmp/hearth-build}"
OUT="${OUT:-$ROOT/out}"
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"

echo "==> Outils de construction"
grep -q '^\[multilib\]' /etc/pacman.conf || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
# mise à jour complète : une installation partielle casse les dépendances (openssl…)
pacman -Syu --noconfirm --needed archiso rsync unzip

[ -d "$ROOT/daemon/dist" ] || { echo "daemon/dist manquant : lancez 'npm run build -w daemon' avant."; exit 1; }

echo "==> Profil releng → $WORK/profile"
rm -rf "$WORK/profile" "$WORK/work"
mkdir -p "$WORK" "$OUT"
cp -r /usr/share/archiso/configs/releng "$WORK/profile"
P="$WORK/profile"

sed -i "s/^iso_name=.*/iso_name=\"$NAME\"/" "$P/profiledef.sh"
sed -i "s/^iso_application=.*/iso_application=\"$NAME live\"/" "$P/profiledef.sh"
grep -q '^\[multilib\]' "$P/pacman.conf" || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> "$P/pacman.conf"

echo "==> Paquets"
grep -v '^\s*#' "$ROOT/os/packages.x86_64" | grep -v '^\s*$' >> "$P/packages.x86_64"
sort -u "$P/packages.x86_64" -o "$P/packages.x86_64"

echo "==> Fichiers système (airootfs)"
rsync -a "$ROOT/os/airootfs/" "$P/airootfs/"
# Les fichiers venant de Windows peuvent avoir des fins de ligne CRLF.
find "$P/airootfs/usr/local/bin" "$P/airootfs/etc/skel" "$P/airootfs/etc/systemd" "$P/airootfs/etc/sudoers.d" "$P/airootfs/etc/hearth" -type f -exec sed -i 's/\r$//' {} +

APP="$P/airootfs/opt/hearth"
mkdir -p "$APP/daemon" "$APP/console"

cp "$ROOT/VERSION" "$APP/VERSION"

echo "==> Epic Games : legendary"
mkdir -p "$APP/bin"
curl -fL -o "$APP/bin/legendary" https://github.com/derrod/legendary/releases/latest/download/legendary_linux_x64
chmod +x "$APP/bin/legendary"

echo "==> Service système (daemon Node)"
rsync -a "$ROOT/daemon/dist/" "$APP/daemon/dist/"
cp "$ROOT/daemon/package.json" "$APP/daemon/"
if [ -d "$ROOT/vm-stage/daemon/node_modules" ]; then
  rsync -a "$ROOT/vm-stage/daemon/node_modules/" "$APP/daemon/node_modules/"
else
  ( cd "$APP/daemon" && npm install --omit=dev --no-audit --no-fund --loglevel=error )
fi

echo "==> Interface console (Godot $GODOT_VERSION)"
GODOT_BIN="$WORK/godot-$GODOT_VERSION"
if [ ! -x "$GODOT_BIN" ]; then
  curl -fL -o "$WORK/godot.zip" "https://github.com/godotengine/godot/releases/download/$GODOT_VERSION-stable/Godot_v$GODOT_VERSION-stable_linux.x86_64.zip"
  unzip -o -q "$WORK/godot.zip" -d "$WORK"
  mv "$WORK/Godot_v$GODOT_VERSION-stable_linux.x86_64" "$GODOT_BIN"
  chmod +x "$GODOT_BIN"
  rm -f "$WORK/godot.zip"
fi
install -m 755 "$GODOT_BIN" "$APP/godot"
rsync -a --delete --exclude '.godot/' --exclude 'tools/' "$ROOT/console/" "$APP/console/"
# Pré-import des ressources (évite tout import au premier démarrage)
"$GODOT_BIN" --headless --path "$APP/console" --import >/dev/null 2>&1 || true

echo "==> Services : NetworkManager remplace iwd + systemd-networkd"
WANTS="$P/airootfs/etc/systemd/system/multi-user.target.wants"
mkdir -p "$WANTS"
rm -f "$WANTS/iwd.service" "$WANTS/systemd-networkd.service" "$WANTS/systemd-resolved.service" \
      "$P/airootfs/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service" \
      "$P/airootfs/etc/systemd/system/sockets.target.wants/systemd-networkd.socket" 2>/dev/null || true
ln -sf /usr/lib/systemd/system/NetworkManager.service "$WANTS/NetworkManager.service"
ln -sf /usr/lib/systemd/system/bluetooth.service "$WANTS/bluetooth.service"
ln -sf /etc/systemd/system/hearth-live-setup.service "$WANTS/hearth-live-setup.service"

echo "==> Permissions"
sed -i '/^file_permissions=(/a\  ["/usr/local/bin/hearth-session"]="0:0:755"\n  ["/usr/local/bin/hearth-inner"]="0:0:755"\n  ["/usr/local/bin/hearth-live-setup"]="0:0:755"\n  ["/opt/hearth/godot"]="0:0:755"\n  ["/opt/hearth/bin/legendary"]="0:0:755"\n  ["/etc/sudoers.d/hearth-live"]="0:0:440"' "$P/profiledef.sh"

echo "==> mkarchiso"
mkarchiso -v -w "$WORK/work" -o "$OUT" "$P"
echo "==> ISO prête :"
ls -lh "$OUT"/*.iso
