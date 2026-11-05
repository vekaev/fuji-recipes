# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow", "scikit-image"]
# ///
"""The fixed evaluation of the look model (research/look-model/PLAN.md). The improvement loop never edits this file.

  uv run research/look-model/score.py val --predict "<command>" [--label name]
  uv run research/look-model/score.py val --predictions preds.json [--label name]      (val only)
  uv run research/look-model/score.py test --predict "<command>" --label name          (milestones only)
  uv run research/look-model/score.py val --packages                                   (just build the case folders)

Each case runs `<command> <case folder>` in its own process. The folder holds only what a user would give: refs/*.jpg
(the hidden recipe developed on 3 scenes the method never gets the RAWs of; re-encoded, random names, no EXIF) and
inputs.json (2 of the owner's RAFs). The command prints the recipe as JSON on its last line.

Judging: the found recipe and the hidden one are developed on 3 more of the owner's scenes. Grain, sharpness and
noise reduction are copied from the hidden recipe first (texture, not the look), the renders are shrunk 4x, and
CIEDE2000 is averaged per scene (and its 90th percentile, which catches local changes such as Color or
Color Chrome). A case matches when its worst scene's mean is <= 3.
Prints: "dE 2.84 match 0.61 (49/80) p90 5.2 worst 3.10 film 0.55 | colour dE … | mono dE … | label" (lower dE is better).
val: every case goes to look-model/scores.jsonl. test: only the summary, to look-holdout/scores.jsonl.
"""
import json, os, random, shutil, subprocess, sys, tempfile, time, hashlib
import numpy as np
from PIL import Image
from skimage.color import rgb2lab, deltaE_ciede2000

DATA = os.path.expanduser("~/Library/Caches/FujiRecipes/look-model")
HOLD = os.path.expanduser("~/Library/Caches/FujiRecipes/look-holdout")
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FUJI = os.path.join(REPO, ".build/debug/fuji")
MATCH = 3.0
TEXTURE = ("grain_roughness", "grain_size", "sharpness", "high_iso_nr")


def arg(name, default=None):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def lab(path):
    im = Image.open(path).convert("RGB")
    if im.size == (640, 480):   # the camera's preview: a 3:2 photo letterboxed into 4:3 (black bars of ~27 rows)
        im = im.crop((0, 28, 640, 452))
    im = im.resize((max(1, im.width // 4), max(1, im.height // 4)), Image.BOX)
    return rgb2lab(np.asarray(im, dtype=np.float64) / 255.0)


def delta(a, b):
    """(mean, 90th percentile) CIEDE2000 between two renders of the same scene."""
    A, B = lab(a), lab(b)
    h, w = min(A.shape[0], B.shape[0]), min(A.shape[1], B.shape[1])
    d = deltaE_ciede2000(A[:h, :w], B[:h, :w])
    return float(d.mean()), float(np.percentile(d, 90))


def render(jobs, cache):
    with tempfile.TemporaryDirectory() as t:
        jp, mp = os.path.join(t, "jobs.jsonl"), os.path.join(t, "manifest.jsonl")
        with open(jp, "w") as f:
            for raf, s in jobs: f.write(json.dumps({"raf": raf, "settings": s}) + "\n")
        r = subprocess.run([FUJI, "render-batch", jp, "--cache", cache, "--manifest", mp], capture_output=True, text=True)
        if r.returncode != 0: sys.exit("render-batch failed: " + (r.stdout + r.stderr).strip()[-400:])
        out = {json.loads(l)["line"]: json.loads(l)["jpeg"] for l in open(mp)}
        return [out.get(i) for i in range(len(jobs))]


def package(c, base, cache):
    """The case folder a method sees. Built once; ref names are a hash of a secret salt, so they say nothing."""
    d = os.path.join(base, "packages", c["id"])
    if os.path.exists(os.path.join(d, "inputs.json")): return d
    os.makedirs(os.path.join(d, "refs"), exist_ok=True)
    salt_file = os.path.join(base, ".salt")
    if not os.path.exists(salt_file): open(salt_file, "w").write(os.urandom(16).hex())
    salt = open(salt_file).read()
    paths = render([(raf, c["recipe"]) for raf in c["refs"]], cache)
    for i, p in enumerate(paths):
        if not p: sys.exit(f"reference render failed for {c['id']}")
        name = hashlib.sha256(f"{salt}{c['id']}{i}".encode()).hexdigest()[:12]
        Image.open(p).convert("RGB").save(os.path.join(d, "refs", name + ".jpg"), quality=92)   # no EXIF
    json.dump({"inputs": c["inputs"]}, open(os.path.join(d, "inputs.json"), "w"))
    return d


def predict(cmd, d):
    with tempfile.TemporaryDirectory() as t:   # a fresh copy, so a method can't leave notes between cases
        w = os.path.join(t, "case"); shutil.copytree(d, w)
        r = subprocess.run(cmd + " " + json.dumps(w), shell=True, capture_output=True, text=True, timeout=900)
        lines = [l for l in r.stdout.strip().splitlines() if l.strip().startswith("{")]
        if r.returncode != 0 or not lines:
            print(f"  predictor failed on {os.path.basename(d)}: {(r.stderr or r.stdout).strip()[-300:]}", file=sys.stderr)
            return None
        return json.loads(lines[-1])


def main():
    split = sys.argv[1]
    if split not in ("val", "test"): sys.exit("split: val or test")
    base = DATA if split == "val" else HOLD
    cases = json.load(open(f"{base}/cases-{split}.json"))
    cache = f"{base}/eval-renders"
    label = arg("--label", "unnamed")
    if "--packages" in sys.argv:   # only build the case folders (from cached renders), e.g. to try a predictor by hand
        for c in cases: package(c, base, cache)
        print(f"{len(cases)} case folders in {base}/packages"); return
    if arg("--predictions"):
        if split == "test": sys.exit("test takes --predict only (each case in its own process)")
        preds = json.load(open(arg("--predictions")))
    else:
        cmd = arg("--predict") or sys.exit("--predict <command> or --predictions <file>")
        preds = {}
        for c in cases:
            preds[c["id"]] = predict(cmd, package(c, base, cache))
    jobs = []
    for c in cases:
        f = dict(preds.get(c["id"]) or c["recipe"] | {"film": "__none__"})
        for k in TEXTURE: f[k] = c["recipe"][k]
        preds[c["id"]] = f
        for raf in c["evals"]: jobs += [(raf, c["recipe"]), (raf, f)]
    # A failed prediction has no renders and counts as dE 99.
    paths = render([(r, s) for r, s in jobs if s.get("film") != "__none__"], cache)
    it = iter(paths); rows = []
    for c in cases:
        failed = preds[c["id"]].get("film") == "__none__"
        ds, p90 = [], []
        for _ in c["evals"]:
            if failed: ds.append(99.0); p90.append(99.0); continue
            t, f = next(it), next(it)
            m, p = delta(t, f) if t and f else (99.0, 99.0)
            ds.append(m); p90.append(p)
        mono = c["recipe"].get("color") is None
        rows.append({"id": c["id"], "source": c["source"].split(":")[0], "mono": mono, "dE": round(float(np.mean(ds)), 2),
                     "worst": round(max(ds), 2), "p90": round(float(np.mean(p90)), 2), "match": max(ds) <= MATCH, "film": preds[c["id"]].get("film") == c["recipe"]["film"]})

    def summary(rs):
        if not rs: return "-"
        return f"dE {np.mean([r['dE'] for r in rs]):.2f} match {np.mean([r['match'] for r in rs]):.2f} ({sum(r['match'] for r in rs)}/{len(rs)})"
    line = (f"{summary(rows)} p90 {np.mean([r['p90'] for r in rows]):.2f} worst {np.mean([r['worst'] for r in rows]):.2f} film {np.mean([r['film'] for r in rows]):.2f}"
            f" | colour {summary([r for r in rows if not r['mono']])} | mono {summary([r for r in rows if r['mono']])}"
            f" | real {summary([r for r in rows if r['source'] != 'random'])} | random {summary([r for r in rows if r['source'] == 'random'])}"
            f" | {label}")
    print(line)
    rec = {"time": time.strftime("%Y-%m-%d %H:%M"), "split": split, "label": label, "line": line}
    if split == "val": rec["cases"] = rows
    with open(f"{base}/scores.jsonl", "a") as f: f.write(json.dumps(rec) + "\n")


main()
