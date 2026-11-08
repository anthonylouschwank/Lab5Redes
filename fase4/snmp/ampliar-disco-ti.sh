#!/bin/bash
# Fase 4 · F4 — Extender la partición raíz de TI tras modify-volume 8 -> 12 GiB (en caliente).
set -euo pipefail
echo "antes:"; df -h / | tail -1; lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -vE 'loop'
ROOT=$(findmnt -n -o SOURCE /)              # p. ej. /dev/nvme0n1p1
DISK=/dev/$(lsblk -no PKNAME "$ROOT")       # /dev/nvme0n1
PART=${ROOT##*[!0-9]}                        # 1
FS=$(findmnt -n -o FSTYPE /)
echo "raíz=$ROOT disco=$DISK partición=$PART fs=$FS"
sudo growpart "$DISK" "$PART" || echo "(growpart: sin cambios)"
case "$FS" in
  ext4) sudo resize2fs "$ROOT" ;;
  xfs)  sudo xfs_growfs / ;;
  *)    echo "fs no soportado: $FS"; exit 1 ;;
esac
echo "después:"; df -h / | tail -1
