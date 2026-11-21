#!/usr/bin/env bash
# Construit l'ISO live de Hearth à partir du profil « releng » d'archiso.
# À lancer DANS un environnement Arch Linux (conteneur Docker, WSL Arch, ou machine Arch), en root.
#   Docker : voir scripts/build-iso.ps1
# Prérequis : `npm run build` déjà exécuté à la racine (shell/dist + daemon/dist).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${HEARTH_NAME:-hearth}"
WORK="${WORK:-/tmp/hearth-build}"
OUT="${OUT:-$ROOT/out}"

echo "==> Paquets de build"
pacman -Syu --noconfirm --needed archiso rsync

[ -d "$ROOT/shell/dist" ] && [ -d "$ROOT/daemon/dist" ] || { echo "Lancez d'abord 'npm run build' à la racine."; exit 1; }

echo "==> Profil releng → $WORK/profile"
rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"
cp -r /usr/share/archiso/configs/releng "$WORK/profile"
P="$WORK/profile"

# Nom de l'ISO
sed -i "s/^iso_name=.*/iso_name=\"$NAME\"/" "$P/profiledef.sh"
sed -i "s/^iso_application=.*/iso_application=\"$NAME live\"/" "$P/profiledef.sh"

# multilib (Steam, bibliothèques 32 bits)
if ! grep -q '^\[multilib\]' "$P/pacman.conf"; then
  printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> "$P/pacman.conf"
fi
grep -q '^\[multilib\]' /etc/pacman.conf || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf

echo "==> Paquets Hearth"
grep -v '^\s*#' "$ROOT/os/packages.x86_64" | grep -v '^\s*$' >> "$P/packages.x86_64"
sort -u "$P/packages.x86_64" -o "$P/packages.x86_64"

echo "==> Fichiers du système (airootfs)"
rsync -a "$ROOT/os/airootfs/" "$P/airootfs/"

# Application
APP="$P/airootfs/opt/hearth"
mkdir -p "$APP/shell" "$APP/daemon"
rsync -a "$ROOT/shell/dist/" "$APP/shell/dist/"
rsync -a "$ROOT/shell/electron/" "$APP/shell/electron/"
rsync -a "$ROOT/daemon/dist/" "$APP/daemon/dist/"
cp "$ROOT/daemon/package.json" "$APP/daemon/"
( cd "$APP/daemon" && pacman -S --noconfirm --needed nodejs npm >/dev/null && npm install --omit=dev --no-audit --no-fund )

# Services : NetworkManager remplace iwd + systemd-networkd du releng
WANTS="$P/airootfs/etc/systemd/system/multi-user.target.wants"
mkdir -p "$WANTS"
rm -f "$WANTS/iwd.service" "$WANTS/systemd-networkd.service" "$WANTS/systemd-resolved.service" \
      "$P/airootfs/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$WANTS/NetworkManager.service"
ln -sf /usr/lib/systemd/system/bluetooth.service "$WANTS/bluetooth.service"
ln -sf /etc/systemd/system/hearth-live-setup.service "$WANTS/hearth-live-setup.service"

# Permissions des scripts
sed -i '/^file_permissions=(/a\  ["/usr/local/bin/hearth-session"]="0:0:755"\n  ["/usr/local/bin/hearth-inner"]="0:0:755"\n  ["/usr/local/bin/hearth-live-setup"]="0:0:755"\n  ["/etc/sudoers.d/hearth-live"]="0:0:440"' "$P/profiledef.sh"

echo "==> mkarchiso"
mkarchiso -v -w "$WORK/work" -o "$OUT" "$P"
echo "==> ISO prête dans $OUT"
ls -lh "$OUT"/*.iso
