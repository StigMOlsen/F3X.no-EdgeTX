# F3X.no – oppsettveiviser for seilfly (EdgeTX)

Lua-verktøy for **RadioMaster TX16S MK3** (800×480) og **TX16S MK2** (480×272) med EdgeTX.
Setter opp et seilfly steg for steg: pilotens brytere og kanaler, servoretning, senter,
endepunkter, utslag, flymoduser (Normal, Landing, Speed, Termikk, motor), butterfly/crow,
camber, kikkflapp, aileron→sideror og aileron→flaps, med norske stemmeutrop.

**Bruksanvisning:** [F3X_bruksanvisning.html](F3X_bruksanvisning.html) (last ned og åpne i nettleseren).

## Krav

- **EdgeTX 2.11 eller nyere** (anbefalt 2.12, testet på 2.12.5). Eldre versjoner finner ikke
  bryterne – F3X.no sier fra og ber om oppdatering.
- **ExpressLRS 4** på sender og mottaker. Med ELRS 3 er CH5 alltid armeringskanal og går bare
  av/på. Sett **Arm using: Switch (ON)** under MDL → Setup → Internal RF, og i ExpressLRS-menyen
  **Packet Rate 100Hz Full** og **Switch Mode 8ch**.
- Talespråk **English** på radioen: de norske utropene ligger i `SOUNDS/en/`.

## Installasjon

1. Last ned siste zip under **Releases** (til høyre på denne siden), eller hele repoet (Code → Download ZIP).
2. Koble radioen til PC/Mac med USB og velg **USB Storage (SD)**.
3. Har du en eldre versjon: slett `SCRIPTS/RM` og `SCRIPTS/TOOLS/F3X.lua` / `F3X.luac` først
   (ta vare på `SCRIPTS/RM/DATA` for å beholde pilotoppsett og modeller).
4. Kopier innholdet i zip-filen (eller mappen `SD/`) til roten på SD-kortet: `SCRIPTS` og `SOUNDS`.
   NB: `SOUNDS/en/launch.wav`, `normal.wav` og `speed.wav` erstattes med norske utrop.
5. Løs ut disken, trekk ut USB, og start **SYS → Tools → F3X.no**.

Start med en ny, tom modell. Veiviseren skriver over mikser på kanalene den bruker (CH1–9 og CH17–21).

## Kanaler (standard, kan endres i pilotoppsettet)

| CH1 | CH2 | CH3 | CH4 | CH5 | CH6 | CH7 | CH8/9 |
|---|---|---|---|---|---|---|---|
| Ail V | Flap V | Elev / V-hale V | Rud / V-hale H | Flap H | Ail H | Motor | Tip V/H |

## Justering

S1 = grov, S2 = fin justering (begge i midten før hvert ror). PAGE>/< hopper mellom ror uten å
lagre, knapp 1–6 henter kanal 1–6. Hold SH inne i justeringene for å sette alle ror i senter.

## Status

Brukt på TX16S MK3 med EdgeTX 2.12.5 og ER8-mottaker. MK2-versjonen er samme kode, skalert ned,
og er lite prøvd på ekte radio. Tilbakemeldinger: åpne en *Issue* her på GitHub.

## Lisens

Gratis å laste ned og bruke til eget bruk. **Det er ikke tillatt å endre eller dele programmet
videre** – del heller lenken til dette repoet. Se [LICENSE](LICENSE). Ingen garanti: sjekk alltid
ror, retninger og failsafe før flyging.
