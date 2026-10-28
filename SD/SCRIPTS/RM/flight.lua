-- Flyskjerm (knappen «Flightscreen» i F3X.no-menyen): flytid, motortid, nedtelling etter
-- motorkutt og link-kvalitet, med stemme og en enkel flylogg på SD-kortet.
-- Tidene kommer fra timerne veiviseren skriver (Timer 1 «Flytid» starter ved første motor på,
-- Timer 2 «Motor» går mens motoren går), så de teller videre selv om skjermen lukkes.
-- Stemmen og loggen kommer bare mens skjermen er åpen.

return function(L, STD)
  local F = {}
  local V = STD.values
  local lcd = L.lcd
  local floor, max = math.floor, math.max

  -- Utrop på flytiden (r = sekunder igjen): hvert minutt, hvert 10. sekund fra 1 minutt
  -- og hvert sekund fra 25. Etter 0 teller flytiden videre uten utrop.
  function F.flightCall(r, total)
    if r >= total or r < 0 then return nil end
    if r >= 60 and r % 60 == 0 then return "dur", r end
    if r == 50 or r == 40 or r == 30 then return "dur", r end
    if r <= 25 then return "num", r end
    return nil
  end

  -- Utrop på motortiden og etter motorkutt: hvert 5. sekund, hvert sekund de 7 siste. Stopper på 0.
  function F.motorCall(r, total)
    if r >= total or r <= 0 then return nil end
    if r <= 7 or r % 5 == 0 then return "num", r end
    return nil
  end

  -- Trudelutt før «2 minutter» igjen av flytiden: C-E-G-C opp
  local JINGLE = { 523, 659, 784, 1047 }
  local function jingle()
    if not playTone then return end
    for i, f in ipairs(JINGLE) do playTone(f, i == #JINGLE and 250 or 120, 30) end
  end

  local function say(kind, v)
    if kind == "dur" and playDuration then playDuration(v, 0)
    elseif playNumber then playNumber(v, 0) end
  end

  -- m:ss (negativ tid vises med +, flytiden teller videre etter 0)
  function F.clock(s)
    local sign = s < 0 and "+" or ""
    s = math.abs(s)
    return string.format("%s%d:%02d", sign, floor(s / 60), s % 60)
  end

  ----------------------------------------------------------------------
  -- Innstillinger (felles for alle modellene, som pilotoppsettet)

  local CFG = "fly.lua"
  local function loadCfg()
    local c = L.load(CFG) or {}
    c.flightMin = c.flightMin or V.flightMin
    c.motorSec = c.motorSec or V.motorSec
    return c
  end

  local function nextIn(list, v)
    for i, x in ipairs(list) do
      if x == v then return list[i % #list + 1] end
    end
    return list[1]
  end

  ----------------------------------------------------------------------
  -- Kilder

  local function field(n)
    local ok, i = pcall(getFieldInfo, n)
    return ok and i and i.id or nil
  end

  local function read(id) if id then return getValue(id) or 0 end end

  local function timerValue(i)
    local ok, t = pcall(model.getTimer, i)
    if ok and t and t.mode and t.mode ~= 0 then return t.value or 0 end
    return nil
  end

  ----------------------------------------------------------------------
  -- Flylogg: én tekstfil per modell og dag i /LOGS/, en linje per hendelse

  local function logName()
    local d = getDateTime and getDateTime() or {}
    local info = model.getInfo()
    local n = string.gsub((info and info.name) or "", "[^%w]", "_")
    if n == "" then n = "modell" end
    return string.format("/LOGS/F3X_%s_%04d-%02d-%02d.txt", n, d.year or 0, d.mon or 0, d.day or 0)
  end

  -- Timerne skal ikke si tiden selv (minuttpip og nedtelling), ellers sies flytiden dobbelt:
  -- EdgeTX teller opp og flyskjermen ned. Modeller skrevet før planVersion 4 har minuttpip på.
  -- Hele timeren leses og skrives tilbake, så de andre feltene beholdes.
  function F.silenceTimers()
    for i = 0, 1 do
      local ok, t = pcall(model.getTimer, i)
      if ok and t and t.mode and t.mode ~= 0 and (t.minuteBeep or (t.countdownBeep or 0) ~= 0) then
        t.minuteBeep, t.countdownBeep = false, 0
        pcall(model.setTimer, i, t)
      end
    end
  end

  local BAT_NAMES = { "VFAS", "Bat", "RxBt" }

  function F.screen()
    F.silenceTimers()
    local s = {}
    local cfg = loadCfg()
    local st = {}
    local src = { lq = field("RQly"), rssi = field("1RSS"), alt = field("Alt") }
    -- Batteri: flybatteriet hvis en sensor gir det (VFAS/Bat), ellers RxBt. ER8 gir motorbatteriet
    -- som RxBt når spenningsledningen er koblet til batteriet (4-35 V, velger inngang selv).
    for _, n in ipairs(BAT_NAMES) do
      src.rx = field(n)
      if src.rx then src.rxName = n; break end
    end
    local runSw = L.lsSwitch(STD.ls.motorRun)
    local confirmUntil = 0

    local function log(text)
      if not st.file then st.file = logName() end
      local f = io.open(st.file, "a")
      if not f then st.logFail = true; return end
      local d = getDateTime and getDateTime() or {}
      io.write(f, string.format("%02d:%02d:%02d  %-6s  %s\n", d.hour or 0, d.min or 0, d.sec or 0,
        F.clock(st.fe or 0), text))
      io.close(f)
      st.logFail = nil
    end

    local function summary(why)
      if not st.started then return end
      local t = { why .. ": flytid " .. F.clock(st.fe or 0), "motor " .. (st.me or 0) .. " s" }
      if st.lqMin then t[#t + 1] = "min RQly " .. st.lqMin .. " %" end
      if st.rxMin then
        t[#t + 1] = string.format("min %s %.1f V", src.rxName, st.rxMin)
        if st.cells then t[#t + 1] = string.format("(%dS, %.2f V/celle)", st.cells, st.rxMin / st.cells) end
      end
      if st.altMax then t[#t + 1] = string.format("maks høyde %d m", floor(st.altMax + 0.5)) end
      log(table.concat(t, ", "))
    end

    local function clear()
      st = { file = st.file, cells = st.cells }
    end

    local function motorRunning(me)
      if runSw and getSwitchValue then return getSwitchValue(runSw) == true end
      -- uten bryteren: motoren går hvis motortimeren har økt det siste 1,5 sekundet
      local now = getTime()
      if st.meLast ~= me then st.meLast, st.meAt = me, now end
      return st.meAt ~= nil and now - st.meAt < 150 and (me or 0) > 0
    end

    function s:tick()
      local fe, me = timerValue(0), timerValue(1)
      st.noTimer = fe == nil
      if not fe then return end
      me = me or 0
      local now = getTime()
      local fTot, mTot = cfg.flightMin * 60, cfg.motorSec

      -- Timerne nullstilt (Reset flight eller Nullstill): ny flyging
      if st.fe and fe < st.fe then summary("Nullstilt"); clear() end
      st.fe, st.me = fe, me
      if fe > 0 and not st.started then
        st.started = true
        log(string.format("=== Flyging startet (motor på), flytid %d min, motor %d s ===", cfg.flightMin, mTot))
      end

      -- Nedtellingen etter motorkutt starter når motoren stoppes eller motortiden går ut,
      -- det som kommer først, og bare én gang per motorstart
      local function startCut()
        if st.cutStarted then return end
        st.cutStarted = true
        st.cutAt, st.cutLeft = now, V.cutSec
      end

      local linkedNow = st.linked
      local run = motorRunning(me)
      if st.run ~= nil and run ~= st.run then
        if run then
          log("Motor på")
          st.cutAt, st.cutStarted, st.cutLeft = nil, nil, nil
        else
          log("Motor av, motortid " .. me .. " s" ..
            ((linkedNow and st.rx and st.rx > 0) and string.format(", batteri %.1f V", st.rx) or ""))
          startCut()
        end
      end
      st.run = run

      -- Flytid
      local fr = fTot - fe
      if st.fr and fr < st.fr and st.started then
        local k, v = F.flightCall(fr, fTot)
        if fr == V.jingleSec then jingle() end
        if k then say(k, v) end
        if fr <= 0 and st.fr > 0 then log("Flytid " .. cfg.flightMin .. " min nådd") end
      end
      st.fr = fr

      -- Motortid
      local mr = max(0, mTot - me)
      if st.mr and mr < st.mr then
        local k, v = F.motorCall(mr, mTot)
        if k then say(k, v) end
        if mr == 0 then log("Motortid " .. mTot .. " s brukt opp"); startCut() end
      end
      st.mr = mr

      -- Nedtelling etter motorkutt
      if st.cutAt then
        local cl = max(0, V.cutSec - floor((now - st.cutAt) / 100))
        if cl < st.cutLeft then   -- samme utrop som motortiden: hvert 5. sekund og de 7 siste
          local k, v = F.motorCall(cl, V.cutSec)
          if k then say(k, v) end
        end
        st.cutLeft = cl
        local a = read(src.alt)
        if a and (not st.altWin or a > st.altWin) then st.altWin = a end
        if st.cutLeft == 0 then
          local t = V.cutSec .. " s etter motorkutt"
          if st.altWin then t = t .. string.format(": høyde %d m (maks i vinduet)", floor(st.altWin + 0.5)) end
          log(t)
          if playTone then playTone(1500, 300, 0) end
          st.cutAt, st.altWin = nil, nil
        end
      end

      -- Flymodus
      local _, fmName = getFlightMode()
      fmName = fmName or ""
      if st.started and st.fm and fmName ~= st.fm then log("Flymodus: " .. fmName) end
      st.fm = fmName

      -- Link og telemetri
      local lq = read(src.lq)
      local linked
      if getRSSI then linked = (getRSSI() or 0) > 0 else linked = (lq or 0) > 0 end
      st.lq, st.linked = lq, linked
      st.rssi, st.rx = read(src.rssi), read(src.rx)
      -- Motorbatteri: over 6 V er det en pakke (2S og mer), ikke mottakerens 5 V. Celletallet
      -- regnes én gang med motoren av (fulladet 4,2 V per celle), og beholdes til nullstilling.
      if linked and st.rx and st.rx >= V.packMin and not st.cells and not st.run then
        st.cells = math.ceil(st.rx / V.cellDetect)
      end
      local a = read(src.alt)
      if st.started then
        if st.linkWas ~= nil and linked ~= st.linkWas then log(linked and "Link tilbake" or "Link tapt") end
        if linked and lq then
          if not st.lqMin or lq < st.lqMin then st.lqMin = lq end
          if lq < V.lqWarn and not st.lqLow then st.lqLow = true; log("Svakt signal: RQly " .. lq .. " %") end
          if lq >= V.lqWarn + 10 then st.lqLow = nil end
        end
        if linked and st.rx and st.rx > 0 and (not st.rxMin or st.rx < st.rxMin) then st.rxMin = st.rx end
        if linked and a and (not st.altMax or a > st.altMax) then st.altMax = a end
      end
      st.linkWas = linked
    end

    function s:leave()
      summary("Flyskjerm lukket")
    end

    local function box(x, y, w, h, label)
      lcd.drawFilledRectangle(x, y, w, h, L.C.panel)
      lcd.drawRectangle(x, y, w, h, L.C.edge)
      L.text(x + 12, y + 8, label, SMLSIZE, L.C.dim)
    end

    local function big(x, y, t, color)
      lcd.drawText(x, y, t, XXLSIZE + CENTER + color)
    end

    function s:draw(list)
      L.header("Flightscreen", st.fm ~= "" and st.fm or nil)
      if st.noTimer then
        L.text(30, 90, "Modellen har ingen flytid-timer.", MIDSIZE, L.C.warn)
        L.text(30, 150, "Timerne skrives av veiviseren når flyet har motor (steg 5).", 0, L.C.text)
        L.btnRow(list, { { "Tilbake", function() L.pop() end } })
        return
      end
      local fTot = cfg.flightMin * 60

      -- Flytid
      local fr = st.fr or fTot
      box(10, 60, 500, 180, fr < 0 and "Flytid – over tiden" or ("Flytid (" .. cfg.flightMin .. " min)"))
      local fc = (fr <= 0 and L.C.warn) or (fr <= 60 and L.C.act) or L.C.text
      big(260, 110, F.clock(fr), fc)
      if not st.started then L.text(260, 200, "Starter ved motor på", SMLSIZE + CENTER, L.C.dim) end

      -- Batteri (øverst) og link (under)
      box(520, 60, 270, 85, (st.cells and "Motorbatteri" or "Batteri") ..
        (src.rxName and (" (" .. src.rxName .. ")") or ""))
      if not src.rx then
        L.text(655, 98, "Ingen sensor", CENTER, L.C.dim)
      elseif not st.linked or not st.rx or st.rx <= 0 then
        L.text(655, 88, "-", DBLSIZE + CENTER, L.C.dim)
      elseif st.cells then
        local cell = st.rx / st.cells
        local c = (cell < V.cellWarn and L.C.warn) or (cell < V.cellLow and L.C.act) or L.C.text
        L.text(534, 88, string.format("%.1f V", st.rx), DBLSIZE, c)
        L.text(776, 92, st.cells .. "S", SMLSIZE + RIGHT, L.C.dim)
        L.text(776, 114, string.format("%.2f V/c", cell), SMLSIZE + RIGHT, c)
      else
        local low = src.rxName == "RxBt" and st.rx < V.rxbtWarn / 10
        L.text(655, 88, string.format("%.1f V", st.rx), DBLSIZE + CENTER, low and L.C.warn or L.C.text)
      end
      box(520, 155, 270, 85, "Link (RQly)")
      if src.lq == nil and src.rssi == nil then
        L.text(655, 193, "Ingen telemetri", CENTER, L.C.dim)
      elseif not st.linked then
        L.text(655, 183, "INGEN LINK", DBLSIZE + CENTER, L.C.warn)
      else
        local lq = st.lq or 0
        local c = (lq < V.lqWarn and L.C.warn) or (lq < 80 and L.C.act) or L.C.ok
        L.text(534, 183, lq .. " %", DBLSIZE, c)
        if st.rssi then L.text(776, 163, string.format("%d dBm", st.rssi), SMLSIZE + RIGHT, L.C.text) end
        lcd.drawFilledRectangle(670, 205, 106, 14, L.C.off)
        lcd.drawFilledRectangle(670, 205, floor(106 * L.clamp(lq, 0, 100) / 100), 14, c)
      end

      -- Motor
      local mr = st.mr or cfg.motorSec
      box(10, 250, 385, 150, "Motor (" .. cfg.motorSec .. " s)" .. (st.run and "  – går" or ""))
      local mc = (mr == 0 and L.C.warn) or (st.run and mr <= 7 and L.C.act) or (st.run and L.C.text) or L.C.dim
      big(202, 290, cfg.motorSec >= 60 and F.clock(mr) or tostring(mr), mc)

      -- Etter motorkutt
      box(405, 250, 385, 150, "Etter motorkutt")
      local cl = st.cutLeft or V.cutSec
      big(597, 290, tostring(cl), st.cutAt and L.C.act or L.C.dim)

      -- Innstillinger kan bare endres før flygingen, nullstilling krever to trykk
      local idle = not st.started
      L.btnRow(list, {
        { "Flytid " .. cfg.flightMin .. " min", function()
            cfg.flightMin = nextIn(V.flightChoices, cfg.flightMin); L.save(CFG, cfg)
          end, { enabled = idle, primary = false } },
        { "Motor " .. cfg.motorSec .. " s", function()
            cfg.motorSec = nextIn(V.motorChoices, cfg.motorSec); L.save(CFG, cfg)
          end, { enabled = idle, primary = false } },
        { getTime() < confirmUntil and "Trykk igjen" or "Nullstill", function()
            if getTime() < confirmUntil then
              summary("Nullstilt")
              model.resetTimer(0); model.resetTimer(1)
              clear(); confirmUntil = 0
              L.toast("Tidene er nullstilt")
            else
              confirmUntil = getTime() + 300
            end
          end, { enabled = not st.run and st.started == true, primary = false } },
        { "Tilbake", function() L.pop() end, { primary = false } },
      })
      if st.logFail then L.text(400, 382, "Flyloggen kunne ikke skrives (/LOGS)", SMLSIZE + CENTER, L.C.warn) end
    end

    return s
  end

  return F
end
