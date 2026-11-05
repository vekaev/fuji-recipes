# Fuji Recipes: working rules

**Read, write, shoot. Nothing else.** See and change what's on your Fujifilm (all ten slots: C1–C7 and the
film simulation dial's FS1–FS3), keep your recipes with real photos of how they look, and add them from reels,
public sources and Claude. Refuse: a social feed, Bluetooth, photo editing, AI-made sample photos.

Looks before numbers: a recipe is its **name**, then **how it looks** (the same reference scenes rendered in every
recipe, your own photos shot with it, the creator's frames), then **tags**; settings only behind "Settings ›".
Decisions and why: `docs/adr/`. Words: `GLOSSARY.md`. Research: `docs/research/brief.md`.

## Layout

| | Mac | iPhone / iPad |
|---|---|---|
| App code | `App/` (Mac entry, menus, window chrome) | `iOS/` (entry, folder picker) |
| Shared SwiftUI | `Shared/` (Looks, Camera, Inbox, Preview, editor, theme, AppModel) | same files |
| Core | `Sources/FujiKit` (Swift package: camera over ImageCaptureCore, library, history, inbox, Doctor) | same |
| Agents | `Sources/fuji` (`fuji` CLI + `fuji mcp`), `skills/fuji-recipes` (/recipe) | — |
| Schemes | `FujiRecipes` | `FujiRecipes-iOS` |

## Rule: every change ships on Mac and iPhone/iPad (and MCP when it touches data)

1. A task list with one item per platform (Mac, iPhone/iPad) plus shared FujiKit / MCP work, before code.
2. Translate, don't copy: drag onto a slot ↔ tap a slot then pick; hover ↔ visible hint; right-click ↔ long-press;
   side panes ↔ full-screen views. iPad at regular width uses the Mac layout, compact width the iPhone one.
3. A feature that doesn't apply to one platform: say so in the reply and record it in the parity table below.
4. Build every scheme before saying it's done:
   ```bash
   xcodegen generate
   xcodebuild -project FujiRecipes.xcodeproj -scheme FujiRecipes -configuration Debug -derivedDataPath build -quiet build
   xcodebuild -project FujiRecipes.xcodeproj -scheme FujiRecipes-iOS -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17 Pro" -derivedDataPath build -quiet build
   swift test
   ```
5. Restart both apps with the new build (no need to ask): `scripts/install-mac.sh` and `scripts/run-ios-sim.sh`.
   install-mac.sh signs the installed copy with the owner's Apple Development certificate, so macOS keeps its
   permissions (Downloads / Desktop photos, camera) across rebuilds. Never ad-hoc sign the owner's copy: every
   reinstall would ask again. Public release builds stay ad-hoc (others don't have the certificate).
   Simulator tools: always pass `device: "03B18753-A9C9-4A8C-9ADC-3BA0FB353BA7"` (iPhone 17 Pro; "DayGate Test" is
   another project's). MCP changes: `scripts/dev-install.sh`.
6. Check on screen (simulator screenshots; the Mac via computer-use, never clicking in the owner's open window
   without asking), commit, push to `main`. Update the parity table and the README.

## Camera safety (non-negotiable)

- In the app the owner's own action is the approval (owner's choice, 2026-11-04): a look dropped on a slot, Put back,
  or a dial edit (0.8 s after the last change) is written right away. Every write still backs up the slots it
  changes (read from the camera) first, reads them back, and the toast offers Undo (8 s), which writes the old
  contents back the same way. "Ask before writing" (Settings, ⋯, Camera menu; off by default) brings back the
  "now → new" review. The app's only write path is `AppModel.writeChanges`.
- Claude never writes on its own: MCP stays `fuji_plan_write` → the owner approves the preview → `fuji_apply_write`.
- Every write records what the slot held in the slot history (`history/`), so nothing is lost: "Put back" restores it.
- FS1–FS3 are written only through `FujiCamera.writeDialSlot` (ADR 0004: supervised test passed 2026-11-04): whole
  settings file saved first, patched, restored in a fresh session, read back and compared. WB shift and mono WC/MG
  are left as set on the camera until mapped. `fuji settings-restore` (whole file) is for supervised use only. Never write a slot to verify something; test with `--simulate` / `SimulatedCamera`.
- Looks are real or absent: camera-rendered scenes, the owner's photos, the creator's frames, else "not rendered
  yet". No colour-filter imitations in the app.

## Connecting the camera (tell the owner exactly this)

Full guide: docs/CONNECT.md. Only **USB RAW CONV./BACKUP RESTORE** mode exposes the slots; the factory default
**USB CARD READER** shows the photos.

- **Once (X-E5 wording):** MENU/OK ▸ network/USB tab ▸ CONNECTION MODE ▸ USB RAW CONV./BACKUP RESTORE, and USB POWER
  SUPPLY/COMM SETTING ▸ AUTO. Older bodies: SET UP ▸ CONNECTION SETTING ▸ PC CONNECTION MODE.
- **Every time:** camera off ▸ USB-C data cable ▸ camera on. The mode is picked when the cable goes in. The camera's
  menu is locked while connected.
- **Check:** `fuji doctor` / `fuji_doctor` / the app's live check. The owner's X-E5 (fw 1.12) needed both settings and
  camera off → plug → on (2026-11-04). Card reader: 5 properties; RAW CONV.: 61, C1–C7 readable.
- **Using slots on the camera:** docs/USING-SLOTS.md. The dial wins: a C slot's film applies only with the dial on C
  (dial C ▸ Q ▸ SELECT CUSTOM SETTING ▸ C1–C7).

## Library

`~/Library/Mobile Documents/com~apple~CloudDocs/Fuji Recipes` (iCloud Drive) when iCloud Drive is on, else
`~/Documents/FujiRecipes`, or `$FUJI_RECIPES`. iPhone/iPad open the same folder with the Files picker (bookmark).
Shared with `/recipe` and `fuji mcp`: field names in skills/fuji-recipes/references/schema.md. Folders: `recipes/`,
`inbox/`, `history/`, `scenes/`, `samples/`, `backups/`, `kits/`; `library.md` is generated.

## Parity table

| Feature | Mac | iPhone / iPad | MCP |
|---|---|---|---|
| Looks (name, scenes/photos, tags, filter chips, settings behind ›) | ✓ | ✓ (iPad regular = Mac layout) | `fuji_recipes`, `fuji_recipe` |
| Edit a recipe: name, description, status, tags, creator + link (slug and photos stay; settings read only) | ✓ click anywhere on the card (photos open the preview), Edit ›, right-click "Edit…"; Save / Cancel | ✓ tap anywhere on the card (photos open the preview), Edit › | `fuji_edit_recipe`, `fuji_tag` |
| Photo tiles: fixed size from width + ratio, every photo fills (portrait cropped; the preview shows it whole) | ✓ | ✓ | — |
| Fast photos: thumbnails decoded in parallel, kept as small JPEGs in Caches/thumbs (keyed by path, size, date, pixels) | ✓ | ✓ | — |
| Top bar: Recipes · Add recipes; camera as a green dot + name (hover: since when, firmware; grey "No camera" opens the guide); status text only while busy; a hairline before ⋯ | ✓ | iPad: same; iPhone: tab bar (Recipes, Camera, Add) | — |
| Updates: Sparkle daily check, Check for Updates…, Settings toggle; DMG + one-line installer | ✓ | n/a (App Store / TestFlight later) | `fuji update` for the CLI |
| One top bar: window buttons re-centred in the 38 pt bar beside the tabs (`TrafficLights` in App/MacSupport.swift) | ✓ | n/a (no window buttons) | — |
| Modals: click outside or Esc closes (the recipe page keeps its edits; Cancel discards) | ✓ own overlay, not a system sheet | ✓ system sheet, swipe down keeps edits | — |
| Pointing-hand cursor on everything clickable (`.pointer()`; every `.buttonStyle(.plain)`, pills, chips, photos, rows, menus) | ✓ | iPad pointer: hover lift | — |
| Click/tap an image → preview, arrows / swipe between images and recipes | ✓ (Space / Esc) | ✓ (tap, swipe) | — |
| Slots: Mac / wide iPad have two tabs (Recipes, Add recipes); the slot column beside the looks takes drops, a click opens the slot's page as a modal (photos, since / last used, swap in, history + Put back, Settings › dials). iPhone keeps a Camera tab (no room for a column). No camera: "Connect camera" in the top bar opens the guide as a modal | ✓ drag onto a slot, click a slot | ✓ Camera tab: tap a slot, pick a look; iPad regular = Mac | `fuji_slots`, `fuji_plan_write` / `fuji_apply_write` |
| Instant writes: drop / Put in / Put back / dial edits go straight to the camera (slot backup, read-back, Undo in the toast); "Ask before writing" setting brings the review back | ✓ (Settings, ⋯, Camera menu) | ✓ (Camera tab toggle on iPhone; ⋯ on iPad) | plan → approve → apply (unchanged) |
| Same recipe in two slots: ⧉ in the slot column (hover: "Same recipe as C3"), "also in C3" on iPhone, "same recipe as C3" on the slot page; FS compared without WB shift / toning | ✓ | ✓ | — |
| Camera limits: a slot still shows its recipe when the camera kept a lower DR (DR200/DR400 need the slot's hidden ISO ≥ 320/640; not settable over USB) or dropped B&W toning; the slot page says what differs; refusals are explained in the message with the on-camera fix (`RecipeSettings.cameraLimitedDifferences`, `Library.matchOnCamera`) | ✓ | ✓ | `fuji_slots` → `cameraLimits` |
| Studio: one RAW (.RAF, same model) developed by the camera with each recipe (upload once 0x900C/D, profile 0xD185 per recipe, trigger 0xD183, fetch + delete the new object; `FujiKit/Render.swift`), cached in `renders/`, grid + big preview to compare, ♡ per tile; filters Favorites & to try / All / ♡ / To try / tags | ✓ Studio tab (⌘2), drop or choose a RAF | ✓ Studio tab; the RAF is copied into the library | `fuji_render`, `fuji render <raf> [recipes]` |
| Match a look (`FujiKit/Look.swift`, ADR 0006): any reference photo → `LookStats` (tone shape around the median, cast of near-grey pixels per zone, saturation per hue, grain, local contrast; flat borders trimmed) → first guess from the library's own sample photos (nearest neighbours, `LookIndex` in `looks.json`; rules alone when the library has < 15 photos) → camera search on the Studio RAW (film simulations, then Levenberg–Marquardt on WB shift / Color / tone with one-render-per-setting sensitivities, every film corrected once, polish; budget 60 renders) → three closest with a match %, Save = to-try recipe "Look of <file>" with the reference + render as samples. `fuji match --evaluate` reports accuracy on the library | ✓ Studio ▸ Match a look: drop / choose a photo or From Photos, "Looks like" chips, first guess + Save, "Find the closest recipe", results next to the reference | ✓ same view; picked photos (Files or Photos) are copied into the library's studio/looks | `fuji_match_look`, `fuji match <photo> [raf] [--budget N] [--save Name]`, `--evaluate`, `--benchmark [raf] [--cases N] [--seed N]`, `--learn <jsonl> --name` |
| Slot history + Put back | ✓ | ✓ | `fuji_slot_history` |
| Add recipes (was Inbox, then New looks): paste/drop links, Instagram export, Keep/Skip | ✓ (drop, paste) | ✓ (paste; share extension: later) | `fuji_inbox`, `fuji_inbox_add`, `fuji_inbox_resolve` |
| Reading reels | via Claude / `/recipe` on the Mac | queued, read on the Mac | `fuji_inbox` → `/recipe` |
| Connect guide + live check | ✓ (USB, ioreg) | ✓ (no USB step: iOS can't see the bus) | `fuji_doctor` |
| FS1–FS3 (film simulation dial) | ✓ drop / Put in / Undo (WB shift, toning kept) | ✓ same | `fuji_plan_write` slot "FS1"…"FS3" → approve → `fuji_apply_write` |
| Reference scenes rendered by the camera | not yet (ADR 0003 spike) | not yet | not yet |
| Recipes from your photos' EXIF | ✓ (exiftool) | n/a (no exiftool on iOS; the Mac fills the library) | `fuji_import_photos` |

## Tests (run `scripts/test.sh` before saying anything works)

- `swift test`: FujiKitTests (codec, settings file, FS writes, session rule, DR gate, studio rendering, Match a look:
  measuring, border trim, learning from library photos, camera search finding a known recipe and staying B&W, saving;
  inbox, history) against `SimulatedCamera`, which models the X-E5's refusals, settings file + checksum, hidden-ISO DR gate
  and RAW development; FujiCLITests run the real `fuji mcp` binary over JSON-RPC like Claude (simulated camera,
  throwaway library), including `fuji_match_look` with a camera search and `--evaluate`.
- The simulated camera's renders react to every setting (film character per hue, Color, WB shift, tone, B&W toning)
  so searches can be tested; they are not Fujifilm's rendering. Real accuracy needs the owner's X-E5 and a RAF.
- `fuji match --benchmark [raf]`: 20 hidden recipes (seed 7) developed and found again from their renders alone; one
  score to compare search changes (simulated camera 2026-11-04: 15/20 at 85%+, 12/20 recovered, score 101.6). Run it
  before and after any change to `LookMatch.refine` and keep the change only if the score goes up.
- `fuji match --real <folder with JPEG+RAF pairs> [--cases N]` is the real test (camera connected, Mac app quit):
  the JPEG's EXIF recipe is hidden and the camera search must find it. 2026-11-04 on the owner's card: 6/12 recovered,
  mean match 92% vs 91% for the true recipe itself.
- `research/`: the first-guess research loop (program.md, `fuji match --score`, results.tsv). Only
  `Sources/FujiKit/LookGuess.swift` changes during a run.
- `FujiRecipesUITests` (scheme FujiRecipes-iOS → test): the iPhone app with `-uiTesting` (throwaway library seeded by
  `AppModel.uiTestLibrary`, simulated X-E5): rename a recipe, put one in C3 + Undo, Studio render + preview, Match a look (guess → camera
  search → save → in Recipes), add links.
  New screens get an accessibility identifier and a UI test here. Mac UI tests: not added (they'd drive the owner's
  screen); the Mac shares the same views and model.

## Shipping

- CLI + MCP: `scripts/install.sh` (public one-liner, POSIX sh), `scripts/release.sh X.Y.Z` (ask first: public),
  `scripts/dev-install.sh` for development. Never replace a release asset.
- Mac app: `scripts/release.sh` also builds `FujiRecipes-mac.dmg` (dmgbuild, white "Drag to Applications" window from
  `Support/DMG`) and `appcast.xml` (Sparkle 2, EdDSA key in the login keychain, account `fuji-recipes`; public key
  `SUPublicEDKey` in project.yml). Installed copies check daily (`App/Updater.swift`: app menu Check for Updates…,
  Settings ▸ updates). `scripts/install-app.sh` is the app's one-line installer (no Open Anyway); `scripts/signing.sh`
  signs with Developer ID / Apple Development when present so permissions survive updates (`build-app.sh`,
  `install-mac.sh`). One version for app + CLI. iPhone / iPad: n/a here (App Store / TestFlight later).
