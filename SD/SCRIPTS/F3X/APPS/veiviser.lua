-- RM Oppsettveiviser. Startes fra F3X-verktøyet (/SCRIPTS/TOOLS/F3X.lua). Selve koden ligger i /SCRIPTS/F3X/.
local toolName = "TNS|RM Oppsettveiviser|TNE"

local L
local err

local function load(path)
  local chunk, e = loadScript(path)
  if not chunk then err = "Mangler eller feil i " .. path .. ": " .. tostring(e) end
  return chunk
end

local function init()
  local libC, stdC, pilotC, wizC = load("/SCRIPTS/F3X/lib.lua"), load("/SCRIPTS/F3X/std.lua"),
    load("/SCRIPTS/F3X/pilot.lua"), load("/SCRIPTS/F3X/wizard.lua")
  local setupC, adjC = load("/SCRIPTS/F3X/setup.lua"), load("/SCRIPTS/F3X/adjust.lua")
  local gfxC = load("/SCRIPTS/F3X/gfx.lua")
  local trC = loadScript("/SCRIPTS/F3X/trainer.lua")   -- valgfri: uten Trener-appen på SD-kortet
  if err then return end
  L = libC()
  local STD = stdC()
  local P = pilotC()(L, STD)
  local W = wizC()(L, STD, P)
  W.G = gfxC()(L)
  W.S = setupC()(L, STD, W)
  W.A = adjC()(L, STD, W, W.S)
  if trC then W.T = trC()(L, STD, W, W.S) end
  L.initControls()
  local n = L.tmpClearAll()
  L.push(W.startScreen())
  if n > 0 then L.toast(n .. " gamle testmikser fjernet") end
end

local function run(event, touchState)
  if err then
    lcd.clear()
    lcd.drawText(10, 10, "RM Oppsettveiviser", MIDSIZE)
    lcd.drawText(10, 60, err, SMLSIZE)
    if event == EVT_VIRTUAL_EXIT then return 1 end
    return 0
  end
  local r = L.run(event, touchState)
  if r == 1 then L.tmpClearAll() end
  return r
end

return { init = init, run = run }
