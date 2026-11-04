# 3. Real looks only; reference scenes rendered by the camera

Date: 2026-11-04 · Status: accepted, rendering pending a hardware spike

No colour-filter imitations. A look is shown with, in order: the reference scenes rendered by the camera itself
(upload a RAF, set the conversion profile 0xD185 from the recipe, trigger 0xD183, download the JPEG: the route X RAW
Studio uses, documented in zgrimz/fujifilm-ptp-reference 05-raw-conversion), the owner's photos shot with the
recipe (EXIF), the creator's frames (local only), else "not rendered yet". The owner needs to shoot 3–6 RAW + JPEG
reference scenes on the X-E5 (none on the Mac on 2026-11-04). The rendering ships after a spike on the owner's camera.


## Update 2026-11-04: Studio built

Camera rendering is implemented (`Sources/FujiKit/Render.swift`, protocol in docs/research/raw-rendering.md) and
exposed as the Studio (app), `fuji render` (CLI) and `fuji_render` (MCP), cached in `renders/`. Tested end to end
against the simulated X-E5; the first render on the owner's X-E5 still needs a RAF from that camera and their OK.
