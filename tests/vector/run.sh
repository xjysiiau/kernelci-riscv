#!/bin/bash
# tests/vector/run.sh
# Compile and run the RVV vector_add self-test. Skips gracefully if the
# target lacks the V extension.
set -u

SD=$(cd "$(dirname "$0")" && pwd)
SRC="$SD/vector_add.c"
OUT=${OUT:-$SD/build}
BIN="$OUT/vector_add"
CC=${CC:-gcc}
MARCH=${MARCH:-rv64gcv}
mkdir -p "$OUT"

ISA_FULL=$(grep -m1 '^isa' /proc/cpuinfo | awk -F':[[:space:]]*' '{print $2}')
EXTS="${ISA_FULL%%_*}"; EXTS="${EXTS#rv??}"
case "$EXTS" in
  *v*) ;;
  *)
    echo "vector: SKIP (no V extension in /proc/cpuinfo)"
    echo '{"test":"vector","status":"SKIP","reason":"no V extension"}' > "$OUT/vector.json"
    exit 0
    ;;
esac

if [ "${SKIP_BUILD:-0}" = "1" ]; then
  if [ ! -x "$BIN" ]; then
    echo "vector: FAIL (prebuilt binary missing at $BIN)"
    echo '{"test":"vector","status":"FAIL","reason":"prebuilt missing"}' > "$OUT/vector.json"
    exit 1
  fi
elif ! $CC -O2 -march=$MARCH "$SRC" -o "$BIN" 2>"$OUT/vector_build.log"; then
  echo "vector: FAIL (build error)"
  tail -8 "$OUT/vector_build.log"
  echo '{"test":"vector","status":"FAIL","reason":"build"}' > "$OUT/vector.json"
  exit 1
fi

if "$BIN"; then
  echo '{"test":"vector","status":"PASS"}' > "$OUT/vector.json"
  echo "vector: PASS"
  exit 0
else
  echo '{"test":"vector","status":"FAIL","reason":"runtime"}' > "$OUT/vector.json"
  echo "vector: FAIL"
  exit 1
fi
