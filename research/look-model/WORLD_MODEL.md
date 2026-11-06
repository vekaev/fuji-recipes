# What we know (update after every milestone)

## The camera (X-E5, RAW CONV. over USB)

- Renders a 640 × 480 preview: the 3:2 photo letterboxed (black rows 0–26 and 453–479). ~1.2 s per render with the
  RAW already uploaded; 3,500–7,300 renders/hour depending on how many RAWs a batch uploads.
- A recipe above the shot's own DR renders at the shot's DR. D-Range Priority isn't rendered. So DR200/400 only on
  DR400 shots (half the card).
- Sweep (mean ΔE00 vs Provia neutral, 3 scenes, 4× shrunk): Sepia ignores toning and FX Blue (all 17.4); FX Blue does
  nothing on B&W films; WB shift ±9 is 9–17; Kelvin / Incandescent ~10; B&W films ~7; shadow +4 6.4, −2 4.2;
  Velvia 3.8, Classic Neg. 3.6, Classic Chrome 2.8, Astia 2.0, Reala Ace 1.5; Color ±4 1.6–1.7 (local: saturated
  areas); clarity ±5 1.4–1.6; highlight +4 1.3, −2 0.8; DR200/400 0.8–0.9; Color Chrome Strong 0.5; FX Blue Strong
  1.7; AWP / AAP 0.25. Texture: grain 0.75, NR ±4 0.55, sharpness ±4 0.43 (the score copies them from the truth).
- The Mac's decode (CIRAWFilter, linear, no boost) lines up with the camera's preview pixel for pixel (gradient
  correlation 0.93–0.96 at zero offset).

## The task

- Cross-scene: the examples are other scenes; hand-made statistics confuse scene with recipe (ADR 0006).
- Some settings barely show (DR vs highlight, Color Chrome, Acros filters at 640 px): the score judges the look.

## Results

Split v3, val (80 fixed cases; `results.tsv` has every run): neutral 7.29 / 0 matches, library's most common 6.87 / 1.

### Limits of this benchmark

- Val's owner scenes: 10 of 12 from one session, 9 of them daylight; 30 of 45 refs from that session. A val gain may be
  a gain for that session only. Test (other sessions) is the check; the owner's new photos would widen both.
- Training: session 19 holds 100 of the 106 DR400 train scenes, so DR200/400 is confounded with its scenes.
- Runs differ by chance: encoder vs encoder + proxy looks on the old split was 0.24 ± 0.28.

### A leak, found and fixed before any score on split v3

Recipes 0–1999 were drawn before split v3, from a pool that then held today's val and test recipes: 3 val and 5 test
library recipes were in training exactly, and 20 val / 20 test cases had a training recipe within 2 steps. 507 of 4,999
recipes are now banned (`train-banned.json`, within 4 steps of any val / test recipe). The first split's numbers below
may carry the same flaw.

### First split (train: 7 sessions, two of them 84% of its scenes; archived in scores-split2.jsonl)

val dE (lower is better) / match: neutral 8.20 / 0, library's most common 7.35 / 2, encoder (camera renders) 5.18 / 14,
encoder + proxy-made looks 4.94 / 12, either + refinement through the proxy 6.5 / 3–7 (refinement hurts: don't use it
until its objective is rethought; the encoder's embedding of the proxy's renders is no reliable distance).
Film right: 83% on train scenes, 36% on val: the encoder memorises scenes. So: more sessions in train (split v3: 22),
scene augmentation, whole sessions held out for its quick check. Proxy: dE 3.3 on val scenes, target ≤ 2; the error is
large-scale tone and colour, not a global offset and not fine detail.

## Ideas not tried yet

- Posterior medoid instead of refinement through the encoder's embedding: candidates from top films × modes, pick the
  one nearest the others through the proxy, probability-weighted.
- Ensembles of encoders. Frozen DINOv2 features (knowing skin, sky or foliage separates cast from scene).
- Attribution: score with the truth swapped in for WB, film or tone (`score.py --predictions`) to see what costs most.
- A stronger proxy (wider, Lab / ΔE loss, per-scene tone stage). A pretrained image backbone for the encoder.
- The owner's new photos: new sessions, especially DR400 ones.
