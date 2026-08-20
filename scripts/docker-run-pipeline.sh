#!/bin/bash
# scripts/docker-run-pipeline.sh
# Build the pipeline container image and run a command inside it with the
# repo, kernel source and image dir mounted. Defaults to an interactive shell.
#
#   scripts/docker-run-pipeline.sh /work/kernelci-riscv/scripts/check-config-drift.sh
#   scripts/docker-run-pipeline.sh /work/kernelci-riscv/scripts/run-closed-loop.sh
set -euo pipefail

PROJECT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=${IMAGE:-kernelci-riscv-pipeline:latest}
KSRC=${KSRC:-$HOME/kernelci-work/linux}
IMGDIR=${IMGDIR:-$HOME/kernelci-test}

echo "[docker] building image $IMAGE ..."
docker build -t "$IMAGE" "$PROJECT"

echo "[docker] running: ${*:-bash}"
exec docker run --rm \
  -v "$PROJECT:/work/kernelci-riscv" \
  -v "$KSRC:/work/linux" \
  -v "$IMGDIR:/work/images" \
  -e KERNEL_SRC=/work/linux \
  -e ACTUAL=/work/linux/.config \
  -e KERNEL=/work/linux/arch/riscv/boot/Image \
  -e IMG=/work/images/openkylin-test.img \
  "$IMAGE" "${@:-bash}"
