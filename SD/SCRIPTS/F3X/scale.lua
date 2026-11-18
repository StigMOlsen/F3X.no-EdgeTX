-- Mindre skjerm (TX16S MK2 og andre med 480 x 272): veiviseren er tegnet for 800 x 480 (MK3).
-- Gir en lcd-tabell som skalerer alle koordinater ned og velger mindre fonter, slik at hele
-- layouten og grafikken beholdes. lib.lua, gfx.lua og pilot.lua tegner gjennom L.lcd.
-- Den globale lcd-tabellen endres ikke, så andre verktøy på radioen påvirkes ikke.

return function(sx, sy)
  local floor, max = math.floor, math.max
  local real = lcd
  local S = setmetatable({}, { __index = real })

  -- Fontindeks (bit 8-11): 0 std, 1 bold, 2 tin (XXS), 3 sml (XS), 4 mid (L), 5 dbl (XL), 6 xxl.
  -- MK3 bruker store fonter (std 22, XS 18, L 33, XL 44 px), 480 x 272 vanlige (16, 13, 24, 32 px).
  -- Med skjermskala ca. 0,58 passer ett hakk ned best; SMLSIZE går til TINSIZE så linjene ikke overlapper.
  local FONT = { [0] = 3, 1, 2, 2, 0, 4, 5 }

  local function font(f)
    f = f or 0
    local i = floor((f % 0x1000) / 0x100)
    local to = FONT[i]
    if not to or to == i then return f end
    return f + (to - i) * 0x100
  end

  local function X(x) return floor(x * sx + 0.5) end
  local function Y(y) return floor(y * sy + 0.5) end

  -- Rektangel: kantene skaleres hver for seg, så nabofelt møtes uten glipper
  local function box(x, y, w, h)
    local x0, y0 = X(x), Y(y)
    local w2, h2 = X(x + w) - x0, Y(y + h) - y0
    if w > 0 then w2 = max(w2, 1) end
    if h > 0 then h2 = max(h2, 1) end
    return x0, y0, w2, h2
  end

  function S.drawText(x, y, t, f) real.drawText(X(x), Y(y), t, font(f)) end

  function S.drawFilledRectangle(x, y, w, h, ...)
    local a, b, c, d = box(x, y, w, h)
    real.drawFilledRectangle(a, b, c, d, ...)
  end

  function S.drawRectangle(x, y, w, h, ...)
    local a, b, c, d = box(x, y, w, h)
    real.drawRectangle(a, b, c, d, ...)
  end

  function S.drawLine(x1, y1, x2, y2, ...) real.drawLine(X(x1), Y(y1), X(x2), Y(y2), ...) end

  if real.drawBitmap then
    function S.drawBitmap(b, x, y, scale)
      real.drawBitmap(b, X(x), Y(y), floor((scale or 100) * sx + 0.5))
    end
  end

  -- Tekststørrelse i 800 x 480-koordinater, med fonten som faktisk tegnes
  if real.sizeText then
    function S.sizeText(t, f)
      local w, h = real.sizeText(t, font(f))
      return math.ceil(w / sx), math.ceil(h / sy)
    end
  end

  -- Trykk: skjermkoordinater tilbake til 800 x 480
  function S.toVirtual(t)
    local v = {}
    for k, x in pairs(t) do v[k] = x end
    if t.x then v.x = t.x / sx end
    if t.y then v.y = t.y / sy end
    return v
  end

  return S
end
