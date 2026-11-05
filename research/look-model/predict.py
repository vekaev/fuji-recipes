# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow", "tifffile", "torch", "scikit-image"]
# ///
"""The look model's answer for one case: python predict.py [--encoder encoder.pt] [--proxy proxy.pt] [--steps N] <case dir>
Prints the recipe as JSON on its last line (score.py --predict runs it per case).

1. The encoder reads the example photos (refs/*.jpg) and proposes a recipe (its top films are kept as candidates).
2. With --proxy: the owner's RAFs (inputs.json) are decoded on the Mac, and for each candidate film the settings are
   tuned by gradient descent so that the proxy's renders of the owner's scenes look like the examples to the encoder
   (same look embedding). The candidate whose renders sit closest wins.
"""
import json, os, sys, glob, subprocess, tempfile
import numpy as np
import torch
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
from common import DATA, FILMS, WBS, DRS, EFF
import encoder as enc_mod

dev = torch.device("mps" if torch.backends.mps.is_available() else "cpu")


def arg(n, d=None):
    return sys.argv[sys.argv.index(n) + 1] if n in sys.argv else d


def load_refs(d):
    return np.stack([common.load_render(p) for p in sorted(glob.glob(os.path.join(d, "refs", "*.jpg")))])


def decode_inputs(rafs):
    """The owner's RAFs at the working size, decoded on the Mac (cached by file name)."""
    out = []
    missing = [r for r in rafs if not os.path.exists(f"{DATA}/raw/{os.path.splitext(os.path.basename(r))[0]}.tiff")]
    if missing:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump([{"raf": r} for r in missing], f)
        subprocess.run([f"{DATA}/decode", f.name, f"{DATA}/raw"], capture_output=True)
    return [common.load_raw(r) for r in rafs]


def main():
    case = sys.argv[-1]
    model = enc_mod.Encoder().to(dev)
    model.load_state_dict(torch.load(f"{DATA}/models/{arg('--encoder', 'encoder.pt')}", map_location=dev)); model.eval()
    refs = torch.tensor(load_refs(case))[None].to(dev)
    with torch.no_grad():
        logits, reg = model(refs)
    logits = {k: v[0].cpu() for k, v in logits.items()}
    guess = enc_mod.decode(logits, reg[0].cpu().numpy())
    if not arg("--proxy"):
        print(json.dumps(guess)); return
    import refine
    rafs = json.load(open(os.path.join(case, "inputs.json")))["inputs"]
    raws = decode_inputs(rafs)
    best = refine.fit(model, refs, raws, rafs, logits, reg[0], f"{DATA}/models/{arg('--proxy')}", dev,
                      steps=int(arg("--steps", 60)), films=int(arg("--films", 3)))
    print(json.dumps(best))


if __name__ == "__main__":
    main()
