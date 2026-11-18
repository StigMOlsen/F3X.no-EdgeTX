-- F3X (EdgeTX Lua Tool): én knapp i Tools-menyen som åpner alle RM-verktøyene.
-- Verktøyene ligger i /SCRIPTS/F3X/APPS/ og kjøres herfra; når et verktøy avsluttes,
-- kommer man tilbake hit. Tools-siden i EdgeTX 2.12 viser bare tekst, så logoen
-- vises i overskriften og på menyknappene her.
local toolName = "TNS|F3X.no|TNE"

-- 4. felt: sperret etter motor (flysperren, se std.lua ls.flyLock)
local APPS = {
  { "Flightscreen", "Tider, link og flylogg", "/SCRIPTS/F3X/APPS/flyskjerm.lua" },
  { "Oppsettveiviser", "Nytt fly eller endre oppsett", "/SCRIPTS/F3X/APPS/veiviser.lua" },
  { "Pilotoppsett", "Brytere og kontroller", "/SCRIPTS/F3X/APPS/pilot.lua", true },
  { "Diagnose", "Test av Lua-API (tom testmodell)", "/SCRIPTS/F3X/APPS/diag.lua" },
}

local L, err, active, LOCK_LS, OLD_RM

-- Til og med v2026-11-18 lå programmet i /SCRIPTS/RM. Data (pilotprofil og fremdrift per
-- modell) kopieres derfra til /SCRIPTS/F3X/DATA første gang, uten å overskrive noe. Etterpå
-- skal brukeren slette /SCRIPTS/RM på SD-kortet (står i bruksanvisningen og i menyen).
local OLD = "/SCRIPTS/RM/"
local NEW_DATA = "/SCRIPTS/F3X/DATA/"

local function exists(path)
  local f = io.open(path, "r")
  if f then io.close(f); return true end
  return false
end

local function copyFile(src, dst)
  if exists(dst) then return false end
  local f = io.open(src, "r")
  if not f then return false end
  local parts = {}
  for _ = 1, 64 do   -- datafilene er små (under 64 kB)
    local c = io.read(f, 1024)
    if not c or c == "" then break end
    parts[#parts + 1] = c
  end
  io.close(f)
  local o = io.open(dst, "w")
  if not o then return false end
  io.write(o, table.concat(parts))
  io.close(o)
  return true
end

local function migrateRM()
  local old = exists(OLD .. "lib.lua") or exists(OLD .. "lib.luac") or exists(OLD .. "DATA/pilot.lua")
  if not old then return false end
  local names = {}
  local ok = dir and pcall(function()
    for n in dir(OLD .. "DATA") do
      if string.sub(n, -4) == ".lua" or string.sub(n, -4) == ".txt" then names[#names + 1] = n end
    end
  end)
  if not ok or #names == 0 then
    -- Uten dir(): de faste filene og fremdriften for modellen som er valgt nå
    names = { "pilot.lua", "fly.lua", "diag.lua" }
    local info = model.getInfo()
    local file = info and info.filename and string.gsub(info.filename, "%.yml$", "")
    if file then names[#names + 1] = "f_" .. file .. ".lua" end
    if info and info.name then names[#names + 1] = "m_" .. info.name .. ".lua" end
  end
  local n = 0
  for _, name in ipairs(names) do
    if copyFile(OLD .. "DATA/" .. name, NEW_DATA .. name) then n = n + 1 end
  end
  return true, n
end

local function start(path)
  local chunk = loadScript(path)
  if not chunk then L.toast("Mangler " .. path, true); return end
  local t = chunk()
  if t.init then t.init() end
  active = t
end

local function menu()
  local s = {}
  function s:draw(list)
    L.header("F3X.no", OLD_RM and "Slett mappen SCRIPTS/RM på SD-kortet" or "RadioMaster-verktøy")
    local step = math.min(84, math.floor(350 / #APPS))   -- plass over knapperaden nederst
    local lock = L.flyLocked(LOCK_LS)
    for i, a in ipairs(APPS) do
      L.btn(list, 20, 62 + (i - 1) * step, 760, step - 10, a[1], not (lock and a[4]) and function() start(a[3]) end or nil,
        { left = true, icon = true, right = (lock and a[4]) and "Sperret etter motor" or a[2] })
    end
    L.btnRow(list, { { "Avslutt", function() L.pop() end } })
  end
  return s
end

-- EdgeTX 2.10 og eldre har Lua 5.2, og getSwitchIndex finner bare brytere som er i bruk
-- (logiske brytere og flymoduser blir ikke funnet). Verktøyet krever 2.11 eller nyere.
local function oldEdgeTX()
  local ver = getVersion and getVersion() or ""
  local maj, min = string.match(ver, "^(%d+)%.(%d+)")
  maj, min = tonumber(maj), tonumber(min)
  if not maj then return nil end
  if maj < 2 or (maj == 2 and min < 11) then return ver end
end

local function init()
  local old = oldEdgeTX()
  if old then
    err = { "Radioen har EdgeTX " .. old .. ".", "F3X.no krever EdgeTX 2.11 eller nyere (anbefalt 2.12).",
            "Oppdater radioen med EdgeTX Buddy (buddy.edgetx.org)." }
    return
  end
  local chunk, e = loadScript("/SCRIPTS/F3X/lib.lua")
  if not chunk then err = "Mangler eller feil i /SCRIPTS/F3X/lib.lua: " .. tostring(e); return end
  L = chunk()
  local sc = loadScript("/SCRIPTS/F3X/std.lua")
  LOCK_LS = sc and sc().ls.flyLock
  L.push(menu())
  local n
  OLD_RM, n = migrateRM()
  if OLD_RM then
    L.toast((n and n > 0) and ("Data kopiert fra SCRIPTS/RM (" .. n .. " filer). Slett SCRIPTS/RM.")
      or "Gammel mappe SCRIPTS/RM: slett den på SD-kortet.", true)
  end
end

local function run(event, touchState)
  if err then
    lcd.clear()
    lcd.drawText(10, 10, "F3X.no", MIDSIZE)
    local lines = type(err) == "table" and err or { err }
    for i, t in ipairs(lines) do lcd.drawText(10, 40 + i * 24, t, SMLSIZE) end
    if event == EVT_VIRTUAL_EXIT then return 1 end
    return 0
  end
  if active then
    if active.run(event, touchState) ~= 0 then
      active = nil
      collectgarbage()
    end
    return 0
  end
  return L.run(event, touchState)
end

return { init = init, run = run }
