"""Recipes and camera jobs for the look model (research/look-model/PLAN.md).

python3 -I recipes.py cases   -> cases-val.json, cases-test.json (frozen: the loop never rewrites them) + eval-jobs.jsonl
python3 -I recipes.py train N -> train-jobs.jsonl: N random recipes, each on 4 train scenes (append; seeds don't repeat)

Everything lands in ~/Library/Caches/FujiRecipes/look-model. The camera renders them with
`fuji render-batch <jobs> --cache <data>/renders`.
"""
import json, os, random, sys, glob

DATA = os.path.expanduser("~/Library/Caches/FujiRecipes/look-model")
LIB = os.path.expanduser("~/Documents/FujiRecipes/recipes")
COLOUR = ["Provia", "Velvia", "Astia", "Classic Chrome", "Reala Ace", "Pro Neg. Hi", "Pro Neg. Std", "Classic Neg.",
          "Nostalgic Neg.", "Eterna", "Eterna Bleach Bypass"]
MONO = ["Acros", "Acros+Ye", "Acros+R", "Acros+G", "Monochrome", "Monochrome+Ye", "Monochrome+R", "Monochrome+G", "Sepia"]
WB = [("Auto", 40), ("Daylight", 14), ("Kelvin", 24), ("Shade", 5), ("Incandescent", 3), ("Fluorescent 1", 2),
      ("Fluorescent 2", 2), ("Fluorescent 3", 2), ("Underwater", 2), ("Auto White Priority", 3), ("Auto Ambience Priority", 3)]
HALF = [x / 2 for x in range(-4, 9)]          # -2 ... +4


def pick(rng, weighted):
    return rng.choices([w[0] for w in weighted], [w[1] for w in weighted])[0]


def random_recipe(rng, max_dr):
    """A recipe from the camera's whole range, with the spread recipes really use (more mass near the middle)."""
    mono = rng.random() < 0.2
    s = {"film": rng.choice(MONO if mono else COLOUR)}
    g = pick(rng, [("Off", 40), ("Weak", 30), ("Strong", 30)])
    s["grain_roughness"] = g
    s["grain_size"] = "Off" if g == "Off" else rng.choice(["Small", "Large"])
    s["color_chrome"] = pick(rng, [("Off", 34), ("Weak", 33), ("Strong", 33)])
    s["color_chrome_fx_blue"] = pick(rng, [("Off", 34), ("Weak", 33), ("Strong", 33)])
    s["wb"] = pick(rng, WB)
    s["wb_kelvin"] = rng.randrange(2800, 9001, 100) if s["wb"] == "Kelvin" else None
    tri = lambda lo, hi: int(round(rng.triangular(lo, hi, 0)))
    s["wb_red"], s["wb_blue"] = tri(-9, 9), tri(-9, 9)
    s["dynamic_range"] = rng.choice(["DR100", "DR200", "DR400"][: {100: 1, 200: 2, 400: 3}[max_dr]])
    s["d_range_priority"] = "Off"          # the camera can't render D-Range Priority from a RAW yet
    s["highlight"] = rng.choice(HALF[:9] + [x for x in HALF if -1.5 <= x <= 1.5])   # -2..+2 mostly, +4 rare
    s["shadow"] = rng.choice(HALF[:11] + [x for x in HALF if -1.5 <= x <= 1.5])
    if mono:
        s["color"] = None
        s["mono_warm_cool"] = tri(-9, 9) if rng.random() < 0.4 else 0
        s["mono_magenta_green"] = tri(-9, 9) if rng.random() < 0.3 else 0
    else:
        s["color"] = rng.randint(-4, 4)
        s["mono_warm_cool"] = s["mono_magenta_green"] = None
    s["sharpness"] = rng.randint(-4, 4)
    s["high_iso_nr"] = rng.randint(-4, 4)
    s["clarity"] = 0 if rng.random() < 0.5 else rng.randint(-5, 5)
    return s


def library_recipes():
    out = []
    for f in sorted(glob.glob(f"{LIB}/*.json")):
        r = json.load(open(f))
        s = dict(r["settings"])
        if s.get("d_range_priority", "Off") != "Off":
            continue
        out.append((r["slug"], s))
    return out


def dr_of(s):
    return int(s["dynamic_range"][2:]) if s["dynamic_range"].startswith("DR") else 100


def make_cases(rng, scenes, split, n_random, lib):
    pool = [s for s in scenes if s["split"] == split]
    cases = []
    recipes = [("random", random_recipe(rng, 400)) for _ in range(n_random)] + lib
    for i, (src, rec) in enumerate(recipes):
        ok = [s for s in pool if s["dr"] >= dr_of(rec)]
        chosen = rng.sample(ok, 8)
        cases.append({"id": f"{split}-{i:02d}", "source": src, "recipe": rec,
                      "refs": [c["raf"] for c in chosen[:3]], "inputs": [c["raf"] for c in chosen[3:5]],
                      "evals": [c["raf"] for c in chosen[5:]]})
    return cases


def main():
    scenes = json.load(open(f"{DATA}/scenes.json"))
    if sys.argv[1] == "cases":
        for name in ("cases-val.json", "cases-test.json"):
            if os.path.exists(f"{DATA}/{name}"):
                sys.exit(f"{name} exists: the cases are frozen. Delete it by hand only to start a new benchmark.")
        rng = random.Random(20261105)
        lib = library_recipes(); rng.shuffle(lib)
        half = len(lib) // 2
        val = make_cases(rng, scenes, "val", 30, [(f"library:{a}", b) for a, b in lib[:10]])
        test = make_cases(rng, scenes, "test", 28, [(f"library:{a}", b) for a, b in lib[half:half + 12]])
        json.dump(val, open(f"{DATA}/cases-val.json", "w"), indent=1)
        json.dump(test, open(f"{DATA}/cases-test.json", "w"), indent=1)
        with open(f"{DATA}/eval-jobs.jsonl", "w") as f:
            for c in val + test:
                for raf in c["refs"] + c["evals"]:
                    f.write(json.dumps({"raf": raf, "settings": c["recipe"]}) + "\n")
        print(len(val), "val and", len(test), "test cases;", 6 * (len(val) + len(test)), "renders in eval-jobs.jsonl")
    elif sys.argv[1] == "train":
        n = int(sys.argv[2])
        path = f"{DATA}/train-jobs.jsonl"
        start = sum(1 for _ in open(path)) // 4 if os.path.exists(path) else 0
        train = [s for s in scenes if s["split"] == "train"]
        with open(path, "a") as f:
            for k in range(start, start + n):
                rng = random.Random(1_000_000 + k)
                rec = random_recipe(rng, 400)
                for sc in rng.sample([s for s in train if s["dr"] >= dr_of(rec)], 4):
                    f.write(json.dumps({"raf": sc["raf"], "settings": rec, "recipe_id": k}) + "\n")
        print(f"recipes {start}..{start + n - 1} -> {path}")


main()
