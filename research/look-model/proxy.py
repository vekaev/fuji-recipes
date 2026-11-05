# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow", "tifffile", "torch", "scikit-image"]
# ///
"""Camera proxy: (the Mac's decode of a RAW, a recipe) -> what the X-E5 renders, at 160 x 106.

uv run research/look-model/proxy.py train [--minutes 20] [--out proxy.pt]
uv run research/look-model/proxy.py check [--model proxy.pt]     (ΔE00 against the camera on val owner scenes)

A per-pixel network whose layers are modulated by the recipe and the scene (exposure, as-shot white balance), with a
little local context (blurred luminance at two radii) for clarity and dynamic range. Trained on the camera's renders
of train scenes (train chunks + the sweep). Checked on val cases' renders of owner scenes it never saw.
"""
import json, os, sys, time, glob
import numpy as np
import torch, torch.nn as nn, torch.nn.functional as F
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
from common import DATA

dev = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
SCENE_DIM = 9


def arg(n, d=None):
    return sys.argv[sys.argv.index(n) + 1] if n in sys.argv else d


def pixel_feats(raw):
    """raw: (B, H, W, 3) linear -> (B, H, W, 9) per-pixel inputs."""
    x = raw.permute(0, 3, 1, 2)
    luma = (0.2126 * x[:, 0] + 0.7152 * x[:, 1] + 0.0722 * x[:, 2]).unsqueeze(1)
    ll = torch.log2(luma.clamp_min(1e-4)) / 8
    b1 = F.avg_pool2d(ll, 5, 1, 2, count_include_pad=False)
    b2 = F.avg_pool2d(ll, 21, 1, 10, count_include_pad=False)
    feats = torch.cat([torch.log2(x.clamp_min(1e-4)) / 8, x.clamp_min(0) ** (1 / 2.2), ll, ll - b1, ll - b2], 1)
    return feats.permute(0, 2, 3, 1)


class Proxy(nn.Module):
    def __init__(self, width=160, depth=5):
        super().__init__()
        self.cond = nn.Sequential(nn.Linear(common.RECIPE_DIM + SCENE_DIM, 256), nn.SiLU(), nn.Linear(256, 256), nn.SiLU())
        self.inp = nn.Linear(9, width)
        self.layers = nn.ModuleList([nn.Linear(width, width) for _ in range(depth)])
        self.film = nn.ModuleList([nn.Linear(256, 2 * width) for _ in range(depth + 1)])
        self.out = nn.Linear(width, 3)

    def forward(self, raw, recipe, scene):
        """raw (B,H,W,3) linear, recipe (B,R), scene (B,S) -> (B,H,W,3) sRGB 0..1."""
        c = self.cond(torch.cat([recipe, scene], -1))
        h = self.inp(pixel_feats(raw))
        for i, layer in enumerate([None] + list(self.layers)):
            if layer is not None: h = layer(h)
            g, b = self.film[i](c).chunk(2, -1)
            h = F.silu(h * (1 + g[:, None, None]) + b[:, None, None])
        return torch.sigmoid(self.out(h))


def dataset(manifests, jobs_files):
    meta = common.scene_meta()
    items = []
    for jf, mf in zip(jobs_files, manifests):
        if not os.path.exists(mf): continue
        jobs = [json.loads(l) for l in open(jf)]
        for l in open(mf):
            m = json.loads(l)
            if not m.get("jpeg"): continue
            j = jobs[m["line"]]
            stem = os.path.splitext(os.path.basename(j["raf"]))[0]
            if not os.path.exists(f"{DATA}/raw/{stem}.tiff"): continue
            items.append((j["raf"], j["settings"], m["jpeg"]))
    raws, scenes, recs, outs, keys = {}, {}, [], [], []
    for raf, s, jpg in items:
        if raf not in raws:
            raws[raf] = common.load_raw(raf); scenes[raf] = common.scene_vec(raws[raf], meta.get(raf))
        recs.append(common.recipe_vec(s)); outs.append(common.load_render(jpg)); keys.append(raf)
    order = sorted(raws)
    idx = {k: i for i, k in enumerate(order)}
    R = torch.tensor(np.stack([raws[k] for k in order]))
    S = torch.tensor(np.stack([scenes[k] for k in order]))
    return R, S, torch.tensor(np.array([idx[k] for k in keys])), torch.tensor(np.stack(recs)), torch.tensor(np.stack(outs))


def train_files():
    jf, mf = [f"{DATA}/sweep-jobs.jsonl"], [f"{DATA}/sweep-manifest.jsonl"]
    for c in sorted(glob.glob(f"{DATA}/chunks/train-??")):
        jf.append(c); mf.append(c + ".manifest")
    return mf, jf


def val_files():
    """Val cases' renders on owner scenes (decoded); reference scenes aren't decoded, so they drop out."""
    cases = json.load(open(f"{DATA}/cases-val.json"))
    jobs = [{"raf": raf, "settings": c["recipe"]} for c in cases for raf in c["refs"] + c["evals"]]
    tmp = f"{DATA}/.val-jobs.jsonl"
    with open(tmp, "w") as f:
        for j in jobs: f.write(json.dumps(j) + "\n")
    return [f"{DATA}/eval-manifest.jsonl"], [tmp]


def evaluate(model, data):
    from skimage.color import rgb2lab, deltaE_ciede2000
    R, S, I, X, Y = data
    model.eval(); ds = []
    with torch.no_grad():
        for k in range(0, len(I), 64):
            sl = slice(k, k + 64)
            p = model(R[I[sl]].to(dev), X[sl].to(dev), S[I[sl]].to(dev)).cpu().numpy()
            for a, b in zip(p, Y[sl].numpy()):
                ds.append(float(deltaE_ciede2000(rgb2lab(a), rgb2lab(b)).mean()))
    model.train()
    return float(np.mean(ds)), float(np.percentile(ds, 90))


def main():
    out = f"{DATA}/models/{arg('--out', 'proxy.pt')}"
    if sys.argv[1] == "check":
        model = Proxy().to(dev); model.load_state_dict(torch.load(f"{DATA}/models/{arg('--model', 'proxy.pt')}", map_location=dev))
        print("val dE %.2f p90 %.2f" % evaluate(model, dataset(*val_files())))
        return
    t0 = time.time()
    tr = dataset(*train_files()); va = dataset(*val_files())
    print(f"train {len(tr[2])} renders of {len(tr[0])} scenes, val {len(va[2])} renders of {len(va[0])} scenes "
          f"(loaded in {time.time() - t0:.0f} s)", flush=True)
    R, S, I, X, Y = tr
    R, S, X, Y = R.to(dev), S.to(dev), X.to(dev), Y.to(dev)
    model = Proxy().to(dev)
    opt = torch.optim.AdamW(model.parameters(), 2e-3, weight_decay=1e-4)
    minutes = float(arg("--minutes", 20)); end = time.time() + 60 * minutes
    step, best = 0, 1e9
    sched_total = None
    while time.time() < end:
        b = torch.randint(0, len(I), (24,))
        pred = model(R[I[b].to(dev)], X[b], S[I[b].to(dev)])
        loss = F.l1_loss(pred, Y[b])
        frac = 1 - (end - time.time()) / (60 * minutes)
        for g in opt.param_groups: g["lr"] = 2e-3 * 0.5 * (1 + np.cos(np.pi * min(1, frac)))
        opt.zero_grad(); loss.backward(); opt.step(); step += 1
        if step % 1000 == 0:
            d, p = evaluate(model, va)
            print(f"step {step} loss {loss.item():.4f} val dE {d:.2f} p90 {p:.2f} ({(time.time() - t0) / 60:.0f} min)", flush=True)
            if d < best:
                best = d; os.makedirs(os.path.dirname(out), exist_ok=True); torch.save(model.state_dict(), out)
    d, p = evaluate(model, va)
    if d < best: torch.save(model.state_dict(), out); best = d
    print(f"done: {step} steps, best val dE {best:.2f} -> {out}")


if __name__ == "__main__":
    main()
