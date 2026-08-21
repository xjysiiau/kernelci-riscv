#!/bin/bash
# tests/kselftest/run.sh
# Build and run the RISC-V kernel selftests (tools/testing/selftests/riscv)
# on a riscv64 target. Encodes the official run preconditions:
#   - ARCH must be passed explicitly ("riscv64" does not match the Makefile's
#     "riscv" filter, so ARCH=riscv is required);
#   - vector tests must run from their build dir (they exec sibling helpers);
#   - mm tests must run via run_mmap.sh (ulimit -s unlimited for bottom-up).
set -u

KERNEL_SRC=${KERNEL_SRC:-$HOME/linux}
OUT=${OUT:-$(cd "$(dirname "$0")" && pwd)/build}
WORK="$OUT/kselftest"
ST_OUT="$WORK/build"          # kselftest build output tree
mkdir -p "$WORK" "$ST_OUT"

NCPU=$(nproc)
SKIP_BUILD=${KSELFTEST_BUILD:-build}

# ---------------------------------------------------------------- build ----
if [ "$SKIP_BUILD" = "skip" ]; then
  echo "[build] SKIPPED (using prebuilt binaries under $ST_OUT)"
else
  if [ ! -d "$KERNEL_SRC/usr/include/linux" ]; then
    echo "[build] installing uapi headers..."
    (cd "$KERNEL_SRC" && make ARCH=riscv headers) > "$WORK/headers.log" 2>&1 \
      || { echo "kselftest: FAIL (make headers)"; tail -8 "$WORK/headers.log"; exit 1; }
  fi

  echo "[build] building selftests/riscv (ARCH=riscv, -j$NCPU)..."
  (cd "$KERNEL_SRC/tools/testing/selftests/riscv" && \
   make ARCH=riscv OUTPUT="$ST_OUT" -j"$NCPU") > "$WORK/build.log" 2>&1
  echo "[build] done (see $WORK/build.log)"
fi

# Known upstream failures (tracked, see docs/findings-pointer-masking.md).
# Space-separated "subdir/binary" entries. A known failure is reported as
# XFAIL (expected) and does not fail the run; if it unexpectedly passes,
# it is reported as XPASS — upstream may have fixed it, remove the entry.
KNOWN_FAILURES=${KNOWN_FAILURES:-"abi/pointer_masking"}

is_known_fail() {
  local t="$1" k
  for k in $KNOWN_FAILURES; do
    [ "$t" = "$k" ] && return 0
  done
  return 1
}

# ------------------------------------------------------------ run table ----
# run_one <subdir> <binary> [timeout]
run_one() {
  local sub="$1" bin="$2" tmo="${3:-90}"
  local dir="$ST_OUT/$sub" log="$WORK/${sub}_${bin}.log"
  if [ ! -x "$dir/$bin" ]; then
    echo "$sub/$bin : SKIP (not built)"
    echo "{\"test\":\"kselftest/$sub/$bin\",\"status\":\"SKIP\",\"reason\":\"not built\"}" > "$WORK/${sub}_${bin}.json"
    return 0
  fi
  (cd "$dir" && timeout "$tmo" "./$bin") > "$log" 2>&1
  local rc=$?
  if [ $rc -eq 0 ] && ! grep -q '^not ok' "$log"; then
    if is_known_fail "$sub/$bin"; then
      echo "$sub/$bin : XPASS (known failure no longer reproduces - upstream may have fixed it)"
      echo "{\"test\":\"kselftest/$sub/$bin\",\"status\":\"XPASS\"}" > "$WORK/${sub}_${bin}.json"
    else
      echo "$sub/$bin : PASS"
      echo "{\"test\":\"kselftest/$sub/$bin\",\"status\":\"PASS\"}" > "$WORK/${sub}_${bin}.json"
    fi
  else
    if is_known_fail "$sub/$bin"; then
      echo "$sub/$bin : XFAIL (known failure, see docs/findings-pointer-masking.md)"
      grep -E '^(not ok|# FAILED|# Totals)' "$log" | head -3 | sed 's/^/    /'
      echo "{\"test\":\"kselftest/$sub/$bin\",\"status\":\"XFAIL\",\"rc\":$rc}" > "$WORK/${sub}_${bin}.json"
    else
      echo "$sub/$bin : FAIL (rc=$rc)"
      grep -E '^(not ok|# FAILED|# Totals)' "$log" | head -4 | sed 's/^/    /'
      echo "{\"test\":\"kselftest/$sub/$bin\",\"status\":\"FAIL\",\"rc\":$rc}" > "$WORK/${sub}_${bin}.json"
    fi
  fi
}

echo
echo "[run] hwprobe / vector / sigreturn / abi"
run_one hwprobe hwprobe 60
run_one hwprobe cbo 60
run_one hwprobe which-cpus 60
run_one vector vstate_prctl 120
run_one vector v_initval 120
run_one vector vstate_ptrace 180
# note: v_exec_initval_nolibc / vstate_exec_nolibc are helpers exec'd by
# v_initval / vstate_prctl above (which passed), not standalone tests.
run_one vector validate_v_ptrace 120
run_one sigreturn sigreturn 60
run_one abi pointer_masking 60

echo "[run] mm (via run_mmap.sh, ulimit -s unlimited)"
MMLOG="$WORK/mm.log"
if [ -x "$ST_OUT/mm/mmap_bottomup" ]; then
  (cd "$ST_OUT/mm" && timeout 120 bash "$KERNEL_SRC/tools/testing/selftests/riscv/mm/run_mmap.sh") > "$MMLOG" 2>&1
  if grep -q '^not ok' "$MMLOG"; then
    echo "mm (run_mmap.sh) : FAIL"
    echo '{"test":"kselftest/mm/run_mmap.sh","status":"FAIL"}' > "$WORK/mm.json"
  else
    echo "mm (run_mmap.sh) : PASS"
    echo '{"test":"kselftest/mm/run_mmap.sh","status":"PASS"}' > "$WORK/mm.json"
  fi
else
  echo "mm (run_mmap.sh) : SKIP (not built)"
  echo '{"test":"kselftest/mm/run_mmap.sh","status":"SKIP","reason":"not built"}' > "$WORK/mm.json"
fi

# ------------------------------------------------------------ aggregate ----
python3 - "$WORK" "$OUT" <<'PY'
import json, sys, glob, os
work, out = sys.argv[1], sys.argv[2]
items = []
for f in sorted(glob.glob(os.path.join(work, '*.json'))):
    try:
        items.append(json.load(open(f)))
    except Exception as e:
        items.append({"file": os.path.basename(f), "error": str(e)})
st = [i.get("status") for i in items]
overall = "FAIL" if "FAIL" in st else "PASS"
summary = {"test": "kselftest", "status": overall,
           "pass": st.count("PASS"), "fail": st.count("FAIL"), "skip": st.count("SKIP"),
           "xfail": st.count("XFAIL"), "xpass": st.count("XPASS"),
           "tests": items}
json.dump(summary, open(os.path.join(out, "kselftest.json"), "w"), indent=2)
print("kselftest summary: %s (pass=%d fail=%d skip=%d xfail=%d xpass=%d)" % (
    overall, st.count("PASS"), st.count("FAIL"), st.count("SKIP"),
    st.count("XFAIL"), st.count("XPASS")))
PY

grep -q '"status": "FAIL"' "$OUT/kselftest.json" && exit 1 || exit 0
