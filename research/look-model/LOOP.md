# The look model's improvement loop

Like karpathy/autoresearch, with the lessons of its follow-ups (reviewer agents, a fixed referee, a held-out set).

## Fixed, never edited by the loop

- `score.py`, `scenes.py`, `recipes.py`, the frozen cases (`cases-val.json`, the holdout's `cases-test.json`), the
  camera renders. A loop that wants a different measurement stops and proposes it to the orchestrator.
- `~/Library/Caches/FujiRecipes/look-holdout/` is off limits to every loop agent: don't read, list or hash anything
  in it, don't pass it to a tool. Only the orchestrator scores test, at milestones.

## What the loop may change

`common.py` (features, not the recipe layout's meaning), `proxy.py`, `encoder.py`, `synth.py`, `refine.py`,
`predict.py`, new files next to them, the training data jobs (`recipes.py train N` adds more; never edit cases).

## The number

`uv run research/look-model/score.py val --predict "<cmd>" --label "<what changed>"` →
`dE … match … p90 …`. The loop's number is **val dE** (lower is better); p90 and match must not get worse by more
than the noise. Noise: rerun the same predictor once per milestone; differences under 0.05 dE are noise.

## Roles

- **Orchestrator** (the main session): owns the camera queue (one camera job at a time), runs scores, keeps or
  reverts, commits kept changes, scores test at milestones, updates `WORLD_MODEL.md`.
- **Idea agent:** reads `WORLD_MODEL.md` and the last results; proposes one experiment with its predicted effect on
  val dE and why. No code.
- **Worker:** implements one experiment (training within a fixed budget, default 20 minutes), reports val dE.
- **Red-team reviewer:** reads the diff and the result before anything is kept: holdout touched? val cases used for
  training (their refs / evals / recipes)? the score file changed? a gain under the noise? Nothing is kept without it.

## Log

Every run → `results.tsv` (commit, val dE, match, p90, film, minutes, kept/discarded, description). Kept changes are
committed; discarded ones reverted.
