F3X.no tools for RadioMaster TX16S MK3 (800 x 480) and MK2 (480 x 272)
======================================================================

Setup wizard and pilot setup for gliders (F3J/F5J/F3B type, EdgeTX).
Contents: the F3X.no tool with Setup wizard, Pilot setup and Diagnostics.
The same files work on MK3 and MK2; on MK2 the screens are scaled down.

Manual: F3X_manual.html (open in a web browser).

Requirements
- EdgeTX 2.11 or newer, 2.12 recommended (tested with 2.12.5). With 2.10 and older,
  F3X.no asks you to update.
- ExpressLRS 4 on transmitter and receiver, with Arm using: Switch (ON) and Packet Rate
  100Hz Full / 8ch. With ELRS 3, CH5 (Flap R) is on/off only.
- Voice callouts are in English, in SOUNDS/en/.

Installation
1. Connect the radio to the PC/Mac with USB and select "USB Storage (SD)".
2. If you have an older version: first delete the folder SCRIPTS/RM and the files
   SCRIPTS/TOOLS/F3X.lua and F3X.luac on the SD card. Keep SCRIPTS/RM/DATA if you want to
   keep the pilot profile and models. Otherwise the radio may mix old compiled .luac files
   with the new ones.
   Then copy the folders SCRIPTS and SOUNDS from this package to the root of the SD card.
   Note: SOUNDS/en/launch.wav, normal.wav and speed.wav are replaced.
3. Eject the disk and unplug USB.
4. SYS -> Tools -> F3X.no.

Run Diagnostics first, in an empty test model. The results are saved in
SCRIPTS/RM/DATA/diag.lua.

Notes
- S1 = coarse and S2 = fine adjustment (fixed). Keys 1-6 jump to channel 1-6. On MK2 the
  6POS switch is assumed to do this (not tried).
- The checklist assumes ELRS. With a 4-in-1 multi-module the ELRS items do not apply.
