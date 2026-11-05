"""Pick the scenes (the owner's X-E5 RAFs) for the look model and split them by shooting session.
Writes <data>/scenes.json. Usage: python3 -I scenes.py [card folder]   (default /Volumes/Untitled/DCIM).
Deterministic for the same card.

- Sessions: shots sorted by time; a gap over 6 h starts a new one, unless the file numbers run on (≤ 10 apart) within
  36 h (the same outing across midnight). Shots with an unset clock (2025:01:01) are left out.
- Split by session: test and val get ~90 scenes each, with the same mix of light (day / shade / dim / night) and of
  as-shot dynamic range; the rest is train. Whole sessions only, so no near-identical frames cross splits.
- Roles inside val and test: "owner" scenes (DR400 shots, so the camera can render DR100/200/400 on them and their
  EXIF tells nothing) are the RAWs a method gets and the eval scenes; "ref" scenes only ever appear as example photos
  (rendered JPEGs, EXIF stripped); their RAWs are never given to a method or decoded.
"""
import json, os, random, subprocess, sys, collections, datetime

CARD = sys.argv[1] if len(sys.argv) > 1 else "/Volumes/Untitled/DCIM"
DATA = os.path.expanduser("~/Library/Caches/FujiRecipes/look-model")
PER_SESSION_GAP = 30      # seconds between two picks from one session (no bursts)
TARGET = {"train": 300, "val": 90, "test": 90}

# The as-shot dynamic range is in the JPEG twin's maker notes (the RAF doesn't carry it), so read the JPEGs.
rows = json.loads(subprocess.run(["exiftool", "-fast", "-q", "-r", "-ext", "JPG", "-j", "-n", "-DateTimeOriginal", "-BrightnessValue",
                                  "-ISO", "-Model", "-DevelopmentDynamicRange", CARD], capture_output=True, text=True).stdout)
for r in rows:
    r["SourceFile"] = r["SourceFile"][:-4] + ".RAF"
rows = [r for r in rows if os.path.exists(r["SourceFile"])]
shots = [r for r in rows if r.get("Model") == "X-E5" and str(r.get("DateTimeOriginal", "")).startswith("20")
         and not str(r["DateTimeOriginal"]).startswith("2025:01:01")]


def secs(t):
    return datetime.datetime.strptime(t[:19], "%Y:%m:%d %H:%M:%S").timestamp()


def num(r):
    return int(os.path.basename(r["SourceFile"])[4:8])


def light(r):
    bv = float(r.get("BrightnessValue", 5) or 5)
    return "night" if bv < 0 else "dim" if bv < 4 else "shade" if bv < 7 else "day"


def dr(r):
    return int(r.get("DevelopmentDynamicRange", 100) or 100)


shots.sort(key=lambda r: r["DateTimeOriginal"])
sessions, cur = [], []
for r in shots:
    if cur:
        gap = secs(r["DateTimeOriginal"]) - secs(cur[-1]["DateTimeOriginal"])
        runs_on = 0 <= num(r) - num(cur[-1]) <= 3 and gap < 20 * 3600
        if gap > 6 * 3600 and not runs_on:
            sessions.append(cur); cur = []
    cur.append(r)
sessions.append(cur)

rng = random.Random(11)
total = sum(len(s) for s in sessions)
thinned = []
for s in sessions:
    want = max(2, round(sum(TARGET.values()) * len(s) / total))
    pool = s[:]; rng.shuffle(pool); keep = []
    for r in pool:
        if len(keep) >= want: break
        if all(abs(secs(r["DateTimeOriginal"]) - secs(k["DateTimeOriginal"])) >= PER_SESSION_GAP for k in keep): keep.append(r)
    thinned.append(sorted(keep, key=lambda r: r["DateTimeOriginal"]))


def mix(ss):
    c = collections.Counter(); n = 0
    for s in ss:
        for r in s:
            c[light(r)] += 1; c["dr400"] += dr(r) >= 400; n += 1
    return {k: v / max(1, n) for k, v in c.items()}


overall = mix(thinned)
best = None
for t in range(4000):
    idx = list(range(len(thinned))); rng.shuffle(idx)
    split, sizes = {}, {"val": 0, "test": 0}
    for i in idx:
        k = next((k for k in ("test", "val") if sizes[k] + len(thinned[i]) <= TARGET[k] * 1.1), "train")
        split[i] = k
        if k != "train": sizes[k] += len(thinned[i])
    cost = sum(abs(sizes[k] - TARGET[k]) / TARGET[k] for k in sizes)
    for k in ("val", "test"):
        m = mix([thinned[i] for i in split if split[i] == k])
        cost += 2 * sum(abs(m.get(x, 0) - overall.get(x, 0)) for x in ("day", "shade", "dim", "night", "dr400"))
        cost -= 0.08 * min(8, sum(1 for i in split if split[i] == k))   # more sessions = more independent scenes
    if best is None or cost < best[0]: best = (cost, split)
split = best[1]

scenes = []
for i, s in enumerate(thinned):
    for r in s:
        scenes.append({"raf": r["SourceFile"], "session": i, "time": r["DateTimeOriginal"], "iso": r.get("ISO"),
                       "light": light(r), "dr": dr(r), "split": split[i]})
for k in ("val", "test"):
    d4 = [s for s in scenes if s["split"] == k and s["dr"] >= 400]
    rng.shuffle(d4)
    owners = {s["raf"] for s in d4[: len(d4) // 2]}
    for s in scenes:
        if s["split"] == k: s["role"] = "owner" if s["raf"] in owners else "ref"
for s in scenes:
    s.setdefault("role", "train")
os.makedirs(DATA, exist_ok=True)
json.dump(scenes, open(f"{DATA}/scenes.json", "w"), indent=1)
print(f"{len(shots)} X-E5 RAFs, {len(sessions)} sessions, {len(scenes)} scenes -> {DATA}/scenes.json")
for k in ("train", "val", "test"):
    ss = [s for s in scenes if s["split"] == k]
    c = collections.Counter(s["light"] for s in ss)
    print(f"  {k:5} {len(ss):3} sessions {len({s['session'] for s in ss}):2} dr400 {sum(s['dr'] >= 400 for s in ss):3} "
          f"owner {sum(s['role'] == 'owner' for s in ss):2} ref {sum(s['role'] == 'ref' for s in ss):2} "
          + " ".join(f"{l} {c[l]}" for l in ("day", "shade", "dim", "night")))
