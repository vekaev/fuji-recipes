"""Shared by the look model's training and prediction code (not by score.py, which stays fixed).

- recipe_vec(s): a recipe as numbers (texture settings left out: grain, sharpness and NR don't show at this size;
  settings the camera ignores are zeroed: toning and FX Blue on Sepia, FX Blue on B&W films).
- vec_recipe(v): back to a recipe the camera takes (nearest valid values).
- load_render / load_raw: the camera's preview without its letterbox bars, and the Mac's linear decode, both at the
  same size and aligned.
"""
import json, os
import numpy as np
from PIL import Image

DATA = os.path.expanduser("~/Library/Caches/FujiRecipes/look-model")
FILMS = ["Provia", "Velvia", "Astia", "Classic Chrome", "Reala Ace", "Pro Neg. Hi", "Pro Neg. Std", "Classic Neg.",
         "Nostalgic Neg.", "Eterna", "Eterna Bleach Bypass", "Acros", "Acros+Ye", "Acros+R", "Acros+G", "Monochrome",
         "Monochrome+Ye", "Monochrome+R", "Monochrome+G", "Sepia"]
MONO = set(FILMS[11:])
WBS = ["Auto", "Daylight", "Kelvin", "Shade", "Incandescent", "Fluorescent 1", "Fluorescent 2", "Fluorescent 3",
       "Underwater", "Auto White Priority", "Auto Ambience Priority"]
DRS = ["DR100", "DR200", "DR400"]
EFF = ["Off", "Weak", "Strong"]
W, H = 160, 106          # working size (the 640 x 426 preview / 4)


def recipe_vec(s):
    v = []
    f = s["film"]
    v += [1.0 if f == x else 0.0 for x in FILMS]
    mono = f in MONO
    wb = s["wb"] if s["wb"] in WBS else "Auto"
    v += [1.0 if wb == x else 0.0 for x in WBS]
    v.append(((s.get("wb_kelvin") or 5500) - 5500) / 2000 if wb == "Kelvin" else 0.0)
    v += [s["wb_red"] / 9, s["wb_blue"] / 9]
    dr = s["dynamic_range"] if s["dynamic_range"] in DRS else "DR400"
    v += [1.0 if dr == x else 0.0 for x in DRS]
    v += [s["highlight"] / 2, s["shadow"] / 2]
    v.append(0.0 if mono else (s.get("color") or 0) / 4)
    tone = mono and f != "Sepia"
    v += [(s.get("mono_warm_cool") or 0) / 9 if tone else 0.0, (s.get("mono_magenta_green") or 0) / 9 if tone else 0.0]
    v += [1.0 if s["color_chrome"] == x else 0.0 for x in EFF]
    fxb = "Off" if mono else s["color_chrome_fx_blue"]
    v += [1.0 if fxb == x else 0.0 for x in EFF]
    v.append(s.get("clarity", 0) / 5)
    return np.array(v, dtype=np.float32)


RECIPE_DIM = len(recipe_vec({"film": "Provia", "wb": "Auto", "wb_red": 0, "wb_blue": 0, "dynamic_range": "DR100",
                             "highlight": 0, "shadow": 0, "color": 0, "color_chrome": "Off", "color_chrome_fx_blue": "Off"}))


def neutral():
    return {"film": "Provia", "grain_roughness": "Off", "grain_size": "Off", "color_chrome": "Off", "color_chrome_fx_blue": "Off",
            "wb": "Auto", "wb_kelvin": None, "wb_red": 0, "wb_blue": 0, "dynamic_range": "DR400", "d_range_priority": "Off",
            "highlight": 0.0, "shadow": 0.0, "color": 0, "mono_warm_cool": None, "mono_magenta_green": None,
            "sharpness": 0, "high_iso_nr": -4, "clarity": 0}


def finish(s):
    mono = s["film"] in MONO
    s["color"] = None if mono else int(s.get("color") or 0)
    s["mono_warm_cool"] = int(s.get("mono_warm_cool") or 0) if mono else None
    s["mono_magenta_green"] = int(s.get("mono_magenta_green") or 0) if mono else None
    if s["wb"] != "Kelvin": s["wb_kelvin"] = None
    return s


def load_render(path):
    im = Image.open(path).convert("RGB")
    if im.size == (640, 480): im = im.crop((0, 27, 640, 453))
    return np.asarray(im.resize((W, H), Image.BOX), dtype=np.float32) / 255.0


_raw_cache = {}


def load_raw(raf):
    """The Mac's linear decode of a scene (sRGB primaries, 0..1), at the working size."""
    if raf in _raw_cache: return _raw_cache[raf]
    import tifffile
    stem = os.path.splitext(os.path.basename(raf))[0]
    a = tifffile.imread(f"{DATA}/raw/{stem}.tiff").astype(np.float32)[..., :3] / 65535.0
    out = np.stack([np.asarray(Image.fromarray(a[..., c], mode="F").resize((W, H), Image.BOX)) for c in range(3)], -1)
    _raw_cache[raf] = out.astype(np.float32)
    return _raw_cache[raf]


def scene_meta():
    m = {}
    for l in open(f"{DATA}/meta.jsonl"):
        o = json.loads(l); m[o["raf"]] = o
    return m


def scene_vec(raw, meta):
    """Global facts about a scene the camera's processing depends on (exposure, as-shot white balance)."""
    luma = 0.2126 * raw[..., 0] + 0.7152 * raw[..., 1] + 0.0722 * raw[..., 2]
    ll = np.log2(np.clip(luma, 1e-4, None))
    p = np.percentile(ll, [5, 25, 50, 75, 95, 99])
    t = (meta.get("temperature", 5500) - 5500) / 2000 if meta else 0.0
    tint = meta.get("tint", 0) / 20 if meta else 0.0
    return np.array([*(p / 8), t, tint, ll.mean() / 8], dtype=np.float32)
