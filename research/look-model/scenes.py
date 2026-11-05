"""Pick the scenes (owner's RAFs) for the look model and split them by day. Writes scenes.json in the data folder.
Usage: python3 -I scenes.py [card folder]   (default /Volumes/Untitled/DCIM). Deterministic: same card, same split."""
import json, os, random, subprocess, sys, collections
CARD = sys.argv[1] if len(sys.argv) > 1 else "/Volumes/Untitled/DCIM"
OUT = os.path.expanduser("~/Library/Caches/FujiRecipes/look-model/scenes.json")
TARGET, MIN_GAP = 240, 120  # scenes in total; seconds between two picks of the same day (no bursts)

rows = subprocess.run(["exiftool", "-fast2", "-q", "-r", "-ext", "RAF", "-j", "-n", "-DateTimeOriginal", "-BrightnessValue",
                       "-ISO", "-Model", CARD], capture_output=True, text=True).stdout
shots = [r for r in json.loads(rows) if str(r.get("DateTimeOriginal", "")).startswith("20") and r.get("Model") == "X-E5"]
def secs(t):  # "2026:10:23 15:04:05"
    d, h = t.split(" "); y, m, dd = map(int, d.split(":")); H, M, S = map(int, h[:8].split(":"))
    return (((y * 400 + m * 32 + dd) * 24 + H) * 60 + M) * 60 + S
def light(bv):
    return "night" if bv < 0 else "dim" if bv < 4 else "shade" if bv < 7 else "day"
byday = collections.defaultdict(list)
for r in shots:
    byday[r["DateTimeOriginal"][:10]].append(r)
rng = random.Random(7)
picks = []
quota = {d: max(2, round(TARGET * len(v) / len(shots))) for d, v in byday.items()}
for d, v in sorted(byday.items()):
    v = sorted(v, key=lambda r: r["DateTimeOriginal"]); rng.shuffle(v)
    chosen = []
    for r in v:
        if len(chosen) >= quota[d]: break
        if all(abs(secs(r["DateTimeOriginal"]) - secs(c["DateTimeOriginal"])) >= MIN_GAP for c in chosen): chosen.append(r)
    picks += chosen
# Split by day: shuffle days, fill test and val to ~15% each, rest train.
days = sorted(byday); rng.shuffle(days)
n = collections.Counter(p["DateTimeOriginal"][:10] for p in picks)
split, filled = {}, {"test": 0, "val": 0}
for d in days:
    s = next((k for k in ("test", "val") if filled[k] + n[d] <= 0.17 * len(picks)), "train")
    if s != "train": filled[s] += n[d]
    split[d] = s
scenes = [{"raf": p["SourceFile"], "day": p["DateTimeOriginal"][:10], "time": p["DateTimeOriginal"],
           "light": light(float(p.get("BrightnessValue", 5) or 5)), "iso": p.get("ISO"), "split": split[p["DateTimeOriginal"][:10]]}
          for p in sorted(picks, key=lambda p: p["DateTimeOriginal"])]
json.dump(scenes, open(OUT, "w"), indent=1)
c = collections.Counter((s["split"], s["light"]) for s in scenes)
print(len(shots), "X-E5 RAFs,", len(scenes), "scenes ->", OUT)
for sp in ("train", "val", "test"):
    print(f"  {sp:5}", sum(v for (a, _), v in c.items() if a == sp), {l: c[(sp, l)] for l in ("day", "shade", "dim", "night")},
          "days", sum(1 for d in split.values() if d == sp))
