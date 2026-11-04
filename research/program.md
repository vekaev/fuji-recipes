# Research loop: the first guess (autoresearch-style)

Like karpathy/autoresearch: change one file, run the fixed evaluation, keep the change only if the score improves.

- **The file you change:** `Sources/FujiKit/LookGuess.swift` (features, nearest neighbours, the blend that makes the
  first guess). Keep the public signatures of `LookMatch.nearest` and `LookMatch.firstGuess(_:index:recipes:exclude:)`.
- **Fixed, never changed during a run:** `Sources/FujiKit/Look.swift` (how photos are measured, `LookMatch.evaluate`,
  `LookMatch.score`), the data, this file's rules. If an idea needs a new measurement, stop the run and propose it.
- **The evaluation:** `FUJI_SIMULATE=1 FUJI_RECIPES=<eval library> fuji match --score` (≈3 s). It prints
  `dev <score> held-out <score> | details`.
  - dev: the library's own sample photos, each guessed with its recipe (and any with identical settings) left out.
  - held-out: reference-set photos (Fuji X Weekly, 452 photos of 113 recipes, other photographers and scenes), guessed
    from the library alone. Nothing may learn from them.
  - score = 100·film exact + 50·film family − 8·(mean step error of WB red, WB blue, highlight, shadow, Color)
    + 30·(dev only) recognising a library recipe in the top three.
- **Keep a change** when dev goes up and held-out doesn't go down by more than 1 (noise); otherwise revert it.
  Log every experiment in `research/results.tsv` (kept or not, with the numbers), commit the kept ones.
- **The eval library:** a copy of the owner's library (recipes/ + samples/) plus a reference set imported with
  `fuji match --learn <recipes.jsonl> --name "Fuji X Weekly"`. It stays local; reference photos are never published.
- Don't tune against the simulated camera's renders (`--benchmark`): its look is made up. Real accuracy of the camera
  search needs the owner's X-E5.
