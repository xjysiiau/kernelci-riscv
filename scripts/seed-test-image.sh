#!/bin/bash
# scripts/seed-test-image.sh — one-time setup, needs sudo.
# Copies the source RISC-V distro image onto the Linux filesystem
# (loop-mounting a drvfs/9p file does not work) and seeds the SSH public key
# for the guest user so the closed-loop runner can SSH in non-interactively.
# Mounts partition 2 by byte offset, which works both on regular hosts and
# inside containers (no dependency on udev-created partition device nodes).
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
[ -f "$SRC" ]      || { echo "ERROR: source image missing: $SRC"; exit 2; }

if [ -f "$DEST" ]; then
  echo "[1/4] $DEST already exists, skipping copy (remove it to re-seed)."
else
  echo "[1/4] copying image (6GB, several minutes)..."
  cp "$SRC" "$DEST"
fi

echo "[2/4] mounting root partition (sudo)..."
# Detach any stale loop devices left over from earlier failed attempts.
for L in $(sudo losetup -j "$DEST" 2>/dev/null | cut -d: -f1); do
  sudo losetup -d "$L" 2>/dev/null || true
done
# Byte offset of partition 2 (the root filesystem on these distro images).
OFF=$(sudo parted -s "$DEST" unit B print 2>/dev/null \
      | awk '$1 == 2 {gsub("B", "", $2); print $2}')
[ -n "$OFF" ] || { echo "ERROR: could not determine partition 2 offset (parted available?)"; exit 2; }
sudo mkdir -p /mnt/kci-root
sudo mount -o loop,offset="$OFF" "$DEST" /mnt/kci-root

echo "[3/4] seeding SSH key for '$GUEST_USER'..."
HOMEDIR="/mnt/kci-root/home/$GUEST_USER"
if [ ! -d "$HOMEDIR" ]; then
  echo "ERROR: $HOMEDIR not found (wrong guest user?)"
  sudo umount /mnt/kci-root
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
echo "SEEDED: $DEST"
