# 4. All ten slots editable; FS1–FS3 after a supervised test

Date: 2026-11-04 · Status: accepted

C1–C7 are written through the bank properties (confirmed on the X-E5). FS1–FS3 live only in the camera's settings
file (PTP object 0, 70,524 bytes on the X-E5): writing them means patching the file (additive checksum at 0x120,
grawji's research) and restoring it whole. Reading matched the owner's photos except the WB shift offsets. So FS
writes ship only after a supervised test on the owner's camera: backup, change one harmless FS3 value, read back,
restore. Every write keeps the previous contents in the slot history; "Put back" restores them.

## Supervised test, 2026-11-04 (owner's X-E5, firmware 1.12): passed

Each phase in its own process / PTP session (`fuji backup --full`, `fuji settings-restore <file> --owner-is-watching`),
the Mac app closed. Files kept in `~/Documents/FujiRecipes/backups/fs-test-2026-11-04/`.

1. Two reads of the settings file (object 0, 70,524 bytes): byte-identical.
2. Round trip, the unchanged file sent back (SendObjectInfo 0x100C [0,0], 1076-byte ObjectInfo, format 0x5000; then
   SendObject 0x100D): accepted in ~2 s. Read back: C1–C7 identical (settings, names, raw values); 11 bytes differ, all
   the camera's own bookkeeping: the checksum (0x120), "_FUJI" written at 0x1744–0x1748, a counter at 0xF6C0–0xF6C4.
3. FS3 Sharpness 0 → +1 (one byte at 34760, checksum −1, as grawji describes): accepted; read back exactly as sent
   apart from another counter at 0xF724–0xF725; `fuji slots` shows FS3 Sharpness +1; C1–C7 identical.
4. Original restored: FS3 Sharpness back to 0, C1–C7 identical, only the bookkeeping bytes above differ.

So: the restore path and the delta checksum work on the X-E5 through ImageCaptureCore. Still unverified: the WB shift
and monochrome WC/MG offsets (they decode 0/0 where the owner's photos say otherwise). Map them by having the owner set
a known shift on FS3 on the camera and diffing two reads. Until then FS writes leave those fields alone.

## Shipped, 2026-11-04

`FujiCamera.writeDialSlot` (download → `SettingsFile.patch` → fresh session → restore → fresh session → read back and
compare, ignoring the camera's bookkeeping bytes) is the one FS write path, used by the app and by
`fuji_plan_write` / `fuji_apply_write` (slots "FS1"…"FS3"). Checked on the owner's X-E5 in one process, as the app runs
it: FS3 Sharpness 0 → +1 changed exactly that byte; writing 0 back left the file identical apart from bookkeeping.
Before every FS write the whole settings file is saved in `backups/` (`…-settings-before-fsN.dat`). WB shift, mono
WC/MG and D-Range Priority are left as set on the camera until their offsets are mapped.
