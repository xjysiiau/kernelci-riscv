#!/bin/bash
# scripts/record-result.sh [results.json]
# Archive a run's results.json into results/history/ (timestamped, tagged
# with the kernel version) and regenerate the trend report.
set -euo pipefail

PROJECT=$(cd "$(dirname "$0")/.." && pwd)
SRC=${1:-$PROJECT/build/closed-loop/guest-results/results.json}
HIST="$PROJECT/results/history"
KLOG="$PROJECT/build/closed-loop/qemu.log"

[ -f "$SRC" ] || { echo "ERROR: results file not found: $SRC"; exit 2; }

# kernel version from the boot serial log, e.g. 7.2.0-rc7-g3eb... -> 7.2.0
KV=$(grep -m1 -oE 'Linux version [^ ]+' "$KLOG" 2>/dev/null | sed 's/Linux version //' | cut -d- -f1 || true)
KV=${KV:-unknown}
STAMP=$(date -u +%Y%m%d-%H%M%S)
DEST="$HIST/${STAMP}__${KV}.json"

mkdir -p "$HIST"
python3 - "$SRC" "$DEST" "$KV" "$STAMP" <<'PY'
import json, sys
src, dest, kv, stamp = sys.argv[1:5]
d = json.load(open(src))
d["_recorded_at"] = stamp
d["_kernel"] = kv
json.dump(d, open(dest, "w"), indent=2)
print("recorded:", dest)
PY

if [ -x "$PROJECT/scripts/report-history.py" ]; then
  python3 "$PROJECT/scripts/report-history.py"
fi
