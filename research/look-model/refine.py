"""Tune a recipe through the camera proxy so the owner's scenes, rendered with it, look like the examples (predict.py).

For each candidate film (the encoder's top ones): white balance mode and dynamic range from the encoder, every
continuous setting (Kelvin, WB shift, highlight, shadow, Color, toning, clarity) and the Color Chrome levels relaxed
to real numbers, and gradient descent on the distance between the encoder's look embedding of the examples and of
the proxy's renders of the owner's scenes, with a pull towards the encoder's own guess. Then rounded to the camera's
steps; the candidate whose rounded recipe sits closest wins.
"""
import json, os
import numpy as np
import torch, torch.nn.functional as F
import common
from common import FILMS, WBS, DRS, EFF
import proxy as proxy_mod

_proxy = None


def load_proxy(path, dev):
    global _proxy
    if _proxy is None:
        _proxy = proxy_mod.Proxy().to(dev); _proxy.load_state_dict(torch.load(path, map_location=dev)); _proxy.eval()
        for p in _proxy.parameters(): p.requires_grad_(False)
    return _proxy


def assemble(film, wb, dr, cont, cc, fxb, dev):
    """Differentiable recipe vector (layout of common.recipe_vec)."""
    mono = FILMS[film] in common.MONO
    tone = mono and FILMS[film] != "Sepia"
    f = F.one_hot(torch.tensor(film), len(FILMS)).float().to(dev)
    w = F.one_hot(torch.tensor(wb), len(WBS)).float().to(dev)
    d = F.one_hot(torch.tensor(dr), len(DRS)).float().to(dev)
    k, r, b, h, s, col, wc, mg, cl = cont
    kel = k if WBS[wb] == "Kelvin" else k * 0
    zero = torch.zeros((), device=dev)
    parts = [f, w, kel[None], r[None], b[None], d, h[None], s[None], (zero if mono else col)[None],
             (wc if tone else zero)[None], (mg if tone else zero)[None], torch.softmax(cc, 0),
             (F.one_hot(torch.tensor(0), 3).float().to(dev) if mono else torch.softmax(fxb, 0)), cl[None]]
    return torch.cat(parts)


def to_recipe(film, wb, dr, cont, cc, fxb):
    c = [float(x) for x in cont]
    s = common.neutral()
    s["film"], s["wb"], s["dynamic_range"] = FILMS[film], WBS[wb], DRS[dr]
    clip = lambda v, lo, hi: max(lo, min(hi, v))
    s["wb_kelvin"] = int(round(clip(5500 + 2000 * c[0], 2500, 10000) / 100) * 100) if WBS[wb] == "Kelvin" else None
    s["wb_red"], s["wb_blue"] = int(round(clip(9 * c[1], -9, 9))), int(round(clip(9 * c[2], -9, 9)))
    s["highlight"], s["shadow"] = round(clip(2 * c[3], -2, 4) * 2) / 2, round(clip(2 * c[4], -2, 4) * 2) / 2
    s["color"] = int(round(clip(4 * c[5], -4, 4)))
    s["mono_warm_cool"], s["mono_magenta_green"] = int(round(clip(9 * c[6], -9, 9))), int(round(clip(9 * c[7], -9, 9)))
    s["clarity"] = int(round(clip(5 * c[8], -5, 5)))
    s["color_chrome"], s["color_chrome_fx_blue"] = EFF[int(cc.argmax())], EFF[int(fxb.argmax())]
    return common.finish(s)


def fit(encoder, refs, raws, rafs, logits, reg, proxy_path, dev, steps=60, films=3):
    proxy = load_proxy(proxy_path, dev)
    R = torch.tensor(np.stack(raws)).to(dev)
    S = torch.tensor(np.stack([common.scene_vec(r, common.raf_meta(f)) for r, f in zip(raws, rafs)])).to(dev)
    with torch.no_grad():
        target = encoder.embed(refs)
    for p in encoder.parameters(): p.requires_grad_(False)
    wb, dr = int(logits["wb"].argmax()), int(logits["dr"].argmax())
    cands = []
    for film in logits["film"].topk(films).indices.tolist():
        cont = reg.detach().clone().to(dev).requires_grad_(True)
        prior = reg.detach().clone().to(dev)
        cc = logits["cc"].detach().clone().to(dev).requires_grad_(True)
        fxb = logits["fxb"].detach().clone().to(dev).requires_grad_(True)
        opt = torch.optim.Adam([cont, cc, fxb], lr=0.03)
        for _ in range(steps):
            vec = assemble(film, wb, dr, cont, cc, fxb, dev)
            imgs = proxy(R, vec[None].expand(len(raws), -1), S)
            e = encoder.embed(imgs[None])
            loss = (e - target).pow(2).mean() + 0.02 * (cont - prior).pow(2).mean()
            opt.zero_grad(); loss.backward(); opt.step()
        s = to_recipe(film, wb, dr, cont.detach().cpu(), cc.detach().cpu(), fxb.detach().cpu())
        with torch.no_grad():
            imgs = proxy(R, torch.tensor(common.recipe_vec(s), device=dev)[None].expand(len(raws), -1), S)
            d = (encoder.embed(imgs[None]) - target).pow(2).mean().item()
        cands.append((d, s))
    cands.sort(key=lambda x: x[0])
    return cands[0][1]
