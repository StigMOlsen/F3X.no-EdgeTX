-- RM Flightscreen, startes fra F3X-verktøyet: tider, link og flylogg under flyging (flight.lua).
local toolName = "TNS|RM Flightscreen|TNE"

local L
local err

local function load(path)
  local chunk, e = loadScript(path)
  if not chunk then err = "Mangler eller feil i " .. path .. ": " .. tostring(e) end
  return chunk
end

local function init()
  local libC, stdC, flightC = load("/SCRIPTS/RM/lib.lua"), load("/SCRIPTS/RM/std.lua"),
    load("/SCRIPTS/RM/flight.lua")
  if err then return end
  L = libC()
  local STD = stdC()
  local F = flightC()(L, STD)
  L.initControls()
  L.push(F.screen())
end

local function run(event, touchState)
  if err then
    lcd.clear()
    lcd.drawText(10, 10, "RM Flightscreen", MIDSIZE)
    lcd.drawText(10, 60, err, SMLSIZE)
    if event == EVT_VIRTUAL_EXIT then return 1 end
    return 0
  end
  return L.run(event, touchState)
end

return { init = init, run = run }
