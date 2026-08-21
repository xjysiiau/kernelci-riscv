#!/usr/bin/env python3
"""Aggregate results/history/*.json into a pass-rate trend table.

XFAIL = known upstream failure (expected outcome, counts as healthy).
XPASS = a known failure no longer reproduces (upstream likely fixed it).
"""
import glob
import json
import os
import sys

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HIST = os.path.join(BASE, "results", "history")
OUT = os.path.join(BASE, "results", "trend.md")

records = []
for f in sorted(glob.glob(os.path.join(HIST, "*.json"))):
    try:
        records.append((os.path.basename(f), json.load(open(f))))
    except Exception as e:  # noqa: BLE001
        print("skip", f, e)

if not records:
    print("no history records under", HIST)
    sys.exit(0)

# collect test names (flattening the nested kselftest list), keep order
test_names = []
for _, d in records:
    for t in d.get("tests", []):
        if t.get("test") == "kselftest":
            for sub in t.get("tests", []):
                test_names.append(sub.get("test"))
        else:
            test_names.append(t.get("test"))
test_names = list(dict.fromkeys(test_names))


def status_of(d, name):
    for t in d.get("tests", []):
        if t.get("test") == name:
            return t.get("status", "?")
        if t.get("test") == "kselftest":
            for sub in t.get("tests", []):
                if sub.get("test") == name:
                    return sub.get("status", "?")
    return "-"


HEALTHY = ("PASS", "XFAIL")
lines = ["# Regression pass-rate history", "",
         "Runs: %d | XFAIL = known upstream failure (expected) | "
         "XPASS = known failure fixed upstream" % len(records), ""]
header = ["test"] + ["%s<br>%s" % (d["_kernel"], d["_recorded_at"][4:12])
                     for _, d in records] + ["pass%"]
lines.append("| " + " | ".join(header) + " |")
lines.append("|" + "---|" * (len(records) + 2))

for name in test_names:
    cells = []
    healthy = 0
    for _, d in records:
        s = status_of(d, name)
        cells.append(s if s != "?" else "-")
        if s in HEALTHY:
            healthy += 1
    lines.append("| %s | %s | %d%% |" % (name, " | ".join(cells),
                                          round(100 * healthy / len(records))))

cells = []
ok = 0
for _, d in records:
    s = d.get("summary", {}).get("overall", "?")
    cells.append(s)
    if s == "PASS":
        ok += 1
lines.append("| **overall** | %s | %d%% |" % (" | ".join(cells),
                                              round(100 * ok / len(records))))

md = "\n".join(lines) + "\n"
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as f:
    f.write(md)
print(md)
print("trend written to", OUT)
