#!/bin/bash
# scripts/run-closed-loop.sh — KernelCI-style closed loop, run in WSL (x86).
#   kernel Image -> boot seeded openkylin test image (-snapshot, zero risk)
#   -> wait for SSH -> push test suite -> run tests inside guest
#   -> pull results back -> verdict
set -euo pipefail

PROJECT=$(cd "$(dirname "$0")/.." && pwd)
IMG=${IMG:-$HOME/kernelci-test/openkylin-test.img}
KERNEL=${KERNEL:-$HOME/kernelci-work/linux/arch/riscv/boot/Image}
PORT=${PORT:-12056}
GUEST_USER=${GUEST_USER:-openkylin}
BOOT_TIMEOUT=${BOOT_TIMEOUT:-240}
KEY=$HOME/.ssh/kci-test-key
OUT="$PROJECT/build/closed-loop"
mkdir -p "$OUT"

[ -f "$IMG" ]    || { echo "ERROR: seeded image missing: $IMG (run scripts/seed-test-image.sh first)"; exit 2; }
[ -f "$KERNEL" ] || { echo "ERROR: kernel Image missing: $KERNEL"; exit 2; }

if [ ! -f "$KEY" ]; then
  KEY_SRC=${KEY_SRC:-/mnt/d/kernelcl/riscv-vm-key}
  cp "$KEY_SRC" "$KEY" 2>/dev/null \
    || { echo "ERROR: ssh key missing at $KEY (set KEY_SRC or pre-stage the key)"; exit 2; }
  chmod 600 "$KEY"
  echo "[0/5] ssh key staged at $KEY"
fi

echo "[0b/5] config drift check..."
set +e
"$PROJECT/scripts/check-config-drift.sh"
DRIFT_RC=$?
set -e
if [ "$DRIFT_RC" -eq 2 ]; then
  echo "ABORT: FAIL-level config drift (see build/config-drift.json)"
  exit 2
elif [ "$DRIFT_RC" -eq 1 ]; then
  echo "WARNING: WARN-level config drift (see build/config-drift.json)"
else
  echo "    config clean"
fi

# [0c/5] ensure the prebuilt guest test artifacts exist on the host.
# A fresh checkout (e.g. on the CI runner) has no tests/build/, so build
# them with the cross toolchain on demand.
ART_DIR="$PROJECT/tests/build"
mkdir -p "$ART_DIR"
if [ ! -x "$ART_DIR/vector_add" ]; then
  echo "[0c/5] cross-building vector_add (missing)..."
  riscv64-linux-gnu-gcc -static -O2 -march=rv64gcv \
    "$PROJECT/tests/vector/vector_add.c" -o "$ART_DIR/vector_add" \
    || echo "  WARNING: vector_add cross-build failed"
fi
if [ ! -x "$ART_DIR/kselftest/build/hwprobe/hwprobe" ]; then
  echo "[0c/5] cross-building riscv kselftests (missing)..."
  KSELFTEST_SRC=${KSELFTEST_SRC:-${KERNEL_SRC:-$HOME/kernelci-work/linux}}
  (cd "$KSELFTEST_SRC/tools/testing/selftests/riscv" && \
   make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- \
        OUTPUT="$ART_DIR/kselftest/build" -j"$(nproc)") \
    > "$OUT/kselftest-cross-build.log" 2>&1 \
    || echo "  (note: some subtargets may fail to build - see $OUT/kselftest-cross-build.log)"
fi

SSHOPTS=(-i "$KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
         -o UserKnownHostsFile="$OUT/known_hosts" -o ConnectTimeout=5)

QEMU_PID=""
cleanup() { [ -n "$QEMU_PID" ] && kill "$QEMU_PID" 2>/dev/null || true; }
trap cleanup EXIT

echo "[1/5] booting $IMG with $KERNEL (-snapshot, ssh port $PORT)..."
qemu-system-riscv64 \
  -machine virt -cpu max -nographic -no-reboot \
  -m 4G -smp 4 \
  -bios /usr/lib/riscv64-linux-gnu/opensbi/generic/fw_dynamic.bin \
  -kernel "$KERNEL" \
  -drive file="$IMG",format=raw,if=virtio \
  -device virtio-net-device,netdev=usernet \
  -netdev user,id=usernet,hostfwd=tcp:127.0.0.1:${PORT}-:22 \
  -append "root=/dev/vda2 rw console=ttyS0 earlycon=sbi" \
  -snapshot > "$OUT/qemu.log" 2>&1 &
QEMU_PID=$!
echo "    qemu pid: $QEMU_PID (serial log: $OUT/qemu.log)"

echo "[2/5] waiting for SSH (up to ${BOOT_TIMEOUT}s)..."
BOOT=0
for i in $(seq 1 $((BOOT_TIMEOUT / 5))); do
  if ssh "${SSHOPTS[@]}" -p "$PORT" "$GUEST_USER@127.0.0.1" true 2>/dev/null; then
    BOOT=1
    break
  fi
  sleep 5
done
if [ "$BOOT" -ne 1 ]; then
  echo "RESULT: BOOT FAIL (no SSH after ${BOOT_TIMEOUT}s)"
  echo "--- last serial lines ---"
  tail -25 "$OUT/qemu.log"
  exit 1
fi
echo "    BOOT OK (guest reachable via ssh port $PORT)"

echo "[3/5] pushing test suite to guest..."
ssh "${SSHOPTS[@]}" -p "$PORT" "$GUEST_USER@127.0.0.1" \
  "rm -rf /tmp/kernelci-tests && mkdir -p /tmp/kernelci-tests"
scp "${SSHOPTS[@]}" -P "$PORT" -r "$PROJECT/tests" \
  "$GUEST_USER@127.0.0.1:/tmp/kernelci-tests/"

echo "[4/5] running tests inside guest..."
set +e
ssh "${SSHOPTS[@]}" -p "$PORT" "$GUEST_USER@127.0.0.1" \
  "chmod -R +x /tmp/kernelci-tests/tests; export SKIP_BUILD=1 KSELFTEST_BUILD=skip; cd /tmp/kernelci-tests/tests && ./run-tests.sh" \
  | tee "$OUT/guest-run.log"
GUEST_RC=${PIPESTATUS[0]}
set -e

echo "[5/5] pulling results..."
rm -rf "$OUT/guest-results"
scp "${SSHOPTS[@]}" -P "$PORT" -r \
  "$GUEST_USER@127.0.0.1:/tmp/kernelci-tests/tests/build" "$OUT/guest-results" 2>/dev/null || true

echo "--- verdict ---"
if [ -f "$OUT/guest-results/results.json" ]; then
  python3 -c "import json;d=json.load(open('$OUT/guest-results/results.json'));print('OVERALL:',d['summary']['overall']);[print(' -',t.get('test','?'),'->',t.get('status','?')) for t in d['tests']]" || true
fi

echo "--- recording result history ---"
if [ -x "$PROJECT/scripts/record-result.sh" ]; then
  "$PROJECT/scripts/record-result.sh" "$OUT/guest-results/results.json" || echo "  (record skipped)"
fi
exit "$GUEST_RC"
