enum Guide {
    static let text = """
    Fujifilm recipes and custom slots

    A recipe is the set of in-camera JPEG settings a custom slot (C1–C7; C1–C4 on X-S20, X-M5, X-S10) stores. Library: ~/Documents/FujiRecipes (recipes/<slug>.json, kits/, backups/, library.md). The /recipe skill and the app use the same folder.

    Fields and values (as in the recipe files):
    • film: Provia, Velvia, Astia, Classic Chrome, Reala Ace, Pro Neg. Hi, Pro Neg. Std, Classic Neg., Nostalgic Neg., Eterna, Eterna Bleach Bypass, Acros, Acros+Ye, Acros+R, Acros+G, Monochrome, Monochrome+Ye, Monochrome+R, Monochrome+G, Sepia
    • grain_roughness Off|Weak|Strong · grain_size Off|Small|Large (Off when roughness is Off)
    • color_chrome, color_chrome_fx_blue: Off|Weak|Strong
    • wb: Auto, Auto White Priority, Auto Ambience Priority, Daylight, Shade, Fluorescent 1–3, Incandescent, Underwater, Kelvin (then wb_kelvin 2500–10000) · wb_red, wb_blue −9…+9 (WB Shift)
    • dynamic_range Auto|DR100|DR200|DR400 · d_range_priority Off|Auto|Weak|Strong (when on, the camera sets DR and tone)
    • highlight, shadow −2…+4 in 0.5 steps
    • color −4…+4 (null for monochrome films) · mono_warm_cool, mono_magenta_green −9…+9 (monochrome films only)
    • sharpness −4…+4 · high_iso_nr −4…+4 · clarity −5…+5
    Not stored in a slot (keep them in the recipe's shooting advice): ISO, exposure compensation, lens, filters.

    Camera rules
    • DR200 needs ISO ≥ 2× base and DR400 ≥ 4× base (on the X-E5 DR400 needs ISO 640+); D-Range Priority on locks DR and tone; mono films refuse Color, colour films refuse mono toning; Clarity is refused when the slot shoots HEIF.
    • Bodies with a film simulation dial (X-E5, X-T50, X-M5, X-T30 III): the dial overrides the slot's film unless it's on C. FS1–FS3 can't be written over USB.
    • Supported for slot writes: X-T5, X-H2, X-H2S, X100VI, X-T50, X-E5, X-S20, X-M5, X-S10, X-T30 II, GFX100S, GFX100 II, GFX100RF; X100V partly. Not: X-T3, X-T30 and older (no slot properties), X-Pro3 (fails). X-T4, X-E4: untested.
    • USB mode must be USB RAW CONV./BACKUP RESTORE; the camera's menu is locked while connected.

    Safety
    • Reads change nothing. Writes go plan → preview → user approves → apply; every apply saves a backup of all slots first, writes only what differs, then reads each slot back and reports anything refused or stored differently.
    • Restore any backup with fuji_plan_write {restore: "latest"}.
    • Fujifilm reportedly says connecting unlicensed software may void the warranty. No bricked camera has been reported for slot writes; a stuck camera recovers by switching it off and on.

    Reading recipes from reels and posts
    • Abbreviations: CC = Classic Chrome (film) or Color Chrome (effect) by position; CCFXB / FX Blue; R+2 B−4 = WB shift; DR-P = D-Range Priority; H−1 S+1 = highlight/shadow; NR −4; Grain W/S = weak, small.
    • A field the source doesn't give stays at the default and goes into `uncertain`. Credit the creator (source.creator, source.url); store settings and a link, not their caption or photos.
    """
}
