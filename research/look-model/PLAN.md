# Look model: 2–3 example photos → a recipe, on the Mac

Goal: someone shows 2–3 photos with a look (other scenes, other photographers). The app finds the X-E5 recipe that
gives the owner's own RAWs that look. Not a pick from the library: every setting is solved for.
Target: **9 of 10 test cases look the same as the hidden recipe** (definition below).

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

- **Scenes:** ~240 RAFs from the card spread over its 31 days and light (day, shade, dim, night). Split *by day* into
  train 70% / val 15% / test 15%, so near-identical frames never cross splits.
- **Recipes:** realistic random recipes over the camera's whole range (every film sim, WB shift, DR, tone, Color,
  Color Chrome, FX Blue), plus the library's 46 and Fuji X Weekly's 113. Test recipes are never trained on.
- **A case:** 3 example photos = the hidden recipe developed on 3 test scenes. The system also gets 2 of the owner's
  RAFs (other test scenes) and returns a recipe.
- **Judged by the camera:** the found recipe and the hidden one are developed on 3 more unseen test scenes; mean
  CIEDE2000 between the two. **Pass: ΔE00 ≤ 3** (side by side, hard to tell apart). Score = share of cases passed.
  Also reported: film right, each setting's error, mean ΔE.
- **Wild set** (real photos, not our renders): Fuji X Weekly's 452 sample photos of 113 published recipes, and the
  owner's own JPEGs from other days; same pass rule (published / EXIF recipe vs found, developed on test RAFs).
- val is for the loop; test and wild only at milestones, and every number is logged.

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
