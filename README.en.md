# F3X.no – setup wizard for gliders (EdgeTX)

🇳🇴 **Norsk versjon:** [README.md](README.md)

Lua tool for **RadioMaster TX16S MK3** (800×480) and **TX16S MK2** (480×272) with EdgeTX.
Sets up a glider step by step: the pilot's switches and channels, servo direction, centre,
end points, rates, flight modes (Normal, Landing, Speed, Thermal, motor), butterfly/crow,
camber, snap flap, aileron→rudder and aileron→flaps, with English voice call-outs.

**Manual:** [F3X_manual.html](F3X_manual.html) (download and open in a web browser).

## Requirements

- **EdgeTX 2.11 or newer** (2.12 recommended, tested with 2.12.5). Older versions cannot find
  the switches – F3X.no tells you to update.
- **ExpressLRS 4** on transmitter and receiver. With ELRS 3, CH5 is always the arm channel and
  is on/off only. Set **Arm using: Switch (ON)** in MDL → Setup → Internal RF, and in the
  ExpressLRS menu **Packet Rate 100Hz Full** and **Switch Mode 8ch**.
- The voice call-outs are in `SOUNDS/en/` (radio voice language English).

## Installation

1. Download the **English** zip (`F3X.no-EdgeTX_SD_EN_…zip`) under **Releases** (right-hand side of this page).
2. Connect the radio to your PC/Mac with USB and select **USB Storage (SD)**.
3. If you have an older version: first delete `SCRIPTS/RM` and `SCRIPTS/TOOLS/F3X.lua` / `F3X.luac`
   (keep `SCRIPTS/RM/DATA` to keep your pilot profile and models).
4. Copy the contents of the zip file to the root of the SD card: `SCRIPTS` and `SOUNDS`.
   Note: `SOUNDS/en/launch.wav`, `normal.wav` and `speed.wav` are replaced.
5. Eject the disk, unplug USB and start **SYS → Tools → F3X.no**.

Start with a new, empty model. The wizard overwrites mixes on the channels it uses (CH1–9 and CH17–21).

## Channels (default, can be changed in the pilot setup)

| CH1 | CH2 | CH3 | CH4 | CH5 | CH6 | CH7 | CH8/9 |
|---|---|---|---|---|---|---|---|
| Ail L | Flap L | Elev / V-tail L | Rud / V-tail R | Flap R | Ail R | Motor | Tip L/R |

## Flightscreen

**F3X.no → Flightscreen** while flying: flight time from motor on (countdown 10 or 15 min, voice
every minute, a jingle at 2 min, every 10 s from 1 min and every second from 25), motor time
(30 s, voice every 5 s and the last 7), 10 s countdown after motor cut, motor battery (cell count
and V per cell) and link quality. Events are logged to `LOGS/F3X_<model>_<date>.txt`.

## Adjusting

S1 = coarse, S2 = fine (centre both before each surface). PAGE>/< jumps between surfaces without
saving, buttons 1–6 select channel 1–6. Hold SH during adjustments to centre all surfaces.

## Coming

**M-tail** support is on its way, but not ready yet.

## Report errors

The English version is translated from Norwegian. If you find errors in the text (wording,
translation) or in the code, or something that does not work on your radio: please open an
**Issue** here on GitHub (the *Issues* tab → *New issue*). Tell us your radio and EdgeTX version
and which step it is about, and a photo of the screen helps a lot.

## Status

Used on a TX16S MK3 with EdgeTX 2.12.5 and an ER8 receiver. The MK2 version is the same code,
scaled down, and has had little testing on a real radio. Feedback is welcome (see above).

## Licence

Free to download and use for personal use. **Modification and redistribution are not
permitted** – share the link to this repository instead. See [LICENSE](LICENSE). No warranty:
always check surfaces, directions and failsafe before flying.
