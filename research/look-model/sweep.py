# /// script
# dependencies = ["numpy", "pillow", "scikit-image"]
# ///
"""How far each setting moves the look: ΔE00 (renders shrunk 4x) of each sweep variant against the neutral base,
per scene, plus camera notes (settings it didn't apply). uv run research/look-model/sweep.py"""
import json, os, collections
import numpy as np
from PIL import Image
from skimage.color import rgb2lab, deltaE_ciede2000
D = os.path.expanduser("~/Library/Caches/FujiRecipes/look-model")
jobs = [json.loads(l) for l in open(f"{D}/sweep-jobs.jsonl")]
man = {json.loads(l)["line"]: json.loads(l) for l in open(f"{D}/sweep-manifest.jsonl")}
def lab(p):
    im = Image.open(p).convert("RGB"); im = im.crop((0, 28, 640, 452)) if im.size == (640, 480) else im; im = im.resize((im.width // 4, im.height // 4), Image.BOX)
    return rgb2lab(np.asarray(im, dtype=float) / 255)
base = {j["raf"]: man[i]["jpeg"] for i, j in enumerate(jobs) if j["name"] == "base"}
res = collections.defaultdict(list); notes = collections.defaultdict(set)
for i, j in enumerate(jobs):
    m = man[i]
    if not m["jpeg"]: continue
    res[j["name"]].append(float(deltaE_ciede2000(lab(base[j["raf"]]), lab(m["jpeg"])).mean()))
    for n in m.get("notes") or []: notes[j["name"]].add(n)
for k, v in sorted(res.items(), key=lambda kv: -np.mean(kv[1])):
    print(f"{np.mean(v):6.2f}  {k}" + (f"   notes: {'; '.join(notes[k])}" if notes[k] else ""))
