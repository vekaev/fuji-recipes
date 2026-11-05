"""research/search-experiment.py: the camera search's research loop on the owner's X-E5 (research/search.md).
Applies one experiment at a time to Sources/FujiKit/Look.swift (the `refine` function), runs the real benchmark,
keeps the change only if the score rises by more than KEEP_MARGIN, logs every run to research/search-results.tsv.
Usage: python3 -I research/search-experiment.py <experiments.json>
  [{"desc": "...", "edits": [["old", "new"], ...], "args": ["--budget", "90"]}, ...]   (edits may be empty: a baseline)
Stops at once (and says why in the status file) when the camera fails or the Fuji Recipes Mac app is opened."""
import json, os, re, subprocess, sys, time, datetime
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILE = os.path.join(ROOT, "Sources/FujiKit/Look.swift")
LOG = os.path.join(ROOT, "research/search-results.tsv")
WORK = os.path.expanduser("~/Library/Caches/FujiRecipes/research")   # renders + per-run logs: the owner's photos, local only
STATUS = os.path.join(WORK, "status.txt")
FOLDER = os.environ.get("REAL_FOLDER", "/Volumes/Untitled/DCIM")
CASES = os.environ.get("REAL_CASES", "16")
KEEP_MARGIN = 2.0     # a quarter of one more recipe recovered (10) isn't noise-proof; 2 points is about one more right film half the time

def status(s):
    with open(STATUS, "a") as f: f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M} {s}\n")
    print(s, flush=True)

def app_open():
    # The executable's own path (ps comm), so a shell whose command line mentions the app doesn't count.
    names = subprocess.run(["ps", "-axo", "comm="], capture_output=True, text=True).stdout.splitlines()
    return any(n.strip().endswith("/Fuji Recipes.app/Contents/MacOS/Fuji Recipes") for n in names)

def run(desc, args):
    b = subprocess.run(["swift", "build"], capture_output=True, text=True, cwd=ROOT)
    if b.returncode != 0: return None, "build failed: " + (b.stdout + b.stderr)[-400:]
    stamp = datetime.datetime.now().strftime("%m%d-%H%M")
    out = os.path.join(WORK, f"run-{stamp}.json"); errlog = os.path.join(WORK, f"run-{stamp}.log")
    with open(errlog, "w") as e:
        e.write(desc + "\n")
        r = subprocess.run([os.path.join(ROOT, ".build/debug/fuji"), "match", "--real", FOLDER, "--cases", CASES,
                            "--cache", os.path.join(WORK, "renders"), "--out", out] + args,
                           stdout=subprocess.PIPE, stderr=e, text=True, cwd=ROOT)
    m = re.search(r"score (-?[\d.]+) recovered (\d+) film (\d+) match (\d+) floor (\d+) renders (\d+)", r.stdout)
    if not m: return None, f"no score (exit {r.returncode}): {r.stdout[-300:]} | see {errlog}"
    return float(m.group(1)), m.group(0)

rows = [l.split("\t") for l in open(LOG).read().splitlines()[1:]] if os.path.exists(LOG) else []
best = None
for row in reversed(rows):
    if row[2] in ("baseline", "kept"): best = float(row[1]); break
for exp in json.load(open(sys.argv[1])):
    if app_open(): status("stopped: the Fuji Recipes Mac app is open (the owner is using the camera)"); break
    src = open(FILE).read(); new = src
    if any(old not in new for old, _ in exp.get("edits", [])):
        status(f"skip (edit doesn't apply): {exp['desc']}"); continue
    for old, rep in exp.get("edits", []): new = new.replace(old, rep, 1)
    open(FILE, "w").write(new)
    t0 = time.time()
    score, detail = run(exp["desc"], exp.get("args", []))
    mins = int((time.time() - t0) / 60)
    if score is None:
        open(FILE, "w").write(src)
        if detail.startswith("build failed"): status(f"skip ({detail[:200]}): {exp['desc']}"); continue
        status(f"stopped: {exp['desc']}: {detail}")
        break
    baseline = best is None or not exp.get("edits") and not exp.get("args")
    keep = not baseline and score > best + KEEP_MARGIN
    if baseline: best = score; verdict = "baseline"
    elif keep:
        best = score; verdict = "kept"
        subprocess.run(["git", "commit", "-q", "-m", f"research (camera search): {exp['desc']} ({detail})", "--", FILE], cwd=ROOT)
    else:
        open(FILE, "w").write(src); verdict = "discarded"
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True, cwd=ROOT).stdout.strip()
    if not os.path.exists(LOG): open(LOG, "w").write("commit\tscore\tverdict\tdetail\tminutes\tdescription\n")
    with open(LOG, "a") as f: f.write(f"{commit if keep else '-'}\t{score}\t{verdict}\t{detail}\t{mins}\t{exp['desc']}\n")
    status(f"{verdict}: {detail} in {mins} min | {exp['desc']}")
status("batch done")
