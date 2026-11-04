# Connect your Fujifilm to the Mac

Out of the box a Fujifilm camera connects as a **card reader**: the Mac sees your photos, not the camera's settings.
To read and write recipes it has to connect in **USB RAW CONV./BACKUP RESTORE** mode. You set that once on the
camera, and it stays set. Menu names below are the X-E5's (from Fujifilm's manual); other recent bodies are the same
or very close.

## Once: set the camera up

1. Press **MENU/OK** and go to the **network/USB** tab (the last tab, with the plug icon).
2. Open **CONNECTION MODE** and choose **USB RAW CONV./BACKUP RESTORE**.
   The other choices are USB CARD READER (the default: photos only) and USB WEBCAM.
3. On the same tab, open **USB POWER SUPPLY/COMM SETTING** and choose **AUTO**
   (POWER SUPPLY OFF/COMM ON also works; POWER SUPPLY ON/COMM OFF only charges and blocks data).

Older bodies (X-T4, X100V, X-S10 era): **SET UP ▸ CONNECTION SETTING ▸ PC CONNECTION MODE ▸ USB RAW CONV./BACKUP RESTORE**.

## Every time: connect

1. Switch the camera **off**.
2. Connect a **USB-C data cable** straight to the Mac (no hub at first; ≤ 1 m is what Fujifilm recommends).
3. Switch the camera **on**. Its screen shows a USB / PC connection screen and its menu is locked while
   connected: that's normal. Take photos again by unplugging.
4. If **Preview** or **Photos** pops up offering to import, the camera is still in card-reader mode (go back to
   step 2 above). Quit them either way.
5. Check: `fuji doctor` (or ask Claude: "is my camera connected?", which runs `fuji_doctor`).

To shoot again, unplug the cable. You can leave CONNECTION MODE on RAW CONV./BACKUP RESTORE: "the camera functions
normally when not connected" (Fujifilm). The trade-off: while it's set, the Mac won't import photos from the camera
over the cable. Use a card reader for that, or switch back to USB CARD READER.

## When it doesn't work: `fuji doctor`

`fuji doctor` checks one step at a time and stops at the first that fails, with the fix:

```
✓ 1. USB      FUJIFILM X-E5 is on USB
✓ 2. Camera   macOS offers it as a PTP camera
✓ 3. Session  X-E5, firmware 1.12
✓ 4. Mode     USB RAW CONV./BACKUP RESTORE
✓ 5. Slots    C1–C7 readable
```

| Step fails | What it means | Fix |
|---|---|---|
| 1 USB | The Mac doesn't see a Fujifilm at all | Camera on? A charge-only cable is the usual culprit: try another. USB POWER SUPPLY/COMM SETTING ▸ AUTO. Plug straight into the Mac. |
| 2 Camera | It's on USB but macOS doesn't offer it as a camera | Unplug, wait 3 s, plug in. Quit photo apps. Check that Image Capture.app lists it. |
| 3 Session | macOS lists it but it doesn't answer | Another app holds it (Preview, Photos, Image Capture, X RAW Studio, the Fujifilm Tether app, Lightroom, Capture One): quit them, then camera off → on. |
| 4 Mode | It answers, but as a card reader / webcam / tether | CONNECTION MODE ▸ USB RAW CONV./BACKUP RESTORE, then camera off → connect → on. Reconnecting matters: the mode is picked when the cable goes in. |
| 5 Slots | RAW CONV. mode, but no custom slots | The body doesn't expose them over USB (X-T3, X-T30, older), or it's busy: off → on. |

Deeper tools, all read-only:

- `fuji status`: model, firmware, USB mode, number of slots.
- `fuji probe`: what the camera advertises and answers. In card-reader mode it lists ~5 properties
  (`5001 D303 D406 D407 D041` on an X-E5); in RAW CONV. mode about 60, including `D18C…D1A4` (the slots).
- `fuji probe D001 D023 …`: any property by code (the live `0xD0xx` shooting state included).
- `ioreg -p IOUSB -w0 -l | grep -A3 FUJIFILM`: what USB itself reports (vendor 1227 = 0x04CB).
- `/usr/bin/log show --last 10m --predicate 'eventMessage CONTAINS "X-E5"'`: which app grabbed the camera.

What we saw on a real X-E5 (fw 1.12): in card-reader mode ImageCaptureCore still opens it and GetDeviceInfo answers,
but only 5 properties are advertised and everything else is refused; Preview offers to import. After switching
CONNECTION MODE and reconnecting with the camera off: 61 properties, mode 6, C1–C7 readable.
