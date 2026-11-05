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

(none yet)
