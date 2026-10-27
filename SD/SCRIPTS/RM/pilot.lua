-- Steg P: pilotoppsett. Piloten velger brytere ved å flippe dem (skisse K),
-- og ser over og endrer valgene før profilen lagres (skisse K2).
-- Én pilotprofil per radio, lagret i /SCRIPTS/RM/DATA/pilot.lua.

return function(L, STD)
  local lcd = L.lcd   -- skalert på mindre skjermer (scale.lua)
  local P = {}
  local FILE = "pilot.lua"
  P.FUNCS = STD.funcs

  local function byKey(key)
    for _, f in ipairs(P.FUNCS) do
      if f.key == key then return f end
    end
  end

  function P.load() return L.load(FILE) end
  function P.save(p) return L.save(FILE, p) end

  function P.defaults()
    local p = {}
    for _, f in ipairs(P.FUNCS) do p[f.key] = L.copy(f.default or { none = true }) end
    return p
  end

  -- Kanalene til rorene fra std.lua (før piloten har endret noe)
  local CH_DEFAULT = {}
  for _, r in ipairs(STD.chRoles) do CH_DEFAULT[r.key] = STD.ch[r.key] end
  function P.channelDefaults() return L.copy(CH_DEFAULT) end

  -- Gamle profiler mangler kanskje nye funksjoner eller kanaler: fyll inn standard
  function P.complete(p)
    for _, f in ipairs(P.FUNCS) do
      if not p[f.key] then p[f.key] = L.copy(f.default or { none = true }) end
    end
    p.ch = p.ch or {}
    for k, v in pairs(CH_DEFAULT) do if not p.ch[k] then p.ch[k] = v end end
    return p
  end

  -- Pilotens kanaler gjelder hele veiviseren: skriv dem inn i STD.ch.
  -- V-hale bruker kanalene til Elev og Rud.
  function P.applyChannels(p)
    local m = (p and p.ch) or CH_DEFAULT
    for k, v in pairs(CH_DEFAULT) do STD.ch[k] = m[k] or v end
    STD.ch.vL, STD.ch.vR = STD.ch.elev, STD.ch.rud
  end

  -- Kort tekst som endres når kanalene endres (for å se om modellen må settes opp på nytt)
  function P.channelSig(p)
    local t = {}
    for _, r in ipairs(STD.chRoles) do t[#t + 1] = (p.ch and p.ch[r.key]) or CH_DEFAULT[r.key] end
    return table.concat(t, ",")
  end

  -- Ror som deler kanal (ingen kan dele)
  function P.channelClash(p)
    local seen, clash = {}, {}
    for _, r in ipairs(STD.chRoles) do
      local c = p.ch[r.key]
      if seen[c] then clash[r.key] = true; clash[seen[c]] = true else seen[c] = r.key end
    end
    return clash
  end

  local function accepts(f, c)
    for _, t in ipairs(f.accept or {}) do
      if t == c.type then return true end
    end
    return false
  end

  local function acceptText(f)
    if f.kind == "trim" then return "Trimknapp" end
    local t = {}
    for _, a in ipairs(f.accept or {}) do t[#t + 1] = L.TYPE_LABEL[a] end
    local s = table.concat(t, ", ")
    if f.auto then s = s .. " eller automatisk" end
    if f.optional then s = s .. " (valgfri)" end
    return s
  end

  function P.describe(f, a)
    if not a or a.none then return "Ikke i bruk" end
    if a.auto then return "Auto (crow)" end
    if a.trim then return a.trim end
    local c = L.ctrl(a.ctrl)
    local name = c and c.label or tostring(a.ctrl)
    if a.pos then return name .. " " .. L.POS[a.pos] end
    if a.rev then return name .. " (snudd)" end
    return name
  end

  -- Returnerer navnet på funksjonen som allerede bruker kontrollen, eller nil.
  -- Flymoduser kan dele bryter, men ikke posisjon. Funksjoner som bare brukes i
  -- veiviseren (wizard) kan dele med alt unntatt justeringspotten.
  function P.conflict(p, f, a)
    if not a or not a.ctrl then return nil end
    for _, g in ipairs(P.FUNCS) do
      local b = p[g.key]
      local shared = (f.wizard or g.wizard) and f.key ~= "adjust" and g.key ~= "adjust"
      if g.key ~= f.key and b and b.ctrl == a.ctrl and not shared then
        if not (f.fm and g.fm) or b.pos == a.pos then return g.label end
      end
    end
    return nil
  end

  -- Flymoduser på ulike brytere kan være på samtidig: lavest FM-nummer vinner
  function P.warnings(p)
    local w = {}
    local fms = { "landing", "launch", "speed", "thermal" }
    for i = 1, #fms do
      for j = i + 1, #fms do
        local a, b = p[fms[i]], p[fms[j]]
        if a and b and a.ctrl and b.ctrl and a.ctrl ~= b.ctrl then
          local fa, fb = byKey(fms[i]), byKey(fms[j])
          w[#w + 1] = fb.label .. " og " .. fa.label .. " kan være på samtidig: " .. fa.label .. " vinner"
        end
      end
    end
    return w
  end

  local function endName(f, a, v)
    if not f.ends then return nil end
    if a.rev then v = -v end
    if v < -300 then return f.ends[1] elseif v > 300 then return f.ends[2] end
    return "midt"
  end

  ----------------------------------------------------------------------
  -- Skisse K: velg kontroll for én funksjon om gangen

  function P.selectScreen(prof, startIdx, single, onDone)
    local s = { idx = startIdx or 1 }
    local function fn() return P.FUNCS[s.idx] end

    local function rebase()
      s.base = {}
      for _, c in ipairs(L.CONTROLS) do
        if c.id then s.base[c.key] = L.value(c) end
      end
      s.det = nil
      s.warn = nil
      s.cur = L.copy(prof[fn().key] or { none = true })
    end

    local function finish()
      L.pop()
      if onDone then onDone() end
    end

    local function commit()
      local f = fn()
      if (not s.cur or s.cur.none) and not f.optional then
        L.toast(f.label .. " må ha en kontroll", true)
        return
      end
      local c = P.conflict(prof, f, s.cur)
      if c then
        L.toast("Allerede brukt til " .. c, true)
        return
      end
      prof[f.key] = L.copy(s.cur)
      if single or s.idx >= #P.FUNCS then
        finish()
      else
        s.idx = s.idx + 1
        rebase()
      end
    end

    function s:enter() rebase() end

    function s:tick()
      local f = fn()
      if f.kind == "trim" then return end
      local best, bestD
      for _, c in ipairs(L.CONTROLS) do
        local b = c.id and s.base[c.key]
        if b then
          local d = math.abs(L.value(c) - b)
          local thr = (c.type == "pot" or c.type == "slider" or c.type == "stick") and 300 or 600
          if d > thr and (not bestD or d / thr > bestD) then best, bestD = c, d / thr end
        end
      end
      if best then
        for _, c in ipairs(L.CONTROLS) do
          if c.id then s.base[c.key] = L.value(c) end
        end
        if accepts(f, best) then
          s.det = best
          s.warn = nil
          s.cur = { ctrl = best.key }
          if f.kind == "axis" then s.cur.rev = false end
        else
          s.warn = best.label .. " (" .. L.TYPE_LABEL[best.type] .. ") passer ikke her"
        end
      end
      -- Bryterposisjonen følger bryteren etter at den er oppdaget
      if s.det and f.kind == "pos" then s.cur.pos = L.pos(L.value(s.det)) end
      if s.det then
        local c = P.conflict(prof, f, s.cur)
        if c then s.warn = s.det.label .. " er allerede brukt til " .. c end
      end
    end

    local function drawPositions(f, c, x, y)
      local v = L.value(c)
      local p = L.pos(v)
      local list
      if c.type == "3pos" then list = { -1, 0, 1 } else list = { -1, 1 } end
      for i, q in ipairs(list) do
        local bx = x + (i - 1) * 150
        local lit = (q == p)
        lcd.drawFilledRectangle(bx, y, 140, 40, lit and L.C.act or L.C.off)
        local label = L.POS[q]
        if f.kind == "axis" and f.ends then
          local a = s.cur or {}
          label = endName(f, a, q * 1000)
          if label == "midt" then label = "Medium" end
        end
        L.text(bx + 70, y + 9, label, CENTER)
      end
    end

    function s:draw(list)
      local f = fn()
      L.header("Steg P - Pilotoppsett", s.idx .. " / " .. #P.FUNCS)

      -- Venstre: alle funksjoner
      for i, g in ipairs(P.FUNCS) do
        local y = 56 + (i - 1) * 27
        local a = (i == s.idx) and s.cur or prof[g.key]
        if i == s.idx then lcd.drawFilledRectangle(4, y - 2, 296, 26, L.C.focus) end
        L.text(10, y, g.label, SMLSIZE)
        L.text(295, y, P.describe(g, a), SMLSIZE + RIGHT, (i < s.idx or single) and L.C.ok or L.C.dim)
      end

      -- Høyre: aktiv funksjon
      local x = 320
      L.text(x, 58, f.label, MIDSIZE)
      L.text(x, 96, "Godtar: " .. acceptText(f), SMLSIZE, L.C.dim)
      if f.kind == "trim" then
        L.text(x, 130, "Velg trimknapp med knappene under.")
        L.text(x, 175, "Valgt: " .. (s.cur.trim or "-"), MIDSIZE)
      else
        L.text(x, 130, "Flipp bryteren, eller vri potten/skyveren,")
        L.text(x, 155, "som skal brukes til denne funksjonen.")
        local c = s.det or (s.cur and L.ctrl(s.cur.ctrl))
        if s.det then
          L.text(x, 195, "Oppdaget: " .. s.det.label .. " - " .. L.TYPE_LABEL[s.det.type], 0, L.C.ok)
        else
          L.text(x, 195, "Valgt: " .. P.describe(f, s.cur))
        end
        if c and c.id then
          if c.type == "3pos" or c.type == "2pos" or c.type == "mom" then
            drawPositions(f, c, x, 230)
            if f.kind == "pos" then
              L.text(x, 280, "Sett bryteren i posisjonen som skal aktivere funksjonen.", SMLSIZE, L.C.dim)
            end
          else
            local v = L.value(c)
            local pct = L.round(v / 10.24)
            local e = s.cur and endName(f, s.cur, v)
            L.text(x, 235, "Nå: " .. pct .. " %" .. (e and ("  = " .. e) or ""), MIDSIZE)
            if f.ends then
              L.text(x, 280, "Sjekk at endene stemmer. Ellers: Snu retning.", SMLSIZE, L.C.dim)
            end
          end
        end
      end
      if s.warn then L.text(x, 320, s.warn, 0, L.C.warn) end

      -- Knapper
      local items = {}
      items[#items + 1] = { "Tilbake", function()
        if not single and s.idx > 1 then s.idx = s.idx - 1; rebase() else L.pop() end
      end }
      items[#items + 1] = { "Standard", function()
        s.cur = L.copy(f.default or { none = true }); s.det = nil; s.warn = nil
      end }
      if f.kind == "trim" then
        local function step(d)
          local i = 3
          for k, t in ipairs(L.TRIMS) do if t == s.cur.trim then i = k end end
          i = (i - 1 + d) % #L.TRIMS + 1
          s.cur = { trim = L.TRIMS[i] }
        end
        items[#items + 1] = { "< Trim", function() step(-1) end }
        items[#items + 1] = { "Trim >", function() step(1) end }
      end
      if f.auto then
        items[#items + 1] = { "Automatisk", function() s.cur = { auto = true }; s.det = nil; s.warn = nil end }
      end
      if f.optional then
        items[#items + 1] = { "Ikke i bruk", function() s.cur = { none = true }; s.det = nil; s.warn = nil end }
      end
      if f.kind == "axis" then
        items[#items + 1] = { "Snu retning", function() s.cur.rev = not s.cur.rev end,
          { enabled = s.cur ~= nil and s.cur.ctrl ~= nil } }
      end
      items[#items + 1] = { (single or s.idx == #P.FUNCS) and "Ferdig" or "Neste", commit }
      L.btnRow(list, items)
      -- Rullehjulet starter på «Neste»
      if not s.focusSet then s.focus = #list; s.focusSet = true end
    end

    return s
  end

  ----------------------------------------------------------------------
  -- Kanaloppsett: hvilken kanal hvert ror og motoren går på. Trykk på en rad = neste
  -- kanal (rundt til CH1 etter chMax). Ror som deler kanal vises rødt, og da kan
  -- profilen ikke lagres.

  function P.channelScreen(prof)
    local s = {}
    P.complete(prof)
    local work = L.copy(prof.ch)

    function s:draw(list)
      L.header("Pilotoppsett - kanaler", "trykk på en rad for neste kanal")
      local tmp = { ch = work }
      local clash = P.channelClash(tmp)
      local n = #STD.chRoles
      local half = math.ceil(n / 2)
      for i, r in ipairs(STD.chRoles) do
        local col = (i <= half) and 0 or 1
        local row = (i <= half) and (i - 1) or (i - 1 - half)
        L.btn(list, 10 + col * 395, 58 + row * 50, 385, 44, r.label, function()
          work[r.key] = work[r.key] % STD.chMax + 1
        end, { left = true, right = "CH" .. work[r.key], warn = clash[r.key] })
      end
      local y = 58 + half * 50 + 6
      if next(clash) then
        L.text(15, y, "To ror har samme kanal (rødt). Endre før du lagrer.", SMLSIZE, L.C.warn)
      else
        L.text(15, y, "Gjelder alle modellene. Etter endring: kjør veiviseren (0-5) på nytt.", SMLSIZE, L.C.dim)
      end
      L.btnRow(list, {
        { "Avbryt", function() L.pop() end },
        { "Standard", function() work = P.channelDefaults() end },
        { "OK", function() prof.ch = L.copy(work); L.pop() end, { enabled = next(clash) == nil } },
      })
    end

    return s
  end

  ----------------------------------------------------------------------
  -- Skisse K2: oversikt, trykk på en rad for å endre, «Lagre profil»

  function P.overviewScreen(prof, onSaved)
    local s = {}

    function s:draw(list)
      L.header("Pilotoppsett - oversikt", "trykk på en rad for å endre")
      local n = #P.FUNCS
      local half = math.ceil(n / 2)
      for i, f in ipairs(P.FUNCS) do
        local col = (i <= half) and 0 or 1
        local row = (i <= half) and (i - 1) or (i - 1 - half)
        L.btn(list, 10 + col * 395, 58 + row * 42, 385, 38, f.label,
          function() L.push(P.selectScreen(prof, i, true)) end,
          { left = true, right = P.describe(f, prof[f.key]) })
      end
      local y = 58 + half * 42 + 4
      L.text(15, y, "Normal (FM0): aktiv når ingen annen flymodus er på.", SMLSIZE, L.C.dim)
      for k, w in ipairs(P.warnings(prof)) do
        if k <= 2 then L.text(15, y + 22 * k, "! " .. w, SMLSIZE, L.C.warn) end
      end
      L.btnRow(list, {
        { "Avbryt", function() L.pop() end },
        { "Kanaler", function() L.push(P.channelScreen(prof)) end },
        { "Lagre profil", function()
          if P.save(prof) then
            L.toast("Pilotprofil lagret")
            L.pop()
            if onSaved then onSaved() end
          else
            L.toast("Kunne ikke lagre profilen", true)
          end
        end },
      })
    end

    return s
  end

  ----------------------------------------------------------------------
  -- Inngang til steg P: «Bruk lagret / Endre»

  function P.startScreen(onDone)
    local s = {}

    local function done()
      L.pop()
      if onDone then onDone() end
    end

    local function walk(work)
      L.push(P.selectScreen(work, 1, false, function()
        L.push(P.overviewScreen(work, done))
      end))
    end

    function s:enter() s.saved = P.load() end
    function s:resume() s.saved = P.load() end

    function s:draw(list)
      L.header("Steg P - Pilotoppsett")
      local items = {}
      if s.saved then
        local p = P.complete(L.copy(s.saved))
        L.text(20, 65, "Lagret pilotprofil:", MIDSIZE)
        local y = 105
        for i, f in ipairs(P.FUNCS) do
          local col = (i <= 7) and 0 or 1
          local row = (i <= 7) and (i - 1) or (i - 8)
          L.text(30 + col * 390, y + row * 30, f.label .. ": " .. P.describe(f, p[f.key]), SMLSIZE)
        end
        items = {
          { "Tilbake", function() L.pop() end },
          { "Bruk lagret", done },
          { "Endre enkeltvalg", function() L.push(P.overviewScreen(p, done)) end },
          { "Gå gjennom alle", function() walk(p) end },
        }
      else
        L.text(20, 70, "Ingen pilotprofil er lagret ennå.", MIDSIZE)
        L.text(20, 120, "Du går gjennom funksjonene en og en. For hver funksjon flipper du")
        L.text(20, 148, "bryteren, eller vrir potten eller skyveren, du vil bruke.")
        L.text(20, 176, "Forslaget er Stigs oppsett. Trykk Neste for å beholde forslaget.")
        L.text(20, 220, "Profilen gjelder alle modellene på denne radioen.", 0, L.C.dim)
        items = {
          { "Tilbake", function() L.pop() end },
          { "Bruk standard", function() L.push(P.overviewScreen(P.defaults(), done)) end },
          { "Start", function() walk(P.defaults()) end },
        }
      end
      L.btnRow(list, items)
    end

    return s
  end

  return P
end
