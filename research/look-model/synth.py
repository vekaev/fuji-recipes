"""Synthetic training looks from the camera proxy: random recipes rendered on train scenes (encoder.py --proxy)."""
import json, os, random, sys
import numpy as np
import torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
from common import DATA
import proxy as proxy_mod
import recipes as recipe_mod
from encoder import targets, HEADS


class Generator:
    def __init__(self, model_path, dev):
        self.dev = dev
        self.model = proxy_mod.Proxy().to(dev)
        self.model.load_state_dict(torch.load(model_path, map_location=dev)); self.model.eval()
        meta = common.scene_meta()
        scenes = [s for s in json.load(open(f"{DATA}/scenes.json")) if s["role"] == "train"]
        self.scenes = scenes
        self.R = torch.tensor(np.stack([common.load_raw(s["raf"]) for s in scenes])).to(dev)
        self.S = torch.tensor(np.stack([common.scene_vec(common.load_raw(s["raf"]), meta.get(s["raf"])) for s in scenes])).to(dev)
        self.dr400 = [i for i, s in enumerate(scenes) if s["dr"] >= 400]
        split = json.load(open(f"{DATA}/library-split.json"))
        self.pool = [s for a, s in recipe_mod.library() if a in set(split["train_pool"])]
        self.rng = random.Random(12345)

    def recipe(self):
        r = self.rng
        return recipe_mod.perturb(r, r.choice(self.pool)) if self.pool and r.random() < 0.5 else recipe_mod.random_recipe(r)

    @torch.no_grad()
    def batch(self, n, k):
        recs = [self.recipe() for _ in range(n)]
        idx, rv = [], []
        for s in recs:
            pool = self.dr400 if s["dynamic_range"] != "DR100" else range(len(self.scenes))
            idx.append(self.rng.sample(list(pool), k)); rv.append(common.recipe_vec(s))
        I = torch.tensor(idx, device=self.dev).reshape(-1)
        X = torch.tensor(np.stack(rv), device=self.dev).repeat_interleave(k, 0)
        imgs = self.model(self.R[I], X, self.S[I]).reshape(n, k, common.H, common.W, 3)
        cls, reg, mask = {h: [] for h in HEADS}, [], []
        for s in recs:
            c, r, m = targets(s)
            for h in HEADS: cls[h].append(c[h])
            reg.append(r); mask.append(m)
        return (imgs, {h: torch.tensor(cls[h], device=self.dev) for h in HEADS},
                torch.tensor(np.stack(reg), device=self.dev), torch.tensor(np.stack(mask), device=self.dev))
