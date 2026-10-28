-- Felles hjelpefunksjoner for RM-veiviseren: skjerm og knapper, kontroller,
-- filer på SD-kortet og midlertidige testmikser.

local L = {}

L.DATA = "/SCRIPTS/RM/DATA/"
L.IMG = "/SCRIPTS/RM/IMG/"
-- Layouten er tegnet for 800 x 480 (MK3). På mindre skjermer (TX16S MK2, 480 x 272) tegnes
-- den samme layouten nedskalert gjennom scale.lua. All tegning går gjennom L.lcd.
L.W, L.H = 800, 480
local lcd = lcd
if LCD_W and LCD_W < 800 then
  local sc = loadScript("/SCRIPTS/RM/scale.lua")
  if sc then lcd = sc()(LCD_W / 800, (LCD_H or 272) / 480) end
end
L.lcd = lcd
L.TMP = "RMtmp"   -- navn på midlertidige testmikser, slettes alltid igjen
L.SH = "RMsh"     -- midlertidig «alle ror i senter» på testbryteren (meny 6), slettes alltid igjen

local function rgb(r, g, b)
  if lcd.RGB then return lcd.RGB(r, g, b) end
  return 0
end

-- Mørkt tema som skissene i prosjektbeskrivelsen
L.C = {
  bg = rgb(16, 21, 27), text = rgb(230, 237, 243), dim = rgb(139, 152, 165),
  head = rgb(194, 86, 15), headText = rgb(255, 255, 255),
  btn = rgb(27, 35, 44), focus = rgb(74, 52, 30), off = rgb(22, 27, 33),
  act = rgb(243, 156, 80), ok = rgb(76, 175, 105), warn = rgb(231, 76, 60),
  edge = rgb(107, 124, 141), primary = rgb(194, 86, 15), green = rgb(46, 125, 72),
  panel = rgb(27, 35, 44),
}

------------------------------------------------------------------------
-- Kontroller på TX16S MK3. Navnene varierer mellom EdgeTX-versjoner.

L.CONTROLS = {
  { key = "sa", label = "SA", type = "3pos", names = { "sa", "SA" } },
  { key = "sb", label = "SB", type = "3pos", names = { "sb", "SB" } },
  { key = "sc", label = "SC", type = "3pos", names = { "sc", "SC" } },
  { key = "sd", label = "SD", type = "3pos", names = { "sd", "SD" } },
  { key = "se", label = "SE", type = "3pos", names = { "se", "SE" } },
  { key = "sg", label = "SG", type = "3pos", names = { "sg", "SG" } },
  { key = "sf", label = "SF", type = "2pos", names = { "sf", "SF" } },
  { key = "sh", label = "SH", type = "mom",  names = { "sh", "SH" } },
  { key = "s1", label = "S1", type = "pot",  names = { "s1", "S1", "P1" } },
  { key = "s2", label = "S2", type = "pot",  names = { "s2", "S2", "P2" } },
  { key = "ls", label = "LS", type = "slider", names = { "ls", "LS", "sl1", "SL1" } },
  { key = "rs", label = "RS", type = "slider", names = { "rs", "RS", "sl2", "SL2" } },
  { key = "thr", label = "Throttle", type = "stick", names = { "thr", "Thr", "THR" } },
  { key = "ail", label = "Ail", type = "stick", names = { "ail", "Ail", "AIL" } },
  { key = "ele", label = "Ele", type = "stick", names = { "ele", "Ele", "ELE" } },
  { key = "rud", label = "Rud", type = "stick", names = { "rud", "Rud", "RUD" } },
}

L.TRIMS = { "T1", "T2", "T3", "T4", "T5", "T6" }

L.TYPE_LABEL = { ["3pos"] = "3-pos", ["2pos"] = "2-pos", mom = "fjærbelastet",
                 pot = "pot", slider = "skyver", stick = "stikke" }

L.POS = { [-1] = "OPP", [0] = "MIDT", [1] = "NED" }

function L.findSource(names)
  for _, n in ipairs(names) do
    local info = getFieldInfo(n)
    if info then return info.id end
  end
  return nil
end

function L.initControls()
  L.byKey = {}
  for _, c in ipairs(L.CONTROLS) do
    c.id = L.findSource(c.names)
    L.byKey[c.key] = c
  end
end

function L.ctrl(key)
  if not key then return nil end
  return L.byKey[key]
end

function L.value(c)
  if not c or not c.id then return 0 end
  return getValue(c.id) or 0
end

function L.pos(v)
  if v < -500 then return -1 elseif v > 500 then return 1 end
  return 0
end

-- Bryterindeks for en bryterposisjon (til mix-bryter). Prøver flere navneformer.
local ARROWS = {
  [-1] = { "\226\134\145", "u", "0", "Up" },
  [0]  = { "-", "\226\134\148", "1", "Mid" },
  [1]  = { "\226\134\147", "d", "2", "Down" },
}

function L.switchIndex(key, pos)
  local base = string.upper(key)
  local cands = {}
  if pos == -1 and CHAR_UP then cands[#cands + 1] = base .. CHAR_UP end
  if pos == 1 and CHAR_DOWN then cands[#cands + 1] = base .. CHAR_DOWN end
  for _, a in ipairs(ARROWS[pos] or {}) do cands[#cands + 1] = base .. a end
  for _, n in ipairs(cands) do
    local ok, idx = pcall(getSwitchIndex, n)
    if ok and idx then return idx, n end
  end
  return nil
end

------------------------------------------------------------------------
-- Knappene 1-6: funksjonsbryterne SW1-SW6 på TX16S MK3 (sett i RM Diagnose), ellers
-- 6POS-bryteren (TX16S MK2, antatt navn). L.keyPressed gir nummeret på knappen som ble
-- trykket. Knappene på MK3 kan stå i en gruppe der et trykk slår på én og av en annen:
-- da gjelder den som ble slått på. Et nytt skifte like etter på samme knapp (slipp av en
-- fjærbelastet knapp) telles ikke.
local KEY_GAP = 50   -- getTime-enheter à 10 ms

function L.keysNew()
  local k = {}
  for i = 1, 6 do
    local id = L.findSource({ "sw" .. i, "SW" .. i })
    local sidx = (not id) and L.switchIndex("sw" .. i, 1) or nil
    if id or sidx then k[i] = { id = id, sidx = sidx } end
  end
  if not next(k) then
    local id = L.findSource({ "6pos", "6POS", "6p", "6P" })
    if id then k.six = { id = id } end
  end
  return k
end

local function keyOn(c)
  if c.id then return (getValue(c.id) or 0) > 0 end
  return getSwitchValue ~= nil and getSwitchValue(c.sidx) == true
end

function L.keyPressed(k)
  if k.six then
    local v = getValue(k.six.id) or 0
    local pos = L.clamp(math.floor((v + 1024) * 5 / 2048 + 0.5) + 1, 1, 6)
    local last = k.six.last
    k.six.last = pos
    if last and pos ~= last then return pos end
    return nil
  end
  local now = getTime()
  local on, off
  for i = 1, 6 do
    local c = k[i]
    if c then
      local v = keyOn(c)
      if c.last ~= nil and v ~= c.last and (not c.t or now - c.t > KEY_GAP) then
        if v then on = on or i else off = off or i end
      end
      c.last = v
    end
  end
  local hit = on or off
  if hit then k[hit].t = now end
  return hit
end

-- PAGE> og PAGE< (navnene varierer mellom EdgeTX-versjoner)
function L.isPageNext(e)
  return e ~= nil and e ~= 0 and (e == EVT_VIRTUAL_NEXT_PAGE or e == EVT_PAGEDN_FIRST)
end

function L.isPagePrev(e)
  return e ~= nil and e ~= 0 and (e == EVT_VIRTUAL_PREV_PAGE or e == EVT_PAGEUP_FIRST)
end

function L.round(x)
  return math.floor(x + 0.5)
end

function L.clamp(x, lo, hi)
  if x < lo then return lo elseif x > hi then return hi end
  return x
end

function L.copy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = L.copy(v) end
  return r
end

-- Brytere etter navn ("L1", "FM3", "ON", "SD↓"). Prøver getSwitchIndex og leter
-- ellers gjennom getSwitchName, fordi navneformen varierer (for eksempel "L01").
local function normName(n)
  n = string.upper(string.gsub(n, "%s", ""))
  return (string.gsub(n, "^L0+(%d)", "L%1"))
end

local swCache
function L.swIndex(name)
  local ok, idx = pcall(getSwitchIndex, name)
  if ok and idx then return idx end
  if not swCache then
    swCache = {}
    if getSwitchName then
      for i = 1, 600 do
        local ok2, n = pcall(getSwitchName, i)
        if ok2 and type(n) == "string" and n ~= "" then
          local k = normName(n)
          if not swCache[k] then swCache[k] = i end
        end
      end
    end
  end
  return swCache[normName(name)]
end

-- Logiske brytere heter "L01".."L64" i EdgeTX 2.12 (sjekket med RM Diagnose), og
-- getSwitchName gir ikke navnet før bryteren er i bruk. i: 0 = L1
function L.lsSwitch(i)
  return L.swIndex(string.format("L%02d", i + 1)) or L.swIndex("L" .. (i + 1))
end
function L.fmSwitch(fm) return L.swIndex("FM" .. fm) end

-- Trimknapp som kilde (T1..T6 = Rud, Ele, Thr, Ail, T5, T6)
local TRIM_NAMES = {
  { "trim-rud", "TrmR", "trim-t1", "T1" }, { "trim-ele", "TrmE", "trim-t2", "T2" },
  { "trim-thr", "TrmT", "trim-t3", "T3" }, { "trim-ail", "TrmA", "trim-t4", "T4" },
  { "trim-t5", "Trm5", "T5" }, { "trim-t6", "Trm6", "T6" },
}
function L.trimIndex(label)   -- "T3" -> 2 (0-basert)
  local n = tonumber(string.match(label or "", "%d"))
  return n and (n - 1) or nil
end
function L.trimSource(label)
  local i = L.trimIndex(label)
  return i and TRIM_NAMES[i + 1] and L.findSource(TRIM_NAMES[i + 1]) or nil
end

------------------------------------------------------------------------
-- Justeringspotten virker relativt. Står den i enden (ved start eller etter
-- «Nullstill pot»), holdes verdien fast til potten er vridd tilbake til midten.
local POT_END, POT_MID = 700, 60

function L.potStart(s, force)
  s.v0 = L.value(s.adj)
  s.hold = force or math.abs(s.v0) > POT_END
end

-- Pot-endring siden start, eller nil mens verdien holdes fast
function L.potDelta(s)
  local p = L.value(s.adj)
  if s.hold then
    if math.abs(p) > POT_MID then return nil end
    s.hold = false
    s.v0 = p
  end
  return p - s.v0
end

function L.potHint(s, x, y)
  if s.hold then
    L.text(x, y, "Vri " .. s.adj.label .. " tilbake til midten for å justere videre.", SMLSIZE, L.C.warn)
  else
    L.text(x, y, "Potten i enden? Trykk Nullstill pot og vri den til midten.", SMLSIZE, L.C.dim)
  end
end

------------------------------------------------------------------------
-- Grov- og finjustering (steg 2, 3, 4 og meny 6). Grov (S1) virker først når den har
-- vært i midten, hver gang et nytt ror tas fram. Fin (S2) er relativ som over.
-- Fast (bestemt 2026-10-26): S1 grovt, S2 fint. Finnes ikke S1, gjør S2 alt.
function L.dualNew()
  local a = { fine = { adj = L.ctrl("s2") } }
  if L.ctrl("s1") and L.ctrl("s1").id then a.coarse = { adj = L.ctrl("s1") } end
  return a
end

-- soft: grovkontrollen holdes bare hvis den står i enden (som finkontrollen uten force)
function L.dualStart(a, force, soft)
  L.potStart(a.fine, force)
  if a.coarse then L.potStart(a.coarse, not soft) end
end

-- Samlet endring i justeringens enhet: span er endringen over halv vandring.
-- nil mens begge holdes fast.
function L.dualDelta(a, fineSpan, coarseSpan)
  local f = L.potDelta(a.fine)
  local c = a.coarse and L.potDelta(a.coarse)
  if not f and not c then return nil end
  return (f or 0) * fineSpan / 1024 + (c or 0) * coarseSpan / 1024
end

-- Ved grensen: regn videre fra der kontrollene står nå, så verdien følger med tilbake
function L.dualRebase(a)
  if not a.fine.hold then a.fine.v0 = L.value(a.fine.adj) end
  if a.coarse and not a.coarse.hold then a.coarse.v0 = L.value(a.coarse.adj) end
end

-- «LS grovt, S2 fint» eller bare «S2»
function L.dualLabel(a)
  if not a.coarse then return a.fine.adj.label end
  return a.coarse.adj.label .. " grovt, " .. a.fine.adj.label .. " fint"
end

-- Tydelig beskjed mens justeringen venter på at kontrollene settes i midten
function L.dualWait(a, x, y)
  local t = {}
  if a.coarse and a.coarse.hold then t[#t + 1] = a.coarse.adj.label end
  if a.fine.hold then t[#t + 1] = a.fine.adj.label end
  if #t == 0 then return false end
  lcd.drawFilledRectangle(x - 4, y - 2, 368, 22, L.C.bg)
  L.text(x, y, "Sett " .. table.concat(t, " og ") .. " i midten for å starte", 0, L.C.warn)
  return true
end

function L.dualHint(a, x, y)
  if a.coarse and a.coarse.hold and a.fine.hold then
    L.text(x, y, "Sett " .. a.coarse.adj.label .. " og " .. a.fine.adj.label ..
      " tilbake til midten for å justere videre.", SMLSIZE, L.C.warn)
  elseif a.coarse and a.coarse.hold then
    L.text(x, y, "Sett " .. a.coarse.adj.label .. " i midten for grovjustering. " ..
      a.fine.adj.label .. " finjusterer.", SMLSIZE, L.C.warn)
  elseif a.fine.hold or not a.coarse then
    L.potHint(a.fine, x, y)
  else
    L.text(x, y, a.coarse.adj.label .. " grovt, " .. a.fine.adj.label ..
      " fint. I enden? Trykk Nullstill pot og sett begge i midten.", SMLSIZE, L.C.dim)
  end
end

------------------------------------------------------------------------
-- Mikser etter navn (kanal 1-basert)

function L.findMix(ch, name)
  for i = 0, model.getMixesCount(ch - 1) - 1 do
    local m = model.getMix(ch - 1, i)
    if m and m.name == name then return i, m end
  end
  return nil
end

-- Endrer felt i en navngitt mix (slett og sett inn på samme plass)
function L.setMix(ch, name, fields)
  local i, m = L.findMix(ch, name)
  if not i then return false end
  for k, v in pairs(fields) do m[k] = v end
  model.deleteMix(ch - 1, i)
  model.insertMix(ch - 1, i, m)
  return true
end

function L.countMixes()
  local n = 0
  for ch = 0, 31 do
    local ok, c = pcall(model.getMixesCount, ch)
    if ok and c then n = n + c end
  end
  return n
end

------------------------------------------------------------------------
-- Filer på SD-kortet (Lua-tabeller som tekst)

-- Sortering i ren Lua. EdgeTX setter verktøyet på pause (yield) midt i koden når
-- et run-kall har brukt over 50 ms, og en pause inne i en sammenligning som
-- table.sort kaller fra C gir «attempt to yield across a C-call boundary»
-- (vises som «Script syntax error»). Bruk derfor aldri table.sort med funksjon.
function L.sort(t, lt)
  for i = 2, #t do
    local v, j = t[i], i - 1
    while j >= 1 and lt(v, t[j]) do t[j + 1] = t[j]; j = j - 1 end
    t[j + 1] = v
  end
  return t
end

local function ser(v)
  local t = type(v)
  if t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    L.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do
      local ks = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
      parts[#parts + 1] = ks .. "=" .. ser(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then
    return string.format("%q", v)
  end
  return tostring(v)
end

function L.save(name, tbl)
  local f = io.open(L.DATA .. name, "w")
  if not f then return false end
  io.write(f, "return " .. ser(tbl) .. "\n")
  io.close(f)
  return true
end

-- loadScript i EdgeTX godtar bare filer som slutter på .lua, derfor .lua også for data.
-- Eldre .txt-filer (v0.1) leses som tekst og lagres på nytt som .lua.
local function readOld(name)
  if not load then return nil end
  local f = io.open(L.DATA .. string.gsub(name, "%.lua$", ".txt"), "r")
  if not f then return nil end
  local s = io.read(f, 8192)
  io.close(f)
  if type(s) ~= "string" or s == "" then return nil end
  local ok, chunk = pcall(load, s)
  if not ok or not chunk then return nil end
  local ok2, t = pcall(chunk)
  if ok2 and type(t) == "table" then
    L.save(name, t)
    return t
  end
  return nil
end

function L.load(name)
  local ok, chunk = pcall(loadScript, L.DATA .. name, "T")
  if ok and chunk then
    local ok2, t = pcall(chunk)
    if ok2 and type(t) == "table" then return t end
  end
  return readOld(name)
end

function L.modelKey()
  local info = model.getInfo()
  local n = (info and info.name) or ""
  n = string.gsub(n, "[^%w]", "_")
  if n == "" then n = "uten_navn" end
  return "m_" .. n .. ".lua"
end

------------------------------------------------------------------------
-- Midlertidige testmikser (REPLACE, sist på kanalen)

-- model.setOutput nullstiller alle felt som ikke er med (memclear i EdgeTX, i strid
-- med dokumentasjonen). Les derfor kanalen, endre bare feltene i f og skriv alt tilbake.
-- idx er 0-basert som i model.setOutput.
function L.setOutput(idx, f)
  local o = model.getOutput(idx) or {}
  for k, v in pairs(f) do o[k] = v end
  model.setOutput(idx, o)
end

-- Gir false hvis mixen ikke kom inn. EdgeTX sier ikke fra når alle 64 mikser er brukt.
function L.tmpAdd(ch, source, weight, offset)
  local idx = ch - 1
  local n = model.getMixesCount(idx)
  -- Foran senter-mixen på testbryteren, så den fortsatt vinner når bryteren er inne
  local pos = n
  for i = 0, n - 1 do
    local m = model.getMix(idx, i)
    if m and m.name == L.SH then pos = i; break end
  end
  pcall(model.insertMix, idx, pos,
    { name = L.TMP, source = source, weight = weight, offset = offset or 0, multiplex = 2 })
  return model.getMixesCount(idx) > n
end

-- Alle mikser i modellen
function L.mixTotal()
  local n = 0
  for ch = 0, 31 do
    local ok, c = pcall(model.getMixesCount, ch)
    if ok and c then n = n + c end
  end
  return n
end

-- Testbryteren (sw = bryterindeks) inne: kanalen i senter. Legges sist, så den vinner.
function L.shAdd(ch, source, sw)
  local idx = ch - 1
  local n = model.getMixesCount(idx)
  pcall(model.insertMix, idx, n,
    { name = L.SH, source = source, weight = 0, multiplex = 2, switch = sw })
  return model.getMixesCount(idx) > n
end

function L.shClear(ch)
  local idx = ch - 1
  for i = model.getMixesCount(idx) - 1, 0, -1 do
    local m = model.getMix(idx, i)
    if m and m.name == L.SH then model.deleteMix(idx, i) end
  end
end

-- Testmiks på aktivt ror først, så holdes rorene i hold i senter hvis det er plass.
-- src er kilden MAX. Gir (aktiv ok, alle holdt).
function L.tmpActive(chs, active, weight, src, hold)
  for _, x in ipairs(chs) do L.tmpClear(x.ch) end
  local ok = L.tmpAdd(active, src, weight, 0)
  local held = true
  for _, x in ipairs(hold or {}) do
    if x.ch ~= active and not L.tmpAdd(x.ch, src, 0, 0) then held = false end
  end
  return ok, held
end

-- Advarsel i linjen under stolpen når mikstaket er nådd, ellers forklaringen
function L.mixWarn(ok, held, x, y, okText)
  if not ok then
    L.text(x, y, "Mikstaket (64) er nådd: roret kan ikke styres!", SMLSIZE, L.C.warn)
  elseif not held then
    L.text(x, y, "Mikstaket (64) nådd: andre ror holdes ikke.", SMLSIZE, L.C.warn)
  else
    L.text(x, y, okText, SMLSIZE, L.C.ok)
  end
end

function L.tmpClear(ch)
  local idx = ch - 1
  for i = model.getMixesCount(idx) - 1, 0, -1 do
    local m = model.getMix(idx, i)
    if m and m.name == L.TMP then model.deleteMix(idx, i) end
  end
end

function L.tmpClearAll()
  local n = 0
  for ch = 1, 32 do
    local ok, cnt = pcall(model.getMixesCount, ch - 1)
    if ok and cnt then
      for i = cnt - 1, 0, -1 do
        local m = model.getMix(ch - 1, i)
        if m and (m.name == L.TMP or m.name == L.SH) then
          model.deleteMix(ch - 1, i)
          n = n + 1
        end
      end
    end
  end
  return n
end

------------------------------------------------------------------------
-- Skjermer: stabel, knapper, rullehjul og berøring

local app = { stack = {} }
L.app = app

function L.push(s)
  s.focus = s.focus or 1
  app.stack[#app.stack + 1] = s
  if s.enter then s:enter() end
end

function L.pop()
  local s = table.remove(app.stack)
  if s and s.leave then s:leave() end
  local top = app.stack[#app.stack]
  if top and top.resume then top:resume() end
end

function L.quit()
  while #app.stack > 0 do
    local s = table.remove(app.stack)
    if s.leave then s:leave() end
  end
end

function L.top()
  return app.stack[#app.stack]
end

function L.toast(text, warn)
  app.msg = text
  app.msgWarn = warn
  app.msgUntil = getTime() + 300
end

-- Bilder (PNG) i /SCRIPTS/RM/IMG/. Lastes én gang. Mangler filen, tegnes ingenting.
local bmps = {}
function L.image(name, x, y)
  local b = bmps[name]
  if b == nil then
    b = (Bitmap and Bitmap.open(L.IMG .. name)) or false
    bmps[name] = b
  end
  if b and lcd.drawBitmap then lcd.drawBitmap(b, x, y) end
end

-- F3X-logoen: hele logoen øverst til høyre (133 x 38), symbolet på menyknappene (49 x 24)
L.LOGO_W, L.ICON_W = 133, 49

function L.header(title, sub)
  lcd.drawFilledRectangle(0, 0, L.W, 50, L.C.head)
  lcd.drawText(15, 7, title, MIDSIZE + L.C.headText)
  L.image("f3x_head.png", L.W - 12 - L.LOGO_W, 6)
  if sub then
    -- mindre skrift hvis teksten ellers når inn i tittelen
    local right = L.W - 26 - L.LOGO_W
    local free = right - 30 - L.textSize(title, MIDSIZE)
    if L.textSize(sub, 0) <= free then lcd.drawText(right, 13, sub, RIGHT + L.C.headText)
    else lcd.drawText(right, 16, sub, SMLSIZE + RIGHT + L.C.headText) end
  end
end

-- font: 0, BOLD, SMLSIZE, MIDSIZE, DBLSIZE (+ RIGHT/CENTER). color: L.C.*
-- NB: BOLD er en egen font i EdgeTX, ikke et tillegg (MIDSIZE + BOLD = DBLSIZE).
function L.text(x, y, t, font, color)
  lcd.drawText(x, y, t, (font or 0) + (color or L.C.text))
end

-- Tekstbredde og -høyde. lcd.sizeText finnes i EdgeTX; ellers et anslag.
local FONT_EST = { [0] = { 10, 24 }, { 10, 24 }, { 7, 16 }, { 8, 20 }, { 15, 34 }, { 20, 44 }, { 39, 80 } }
function L.textSize(t, font)
  if lcd.sizeText then return lcd.sizeText(t, font or 0) end
  local e = FONT_EST[math.floor(((font or 0) % 0x1000) / 0x100)] or FONT_EST[0]
  return #string.gsub(t, "[\128-\191]", "") * e[1], e[2]
end

-- Tegner teksten med den første fonten i fonts som får plass i maxW. Gir bredde og høyde.
function L.fit(x, y, t, maxW, fonts, color)
  local f, w, h
  for _, ff in ipairs(fonts) do
    f = ff
    w, h = L.textSize(t, f)
    if w <= maxW then break end
  end
  L.text(x, y, t, f, color)
  return w, h
end

-- Knapp: opts = { enabled, color, left, right (tekst til høyre), primary (oransje),
--               hidden (usynlig trykkflate, f.eks. et ror på flyfiguren; ikke med i rullehjulet),
--               icon (F3X-symbolet foran teksten, for menyknapper) }
function L.btn(list, x, y, w, h, text, fn, opts)
  opts = opts or {}
  list[#list + 1] = { x = x, y = y, w = w, h = h, text = text, fn = fn,
    enabled = opts.enabled ~= false and fn ~= nil, color = opts.color,
    left = opts.left, right = opts.right, primary = opts.primary, hidden = opts.hidden, icon = opts.icon,
    warn = opts.warn }
end

-- Knapperad nederst, like brede knapper. Siste knapp er hovedknappen (oransje),
-- med mindre den har { primary = false }.
function L.btnRow(list, items)
  local n = #items
  local gap = 8
  local w = math.floor((L.W - 20 - gap * (n - 1)) / n)
  lcd.drawFilledRectangle(0, 410, L.W, 70, L.C.panel)
  for i, it in ipairs(items) do
    local o = it[3] or {}
    if i == n and n > 1 and o.primary == nil then
      local c = {}
      for k, v in pairs(o) do c[k] = v end
      c.primary = true
      o = c
    end
    L.btn(list, 10 + (i - 1) * (w + gap), 418, w, 54, it[1], it[2], o)
  end
end

local function drawBtn(b, focused)
  if b.hidden then return end
  local on = b.enabled
  local bg = b.color or (b.primary and L.C.primary) or L.C.btn
  if not on then bg = L.C.off end
  if focused and on and not b.primary and not b.color then bg = L.C.focus end
  lcd.drawFilledRectangle(b.x, b.y, b.w, b.h, bg)
  local fr = (focused and on) and (b.primary and L.C.headText or L.C.act) or (on and L.C.edge or L.C.btn)
  lcd.drawRectangle(b.x, b.y, b.w, b.h, fr)
  if focused and on then lcd.drawRectangle(b.x + 1, b.y + 1, b.w - 2, b.h - 2, fr) end
  local fc = on and (b.primary and L.C.headText or L.C.text) or L.C.dim
  local ty = b.y + math.floor(b.h / 2) - 11
  local tx = b.x + 10
  if b.icon then
    L.image("f3x_btn.png", tx, b.y + math.floor((b.h - 24) / 2))
    tx = tx + L.ICON_W + 10
  end
  if b.left then
    lcd.drawText(tx, ty, b.text, fc)
  else
    lcd.drawText(b.x + math.floor(b.w / 2), ty, b.text, CENTER + fc)
  end
  if b.right then lcd.drawText(b.x + b.w - 10, ty, b.right, RIGHT + (b.warn and L.C.warn or fc)) end
end

local function nextEnabled(list, i, dir)
  for _ = 1, #list do
    i = (i - 1 + dir) % #list + 1
    if list[i].enabled and not list[i].hidden then return i end
  end
  return i
end

-- Bygger knappelisten for skjermen på toppen (brukes også av testoppsettet på PC)
function L.buttons(s)
  local list = {}
  s:draw(list)
  return list
end

-- Trykk: knappen som er truffet, ellers den nærmeste innenfor L.TOUCH_PAD (800 x 480-
-- koordinater), så et trykk litt ved siden av en knapp også virker. Ved lik avstand vinner
-- den første i listen. Et trykk rett på en deaktivert (grå) knapp gjør ingenting.
L.TOUCH_PAD = 30
function L.touchHit(list, x, y)
  local best, bestD
  for i, b in ipairs(list) do
    local dx = math.max(b.x - x, 0, x - (b.x + b.w))
    local dy = math.max(b.y - y, 0, y - (b.y + b.h))
    local d = dx * dx + dy * dy
    if b.enabled then
      if d <= L.TOUCH_PAD * L.TOUCH_PAD and (not bestD or d < bestD) then best, bestD = i, d end
    elseif d == 0 and not b.hidden then
      return nil
    end
  end
  return best
end

function L.run(event, touch)
  if touch and lcd.toVirtual then touch = lcd.toVirtual(touch) end
  local s = L.top()
  if not s then return 1 end
  if s.tick then s:tick() end
  s = L.top()
  if not s then return 1 end

  lcd.clear(L.C.bg)
  local list = L.buttons(s)
  if #list > 0 then
    if s.focus > #list or not list[s.focus].enabled or list[s.focus].hidden then
      s.focus = nextEnabled(list, s.focus, 1)
    end
    for i, b in ipairs(list) do drawBtn(b, i == s.focus) end
  end

  if app.msg then
    if getTime() < app.msgUntil then
      lcd.drawFilledRectangle(0, 372, L.W, 40, app.msgWarn and L.C.warn or L.C.ok)
      lcd.drawText(L.W / 2, 380, app.msg, CENTER + L.C.headText)
    else
      app.msg = nil
    end
  end

  if event ~= 0 and s.onEvent and s:onEvent(event) then
    -- tatt av skjermen (f.eks. PAGE> / PAGE<)
  elseif event == EVT_VIRTUAL_EXIT then
    if s.back then s:back() else L.pop() end
  elseif #list > 0 then
    if event == EVT_VIRTUAL_NEXT then
      s.focus = nextEnabled(list, s.focus, 1)
    elseif event == EVT_VIRTUAL_PREV then
      s.focus = nextEnabled(list, s.focus, -1)
    elseif event == EVT_VIRTUAL_ENTER then
      local b = list[s.focus]
      if b and b.enabled then b.fn() end
    elseif event == EVT_TOUCH_TAP and touch then
      local i = L.touchHit(list, touch.x, touch.y)
      if i then
        if not list[i].hidden then s.focus = i end
        list[i].fn()
      end
    end
  end

  if #app.stack == 0 then return 1 end
  return 0
end

return L
