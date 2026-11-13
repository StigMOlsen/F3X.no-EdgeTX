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
  -- def = { title, entries = function() -> liste, done(), leave(), select(k) -> k,
  --         quick(st) -> true: lagre og gå ut fra hver verdi (standard: oppsettet er skrevet),
  --         quickLabel }
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
      -- Gjort før: Tilbake byttes mot en knapp som lagrer og går ut
      if def.quick then s.quick = def.quick(s.st) else s.quick = s.st.done.mix end
      -- Testbryteren inne: alle ror i senter, så de er lette å sammenligne mot. Bare når det
      -- er plass til både disse og testmiksene som viser verdiene.
      -- def.noSH: skjermen viser ingen ror, så SH sentrerer ikke (trygt å ha åpen i lufta)
      local test = not def.noSH and s.prof.test and L.ctrl(s.prof.test.ctrl)
      local sw = test and L.switchIndex(test.key, 1)
      local MAXS = L.findSource({ "max", "MAX" })
      s.shChs = {}
      local chs = W.channels(s.st.cfg, false)
      -- Rorene som viser verdien med testmiks (def.room) må ha plass under mikstaket, ellers
      -- står de stille når S1/S2 dreies. Veiviserens mikser der tas ut mens skjermen er åpen.
      if def.room then
        s.room = { chs = def.room(s.st) }
        W.makeRoom(s.room, (sw and MAXS) and #chs or 0)
      end
      -- Plass: én per ror, pluss testmiksene skjermen selv trenger (def.tmpNeed, ellers 1)
      local tmpNeed = s.room and #s.room.chs or def.tmpNeed or 1
      -- Ikke SH-senter når flysperren er på: et trykk på SH i lufta skal ikke sentrere rorene
      if sw and MAXS and not W.locked() and L.mixTotal() + #chs + tmpNeed <= STD.maxMixes then
        for _, c in ipairs(chs) do
          if L.shAdd(c.ch, MAXS, sw) then s.shChs[#s.shChs + 1] = c.ch end
        end
      end
      s.shLabel = #s.shChs > 0 and test.label or nil
      s.shBlocked = sw and MAXS and #s.shChs == 0 and not W.locked() and test.label or nil
      if #s.entries > 0 then setup() end
    end

    function s:leave()
      if def.leave then def.leave() end
      for _, ch in ipairs(s.shChs or {}) do L.shClear(ch) end
      s.shChs = {}
      if s.room then W.restoreRoom(s.room); s.room = nil end
    end

    -- Tilbake fra en underskjerm (def.extra): sett opp testmikser og pot på nytt, samme verdi
    function s:resume() s:enter() end

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

    -- out: lagre denne verdien og gå ut, uten å bla gjennom resten
    local function confirm(out)
      commit()
      if not def.select and s.k < #s.entries and not out then
        s.k = s.k + 1
        setup()
      else
        if def.done then def.done(s.st, s.prof) end
        W.saveState()
        L.toast((def.doneText or "Lagret"))
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
        L.text(20, 70, def.empty or "Ingenting å justere for denne modellen.")
        L.btnRow(list, { { "Tilbake", function() L.pop() end } })
        return
      end
      local e = cur()
      L.header(def.title, def.select and "" or (s.k .. " av " .. #s.entries))
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
        L.text(430, y, "Brukes ikke i " .. fmName(s.fm) .. ". Bytt flymodus.", SMLSIZE, L.C.warn)
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
      if s.shLabel or s.shBlocked then L.shNote(s.shLabel or s.shBlocked, "alle ror i senter", not s.shLabel) end
      local quick = s.quick and not def.select and #s.entries > 1
      local items = { { "Avbryt", cancel } }
      if not quick then
        items[#items + 1] = { "Tilbake", function() commit(); s.k = s.k - 1; setup() end,
          { enabled = s.k > 1 and not def.select } }
      end
      items[#items + 1] = { "Nullstill pot", function() s.base = s.val; L.dualStart(s.dual, true) end }
      -- Underskjerm (f.eks. Kalibrer i steg 4): denne skjermen rydder testmiksene først
      if def.extra and def.extra.show(s.st) then
        items[#items + 1] = { def.extra.label, function()
          commit()
          s:leave()
          local x = def.extra.screen()
          x.danger = s.danger
          L.push(x)
        end, { primary = false } }
      end
      if e.fm then
        items[#items + 1] = { "Kopier alle FM", function()
          commit()
          for _, fm in ipairs(S.usedFMs(s.st.cfg, s.prof)) do
            if not (e.skipFM and e.skipFM[fm]) then e.set(fm, s.val) end
          end
          W.saveState()
          L.toast("Kopiert til alle flymoduser")
        end }
      end
      local last = def.select or s.k == #s.entries
      if quick then
        if not last then items[#items + 1] = { "Bekreft", function() confirm() end, { primary = false } } end
        items[#items + 1] = { def.quickLabel or "Ferdig", function() confirm(true) end }
      else
        items[#items + 1] = { last and "Ferdig" or "Bekreft", function() confirm() end }
      end
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
    if v < 0 then return v .. " % (ned)" elseif v > 0 then return "+" .. v .. " % (opp)" end
    return "0 %"
  end

  ----------------------------------------------------------------------
  -- Steg 4: utslag per ror og side, vist med testmix

  function A.ratesScreen()
    local MAX = L.findSource({ "max", "MAX" })
    local chans = {}
    local function clearAll() for ch in pairs(chans) do L.tmpClear(ch) end end
    local def = { title = "4 - Utslag", doneText = "Utslag lagret", quickLabel = "Lagre og skriv" }
    function def.quick(st) return st.done.rates end

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
          hint = { "Roret står som ved " .. r.stick .. " fullt ut.", "Juster utslaget med potten. 100 % = endepunktet." },
          get = function() return S.rate(st, r.role, r.f, r.sd) end,
          set = function(_, v) st.rates[r.key] = v; show(v) end,
          prep = function() clearAll(); show(S.rate(st, r.role, r.f, r.sd)) end,
        }
      end
      return list
    end

    def.leave = clearAll
    def.extra = { label = "Kalibrer", screen = function() return A.calScreen() end,
      show = function(st) return #S.calPairs(st.cfg) > 0 end }

    function def.done(st, prof)
      clearAll()
      st.done.rates = true
      if st.done.mix then S.write(S.plan(st.cfg, prof, st), st) end   -- skriv mikserne med de nye utslagene
    end

    return A.adjustScreen(def)
  end

  ----------------------------------------------------------------------
  -- Kalibrering (fra steg 4): høyre ror mot samme ror på venstre side i 3 punkter
  -- hver vei (25, 50 og 75 % opp og ned). Begge rorene står i punktet med testmiks;
  -- potten retter høyre ror til det har samme utslag som venstre. Ligger som
  -- utgangskurve på høyre kanal, så alle mikser (rull, camber, crow) får rettelsen.

  function A.calScreen()
    local MAXS = L.findSource({ "max", "MAX" })
    local shown = {}
    local def = { title = "Kalibrer høyre side", doneText = "Kalibrering lagret", tmpNeed = 2 }
    function def.room(st)
      local t = {}
      for _, cp in ipairs(S.calPairs(st.cfg)) do t[#t + 1] = cp.l; t[#t + 1] = cp.r end
      return t
    end
    function def.quick(st) return st.done.cal end
    local function show(cp, x)
      for ch in pairs(shown) do
        if ch ~= cp.l.ch and ch ~= cp.r.ch then L.tmpClear(ch); shown[ch] = nil end
      end
      for _, c in ipairs({ cp.l, cp.r }) do
        if not L.setMix(c.ch, L.TMP, { weight = x }) then L.tmpClear(c.ch); L.tmpAdd(c.ch, MAXS, x, 0) end
        shown[c.ch] = true
      end
    end
    function def.leave()
      for ch in pairs(shown) do L.tmpClear(ch) end
      shown = {}
    end
    local function signed(v) return (v > 0 and "+" or "") .. v .. " %" end
    -- Rekkefølge: 25, 50, 75 opp, så 25, 50, 75 ned (indeks i S.CAL_X)
    local ORDER = { 4, 5, 6, 3, 2, 1 }
    function def.entries(st, prof)
      local list = {}
      for _, cp in ipairs(S.calPairs(st.cfg)) do
        local k = S.calValues(st, cp.r.role)
        for _, i in ipairs(ORDER) do
          local x = S.CAL_X[i]
          local dir = math.abs(x) .. " % " .. (x > 0 and "opp" or "ned")
          list[#list + 1] = {
            label = cp.r.name .. "  " .. dir, min = -S.CAL_MAX, max = S.CAL_MAX, span = 10, fine = 1,
            fmt = signed, roles = { cp.r.role, cp.l.role },
            hint = { cp.l.name .. " og " .. cp.r.name .. " står på " .. dir .. ".",
              "Juster " .. cp.r.name .. " til samme utslag som " .. cp.l.name .. "." },
            graph = function(v)
              local pts = { { -100, 0 } }
              for j, xj in ipairs(S.CAL_X) do
                if j == 4 then pts[#pts + 1] = { 0, 0 } end
                pts[#pts + 1] = { xj, j == i and v or k[j] }
              end
              pts[#pts + 1] = { 100, 0 }
              return pts, { active = i < 4 and i + 1 or i + 2, range = A.range(pts), cursor = x }
            end,
            get = function() return k[i] end,
            set = function(_, v) k[i] = v; S.applyCal(st, prof, cp) end,
            prep = function() show(cp, x) end,
          }
        end
      end
      return list
    end
    function def.done(st) st.done.cal = true end
    def.empty = "Ingen ror med venstre og høyre side."
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
    local def = { title = "Termikk / Speed per ror", tmpNeed = 6 }   -- alle vingerorene vises
    function def.room(st) return wingRoles(st.cfg) end
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
      for _, m in ipairs({ { fm = 4, name = "Termikk", k = "t" }, { fm = 3, name = "Speed", k = "s" } }) do
        if used[m.fm] then
          for _, ende in ipairs(cam and { "Max", "Min" } or { "Max" }) do
            local key = m.k .. ende
            for _, c in ipairs(wing) do
              local hint
              if not cam then
                hint = { "Fast camber i " .. m.name .. " (ingen kontroll).", "Roret viser verdien." }
              elseif ende == "Max" then
                hint = { cam.label .. " bak: mest utslag.", "Alle rorene viser sin maks." }
              else
                hint = { cam.label .. " fram: minst utslag. 0 = nøytral.", "Alle rorene viser sin min." }
              end
              list[#list + 1] = {
                label = c.name .. "  " .. m.name .. (ende == "Max" and " maks" or " min"),
                min = -100, max = 100, span = 50, fmt = updown, roles = { c.role }, hint = hint,
                graph = cam and function(v)
                  local k = st.adj.camber[c.role]
                  local mx = ende == "Max" and v or k[m.k .. "Max"]
                  local mn = ende == "Min" and v or k[m.k .. "Min"]
                  local pts, names, act = { { back, mx }, { -back, mn } }, { "Maks", "Min" }, ende == "Max" and 1 or 2
                  if back > 0 then pts = { pts[2], pts[1] }; names = { "Min", "Maks" }; act = 3 - act end
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
    def.empty = "Modellen bruker ikke Termikk eller Speed."
    return A.adjustScreen(def)
  end

  local function crowScreen()
    local def = { title = "Butterfly (crow)" }
    function def.entries(st, prof)
      local list = {}
      for _, c in ipairs(wingRoles(st.cfg)) do
        local flap = S.FLAPS[c.role] ~= nil
        -- Flaps går bare ned. Ailerons kan gå opp (+) eller ned (-) ved crow (Jo Grini 2026-11-09).
        list[#list + 1] = {
          label = c.name .. (flap and "  ned" or ""), min = flap and 0 or -100, max = 100, span = 50,
          fmt = not flap and updown or nil, roles = { c.role },
          hint = { "Trekk butterfly-kontrollen helt (full crow).", flap and "Flaps ned." or "Ailerons opp (+) eller ned (-)." },
          get = function() return st.adj.crow[c.role] end,
          set = function(_, v) st.adj.crow[c.role] = v; S.applyCrow(st, c.role) end,
        }
      end
      list[#list + 1] = {
        label = "Aileron ved full crow", min = 20, max = 100, span = 40, roles = AIL_ROLES,
        hint = { "Full crow og aileron-utslag.", "Hvor mye aileron som er igjen ved full crow." },
        get = function() return st.adj.crowRed end,
        set = function(_, v) st.adj.crowRed = v; S.writeCurve(st.cfg, prof, st, C.crowRed) end,
      }
      list[#list + 1] = {
        label = "Differensial ved full crow", min = 0, max = 100, span = 50, roles = AIL_ROLES,
        hint = { "Full crow og aileron-utslag.", "Ned-aileron i % av vanlig. 100 % = som uten crow." },
        fmt = function(v) return v .. " % ned" end,
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
    local def = { title = "Høyderor ved butterfly", doneText = "Kurven er lagret" }
    function def.entries(st, prof)
      crowC = prof.crow and L.ctrl(prof.crow.ctrl)
      if not (crowC and crowC.id) then return {} end
      local list = {}
      for i = 1, 7 do
        list[i] = {
          label = "Punkt " .. i .. "  (" .. crowC.label .. " " .. XS[i] .. " %)", min = -100, max = 100, span = 50,
          fmt = updown, roles = ELEV_ROLES,
          graph = function(v)
            local pts = {}
            for j = 1, 7 do pts[j] = { XS[j], j == i and v or st.adj.eleComp[j] } end
            return pts, { active = i, range = A.range(pts), cursor = L.value(crowC) / 10.24 }
          end,
          hint = { "Flytt " .. crowC.label .. " til punktene. Potten justerer", "høyderoret i punktet stikka står i." },
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

  -- Høyderor ved butterfly i lufta (Stig 2026-11-09): butterfly-stikka velger punktet (samme
  -- 7 punkter som kurven), høyderorsstikka holder flyet i rett flukt, og et kort klikk på
  -- testbryteren (SH) legger stikkeutslaget inn i punktet. Langt trykk (over 1 s) angrer
  -- siste lagring. Stemmen sier punktet og «lagret», så skjermen trenger ikke leses i lufta.
  -- Ingen testmikser og ingen SH-senter: skjermen er trygg å ha åpen i lufta.
  local AIR = {
    near = 10,       -- % fra punktet på butterfly-stikka
    window = 50,     -- stikka midles over 0,5 s før klikket (getTime: 10 ms)
    steady = 5,      -- % største variasjon i vinduet
    maxStep = 15,    -- % største endring per klikk
    long = 100,      -- langt trykk = angre (1 s)
  }
  function A.eleAirScreen()
    local s = { hist = {}, undo = {} }
    local function snd(n) playFile("/SOUNDS/en/" .. n .. ".wav") end

    -- Rorets utslag per side for høyderorsstikka (V-hale: snittet av de to sidene)
    local function rate(sd)
      local roles = s.st.cfg.tail == "V" and { "vL", "vR" } or { "elev" }
      local sum = 0
      for _, r in ipairs(roles) do sum = sum + S.rate(s.st, r, "ele", sd) end
      return sum / #roles
    end
    -- Hva stikka (x i -1..1) gir på høyderorskanalen i %, med expo som i miksene.
    -- Ele-miksene har vekt -utslag (negativ = ror ned), og kurven EKo legges til med vekt 100.
    function s.delta(x)
      local e = (s.st.adj.expo and s.st.adj.expo.ele) or 0
      local xe = S.expo(x, -e)
      return -xe * rate(xe > 0 and 1 or -1)
    end

    local function point()
      if not (s.crow and s.crow.id) then return nil end
      local x = L.value(s.crow) / 10.24
      for i, p in ipairs(XS) do if math.abs(x - p) <= AIR.near then return i end end
      return nil
    end

    -- Snittet av stikka i vinduet før t, eller nil hvis den ikke har stått i ro
    local function steadyAvg(t)
      local n, sum, lo, hi = 0, 0, 2, -2
      for _, h in ipairs(s.hist) do
        if h[1] <= t and h[1] >= t - AIR.window then
          n = n + 1; sum = sum + h[2]; lo = math.min(lo, h[2]); hi = math.max(hi, h[2])
        end
      end
      if n < 3 or (hi - lo) * 100 > AIR.steady then return nil end
      return sum / n
    end

    local function write()
      S.writeCurve(s.st.cfg, s.prof, s.st, C.eleComp)
      W.saveState()
    end

    local function save(t)
      local k = s.pt
      if not k then snd("ikkpkt"); return end
      local x = steadyAvg(t)
      if not x then snd("urolig"); return end
      local d = L.clamp(L.round(s.delta(x)), -AIR.maxStep, AIR.maxStep)
      local comp = s.st.adj.eleComp
      s.undo[#s.undo + 1] = { k, comp[k] }
      comp[k] = L.clamp(comp[k] + d, -100, 100)
      write()
      s.last = { k = k, d = d }
      snd("lagrok")
    end

    local function undo()
      local u = table.remove(s.undo)
      if not u then return end
      s.st.adj.eleComp[u[1]] = u[2]
      write()
      s.last = nil
      snd("angret")
    end
    s.undoLast = undo

    function s:enter()
      s.st = W.state()
      s.prof = W.profile() or {}
      S.defaults(s.st)
      s.crow = s.prof.crow and L.ctrl(s.prof.crow.ctrl)
      s.test = s.prof.test and L.ctrl(s.prof.test.ctrl)
      s.ele = L.ctrl("ele") or { id = L.findSource({ "ele", "Ele", "ELE" }) }
    end

    function s:tick()
      local now = getTime()
      local x = (s.ele and s.ele.id) and getValue(s.ele.id) / 1024 or 0
      s.x = x
      s.hist[#s.hist + 1] = { now, x }
      while #s.hist > 0 and s.hist[1][1] < now - 2 * AIR.window do table.remove(s.hist, 1) end
      local k = point()
      if k ~= s.pt then
        s.pt = k
        if k then snd("pkt" .. k) end
      end
      -- SH: kort klikk = lagre (stikka før trykket), langt trykk = angre
      local on = s.test and s.test.id and L.value(s.test) > 0
      if on and not s.down then s.down, s.longDone = now, false end
      if on and s.down and not s.longDone and now - s.down >= AIR.long then s.longDone = true; undo() end
      if not on and s.down then
        if not s.longDone then save(s.down) end
        s.down = nil
      end
    end

    function s:draw(list)
      local G = W.G
      L.header("Høyderor ved butterfly i lufta", fmName(currentFM()))
      if not (s.crow and s.crow.id and s.test and s.test.id) then
        L.text(20, 70, "Mangler butterfly-kontroll eller testbryter i pilotoppsettet.")
        L.btnRow(list, { { "Tilbake", function() L.pop() end } })
        return
      end
      local comp = s.st.adj.eleComp
      L.text(20, 60, s.pt and ("Punkt " .. s.pt .. "  (" .. s.crow.label .. " " .. XS[s.pt] .. " %)") or "Ikke på punkt",
        DBLSIZE, s.pt and L.C.act or L.C.dim)
      if s.pt then L.text(20, 112, "Kurve nå: " .. updown(comp[s.pt]), MIDSIZE) end
      L.text(20, 150, "Stikka gir nå: " .. updown(L.clamp(L.round(s.delta(s.x or 0)), -AIR.maxStep, AIR.maxStep)), 0, L.C.text)
      if s.last then
        L.text(20, 180, "Lagret: punkt " .. s.last.k .. " " .. updown(s.last.d), 0, L.C.ok)
      end
      L.text(20, 222, "1. Trekk " .. s.crow.label .. " til et punkt (radioen sier punktet).", SMLSIZE, L.C.dim)
      L.text(20, 244, "2. Hold flyet i rett flukt med høyderorsstikka.", SMLSIZE, L.C.dim)
      L.text(20, 266, "3. Kort klikk " .. s.test.label .. ": lagres. Slipp stikka.", SMLSIZE, L.C.dim)
      L.text(20, 288, "Langt trykk " .. s.test.label .. " (1 s): angre. Maks " .. AIR.maxStep .. " % per klikk.", SMLSIZE, L.C.dim)
      L.text(20, 318, "Grov forskyvning: høyderorstrimmen i Landing.", SMLSIZE, L.C.dim)
      local pts = {}
      for j = 1, 7 do pts[j] = { XS[j], comp[j] } end
      G.curve(440, 120, 340, 200, pts, { active = s.pt, range = A.range(pts), cursor = L.value(s.crow) / 10.24 })
      L.btnRow(list, { { "Angre", undo, { enabled = #s.undo > 0, primary = false } },
        { "Ferdig", function() L.toast("Kurven er lagret"); L.pop() end } })
    end

    return s
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
    local def = { title = "Kikkflapp" }
    local st0
    function def.entries(st, prof)
      st0 = st
      local list = {}
      for _, c in ipairs(wingRoles(st.cfg, function(r) return S.FLAPS[r] or r == "ailL" or r == "ailR" end)) do
        list[#list + 1] = {
          label = "Maks kikkflapp " .. c.name, min = 0, max = V.snapShareMax, span = V.snapShareMax / 2,
          roles = { c.role },
          hint = { "Trekk høyderoret helt opp.", "Juster roret til maks kikkflapp." },
          get = function() return st.adj.snapShare[c.role] end,
          set = function(_, v) st.adj.snapShare[c.role] = v; S.applySnapShare(st, prof, c.role) end,
          prep = function() S.snapFull(st, true) end,
        }
      end
      list[#list + 1] = {
        label = "Kikkflapp i flymodus", fm = true, min = 0, max = 100, span = 50, roles = FLAP_ROLES,
        skipFM = S.SNAP_SKIP, fmt = function(v) return v .. " % av maks" end,
        hint = { "Trekk høyderoret helt opp.", "0 % = ingen kikkflapp i denne flymodusen." },
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
    local def = { title = "Motor", doneText = "Motor lagret" }
    function def.entries(st, prof)
      if not st.cfg.motor then return {} end
      local pw = prof.motor_pwr and L.ctrl(prof.motor_pwr.ctrl)
      local list = {}
      local warn = "HOLD FLYET. Hold deg unna propellen."
      for i, n in ipairs({ "Liten", "Medium", "Full" }) do
        list[#list + 1] = {
          label = "Motor " .. n, min = 0, max = 100, span = 50,
          hint = { (pw and ("Sett " .. pw.label .. " til " .. n .. ", ") or "") .. "motorbryter på.", warn },
          get = function() return st.adj.motor[i] end,
          set = function(_, v) st.adj.motor[i] = v; S.writeCurve(st.cfg, prof, st, C.motor) end,
        }
      end
      list[#list + 1] = {
        label = "Motor -> høyderor", min = -30, max = 30, span = 15, fmt = updown, roles = ELEV_ROLES,
        hint = { "Høyderor ved full motor (+ = opp).", "Skaleres med motorkraften." },
        get = function() return st.adj.motorEle end,
        set = function(_, v) st.adj.motorEle = v; S.applyMotorEle(st) end,
      }
      return list
    end
    def.empty = "Modellen har ikke motor (steg 0)."
    return A.adjustScreen(def)
  end

  -- Overgang mellom flymoduser: hvor lang tid det tar å gå over til (og ut av) flymodusen.
  -- Normal, Termikk, Speed og motor (felles). Landing og Launch er faste.
  local function fadeScreen()
    local def = { title = "Overgang mellom flymoduser", noSH = true }
    function def.entries(st, prof)
      local used = {}
      for _, fm in ipairs(S.usedFMs(st.cfg, prof)) do used[fm] = true end
      for _, fm in ipairs(S.motorFMs(st.cfg, prof)) do used[fm] = true end
      local fmt = function(v) return string.format("%.1f s", v / 10) end
      local list = {}
      local function entry(g, key, label, hint)
        list[#list + 1] = {
          label = label, min = 0, max = V.fadeMax, span = V.fadeMax / 2, fine = 1, fmt = fmt, hint = hint,
          get = function() return st.adj[key][g.key] end,
          set = function(_, v) st.adj[key][g.key] = v; S.applyFade(st, prof, g.key) end,
        }
      end
      for _, g in ipairs(S.FADE_GROUPS) do
        if used[g.fms[1]] then
          entry(g, "fadeIn", "Inn til " .. g.name, { "Tiden det tar å gå over til " .. g.name .. ".",
            "0 = straks, maks 3 s. Prøv med flymodusbryteren." })
          entry(g, "fadeOut", "Ut av " .. g.name, { "Tiden det tar å gå ut av " .. g.name .. ".",
            "Overgang A til B: ut av A og inn til B." })
        end
      end
      return list
    end
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
        side("afDown", -1, "Ail -> Flap ned", { "Begge flaps viser ned-utslaget nå.", "I % av flappens utslag ned." }),
        side("afUp", 1, "Ail -> Flap opp", { "Begge flaps viser opp-utslaget nå.", "I % av flappens utslag opp." }),
        {
          label = "Ail -> Flap i flymodus", fm = true, min = 0, max = 150, span = 50, roles = FLAP_ROLES,
          fmt = function(v) return v .. " % av ned/opp" end,
          hint = { "Gi full aileron og se på flapsene.", "100 % = utslaget satt i ned og opp. 0 % = av." },
          get = function(fm) return st.adj.afFM[fm] or 0 end,
          set = function(fm, v) st.adj.afFM[fm] = v; S.applyPerFM(st, "afFM", fm) end,
          prep = function() show(nil) end,
        },
      }
    end
    return A.adjustScreen(def)
  end

  -- Differensial-trim og expo (bestemt 2026-10-29). Differensial: hvor mye av utslaget ned trimmen kan endre.
  -- Aileron med T3 (egen verdi per FM), V-hale (sideroret) med T5 (lik i alle FM).
  local function diffScreen()
    local def = { title = "Differensial og expo", doneText = "Differensial og expo lagret" }
    local trims = {}
    function def.entries(st, prof)
      local list = {}
      local function entry(kind, key, pf, label, roles, what)
        local t = pf and pf.trim
        local id = t and L.trimSource(t)
        if not id then return end
        trims[kind] = { label = t, id = id }
        list[#list + 1] = {
          label = label, min = 0, max = 100, span = 50, roles = roles, kind = kind,
          fmt = function(v) return v .. " % av utslaget" end,
          hint = { t .. " fullt ut endrer " .. what .. " ned med så", "mye, den ene eller andre veien. Standard " .. V[key] .. " %." },
          get = function() return st.adj[key] end,
          set = function(_, v) st.adj[key] = v; S.applyDiff(st, prof, kind) end,
        }
      end
      entry("ail", "diffTrim", prof.difftrim, "Aileron-differensial", { "ailL", "ailR" }, "aileron")
      if st.cfg.tail == "V" then
        entry("rud", "vdiffTrim", prof.vdifftrim, "V-hale-differensial", { "vL", "vR" }, "sideroret")
      end
      -- Expo, lik i alle FM: negativ = mykt rundt senter (butterfly: mykt i starten av crow)
      local function expo(f, label, roles, crow)
        list[#list + 1] = {
          label = label, min = -100, max = 100, span = 50, roles = roles,
          fmt = function(v)
            if v == 0 then return "0 % (lineær)" end
            return v .. " %" .. (v < 0 and " (mykt " or " (hardt ") .. (crow and "i starten)" or "senter)")
          end,
          hint = crow and { "Negativ = mykt i starten av crow,", "positiv = mer crow tidlig. Full crow er lik." }
            or { "Negativ = mykt rundt senter av stikka,", "positiv = hardere. Fullt utslag er likt." },
          -- Grafen: utslag over stikka (butterfly: fra crow av til full crow)
          graph = function(v)
            local pts = {}
            for i = 0, 8 do
              local x = crow and i / 8 or (i - 4) / 4
              pts[#pts + 1] = { L.round(crow and (x * 200 - 100) or x * 100), L.round(100 * S.expo(x, -v)) }
            end
            return pts, { range = 100, cursor = not crow and (getValue(f) or 0) / 10.24 or nil }
          end,
          get = function() return st.adj.expo[f] end,
          set = function(_, v) st.adj.expo[f] = v; S.applyExpo(st, prof, f) end,
        }
      end
      expo("ail", "Expo aileron", { "ailL", "ailR" })
      expo("ele", "Expo høyderor", ELEV_ROLES)
      expo("rud", "Expo sideror", RUD_ROLES)
      if prof.crow and L.ctrl(prof.crow.ctrl) then
        expo("crow", "Expo butterfly", { "ailL", "ailR", "flapL", "flapR" }, true)
      end
      return list
    end
    -- Trimmen nå og hvor mye den endrer ned-utslaget med verdien som stilles
    function def.info(s, e, x, y)
      local t = trims[e.kind]
      if not t then return end
      local tr = L.round((getValue(t.id) or 0) / 10.24)
      L.text(x, y, t.label .. " nå: " .. tr .. " %  =  " .. L.round(tr * s.val / 100) .. " % av utslaget ned", SMLSIZE)
    end
    def.empty = "Velg trimknapp for differensial i pilotoppsettet."
    return A.adjustScreen(def)
  end

  function A.menuScreen()
    local s = {}
    -- 4. felt: farlig i lufta (testmikser låser rorene, eller hele oppsettet kan skrives på nytt)
    local items = {
      { "Termikk / Speed per ror", camberScreen, nil, true },
      { "Butterfly (crow)", crowScreen },
      { "Høyderor ved butterfly (kurve)", eleCompScreen, nil, true },
      { "Høyderor ved butterfly i lufta", A.eleAirScreen },
      { "Aileron -> sideror (per FM)", function()
        return perFMScreen("ailRud", "Aileron -> sideror", "Ail -> Rud", { "Gi aileron og se på sideroret." }, 100,
          nil, RUD_ROLES)
      end },
      { "Kikkflapp (per FM)", snapScreen },
      { "Differensial og expo", diffScreen, nil, true },
      { "Aileron -> flaps (per FM)", ailFlapScreen, function(st) return st.cfg.wing >= 4 end, true },
      { "Motor: nivå og høyderor", motorScreen, function(st) return st.cfg.motor end },
      { "Overgang mellom flymoduser", fadeScreen },
    }

    function s:enter()
      s.st = W.state()
      s.prof = W.profile() or {}
      W.upgrade()
    end

    local function trimName(pf) return (pf and pf.trim) or "-" end
    local function open(it) return function() local x = it[2](); x.danger = it[4]; L.push(x) end end

    function s:draw(list)
      L.header("6 - Justering", fmName(currentFM()))
      local lock = W.locked()
      for i, it in ipairs(items) do
        local en = (not it[3] or it[3](s.st)) and not (lock and it[4])
        L.btn(list, 20, 56 + (i - 1) * 31, 500, 28, it[1], en and open(it) or nil, { left = true, icon = true })
      end
      if lock then
        L.text(540, 214, "Sperret etter motor:", SMLSIZE, L.C.warn)
        L.text(540, 238, "motorbryter av og", SMLSIZE, L.C.warn)
        L.text(540, 262, "stikkene i ro i 15 s.", SMLSIZE, L.C.warn)
      end
      L.text(540, 62, "Differensial:", SMLSIZE, L.C.dim)
      local prof = s.prof or {}
      L.text(540, 86, "Trim i lufta: Ail " .. trimName(prof.difftrim) .. " egen per FM,", SMLSIZE, L.C.dim)
      if s.st.cfg and s.st.cfg.tail == "V" then
        L.text(540, 110, "V-hale " .. trimName(prof.vdifftrim) .. " lik i alle FM.", SMLSIZE, L.C.dim)
      end
      L.text(540, 150, "Per FM: bytt flymodus med", SMLSIZE, L.C.dim)
      L.text(540, 174, "bryteren mens du justerer.", SMLSIZE, L.C.dim)
      L.btnRow(list, { { "Tilbake", function() L.pop() end } })
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
      L.header("ESC-kalibrering", "CH" .. mch)
      local t
      if s.step == 0 then
        t = { "TA AV PROPELLEN før du starter.", "Flybatteriet skal være frakoblet.",
              "Start: kanalen går til FULL Throttle (1998 us). Null Throttle er 1003 us." }
      elseif s.step == 1 then
        t = { "Full Throttle sendes nå.", "Koble til flybatteriet og vent på pipene fra ESC-en.", "Trykk Neste for null Throttle." }
      else
        t = { "Null Throttle sendes nå.", "Vent på pipene som bekrefter kalibreringen.", "Trykk Ferdig." }
      end
      for i, x in ipairs(t) do L.text(20, 70 + (i - 1) * 36, x, 0, (s.step == 0 and i == 1) and L.C.warn or L.C.text) end
      L.text(20, 200, "Prosedyren varierer mellom ESC-er. Sjekk manualen til din.", SMLSIZE, L.C.dim)
      L.text(20, 226, "Er motorsperren aktiv (Landing), sender CH" .. mch .. " -100 % uansett.", SMLSIZE, L.C.dim)
      local items = { { "Avbryt", cancel } }
      if s.step == 0 then
        items[2] = { "Start (full Throttle)", function()
          L.setOutput(mch - 1, { min = V.motorMin, max = V.motorMax, ppmCenter = 0 })
          set(100)
          s.step = 1
        end }
      elseif s.step == 1 then
        items[2] = { "Neste (null Throttle)", function() set(-100); s.step = 2 end }
      else
        items[2] = { "Ferdig", function()
          set(nil)
          s.st.done.esc = true
          W.saveState()
          L.toast("ESC kalibrert")
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
    { "bind", "Mottaker bundet (ELRS)" },
    { "range", "Rekkeviddetest gjort" },
    { "fullres", "ELRS 4: 100Hz Full, 8ch" },
    { "telem", "ELRS: Telem Ratio er ikke Race" },
    { "bindsto", "ELRS RX: Bind Storage = Persistent" },
    { "arm", "Arm using: Switch, ON (CH5 blir vanlig)" },
    { "ext", "Extended limits på (MODEL SETUP)" },
    { "failsafe", "Failsafe: Custom, motor -100 %, ror nøytrale" },
    { "swwarn", "Throttle-advarsel av, motorbryter Off ved start" },
    { "sounds", "Lydfilene ligger i /SOUNDS/<språk>/" },
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
      L.header("7 - Sjekkliste", A.checkDone(s.st) .. " / " .. #A.CHECKS)
      for i, c in ipairs(A.CHECKS) do
        local on = s.st.check[c[1]]
        L.btn(list, 20, 56 + (i - 1) * 35, 520, 32, (on and "[x]  " or "[ ]  ") .. c[2], function()
          s.st.check[c[1]] = not s.st.check[c[1]] or nil
          W.saveState()
        end, { left = true, color = on and L.C.off or nil })
      end
      L.text(560, 60, "Telemetri", 0, L.C.dim)
      L.text(560, 92, "RQly: " .. tele("RQly") .. " %", SMLSIZE)
      L.text(560, 118, "1RSS: " .. tele("1RSS") .. " dB", SMLSIZE)
      L.text(560, 144, "RxBt: " .. tele("RxBt") .. " V", SMLSIZE)
      L.text(560, 180, s.st.alarms and "Alarmer: lagt inn" or "Alarmer: ikke lagt inn", SMLSIZE,
        s.st.alarms and L.C.ok or L.C.dim)
      L.btnRow(list, {
        { "Tilbake", function() L.pop() end, { default = true } },
        { "Legg inn alarmer", function()
          if not L.findSource({ "RQly" }) and not L.findSource({ "RxBt" }) then
            L.toast("Ingen telemetri ennå. Bind og slå på mottakeren.", true)
            return
          end
          s.st.alarms = true
          local _, bad = S.write(S.plan(s.st.cfg, W.profile(), s.st), s.st)
          W.saveState()
          L.toast(bad == 0 and "Alarmer lagt inn" or "Feil ved skriving, se steg 5", bad ~= 0)
        end, { enabled = s.st.done.mix == true } },
      })
    end

    return s
  end

  return A
end
