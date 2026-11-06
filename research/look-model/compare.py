"""Is a change real? Paired comparison of two val runs in scores.jsonl (fixed cases, so per-case differences count):
python3 -I research/look-model/compare.py "<label a>" "<label b>"   -> mean(b - a) ± its standard error, per case kind.
A gain counts when it's more than twice its standard error."""
import json, math, os, sys
D = os.path.expanduser("~/Library/Caches/FujiRecipes/look-model")
runs = [json.loads(l) for l in open(f"{D}/scores.jsonl")]
def get(label):
    r = [x for x in runs if x["label"] == label]
    if not r: sys.exit(f"no run labelled {label!r}")
    return r[-1]
a, b = get(sys.argv[1]), get(sys.argv[2])
A = {c["id"]: c for c in a["cases"]}; B = {c["id"]: c for c in b["cases"]}
def line(name, ids):
    if len(ids) < 2: return
    d = [B[i]["dE"] - A[i]["dE"] for i in ids]
    m = sum(d) / len(d); se = math.sqrt(sum((x - m) ** 2 for x in d) / (len(d) - 1) / len(d))
    print(f"{name:8s} n {len(d):3d}  a {sum(A[i]['dE'] for i in ids) / len(d):.2f}  b {sum(B[i]['dE'] for i in ids) / len(d):.2f}  b-a {m:+.2f} ± {se:.2f}  {'REAL' if abs(m) > 2 * se else 'noise'}")
line("all", list(A))
line("colour", [i for i in A if not A[i]["mono"]])
line("mono", [i for i in A if A[i]["mono"]])
line("real", [i for i in A if A[i]["source"] != "random"])
line("random", [i for i in A if A[i]["source"] == "random"])
