#!/bin/bash
# Boot-test harness: boot a RISC-V kernel with QEMU in SNAPSHOT mode and
# detect whether it really reaches a login prompt. Produces result.json.
set -u

KERNEL="${KERNEL:-$HOME/kernelci-work/linux/arch/riscv/boot/Image}"
ROOTFS="${ROOTFS:-/mnt/d/riscv/openkylin.img}"
ROOT_DEV="${ROOT_DEV:-/dev/vda2}"
PORT="${PORT:-12056}"
TIMEOUT="${TIMEOUT:-180}"
OUT="${OUT:-$HOME/kernelci-riscv/build/boot-test}"
LOG="$OUT/boot.log"

mkdir -p "$OUT"

echo "======================================"
echo " RISC-V Boot Test (SNAPSHOT mode)"
echo "======================================"
echo "Kernel : $KERNEL"
echo "Rootfs : $ROOTFS  (root=$ROOT_DEV)"
echo "Timeout: ${TIMEOUT}s"
echo

[ -f "$KERNEL" ] || { echo "ERROR: kernel Image not found: $KERNEL"; exit 2; }
[ -f "$ROOTFS" ] || { echo "ERROR: rootfs not found: $ROOTFS"; exit 2; }

# -snapshot => all writes are temporary, rootfs is never modified.
timeout "$TIMEOUT" qemu-system-riscv64 \
  -machine virt -cpu max -nographic -no-reboot \
  -m 4G -smp 4 \
  -bios /usr/lib/riscv64-linux-gnu/opensbi/generic/fw_dynamic.bin \
  -kernel "$KERNEL" \
  -drive file="$ROOTFS",format=raw,if=virtio \
  -device virtio-net-device,netdev=usernet \
  -netdev user,id=usernet,hostfwd=tcp:127.0.0.1:${PORT}-:22 \
  -append "root=${ROOT_DEV} rw console=ttyS0 earlycon=sbi" \
  -snapshot > "$LOG" 2>&1
QEMU_RC=$?

KV=$(grep -m1 -oE 'Linux version [^ ]+' "$LOG" | sed 's/Linux version //')
KV=${KV:-unknown}

if grep -qiE "(login:|Login Prompts|Reached target .*getty.target)" "$LOG"; then
  BOOT="PASS"
  MARKER=$(grep -iE "(login:|Login Prompts)" "$LOG" | head -1 | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\"\\' | tr -s ' ' | cut -c1-110)
elif grep -qiE "Kernel panic|Unable to mount root|No working init|VFS: Cannot open root" "$LOG"; then
  BOOT="FAIL"
  MARKER=$(grep -iE "Kernel panic|Unable to mount root|No working init|VFS: Cannot open root" "$LOG" | head -1 | sed 's/\x1b\[[0-9;]*m//g' | tr -d '\"\\' | tr -s ' ' | cut -c1-110)
else
  BOOT="FAIL"
  MARKER="no login prompt within ${TIMEOUT}s (qemu rc=$QEMU_RC)"
fi

cat > "$OUT/result.json" <<EOF
{
  "test": "boot",
  "architecture": "riscv64",
  "kernel_version": "$KV",
  "rootfs": "$(basename "$ROOTFS")",
  "root_device": "$ROOT_DEV",
  "boot": "$BOOT",
  "marker": "$MARKER",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo
echo "BOOT RESULT: $BOOT"
echo "Kernel      : $KV"
echo "Marker      : $MARKER"
echo "Report      : $OUT/result.json"
[ "$BOOT" = "PASS" ]
