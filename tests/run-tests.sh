#!/bin/bash
# tests/run-tests.sh
# Run all functional tests and aggregate the per-test JSON reports.
set -u

SD=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$SD/build}
mkdir -p "$OUT"

overall=PASS
for t in cpuinfo vector kselftest boot; do
  [ -x "$SD/$t/run.sh" ] || continue
  echo "===================== $t ====================="
  if OUT="$OUT" "$SD/$t/run.sh"; then
    echo "[$t] OK"
  else
    echo "[$t] FAILED"
    overall=FAIL
  fi
done

python3 - "$OUT" <<'PY'
import json, sys, glob, os
out = sys.argv[1]
items = []
for f in sorted(glob.glob(os.path.join(out, '*.json'))):
    if os.path.basename(f) == 'results.json':
        continue
    try:
        items.append(json.load(open(f)))
    except Exception as e:
        items.append({"file": os.path.basename(f), "error": str(e)})
statuses = [i.get("status") for i in items if isinstance(i, dict)]
overall = "PASS" if statuses and all(s == "PASS" for s in statuses) else "FAIL"
json.dump({"tests": items, "summary": {"total": len(items), "overall": overall}},
          open(os.path.join(out, "results.json"), "w"), indent=2)
print("summary:", os.path.join(out, "results.json"), "->", overall)
PY

echo "OVERALL: $overall"
[ "$overall" = PASS ]
