# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow", "scikit-image"]
# ///
"""The fixed evaluation of the look model (research/look-model/PLAN.md). The improvement loop never edits this file.

uv run research/look-model/score.py <val|test> <predictions.json> [--label name]

predictions.json: {"<case id>": {recipe settings}, ...} for every case of the split. The camera develops each found
recipe on the case's 3 eval scenes (cached), and they are compared with the hidden recipe's renders of the same scenes:
mean CIEDE2000 per case. Pass: ΔE00 <= 3. Prints one line:
  score 0.725 passed 29/40 dE 2.41 film 0.55 | <label>
and appends it, with every case, to <data>/scores.jsonl. Needs the camera only for renders not cached yet.
"""
import json, os, subprocess, sys, tempfile, time
import numpy as np
from PIL import Image
from skimage.color import rgb2lab, deltaE_ciede2000

DATA = os.path.expanduser("~/Library/Caches/FujiRecipes/look-model")
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FUJI = os.path.join(REPO, ".build/debug/fuji")
PASS = 3.0


def lab(path):
    im = Image.open(path).convert("RGB")
    return rgb2lab(np.asarray(im, dtype=np.float64) / 255.0)


def delta(a, b):
    A, B = lab(a), lab(b)
    if A.shape != B.shape:   # same RAW, so this shouldn't happen; crop to the common size
        h, w = min(A.shape[0], B.shape[0]), min(A.shape[1], B.shape[1]); A, B = A[:h, :w], B[:h, :w]
    return float(deltaE_ciede2000(A, B).mean())


def render(jobs):
    """Runs the camera batch for [(raf, settings)] and returns the JPEG path per job (None if it failed)."""
    with tempfile.TemporaryDirectory() as t:
        jp, mp = os.path.join(t, "jobs.jsonl"), os.path.join(t, "manifest.jsonl")
        with open(jp, "w") as f:
            for raf, s in jobs: f.write(json.dumps({"raf": raf, "settings": s}) + "\n")
        r = subprocess.run([FUJI, "render-batch", jp, "--cache", f"{DATA}/renders", "--manifest", mp], capture_output=True, text=True)
        if r.returncode != 0: sys.exit("render-batch failed: " + (r.stdout + r.stderr).strip()[-400:])
        out = {}
        for l in open(mp):
            o = json.loads(l); out[o["line"]] = o["jpeg"]
        return [out.get(i) for i in range(len(jobs))]


def main():
    split, pred_path = sys.argv[1], sys.argv[2]
    label = sys.argv[sys.argv.index("--label") + 1] if "--label" in sys.argv else os.path.basename(pred_path)
    cases = json.load(open(f"{DATA}/cases-{split}.json"))
    preds = json.load(open(pred_path))
    missing = [c["id"] for c in cases if c["id"] not in preds]
    if missing: sys.exit(f"predictions missing for {len(missing)} cases, e.g. {missing[:3]}")
    jobs = []
    for c in cases:
        for raf in c["evals"]:
            jobs += [(raf, c["recipe"]), (raf, preds[c["id"]])]
    paths = render(jobs)
    rows, k = [], 0
    for c in cases:
        ds = []
        for _ in c["evals"]:
            t, f = paths[k], paths[k + 1]; k += 2
            ds.append(delta(t, f) if t and f else 99.0)
        d = float(np.mean(ds))
        rows.append({"id": c["id"], "dE": round(d, 2), "pass": d <= PASS,
                     "film": preds[c["id"]].get("film") == c["recipe"]["film"]})
    n = len(rows); passed = sum(r["pass"] for r in rows)
    line = (f"score {passed / n:.3f} passed {passed}/{n} dE {np.mean([r['dE'] for r in rows]):.2f} "
            f"film {np.mean([r['film'] for r in rows]):.2f} | {label}")
    print(line)
    with open(f"{DATA}/scores.jsonl", "a") as f:
        f.write(json.dumps({"time": time.strftime("%Y-%m-%d %H:%M"), "split": split, "label": label, "line": line, "cases": rows}) + "\n")


main()
