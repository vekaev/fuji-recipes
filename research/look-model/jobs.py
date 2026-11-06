"""More training renders, balanced by scene (orchestrator only: reads the frozen cases of val and test to stay away
from them, and prints nothing about them).

python3 -I jobs.py ban        -> train-banned.json: existing training recipes within 4 steps of any val / test recipe
python3 -I jobs.py more N     -> N more recipes, each on 4 scenes, the least-rendered ones first; appended to
                                 train-jobs.jsonl and cut into chunks/train-c??, sorted by RAW

recipes.py balanced sessions, so scenes alone in a session got thousands of renders (one has 2,189, the median 17).
Half of the new recipes change a real recipe from the clean pool, half are random; half of the random ones draw the
white balance mode evenly, because fixed modes are rare in recipes.py's mix and common in real recipes.
"""
import json, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import recipes as R
from recipes import DATA, HOLD

JOBS = f"{DATA}/train-jobs.jsonl"
NEAR = 4


def held():
    return [c["recipe"] for f in (f"{DATA}/cases-val.json", f"{HOLD}/cases-test.json") for c in json.load(open(f))]


def main():
    H = held()
    jobs = [json.loads(l) for l in open(JOBS)]
    if sys.argv[1] == "ban":
        seen = {}
        for j in jobs: seen.setdefault(j["recipe_id"], j["settings"])
        ban = sorted(i for i, s in seen.items() if any(R.distance(s, h) <= NEAR for h in H))
        json.dump(ban, open(f"{DATA}/train-banned.json", "w"))
        print(f"{len(ban)} of {len(seen)} recipes banned")
        return
    n = int(sys.argv[2])
    scenes = [s for s in json.load(open(f"{DATA}/scenes.json")) if s["role"] == "train"]
    count = {s["raf"]: 0 for s in scenes}
    for j in jobs:
        if j["raf"] in count: count[j["raf"]] += 1
    pool = [s for a, s in R.library() if a in set(json.load(open(f"{DATA}/library-split.json"))["train_pool"])]
    rng = random.Random(777 + len(jobs))
    start = 1 + max(j["recipe_id"] for j in jobs)
    new, k = [], start
    while k < start + n:
        if pool and rng.random() < 0.5:
            s = R.perturb(rng, rng.choice(pool))
        else:
            s = R.random_recipe(rng)
            if rng.random() < 0.5:
                s["wb"] = rng.choice([w for w, _ in R.WB])
                s["wb_kelvin"] = rng.randrange(2800, 9001, 100) if s["wb"] == "Kelvin" else None
                s = R.finish(s)
        if rng.random() < 0.7: s["dynamic_range"] = "DR100"       # most scenes can't show DR200 / 400; it barely shows anyway
        if any(R.distance(s, h) <= NEAR for h in H): continue
        cand = scenes if s["dynamic_range"] == "DR100" else [x for x in scenes if x["dr"] >= 400]
        cand = sorted(cand, key=lambda x: count[x["raf"]] + rng.random() * 8)
        sel, sess = [], set()
        for x in cand:
            if x["session"] not in sess or len(sess) >= 4:
                sel.append(x); sess.add(x["session"])
            if len(sel) == 4: break
        for x in sel:
            count[x["raf"]] += 1
            new.append({"raf": x["raf"], "settings": s, "recipe_id": k})
        k += 1
    with open(JOBS, "a") as f:
        for j in new: f.write(json.dumps(j) + "\n")
    new.sort(key=lambda j: j["raf"])
    os.makedirs(f"{DATA}/chunks", exist_ok=True)
    letters = "abcdefghijklmnopqrstuvwxyz"
    size, names = 200, []
    for i in range(0, len(new), size):
        c = i // size
        name = f"{DATA}/chunks/train-{'cdefghij'[c // 26]}{letters[c % 26]}"
        names.append(name)
        with open(name, "w") as f:
            for j in new[i:i + size]: f.write(json.dumps(j) + "\n")
    vals = sorted(count.values())
    print(f"recipes {start}..{k - 1}: {len(new)} jobs in {len(names)} chunks; scene renders now min {vals[0]} median {vals[len(vals) // 2]} max {vals[-1]}")


if __name__ == "__main__":
    main()
