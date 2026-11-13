-- F3X (EdgeTX Lua Tool): én knapp i Tools-menyen som åpner alle RM-verktøyene.
-- Verktøyene ligger i /SCRIPTS/RM/APPS/ og kjøres herfra; når et verktøy avsluttes,
-- kommer man tilbake hit. Tools-siden i EdgeTX 2.12 viser bare tekst, så logoen
-- vises i overskriften og på menyknappene her.
local toolName = "TNS|F3X.no|TNE"

-- 4. felt: sperret etter motor (flysperren, se std.lua ls.flyLock)
local APPS = {
  { "Flightscreen", "Timers, link and flight log", "/SCRIPTS/RM/APPS/flyskjerm.lua" },
  { "Setup wizard", "New model or change setup", "/SCRIPTS/RM/APPS/veiviser.lua" },
  { "Pilot setup", "Switches and controls", "/SCRIPTS/RM/APPS/pilot.lua", true },
  { "Diagnostics", "Lua API test (empty test model)", "/SCRIPTS/RM/APPS/diag.lua" },
}

local L, err, active, LOCK_LS

local function start(path)
  local chunk = loadScript(path)
  if not chunk then L.toast("Missing " .. path, true); return end
  local t = chunk()
  if t.init then t.init() end
  active = t
end

local function menu()
  local s = {}
  function s:draw(list)
    L.header("F3X.no", "RadioMaster tools")
    local step = math.min(84, math.floor(350 / #APPS))   -- plass over knapperaden nederst
    local lock = L.flyLocked(LOCK_LS)
    for i, a in ipairs(APPS) do
      L.btn(list, 20, 62 + (i - 1) * step, 760, step - 10, a[1], not (lock and a[4]) and function() start(a[3]) end or nil,
        { left = true, icon = true, right = (lock and a[4]) and "Locked after motor" or a[2] })
    end
    L.btnRow(list, { { "Exit", function() L.pop() end } })
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
    err = { "This radio has EdgeTX " .. old .. ".", "F3X.no needs EdgeTX 2.11 or newer (2.12 recommended).",
            "Update the radio with EdgeTX Buddy (buddy.edgetx.org)." }
    return
  end
  local chunk, e = loadScript("/SCRIPTS/RM/lib.lua")
  if not chunk then err = "Missing or error in /SCRIPTS/RM/lib.lua: " .. tostring(e); return end
  L = chunk()
  local sc = loadScript("/SCRIPTS/RM/std.lua")
  LOCK_LS = sc and sc().ls.flyLock
  L.push(menu())
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
