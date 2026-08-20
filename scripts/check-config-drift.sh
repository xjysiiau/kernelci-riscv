#!/bin/bash
# scripts/check-config-drift.sh
# Detect kernel configuration drift between the committed reference config
# and the actual built kernel .config.
#
#   FAIL  : a required option (required-opts.txt) is missing/disabled, or a
#           reference =y/=m option was lost from the actual config.
#   WARN  : an option changed value between reference and actual.
#   INFO  : options present only in the actual config (new in this kernel).
#
# Output: <OUT>/config-drift.json + human-readable summary.
# Exit codes: 2 = FAIL-level drift, 1 = WARN-level, 0 = clean/INFO-only.
set -u

PROJECT=$(cd "$(dirname "$0")/.." && pwd)
REF=${REF:-$PROJECT/configs/riscv-qemu/defconfig}
REQ=${REQ:-$PROJECT/configs/riscv-qemu/required-opts.txt}
ACTUAL=${ACTUAL:-$HOME/kernelci-work/linux/.config}
OUT=${OUT:-$PROJECT/build}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

[ -f "$REF" ]    || { echo "ERROR: reference config not found: $REF"; exit 3; }
[ -f "$ACTUAL" ] || { echo "ERROR: actual config not found: $ACTUAL"; exit 3; }
[ -f "$REQ" ]    || { echo "ERROR: required-opts not found: $REQ"; exit 3; }

# normalize a .config into "CONFIG_X<TAB>value" lines (y/m/n/string/number)
norm() {
  awk '
    /^# CONFIG_[A-Za-z0-9_]+ is not set[[:space:]]*$/ { print $2 "\t" "n"; next }
    /^CONFIG_[A-Za-z0-9_]+=/ {
      i = index($0, "=")
      print substr($0, 1, i-1) "\t" substr($0, i+1)
    }
  ' "$1" | sort
}

norm "$REF"    > "$TMP/ref"
norm "$ACTUAL" > "$TMP/actual"

echo "reference : $REF"
echo "actual    : $ACTUAL"

echo
echo "== [1/2] required options (baseline contract) =="
REQ_OK=0; REQ_FAIL=0
: > "$TMP/req.fail"
while read -r spec; do
  [ -z "$spec" ] && continue
  case "$spec" in \#*) continue;; esac
  opt="${spec%%=*}"; want="${spec#*=}"
  got=$(awk -F '\t' -v o="$opt" '$1==o{print $2}' "$TMP/actual")
  if [ "$got" = "$want" ]; then
    REQ_OK=$((REQ_OK+1))
    echo "  ok    $opt=$want"
  else
    REQ_FAIL=$((REQ_FAIL+1))
    echo "  FAIL  $opt  want=$want got=${got:-<absent>}"
    echo "$opt" >> "$TMP/req.fail"
  fi
done < "$REQ"
echo "  required: ok=$REQ_OK fail=$REQ_FAIL"

echo
echo "== [2/2] full diff: reference vs actual =="
join -t "$(printf '\t')" -a1 -a2 -e '<ABSENT>' -o 0,1.2,2.2 \
  "$TMP/ref" "$TMP/actual" > "$TMP/joined"

LOST=0; DISABLED=0; CHANGED=0; NEW=0
MARKER_LOST=0; MARKER_DISABLED=0
: > "$TMP/lost"; : > "$TMP/disabled"; : > "$TMP/changed"; : > "$TMP/new"
: > "$TMP/marker_lost"; : > "$TMP/marker_disabled"

# Environment-dependent capability markers (toolchain/arch auto-detection).
# Losing/changing these only means the build environment differs; it is NOT
# a real configuration regression, so they are WARN-level, never FAIL.
is_marker() {
  case "$1" in
    CONFIG_TOOLCHAIN_HAS_*|CONFIG_CC_HAS_*|CONFIG_CC_CAN_LINK*|CONFIG_CC_IS_*|\
    CONFIG_CC_VERSION*|CONFIG_GCC_VERSION*|CONFIG_LD_VERSION*|CONFIG_LD_IS_*|\
    CONFIG_AS_VERSION*|CONFIG_AS_IS_*|CONFIG_OPENSSL_SUPPORTS_*|\
    CONFIG_ARCH_HAS_*|CONFIG_ARCH_USES_*|CONFIG_HAVE_*)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

while IFS="$(printf '\t')" read -r opt refval actval; do
  if [ "$actval" = "<ABSENT>" ]; then
    case "$refval" in
      y|m)
        if is_marker "$opt"; then
          echo "  MARKER-LOST $opt=$refval (absent from actual, env-dependent)"
          echo "$opt" >> "$TMP/marker_lost"; MARKER_LOST=$((MARKER_LOST+1))
        else
          echo "  LOST      $opt=$refval (absent from actual)"
          echo "$opt" >> "$TMP/lost"; LOST=$((LOST+1))
        fi ;;
      *) ;;
    esac
  elif [ "$refval" = "<ABSENT>" ]; then
    echo "  new       $opt=$actval"
    echo "$opt" >> "$TMP/new"; NEW=$((NEW+1))
  elif [ "$refval" != "$actval" ]; then
    if [ "$actval" = "n" ]; then
      if is_marker "$opt"; then
        echo "  MARKER-DISABLED $opt  ref=$refval actual=$actval"
        echo "$opt" >> "$TMP/marker_disabled"; MARKER_DISABLED=$((MARKER_DISABLED+1))
      else
        echo "  DISABLED  $opt  ref=$refval actual=$actval"
        echo "$opt" >> "$TMP/disabled"; DISABLED=$((DISABLED+1))
      fi
    else
      echo "  CHANGED   $opt  ref=$refval actual=$actval"
      echo "$opt" >> "$TMP/changed"; CHANGED=$((CHANGED+1))
    fi
  fi
done < "$TMP/joined"

python3 - "$OUT" "$TMP" "$REF" "$ACTUAL" <<'PY'
import json, sys, os
out, tmp, ref, actual = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
def lines(p):
    try:
        return [l.strip() for l in open(os.path.join(tmp, p)) if l.strip()]
    except FileNotFoundError:
        return []
req_fail, lost, disabled = lines('req.fail'), lines('lost'), lines('disabled')
changed, new = lines('changed'), lines('new')
marker_lost, marker_disabled = lines('marker_lost'), lines('marker_disabled')
status = "FAIL" if (req_fail or lost or disabled) else (
    "WARN" if (changed or marker_lost or marker_disabled) else "PASS")
d = {
    "test": "config-drift",
    "reference": ref,
    "actual": actual,
    "required_fail": req_fail,
    "lost": lost,
    "disabled": disabled,
    "changed": changed,
    "marker_lost": marker_lost,
    "marker_disabled": marker_disabled,
    "new_options": new,
    "status": status,
}
json.dump(d, open(os.path.join(out, "config-drift.json"), "w"), indent=2)
print("\nconfig-drift:", status,
      "(required_fail=%d lost=%d disabled=%d changed=%d marker=%d new=%d)"
      % (len(req_fail), len(lost), len(disabled), len(changed),
         len(marker_lost) + len(marker_disabled), len(new)))
PY

# DRIFT_STRICT=required: only the required-opts contract gates the exit code
# (the full diff is still computed and reported). Useful on foreign runners
# whose toolchain/kernel version differs from the local baseline.
if [ "${DRIFT_STRICT:-full}" = "required" ]; then
  if [ "$REQ_FAIL" -eq 0 ]; then
    echo "drift-mode: required-only -> PASS (contract ok)"
    python3 - "$OUT" <<'PY'
import json, sys, os
out = sys.argv[1]
p = os.path.join(out, "config-drift.json")
try:
    d = json.load(open(p))
    d["mode"] = "required"
    d["status"] = "FAIL" if d.get("required_fail") else "PASS"
    json.dump(d, open(p, "w"), indent=2)
except Exception:
    pass
PY
    exit 0
  fi
  exit 2
fi

[ "$REQ_FAIL" -eq 0 ] && [ "$LOST" -eq 0 ] && [ "$DISABLED" -eq 0 ] || exit 2
[ "$CHANGED" -eq 0 ] && [ "$MARKER_LOST" -eq 0 ] && [ "$MARKER_DISABLED" -eq 0 ] || exit 1
exit 0
