# 4. All ten slots editable; FS1–FS3 after a supervised test

Date: 2026-11-04 · Status: accepted

C1–C7 are written through the bank properties (confirmed on the X-E5). FS1–FS3 live only in the camera's settings
file (PTP object 0, 70,524 bytes on the X-E5): writing them means patching the file (additive checksum at 0x120,
grawji's research) and restoring it whole. Reading matched the owner's photos except the WB shift offsets. So FS
writes ship only after a supervised test on the owner's camera: backup, change one harmless FS3 value, read back,
restore. Every write keeps the previous contents in the slot history; "Put back" restores them.
