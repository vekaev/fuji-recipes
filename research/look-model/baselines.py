"""Trivial predictors, to calibrate the score. Use as score.py --predict "python3 -I research/look-model/baselines.py neutral".
neutral: Provia, everything 0. library-mean: the library's most common film with its median settings.
They ignore the case folder (the last argument)."""
import json, os, sys, glob, statistics, collections
neutral = {"film": "Provia", "grain_roughness": "Off", "grain_size": "Off", "color_chrome": "Off", "color_chrome_fx_blue": "Off",
           "wb": "Auto", "wb_kelvin": None, "wb_red": 0, "wb_blue": 0, "dynamic_range": "DR100", "d_range_priority": "Off",
           "highlight": 0, "shadow": 0, "color": 0, "mono_warm_cool": None, "mono_magenta_green": None,
           "sharpness": 0, "high_iso_nr": 0, "clarity": 0}
if sys.argv[1] == "neutral":
    print(json.dumps(neutral))
else:
    lib = [json.load(open(f))["settings"] for f in glob.glob(os.path.expanduser("~/Documents/FujiRecipes/recipes/*.json"))]
    film = collections.Counter(s["film"] for s in lib).most_common(1)[0][0]
    same = [s for s in lib if s["film"] == film]
    m = dict(neutral, film=film)
    for k in ("wb_red", "wb_blue", "color"): m[k] = int(round(statistics.median(s[k] for s in same)))
    for k in ("highlight", "shadow"): m[k] = round(2 * statistics.median(s[k] for s in same)) / 2
    m["dynamic_range"] = collections.Counter(s["dynamic_range"] for s in same).most_common(1)[0][0]
    if m["dynamic_range"] not in ("DR100", "DR200", "DR400"): m["dynamic_range"] = "DR400"
    print(json.dumps(m))
