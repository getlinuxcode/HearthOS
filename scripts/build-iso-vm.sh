#!/usr/bin/env bash
# Construit l'ISO Hearth dans la VM VirtualBox « Hearth-build » (Arch live), sans WSL ni Docker.
# Pré-requis : la VM tourne et répond en SSH sur 127.0.0.1:2222 (voir scripts/README-vm.md).
# Usage (Git Bash) : bash scripts/build-iso-vm.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="$ROOT/vm/ssh/id_ed25519"
SSH=(ssh -i "$KEY" -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@127.0.0.1)

echo "==> Préparation du disque de travail de la VM"
"${SSH[@]}" 'set -e
  if ! mountpoint -q /mnt; then
    blkid /dev/sda >/dev/null 2>&1 || mkfs.ext4 -q -F /dev/sda
    mount /dev/sda /mnt
  fi
  mkdir -p /mnt/cache /mnt/src /mnt/out /mnt/work
  mountpoint -q /var/cache/pacman/pkg || mount --bind /mnt/cache /var/cache/pacman/pkg
  mount -o remount,size=4G /run/archiso/cowspace || true'

echo "==> Dépendances du daemon (préparées ici, pur JavaScript)"
rm -rf "$ROOT/vm-stage" && mkdir -p "$ROOT/vm-stage/daemon"
cp "$ROOT/daemon/package.json" "$ROOT/vm-stage/daemon/"
( cd "$ROOT/vm-stage/daemon" && npm install --omit=dev --ignore-scripts --no-audit --no-fund --loglevel=error )

echo "==> Envoi du projet"
tar -C "$ROOT" --exclude='./node_modules' --exclude='./vm' --exclude='./out' --exclude='./tools' \
  --exclude='./console/.godot' --exclude='./shell' --exclude='./.git' -czf - . | "${SSH[@]}" 'rm -rf /mnt/src && mkdir -p /mnt/src && tar -C /mnt/src -xzf -'

echo "==> Construction (plusieurs minutes : téléchargement des paquets puis compression)"
mkdir -p "$ROOT/vm"
"${SSH[@]}" 'cd /mnt/src && WORK=/mnt/work OUT=/mnt/out bash os/build.sh' 2>&1 | tee "$ROOT/vm/build-remote.log" \
  | grep --line-buffered -E '^==>|error|ERROR|warning: .*not found|\.iso'

echo "==> Récupération de l'ISO"
mkdir -p "$ROOT/out"
ISO=$("${SSH[@]}" 'ls -t /mnt/out/*.iso | head -1')
scp -i "$KEY" -P 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "root@127.0.0.1:$ISO" "$ROOT/out/"
ls -lh "$ROOT/out/"
