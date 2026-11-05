# 0006 Match a look: the camera judges, the photo only suggests

Status: accepted, 2026-11-04

## Context

The owner wants to point at any photo (a paid recipe's samples, a Leica shot) and get a Fujifilm recipe for that
look. Existing tools guess from the photo alone (Fuji Frame, ToneChef, Fujicipe, recipe-detector; chatbots). Fuji X
Weekly's tests found them inaccurate: given a Provia photo they never said Provia. Capture One's Match Look gets close
for its own sliders, which don't map 1:1 onto in-camera settings. Deep Preset (WACV 2021) trains a preset predictor on
renders; its weights are non-commercial.

## What we measured (fuji match --evaluate, the owner's library, 141 photos of 45 recipes, leave-one-recipe-out)

| First guess from the photo | Film exact | Film family | B&W | WB red / blue | Highlight / shadow | Color |
|---|---|---|---|---|---|---|
| Guess the library's average | 38% | 39% | 78% | ±1.8 / ±2.2 | ±1.2 / ±1.3 | ±1.0 |
| Rules (tone, cast, saturation) | 16% | 45% | 99% | ±3.3 / ±3.2 | ±2.6 / ±2.0 | ±3.4 |
| Nearest library photos (k = 5) | 40% | 60% | 99% | ±1.8 / ±1.9 | ±1.1 / ±1.4 | ±0.8 |
| … plus Fuji X Weekly's 452 photos of 113 recipes | 30% | 61% | 99% | ±2.2 / ±2.0 | ±1.4 / ±1.3 | ±1.5 |

Recognising a library recipe from another photo of it: right one first 28%, in the top three 42% (chance 7%).
A blind test on a new post (Nostalgic Memory, Classic Neg.) guessed Classic Neg., DR400, R+4 B−5, H −1.5, Col +4 for
the real Classic Neg., DR400, R+3 B−4, H −1, Col +3.

So: from one photo, scene and light swamp the recipe. Rules read white balance worse than not guessing. A bigger,
more varied reference set made it worse, not better: hand-made statistics don't separate the photographer's scenes
from the recipe.

## Decision

- The first guess is a nearest-neighbour blend of the library's own sample photos (it improves as the library grows);
  rules only decide black-and-white, film family, grain and clarity, and leave WB, tone and Color neutral.
- The answer comes from the camera: it develops one of the owner's RAWs (similar light helps) with candidates and the
  look statistics pick the closest. Search: every film simulation, the sensitivities of the look to WB red, WB blue,
  Color, highlight and shadow (one render each), one Levenberg–Marquardt step per film before ranking films (so a bad
  first white balance doesn't drop the right film), three more on the best three, then one-setting-at-a-time polish.
  60 renders ≈ 2 minutes. `fuji match --benchmark` (20 hidden recipes, seed 7) on the simulated camera: 15 matched
  at 85%+, 12 recovered with the right film and every setting within one step; score 101.6. Tried and dropped
  (benchmark went down): polishing the top three films equally, Broyden updates of the sensitivities, more
  Levenberg–Marquardt steps per film, starting from the photo-only rules' WB / tone / Color.
- Grain and clarity can't be judged on the camera's 640-px previews; they come from the photo.
- Reference sets (`fuji match --learn`) can be imported and evaluated but aren't used for guesses.
- No recipe is taken from a paid recipe's sample metadata.

## On the real X-E5 (2026-11-04)

`fuji match --real <card folder>`: the owner's JPEG + RAF pairs; the JPEG's recipe (EXIF) is hidden, its look is the
reference, the camera develops the RAF (about 2 s a render, 1–2 minutes a photo), the search must find the recipe.
12 photos across all 11 recipes on the card, 60 renders each:

- 6 of 12 recovered (right film, every setting within one step), two exactly (Classic Chrome R+4 B−5 H−1.5 Col +4).
- Mean match 92%; the true recipe re-developed scores 91% against its own JPEG (94–100% on clean pairs), so the look
  measure works on real photos.
- Misses: three black-and-white near-ties (Acros vs Acros+G vs Monochrome, 96–99%: the filters barely differ at 640 px),
  a nearly colourless scene, a pair whose own recipe renders only 55% (the JPEG isn't the RAF's plain development:
  a crop or an in-camera edit), and two real search failures: a Classic Neg. found first and then dropped, and a plain Astia started from the
  library's warm average that never reached neutral.
- A targeted fix (the first guess's film always reaches the final round) helped the simulated benchmark (101.6 →
  105.5) but not that photo, and the second real run (with it and newer first guesses) recovered only 2 of 12: the
  search is unstable on the real camera; small changes in the start lead elsewhere (DSCF4027 went from its exact
  recipe at 97% to Pro Neg. Hi at 94%). Reverted. Next: robustness measured on real pairs (more budget, several
  starts polished), not special cases. The simulated benchmark doesn't predict the real one.

## Research loop (first guess)

`research/` holds an autoresearch-style loop: `Sources/FujiKit/LookGuess.swift` is the one file it changes,
`fuji match --score` the fixed evaluation (dev: the library's photos; held-out: Fuji X Weekly's 452 photos and 162 of
the owner's card photos labelled from EXIF), `research/results.tsv` every experiment. 23 experiments, 8 kept: dev
27.5 → 33.6, held-out (both sets) −30.5 → −28.4. Dropping scene-dependent features (hue, shadow cast, extreme tone
percentiles), weighting the cast more, k = 6 and softer weights helped; correcting for the library's Classic Neg. bias,
shrinking WB, dropping saturation or brightness features didn't.

## Later

The benchmark is the fixed evaluation an autoresearch-style loop (karpathy/autoresearch: an agent edits one file, runs
the fixed evaluation, keeps a change only when the score improves) needs: `LookMatch.refine` and `firstGuess` are the
file, `fuji match --benchmark` the score. On the simulated camera it would overfit to a made-up rendering; on the real
X-E5 with a few RAFs each run costs ~40 minutes of camera time, so a night is ~12 experiments.

A trained model (Deep Preset-style) on camera renders of the owner's RAWs with random recipes (the camera labels them
for free: ~10k pairs is a night of rendering) plus EXIF-labelled Fuji JPEGs, with content-invariant augmentation. It
would replace the first guess, not the camera check. Test it on the real X-E5 first: the simulated camera's look is
made up.
