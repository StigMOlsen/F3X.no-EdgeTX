-- Steg 5: skriver hele oppsettet til modellen ut fra flykonfig, pilotprofil,
-- utslag (steg 4) og justeringene (meny 6): kurver, mikser, logiske brytere,
-- flymoduser, spesialfunksjoner og timere. Kan kjøres på nytt når som helst;
-- alle verdier ligger i fremdriftsfilen til modellen.
-- Fortegn (bestemt): negativ = ror ned / sideror høyre.

return function(L, STD, W)
  local S = {}
  local V = STD.values
  local C = STD.curves
  local LS = STD.ls
  local VCH = STD.vch

  -- Fortegn ved stikke til høyre / fremover
  local WING_AIL = { ailL = -1, ailR = 1, tipL = -1, tipR = 1 }
  local FLAPS = { flapL = -1, flapR = 1 }
  local FUNCS = {
    ailL = { { "ail", -1 } }, ailR = { { "ail", 1 } }, tipL = { { "ail", -1 } }, tipR = { { "ail", 1 } },
    elev = { { "ele", -1 } }, rud = { { "rud", -1 } },
    vL = { { "ele", -1 }, { "rud", 1 } }, vR = { { "ele", -1 }, { "rud", -1 } },
  }
  local RUD_SIGN = { rud = -1, vL = 1, vR = -1 }
  local ELEV = { elev = true, vL = true, vR = true }
  local SRC_NAMES = { ail = { "ail", "Ail", "AIL" }, ele = { "ele", "Ele", "ELE" }, rud = { "rud", "Rud", "RUD" } }
  local MIX_NAMES = { ail = "Ail", ele = "Ele", rud = "Rud" }
  local CURVE_NAMES = { flapL = "CFL", flapR = "CFR", ailL = "CAL", ailR = "CAR", tipL = "CTL", tipR = "CTR" }
  S.WING_AIL, S.FLAPS, S.ELEV = WING_AIL, FLAPS, ELEV

  local ALL_FM = 511                       -- 9 flymoduser, bit satt = mixen er av i den modusen
  local function only(fm) return ALL_FM - 2 ^ fm end
  local function xDead() return 100 - 2 * V.crowDead end   -- crow starter her (Throttle-enden er +100)

  local function src(names) return L.findSource(names) end
  local function chSrc(ch) return L.findSource({ "ch" .. ch, "CH" .. ch }) end

  ----------------------------------------------------------------------
  -- Utslag per ror og side (steg 4)

  function S.rateKey(role, f, sd) return role .. "." .. f .. (sd > 0 and "+" or "-") end

  local function sign(role, f)
    for _, x in ipairs(FUNCS[role] or {}) do if x[1] == f then return x[2] end end
    return 1
  end

  function S.rateDefault(role, f, sd)
    local out = sign(role, f) * sd
    if WING_AIL[role] then return out < 0 and V.ailDown or 100 end
    if role == "vL" or role == "vR" then return f == "ele" and V.vtailEle or V.vtailRud end
    return 100
  end

  function S.rate(st, role, f, sd)
    return (st.rates and st.rates[S.rateKey(role, f, sd)]) or S.rateDefault(role, f, sd)
  end

  local STICK = { ail = { "right", "left" }, ele = { "forward", "back" }, rud = { "right", "left" } }

  -- Liste over alt som stilles i steg 4, i kanalrekkefølge
  function S.rateEntries(cfg)
    local list = {}
    for _, c in ipairs(W.channels(cfg, false)) do
      for _, f in ipairs(FUNCS[c.role] or {}) do
        for _, sd in ipairs({ 1, -1 }) do
          local out = f[2] * sd
          local dir
          if f[1] == "rud" and c.role == "rud" then dir = out < 0 and "right" or "left"
          elseif f[1] == "rud" then dir = "rudder " .. (sd > 0 and "right" or "left")
          else dir = out < 0 and "down" or "up" end
          list[#list + 1] = { role = c.role, ch = c.ch, f = f[1], sd = sd, sign = f[2],
            key = S.rateKey(c.role, f[1], sd),
            label = c.name .. "  " .. dir, stick = MIX_NAMES[f[1]] .. " stick " .. STICK[f[1]][sd > 0 and 1 or 2] }
        end
      end
    end
    return list
  end

  ----------------------------------------------------------------------
  -- Standardverdier for justeringene (meny 6)

  function S.defaults(st)
    st.rates = st.rates or {}
    local a = st.adj or {}
    a.camber = a.camber or {}
    a.crow = a.crow or {}
    a.snapShare = a.snapShare or {}
    for role in pairs(CURVE_NAMES) do
      local c = a.camber[role]
      if c and c[1] ~= nil then
        -- Gammelt format: {Termikk, Midt, Speed} per ror, skalert med «hele vingen»
        -- (camScale, % av veien fra Midt). Regnes om til maks og min per flymodus.
        local k = a.camScale or { tMax = 100, tMin = 0, sMax = 100, sMin = 0 }
        local function at(y, pct) return L.round(c[2] + (pct or 0) / 100 * (y - c[2])) end
        c = { tMax = at(c[1], k.tMax), tMin = at(c[1], k.tMin), sMax = at(c[3], k.sMax), sMin = at(c[3], k.sMin) }
        a.camber[role] = c
      end
      if not c then a.camber[role] = L.copy(FLAPS[role] and V.camber.flap or V.camber.ail) end
      if not a.crow[role] then a.crow[role] = FLAPS[role] and V.crowFlap or V.crowAil end
      if not a.snapShare[role] then a.snapShare[role] = FLAPS[role] and V.snapShare.flap or V.snapShare.ail end
    end
    a.camScale = nil
    a.crowRed = a.crowRed or V.crowRed
    a.crowDiff = a.crowDiff or V.crowDiff
    a.eleComp = a.eleComp or { 0, 0, 0, 0, 0, 0, 0 }
    a.ailRud = a.ailRud or L.copy(V.ailRud)
    a.snap = a.snap or L.copy(V.snap)
    if a.afDown == nil and a.ailFlap then
      -- Gammelt format: ned i % per flymodus (og en stund opp i % av ned). Største verdi blir
      -- ned, opp likt (eller etter forholdet), og flymodusene får sin andel av den.
      local d = 0
      for _, v in pairs(a.ailFlap) do d = math.max(d, v) end
      a.afDown = d
      a.afUp = L.round(d * (a.ailFlapUp or 100) / 100)
      a.afFM = {}
      for fm = 0, 4 do a.afFM[fm] = d > 0 and L.round((a.ailFlap[fm] or 0) * 100 / d) or V.afFM[fm] end
    end
    a.ailFlap, a.ailFlapUp = nil, nil
    a.afDown = a.afDown or V.afDown
    a.afUp = a.afUp or V.afUp
    a.afFM = a.afFM or L.copy(V.afFM)
    a.motor = a.motor or L.copy(V.motorLevels)
    a.motorEle = a.motorEle or V.motorEle
    st.adj = a
    return a
  end

  -- Flymodusene som brukes på denne modellen (FM-nummer)
  function S.usedFMs(cfg, prof)
    local list = { 0 }
    local function has(k) local a = prof[k]; return a and a.ctrl and a.pos ~= nil end
    if cfg.landing and prof.landing and not prof.landing.none then list[#list + 1] = 1 end
    if cfg.launch and has("launch") then list[#list + 1] = 2 end
    if cfg.speed and has("speed") then list[#list + 1] = 3 end
    if cfg.thermal and has("thermal") then list[#list + 1] = 4 end
    return list
  end

  -- Motor-FM-ene (FM-nummer). Tom liste uten motor eller motorbryter.
  function S.motorFMs(cfg, prof)
    local on = prof.motor_on
    if not (cfg.motor and on and on.ctrl and on.pos ~= nil) then return {} end
    local pw = prof.motor_pwr and L.ctrl(prof.motor_pwr.ctrl)
    if pw and pw.type == "3pos" then return { 5, 6, 7 } end
    return { 5 }
  end

  -- FM der verdiene per flymodus hentes fra (motor-FM bruker Normal)
  function S.valueFM(fm)
    return (fm or 0) >= 5 and 0 or (fm or 0)
  end

  -- Kikkflapp brukes ikke i Landing
  S.SNAP_SKIP = { [1] = true }

  -- Vekt for CDiff: ved full crow fjernes (100 - crowDiff) % av ned-aileronen
  function S.crowDiffWeight(st, role)
    local sg = WING_AIL[role]
    return L.round(-sg * S.rate(st, role, "ail", -sg) * (100 - st.adj.crowDiff) / 100)
  end

  ----------------------------------------------------------------------
  -- Kurver. Verdiene lagres «i kontrollens retning» (Termikk / Full crow / Liten
  -- først) og speilvendes når kontrollen er snudd i pilotprofilen.

  local function mirror(y, x)
    local ry, rx = {}, x and {} or nil
    for i = #y, 1, -1 do
      ry[#ry + 1] = y[i]
      if x then rx[#rx + 1] = -x[i] end
    end
    return ry, rx
  end

  local function curveDef(name, y, x, rev)
    y = L.copy(y)
    x = x and L.copy(x) or nil
    if rev then y, x = mirror(y, x) end
    return { name = name, type = x and 1 or 0, y = y, x = x, smooth = 0 }
  end

  function S.curveDefs(cfg, prof, st)
    local a = S.defaults(st)
    local d = {}
    local camRev = prof.camber and prof.camber.rev
    -- Rorets kurve over camber-signalet på CH20 (5 punkter, -100 .. +100):
    -- Termikk maks, Termikk min, nøytral, Speed min, Speed maks.
    for _, c in ipairs(W.channels(cfg, false)) do
      local k = a.camber[c.role]
      if CURVE_NAMES[c.role] then
        d[C[c.role]] = curveDef(CURVE_NAMES[c.role], { k.tMax, k.tMin, 0, k.sMin, k.sMax })
      end
    end
    -- Camber-signalet: i Termikk går kontrollen fra -50 (fram, min) til -100 (bak, maks),
    -- i Speed fra +50 til +100. Normal og Launch gir 0. Bytte av flymodus glir fra 0.
    if (cfg.camberMode or "split") == "full" then
      d[C.camT] = curveDef("CmF", { -100, 0, 100 }, nil, camRev)   -- hele kontrollen: Termikk .. Speed
    else
      d[C.camT] = curveDef("CmT", { -100, -75, -50 }, nil, camRev)
      d[C.camS] = curveDef("CmS", { 100, 75, 50 }, nil, camRev)
    end
    -- Ail->Flap: CH19 er aileron ganger andelen i flymodusen. Kurven per flap gir ned- og
    -- opp-utslaget i % av flappens utslag den veien. Venstre flap går ned når CH19 er
    -- positiv, høyre når den er negativ.
    for role, sg in pairs(FLAPS) do
      local dn, up = a.afDown, a.afUp
      d[C[role == "flapL" and "ailFlapL" or "ailFlapR"]] =
        curveDef(role == "flapL" and "AFL" or "AFR", sg < 0 and { -up, 0, dn } or { -dn, 0, up })
    end
    local crowRev = prof.crow and prof.crow.rev
    local xs = { -100, xDead(), 100 }
    d[C.crow] = curveDef("Crw", { 100, 0, 0 }, xs, crowRev)
    d[C.crowRed] = curveDef("CrR", { a.crowRed, 100, 100 }, xs, crowRev)
    d[C.eleComp] = curveDef("ECo", a.eleComp)   -- etter stikkas rå posisjon, som i læringen
    if cfg.motor then
      local y = {}
      for i, lv in ipairs(a.motor) do y[i] = -100 + 2 * lv end   -- -100 = motor av
      d[C.motor] = curveDef("Mot", y, nil, prof.motor_pwr and prof.motor_pwr.rev)
    end
    return d
  end

  function S.writeCurve(cfg, prof, st, idx)
    local def = S.curveDefs(cfg, prof, st)[idx]
    if not def then return false end
    local ok, r = pcall(model.setCurve, idx, def)
    return ok and (r == nil or r == 0)
  end

  ----------------------------------------------------------------------
  -- Planen: alt som skal skrives, uten å røre modellen

  function S.plan(cfg, prof, st)
    local a = S.defaults(st)
    local p = { mixes = {}, ls = {}, fms = {}, sfs = {}, timers = {}, outputs = {}, errors = {}, notes = {} }
    local function err(t) p.errors[#p.errors + 1] = t end
    local function note(t) p.notes[#p.notes + 1] = t end
    local SRC = {}
    for k, n in pairs(SRC_NAMES) do
      SRC[k] = src(n)
      if not SRC[k] then err("Source not found: " .. MIX_NAMES[k]) end
    end
    local MAX = src({ "max", "MAX" })
    local ON = L.swIndex("ON")
    local fms = S.usedFMs(cfg, prof)
    local useFM = {}
    for _, f in ipairs(fms) do useFM[f] = true end
    p.fmList = fms
    local motFMs = S.motorFMs(cfg, prof)
    local motFM, motMask = {}, 0
    for _, f in ipairs(motFMs) do motFM[f] = true; motMask = motMask + 2 ^ f end

    local function add(ch, m)
      if not m.source then return end
      p.mixes[ch] = p.mixes[ch] or {}
      table.insert(p.mixes[ch], m)
    end

    local crowC = prof.crow and L.ctrl(prof.crow.ctrl)
    local crowId = crowC and crowC.id
    if not crowId then err("Butterfly control not found. Crow and Landing left out.") end
    local camC = prof.camber and prof.camber.ctrl and L.ctrl(prof.camber.ctrl)
    local camId = camC and camC.id
    local trimId = prof.difftrim and prof.difftrim.trim and L.trimSource(prof.difftrim.trim)
    if prof.difftrim and prof.difftrim.trim and not trimId then
      err("Trim not found: " .. prof.difftrim.trim .. ". Differential trim left out.")
    end
    local landMask = useFM[1] and 2 or 0
    local roles = W.channels(cfg, false)
    local hasRole = {}
    for _, c in ipairs(roles) do hasRole[c.role] = true end

    -- Rorene
    for _, c in ipairs(roles) do
      local role, ch = c.role, c.ch
      local isAil, isFlap = WING_AIL[role] ~= nil, FLAPS[role] ~= nil
      local mainAil = role == "ailL" or role == "ailR"   -- tip-servoene får bare utslag, camber og crow
      -- Differensial med trim: demper ned-siden. Står først fordi MULTIPLY ganger alt over.
      if mainAil and trimId then
        local sg = WING_AIL[role]
        local sDown = -sg
        add(ch, { name = "Diff", source = SRC.ail, weight = -sg * S.rate(st, role, "ail", sDown),
          curveType = 2, curveValue = sDown > 0 and 1 or 2 })
        add(ch, { name = "DiffT", source = trimId, weight = 100, multiplex = 1, carryTrim = false })
      end
      -- Utslag per side (steg 4): x>0 og x<0 hver for seg
      for _, f in ipairs(FUNCS[role] or {}) do
        for _, sd in ipairs({ 1, -1 }) do
          add(ch, { name = MIX_NAMES[f[1]] .. (sd > 0 and "+" or "-"), source = SRC[f[1]],
            weight = f[2] * S.rate(st, role, f[1], sd), curveType = 2, curveValue = sd > 0 and 1 or 2 })
        end
      end
      -- Flaps følger aileron (per flymodus, via virtuell kanal)
      if isFlap then add(ch, { name = "AilFlp", source = chSrc(VCH.ailFlap), weight = 100 * FLAPS[role],
        curveType = 3, curveValue = C[role == "flapL" and "ailFlapL" or "ailFlapR"] + 1 }) end
      -- Differensial ved crow: mindre ned-aileron jo mer crow (aileron x crow ligger i CH21)
      if mainAil and crowId and a.crowDiff ~= 100 then
        local sDown = -WING_AIL[role]
        add(ch, { name = "CDiff", source = chSrc(VCH.crowDiff), curveType = 2, curveValue = sDown > 0 and 1 or 2,
          weight = S.crowDiffWeight(st, role) })
        p.crowDiff = true
      end
      -- Mindre aileron ved crow: ganger aileron-delen over (for flaps gjøres det i CH19)
      if mainAil and crowId then
        add(ch, { name = "CrowR", source = crowId, weight = 100, multiplex = 1, curveType = 3,
          curveValue = C.crowRed + 1, carryTrim = false })
      end
      -- Camber fra CH20 gjennom rorets 3-punkts kurve (Termikk, Midt, Speed), av i Landing
      if isAil or isFlap then
        local slow = isFlap and V.flapSlow or 0
        add(ch, { name = "Camb", source = chSrc(VCH.camber), weight = 100, curveType = 3, curveValue = C[role] + 1,
          flightModes = landMask, speedUp = slow, speedDown = slow })
      end
      -- Butterfly: flaps ned, ailerons opp. Uten Slow, så flaps følger stikka i takt med ailerons og EKomp.
      if (isAil or isFlap) and crowId then
        add(ch, { name = "Crow", source = crowId, weight = (isFlap and -1 or 1) * a.crow[role],
          curveType = 3, curveValue = C.crow + 1, carryTrim = false })
      end
      -- Kikkflapp (virtuell kanal, negativ = ned) med andel per ror. Ailerons bare med andel,
      -- slik at det største oppsettet (6 servoer, V-hale, alle FM) holder seg under 64 mikser.
      if isFlap or (mainAil and a.snapShare[role] ~= 0) then
        add(ch, { name = "Snap", source = chSrc(VCH.snap), weight = a.snapShare[role] })
      end
      -- Høyderor: kompensasjon for crow (læres i meny 6) og for motor
      if ELEV[role] then
        if crowId then add(ch, { name = "EleCmp", source = crowId, weight = 100, curveType = 3,
          curveValue = C.eleComp + 1, carryTrim = false }) end
        if cfg.motor then
          local h = L.round(a.motorEle / 2)
          add(ch, { name = "MotEle", source = chSrc(STD.ch.motor), weight = h, offset = h })
        end
      end
      if RUD_SIGN[role] then add(ch, { name = "AilRud", source = chSrc(VCH.ailRud), weight = 100 * RUD_SIGN[role] }) end
    end

    -- Virtuelle kanaler: én mix per flymodus
    local function perFM(ch, base, id, vals, ct, cv, skip)
      for _, fm in ipairs(fms) do
        -- FM0-mixen gjelder også i motor-FM-ene
        if not (skip and skip[fm]) then add(ch, { name = base .. fm, source = id, weight = vals[fm] or 0,
          flightModes = only(fm) - (fm == 0 and motMask or 0),
          curveType = ct, curveValue = cv }) end
      end
    end
    perFM(VCH.snap, "Snap", SRC.ele, a.snap, 2, 2, S.SNAP_SKIP)   -- bare høyderor opp (x<0), ikke i Landing
    if p.crowDiff then
      add(VCH.crowDiff, { name = "CDAil", source = SRC.ail, weight = 100 })
      add(VCH.crowDiff, { name = "CDCrow", source = crowId, weight = 100, multiplex = 1, curveType = 3,
        curveValue = C.crow + 1, carryTrim = false })
      p.outputs[VCH.crowDiff] = "CrDiff"
    end
    p.outputs[VCH.snap] = "Snap"
    perFM(VCH.ailRud, "ARud", SRC.ail, a.ailRud)
    p.outputs[VCH.ailRud] = "AilRud"
    if hasRole.flapL then
      perFM(VCH.ailFlap, "AFlp", SRC.ail, a.afFM)
      if crowId then   -- mindre aileron-følging ved crow, felles for begge flaps
        add(VCH.ailFlap, { name = "CrowR", source = crowId, weight = 100, multiplex = 1, curveType = 3,
          curveValue = C.crowRed + 1, carryTrim = false })
      end
      p.outputs[VCH.ailFlap] = "AilFlp"
    end
    -- Camber-signal (-100 Termikk .. +100 Speed). «split»: kontrollen er bare Termikk-slider i
    -- Termikk og bare Speed-slider i Speed, ellers nøytral. Uten kontroll: fast Termikk/Speed per FM.
    local camMode = cfg.camberMode or "split"
    if camId and camMode == "full" then
      add(VCH.camber, { name = "Camb", source = camId, weight = 100, curveType = 3, curveValue = C.camT + 1,
        carryTrim = false })
    elseif camId then
      if useFM[4] then add(VCH.camber, { name = "CambT", source = camId, weight = 100, curveType = 3,
        curveValue = C.camT + 1, flightModes = only(4), carryTrim = false }) end
      if useFM[3] then add(VCH.camber, { name = "CambS", source = camId, weight = 100, curveType = 3,
        curveValue = C.camS + 1, flightModes = only(3), carryTrim = false }) end
    else
      -- Uten kontroll: fast maks camber i flymodusen
      if useFM[4] then add(VCH.camber, { name = "CambT", source = MAX, weight = -100, flightModes = only(4) }) end
      if useFM[3] then add(VCH.camber, { name = "CambS", source = MAX, weight = 100, flightModes = only(3) }) end
    end
    p.outputs[VCH.camber] = "Camb"

    -- Logiske brytere
    local function sw(i) return L.lsSwitch(i) end
    if useFM[1] then
      local la = prof.landing
      if la.auto then
        if crowId then
          local xd = xDead()
          local e = L.round(xd - V.landingCrow * (xd + 100) / 100)
          if prof.crow.rev then p.ls[LS.landing] = { func = LS_FUNC_VPOS, v1 = crowId, v2 = -e, label = "Landing: crow" }
          else p.ls[LS.landing] = { func = LS_FUNC_VNEG, v1 = crowId, v2 = e, label = "Landing: crow" } end
        end
      elseif la.ctrl and la.pos then
        local s = L.switchIndex(la.ctrl, la.pos)
        if s then p.ls[LS.landing] = { func = LS_FUNC_OR, v1 = s, v2 = s, label = "Landing: switch" }
        else err("Landing switch not found.") end
      end
    end
    local l1, l2, l3, l4, l5 = sw(LS.landing), sw(LS.motorOn), sw(LS.landMotor), sw(LS.lock), sw(LS.motorRun)
    if not (l1 and l2 and l3 and l4 and l5) then err("Logical switches (L1-L5) not found.") end
    local motorOk = false
    if cfg.motor then
      local on = prof.motor_on
      local onSw = on and on.ctrl and on.pos and L.switchIndex(on.ctrl, on.pos)
      if onSw and l1 and l2 and l3 and l4 and l5 then
        motorOk = true
        p.ls[LS.motorOn] = { func = LS_FUNC_OR, v1 = onSw, v2 = onSw, label = "Motor switch on" }
        if p.ls[LS.landing] then
          p.ls[LS.landMotor] = { func = LS_FUNC_AND, v1 = l1, v2 = l2, label = "Landing with motor on" }
        end
        -- Sperre: settes av Landing med motor på, nullstilles når motorbryteren settes av
        p.ls[LS.lock] = { func = LS_FUNC_STICKY, v1 = l3, v2 = -l2, label = "Motor lock" }
        p.ls[LS.motorRun] = { func = LS_FUNC_AND, v1 = l2, v2 = -l4, label = "Motor allowed" }
        -- Motor-FM per motortrinn (3-pos bryter): motor tillatt OG bryterposisjon
        if #motFMs == 3 then
          local pr = prof.motor_pwr
          for i, key in ipairs({ "mot1", "mot2", "mot3" }) do
            local s = L.switchIndex(pr.ctrl, (i - 2) * (pr.rev and -1 or 1))
            if s then p.ls[LS[key]] = { func = LS_FUNC_AND, v1 = l5, v2 = s, label = "Motor-FM " .. i }
            else err("Switch position not found for motor step " .. i .. ".") end
          end
        end
      else
        err("Motor: motor switch not found. The motor stays OFF.")
      end
    end

    -- Motor: alltid av, og erstattes av motorkraft (kurve) når motoren er tillatt
    if cfg.motor then
      local mch = STD.ch.motor
      add(mch, { name = "MotOff", source = MAX, weight = -100 })
      if motorOk then
        local pw = prof.motor_pwr and prof.motor_pwr.ctrl and L.ctrl(prof.motor_pwr.ctrl)
        add(mch, { name = "Motor", source = (pw and pw.id) or MAX, weight = 100, curveType = 3,
          curveValue = C.motor + 1, switch = l5, multiplex = 2, carryTrim = false,
          speedUp = V.motorUp, speedDown = V.motorDown })
      end
    end

    -- Flymoduser: fast nummer, egen høyderorstrim og diff-trim i hver modus.
    -- trimsModes har nøkkel 1-6 (Rud, Ele, Thr, Ail, T5, T6), sjekket med RM Diagnose.
    local ti = prof.difftrim and L.trimIndex(prof.difftrim.trim)
    local GUARD = { [2] = LS.launchG, [3] = LS.speedG, [4] = LS.thermalG }
    p.fmNames = {}
    for _, f in ipairs(STD.fms) do
      local trims = { [2] = 2 * f.fm }
      if ti then trims[ti + 1] = 2 * f.fm end
      if f.fm == 0 then
        p.fms[0] = { name = f.name, fadeIn = V.fade, fadeOut = V.fade, trimsModes = trims }
        p.fmNames[#p.fmNames + 1] = f.name
      elseif useFM[f.fm] then
        local s
        if f.fm == 1 then s = l1 else
          local pa = prof[f.key]
          s = L.switchIndex(pa.ctrl, pa.pos)
          -- Mens motoren går, skal motor-FM vinne: glidefly-FM bare når motoren står
          if s and motorOk and GUARD[f.fm] then
            p.ls[GUARD[f.fm]] = { func = LS_FUNC_AND, v1 = s, v2 = -l5, label = f.name .. " (motor off)" }
            s = sw(GUARD[f.fm])
          end
        end
        if not s then err("Switch not found for " .. f.name .. ".") end
        p.fms[f.fm] = { name = f.name, switch = s or 0, fadeIn = V.fade, fadeOut = V.fade, trimsModes = trims }
        p.fmNames[#p.fmNames + 1] = f.name
      elseif motorOk and motFM[f.fm] then
        -- Egen høyderorstrim per motortrinn, diff-, side- og aileron-trim som Normal
        local s = #motFMs == 1 and l5 or sw(LS["mot" .. f.motor])
        if ti then trims[ti + 1] = 0 end
        trims[1], trims[4] = 0, 0
        local name = #motFMs == 1 and "Motor" or f.name
        p.fms[f.fm] = { name = name, switch = s or 0, fadeIn = V.fade, fadeOut = V.fade, trimsModes = trims }
        p.fmNames[#p.fmNames + 1] = name
      else
        p.fms[f.fm] = { name = "", switch = 0 }
      end
    end

    -- Spesialfunksjoner
    local function sf(t) p.sfs[#p.sfs + 1] = t end
    if motorOk then
      sf({ switch = l4, func = FUNC_OVERRIDE_CHANNEL, param = STD.ch.motor - 1, value = -100,
        label = "Motor lock: CH" .. STD.ch.motor .. " -100 %" })
    end
    for _, f in ipairs(STD.fms) do
      if useFM[f.fm] then
        local s = L.fmSwitch(f.fm)
        if s then sf({ switch = s, func = FUNC_PLAY_TRACK, name = f.sound, repetition = 0, label = "Callout: " .. f.name })
        else note("Switch not found for FM" .. f.fm .. ": no callout for " .. f.name .. ".") end
      end
    end
    if motorOk then
      sf({ switch = l2, func = FUNC_PLAY_TRACK, name = "motpaa", repetition = 0, label = "Callout: Motor on" })
      sf({ switch = -l2, func = FUNC_PLAY_TRACK, name = "motav", repetition = 0, label = "Callout: Motor off" })
      sf({ switch = l4, func = FUNC_PLAY_TRACK, name = "motstp", repetition = 0, label = "Callout: Motor stop" })
    end
    local vol = prof.volume and prof.volume.ctrl and L.ctrl(prof.volume.ctrl)
    if vol and vol.id and ON then sf({ switch = ON, func = FUNC_VOLUME, value = vol.id, label = "Volume: " .. vol.label }) end
    local va = prof.vario
    if va and va.ctrl and va.pos then
      local s = L.switchIndex(va.ctrl, va.pos)
      if s then sf({ switch = s, func = FUNC_VARIO, label = "Vario" }) end
    end
    if ON then sf({ switch = ON, func = FUNC_LOGS, value = V.logInterval, label = "Logging to SD" }) end

    -- Alarmer (lagt inn fra sjekklisten når telemetrien er oppdaget)
    if st.alarms then
      local lq = L.findSource({ "RQly" })
      local bt = L.findSource({ "RxBt" })
      local lq_s, bt_s = sw(LS.lq), sw(LS.rxbt)
      if lq and lq_s then
        p.ls[LS.lq] = { func = LS_FUNC_VNEG, v1 = lq, v2 = V.lqWarn, label = "Weak signal" }
        sf({ switch = lq_s, func = FUNC_PLAY_TRACK, name = "signal", repetition = 10, label = "Callout: Signal" })
      end
      if bt and bt_s then
        p.ls[LS.rxbt] = { func = LS_FUNC_VNEG, v1 = bt, v2 = V.rxbtWarn, label = "Low RX voltage" }
        sf({ switch = bt_s, func = FUNC_PLAY_TRACK, name = "batlav", repetition = 10, label = "Callout: Battery" })
      end
      if not lq and not bt then note("No telemetry found (RQly/RxBt): alarms left out.") end
    end

    -- Timere: flytid fra første motorstart, motortid mens motoren går. Uten pip og stemme:
    -- flyskjermen (flight.lua) leser timerne og gir nedtellingen.
    if motorOk then
      p.timers[0] = { name = "Flight time", mode = 2, switch = l2, start = 0, minuteBeep = false, countdownBeep = 0, persistent = 0 }
      p.timers[1] = { name = "Motor", mode = 1, switch = l5, start = 0, minuteBeep = false, countdownBeep = 0, persistent = 0 }
    end

    p.curves = S.curveDefs(cfg, prof, st)
    local n = 0
    for _, list in pairs(p.mixes) do n = n + #list end
    if n > STD.maxMixes and p.crowDiff then   -- største oppsett: dropp differensial ved crow
      p.mixes[VCH.crowDiff] = nil
      for ch, list in pairs(p.mixes) do
        for i = #list, 1, -1 do if list[i].name == "CDiff" then table.remove(list, i) end end
      end
      p.crowDiff = nil
      err("Too many mixes: differential at crow left out.")
      n = 0
      for _, list in pairs(p.mixes) do n = n + #list end
    end
    p.mixCount = n
    return p
  end

  ----------------------------------------------------------------------
  -- Skriv planen til modellen

  -- Kanaler veiviseren eier: standardkanalene og de virtuelle
  -- Kanaler veiviseren eier: standardkanalene og de virtuelle, og kanalene den skrev til
  -- sist (har piloten flyttet et ror, ryddes den gamle kanalen)
  local function ownedChannels(st)
    local t = {}
    for _, ch in pairs(STD.ch) do t[ch] = true end
    for _, ch in pairs(VCH) do t[ch] = true end
    for _, ch in ipairs((st and st.ownedCh) or {}) do t[ch] = true end
    return t
  end

  local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

  function S.write(p, st)
    local rep, bad = {}, 0
    local function fail(t) rep[#rep + 1] = "! " .. t; bad = bad + 1 end
    local owned = ownedChannels(st)
    st.ownedCh = {}
    for _, ch in pairs(STD.ch) do st.ownedCh[#st.ownedCh + 1] = ch end

    -- Mikser: sjekk plassen først
    local others = 0
    for ch = 1, 32 do
      if not owned[ch] then others = others + model.getMixesCount(ch - 1) end
    end
    if others + p.mixCount > STD.maxMixes then
      fail("Too many mixes (" .. (others + p.mixCount) .. " > " .. STD.maxMixes .. "). Nothing written.")
      return rep, bad, 0
    end

    for idx, c in pairs(p.curves) do
      local ok, r = pcall(model.setCurve, idx, c)
      if not ok or (r ~= nil and r ~= 0) then fail("Curve " .. (idx + 1) .. " " .. c.name .. ": " .. tostring(r)) end
    end
    rep[#rep + 1] = "Curves: " .. count(p.curves)

    for ch in pairs(owned) do
      local idx = ch - 1
      while model.getMixesCount(idx) > 0 do model.deleteMix(idx, 0) end
    end
    local written = 0
    for ch, list in pairs(p.mixes) do
      for i, m in ipairs(list) do
        local ok, e = pcall(model.insertMix, ch - 1, i - 1, m)
        if ok then written = written + 1 else fail("Mix " .. m.name .. " CH" .. ch .. ": " .. tostring(e)) end
      end
    end
    for _, c in ipairs(W.channels(st.cfg, true)) do L.setOutput(c.ch - 1, { name = c.name }) end
    for ch, name in pairs(p.outputs) do L.setOutput(ch - 1, { name = name }) end
    rep[#rep + 1] = "Mixes: " .. written
    if written > 0 then st.planVer = STD.planVersion end

    -- Logiske brytere (felt som utelates nullstilles av EdgeTX, så alle tas med)
    for _, i in pairs(LS) do
      local t = p.ls[i]
      local v = t and { func = t.func, v1 = t.v1, v2 = t.v2, v3 = 0, ["and"] = 0, delay = 0, duration = 0 }
        or { func = LS_FUNC_NONE or 0, v1 = 0, v2 = 0, v3 = 0, ["and"] = 0, delay = 0, duration = 0 }
      local ok, e = pcall(model.setLogicalSwitch, i, v)
      if not ok then fail("L" .. (i + 1) .. ": " .. tostring(e)) end
    end
    rep[#rep + 1] = "Logical switches: " .. count(p.ls)

    if model.setFlightMode then
      for fm, t in pairs(p.fms) do
        local ok, e = pcall(model.setFlightMode, fm, t)
        if not ok or (e ~= nil and e ~= 0) then fail("FM" .. fm .. ": " .. tostring(e)) end
      end
      rep[#rep + 1] = "Flight modes: " .. #p.fmNames
    else
      fail("model.setFlightMode is missing: set the flight modes by hand.")
    end

    -- Bare feltene funksjonen bruker: lydfilnavnet deler minne med value/mode/param,
    -- så value = 0 etter navnet kutter det («normal» ble «no» i RM Diagnose).
    for i, t in ipairs(p.sfs) do
      local v = { switch = t.switch, func = t.func, active = 1 }
      if t.name then v.name = t.name; v.repetition = t.repetition or 0
      else v.value = t.value; v.param = t.param end
      local ok, e = pcall(model.setCustomFunction, i - 1, v)
      if not ok then fail("SF" .. i .. ": " .. tostring(e)) end
    end
    for i = #p.sfs, (st.sfCount or 0) - 1 do   -- fjern gamle som ikke trengs lenger
      pcall(model.setCustomFunction, i, { switch = 0, func = 0, active = 0 })
    end
    st.sfCount = #p.sfs
    rep[#rep + 1] = "Special functions: " .. #p.sfs

    for i, t in pairs(p.timers) do
      local ok, e = pcall(model.setTimer, i, t)
      if not ok then fail("Timer " .. (i + 1) .. ": " .. tostring(e)) end
    end
    rep[#rep + 1] = "Timers: " .. count(p.timers)
    return rep, bad, written
  end

  ----------------------------------------------------------------------
  -- Endringer fra justeringsmenyen, skrevet direkte (uten å skrive alt på nytt)

  function S.applyCamber(st, prof, role)
    return S.writeCurve(st.cfg, prof, st, C[role])
  end

  function S.applyCrow(st, role)
    return L.setMix(STD.ch[role], "Crow", { weight = (FLAPS[role] and -1 or 1) * st.adj.crow[role] })
  end

  function S.applyPerFM(st, kind, fm)
    local base = ({ snap = "Snap", ailRud = "ARud", afFM = "AFlp" })[kind]
    local ch = ({ snap = VCH.snap, ailRud = VCH.ailRud, afFM = VCH.ailFlap })[kind]
    return L.setMix(ch, base .. fm, { weight = st.adj[kind][fm] or 0 })
  end

  -- Ail->Flap ned og opp: de to kurvene
  function S.applyAilFlap(st, prof)
    local a = S.writeCurve(st.cfg, prof, st, C.ailFlapL)
    local b = S.writeCurve(st.cfg, prof, st, C.ailFlapR)
    return a and b
  end

  function S.applyCrowDiff(st, prof)
    local ok = true
    for _, role in ipairs({ "ailL", "ailR" }) do
      if STD.ch[role] and not L.setMix(STD.ch[role], "CDiff", { weight = S.crowDiffWeight(st, role) }) then ok = false end
    end
    if not ok then S.write(S.plan(st.cfg, prof, st), st) end   -- mixene fantes ikke: skriv alt på nytt
    return true
  end

  -- Kikkflapp: under «Maks kikkflapp» står kikkflappen på 100 % i alle FM, så full
  -- høyderor opp viser maks utslag. Ellers verdiene per FM.
  function S.snapFull(st, on)
    for fm = 0, 4 do
      if not S.SNAP_SKIP[fm] then L.setMix(VCH.snap, "Snap" .. fm, { weight = on and 100 or (st.adj.snap[fm] or 0) }) end
    end
  end

  function S.applySnapShare(st, prof, role)
    if L.setMix(STD.ch[role], "Snap", { weight = st.adj.snapShare[role] }) then return true end
    S.write(S.plan(st.cfg, prof, st), st)   -- mixen fantes ikke (andel var 0): skriv alt på nytt
    return true
  end

  function S.applyMotorEle(st)
    local h = L.round(st.adj.motorEle / 2)
    for _, c in ipairs(W.channels(st.cfg, false)) do
      if ELEV[c.role] then L.setMix(c.ch, "MotEle", { weight = h, offset = h }) end
    end
  end

  ----------------------------------------------------------------------
  -- Skjerm for steg 5

  function S.writeScreen()
    local s = {}

    function s:enter()
      s.st = W.state()
      s.prof = W.profile()
      s.p = S.plan(s.st.cfg, s.prof, s.st)
    end

    local function write()
      local written
      s.result, s.bad, written = S.write(s.p, s.st)
      if written > 0 then s.st.done.mix = true end
      W.saveState()
    end

    function s:draw(list)
      L.header("5 - Write setup")
      local y = 58
      if not s.result then
        local p = s.p
        L.text(20, y, "Writes the whole setup to the model \"" .. ((model.getInfo() or {}).name or "") .. "\":")
        y = y + 32
        local lines = {
          "Flight modes: " .. table.concat(p.fmNames, ", "),
          "Mixes: " .. p.mixCount .. " (max " .. STD.maxMixes .. ")",
          "Curves: " .. count(p.curves) .. "   Logical switches: " .. count(p.ls) ..
            "   Special functions: " .. #p.sfs .. "   Timers: " .. count(p.timers),
        }
        for _, t in ipairs(lines) do L.text(30, y, t, SMLSIZE); y = y + 24 end
        y = y + 6
        for _, e in ipairs(p.errors) do L.text(20, y, "! " .. e, SMLSIZE, L.C.warn); y = y + 24 end
        for _, e in ipairs(p.notes) do L.text(20, y, e, SMLSIZE, L.C.dim); y = y + 24 end
        L.text(20, math.max(y, 330), "Mixes on CH1-9 and CH17-20, L1-L13, special functions and", SMLSIZE, L.C.warn)
        L.text(20, math.max(y, 330) + 22, "timers 1-2 are overwritten. Values from step 4 and menu 6 are kept.", SMLSIZE, L.C.warn)
        L.btnRow(list, {
          { "Cancel", function() L.pop() end },
          { "Write setup", write },
        })
      else
        L.text(20, y, s.bad == 0 and "Done. Check the channel monitor and the flight modes." or "Done, with errors:", 0,
          s.bad == 0 and L.C.ok or L.C.warn)
        y = y + 34
        for _, r in ipairs(s.result) do
          if y > 400 then break end
          L.text(30, y, r, SMLSIZE, string.sub(r, 1, 1) == "!" and L.C.warn or L.C.text)
          y = y + 24
        end
        L.btnRow(list, { { "Done", function() L.pop() end } })
      end
    end

    return s
  end

  return S
end
