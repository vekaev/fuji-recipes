"""research/experiment.py: apply one edit to LookGuess.swift, score it, keep it only if dev improves and held-out
doesn't drop by more than 1; log every run to research/results.tsv. Usage: python3 -I experiment.py <experiments.json>
where the file holds [{"desc": "...", "edits": [["old", "new"], ...]}, ...] applied in order (kept edits stack)."""
import json, os, re, subprocess, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILE = os.path.join(ROOT, "Sources/FujiKit/LookGuess.swift")
LOG = os.path.join(ROOT, "research/results.tsv")

def score():
    out = subprocess.run([os.path.join(ROOT, "research/run.sh")], capture_output=True, text=True, cwd=ROOT)
    m = re.search(r"dev (-?[\d.]+) held-out (-?[\d.]+)(.*)", out.stdout)
    if not m: return None, None, (out.stdout + out.stderr)[-300:]
    return float(m.group(1)), float(m.group(2)), m.group(3).strip()

last = [l.split("\t") for l in open(LOG).read().splitlines()[1:]]
best_dev, best_held = float(last[-1][1]), float(last[-1][2])
for best_row in reversed(last):
    if best_row[3] in ("baseline", "kept"): best_dev, best_held = float(best_row[1]), float(best_row[2]); break
for exp in json.load(open(sys.argv[1])):
    src = open(FILE).read()
    new = src
    ok = True
    for old, rep in exp["edits"]:
        if old not in new: ok = False; break
        new = new.replace(old, rep, 1)
    if not ok:
        print("SKIP (edit doesn't apply):", exp["desc"]); continue
    open(FILE, "w").write(new)
    dev, held, detail = score()
    keep = dev is not None and dev > best_dev + 0.05 and held >= best_held - 1
    if keep:
        best_dev, best_held = dev, held
        subprocess.run(["git", "commit", "-qam", f"research: {exp['desc']} (dev {dev}, held-out {held})"], cwd=ROOT)
    else:
        open(FILE, "w").write(src)
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True, cwd=ROOT).stdout.strip()
    with open(LOG, "a") as f:
        f.write(f"{commit if keep else '-'}\t{dev}\t{held}\t{'kept' if keep else 'discarded'}\t{exp['desc']}\n")
    print(f"{'KEEP' if keep else 'drop'} dev {dev} held {held} | {exp['desc']} | {detail[:160] if not keep else detail}")
