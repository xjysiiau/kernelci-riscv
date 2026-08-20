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
: > "$TMP/lost"; : > "$TMP/disabled"; : > "$TMP/changed"; : > "$TMP/new"

while IFS="$(printf '\t')" read -r opt refval actval; do
  if [ "$actval" = "<ABSENT>" ]; then
    case "$refval" in
      y|m)
        echo "  LOST      $opt=$refval (absent from actual)"
        echo "$opt" >> "$TMP/lost"; LOST=$((LOST+1)) ;;
      *) ;;
    esac
  elif [ "$refval" = "<ABSENT>" ]; then
    echo "  new       $opt=$actval"
    echo "$opt" >> "$TMP/new"; NEW=$((NEW+1))
  elif [ "$refval" != "$actval" ]; then
    if [ "$actval" = "n" ]; then
      echo "  DISABLED  $opt  ref=$refval actual=$actval"
      echo "$opt" >> "$TMP/disabled"; DISABLED=$((DISABLED+1))
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
status = "FAIL" if (req_fail or lost or disabled) else ("WARN" if changed else "PASS")
d = {
    "test": "config-drift",
    "reference": ref,
    "actual": actual,
    "required_fail": req_fail,
    "lost": lost,
    "disabled": disabled,
    "changed": changed,
    "new_options": new,
    "status": status,
}
json.dump(d, open(os.path.join(out, "config-drift.json"), "w"), indent=2)
print("\nconfig-drift:", status,
      "(required_fail=%d lost=%d disabled=%d changed=%d new=%d)"
      % (len(req_fail), len(lost), len(disabled), len(changed), len(new)))
PY

[ "$REQ_FAIL" -eq 0 ] && [ "$LOST" -eq 0 ] && [ "$DISABLED" -eq 0 ] || exit 2
[ "$CHANGED" -eq 0 ] || exit 1
exit 0
