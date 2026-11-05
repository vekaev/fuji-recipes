# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow", "tifffile", "torch", "scikit-image"]
# ///
"""Encoder: 2–3 example photos (other scenes) -> a recipe. Trained on renders of the same recipe on different scenes,
so it learns the look and not the scene.

uv run research/look-model/encoder.py train [--minutes 20] [--proxy proxy.pt] [--out encoder.pt]
  --proxy: also train on looks the camera proxy renders on train scenes (unlimited recipes; Deep Preset style).

The case predictor (predict.py) loads it.
"""
import json, os, sys, time, glob, random
import numpy as np
import torch, torch.nn as nn, torch.nn.functional as F
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
from common import DATA, FILMS, WBS, DRS, EFF

dev = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
HEADS = {"film": len(FILMS), "wb": len(WBS), "dr": len(DRS), "cc": len(EFF), "fxb": len(EFF)}
REG = ["kelvin", "wb_red", "wb_blue", "highlight", "shadow", "color", "wc", "mg", "clarity"]


def arg(n, d=None):
    return sys.argv[sys.argv.index(n) + 1] if n in sys.argv else d


def targets(s):
    mono = s["film"] in common.MONO
    cls = {"film": FILMS.index(s["film"]), "wb": WBS.index(s["wb"]) if s["wb"] in WBS else 0,
           "dr": DRS.index(s["dynamic_range"]) if s["dynamic_range"] in DRS else 2,
           "cc": EFF.index(s["color_chrome"]), "fxb": 0 if mono else EFF.index(s["color_chrome_fx_blue"])}
    tone = mono and s["film"] != "Sepia"
    reg = [((s.get("wb_kelvin") or 5500) - 5500) / 2000 if s["wb"] == "Kelvin" else 0.0, s["wb_red"] / 9, s["wb_blue"] / 9,
           s["highlight"] / 2, s["shadow"] / 2, 0.0 if mono else (s.get("color") or 0) / 4,
           (s.get("mono_warm_cool") or 0) / 9 if tone else 0.0, (s.get("mono_magenta_green") or 0) / 9 if tone else 0.0,
           s.get("clarity", 0) / 5]
    # which regression targets count (kelvin only for Kelvin, colour only for colour films, toning only for toned B&W)
    mask = [1.0 if s["wb"] == "Kelvin" else 0.0, 1, 1, 1, 1, 0.0 if mono else 1.0, 1.0 if tone else 0.0, 1.0 if tone else 0.0, 1]
    return cls, np.array(reg, np.float32), np.array(mask, np.float32)


def decode(cls_logits, reg):
    """Network output for one case -> a recipe the camera takes."""
    s = common.neutral()
    s["film"] = FILMS[int(cls_logits["film"].argmax())]
    s["wb"] = WBS[int(cls_logits["wb"].argmax())]
    s["dynamic_range"] = DRS[int(cls_logits["dr"].argmax())]
    s["color_chrome"] = EFF[int(cls_logits["cc"].argmax())]
    s["color_chrome_fx_blue"] = EFF[int(cls_logits["fxb"].argmax())]
    r = reg
    clip = lambda v, lo, hi: max(lo, min(hi, v))
    s["wb_kelvin"] = int(round(clip(5500 + 2000 * r[0], 2500, 10000) / 100) * 100) if s["wb"] == "Kelvin" else None
    s["wb_red"], s["wb_blue"] = int(round(clip(9 * r[1], -9, 9))), int(round(clip(9 * r[2], -9, 9)))
    s["highlight"] = round(clip(2 * r[3], -2, 4) * 2) / 2
    s["shadow"] = round(clip(2 * r[4], -2, 4) * 2) / 2
    s["color"] = int(round(clip(4 * r[5], -4, 4)))
    s["mono_warm_cool"], s["mono_magenta_green"] = int(round(clip(9 * r[6], -9, 9))), int(round(clip(9 * r[7], -9, 9)))
    s["clarity"] = int(round(clip(5 * r[8], -5, 5)))
    return common.finish(s)


class Encoder(nn.Module):
    """A small CNN per photo (colour + tone, global pooling), averaged over the 2–3 photos, then heads."""
    def __init__(self, width=96):
        super().__init__()
        def blk(i, o): return nn.Sequential(nn.Conv2d(i, o, 3, 2, 1), nn.GroupNorm(8, o), nn.SiLU(), nn.Conv2d(o, o, 3, 1, 1), nn.GroupNorm(8, o), nn.SiLU())
        self.cnn = nn.Sequential(blk(6, width // 2), blk(width // 2, width), blk(width, width), blk(width, width))
        self.hist = nn.Sequential(nn.Linear(3 * 3 * 16, 256), nn.SiLU())
        self.mix = nn.Sequential(nn.Linear(2 * width + 256, 384), nn.SiLU(), nn.Linear(384, 384), nn.SiLU())
        self.heads = nn.ModuleDict({k: nn.Linear(384, n) for k, n in HEADS.items()})
        self.reg = nn.Linear(384, len(REG))

    def embed(self, imgs):
        """imgs (B, N, H, W, 3) sRGB 0..1 -> (B, 384): the look, pooled over the N photos."""
        B, N = imgs.shape[:2]
        x = imgs.reshape(B * N, *imgs.shape[2:]).permute(0, 3, 1, 2)
        lab = rgb_to_lab(x)
        f = self.cnn(torch.cat([x, lab / torch.tensor([100, 128, 128], device=x.device)[None, :, None, None]], 1))
        f = torch.cat([f.mean((2, 3)), f.amax((2, 3))], 1)
        h = self.hist(histograms(lab))
        e = self.mix(torch.cat([f, h], 1)).reshape(B, N, -1).mean(1)
        return e

    def forward(self, imgs):
        e = self.embed(imgs)
        return {k: h(e) for k, h in self.heads.items()}, self.reg(e)


def rgb_to_lab(x):
    """sRGB (B,3,H,W) 0..1 -> CIELAB, differentiable."""
    lin = torch.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)
    M = torch.tensor([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]], device=x.device)
    xyz = torch.einsum("ij,bjhw->bihw", M, lin) / torch.tensor([0.9505, 1.0, 1.089], device=x.device)[None, :, None, None]
    f = torch.where(xyz > 0.008856, xyz.clamp_min(1e-6) ** (1 / 3), 7.787 * xyz + 16 / 116)
    return torch.stack([116 * f[:, 1] - 16, 500 * (f[:, 0] - f[:, 1]), 200 * (f[:, 1] - f[:, 2])], 1)


def histograms(lab):
    """Soft 16-bin histograms of L, a, b in three luminance bands (shadows / mids / highlights): (B, 144)."""
    L, a, b = lab[:, 0], lab[:, 1], lab[:, 2]
    bands = [torch.sigmoid((40 - L) / 5), torch.sigmoid((L - 30) / 5) * torch.sigmoid((70 - L) / 5), torch.sigmoid((L - 60) / 5)]
    out = []
    for w in bands:
        for v, lo, hi in ((L, 0, 100), (a, -40, 40), (b, -40, 40)):
            c = torch.linspace(lo, hi, 16, device=lab.device)
            k = torch.exp(-((v.unsqueeze(1) - c[None, :, None, None]) / ((hi - lo) / 16)) ** 2) * w.unsqueeze(1)
            out.append(k.sum((2, 3)) / (w.sum((1, 2))[:, None] + 1e-3))
    return torch.cat(out, 1)


def real_groups():
    """Training renders grouped by recipe: [(settings, [preview arrays])] with >= 3 scenes each."""
    groups = {}
    for c in sorted(glob.glob(f"{DATA}/chunks/train-??")):
        mf = c + ".manifest"
        if not os.path.exists(mf): continue
        jobs = [json.loads(l) for l in open(c)]
        for l in open(mf):
            m = json.loads(l)
            if not m.get("jpeg"): continue
            j = jobs[m["line"]]
            g = groups.setdefault(j["recipe_id"], (j["settings"], []))
            g[1].append(common.load_render(m["jpeg"]))
    return [g for g in groups.values() if len(g[1]) >= 3]


def loss_fn(out, cls_t, reg_t, mask):
    logits, reg = out
    l = sum(F.cross_entropy(logits[k], cls_t[k]) for k in HEADS)
    l = l + 3 * ((reg - reg_t).abs() * mask).sum() / mask.sum().clamp_min(1)
    return l


def batch_real(groups, n, k=3):
    imgs, cls, reg, mask = [], {h: [] for h in HEADS}, [], []
    for _ in range(n):
        s, pics = random.choice(groups)
        sel = random.sample(pics, k)
        imgs.append(np.stack(sel))
        c, r, m = targets(s)
        for h in HEADS: cls[h].append(c[h])
        reg.append(r); mask.append(m)
    return (torch.tensor(np.stack(imgs)).to(dev), {h: torch.tensor(cls[h]).to(dev) for h in HEADS},
            torch.tensor(np.stack(reg)).to(dev), torch.tensor(np.stack(mask)).to(dev))


def main():
    if sys.argv[1] != "train": sys.exit(__doc__)
    groups = real_groups()
    random.seed(0); random.shuffle(groups)
    hold = groups[: max(20, len(groups) // 20)]; groups = groups[len(hold):]
    print(f"{len(groups)} recipes to train on, {len(hold)} held for a quick check", flush=True)
    proxy_gen = None
    if arg("--proxy"):
        import synth
        proxy_gen = synth.Generator(f"{DATA}/models/{arg('--proxy')}", dev)
    model = Encoder().to(dev)
    opt = torch.optim.AdamW(model.parameters(), 1e-3, weight_decay=1e-4)
    minutes = float(arg("--minutes", 20)); t0 = time.time(); end = t0 + 60 * minutes; step = 0
    out = f"{DATA}/models/{arg('--out', 'encoder.pt')}"
    while time.time() < end:
        frac = (time.time() - t0) / (60 * minutes)
        for g in opt.param_groups: g["lr"] = 1e-3 * 0.5 * (1 + np.cos(np.pi * min(1, frac)))
        k = random.choice([2, 3])
        if proxy_gen and step % 2 == 1:
            imgs, cls, reg, mask = proxy_gen.batch(24, k)
        else:
            imgs, cls, reg, mask = batch_real(groups, 24, k)
        loss = loss_fn(model(imgs), cls, reg, mask)
        opt.zero_grad(); loss.backward(); opt.step(); step += 1
        if step % 500 == 0:
            model.eval()
            with torch.no_grad():
                imgs, cls, reg, mask = batch_real(hold, 64, 3)
                logits, r = model(imgs)
                film = (logits["film"].argmax(1) == cls["film"]).float().mean().item()
                err = ((r - reg).abs() * mask).sum(0) / mask.sum(0).clamp_min(1)
            model.train()
            print(f"step {step} loss {loss.item():.3f} | held film {film:.2f} wbR {9 * err[1]:.1f} wbB {9 * err[2]:.1f} "
                  f"H {2 * err[3]:.2f} S {2 * err[4]:.2f} col {4 * err[5]:.2f} ({(time.time() - t0) / 60:.0f} min)", flush=True)
            os.makedirs(os.path.dirname(out), exist_ok=True); torch.save(model.state_dict(), out)
    torch.save(model.state_dict(), out)
    print("saved", out)


if __name__ == "__main__":
    main()
