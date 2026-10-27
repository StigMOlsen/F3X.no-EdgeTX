-- RM Oppsettveiviser. Startes fra F3X-verktøyet (/SCRIPTS/TOOLS/F3X.lua). Selve koden ligger i /SCRIPTS/RM/.
local toolName = "TNS|RM Setup wizard|TNE"

local L
local err

local function load(path)
  local chunk, e = loadScript(path)
  if not chunk then err = "Missing or error in " .. path .. ": " .. tostring(e) end
  return chunk
end

local function init()
  local libC, stdC, pilotC, wizC = load("/SCRIPTS/RM/lib.lua"), load("/SCRIPTS/RM/std.lua"),
    load("/SCRIPTS/RM/pilot.lua"), load("/SCRIPTS/RM/wizard.lua")
  local setupC, adjC = load("/SCRIPTS/RM/setup.lua"), load("/SCRIPTS/RM/adjust.lua")
  local gfxC = load("/SCRIPTS/RM/gfx.lua")
  if err then return end
  L = libC()
  local STD = stdC()
  local P = pilotC()(L, STD)
  local W = wizC()(L, STD, P)
  W.G = gfxC()(L)
  W.S = setupC()(L, STD, W)
  W.A = adjC()(L, STD, W, W.S)
  L.initControls()
  local n = L.tmpClearAll()
  L.push(W.startScreen())
  if n > 0 then L.toast(n .. " old test mixes removed") end
end

local function run(event, touchState)
  if err then
    lcd.clear()
    lcd.drawText(10, 10, "RM Setup wizard", MIDSIZE)
    lcd.drawText(10, 60, err, SMLSIZE)
    if event == EVT_VIRTUAL_EXIT then return 1 end
    return 0
  end
  local r = L.run(event, touchState)
  if r == 1 then L.tmpClearAll() end
  return r
end

return { init = init, run = run }
