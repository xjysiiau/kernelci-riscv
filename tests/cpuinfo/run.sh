#!/bin/bash
# tests/cpuinfo/run.sh
# RISC-V ISA detection test: assert the target is riscv64 and reports
# single-letter extensions, asserting the required ones are present.
# Required extensions configurable via REQUIRED_EXTS (comma-separated).
set -u

ARCH=$(uname -m)
ISA_FULL=$(grep -m1 '^isa' /proc/cpuinfo | awk -F':[[:space:]]*' '{print $2}')
BASE=$(echo "$ISA_FULL" | cut -d_ -f1)          # e.g. rv64imafdcvh
EXTS="${BASE#rv??}"                              # strip "rv64" -> imafdcvh
REQUIRED=${REQUIRED_EXTS:-v,h}

has_ext() {
  case "$EXTS" in
    *"$1"*) return 0 ;;
    *)      return 1 ;;
  esac
}

echo "architecture : $ARCH"
echo "isa (full)   : $ISA_FULL"
echo "base exts    : $EXTS"

status=PASS
missing=""
for ext in $(echo "$REQUIRED" | tr ',' ' '); do
  if has_ext "$ext"; then
    echo "ext $ext      : PRESENT"
  else
    echo "ext $ext      : MISSING"
    status=FAIL
    missing="${missing},${ext}"
  fi
done

OUT=${OUT:-$(cd "$(dirname "$0")" && pwd)/build}
mkdir -p "$OUT"
cat > "$OUT/cpuinfo.json" <<EOF
{"test":"cpuinfo","arch":"$ARCH","isa":"$ISA_FULL","required":"$REQUIRED","status":"$status","missing":"${missing#,}"}
EOF
echo "cpuinfo: $status"
[ "$status" = PASS ]
