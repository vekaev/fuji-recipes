"""Recipes and camera jobs for the look model (research/look-model/PLAN.md).

python3 -I recipes.py cases    -> val cases (look-model/cases-val.json) and test cases (look-holdout/cases-test.json),
                                  their camera jobs, and the library split (which real recipes training may build on)
python3 -I recipes.py sweep    -> sweep-jobs.jsonl: every setting at its extremes on 3 train scenes (which settings
                                  the camera really applies, and how much each moves the look)
python3 -I recipes.py train N  -> train-jobs.jsonl: N more recipes, each on 4 train scenes (append; seeds never repeat)

Recipes: half are small changes of real recipes (the library, minus every recipe near a val/test one), half random
over the camera's whole range. Dynamic range is DR100/200/400 (no Auto, no D-Range Priority: the camera can't render
those from a RAW the same way). A DR200/400 recipe only goes on DR400 shots, else the camera would render it at DR100.
"""
import json, os, random, sys, glob

DATA = os.path.expanduser("~/Library/Caches/FujiRecipes/look-model")
HOLD = os.path.expanduser("~/Library/Caches/FujiRecipes/look-holdout")
LIB = os.path.expanduser("~/Documents/FujiRecipes/recipes")
COLOUR = ["Provia", "Velvia", "Astia", "Classic Chrome", "Reala Ace", "Pro Neg. Hi", "Pro Neg. Std", "Classic Neg.",
          "Nostalgic Neg.", "Eterna", "Eterna Bleach Bypass"]
MONO = ["Acros", "Acros+Ye", "Acros+R", "Acros+G", "Monochrome", "Monochrome+Ye", "Monochrome+R", "Monochrome+G", "Sepia"]
WB = [("Auto", 40), ("Daylight", 14), ("Kelvin", 24), ("Shade", 5), ("Incandescent", 3), ("Fluorescent 1", 2),
      ("Fluorescent 2", 2), ("Fluorescent 3", 2), ("Underwater", 2), ("Auto White Priority", 3), ("Auto Ambience Priority", 3)]
TONE = [x / 2 for x in range(-4, 9)]          # -2 ... +4 in half steps
TONE_W = [3, 3, 4, 4, 5, 4, 4, 3, 3, 2, 2, 1, 1]
EFFECT = ["Off", "Weak", "Strong"]


def is_mono(f):
    return f in MONO


def tri(rng, lo, hi):
    return int(round(rng.triangular(lo, hi, 0)))


def finish(s):
    """Make a recipe consistent the way the camera stores it."""
    if is_mono(s["film"]):
        s["color"] = None
        s["mono_warm_cool"] = s.get("mono_warm_cool") or 0
        s["mono_magenta_green"] = s.get("mono_magenta_green") or 0
    else:
        s["color"] = 0 if s.get("color") is None else s["color"]
        s["mono_warm_cool"] = s["mono_magenta_green"] = None
    if s["grain_roughness"] == "Off": s["grain_size"] = "Off"
    elif s.get("grain_size", "Off") == "Off": s["grain_size"] = "Small"
    if s["wb"] != "Kelvin": s["wb_kelvin"] = None
    elif not s.get("wb_kelvin"): s["wb_kelvin"] = 5500
    s["d_range_priority"] = "Off"
    if s.get("dynamic_range") not in ("DR100", "DR200", "DR400"): s["dynamic_range"] = "DR400"
    return s


def random_recipe(rng):
    mono = rng.random() < 0.2
    s = {"film": rng.choice(MONO if mono else COLOUR)}
    g = rng.choices(EFFECT, [40, 30, 30])[0]
    s["grain_roughness"], s["grain_size"] = g, "Off" if g == "Off" else rng.choice(["Small", "Large"])
    s["color_chrome"] = rng.choice(EFFECT)
    s["color_chrome_fx_blue"] = rng.choice(EFFECT)
    s["wb"] = rng.choices([w for w, _ in WB], [p for _, p in WB])[0]
    s["wb_kelvin"] = rng.randrange(2800, 9001, 100) if s["wb"] == "Kelvin" else None
    s["wb_red"], s["wb_blue"] = tri(rng, -9, 9), tri(rng, -9, 9)
    s["dynamic_range"] = rng.choice(["DR100", "DR200", "DR400"])
    s["highlight"] = rng.choices(TONE, TONE_W)[0]
    s["shadow"] = rng.choices(TONE, TONE_W)[0]
    s["color"] = None if mono else rng.randint(-4, 4)
    s["mono_warm_cool"] = (tri(rng, -9, 9) if rng.random() < 0.4 else 0) if mono else None
    s["mono_magenta_green"] = (tri(rng, -9, 9) if rng.random() < 0.3 else 0) if mono else None
    s["sharpness"] = rng.randint(-4, 4)
    s["high_iso_nr"] = rng.randint(-4, 4)
    s["clarity"] = 0 if rng.random() < 0.5 else rng.randint(-5, 5)
    return finish(s)


def perturb(rng, base):
    """A small change of a real recipe: each look setting moves a step or two with some chance; the film rarely."""
    s = dict(base)
    if rng.random() < 0.15:
        s["film"] = rng.choice(MONO if is_mono(s["film"]) else COLOUR)
    clip = lambda v, lo, hi: max(lo, min(hi, v))
    for k in ("wb_red", "wb_blue"):
        if rng.random() < 0.5: s[k] = clip(s[k] + rng.choice([-2, -1, 1, 2]), -9, 9)
    for k in ("highlight", "shadow"):
        if rng.random() < 0.4: s[k] = clip(s[k] + rng.choice([-1, -0.5, 0.5, 1]), -2, 4)
    if not is_mono(s["film"]) and rng.random() < 0.4: s["color"] = clip((s.get("color") or 0) + rng.choice([-2, -1, 1]), -4, 4)
    if rng.random() < 0.2: s["dynamic_range"] = rng.choice(["DR100", "DR200", "DR400"])
    if s["wb"] == "Kelvin" and rng.random() < 0.4: s["wb_kelvin"] = clip((s["wb_kelvin"] or 5500) + rng.choice([-400, -200, 200, 400]), 2500, 10000)
    for k in ("color_chrome", "color_chrome_fx_blue"):
        if rng.random() < 0.2: s[k] = rng.choice(EFFECT)
    if rng.random() < 0.2: s["clarity"] = clip(s["clarity"] + rng.choice([-2, -1, 1, 2]), -5, 5)
    return finish(s)


def library():
    out = []
    for f in sorted(glob.glob(f"{LIB}/*.json")):
        r = json.load(open(f))
        out.append((r["slug"], finish(dict(r["settings"]))))
    return out


def distance(a, b):
    """Steps apart on the settings that show at 640 px (grain, sharpness and NR left out)."""
    d = 0 if a["film"] == b["film"] else 3
    d += abs(a["wb_red"] - b["wb_red"]) + abs(a["wb_blue"] - b["wb_blue"])
    d += 2 * (abs(a["highlight"] - b["highlight"]) + abs(a["shadow"] - b["shadow"]))
    d += abs((a.get("color") or 0) - (b.get("color") or 0)) + abs((a.get("mono_warm_cool") or 0) - (b.get("mono_warm_cool") or 0))
    d += 0 if a["wb"] == b["wb"] else 2
    d += abs((a.get("wb_kelvin") or 0) - (b.get("wb_kelvin") or 0)) / 300
    d += 0 if a["dynamic_range"] == b["dynamic_range"] else 1
    d += 0.5 * (a["color_chrome"] != b["color_chrome"]) + 0.5 * (a["color_chrome_fx_blue"] != b["color_chrome_fx_blue"])
    d += abs(a["clarity"] - b["clarity"]) / 2
    return d


def dr(s):
    return int(s["dynamic_range"][2:])


def make_cases(rng, scenes, split, recipes):
    refs = [s for s in scenes if s["split"] == split and s["role"] == "ref"]
    owners = [s for s in scenes if s["split"] == split and s["role"] == "owner"]
    cases = []
    for i, (src, rec) in enumerate(recipes):
        r = rng.sample([s for s in refs if s["dr"] >= dr(rec)], 3)
        o = rng.sample(owners, 5)
        cases.append({"id": f"{split}-{i:03d}", "source": src, "recipe": rec, "refs": [x["raf"] for x in r],
                      "inputs": [x["raf"] for x in o[:2]], "evals": [x["raf"] for x in o[2:]]})
    return cases


def write_jobs(path, cases):
    with open(path, "w") as f:
        for c in cases:
            for raf in c["refs"] + c["evals"]:
                f.write(json.dumps({"raf": raf, "settings": c["recipe"]}) + "\n")


def cmd_cases():
    for p in (f"{DATA}/cases-val.json", f"{HOLD}/cases-test.json"):
        if os.path.exists(p): sys.exit(f"{p} exists: the cases are frozen. Delete it by hand only to start a new benchmark.")
    scenes = json.load(open(f"{DATA}/scenes.json")) + json.load(open(f"{HOLD}/scenes-test.json"))
    rng = random.Random(20261105)
    lib = library(); rng.shuffle(lib)
    n = len(lib)
    test_lib, val_lib = lib[: n // 4], lib[n // 4: n // 2]
    # Training may build on a library recipe only if it's far from every val/test recipe.
    held = [s for _, s in test_lib + val_lib]
    train_lib = [(a, s) for a, s in lib[n // 2:] if min(distance(s, h) for h in held) > 4]
    def mix(base, k, seed):
        r = random.Random(seed); out = [(f"library:{a}", s) for a, s in base]
        while len(out) < k:
            if r.random() < 0.5:
                a, s = r.choice(base); out.append((f"near:{a}", perturb(r, s)))
            else:
                out.append(("random", random_recipe(r)))
        return out
    val = make_cases(rng, scenes, "val", mix(val_lib, 80, 1))
    test = make_cases(rng, scenes, "test", mix(test_lib, 80, 2))
    json.dump(val, open(f"{DATA}/cases-val.json", "w"), indent=1)
    json.dump(test, open(f"{HOLD}/cases-test.json", "w"), indent=1)
    write_jobs(f"{DATA}/eval-jobs.jsonl", val)
    write_jobs(f"{HOLD}/eval-jobs.jsonl", test)
    json.dump({"train_pool": [a for a, _ in train_lib], "val": [a for a, _ in val_lib], "excluded_near_heldout":
               [a for a, _ in lib[n // 2:] if a not in {x for x, _ in train_lib}]}, open(f"{DATA}/library-split.json", "w"), indent=1)
    json.dump({"test": [a for a, _ in test_lib]}, open(f"{HOLD}/library-split.json", "w"), indent=1)
    print(f"{len(val)} val cases, {len(test)} test cases; library: {len(test_lib)} test, {len(val_lib)} val, "
          f"{len(train_lib)} may seed training, {n // 2 - len(train_lib) + n - n // 2 - n // 2} kept out as near")


def cmd_sweep():
    scenes = [s for s in json.load(open(f"{DATA}/scenes.json")) if s["split"] == "train" and s["dr"] >= 400]
    picks = random.Random(3).sample(scenes, 3)
    base = finish({"film": "Provia", "grain_roughness": "Off", "color_chrome": "Off", "color_chrome_fx_blue": "Off", "wb": "Auto",
                   "wb_red": 0, "wb_blue": 0, "dynamic_range": "DR100", "highlight": 0, "shadow": 0, "color": 0,
                   "sharpness": 0, "high_iso_nr": 0, "clarity": 0})
    variants = [("base", base)]
    for f in COLOUR + MONO: variants.append((f"film={f}", finish(dict(base, film=f))))
    for k, vals in (("wb_red", [-9, 9]), ("wb_blue", [-9, 9]), ("highlight", [-2, 4]), ("shadow", [-2, 4]), ("color", [-4, 4]),
                    ("sharpness", [-4, 4]), ("high_iso_nr", [-4, 4]), ("clarity", [-5, 5])):
        for v in vals: variants.append((f"{k}={v}", finish(dict(base, **{k: v}))))
    for k in ("color_chrome", "color_chrome_fx_blue", "grain_roughness"):
        variants.append((f"{k}=Strong", finish(dict(base, **{k: "Strong"}))))
    for d in ("DR200", "DR400"): variants.append((f"dynamic_range={d}", finish(dict(base, dynamic_range=d))))
    for w, _ in WB: variants.append((f"wb={w}", finish(dict(base, wb=w, wb_kelvin=3000 if w == "Kelvin" else None))))
    for k, v in (("mono_warm_cool", 9), ("mono_magenta_green", 9)):
        for f in ("Acros", "Sepia"): variants.append((f"{f} {k}={v}", finish(dict(base, film=f, **{k: v}))))
    for f in ("Acros", "Sepia"): variants.append((f"{f} fx_blue=Strong", finish(dict(base, film=f, color_chrome_fx_blue="Strong"))))
    with open(f"{DATA}/sweep-jobs.jsonl", "w") as out:
        for name, s in variants:
            for sc in picks: out.write(json.dumps({"raf": sc["raf"], "settings": s, "name": name}) + "\n")
    print(len(variants), "variants x 3 scenes ->", f"{DATA}/sweep-jobs.jsonl")


def cmd_train(n):
    scenes = [s for s in json.load(open(f"{DATA}/scenes.json")) if s["split"] == "train"]
    split = json.load(open(f"{DATA}/library-split.json"))
    pool = [(a, s) for a, s in library() if a in set(split["train_pool"])]
    path = f"{DATA}/train-jobs.jsonl"
    start = sum(1 for _ in open(path)) // 4 if os.path.exists(path) else 0
    with open(path, "a") as f:
        for k in range(start, start + n):
            rng = random.Random(1_000_000 + k)
            rec = perturb(rng, rng.choice(pool)[1]) if pool and rng.random() < 0.5 else random_recipe(rng)
            for sc in rng.sample([s for s in scenes if s["dr"] >= dr(rec)], 4):
                f.write(json.dumps({"raf": sc["raf"], "settings": rec, "recipe_id": k}) + "\n")
    print(f"recipes {start}..{start + n - 1} -> {path}")


if __name__ == "__main__":
    {"cases": cmd_cases, "sweep": cmd_sweep}.get(sys.argv[1], lambda: cmd_train(int(sys.argv[2])))()
