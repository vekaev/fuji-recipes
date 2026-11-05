# Look model: 2–3 example photos → a recipe, on the Mac

Goal: someone shows 2–3 photos with a look (other scenes, other photographers). The app finds the X-E5 recipe that
gives the owner's own RAWs that look. Not a pick from the library: every setting is solved for.
Target: as close as it gets. The owner's bar: "like 9 out of 10, 10 out of 10 also good". The number the loop
drives down is the mean ΔE00 on val; the match rate (worst eval scene ≤ 3) is reported next to it.

## What we learned so far (2026-11-05)

- Same-scene search on the real camera (the JPEG's own RAW developed until it matches): 10/16 recovered on the tuning
  photos, 8/16 on other shots. That is the easy case; the product case is cross-scene, and was never measured.
- Hand-made statistics don't separate scene from recipe (ADR 0006); some settings trade off (DR ↔ highlight,
  Acros filters on a 640 px preview). So the score must judge the *look*, not the exact numbers.
- Prior art: no tool reliably reads a recipe from pixels (Fuji X Weekly's tests; recipe-detector, ToneChef, Fuji Frame,
  Fujicipe are classifiers or chatbots). The closest blueprint is Neural Photo-Finishing (Tseng et al. 2022): learn a
  differentiable proxy of the processor, solve for the sliders by gradient descent, and an encoder that reads sliders
  from an image. Deep Preset trained the same idea on 600k synthetic renders. Our advantage: the real camera renders
  any recipe on the owner's RAWs (~2 s each, ~1,800/hour), and macOS decodes X-E5 RAFs (CIRAWFilter).
- Autoresearch lessons: one fixed metric in a file the loop can't edit; a held-out set the loop never sees; measure the
  noise floor first; a red-team reviewer for every kept change (loops learn to "rewrite the referee").

## 1. The test (frozen before any model work; the loop never edits it)

Built by `scenes.py` and `recipes.py`, judged by `score.py`; reviewed by a red-team agent before any render.

- **Scenes:** 415 of the owner's X-E5 RAFs, split by shooting session (a gap over 6 h), never by frame: train 217,
  val 99, test 99, with the same mix of light (day / shade / dim / night) and as-shot dynamic range in val and test.
- **Roles in val and test:** *owner* scenes (DR400 shots, so any DR renders and their EXIF tells nothing) are the RAWs
  a method gets and the eval scenes. *Ref* scenes only appear as example photos: rendered JPEGs, re-encoded under
  salted names, no EXIF; their RAWs are never given to a method or decoded. So a case is really cross-scene.
- **Recipes:** half real (the library's recipes for that split, and small changes of them), half random over the
  camera's whole range (DR100/200/400 only: Auto and D-Range Priority don't render from a RAW). Library recipes near a
  val or test recipe never seed training.
- **A case:** `score.py` runs the method once per case, in a fresh process, on a copy of the case folder: `refs/` (3
  example photos) and `inputs.json` (2 owner RAFs). The method prints a recipe.
- **Judged by the camera:** the found and the hidden recipe are developed on 3 more owner scenes; grain, sharpness
  and NR are copied from the hidden recipe first (texture, not look), the renders are shrunk 4×, and CIEDE2000 is
  averaged per scene. Reported: mean ΔE (the loop's number), match rate (worst scene ≤ 3), film right, and separately
  colour / B&W and real / random recipes.
- **Holdout:** the test cases, their RAWs and renders live in `~/Library/Caches/FujiRecipes/look-holdout`, which no
  loop agent may read. Test is scored only at milestones and logs only the summary. 80 val + 80 test cases.
- **Sweep:** every setting at its extremes on 3 train scenes, to learn which ones the camera ignores (e.g. FX Blue on
  B&W) and how far each moves the look; labels of settings that don't show are dropped from training.

## 2. Data

Camera renders of train scenes, each random recipe on 4+ scenes (so a model sees the same look across scenes), plus
the RAF decoded on the Mac (linear, 512 px) for each scene. Cached on disk; nothing leaves the Mac; never committed.

## 3. Models (all local, PyTorch on the M4 Max GPU, later Core ML in the app)

1. **Camera proxy:** (RAW, recipe) → JPEG. Per-pixel network conditioned on the recipe (a neural 3D LUT) plus a global
   tone stage for DR / highlight / shadow. Bar: ΔE00 ≤ 2 to the camera on val scenes.
2. **Encoder:** 2–3 photos → film probabilities + every setting, trained on renders of the same recipe on different
   scenes so it learns the look, not the scene.
3. **Fit:** start from the encoder's top films, gradient descent through the proxy so the owner's RAFs match the
   examples' colour and tone distributions (sliced-Wasserstein in Lab, as in MS-SWD), several starts.
4. **Camera check:** the best few candidates developed on the camera, the existing search polishes, the camera decides.

## 4. The loop

- Orchestrator (main session) runs the plan, owns the camera queue (one job at a time), and alone promotes a change.
- Idea agent: proposes one experiment with its predicted effect and why, from `WORLD_MODEL.md` (what's known, what
  failed).
- Worker: implements it in a worktree, trains within a fixed time budget, scores on val.
- Red-team reviewer: reads every candidate diff and result for leakage (test/wild data touched, metric changed,
  splits crossed), noise (repeat runs), and overfitting; nothing is kept without its OK.
- Every run in `results.tsv`; kept changes committed; test score at milestones only.

## Needs from the owner

- Camera time: X-E5 on USB in RAW CONV. mode, Mac app closed. ~10–15 hours of renders for the first dataset (nights).
- Optional photos that the card lacks: people/skin, warm indoor (tungsten), sunset, deep greenery, snow or beach,
  neon at night. RAW+JPEG, any recipe.
