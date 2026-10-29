-- Oppsettveiviseren: startside (skisse A), steg 0 flykonfig, steg 1 servoretning,
-- steg 2 senter og steg 3 endepunkter. Steg 4, ESC, 6 og 7 ligger i adjust.lua,
-- steg 5 (skriv oppsett) i setup.lua.
-- Fremdrift, flykonfig og alle justerte verdier lagres per modell i
-- /SCRIPTS/RM/DATA/f_<modellfil>.lua (eldre: m_<modellnavn>.lua).

return function(L, STD, P)
  local W = {}
  local V = STD.values
  local st = { done = {} }

  local function loadState()
    local key, nameKey = L.modelKey(), L.modelNameKey()
    st = L.load(key)
    if not st and key ~= nameKey then
      st = L.load(nameKey)   -- eldre fremdrift etter navn, eller kopi med samme navn
      if st then L.save(key, st) end
    end
    st = st or {}
    -- Et filnavn kan brukes på nytt etter sletting: blank modell = start på nytt
    if st.done and st.done.mix and L.modelEmpty() then st = {} end
    st.done = st.done or {}
    if st.cfg and (st.cfg.wing or 0) > 4 then st.cfg.wing = 4 end   -- tip-servoer er tatt ut
  end

  local function saveState()
    if not L.save(L.modelKey(), st) then L.toast("Could not save progress", true) end
  end

  local function loadProfile()
    local p = P.load()
    if p then P.complete(p); P.applyChannels(p) end
    return p
  end

  -- Brukes av setup.lua og adjust.lua (W.S og W.A settes av verktøyet)
  function W.state() return st end
  function W.saveState() saveState() end
  function W.profile() return loadProfile() end

  -- Kanalene i bruk for en flykonfig, i rekkefølgen fra std.lua
  function W.channels(cfg, withMotor)
    local list = {}
    for _, r in ipairs(STD.order) do
      local use = (r == "ailL" or r == "ailR")
        or ((r == "flapL" or r == "flapR") and cfg.wing >= 4)
        or ((r == "tipL" or r == "tipR") and cfg.wing >= 6)
        or ((r == "elev" or r == "rud") and cfg.tail == "X")
        or ((r == "vL" or r == "vR") and cfg.tail == "V")
      if use and STD.ch[r] then list[#list + 1] = { role = r, ch = STD.ch[r], name = STD.names[r] } end
    end
    if withMotor and cfg.motor then
      list[#list + 1] = { role = "motor", ch = STD.ch.motor, name = STD.names.motor }
    end
    return list
  end

  local function byChannel(list)
    local r = {}
    for i, c in ipairs(list) do r[i] = c end
    L.sort(r, function(a, b) return a.ch < b.ch end)
    return r
  end

  local function yesno(v) return v and "Yes" or "No" end

  function W.cfgText(cfg)
    return cfg.wing .. " servos, " .. (cfg.tail == "V" and "V-tail" or "cross") ..
      (cfg.motor and ", motor" or "")
  end

  local MAXSRC
  local function maxSource()
    if not MAXSRC then MAXSRC = L.findSource({ "max", "MAX" }) end
    return MAXSRC
  end

  local chSrcCache = {}
  local function chSource(ch)
    if chSrcCache[ch] == nil then chSrcCache[ch] = L.findSource({ "ch" .. ch, "CH" .. ch }) or false end
    return chSrcCache[ch] or nil
  end

  -- Utslaget fra mikseren, -1..1 (-1 = 100 % ned etter konvensjonen). getValue på en
  -- kanal gir mikserverdien før endepunkter, subtrim og reversering (sett på radioen).
  function W.outV(ch)
    local id = chSource(ch)
    if not id then return 0 end
    return (getValue(id) or 0) / 1024
  end

  -- Flap: -1 ved min-limit (mekanisk stopp, ca. 90 grader ned), 0 ved subtrim (i flukt),
  -- +1 ved max-limit. EdgeTX skalerer mikserverdien fra subtrim til limit, så det er
  -- mikserverdien direkte.
  function W.flapV(ch)
    return L.clamp(W.outV(ch), -1, 1)
  end

  ----------------------------------------------------------------------
  -- Flyfiguren i venstre del av skjermen (kap. 7b). o = { color = {role = farge},
  -- active = role, x, y, w, caption }. Gir trykkflatene til W.planeHits.
  function W.plane(cfg, o)
    o = o or {}
    local G = W.G
    local chmap = {}
    for _, c in ipairs(W.channels(cfg, true)) do chmap[c.role] = c.ch end
    local x, y, w = o.x or 12, o.y or 64, o.w or 390
    local hits = G.plane(cfg, x, y, w, { color = o.color, ch = chmap, active = o.active })
    if o.caption ~= false then
      L.text(x + math.floor(w / 2), y + math.floor(w * 0.70) + 6,
        o.caption or ((cfg.tail == "V" and "V-tail" or "Cross tail") .. " - " .. cfg.wing .. " wing servos" ..
          (cfg.motor and " - motor" or "")), SMLSIZE + CENTER, L.C.dim)
    end
    return hits
  end

  -- Usynlige knapper over rorene på flyfiguren. Legges til ETTER knapperaden,
  -- slik at fokusnummeret til knappene ikke endres. fn(role)
  function W.planeHits(list, hits, fn)
    for _, h in ipairs(hits or {}) do
      L.btn(list, h.x, h.y, h.w, h.h, "#" .. h.role, function() fn(h.role) end, { hidden = true })
    end
  end

  -- Farger per rolle: ferdig = grønn, aktiv = oransje, resten grå
  function W.roleColors(chs, isDone, activeRole)
    local col = {}
    for k, c in ipairs(chs) do
      if c.role == activeRole then col[c.role] = W.G.C.act
      elseif isDone(k, c) then col[c.role] = W.G.C.ok end
    end
    return col
  end

  local function outPct(ch)
    local id = chSource(ch)
    if not id then return nil end
    return L.round((getValue(id) or 0) / 10.24)
  end

  local function lr(role)   -- negativ retning for rollen, etter konvensjonen
    if role == "rud" then return "RIGHT", "LEFT" end
    return "DOWN", "UP"
  end

  ----------------------------------------------------------------------
  -- Skisse A: startside

  -- Når steg 5 er kjørt én gang, skrives oppsettet på nytt automatisk etter hvert steg.
  -- Første gang må steg 5 kjøres for hånd (den varsler om at mikser overskrives).
  function W.autoWrite()
    local prof = loadProfile()
    if not (st.done.mix and st.cfg and prof and W.S) then return end
    st.planVer = nil
    local _, bad = W.S.write(W.S.plan(st.cfg, prof, st), st)
    saveState()
    if bad == 0 then L.toast("Setup written")
    else L.toast("Write error - run step 5", true) end
  end

  -- Oppsett skrevet med en eldre versjon av skriptene, eller pilotoppsettet er endret
  -- utenfor veiviseren (F3X.no -> Pilotoppsett): skriv det på nytt
  function W.upgrade()
    local prof = loadProfile()
    local ps = prof and L.ser(prof)
    local changed = ps and st.profSig and st.profSig ~= ps
    if ps and st.profSig ~= ps then st.profSig = ps; saveState() end
    if st.done.mix and (st.planVer ~= STD.planVersion or changed) then
      W.autoWrite()
      if st.planVer == STD.planVersion then
        L.toast(changed and "Pilot setup changed: setup written again"
          or "New version: setup written again")
      end
    end
  end

  function W.startScreen()
    local s = {}

    local function refresh()
      loadState()
      s.prof = loadProfile()
      -- Har piloten endret kanalene, stemmer ikke oppsettet av modellen lenger
      if s.prof then
        local sig = P.channelSig(s.prof)
        -- Eldre signatur hadde tip-kanalene til slutt (CH8/9, tatt ut 2026-10-28): samme kanaler
        if st.chSig and string.sub(st.chSig, 1, #sig + 1) == sig .. "," then st.chSig = sig end
        if st.chSig and st.chSig ~= sig and next(st.done) then
          st.done = {}
          L.toast("Channels changed: run 0-5 again", true)
        end
        if st.chSig ~= sig then st.chSig = sig; saveState() end
      end
      W.upgrade()
    end

    function s:enter() refresh() end
    function s:resume()
      refresh()
      if s.autoWrite then s.autoWrite = false; W.autoWrite() end
    end

    function s:draw(list)
      local info = model.getInfo()
      L.header("Setup wizard", info and info.name or "")
      local cfg = st.cfg
      local ready = cfg ~= nil and s.prof ~= nil
      local motor = cfg and cfg.motor
      local d = st.done
      local function push(f) return function() L.push(f()) end end
      -- Steg som endrer oppsettet: skriv automatisk når du kommer tilbake hit
      local function pushW(f) return function() s.autoWrite = true; L.push(f()) end end
      local rows = {
        { "P   Pilot setup", s.prof and "saved" or "missing", pushW(function() return P.startScreen(nil) end), true },
        { "0   Model config", cfg and W.cfgText(cfg) or "not set", pushW(W.configScreen), s.prof ~= nil },
        { "1   Servo direction", d.dir and "done" or "-", pushW(W.dirScreen), ready },
        { "2   Center (PPM center)", d.center and "done" or "-", pushW(W.centerScreen), ready and d.dir },
        { "3   Endpoints", d.limits and "done" or "-", pushW(W.limitScreen), ready and d.center },
        { "4   Throws / rates", d.rates and "done" or (d.limits and "-" or "do 3 first"), push(W.A.ratesScreen),
          ready },
        { "E   ESC calibration", motor and (d.esc and "done" or "-") or "no motor", pushW(W.A.escScreen),
          ready and motor },
        { "5   Write setup", d.mix and "written" or "-", push(W.S.writeScreen), ready },
        { "6   Adjust", d.mix and "" or "after 5", push(W.A.menuScreen), ready and d.mix },
        { "7   Checklist", ready and (W.A.checkDone(st) .. " / " .. #W.A.CHECKS) or "", push(W.A.checkScreen), ready },
      }
      local colW = math.floor((L.W - 50) / 2)
      for i, r in ipairs(rows) do
        local col, row = (i <= 5) and 0 or 1, (i - 1) % 5
        L.btn(list, 20 + col * (colW + 10), 60 + row * 54, colW, 46, r[1], r[4] and r[3] or nil,
          { left = true, right = r[2], icon = true })
      end
      -- Slik justeres verdiene (steg 2, 3, 4 og meny 6)
      if s.prof then
        L.text(20, 366, "Adjusting: S1 = coarse, S2 = fine. Center both before each surface.",
          SMLSIZE, L.C.text)
        L.text(20, 388, "PAGE>/< or keys 1-6 skip without saving. Only Save/Confirm saves.", SMLSIZE, L.C.dim)
      end
      if not s.prof then
        L.text(20, 340, "Start with the pilot setup (P).", SMLSIZE, L.C.dim)
      elseif not cfg then
        L.text(20, 340, "Set the model config (0) before the other steps.", SMLSIZE, L.C.dim)
      elseif not d.mix then
        L.text(20, 340, "Run 1-4 and write the setup (5). Then adjust in 6.", SMLSIZE, L.C.dim)
      else
        L.text(20, 340, "Changed something in P, 0 or 4? Write the setup (5) again.", SMLSIZE, L.C.dim)
      end
      L.btn(list, 20, 418, 220, 54, "Exit", function() L.quit() end)
      if not s.focusSet then
        s.focusSet = true
        s.focus = 1
        for i, r in ipairs(rows) do
          if r[4] and (r[2] == "-" or r[2] == "missing" or r[2] == "not set") then s.focus = i; break end
        end
      end
    end

    return s
  end

  ----------------------------------------------------------------------
  -- Steg 0: flykonfigurasjon

  local CFG_OPTS = {
    { key = "wing", label = "Wing servos", values = { 2, 4 }, text = function(v)
      return v == 2 and "2 (ailerons)" or "4 (ail + flaps)" end },
    { key = "tail", label = "Tail", values = { "X", "V" }, text = function(v)
      return v == "V" and "V-tail" or "Cross / conventional" end },
    { key = "motor", label = "Motor", values = { true, false }, text = yesno },
    { key = "thermal", label = "Thermal (FM4)", values = { true, false }, text = yesno },
    { key = "speed", label = "Speed (FM3)", values = { true, false }, text = yesno },
    { key = "launch", label = "Launch (FM2)", values = { true, false }, text = yesno },
    { key = "landing", label = "Landing (FM1)", values = { true, false }, text = yesno },
    { key = "camberMode", label = "Camber control", values = { "split", "full" }, text = function(v)
      return v == "full" and "Full range in all FM" or "Thermal / Speed per FM" end },
  }

  function W.configScreen()
    local s = {}

    function s:enter()
      s.cfg = L.copy(st.cfg or STD.cfg)
      if s.cfg.camberMode == nil then s.cfg.camberMode = STD.cfg.camberMode end
    end

    local function cycle(o)
      local cur = s.cfg[o.key]
      local i = 1
      for k, v in ipairs(o.values) do if v == cur then i = k end end
      s.cfg[o.key] = o.values[i % #o.values + 1]
    end

    local function store()
      local old = st.cfg
      if old and (old.wing ~= s.cfg.wing or old.tail ~= s.cfg.tail or old.motor ~= s.cfg.motor) then
        st.done = {}   -- nye kanaler: stegene må kjøres på nytt
      end
      st.cfg = s.cfg
      saveState()
      for _, c in ipairs(W.channels(s.cfg, true)) do
        L.setOutput(c.ch - 1, { name = c.name })
      end
      L.toast("Model config saved")
      L.pop()
    end

    function s:draw(list)
      L.header("0 - Model config")
      for i, o in ipairs(CFG_OPTS) do
        L.btn(list, 20, 56 + (i - 1) * 43, 470, 38, o.label, function() cycle(o) end,
          { left = true, right = o.text(s.cfg[o.key]) })
      end
      W.plane(s.cfg, { x = 505, y = 70, w = 285 })
      L.text(505, 310, "Tap a row to change it.", SMLSIZE, L.C.dim)
      L.btnRow(list, {
        { "Cancel", function() L.pop() end },
        { "Save", store },
      })
    end

    return s
  end

  ----------------------------------------------------------------------
  -- Steg 1: servoretning. Testbryteren inne = alle ror til negativ (ned / sideror høyre).

  function W.dirScreen()
    local s = { i = 1 }

    -- Knapp n: kanal n (motoren er ikke med i steg 1)
    function s:tick()
      local n = L.keyPressed(s.keys)
      if not n then return end
      for k, x in ipairs(s.chs) do
        if x.ch == n and x.role ~= "motor" then s.i = k; return end
      end
    end

    function s:enter()
      s.prof = loadProfile()
      s.keys = L.keysNew()
      s.chs = byChannel(W.channels(st.cfg, false))
      s.test = L.ctrl(s.prof.test.ctrl)
      s.state = {}
      local half = L.round(V.dirTest / 2)
      s.full = false
      for _, c in ipairs(s.chs) do
        L.tmpClear(c.ch)
        -- Testbryter i ro (-100) gir 0, inne (+100) gir -dirTest
        if not L.tmpAdd(c.ch, s.test.id, -half, -half) then s.full = true end
      end
    end

    function s:leave()
      for _, c in ipairs(s.chs or {}) do L.tmpClear(c.ch) end
    end

    local function reverse(c)
      local out = model.getOutput(c.ch - 1)
      local r = (out and out.revert == 1) and 0 or 1
      L.setOutput(c.ch - 1, { revert = r })
      s.state[c.ch] = r == 1 and "reversed" or "normal"
    end

    function s:draw(list)
      local G = W.G
      L.header("1 - Servo direction", s.i .. " of " .. #s.chs)
      local c = s.chs[s.i]
      local neg = lr(c and c.role)
      local hits = W.plane(st.cfg, { active = c.role,
        color = W.roleColors(s.chs, function(k) return k < s.i end, c.role) })
      local _, h = L.fit(430, 56, "CH" .. c.ch .. "  " .. c.name, 360, { DBLSIZE, MIDSIZE })
      L.text(430, 56 + h + 4, "Surface moves " .. neg .. "?", MIDSIZE, L.C.act)
      G.profile(440, 215, 250, W.outV(c.ch), { arrow = 1 })
      L.text(430, 268, "Hold " .. s.test.label .. " in: all surfaces " .. -V.dirTest .. " %.", SMLSIZE, L.C.dim)
      L.text(430, 290, "Dashed = neutral. Arrow = correct direction.", SMLSIZE, L.C.dim)
      local out = model.getOutput(c.ch - 1)
      local rev = out and out.revert == 1
      L.text(430, 325, "Direction: " .. (rev and "reversed" or "normal") .. (s.state[c.ch] and "  (changed)" or ""),
        0, rev and L.C.act or L.C.text)
      if s.full then
        L.text(12, 385, "Mix limit (64) reached: some surfaces get no test mix!", SMLSIZE, L.C.warn)
      else
        L.text(12, 385, "Tap a surface to select it.", SMLSIZE, L.C.dim)
      end
      L.btnRow(list, {
        { "Cancel", function() L.pop() end },
        { "Back", function() if s.i > 1 then s.i = s.i - 1 end end, { enabled = s.i > 1 } },
        { "Reverse", function() reverse(c) end },
        { "Yes, " .. neg .. " - OK", function()
          if s.i < #s.chs then
            s.i = s.i + 1
          else
            st.done.dir = true
            saveState()
            L.toast("Servo direction done")
            L.pop()
          end
        end, { color = L.C.green } },
      })
      W.planeHits(list, hits, function(role)
        for k, x in ipairs(s.chs) do if x.role == role then s.i = k end end
      end)
      if not s.focusSet then s.focus = 4; s.focusSet = true end
    end

    return s
  end

  ----------------------------------------------------------------------
  -- Felles for steg 2 og 3: én kanal om gangen, grovt med skyver og fint med justeringspotten

  local function adjustBase(s)
    s.prof = loadProfile()
    s.adj = L.ctrl("s2")
    s.dual = L.dualNew()
    s.keys = L.keysNew()
  end

  -- Flaps: servosenteret står langt fra nøytral (ca. 30 grader ned), og flappen går fra
  -- ca. 8 grader opp til 90 grader ned. Nøytral settes med subtrim (offset) i stedet for
  -- PPM-senter, og endepunktene er absolutte (EdgeTX skalerer utslaget fra subtrim til limit).
  local FLAP = { flapL = true, flapR = true }
  function W.isFlap(role) return FLAP[role] == true end
  local function flapDeg(pct) return pct * V.flapDegPct end   -- % fra nøytral -> grader (anslag)

  -- Hopp mellom ror uten å lagre: PAGE> / PAGE<, knappene 1-6 (kanal) og trykk på flyfiguren
  -- Rorene som holdes i senter mens ett ror justeres, i prioritert rekkefølge: først
  -- samme vingehalvdel eller halen (nabororet brukes som mål), så resten. Er mikstaket
  -- nådd, mister de andre gruppene holdingen først. Uten holding følger et ror de vanlige
  -- mikserne (camber, flymodus, trim) og hopper litt når du går videre.
  local GROUP = { ailL = "L", flapL = "L", tipL = "L", ailR = "R", flapR = "R", tipR = "R",
                  elev = "T", rud = "T", vL = "T", vR = "T" }
  local function holdOrder(chs, role)
    local r = {}
    for _, x in ipairs(chs) do
      if x.role ~= role and GROUP[x.role] == GROUP[role] then r[#r + 1] = x end
    end
    for _, x in ipairs(chs) do
      if GROUP[x.role] ~= GROUP[role] then r[#r + 1] = x end
    end
    return r
  end

  -- Ror ved nøytral: navn i stor skrift, så stikkord ved siden av (eller under)
  local function title(name, tag)
    local w = L.fit(430, 56, name, 360, { DBLSIZE, MIDSIZE })
    if 430 + w + 14 + L.textSize(tag, MIDSIZE) <= 790 then L.text(430 + w + 14, 64, tag, MIDSIZE, L.C.act)
    else L.text(790, 64, tag, MIDSIZE + RIGHT, L.C.act) end
  end

  -- Senterverdi. Vanlige ror: PPM-senter i us. Flaps: % der de første 100 % er subtrim
  -- og resten går over i PPM-senter, fordi subtrim er maks ±100 % i EdgeTX og flappen
  -- kan ha nøytral nær enden av servovandringen (lite opp, mye ned).
  local function readCenter(out, flap)
    if not flap then return out.ppmCenter or 0 end
    return L.round((out.offset or 0) / 10 + (out.ppmCenter or 0) / 5.12)
  end

  local function centerFields(c, flap)
    if not flap then return { ppmCenter = c } end
    local o = L.clamp(c, -100, 100)
    return { offset = o * 10, ppmCenter = L.round((c - o) * 5.12) }
  end

  -- Steg 2: senter. PPM-senter (us fra 1500) på vanlige ror, subtrim (%) på flaps.
  function W.centerScreen()
    local s = { i = 1 }
    local go, closeLimits   -- definert under

    local function setup()
      local c = s.chs[s.i]
      -- Alle rorene holdes i senter (samme gruppe først), så et ferdig ror kan brukes som
      -- mål for det neste og ikke hopper. Aktivt ror først, i tilfelle mikstaket nås.
      s.tmpOk, s.held = L.tmpActive(s.chs, c.ch, 0, maxSource(), holdOrder(s.chs, c.role))
      local out = model.getOutput(c.ch - 1) or {}
      s.flap = FLAP[c.role]
      s.max = s.flap and V.flapCenterMax or V.centerMax
      s.orig = { offset = out.offset or 0, ppmCenter = out.ppmCenter or 0,
                 min = out.min or -1000, max = out.max or 1000 }
      s.c0 = L.clamp(readCenter(out, s.flap), -s.max, s.max)
      s.c = s.c0
      -- EdgeTX lar ikke subtrim gå forbi endepunktene: åpne dem mens flappen sentreres
      s.limOpen = s.flap
      if s.flap then L.setOutput(c.ch - 1, { min = -1500, max = 1500 }) end
      s.written = s.c0
      s.rev = out.revert == 1
      -- Med grovkontroll: potten finjusterer. Uten: potten dekker hele området.
      s.fine = s.dual.coarse and (s.flap and V.flapCenterFine or V.centerFine)
        or s.max * 100 / V.centerPot
      L.dualStart(s.dual, true)   -- begge kontrollene må i midten før justeringen starter
    end

    function s:enter()
      adjustBase(s)
      s.chs = W.channels(st.cfg, false)
      setup()
    end

    function s:leave()
      closeLimits()
      for _, x in ipairs(s.chs or {}) do L.tmpClear(x.ch) end
    end

    function s:tick()
      local n = L.keyPressed(s.keys)
      if n then
        for k, x in ipairs(s.chs) do
          if x.ch == n and k ~= s.i then go(k) return end
        end
      end
      local c = s.chs[s.i]
      local d = L.dualDelta(s.dual, s.fine, s.max)
      if not d then return end
      local v = s.c0 + L.round(d)
      s.c = L.clamp(v, -s.max, s.max)
      -- Ved maks: start på nytt herfra, slik at verdien følger kontrollene tilbake med en gang
      if v ~= s.c then s.c0 = s.c; L.dualRebase(s.dual) end
      if s.c ~= s.written then
        L.setOutput(c.ch - 1, centerFields(s.c, s.flap))
        s.written = s.c
      end
    end

    local function restore()
      L.setOutput(s.chs[s.i].ch - 1, s.orig)
      s.limOpen = false
    end

    -- Endepunktene tilbake etter sentrering av flap. Ligger nytt senter utenfor et
    -- endepunkt, flyttes endepunktet ut, og den siden må justeres i steg 3 igjen.
    function closeLimits()
      if not s.limOpen then return end
      s.limOpen = false
      local c = s.chs[s.i]
      local o = L.clamp(s.c, -100, 100) * 10
      local mn, mx = s.orig.min, s.orig.max
      st.done.lim = st.done.lim or {}
      if mn > o - 50 then mn = math.max(-1500, o - 50); st.done.lim[c.role .. "-"] = nil end
      if mx < o + 50 then mx = math.min(1500, o + 50); st.done.lim[c.role .. "+"] = nil end
      L.setOutput(c.ch - 1, { min = mn, max = mx })
    end

    -- Til et annet ror uten å lagre: det aktive roret får tilbake verdien det hadde
    function go(i)
      restore()
      s.i = (i - 1) % #s.chs + 1
      setup()
    end

    function s:onEvent(e)
      if L.isPageNext(e) then go(s.i + 1) return true end
      if L.isPagePrev(e) then go(s.i - 1) return true end
      return false
    end

    local function confirm()
      closeLimits()
      saveState()
      if s.i < #s.chs then
        s.i = s.i + 1
        setup()
      else
        st.done.center = true
        saveState()
        L.toast("Center done")
        L.pop()
      end
    end

    local function cancel()
      restore()
      L.pop()
    end

    function s:back() cancel() end

    function s:draw(list)
      local G = W.G
      local c = s.chs[s.i]
      L.header("2 - Center (neutral)", "CH" .. c.ch .. " - " .. s.i .. " of " .. #s.chs)
      local hits = W.plane(st.cfg, { active = c.role,
        color = W.roleColors(s.chs, function(k) return k < s.i end, c.role) })
      local M = s.max
      if s.flap then
        title(c.name, "FLUSH")
        L.text(430, 106, "Set the flap flush: " .. L.dualLabel(s.dual) .. ".", SMLSIZE, L.C.dim)
        L.text(430, 126, "Subtrim, above 100 % also PPM center.", SMLSIZE, L.C.dim)
        -- Anslag: servosenter = flapZeroDeg ned, subtrim opp løfter flappen
        G.profile(440, 172, 220, flapDeg(s.c) - V.flapZeroDeg, { deg = 1, neutralColor = G.C.ok })
        L.text(430, 238, (s.c >= 0 and "+" or "") .. s.c .. " %", DBLSIZE)
        local f = centerFields(s.c, true)
        L.text(790, 246, f.ppmCenter ~= 0 and (L.round(f.offset / 10) .. " % + " .. f.ppmCenter .. " us")
          or ("subtrim " .. L.round(s.c * 5.12) .. " us"), MIDSIZE + RIGHT)
        -- Strekene ved ±100 % viser hvor subtrim er full og PPM-senter tar over
        G.bar(440, 302, 340, 10, s.c, -M, M, { dot = G.C.act, labels = true,
          marks = { { 0, G.C.white }, { -100, G.C.edge }, { 100, G.C.edge } } })
        L.mixWarn(s.tmpOk, s.held, 430, 340, "Green dashed = flush with the airfoil")
        if math.abs(s.c) >= M then
          L.text(430, 362, "Max. Move the servo arm one spline.", SMLSIZE, L.C.warn)
        elseif math.abs(s.c) > 100 then
          L.text(430, 362, "Above 100 %: the rest is PPM center.", SMLSIZE, L.C.dim)
        end
      else
        title(c.name, "CENTER")
        L.text(430, 106, "Set the surface neutral: " .. L.dualLabel(s.dual) .. ".", SMLSIZE, L.C.dim)
        -- Forsterket visning: 100 us vises som 25 % utslag. PPM-senter kommer etter reversering.
        G.profile(440, 172, 220, (s.rev and -1 or 1) * s.c / 400, { neutralColor = G.C.ok })
        L.text(430, 238, (s.c >= 0 and "+" or "") .. s.c .. " us", DBLSIZE)
        L.text(790, 246, (1500 + s.c) .. " us", MIDSIZE + RIGHT)
        local Wn = V.centerWarn
        G.bar(440, 302, 340, 10, s.c, -M, M, { dot = G.C.act, labels = true, marks = { { 0, G.C.white } },
          zones = { { -M, -Wn, G.C.yellow }, { Wn, M, G.C.yellow }, { -M, -M * 0.9, G.C.red }, { M * 0.9, M, G.C.red } } })
        L.mixWarn(s.tmpOk, s.held, 430, 340, "Green dashed = flush with the airfoil")
        if math.abs(s.c) >= M then
          L.text(430, 362, "Max " .. M .. " us. Adjust linkage/servo arm.", SMLSIZE, L.C.warn)
        elseif math.abs(s.c) > Wn then
          L.text(430, 362, "Above " .. Wn .. " us: adjust linkage/servo arm.", SMLSIZE, L.C.warn)
        end
      end
      L.dualHint(s.dual, 12, 385)
      L.dualWait(s.dual, 430, 362)
      L.text(12, 362, "PAGE>/< or 1-6: skip without saving", SMLSIZE, L.C.dim)
      L.btnRow(list, {
        { "Cancel", cancel },
        { "Back", function() go(s.i - 1) end, { enabled = s.i > 1 } },
        { "Reset pot", function() s.c0 = s.c; L.dualStart(s.dual, true) end },
        { s.i < #s.chs and ("Save -> CH" .. s.chs[s.i + 1].ch) or "Save - done", confirm },
      })
      W.planeHits(list, hits, function(role)
        for k, x in ipairs(s.chs) do
          if x.role == role and k ~= s.i then go(k) return end
        end
      end)
      if not s.focusSet then s.focus = 4; s.focusSet = true end
    end

    return s
  end

  -- Steg 3: endepunkter, negativ side og så positiv side per kanal
  function W.limitScreen()
    local s = { k = 1 }
    local go, toChannel   -- hopp uten å lagre (under)

    local function setup()
      local e = s.entries[s.k]
      -- Aktivt ror til utslaget (først, i tilfelle mikstaket), de andre i senter
      s.tmpOk, s.held = L.tmpActive(s.chs, e.ch.ch, 100 * e.side, maxSource(), holdOrder(s.chs, e.ch.role))
      local out = model.getOutput(e.ch.ch - 1) or {}
      local field = e.side < 0 and "min" or "max"
      s.field = field
      s.flap = FLAP[e.ch.role]
      s.ofs = L.round((out.offset or 0) / 10)
      s.orig = out[field] or (e.side * 1000)
      local cur = L.round(s.orig / 10)
      -- Første gang: lite utslag (20 %) i riktig retning fra nøytral, så servoen ikke
      -- går mot stopp. Er siden lagret før, startes det fra den lagrede verdien.
      s.key = e.ch.role .. (e.side < 0 and "-" or "+")
      if not (st.done.lim and st.done.lim[s.key]) then
        cur = (s.flap and s.ofs or 0) + V.limitStart * e.side
      end
      s.ppmC = out.ppmCenter or 0
      local lo, hi = s.range(e)
      cur = L.clamp(cur, lo, hi)
      s.L0 = cur
      s.L = cur
      s.fine = s.dual.coarse and V.limitFine or (s.flap and V.flapLimitSpan or V.limitSpan)
      L.dualStart(s.dual, true)   -- begge kontrollene må i midten før justeringen starter
      L.setOutput(e.ch.ch - 1, { [field] = cur * 10 })
      s.written = cur
    end

    function s:enter()
      adjustBase(s)
      s.chs = W.channels(st.cfg, false)
      s.entries = {}
      for _, c in ipairs(s.chs) do
        s.entries[#s.entries + 1] = { ch = c, side = -1 }
        s.entries[#s.entries + 1] = { ch = c, side = 1 }
      end
      setup()
    end

    function s:leave()
      for _, x in ipairs(s.chs or {}) do L.tmpClear(x.ch) end
    end

    local function limits(e)
      -- Maks signal: 1500 +/- 768 us (150 %). Senteret spiser plass på den ene siden.
      if e.side < 0 then
        return math.ceil((-768 - s.ppmC) / 5.12), -10
      end
      return 10, math.floor((768 - s.ppmC) / 5.12)
    end

    -- Lovlig område for limit på denne siden: innenfor maks signal og på riktig side av subtrim
    function s.range(e)
      local lo, hi = limits(e)
      lo, hi = math.max(lo, -150), math.min(hi, 150)
      if e.side < 0 then hi = math.min(hi, s.ofs - 5) else lo = math.max(lo, s.ofs + 5) end
      return lo, hi
    end

    function s:tick()
      local n = L.keyPressed(s.keys)
      if n then toChannel(n) return end
      local e = s.entries[s.k]
      local lo, hi = s.range(e)
      local d = L.dualDelta(s.dual, s.fine, V.coarseLimitSpan)
      if not d then return end
      local v = s.L0 + L.round(d)
      s.L = L.clamp(v, lo, hi)
      s.atMax = (v ~= s.L)
      if s.atMax then s.L0 = s.L; L.dualRebase(s.dual) end
      if s.L ~= s.written then
        L.setOutput(e.ch.ch - 1, { [s.field] = s.L * 10 })
        s.written = s.L
      end
    end

    -- Til en annen side/et annet ror uten å lagre: aktiv side får tilbake verdien den hadde
    function go(k)
      local e = s.entries[s.k]
      L.setOutput(e.ch.ch - 1, { [s.field] = s.orig })
      s.k = (k - 1) % #s.entries + 1
      setup()
    end

    function s:onEvent(e)
      if L.isPageNext(e) then go(s.k + 1) return true end
      if L.isPagePrev(e) then go(s.k - 1) return true end
      return false
    end

    -- Knapp n: kanal n, første side. Står du alt på kanalen, byttes side.
    function toChannel(n)
      local cur = s.entries[s.k]
      for k, x in ipairs(s.entries) do
        if x.ch.ch == n and (cur.ch.ch ~= n and x.side == -1 or cur.ch.ch == n and x.side ~= cur.side) then
          go(k) return
        end
      end
    end

    local function confirm()
      st.done.lim = st.done.lim or {}
      st.done.lim[s.key] = true
      saveState()
      if s.k < #s.entries then
        s.k = s.k + 1
        setup()
      else
        st.done.limits = true
        saveState()
        L.toast("Endpoints done")
        L.pop()
      end
    end

    local function cancel()
      local e = s.entries[s.k]
      L.setOutput(e.ch.ch - 1, { [s.field] = s.orig })
      L.pop()
    end

    function s:back() cancel() end

    function s:draw(list)
      local G = W.G
      local e = s.entries[s.k]
      local neg, pos = lr(e.ch.role)
      local sideName = e.side < 0 and neg or pos
      L.header("3 - Endpoints", "CH" .. e.ch.ch .. " " .. sideName .. " - " .. s.k .. " of " .. #s.entries)
      local hits = W.plane(st.cfg, { active = e.ch.role,
        color = W.roleColors(s.chs, function(k) return 2 * k < s.k end, e.ch.role) })
      title(e.ch.name, sideName)
      L.text(430, 106, "CH" .. e.ch.ch .. " - " .. s.field .. "-limit" ..
        (math.abs(s.L) > 100 and " - Extended limits" or ""), SMLSIZE, L.C.dim)
      local lo, hi = s.range(e)
      local room = e.side < 0 and lo or hi
      if s.flap then
        local goal = e.side < 0 and -V.flapDownDeg or V.flapUpDeg
        L.text(430, 126, "Target: approx. " .. math.abs(goal) .. " degrees " .. string.lower(sideName) ..
          (e.side < 0 and ", mechanical stop" or ""), SMLSIZE, L.C.dim)
        G.profile(440, 172, 220, flapDeg(s.L - s.ofs), { deg = 1, limit = flapDeg(room - s.ofs), target = goal })
      else
        G.profile(440, 172, 220, s.L / 100, { limit = room / 100 })
      end
      local us = L.round(1500 + s.ppmC + s.L * 5.12)
      L.text(430, 238, s.L .. " %", DBLSIZE)
      if s.flap then
        L.text(790, 240, "approx. " .. math.abs(L.round(flapDeg(s.L - s.ofs))) .. " degrees", MIDSIZE + RIGHT)
        L.text(790, 276, us .. " us", SMLSIZE + RIGHT, L.C.dim)
      else
        L.text(790, 246, us .. " us", MIDSIZE + RIGHT)
      end
      local marks = { { -100, G.C.edge }, { 100, G.C.edge }, { 0, G.C.white }, { room, G.C.ok } }
      if s.flap then marks[#marks + 1] = { s.ofs, G.C.act } end
      G.bar(440, 302, 340, 10, s.L, -150, 150, { labels = true, marks = marks })
      L.mixWarn(s.tmpOk, s.held, 430, 340, s.flap and "Green = max room. White = target. Orange = neutral."
        or "Green dashed = max room")
      if s.atMax then
        L.text(430, 362, "No room left (max signal).", SMLSIZE, L.C.warn)
      elseif math.abs(s.L) > 100 then
        L.text(430, 362, "Above 100 %: turn on Extended limits.", SMLSIZE, L.C.warn)
      end
      L.dualHint(s.dual, 12, 385)
      L.dualWait(s.dual, 430, 362)
      L.text(12, 362, "PAGE>/< or 1-6: skip without saving", SMLSIZE, L.C.dim)
      L.btnRow(list, {
        { "Cancel", cancel },
        { "Back", function() go(s.k - 1) end, { enabled = s.k > 1 } },
        { "Reset pot", function() s.L0 = s.L; L.dualStart(s.dual, true) end },
        { s.k < #s.entries and "Save -> next" or "Save - done", confirm },
      })
      W.planeHits(list, hits, function(role)
        for k, x in ipairs(s.entries) do
          if x.ch.role == role and x.side == -1 and k ~= s.k then go(k) return end
        end
      end)
      if not s.focusSet then s.focus = 4; s.focusSet = true end
    end

    return s
  end

  return W
end
