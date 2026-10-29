-- Standardoppsett (Stigs oppsett, designnotat 6c og 6d).
-- Endre standarden her, så følger veiviseren og pilotoppsettet etter.
-- Fortegn (bestemt): negativ = ror ned / sideror høyre.

return {
  version = "0.2",
  -- Øk når mikserne, kurvene eller bryterne som skrives endres: et oppsett skrevet med en
  -- eldre versjon skrives da på nytt automatisk når veiviseren eller meny 6 åpnes.
  planVersion = 7,   -- 4: timerne uten minuttpip (flyskjermen gir stemmen), 5: ekstra av/på-kanal, 6: motor 1003-1998 µs,
                     -- 7: differensial-trim med trimområde, V-hale-differensial (T5, felles i alle FM)

  -- Kanalstandard, flyet sett bakfra (6d). V-hale bruker kanalene til Elev og Rud.
  -- Piloten kan endre kanalene i pilotoppsettet (P.applyChannels skriver over ch).
  -- aux: valgfri av/på-kanal (f.eks. VifFly2), bare i bruk når piloten har valgt en bryter.
  -- Tip-servoer (6 vingeservoer) er tatt ut 2026-10-28: ikke i bruk i oppsettet ennå.
  ch = { ailL = 1, flapL = 2, elev = 3, rud = 4, vL = 3, vR = 4, flapR = 5, ailR = 6,
         motor = 7, aux = 8 },
  -- Rorene i kanaloppsettet (pilotoppsettet), i visningsrekkefølge
  chRoles = { { key = "ailL", label = "Ail L" }, { key = "flapL", label = "Flap L" },
              { key = "elev", label = "Elev / V-tail L" }, { key = "rud", label = "Rud / V-tail R" },
              { key = "flapR", label = "Flap R" }, { key = "ailR", label = "Ail R" },
              { key = "motor", label = "Motor" }, { key = "aux", label = "Extra on/off" } },
  chMax = 16,   -- høyeste kanal som kan velges (CH17-21 er virtuelle kanaler)
  names = { ailL = "Ail L", flapL = "Flap L", flapR = "Flap R", ailR = "Ail R",
            elev = "Elev", rud = "Rud", vL = "V-L", vR = "V-R",
            motor = "Motor", aux = "Ekstra", tipL = "Tip L", tipR = "Tip R" },

  -- Rekkefølge i senter og endepunkter (steg 2 og 3)
  order = { "flapL", "flapR", "ailL", "ailR", "tipL", "tipR", "elev", "rud", "vL", "vR" },

  -- Standard flykonfig (steg 0)
  -- camberMode: "split" = camber-kontrollen er bare Termikk-slider i Termikk og bare
  -- Speed-slider i Speed (nøytral ellers), "full" = én slider over hele området i alle FM
  cfg = { wing = 4, tail = "X", motor = true,
          thermal = true, speed = true, launch = false, landing = true, camberMode = "split" },

  -- Funksjoner i pilotoppsettet (steg P), i fast rekkefølge.
  -- kind: pos = bryter og posisjon, axis = trinnløs eller trinn, ctrl = bare kontrollen, trim = trimknapp
  -- ends: navn på negativ og positiv ende (etter eventuell snuing)
  funcs = {
    { key = "thermal", label = "Thermal (FM4)", kind = "pos", fm = true, optional = true,
      accept = { "3pos", "2pos" }, default = { ctrl = "se", pos = -1 } },
    { key = "speed", label = "Speed (FM3)", kind = "pos", fm = true, optional = true,
      accept = { "3pos", "2pos" }, default = { ctrl = "se", pos = 1 } },
    { key = "motor_on", label = "Motor on", kind = "pos",
      accept = { "3pos", "2pos" }, default = { ctrl = "sd", pos = 1 } },
    { key = "motor_pwr", label = "Motor power", kind = "axis",
      accept = { "3pos", "pot", "slider" }, ends = { "Low", "Full" },
      default = { ctrl = "sg", rev = false } },
    { key = "test", label = "Trainer/test switch", kind = "ctrl",
      accept = { "mom", "2pos" }, default = { ctrl = "sh" } },
    -- Justering i veiviseren er fast: S1 grovt og S2 fint (L.dualNew), ikke valgbart her
    { key = "camber", label = "Thermal<->Speed", kind = "axis", optional = true,
      accept = { "slider", "pot", "3pos", "2pos" }, ends = { "Thermal", "Speed" },
      default = { ctrl = "rs", rev = false } },
    { key = "crow", label = "Butterfly/crow", kind = "axis",
      accept = { "stick", "slider", "pot" }, ends = { "Full crow", "Crow off" },
      default = { ctrl = "thr", rev = false } },
    { key = "difftrim", label = "Ail differential", kind = "trim",
      default = { trim = "T3" } },
    -- Bare i bruk på V-hale: trimmen endrer ned-siden av sideroret på begge rorene
    { key = "vdifftrim", label = "V-tail differential", kind = "trim",
      default = { trim = "T5" } },
    { key = "volume", label = "Volume", kind = "axis", optional = true,
      accept = { "pot", "slider" }, ends = { "Low", "High" }, default = { ctrl = "s1", rev = false } },
    { key = "landing", label = "Landing (FM1)", kind = "pos", fm = true, optional = true, auto = true,
      accept = { "3pos", "2pos" }, default = { auto = true } },
    { key = "launch", label = "Launch (FM2)", kind = "pos", fm = true, optional = true,
      accept = { "3pos", "2pos" }, default = { none = true } },
    { key = "vario", label = "Vario on/off", kind = "pos", optional = true,
      accept = { "3pos", "2pos" }, default = { none = true } },
    -- Ekstra av/på-kanal (std CH8): -100 % av, +100 % i valgt bryterposisjon
    { key = "aux", label = "Extra channel on/off", kind = "pos", optional = true,
      accept = { "2pos", "3pos" }, default = { none = true } },
  },

  values = {
    dirTest = 40,       -- % utslag i retningstesten (ca. 1300 us)
    centerWarn = 50,    -- us: advarsel om mekanisk justering
    centerMax = 500,    -- us: hele PPM-senterområdet i EdgeTX (PPM_CENTER_MAX)
    centerPot = 80,     -- % av S2-vandringen (fra midten) som gir maks senter/subtrim uten grovkontroll
    centerFine = 25,    -- us over halv S2-vandring når grovkontrollen er i bruk
    flapCenterFine = 10,  -- % subtrim over halv S2-vandring når grovkontrollen er i bruk
    -- Flaps: nøytral med subtrim (offset), servosenteret står ca. 30 grader ned
    flapCenterMax = 195,  -- % flapsenter maks: 100 % subtrim + ca. 95 % (487 us) PPM-senter
    flapLimitSpan = 100,  -- % endepunkt over halv pot-vandring
    flapDegPct = 0.45,    -- grader per % (anslag til visningen, ca. 45 grader ved 100 %)
    flapZeroDeg = 30, flapUpDeg = 8, flapDownDeg = 90,   -- servosenter ned, maks opp, maks ned
    limitStart = 20,    -- % fra nøytral i riktig retning, startverdi for endepunkter første gang
    limitSpan = 50,     -- % endring over halv pot-vandring (uten grovkontroll)
    limitFine = 10,     -- % over halv S2-vandring når grovkontrollen er i bruk
    coarseLimitSpan = 150,  -- % over halv vandring på grovkontrollen (hele området)
    camberFlap = 15, camberAil = 10,   -- % camber ved full Termikk/Speed
    crowFlap = 60, crowAil = 40,       -- % ved full crow
    vtailEle = 70, vtailRud = 50,      -- % V-hale-miks
    motorUp = 3, motorDown = 1,        -- tideler sekund, myk start/stopp (80 % ned fra 15/5, 2026-10-28)
    -- Motorkanalens endepunkter i 0,1 %: 100 % = 512 µs fra 1500, så -97,1 % = 1003 µs (motor av)
    -- og +97,3 % = 1998 µs (full). Settes ved ESC-kalibrering og hver gang oppsettet skrives.
    motorMin = -971, motorMax = 973,
    flapSlow = 5,                      -- tideler sekund, servohastighet flaps (bare camber, ikke crow)
    ailDown = 60,                      -- % aileron ned (differensial i steg 4), opp = 100
    -- Differensial-trim (bestemt 2026-10-29): full trim endrer ned-utslaget med så mange % av
    -- utslaget (begge veier). Aileron med T3, V-hale (sideroret) med T5. Stilles i meny 6.
    diffTrim = 30, vdiffTrim = 30,
    -- Expo (bestemt 2026-10-29), lik i alle FM, i meny 6. Negativ = mykt rundt senter (butterfly:
    -- mykt i starten av crow), 0 = lineær. Stikkene går via CH22-24 bare når expo ikke er 0.
    expo = { ail = 0, ele = 0, rud = 0, crow = 0 },
    -- Camber per ror (bestemt 2026-10-26): i Termikk og i Speed går kontrollen fra minst
    -- utslag fram (Min) til mest utslag bak (Max). Negativ = ror ned.
    camber = { flap = { tMax = -15, tMin = 0, sMax = 5, sMin = 0 },
               ail = { tMax = -10, tMin = 0, sMax = 3, sMin = 0 } },
    crowDead = 5,       -- % av Throttle-vandringen fra crow av uten crow (B3)
    crowRed = 60,       -- % aileron-utslag ved full crow (B2)
    crowDiff = 100,     -- % ned-aileron ved full crow (100 = som uten crow, 0 = ingen ned-aileron)
    potSpan = 100,      -- % endring over halv pot-vandring i justeringene (testperioden: stort)
    landingCrow = 10,   -- % crow som slår på Landing (FM1)
    motorLevels = { 50, 75, 100 },     -- % motor Liten / Medium / Full (M1)
    motorEle = 0,       -- % høyderor opp ved full motor (M5)
    fade = 5,           -- tideler sekund, myk overgang mellom flymoduser (F1)
    logInterval = 2,    -- tideler sekund, logging til SD-kortet (S6)
    lqWarn = 50,        -- % RQly: varsel om svakt signal (S2)
    rxbtWarn = 45,      -- RxBt i sensorens enhet (4,5 V hvis 1 desimal): varsel (S2)
    -- Flyskjerm (bestemt 2026-10-28): flytid nedtelling 10 eller 15 min, motortid og
    -- 10 s nedtelling etter motorkutt (F5J). Valgene lagres i DATA/fly.lua.
    flightMin = 10, flightChoices = { 10, 15 },
    motorSec = 30, motorChoices = { 30, 20, 40, 60 },
    cutSec = 10,
    jingleSec = 120,   -- trudelutt når det er 2 min igjen av flytiden
    motorNagSec = 10, motorNagFile = "/SOUNDS/en/motor.wav",   -- «motor» til motoren er av etter motortiden
    -- Motorbatteri (ER8: RxBt fra spenningsledningen): over packMin V regnes det som en pakke,
    -- celletall = oppover(V / cellDetect). Oransje under cellLow, rød under cellWarn V per celle.
    packMin = 6.0, cellDetect = 4.35, cellLow = 3.7, cellWarn = 3.5,
    -- Graf over batteri og link på flyskjermen: ett punkt hvert graphSec sekund, høyst graphMax
    -- punkter (blir det flere, tas annethvert bort og intervallet dobles)
    graphSec = 2, graphMax = 400,
    -- Verdier per flymodus [FM] = %. FM0 Normal, FM1 Landing, FM2 Launch, FM3 Speed, FM4 Thermal.
    -- Standard 0 (bestemt 2026-10-26): pilotene slår dem på selv i meny 6
    ailRud = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0 },
    snap = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0 },
    -- Ail->Flap (bestemt 2026-10-26): ned i % av flappens utslag ned og opp i % av utslaget opp,
    -- felles for begge flaps. Per flymodus: hvor mye av dette som brukes (100 = som satt).
    afDown = 0, afUp = 0,
    afFM = { [0] = 100, [1] = 0, [2] = 100, [3] = 100, [4] = 100 },
    snapShare = { flap = 20, ail = 0 },   -- % maks kikkflapp per ror (svært liten)
    snapShareMax = 50,                    -- % øvre grense for maks kikkflapp i meny 6
  },

  -- Flymoduser (fast nummer, kap. 3). Lavest nummer vinner.
  fms = {
    { fm = 0, key = "normal", name = "Normal", sound = "normal" },
    { fm = 1, key = "landing", name = "Landing", sound = "landng" },
    { fm = 2, key = "launch", name = "Launch", sound = "launch" },
    { fm = 3, key = "speed", name = "Speed", sound = "speed" },
    { fm = 4, key = "thermal", name = "Thermal", sound = "termik" },
    -- Motor-FM: aktiv mens motoren går, med egen høyderorstrim per motortrinn.
    -- 3-pos bryter for motorkraft gir tre FM, pot/slider gir én (FM5 «Motor»).
    { fm = 5, key = "motor1", name = "Mot Low", motor = 1 },
    { fm = 6, key = "motor2", name = "Mot Medium", motor = 2 },
    { fm = 7, key = "motor3", name = "Mot Full", motor = 3 },
  },

  -- Virtuelle kanaler: én verdi per flymodus, brukt av mikserne på rorene
  vch = { snap = 17, ailRud = 18, ailFlap = 19, camber = 20, crowDiff = 21,
          expoAil = 22, expoEle = 23, expoRud = 24 },   -- stikka med expo (bare når expo ikke er 0)

  -- Kurver (indeks 0-basert) og logiske brytere (0 = L1) som veiviseren eier
  curves = { flapL = 0, flapR = 1, ailL = 2, ailR = 3, tipL = 4, tipR = 5,
             crow = 6, crowRed = 7, eleComp = 8, motor = 9, camT = 10, camS = 11,
             ailFlapL = 12, ailFlapR = 13 },   -- Ail->Flap: opp og ned i % av utslaget, per flap
  ls = { landing = 0, motorOn = 1, landMotor = 2, lock = 3, motorRun = 4, lq = 5, rxbt = 6,
         mot1 = 7, mot2 = 8, mot3 = 9,              -- motor-FM: motor tillatt OG motortrinn
         launchG = 10, speedG = 11, thermalG = 12 }, -- FM-bryter OG motoren står (glidefly-FM)
  maxMixes = 64,
}
