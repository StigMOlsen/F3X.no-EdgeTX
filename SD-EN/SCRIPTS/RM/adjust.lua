-- Steg 4 (utslag per ror og side), meny 6 (justeringer, kap. 4b, 4d, 5 og 12),
-- ESC-kalibrering (M2) og sjekkliste med telemetri (steg 7).
-- Alle bruker samme mønster: én verdi om gangen, justeringspotten relativt, Bekreft lagrer.

return function(L, STD, W, S)
  local A = {}
  local V = STD.values
  local C = STD.curves

  local function currentFM()
    local ok, i = pcall(getFlightMode)
    return (ok and i) or 0
  end

  local function fmName(fm)
    for _, f in ipairs(STD.fms) do if f.fm == fm then return f.name end end
    return "FM" .. fm
  end

  -- Rorene som vises oransje på flyfiguren (de som ikke finnes i konfigurasjonen hoppes over)
  local AIL_ROLES = { "ailL", "ailR", "tipL", "tipR" }
  local FLAP_ROLES = { "flapL", "flapR" }
  local ELEV_ROLES = { "elev", "vL", "vR" }
  local RUD_ROLES = { "rud", "vL", "vR" }

  local function used(fm, list)
    for _, f in ipairs(list) do if f == fm then return true end end
    return false
  end

  ----------------------------------------------------------------------
  -- Felles justeringsskjerm.
  -- def = { title, entries = function() -> liste, done(), leave(), select(k) -> k }
  -- entry = { label, hint, get(fm), set(fm, v), min, max, span, unit, fm, prep(), fmt(v) }

  function A.adjustScreen(def)
    local s = { k = 1 }

    local function cur() return s.entries[s.k] end

    local function setup()
      local e = cur()
      s.fm = e.fm and S.valueFM(currentFM()) or nil
      s.orig = e.get(s.fm)
      s.base, s.val, s.dirty = s.orig, s.orig, false
      if e.prep then e.prep() end
      -- Grov (S1) og fin (S2) som i steg 2 og 3. Kurver der stikka velger punktet
      -- (def.select) holder ikke verdien når punktet byttes.
      L.dualStart(s.dual, not def.select, def.select)
    end

    local function commit()
      local e = cur()
      if s.dirty then e.set(s.fm, s.val); s.dirty = false end
      W.saveState()
    end

    function s:enter()
      s.st = W.state()
      s.prof = W.profile()
      s.adj = L.ctrl("s2")
      s.dual = L.dualNew()
      s.keys = L.keysNew()
      S.defaults(s.st)
      s.entries = def.entries(s.st, s.prof)
      -- Testbryteren inne: alle ror i senter, så de er lette å sammenligne mot. Bare når det
      -- er plass til både disse og testmiksene som viser verdiene.
      local test = s.prof.test and L.ctrl(s.prof.test.ctrl)
      local sw = test and L.switchIndex(test.key, 1)
      local MAXS = L.findSource({ "max", "MAX" })
      s.shChs = {}
      local chs = W.channels(s.st.cfg, false)
      -- Plass: én per ror, pluss testmiksene skjermen selv trenger (def.tmpNeed, ellers 1)
      if sw and MAXS and L.mixTotal() + #chs + (def.tmpNeed or 1) <= STD.maxMixes then
        for _, c in ipairs(chs) do
          if L.shAdd(c.ch, MAXS, sw) then s.shChs[#s.shChs + 1] = c.ch end
        end
      end
      s.shLabel = #s.shChs > 0 and test.label or nil
      if #s.entries > 0 then setup() end
    end

    function s:leave()
      if def.leave then def.leave() end
      for _, ch in ipairs(s.shChs or {}) do L.shClear(ch) end
      s.shChs = {}
    end

    function s:tick()
      if #s.entries == 0 then return end
      if def.select then
        local k = def.select(s.k)
        if k and k ~= s.k then commit(); s.k = k; setup(); return end
      end
      -- Knapp n: første verdi for roret på kanal n (aldri motoren)
      local n = not def.select and L.keyPressed(s.keys)
      if n then
        for k, x in ipairs(s.entries) do
          local r = x.roles and x.roles[1]
          if r and r ~= "motor" and STD.ch[r] == n then
            if k ~= s.k then commit(); s.k = k; setup() end
            return
          end
        end
      end
      local e = cur()
      if e.fm and S.valueFM(currentFM()) ~= s.fm then commit(); setup(); return end
      -- Fin: 10 % av området over halv vandring. Grov: hele området over halv vandring.
      -- Uten grovkontroll gjør potten alt (potSpan).
      local fine = s.dual.coarse and (e.fine or math.max(1, L.round((e.max - e.min) / 20)))
        or (V.potSpan or e.span)
      local d = L.dualDelta(s.dual, fine, e.max - e.min)
      if not d then return end
      local v = s.base + L.round(d)
      local c = L.clamp(v, e.min, e.max)
      if c ~= v then s.base = c; L.dualRebase(s.dual) end   -- ved grensen: følg kontrollene tilbake
      if c ~= s.val then s.val = c; s.dirty = true end
      if s.dirty and getTime() - (s.last or 0) >= 25 then
        e.set(s.fm, s.val)
        s.last = getTime()
        s.dirty = false
      end
    end

    local function confirm()
      commit()
      if not def.select and s.k < #s.entries then
        s.k = s.k + 1
        setup()
      else
        if def.done then def.done(s.st, s.prof) end
        W.saveState()
        L.toast((def.doneText or "Saved"))
        L.pop()
      end
    end

    local function cancel()
      if #s.entries > 0 then cur().set(s.fm, s.orig) end
      W.saveState()
      L.pop()
    end

    function s:back() cancel() end

    local function fmTabs()
      local used = S.usedFMs(s.st.cfg, s.prof)
      local t = {}
      local skip = cur().skipFM or {}
      for _, fm in ipairs(used) do
        if not skip[fm] then t[#t + 1] = { fmName(fm), fm == s.fm, true } end
      end
      return t
    end

    function s:draw(list)
      local G = W.G
      if #s.entries == 0 then
        L.header(def.title)
        L.text(20, 70, def.empty or "Nothing to adjust for this model.")
        L.btnRow(list, { { "Back", function() L.pop() end } })
        return
      end
      local e = cur()
      L.header(def.title, def.select and "" or (s.k .. " of " .. #s.entries))
      -- Flyfiguren: rorene som justeres er oransje
      local roles = e.roles or {}
      local col = {}
      for _, r in ipairs(roles) do col[r] = G.C.act end
      local hits = W.plane(s.st.cfg, { color = col, active = roles[1] })
      -- Høyre side: navn, verdi, flymodus, hjelpetekst og grafikk
      local _, h = L.fit(430, 56, e.label, 360, { MIDSIZE, 0, SMLSIZE })
      local vt = e.fmt and e.fmt(s.val) or (s.val .. " " .. (e.unit or "%"))
      local _, h2 = L.fit(430, 58 + h, vt, 360, { DBLSIZE, MIDSIZE }, L.C.act)
      local y = 66 + h + h2
      if e.fm then
        G.tabs(430, y, fmTabs())
        y = y + 34
      end
      if e.fm and e.skipFM and e.skipFM[s.fm] then
        L.text(430, y, "Not used in " .. fmName(s.fm) .. ". Change flight mode.", SMLSIZE, L.C.warn)
        y = y + 22
      end
      for _, h in ipairs(type(e.hint) == "table" and e.hint or { e.hint }) do
        L.text(430, y, h, SMLSIZE, L.C.dim)
        y = y + 22
      end
      y = math.max(y + 10, 222)
      if e.graph then
        local pts, o = e.graph(s.val)
        G.curve(440, y, 330, 110, pts, o)
      elseif roles[1] and STD.ch[roles[1]] then
        -- Flaps: 100 % ned = 90 grader (endepunktet er satt til mekanisk stopp), opp maks 8 grader
        local flap = S.FLAPS[roles[1]] ~= nil
        local ch = STD.ch[roles[1]]
        G.profile(440, y + 40, 250, flap and W.flapV(ch) or W.outV(ch),
          flap and { deg = V.flapDownDeg, degUp = V.flapUpDeg } or nil)
      end
      if def.info then def.info(s, e, 430, y) end
      L.dualHint(s.dual, 12, 385)
      L.dualWait(s.dual, 430, 362)
      if s.shLabel then L.text(12, 362, "Hold " .. s.shLabel .. " in: all surfaces centered.", SMLSIZE, L.C.dim) end
      local items = {
        { "Cancel", cancel },
        { "Back", function() commit(); s.k = s.k - 1; setup() end, { enabled = s.k > 1 and not def.select } },
        { "Reset pot", function() s.base = s.val; L.dualStart(s.dual, true) end },
      }
      if e.fm then
        items[#items + 1] = { "Copy to all FM", function()
          commit()
          for _, fm in ipairs(S.usedFMs(s.st.cfg, s.prof)) do
            if not (e.skipFM and e.skipFM[fm]) then e.set(fm, s.val) end
          end
          W.saveState()
          L.toast("Copied to all flight modes")
        end }
      end
      local last = def.select or s.k == #s.entries
      items[#items + 1] = { last and "Done" or "Confirm", confirm }
      L.btnRow(list, items)
      -- Trykk på et ror: hopp til første verdi for det roret
      if not def.select then
        W.planeHits(list, hits, function(role)
          for k, x in ipairs(s.entries) do
            if x.roles and x.roles[1] == role then
              if k ~= s.k then commit(); s.k = k; setup() end
              return
            end
          end
        end)
      end
      if not s.focusSet then s.focus = #items; s.focusSet = true end
    end

    return s
  end

  local function updown(v)
    if v < 0 then return v .. " % (down)" elseif v > 0 then return "+" .. v .. " % (up)" end
    return "0 %"
  end

  ----------------------------------------------------------------------
  -- Steg 4: utslag per ror og side, vist med testmix

  function A.ratesScreen()
    local MAX = L.findSource({ "max", "MAX" })
    local chans = {}
    local function clearAll() for ch in pairs(chans) do L.tmpClear(ch) end end
    local def = { title = "4 - Throws", doneText = "Throws saved" }

    function def.entries(st)
      local list = {}
      for _, r in ipairs(S.rateEntries(st.cfg)) do
        chans[r.ch] = true
        local function show(v)
          L.tmpClear(r.ch)
          L.tmpAdd(r.ch, MAX, r.sign * r.sd * v, 0)
        end
        list[#list + 1] = {
          label = r.label, min = 0, max = 100, span = 50, roles = { r.role },
          hint = { "Surface is shown as at " .. r.stick .. " full.", "Adjust the throw with the pot. 100 % = endpoint." },
          get = function() return S.rate(st, r.role, r.f, r.sd) end,
          set = function(_, v) st.rates[r.key] = v; show(v) end,
          prep = function() clearAll(); show(S.rate(st, r.role, r.f, r.sd)) end,
        }
      end
      return list
    end

    def.leave = clearAll

    function def.done(st, prof)
      clearAll()
      st.done.rates = true
      if st.done.mix then S.write(S.plan(st.cfg, prof, st), st) end   -- skriv mikserne med de nye utslagene
    end

    return A.adjustScreen(def)
  end

  ----------------------------------------------------------------------
  -- Meny 6: justeringer

  local function wingRoles(cfg, filter)
    local t = {}
    for _, c in ipairs(W.channels(cfg, false)) do
      if (S.WING_AIL[c.role] or S.FLAPS[c.role]) and (not filter or filter(c.role)) then t[#t + 1] = c end
    end
    return t
  end

  -- Y-skala for kurvegrafen: litt over største verdi, minst 20 %
  function A.range(pts)
    local m = 20
    for _, p in ipairs(pts) do m = math.max(m, math.abs(p[2]) + 5) end
    return math.min(100, math.ceil(m / 10) * 10)
  end

  -- Termikk / Speed per ror: maks (kontrollen bak) og min (kontrollen fram) i hver
  -- flymodus. Rekkefølge: maks på begge flaps, så hvert aileron (og tip), så min i samme
  -- rekkefølge. Roret viser verdien med en testmix, så flymodus og kontroll trenger ikke
  -- stilles. Min kan være 0 (nøytral).
  local function camberScreen()
    local def = { title = "Thermal / Speed per surface", tmpNeed = 6 }   -- alle vingerorene vises
    local MAXS = L.findSource({ "max", "MAX" })
    local shown = {}
    -- Alle vingerorene viser verdien for det som stilles (f.eks. Termikk maks), så de ferdige
    -- blir stående og kan sammenlignes med øyemål. Det aktive roret viser v.
    local function show(st, wing, key, role, v)
      for _, c in ipairs(wing) do
        local w = c.role == role and v or st.adj.camber[c.role][key]
        if not L.setMix(c.ch, L.TMP, { weight = w }) then L.tmpClear(c.ch); L.tmpAdd(c.ch, MAXS, w, 0) end
        shown[c.ch] = true
      end
    end
    function def.leave()
      for ch in pairs(shown) do L.tmpClear(ch) end
      shown = {}
    end
    function def.entries(st, prof)
      local list = {}
      local cam = prof.camber and prof.camber.ctrl and L.ctrl(prof.camber.ctrl)
      if cam and not cam.id then cam = nil end
      local back = (prof.camber and prof.camber.rev) and 100 or -100   -- kontrollens maks-ende
      local used = {}
      for _, fm in ipairs(S.usedFMs(st.cfg, prof)) do used[fm] = true end
      local wing = wingRoles(st.cfg)
      for _, m in ipairs({ { fm = 4, name = "Thermal", k = "t" }, { fm = 3, name = "Speed", k = "s" } }) do
        if used[m.fm] then
          for _, ende in ipairs(cam and { "Max", "Min" } or { "Max" }) do
            local key = m.k .. ende
            for _, c in ipairs(wing) do
              local hint
              if not cam then
                hint = { "Fixed camber in " .. m.name .. " (no control).", "The surface shows the value." }
              elseif ende == "Max" then
                hint = { cam.label .. " back: most throw.", "All surfaces show their max." }
              else
                hint = { cam.label .. " forward: least throw. 0 = neutral.", "All surfaces show their min." }
              end
              list[#list + 1] = {
                label = c.name .. "  " .. m.name .. (ende == "Max" and " max" or " min"),
                min = -100, max = 100, span = 50, fmt = updown, roles = { c.role }, hint = hint,
                graph = cam and function(v)
                  local k = st.adj.camber[c.role]
                  local mx = ende == "Max" and v or k[m.k .. "Max"]
                  local mn = ende == "Min" and v or k[m.k .. "Min"]
                  local pts, names, act = { { back, mx }, { -back, mn } }, { "Max", "Min" }, ende == "Max" and 1 or 2
                  if back > 0 then pts = { pts[2], pts[1] }; names = { "Min", "Max" }; act = 3 - act end
                  return pts, { active = act, names = names, range = A.range(pts), cursor = L.value(cam) / 10.24 }
                end or nil,
                get = function() return st.adj.camber[c.role][key] end,
                set = function(_, v)
                  st.adj.camber[c.role][key] = v
                  S.applyCamber(st, prof, c.role)
                  show(st, wing, key, c.role, v)
                end,
                prep = function() show(st, wing, key, c.role, st.adj.camber[c.role][key]) end,
              }
            end
          end
        end
      end
      return list
    end
    def.empty = "The model does not use Thermal or Speed."
    return A.adjustScreen(def)
  end

  local function crowScreen()
    local def = { title = "Butterfly (crow)" }
    function def.entries(st, prof)
      local list = {}
      for _, c in ipairs(wingRoles(st.cfg)) do
        local flap = S.FLAPS[c.role] ~= nil
        list[#list + 1] = {
          label = c.name .. (flap and "  down" or "  up"), min = 0, max = 100, span = 50, roles = { c.role },
          hint = { "Pull the butterfly control fully (full crow).", flap and "Flaps down." or "Ailerons up." },
          get = function() return st.adj.crow[c.role] end,
          set = function(_, v) st.adj.crow[c.role] = v; S.applyCrow(st, c.role) end,
        }
      end
      list[#list + 1] = {
        label = "Aileron at full crow", min = 20, max = 100, span = 40, roles = AIL_ROLES,
        hint = { "Full crow and aileron throw.", "How much aileron is left at full crow." },
        get = function() return st.adj.crowRed end,
        set = function(_, v) st.adj.crowRed = v; S.writeCurve(st.cfg, prof, st, C.crowRed) end,
      }
      list[#list + 1] = {
        label = "Differential at full crow", min = 0, max = 100, span = 50, roles = AIL_ROLES,
        hint = { "Full crow and aileron throw.", "Down aileron in % of normal. 100 % = as without crow." },
        fmt = function(v) return v .. " % down" end,
        get = function() return st.adj.crowDiff end,
        set = function(_, v) st.adj.crowDiff = v; S.applyCrowDiff(st, prof) end,
      }
      return list
    end
    return A.adjustScreen(def)
  end

  -- Høyderorskompensasjon for butterfly: 7-punkts kurve, punktet velges med stikka (kap. 5)
  local XS = { -100, -67, -33, 0, 33, 67, 100 }
  local function eleCompScreen()
    local crowC
    local def = { title = "Elevator with butterfly", doneText = "Curve saved" }
    function def.entries(st, prof)
      crowC = prof.crow and L.ctrl(prof.crow.ctrl)
      if not (crowC and crowC.id) then return {} end
      local list = {}
      for i = 1, 7 do
        list[i] = {
          label = "Point " .. i .. "  (" .. crowC.label .. " " .. XS[i] .. " %)", min = -100, max = 100, span = 50,
          fmt = updown, roles = ELEV_ROLES,
          graph = function(v)
            local pts = {}
            for j = 1, 7 do pts[j] = { XS[j], j == i and v or st.adj.eleComp[j] } end
            return pts, { active = i, range = A.range(pts), cursor = L.value(crowC) / 10.24 }
          end,
          hint = { "Move " .. crowC.label .. " to the points. The pot adjusts", "the elevator at the point the stick is at." },
          get = function() return st.adj.eleComp[i] end,
          set = function(_, v) st.adj.eleComp[i] = v; S.writeCurve(st.cfg, prof, st, C.eleComp) end,
        }
      end
      return list
    end
    function def.select(k)
      local x = L.value(crowC) / 10.24
      local best, bd = k, 1000
      for i, p in ipairs(XS) do
        local d = math.abs(x - p)
        if d < bd then best, bd = i, d end
      end
      if best ~= k and bd < 10 then return best end   -- hysterese: må nær punktet
      return k
    end
    return A.adjustScreen(def)
  end

  local function perFMScreen(kind, title, label, hint, max, extra, roles)
    local def = { title = title }
    function def.entries(st, prof)
      local list = { {
        label = label, fm = true, min = 0, max = max, span = max / 2, hint = hint, roles = roles,
        get = function(fm) return st.adj[kind][fm] or 0 end,
        set = function(fm, v) st.adj[kind][fm] = v; S.applyPerFM(st, kind, fm) end,
      } }
      if extra then extra(st, prof, list) end
      return list
    end
    return A.adjustScreen(def)
  end

  -- Kikkflapp: først maks utslag per ror (kikkflappen står på 100 % imens), så hvor mye
  -- av maks som brukes i hver flymodus. Ikke i Landing.
  local function snapScreen()
    local def = { title = "Snap flap" }
    local st0
    function def.entries(st, prof)
      st0 = st
      local list = {}
      for _, c in ipairs(wingRoles(st.cfg, function(r) return S.FLAPS[r] or r == "ailL" or r == "ailR" end)) do
        list[#list + 1] = {
          label = "Max snap flap " .. c.name, min = 0, max = V.snapShareMax, span = V.snapShareMax / 2,
          roles = { c.role },
          hint = { "Pull full up elevator.", "Adjust the surface to max snap flap." },
          get = function() return st.adj.snapShare[c.role] end,
          set = function(_, v) st.adj.snapShare[c.role] = v; S.applySnapShare(st, prof, c.role) end,
          prep = function() S.snapFull(st, true) end,
        }
      end
      list[#list + 1] = {
        label = "Snap flap in flight mode", fm = true, min = 0, max = 100, span = 50, roles = FLAP_ROLES,
        skipFM = S.SNAP_SKIP, fmt = function(v) return v .. " % of max" end,
        hint = { "Pull full up elevator.", "0 % = no snap flap in this flight mode." },
        get = function(fm) return st.adj.snap[fm] or 0 end,
        set = function(fm, v)
          if S.SNAP_SKIP[fm] then return end
          st.adj.snap[fm] = v; S.applyPerFM(st, "snap", fm)
        end,
        prep = function() S.snapFull(st, false) end,
      }
      return list
    end
    function def.leave() if st0 then S.snapFull(st0, false) end end
    return A.adjustScreen(def)
  end

  local function motorScreen()
    local def = { title = "Motor", doneText = "Motor saved" }
    function def.entries(st, prof)
      if not st.cfg.motor then return {} end
      local pw = prof.motor_pwr and L.ctrl(prof.motor_pwr.ctrl)
      local list = {}
      local warn = "HOLD THE MODEL. Keep clear of the propeller."
      for i, n in ipairs({ "Low", "Medium", "Full" }) do
        list[#list + 1] = {
          label = "Motor " .. n, min = 0, max = 100, span = 50,
          hint = { (pw and ("Set " .. pw.label .. " to " .. n .. ", ") or "") .. "motor switch on.", warn },
          get = function() return st.adj.motor[i] end,
          set = function(_, v) st.adj.motor[i] = v; S.writeCurve(st.cfg, prof, st, C.motor) end,
        }
      end
      list[#list + 1] = {
        label = "Motor -> elevator", min = -30, max = 30, span = 15, fmt = updown, roles = ELEV_ROLES,
        hint = { "Elevator at full motor (+ = up).", "Scales with motor power." },
        get = function() return st.adj.motorEle end,
        set = function(_, v) st.adj.motorEle = v; S.applyMotorEle(st) end,
      }
      return list
    end
    def.empty = "The model has no motor (step 0)."
    return A.adjustScreen(def)
  end

  -- Aileron -> flaps: ned i % av flappens utslag ned, opp i % av utslaget opp (begge flaps),
  -- og hvor mye av dette som brukes i hver flymodus (100 % = som satt)
  local function ailFlapScreen()
    local def = { title = "Aileron -> flaps", tmpNeed = 2 }
    local MAXS = L.findSource({ "max", "MAX" })
    -- Mens ned (opp) stilles, står begge flaps på ned- (opp-)utslaget, så det kan måles
    -- uten aileron-stikka. Andelen per flymodus vises med aileron-stikka som vanlig.
    local function show(w)
      for _, r in ipairs(FLAP_ROLES) do
        local ch = STD.ch[r]
        if w == nil then L.tmpClear(ch)
        elseif not L.setMix(ch, L.TMP, { weight = w }) then L.tmpClear(ch); L.tmpAdd(ch, MAXS, w, 0) end
      end
    end
    function def.leave() show(nil) end
    function def.entries(st, prof)
      local function side(key, sg, label, hint)
        return {
          label = label, min = 0, max = 100, span = 50, roles = FLAP_ROLES, hint = hint,
          get = function() return st.adj[key] end,
          set = function(_, v) st.adj[key] = v; S.applyAilFlap(st, prof); show(sg * v) end,
          prep = function() show(sg * st.adj[key]) end,
        }
      end
      return {
        side("afDown", -1, "Ail -> Flap down", { "Both flaps now show the down throw.", "In % of the flap's down throw." }),
        side("afUp", 1, "Ail -> Flap up", { "Both flaps now show the up throw.", "In % of the flap's up throw." }),
        {
          label = "Ail -> Flap in flight mode", fm = true, min = 0, max = 150, span = 50, roles = FLAP_ROLES,
          fmt = function(v) return v .. " % of down/up" end,
          hint = { "Give full aileron and watch the flaps.", "100 % = the throw set in down and up. 0 % = off." },
          get = function(fm) return st.adj.afFM[fm] or 0 end,
          set = function(fm, v) st.adj.afFM[fm] = v; S.applyPerFM(st, "afFM", fm) end,
          prep = function() show(nil) end,
        },
      }
    end
    return A.adjustScreen(def)
  end

  function A.menuScreen()
    local s = {}
    local items = {
      { "Thermal / Speed per surface", camberScreen },
      { "Butterfly (crow)", crowScreen },
      { "Elevator with butterfly (curve)", eleCompScreen },
      { "Aileron -> rudder (per FM)", function()
        return perFMScreen("ailRud", "Aileron -> rudder", "Ail -> Rud", { "Give aileron and watch the rudder." }, 100,
          nil, RUD_ROLES)
      end },
      { "Snap flap (per FM)", snapScreen },
      { "Aileron -> flaps (per FM)", ailFlapScreen, function(st) return st.cfg.wing >= 4 end },
      { "Motor: level and elevator", motorScreen, function(st) return st.cfg.motor end },
    }

    function s:enter()
      s.st = W.state()
      W.upgrade()
    end

    function s:draw(list)
      L.header("6 - Adjust", fmName(currentFM()))
      for i, it in ipairs(items) do
        local en = not it[3] or it[3](s.st)
        L.btn(list, 20, 56 + (i - 1) * 39, 500, 34, it[1], en and function() L.push(it[2]()) end or nil, { left = true, icon = true })
      end
      L.text(540, 62, "Differential:", SMLSIZE, L.C.dim)
      L.text(540, 86, "Set with the trim in flight,", SMLSIZE, L.C.dim)
      L.text(540, 110, "own value in each flight mode.", SMLSIZE, L.C.dim)
      L.text(540, 150, "Per FM: change flight mode with", SMLSIZE, L.C.dim)
      L.text(540, 174, "the switch while adjusting.", SMLSIZE, L.C.dim)
      L.btnRow(list, { { "Back", function() L.pop() end } })
    end

    return s
  end

  ----------------------------------------------------------------------
  -- ESC-kalibrering (M2): full Throttle, så null Throttle, med testmix på motorkanalen

  function A.escScreen()
    local s = { step = 0 }
    local MAX = L.findSource({ "max", "MAX" })
    local mch = STD.ch.motor

    local function set(w)
      L.tmpClear(mch)
      if w then L.tmpAdd(mch, MAX, w, 0) end
    end

    function s:enter()
      s.st = W.state()
      s.out = model.getOutput(mch - 1)
    end

    function s:leave() set(nil) end

    local function cancel() set(-100); set(nil); L.pop() end
    function s:back() cancel() end

    function s:draw(list)
      L.header("ESC calibration", "CH" .. mch)
      local t
      if s.step == 0 then
        t = { "REMOVE THE PROPELLER before you start.", "The flight battery must be disconnected.",
              "Start: the channel goes to FULL Throttle and endpoints are set to 100 %." }
      elseif s.step == 1 then
        t = { "Full Throttle is being sent.", "Connect the flight battery and wait for the ESC beeps.", "Press Next for zero Throttle." }
      else
        t = { "Zero Throttle is being sent.", "Wait for the beeps that confirm the calibration.", "Press Done." }
      end
      for i, x in ipairs(t) do L.text(20, 70 + (i - 1) * 36, x, 0, (s.step == 0 and i == 1) and L.C.warn or L.C.text) end
      L.text(20, 200, "The procedure varies between ESCs. Check your manual.", SMLSIZE, L.C.dim)
      L.text(20, 226, "If the motor lock is on (Landing), CH" .. mch .. " sends -100 % anyway.", SMLSIZE, L.C.dim)
      local items = { { "Cancel", cancel } }
      if s.step == 0 then
        items[2] = { "Start (full Throttle)", function()
          L.setOutput(mch - 1, { min = -1000, max = 1000, ppmCenter = 0 })
          set(100)
          s.step = 1
        end }
      elseif s.step == 1 then
        items[2] = { "Next (zero Throttle)", function() set(-100); s.step = 2 end }
      else
        items[2] = { "Done", function()
          set(nil)
          s.st.done.esc = true
          W.saveState()
          L.toast("ESC calibrated")
          L.pop()
        end }
      end
      L.btnRow(list, items)
      if not s.focusSet then s.focus = 2; s.focusSet = true end
    end

    return s
  end

  ----------------------------------------------------------------------
  -- Steg 7: sjekkliste for det som ikke kan settes fra Lua, og telemetri

  A.CHECKS = {
    { "bind", "Receiver bound (ELRS)" },
    { "range", "Range check done" },
    { "fullres", "ELRS 4: 100Hz Full, 8ch (16ch/2 with tips)" },
    { "telem", "ELRS: Telem Ratio is not Race" },
    { "nosync", "ELRS: No sync on arm is off" },
    { "arm", "Arm using: Switch, ON (CH5 becomes normal)" },
    { "ext", "Extended limits on (MODEL SETUP)" },
    { "failsafe", "Failsafe: Custom, motor -100 %, surfaces neutral" },
    { "swwarn", "Switch warning: motor switch Off at power-up" },
    { "sounds", "Sound files are in /SOUNDS/<language>/" },
  }

  function A.checkDone(st)
    local n = 0
    for _, c in ipairs(A.CHECKS) do if st.check and st.check[c[1]] then n = n + 1 end end
    return n
  end

  function A.checkScreen()
    local s = {}

    function s:enter()
      s.st = W.state()
      s.st.check = s.st.check or {}
    end

    local function tele(name)
      local id = L.findSource({ name })
      if not id then return "-" end
      local v = getValue(id)
      return v and tostring(v) or "-"
    end

    function s:draw(list)
      L.header("7 - Checklist", A.checkDone(s.st) .. " / " .. #A.CHECKS)
      for i, c in ipairs(A.CHECKS) do
        local on = s.st.check[c[1]]
        L.btn(list, 20, 56 + (i - 1) * 35, 520, 32, (on and "[x]  " or "[ ]  ") .. c[2], function()
          s.st.check[c[1]] = not s.st.check[c[1]] or nil
          W.saveState()
        end, { left = true, color = on and L.C.off or nil })
      end
      L.text(560, 60, "Telemetry", 0, L.C.dim)
      L.text(560, 92, "RQly: " .. tele("RQly") .. " %", SMLSIZE)
      L.text(560, 118, "1RSS: " .. tele("1RSS") .. " dB", SMLSIZE)
      L.text(560, 144, "RxBt: " .. tele("RxBt") .. " V", SMLSIZE)
      L.text(560, 180, s.st.alarms and "Alarms: set" or "Alarms: not set", SMLSIZE,
        s.st.alarms and L.C.ok or L.C.dim)
      L.btnRow(list, {
        { "Back", function() L.pop() end },
        { "Set alarms", function()
          if not L.findSource({ "RQly" }) and not L.findSource({ "RxBt" }) then
            L.toast("No telemetry yet. Bind and power the receiver.", true)
            return
          end
          s.st.alarms = true
          local _, bad = S.write(S.plan(s.st.cfg, W.profile(), s.st), s.st)
          W.saveState()
          L.toast(bad == 0 and "Alarms set" or "Write error, see step 5", bad ~= 0)
        end, { enabled = s.st.done.mix == true } },
      })
    end

    return s
  end

  return A
end
