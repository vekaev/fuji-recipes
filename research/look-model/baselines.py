"""Trivial predictions, to calibrate the score: python3 -I baselines.py <val|test> -> baseline-*.json in the data folder.
neutral: Provia with everything at 0. library-mean: the library's most common film with its median settings."""
import json, os, sys, glob, statistics, collections
DATA = os.path.expanduser("~/Library/Caches/FujiRecipes/look-model")
split = sys.argv[1]
cases = json.load(open(f"{DATA}/cases-{split}.json"))
neutral = {"film": "Provia", "grain_roughness": "Off", "grain_size": "Off", "color_chrome": "Off", "color_chrome_fx_blue": "Off",
           "wb": "Auto", "wb_kelvin": None, "wb_red": 0, "wb_blue": 0, "dynamic_range": "DR100", "d_range_priority": "Off",
           "highlight": 0, "shadow": 0, "color": 0, "mono_warm_cool": None, "mono_magenta_green": None,
           "sharpness": 0, "high_iso_nr": 0, "clarity": 0}
lib = [json.load(open(f))["settings"] for f in glob.glob(os.path.expanduser("~/Documents/FujiRecipes/recipes/*.json"))]
film = collections.Counter(s["film"] for s in lib).most_common(1)[0][0]
mean = dict(neutral, film=film, **{k: statistics.median(s[k] for s in lib if s["film"] == film) for k in ("wb_red", "wb_blue", "highlight", "shadow")})
mean["color"] = round(statistics.median(s["color"] for s in lib if s["film"] == film))
mean["wb_red"], mean["wb_blue"] = int(mean["wb_red"]), int(mean["wb_blue"])
for name, s in (("neutral", neutral), ("library-mean", mean)):
    json.dump({c["id"]: s for c in cases}, open(f"{DATA}/baseline-{name}-{split}.json", "w"))
    print(name, s["film"], s["wb_red"], s["wb_blue"], s["highlight"], s["shadow"], s["color"])
