-- RM Pilotoppsett, startes fra F3X-verktøyet: steg P alene. Profilen gjelder alle modellene.
local toolName = "TNS|RM Pilot setup|TNE"

local L
local err

local function load(path)
  local chunk, e = loadScript(path)
  if not chunk then err = "Missing or error in " .. path .. ": " .. tostring(e) end
  return chunk
end

local function init()
  local libC, stdC, pilotC = load("/SCRIPTS/RM/lib.lua"), load("/SCRIPTS/RM/std.lua"),
    load("/SCRIPTS/RM/pilot.lua")
  if err then return end
  L = libC()
  local STD = stdC()
  local P = pilotC()(L, STD)
  L.initControls()
  L.push(P.startScreen(function() L.quit() end))
end

local function run(event, touchState)
  if err then
    lcd.clear()
    lcd.drawText(10, 10, "RM Pilot setup", MIDSIZE)
    lcd.drawText(10, 60, err, SMLSIZE)
    if event == EVT_VIRTUAL_EXIT then return 1 end
    return 0
  end
  return L.run(event, touchState)
end

return { init = init, run = run }
