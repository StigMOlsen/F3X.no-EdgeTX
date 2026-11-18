-- Grafikk for veiviseren (kap. 7b i designet): flyfigur ovenfra med fargede ror,
-- rorprofil som vipper med servoen, stolper, kurvegraf og flymodus-faner.
-- Alt tegnes med lcd.drawFilledRectangle og lcd.drawLine. Fylte polygoner gjøres
-- om til vannrette striper én gang og lagres, så hver skjermoppdatering er billig.
-- Geometrien er den samme som i flyfigurene i prosjektbeskrivelsen (1000 x 700).

return function(L)
  local G = {}
  local lcd = L.lcd   -- skalert på mindre skjermer (scale.lua)
  local floor, sin, cos, abs = math.floor, math.sin, math.cos, math.abs

  local function rgb(r, g, b) return lcd.RGB and lcd.RGB(r, g, b) or 0 end
  G.C = {
    body = rgb(43, 55, 68), edge = rgb(107, 124, 141), surf = rgb(70, 89, 107),
    canopy = rgb(26, 35, 44), label = rgb(169, 184, 198), white = rgb(235, 240, 245),
    act = rgb(243, 156, 80), ok = rgb(76, 175, 105), warn = rgb(231, 76, 60),
    yellow = rgb(150, 115, 30), red = rgb(130, 45, 40), track = rgb(47, 58, 70),
    neutral = rgb(150, 162, 175),
  }
  local C = G.C

  ----------------------------------------------------------------------
  -- Polygoner som striper

  -- pts: flat liste {x1, y1, x2, y2, ...}. Gir liste med {x, y, w, h}.
  function G.spans(pts, sc, ox, oy)
    local n = #pts / 2
    local xs, ys = {}, {}
    local y0, y1 = 1e9, -1e9
    for i = 1, n do
      xs[i] = ox + pts[2 * i - 1] * sc
      ys[i] = oy + pts[2 * i] * sc
      if ys[i] < y0 then y0 = ys[i] end
      if ys[i] > y1 then y1 = ys[i] end
    end
    local out, last = {}, nil
    for y = floor(y0), floor(y1) do
      local yc = y + 0.5
      local cr = {}
      for i = 1, n do
        local j = i % n + 1
        local ya, yb = ys[i], ys[j]
        if (ya <= yc and yb > yc) or (yb <= yc and ya > yc) then
          local x = xs[i] + (yc - ya) * (xs[j] - xs[i]) / (yb - ya)
          local k = #cr                              -- sett inn sortert (få punkter)
          while k >= 1 and cr[k] > x do cr[k + 1] = cr[k]; k = k - 1 end
          cr[k + 1] = x
        end
      end
      for k = 1, #cr - 1, 2 do
        local a, b = floor(cr[k] + 0.5), floor(cr[k + 1] + 0.5)
        if b > a then
          -- slå sammen med raden over hvis den er lik (rektangler blir én stripe)
          if last and last[1] == a and last[3] == b - a and last[2] + last[4] == y and #cr == 2 then
            last[4] = last[4] + 1
          else
            last = { a, y, b - a, 1 }
            out[#out + 1] = last
          end
        end
      end
    end
    return out
  end

  function G.fill(sp, color)
    for i = 1, #sp do
      local r = sp[i]
      lcd.drawFilledRectangle(r[1], r[2], r[3], r[4], color)
    end
  end

  function G.line(x1, y1, x2, y2, color, dotted)
    lcd.drawLine(floor(x1 + 0.5), floor(y1 + 0.5), floor(x2 + 0.5), floor(y2 + 0.5),
      dotted and (DOTTED or 0) or (SOLID or 0), color)
  end

  function G.outline(pts, sc, ox, oy, color)
    local n = #pts / 2
    for i = 1, n do
      local j = i % n + 1
      G.line(ox + pts[2 * i - 1] * sc, oy + pts[2 * i] * sc, ox + pts[2 * j - 1] * sc, oy + pts[2 * j] * sc, color)
    end
  end

  local discCache = {}
  function G.disc(x, y, r, color)
    local d = discCache[r]
    if not d then
      d = {}
      for dy = -r, r do
        local w = floor(math.sqrt(r * r - dy * dy) + 0.5)
        d[#d + 1] = { dy, w }
      end
      discCache[r] = d
    end
    x, y = floor(x + 0.5), floor(y + 0.5)
    for i = 1, #d do lcd.drawFilledRectangle(x - d[i][2], y + d[i][1], 2 * d[i][2] + 1, 1, color) end
  end

  ----------------------------------------------------------------------
  -- Flyfigur ovenfra

  local WING = { 30,236, 42,226, 80,216, 170,208, 320,202, 484,198, 516,198, 680,202, 830,208, 920,216,
    958,226, 970,236, 970,241, 958,248, 920,258, 830,272, 680,284, 516,292, 484,292, 320,284, 170,272,
    80,258, 42,248, 30,241 }
  local FUS = { 500,34, 507,38, 513,49, 518,66, 521,89, 523,117, 524,150, 523,176, 522,203, 519,230,
    516,257, 512,284, 508,310, 504,600, 503,650, 497,650, 496,600, 492,310, 488,284, 484,257, 481,230,
    478,203, 477,176, 476,150, 477,117, 479,89, 482,66, 487,49, 493,38 }
  local CANOPY = { 500,82, 506,87, 510,100, 511,118, 510,136, 506,149, 500,154, 494,149, 490,136,
    489,118, 490,100, 494,87 }
  local STAB = {
    X = { { 500,582, 372,594, 372,626, 500,630 }, { 500,582, 628,594, 628,626, 500,630 } },
    V = { { 496,572, 350,612, 350,638, 496,628 }, { 504,572, 650,612, 650,638, 504,628 } },
  }

  -- Rorflater per antall vingeservoer, og halen. Hver rolle kan ha flere flater.
  local SURF = {
    [2] = {
      ailL = { { 482,266.6, 320,261.9, 170,254.7, 80,246.7, 44,242.3, 44,248.5, 80,258, 170,272, 320,284, 482,291.9 } },
      ailR = { { 518,266.6, 680,261.9, 830,254.7, 920,246.7, 956,242.3, 956,248.5, 920,258, 830,272, 680,284, 518,291.9 } },
    },
    [4] = {
      flapL = { { 482,266.6, 320,261.9, 252,258.6, 252,278.6, 320,284, 482,291.9 } },
      flapR = { { 518,266.6, 680,261.9, 748,258.6, 748,278.6, 680,284, 518,291.9 } },
      ailL = { { 250,258.5, 170,254.7, 80,246.7, 44,242.3, 44,248.5, 80,258, 170,272, 250,278.4 } },
      ailR = { { 750,258.5, 830,254.7, 920,246.7, 956,242.3, 956,248.5, 920,258, 830,272, 750,278.4 } },
    },
    [6] = {
      flapL = { { 482,266.6, 320,261.9, 282,260.1, 282,281, 320,284, 482,291.9 } },
      flapR = { { 518,266.6, 680,261.9, 718,260.1, 718,281, 680,284, 518,291.9 } },
      ailL = { { 280,260, 170,254.7, 108,249.2, 108,262.4, 170,272, 280,280.8 } },
      ailR = { { 720,260, 830,254.7, 892,249.2, 892,262.4, 830,272, 720,280.8 } },
      tipL = { { 106,249, 80,246.7, 44,242.3, 44,248.5, 80,258, 106,262 } },
      tipR = { { 894,249, 920,246.7, 956,242.3, 956,248.5, 920,258, 894,262 } },
    },
    X = {
      elev = { { 494,612.7, 372,614.5, 372,626, 494,630 }, { 506,612.7, 628,614.5, 628,626, 506,630 } },
      rud = { { 495,598, 505,598, 505,662, 495,662 } },
    },
    V = {
      vL = { { 496,606.7, 350,628.1, 350,638, 496,628 } },
      vR = { { 504,606.7, 650,628.1, 650,638, 504,628 } },
    },
  }
  -- Plassering av CH-teksten (midt under flaten)
  local LABEL = {
    flapL = { 380, 300 }, flapR = { 620, 300 }, ailL = { 170, 290 }, ailR = { 830, 290 },
    tipL = { 70, 274 }, tipR = { 930, 274 }, elev = { 380, 648 }, rud = { 560, 648 },
    vL = { 400, 650 }, vR = { 600, 650 },
  }
  local LABEL2 = { ailL = { 130, 290 }, ailR = { 870, 290 } }   -- 2 servoer: lengre ailerons

  local planeCache = {}

  local function build(cfg, x, y, w)
    local key = cfg.wing .. cfg.tail .. x .. "," .. y .. "," .. w
    local p = planeCache[key]
    if p then return p end
    local sc = w / 960
    local ox, oy = x - 20 * sc, y - 20 * sc
    p = { sc = sc, ox = ox, oy = oy, surf = {}, hits = {} }
    p.wing = G.spans(WING, sc, ox, oy)
    p.fus = G.spans(FUS, sc, ox, oy)
    p.canopy = G.spans(CANOPY, sc, ox, oy)
    p.stab = {}
    for _, s in ipairs(STAB[cfg.tail] or STAB.X) do p.stab[#p.stab + 1] = { pts = s, sp = G.spans(s, sc, ox, oy) } end
    local function add(set)
      for role, list in pairs(set or {}) do
        local t = { polys = {} }
        local hx0, hy0, hx1, hy1 = 1e9, 1e9, -1e9, -1e9
        for _, pts in ipairs(list) do
          t.polys[#t.polys + 1] = { pts = pts, sp = G.spans(pts, sc, ox, oy) }
          for i = 1, #pts, 2 do
            local px, py = ox + pts[i] * sc, oy + pts[i + 1] * sc
            if px < hx0 then hx0 = px end
            if px > hx1 then hx1 = px end
            if py < hy0 then hy0 = py end
            if py > hy1 then hy1 = py end
          end
        end
        local lp = (cfg.wing == 2 and LABEL2[role]) or LABEL[role]
        t.lx, t.ly = floor(ox + lp[1] * sc), floor(oy + lp[2] * sc)
        -- Trykkflate: minst 44 px høy, så den er lett å treffe
        local cy = (hy0 + hy1) / 2
        local hh = math.max(hy1 - hy0, 44)
        p.hits[#p.hits + 1] = { role = role, x = floor(hx0), y = floor(cy - hh / 2), w = floor(hx1 - hx0), h = floor(hh) }
        p.surf[role] = t
      end
    end
    add(SURF[cfg.wing])
    add(SURF[cfg.tail])
    planeCache[key] = p
    return p
  end

  -- Tegner flyet. o = { color = {role = farge}, ch = {role = kanalnr}, active = role,
  --                     hide = {role = true}, motor = bool }
  -- Gir tilbake trykkflatene: liste med {role, x, y, w, h}.
  function G.plane(cfg, x, y, w, o)
    o = o or {}
    local p = build(cfg, x, y, w)
    local sc, ox, oy = p.sc, p.ox, p.oy
    G.fill(p.wing, C.body)
    G.outline(WING, sc, ox, oy, C.edge)
    for _, s in ipairs(p.stab) do
      G.fill(s.sp, C.body)
      G.outline(s.pts, sc, ox, oy, C.edge)
    end
    for role, t in pairs(p.surf) do
      local col = (o.color and o.color[role]) or C.surf
      for _, q in ipairs(t.polys) do
        G.fill(q.sp, col)
        G.outline(q.pts, sc, ox, oy, C.edge)
      end
    end
    G.fill(p.fus, C.body)
    G.outline(FUS, sc, ox, oy, C.edge)
    G.fill(p.canopy, C.canopy)
    if cfg.motor then G.disc(ox + 500 * sc, oy + 30 * sc, math.max(2, floor(10 * sc + 0.5)), C.surf) end
    if o.ch then
      for role, t in pairs(p.surf) do
        local ch = o.ch[role]
        if ch then
          local col = (role == o.active) and C.white or C.label
          lcd.drawText(t.lx, t.ly, "CH" .. ch, SMLSIZE + CENTER + col)
        end
      end
      if cfg.motor and o.ch.motor then
        lcd.drawText(floor(ox + 524 * sc), floor(oy + 22 * sc), "CH" .. o.ch.motor, SMLSIZE + C.label)
      end
    end
    return p.hits
  end

  ----------------------------------------------------------------------
  -- Rorprofil: snitt av vinge og ror, roret vipper rundt hengselen.
  -- v: utslag der -1 = 100 % ned (fortegnskonvensjonen), +1 = 100 % opp.

  local HINGE = 0.74

  local function thick(t)             -- NACA 00xx-tykkelse, 11 %
    return 0.55 * (0.2969 * math.sqrt(t) - 0.126 * t - 0.3516 * t * t + 0.2843 * t ^ 3 - 0.1036 * t ^ 4)
  end

  local profCache = {}
  local function profBody(x, y, w)
    local key = x .. "," .. y .. "," .. w
    local p = profCache[key]
    if p then return p end
    local up, lo = {}, {}
    local N = 14
    for i = 0, N do
      local t = HINGE * (1 - math.cos(i / N * math.pi / 2))   -- tettere ved forkanten
      local camber = 0.025 * (1 - (2 * t - 1) ^ 2)
      up[#up + 1] = { t, camber + thick(t) }
      lo[#lo + 1] = { t, camber - thick(t) }
    end
    local pts = {}
    for i = 1, #up do pts[#pts + 1] = up[i][1] * w; pts[#pts + 1] = -up[i][2] * w end
    for i = #lo, 1, -1 do pts[#pts + 1] = lo[i][1] * w; pts[#pts + 1] = -lo[i][2] * w end
    local hc = 0.025 * (1 - (2 * HINGE - 1) ^ 2)
    local ht = thick(HINGE)
    p = { pts = pts, sp = G.spans(pts, 1, x, y), hy = y - hc * w, ht = ht * w }
    profCache[key] = p
    return p
  end

  local function flapPts(hx, hy, len, half, a)
    -- ror som kile: øvre og nedre kant ved hengselen, spiss bak
    local ca, sa = cos(a), sin(a)
    local function rot(dx, dy) return hx + dx * ca - dy * sa, hy + dx * sa + dy * ca end
    local x1, y1 = rot(0, -half)
    local x2, y2 = rot(len, 0)
    local x3, y3 = rot(0, half)
    return { x1, y1, x2, y2, x3, y3 }, x2, y2
  end

  -- o = { color, limit = v (grønn stiplet), target = v (hvit stiplet, mål), neutralColor,
  --   arrow = -1/1, deg = grader for v = 1 (standard 30, dvs. 100 % vises som 30 grader),
  --   degUp = grader for v = 1 opp, hvis annerledes enn ned }
  function G.profile(x, y, w, v, o)
    o = o or {}
    local p = profBody(x, y, w)
    G.fill(p.sp, C.body)
    G.outline(p.pts, 1, x, y, C.edge)
    local hx, hy = x + HINGE * w, p.hy
    local len = (1 - HINGE) * w
    local function rad(val)
      local d = (val or 0) > 0 and (o.degUp or o.deg or 30) or (o.deg or 30)
      return -L.clamp((val or 0) * d, -95, 95) * math.pi / 180
    end
    -- nøytral (stiplet), grense (grønn stiplet) og mål (hvit stiplet)
    G.line(hx, hy, hx + len * 1.15, hy, o.neutralColor or C.neutral, true)
    if o.target then
      local _, tx, ty = flapPts(hx, hy, len * 1.2, 0, rad(o.target))
      G.line(hx, hy, tx, ty, C.white, true)
    end
    if o.limit then
      local _, lx, ly = flapPts(hx, hy, len * 1.2, 0, rad(o.limit))
      G.line(hx, hy, lx, ly, C.ok, true)
      G.line(hx, hy + 1, lx, ly + 1, C.ok, true)
    end
    local a = rad(v)
    local pts = flapPts(hx, hy, len, p.ht, a)
    G.fill(G.spans(pts, 1, 0, 0), o.color or C.act)
    G.disc(hx, hy, math.max(3, floor(p.ht * 0.7)), C.white)
    if o.arrow then
      local ax, ay = x + w * 1.22, hy
      local d = o.arrow > 0 and 1 or -1           -- 1 = ned
      G.line(ax, ay - 22 * d, ax, ay + 22 * d, C.act)
      G.line(ax + 1, ay - 22 * d, ax + 1, ay + 22 * d, C.act)
      G.fill(G.spans({ ax - 8, ay + 14 * d, ax + 9, ay + 14 * d, ax + 0.5, ay + 26 * d }, 1, 0, 0), C.act)
    end
  end

  ----------------------------------------------------------------------
  -- Stolpe med soner og merker. o = { zones = {{fra, til, farge}}, marks = {{verdi, farge}},
  --   dot = farge, labels = true }
  function G.bar(x, y, w, h, v, lo, hi, o)
    o = o or {}
    local function px(val) return x + floor((L.clamp(val, lo, hi) - lo) / (hi - lo) * w + 0.5) end
    lcd.drawFilledRectangle(x, y, w, h, C.track)
    for _, z in ipairs(o.zones or {}) do
      local a, b = px(z[1]), px(z[2])
      lcd.drawFilledRectangle(a, y, b - a, h, z[3])
    end
    for _, m in ipairs(o.marks or {}) do
      lcd.drawFilledRectangle(px(m[1]) - 1, y - 4, 3, h + 8, m[2])
    end
    if v then
      if o.dot then G.disc(px(v), y + h / 2, floor(h / 2) + 4, o.dot)
      else lcd.drawFilledRectangle(px(v) - 2, y - 6, 5, h + 12, C.white) end
    end
    if o.labels then
      lcd.drawText(x, y + h + 6, tostring(lo), SMLSIZE + C.label)
      lcd.drawText(px(0), y + h + 6, "0", SMLSIZE + CENTER + C.label)
      lcd.drawText(x + w, y + h + 6, (hi > 0 and "+" or "") .. hi, SMLSIZE + RIGHT + C.label)
    end
  end

  ----------------------------------------------------------------------
  -- Kurvegraf. pts = {{x, y}, ...}, x i -100..100, y i -range..range (standard 100).
  -- o = { active = indeks, cursor = x, names = {...}, range }
  function G.curve(x, y, w, h, pts, o)
    o = o or {}
    local yr = o.range or 100
    local function px(v) return x + (v + 100) / 200 * w end
    local function py(v) return y + h / 2 - L.clamp(v, -yr, yr) / (2 * yr) * h end
    lcd.drawRectangle(x, y, w, h, C.track)
    G.line(x, py(0), x + w, py(0), C.track)
    G.line(px(0), y, px(0), y + h, C.track, true)
    for i = 1, #pts - 1 do
      local a, b = pts[i], pts[i + 1]
      G.line(px(a[1]), py(a[2]), px(b[1]), py(b[2]), C.label)
      G.line(px(a[1]), py(a[2]) + 1, px(b[1]), py(b[2]) + 1, C.label)
    end
    if o.cursor then G.line(px(o.cursor), y, px(o.cursor), y + h, C.act, true) end
    for i, q in ipairs(pts) do
      local act = (i == o.active)
      G.disc(px(q[1]), py(q[2]), act and 6 or 4, act and C.act or C.label)
      if o.names and o.names[i] then
        lcd.drawText(floor(px(q[1])), floor(py(q[2]) + (q[2] >= 0 and 10 or -26)), o.names[i],
          SMLSIZE + CENTER + (act and C.act or C.label))
      end
    end
  end

  ----------------------------------------------------------------------
  -- Faner (flymoduser). items = {{tekst, aktiv, i bruk}}
  function G.tabs(x, y, items)
    for _, it in ipairs(items) do
      local tw = 14 + L.textSize(it[1], SMLSIZE)
      local bg = it[2] and C.act or C.track
      lcd.drawFilledRectangle(x, y, tw, 26, bg)
      lcd.drawText(x + floor(tw / 2), y + 4, it[1], SMLSIZE + CENTER + ((it[2] and C.canopy) or (it[3] and C.white) or C.edge))
      x = x + tw + 6
    end
  end

  return G
end
