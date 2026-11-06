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


def banned_ids():
    """Training recipes too close to a val / test recipe (jobs.py ban): never trained on."""
    path = f"{DATA}/train-banned.json"
    return set(json.load(open(path))) if os.path.exists(path) else set()


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
    if a.shape[0] > a.shape[1]:   # macOS turns portrait shots upright; the camera's preview stays in sensor orientation
        a = np.ascontiguousarray(np.rot90(a, 3))
    out = np.stack([np.asarray(Image.fromarray(a[..., c], mode="F").resize((W, H), Image.BOX)) for c in range(3)], -1)
    _raw_cache[raf] = out.astype(np.float32)
    return _raw_cache[raf]


def raf_meta(raf):
    """A RAW's own facts the camera's processing depends on: as-shot white balance and baseline exposure (macOS),
    ISO and the shot's dynamic range (EXIF). Cached in <data>/meta-cache. Works for any RAF a method is given."""
    import subprocess
    stem = os.path.splitext(os.path.basename(raf))[0]
    path = f"{DATA}/meta-cache/{stem}.json"
    if os.path.exists(path): return json.load(open(path))
    os.makedirs(f"{DATA}/meta-cache", exist_ok=True)
    tmp = f"{DATA}/meta-cache/.{stem}.scenes.json"
    json.dump([{"raf": raf}], open(tmp, "w"))
    out = subprocess.run([f"{DATA}/meta", tmp], capture_output=True, text=True).stdout.strip().splitlines()
    m = json.loads(out[0]) if out else {}
    e = json.loads(subprocess.run(["exiftool", "-fast", "-j", "-n", "-ISO", "-DevelopmentDynamicRange", raf], capture_output=True, text=True).stdout or "[{}]")[0]
    m["iso"] = float(e.get("ISO") or 400); m["dr"] = int(e.get("DevelopmentDynamicRange") or 100)
    json.dump(m, open(path, "w")); os.remove(tmp)
    return m


def scene_meta():
    """{raf: raf_meta(raf)} for every scene in scenes.json."""
    return {s["raf"]: raf_meta(s["raf"]) for s in json.load(open(f"{DATA}/scenes.json"))}


def scene_vec(raw, meta):
    """Global facts about a scene the camera's processing depends on (exposure, as-shot white balance)."""
    luma = 0.2126 * raw[..., 0] + 0.7152 * raw[..., 1] + 0.0722 * raw[..., 2]
    ll = np.log2(np.clip(luma, 1e-4, None))
    p = np.percentile(ll, [5, 25, 50, 75, 95, 99])
    t = (meta.get("temperature", 5500) - 5500) / 2000 if meta else 0.0
    tint = meta.get("tint", 0) / 20 if meta else 0.0
    be = meta.get("baseline_exposure", 0) / 2 if meta else 0.0
    iso = np.log2(meta.get("iso", 400) / 400) / 4 if meta else 0.0
    dr = 1.0 if meta and meta.get("dr", 100) >= 400 else 0.0
    return np.array([*(p / 8), t, tint, ll.mean() / 8, be, iso, dr], dtype=np.float32)
