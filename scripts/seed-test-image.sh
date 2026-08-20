#!/bin/bash
# scripts/seed-test-image.sh — one-time setup, run in WSL with sudo.
# Copies the idle openkylin.img onto the Linux filesystem (loop-mounting a
# drvfs file does not work) and seeds the SSH public key for the guest user
# so the closed-loop runner can SSH in non-interactively.
set -euo pipefail

SRC=${SRC:-/mnt/d/riscv/openkylin.img}
# When run via "sudo ./script", $HOME becomes /root; resolve the real
# user's home from SUDO_USER instead.
if [ -n "${SUDO_USER:-}" ]; then
  REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  REAL_HOME=${REAL_HOME:-/home/$SUDO_USER}
else
  REAL_HOME=$HOME
fi
DEST=${DEST:-$REAL_HOME/kernelci-test/openkylin-test.img}
GUEST_USER=${GUEST_USER:-openkylin}
PROJECT=$(cd "$(dirname "$0")/.." && pwd)
PUBKEY_FILE="$PROJECT/configs/dsh-test.pub"

[ -f "$PUBKEY_FILE" ] || { echo "ERROR: pubkey missing: $PUBKEY_FILE"; exit 2; }

if [ -f "$DEST" ]; then
  echo "[1/4] $DEST already exists, skipping copy (remove it to re-seed)."
else
  echo "[1/4] copying image (6GB, several minutes)..."
  cp "$SRC" "$DEST"
fi

echo "[2/4] mounting root partition (sudo)..."
LOOP=$(sudo losetup -Pf --show "$DEST")
sudo mkdir -p /mnt/kci-root
sudo mount "${LOOP}p2" /mnt/kci-root

echo "[3/4] seeding SSH key for '$GUEST_USER'..."
HOMEDIR="/mnt/kci-root/home/$GUEST_USER"
if [ ! -d "$HOMEDIR" ]; then
  echo "ERROR: $HOMEDIR not found (wrong guest user?)"
  sudo umount /mnt/kci-root
  sudo losetup -d "$LOOP"
  exit 1
fi
UIDGID=$(stat -c %u:%g "$HOMEDIR")
sudo mkdir -p "$HOMEDIR/.ssh"
sudo cp "$PUBKEY_FILE" "$HOMEDIR/.ssh/authorized_keys"
sudo chown -R "$UIDGID" "$HOMEDIR/.ssh"
sudo chmod 700 "$HOMEDIR/.ssh"
sudo chmod 600 "$HOMEDIR/.ssh/authorized_keys"

echo "[4/4] unmounting..."
sudo umount /mnt/kci-root
sudo losetup -d "$LOOP"
echo "SEEDED: $DEST"
