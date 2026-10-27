local toolName = "TNS|RM Diagnose|TNE"
-- RM Diagnose, startes fra F3X-verktøyet: prøver ut de delene av Lua-API-et som veiviseren
-- bygger på, og skriver svarene til /SCRIPTS/RM/DATA/diag.lua.
-- Kjør i en TOM testmodell. Bruker CH32, kurve 32, L64 og spesialfunksjon 64, og rydder etter seg.

local R = { tests = {} }
local CH, CURVE, LSI, SFI = 31, 31, 63, 63
local queue, qi, waitUntil, done = {}, 1, 0, false
local shown = {}

local function fid(n)
  local ok, i = pcall(getFieldInfo, n)
  return ok and i and i.id or nil
end

local function ser(v, d)
  d = d or 0
  local t = type(v)
  if t == "table" and d < 4 then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    -- ikke table.sort med funksjon: EdgeTX kan yielde inne i den (C-grense)
    for i = 2, #keys do
      local v, j = keys[i], i - 1
      while j >= 1 and tostring(v) < tostring(keys[j]) do keys[j + 1] = keys[j]; j = j - 1 end
      keys[j + 1] = v
    end
    local parts = {}
    for _, k in ipairs(keys) do
      local ks = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
      parts[#parts + 1] = ks .. "=" .. ser(v[k], d + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then return string.format("%q", v)
  elseif t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
  return string.format("%q", tostring(v))
end

local function note(k, v)
  R.tests[k] = v
  shown[#shown + 1] = k .. ": " .. tostring(v)
end

local function clearCh() while model.getMixesCount(CH) > 0 do model.deleteMix(CH, 0) end end
local function out() return getValue(fid("ch32") or fid("CH32")) end
local MAX

-- Hvert trinn: sett opp, vent 0,4 s, mål
local function test(name, setup, measure)
  queue[#queue + 1] = { name = name, setup = setup, measure = measure or function() note(name, out()) end }
end

local function mix(m)
  clearCh()
  local ok, e = pcall(model.insertMix, CH, 0, m)
  if not ok then note("insertMix-feil", e) end
end

local function collect()
  local v, radio = getVersion()
  R.version, R.radio = v, radio
  local consts = {}
  for _, n in ipairs({ "LS_FUNC_NONE", "LS_FUNC_VPOS", "LS_FUNC_VNEG", "LS_FUNC_AND", "LS_FUNC_OR",
    "LS_FUNC_STICKY", "LS_FUNC_EDGE", "FUNC_OVERRIDE_CHANNEL", "FUNC_PLAY_TRACK", "FUNC_VOLUME",
    "FUNC_VARIO", "FUNC_LOGS", "FUNC_ADJUST_GVAR", "CHAR_UP", "CHAR_DOWN" }) do consts[n] = _G[n] end
  R.consts = consts
  local f = {}
  for _, n in ipairs({ "max", "MAX", "thr", "Thr", "ail", "ele", "rud", "sa", "SA", "sd", "sh", "s1", "s2",
    "P1", "P2", "ls", "rs", "sl1", "sl2", "LS", "RS", "trim-rud", "trim-ele", "trim-thr", "trim-ail", "TrmT",
    "T3", "gv1", "GV1", "ch1", "ch7", "ch32", "CH32", "RQly", "RxBt", "1RSS",
    "sw1", "SW1", "sw6", "SW6" }) do f[n] = fid(n) or false end
  R.keys = { pageNext = EVT_VIRTUAL_NEXT_PAGE or false, pagePrev = EVT_VIRTUAL_PREV_PAGE or false,
    pgdn = EVT_PAGEDN_FIRST or false, pgup = EVT_PAGEUP_FIRST or false }
  R.fields = f
  local sw = {}
  if getSwitchName then
    for i = -5, 600 do
      local ok, n = pcall(getSwitchName, i)
      if ok and n and n ~= "" then sw[i] = n end
    end
  end
  R.switchNames = sw
  local si = {}
  for _, n in ipairs({ "SD" .. (CHAR_DOWN or ""), "SD\226\134\147", "SD-", "SDd", "SD2", "L1", "L01", "FM0",
    "FM1", "ON", "SA\226\134\145" }) do
    local ok, idx = pcall(getSwitchIndex, n)
    si[n] = ok and idx or false
  end
  R.switchIndex = si
  R.api = { setFlightMode = model.setFlightMode ~= nil, getFlightMode = model.getFlightMode ~= nil,
    setCurve = model.setCurve ~= nil, setLogicalSwitch = model.setLogicalSwitch ~= nil,
    setCustomFunction = model.setCustomFunction ~= nil, setTimer = model.setTimer ~= nil,
    getSwitchValue = getSwitchValue ~= nil, setGlobalVariable = model.setGlobalVariable ~= nil }
  local ok, fm = pcall(getFlightMode)
  R.currentFM = ok and fm or false
  if model.getFlightMode then R.fm0 = model.getFlightMode(0); R.fm1 = model.getFlightMode(1) end
  if model.getTimer then R.timer1 = model.getTimer(0) end
  if model.getLogicalSwitch then R.ls1 = model.getLogicalSwitch(0) end
  if model.getCustomFunction then R.sf1 = model.getCustomFunction(0) end
  if model.getCurve then R.curve1 = model.getCurve(0) end
  if model.getMix and model.getMixesCount(0) > 0 then R.mixCh1 = model.getMix(0, 0) end
end

local function init()
  MAX = fid("max") or fid("MAX")
  collect()
  local fm = R.currentFM or 0

  test("max_w50", function() mix({ name = "RMdg", source = MAX, weight = 50 }) end)
  test("fm_bit_current", function() mix({ name = "RMdg", source = MAX, weight = 50, flightModes = 2 ^ fm }) end)
  test("fm_bit_other", function() mix({ name = "RMdg", source = MAX, weight = 50, flightModes = 2 ^ ((fm + 1) % 9) }) end)
  test("curve_std_ret", function()
    local ok, r = pcall(model.setCurve, CURVE, { name = "DG", type = 0, y = { -100, 0, 50 }, smooth = 0 })
    note("curve_std_ret", ok and tostring(r) or ("feil: " .. tostring(r)))
  end, function() end)
  test("curve_val32_1based", function() mix({ name = "RMdg", source = MAX, weight = 100, curveType = 3, curveValue = CURVE + 1 }) end)
  test("curve_val31_0based", function() mix({ name = "RMdg", source = MAX, weight = 100, curveType = 3, curveValue = CURVE }) end)
  test("curve_custom_ret", function()
    local ok, r = pcall(model.setCurve, CURVE, { name = "DG", type = 1, x = { -100, 50, 100 }, y = { 0, 20, 40 }, smooth = 0 })
    note("curve_custom_ret", ok and tostring(r) or ("feil: " .. tostring(r)))
  end, function() if model.getCurve then R.curveCustom = model.getCurve(CURVE) end end)
  test("curve_custom_at_max", function() mix({ name = "RMdg", source = MAX, weight = 100, curveType = 3, curveValue = CURVE + 1 }) end)
  test("func1_xpos", function() mix({ name = "RMdg", source = MAX, weight = 100, curveType = 2, curveValue = 1 }) end)
  test("func2_xneg", function() mix({ name = "RMdg", source = MAX, weight = 100, curveType = 2, curveValue = 2 }) end)
  test("multiply_100x50", function()
    mix({ name = "RMdg", source = MAX, weight = 100 })
    model.insertMix(CH, 1, { name = "RMdg2", source = MAX, weight = 50, multiplex = 1 })
  end)
  -- Kurve x(-100,50,100) y(0,0,100), MAX med vekt 50: 512 = kurve før vekt, 0 = vekt før kurve
  test("curve_before_weight_512", function()
    pcall(model.setCurve, CURVE, { name = "DG", type = 1, x = { -100, 50, 100 }, y = { 0, 0, 100 }, smooth = 0 })
    mix({ name = "RMdg", source = MAX, weight = 50, curveType = 3, curveValue = CURVE + 1 })
  end)
  test("gv_source_50", function()
    if model.setGlobalVariable then model.setGlobalVariable(0, fm, 50) end
    local gv = fid("gv1") or fid("GV1")
    if gv then mix({ name = "RMdg", source = gv, weight = 100 }) else clearCh() end
  end)
  test("roundtrip", function()
    mix({ name = "RMdg", source = MAX, weight = 33, offset = 5, speedUp = 15, speedDown = 5, carryTrim = false,
      flightModes = 6, curveType = 2, curveValue = 1, multiplex = 2 })
  end, function() R.mixRoundtrip = model.getMix(CH, 0) end)
  -- a>x med MAX (100 %): x = 101 gir av hvis x er prosent, på hvis x er raaverdi (-1024..1024)
  local function lsTest(name, v2)
    test(name, function()
      if model.setLogicalSwitch then
        model.setLogicalSwitch(LSI, { func = LS_FUNC_VPOS, v1 = MAX, v2 = v2, v3 = 0, ["and"] = 0, delay = 0, duration = 0 })
      end
    end, function()
      if model.getLogicalSwitch then R.lsRoundtrip = model.getLogicalSwitch(LSI) end
      local ok, idx = pcall(getSwitchIndex, "L64")
      R.ls64Index = ok and idx or false
      if getSwitchValue and R.ls64Index then note(name, tostring(getSwitchValue(R.ls64Index))) end
    end)
  end
  lsTest("ls_max_gt_50", 50)
  lsTest("ls_max_gt_101_percent_if_false", 101)
  test("sf_roundtrip", function()
    if model.setCustomFunction then
      model.setCustomFunction(SFI, { switch = 0, func = FUNC_PLAY_TRACK, name = "normal", active = 0, repetition = 0 })
    end
  end, function() if model.getCustomFunction then R.sfRoundtrip = model.getCustomFunction(SFI) end end)
  test("fm_trims_roundtrip", function()
    if model.setFlightMode and model.getFlightMode then
      R.fm8Before = model.getFlightMode(8)
      model.setFlightMode(8, { trimsModes = { [2] = 16, [3] = 16 } })
    end
  end, function()
    if model.getFlightMode then
      R.fm8After = model.getFlightMode(8)
      if R.fm8Before then model.setFlightMode(8, { trimsModes = R.fm8Before.trimsModes }) end
    end
  end)
  test("trim_thr_now", function() clearCh() end, function() note("trim_thr_now", getValue(fid("trim-thr") or 0)) end)
end

local function cleanup()
  clearCh()
  pcall(model.setCurve, CURVE, { name = "", type = 0, y = { -100, 0, 100 }, smooth = 0 })
  if model.setLogicalSwitch then
    pcall(model.setLogicalSwitch, LSI, { func = LS_FUNC_NONE or 0, v1 = 0, v2 = 0, v3 = 0, ["and"] = 0, delay = 0, duration = 0 })
  end
  if model.setCustomFunction then
    pcall(model.setCustomFunction, SFI, { switch = 0, func = 0, value = 0, mode = 0, param = 0, active = 0 })
  end
  if model.setGlobalVariable then pcall(model.setGlobalVariable, 0, R.currentFM or 0, 0) end
  local f = io.open("/SCRIPTS/RM/DATA/diag.lua", "w")
  if f then
    io.write(f, "return " .. ser(R) .. "\n")
    io.close(f)
    shown[#shown + 1] = "Skrevet: /SCRIPTS/RM/DATA/diag.lua"
  else
    shown[#shown + 1] = "! Kunne ikke skrive diag.lua (finnes DATA-mappen?)"
  end
end

local function run(event)
  if not done then
    local now = getTime()
    local q = queue[qi]
    if not q then
      cleanup()
      done = true
    elseif not q.started then
      q.started = true
      local ok, e = pcall(q.setup)
      if not ok then note(q.name, "feil: " .. tostring(e)) end
      waitUntil = now + 40
    elseif now >= waitUntil then
      local ok, e = pcall(q.measure)
      if not ok then note(q.name, "feil: " .. tostring(e)) end
      qi = qi + 1
    end
  end
  lcd.clear()
  lcd.drawText(10, 8, "RM Diagnose " .. (done and "- ferdig" or ("- test " .. qi .. " / " .. #queue)), MIDSIZE)
  -- Linjer etter skjermhøyden (800 x 480 på MK3, 480 x 272 på MK2)
  local H = LCD_H or 480
  local rowH = H >= 480 and 26 or 16
  local top = H >= 480 and 44 or 30
  local first = math.max(1, #shown - math.floor((H - top - 30) / rowH) + 1)
  for i = first, #shown do
    lcd.drawText(10, top + (i - first) * rowH, shown[i], SMLSIZE)
  end
  if done then lcd.drawText(10, H - 25, "Ferdig. Trykk RTN.", SMLSIZE) end
  if event == EVT_VIRTUAL_EXIT then
    if not done then cleanup() end
    return 1
  end
  return 0
end

return { init = init, run = run }
