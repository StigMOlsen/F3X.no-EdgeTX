-- CRSF-parametre: kjør en kommando i ELRS-mottakeren fra F3X.no, slik ExpressLRS-skriptet gjør
-- (Other Devices -> mottakeren). Brukes av meny 7 for «Set Failsafe Pos», som lagrer kanalene
-- slik de står akkurat nå som failsafe i mottakeren.
--
-- Protokollen (som elrsV3.lua): ping 0x28 -> enhetsinfo 0x29, les felt 0x2C -> feltinfo 0x2B
-- (i biter), skriv felt 0x2D. Kommandofelt (type 13) har status: 0 klar, 1 start, 2 jobber,
-- 3 trenger bekreftelse, 4 bekreftet, 5 avbryt, 6 spør.
-- IKKE PRØVD PÅ RADIO (2026-11-18): bygget etter ELRS-skriptet og PR #1763.
local C = {}

local HS = 0xEF        -- avsender, samme som ELRS-skriptet
local RX = 0xEC        -- CRSF-adressen til mottakeren
local CMD = 13         -- felttype kommando

local function now() return getTime() end   -- 10 ms

local function str(d, i)
  local t = {}
  while d[i] and d[i] ~= 0 do t[#t + 1] = string.char(d[i]); i = i + 1 end
  return table.concat(t), i + 1
end

-- match(navn): true for feltet som skal kjøres
function C.new(match)
  return { state = "ping", t = 0, tries = 0, match = match, text = "Leter etter mottakeren ..." }
end

local function push(cmd, d)
  return crossfireTelemetryPush(cmd, d)
end

local function readField(j)
  push(0x2C, { RX, HS, j.fid, j.chunk })
  j.t = now()
end

-- Feltet er lest ferdig (alle biter): navn, type og (for kommando) status og tekst
local function parseField(buf)
  local f = { parent = buf[1], type = (buf[2] or 0) % 128 }
  local i
  f.name, i = str(buf, 3)
  if f.type == CMD then
    f.status = buf[i]
    f.info = str(buf, i + 2)
  end
  return f
end

local function onField(j, f)
  if j.state == "scan" then
    if f.type == CMD and j.match(f.name) then
      j.state, j.name = "click", f.name
      return
    end
    j.fid = j.fid + 1
    if j.fid > j.count then
      j.state, j.text = "notfound", "Fant ikke «Set Failsafe Pos» i mottakeren (eldre ELRS?)."
    end
    return
  end
  -- Kommandoen kjører: svar på status
  if j.state == "wait" then
    if f.info and f.info ~= "" then j.info = f.info end
    if f.status == 3 then
      push(0x2D, { RX, HS, j.fid, 4 })   -- bekreft
      j.confirmed = true
      j.text = "Bekreftet, venter på mottakeren ..."
    elseif f.status == 2 then
      push(0x2D, { RX, HS, j.fid, 6 })   -- spør igjen
      j.busy = true
    elseif f.status == 0 and (j.confirmed or j.busy or now() - j.t0 > 150) then
      j.state = "done"
      j.text = "Failsafe er lagret i mottakeren" .. (j.info and (": " .. j.info) or ".")
    end
  end
end

local function receive(j)
  for _ = 1, 10 do
    local cmd, d = crossfireTelemetryPop()
    if not cmd then return end
    if cmd == 0x29 and d[2] == RX and j.state == "ping" then
      local name, i = str(d, 3)
      j.rxName = name
      j.count = d[i + 12] or 0
      j.state, j.fid, j.chunk, j.buf, j.tries = "scan", 1, 0, {}, 0
      j.text = "Fant " .. name .. ". Leser innstillingene ..."
      if j.count == 0 then j.state, j.text = "notfound", "Mottakeren har ingen innstillinger." end
      readField(j)
    elseif cmd == 0x2B and d[2] == RX and d[3] == j.fid and (j.state == "scan" or j.state == "wait") then
      for k = 5, #d do j.buf[#j.buf + 1] = d[k] end
      if (d[4] or 0) > 0 then
        j.chunk = j.chunk + 1
        readField(j)
      else
        local f = parseField(j.buf)
        j.buf, j.chunk, j.tries = {}, 0, 0
        onField(j, f)
        if j.state == "scan" then readField(j) end
      end
    end
  end
end

-- Kalles hver tick. Gir true når jobben er ferdig (done, notfound, noreply, nocrsf).
function C.tick(j)
  if j.state == "done" or j.state == "notfound" or j.state == "noreply" or j.state == "nocrsf" then return true end
  if not (crossfireTelemetryPush and crossfireTelemetryPop) then
    j.state, j.text = "nocrsf", "Radioen har ikke CRSF (ELRS-modul) her."
    return true
  end
  receive(j)
  local t = now()
  if j.state == "ping" then
    if t - j.t >= 100 then
      j.tries = j.tries + 1
      if j.tries > 5 then
        j.state, j.text = "noreply", "Mottakeren svarer ikke. Er den på og bundet (link)?"
        return true
      end
      push(0x28, { 0x00, HS })
      j.t = t
    end
  elseif j.state == "scan" then
    if t - j.t >= 100 then   -- intet svar på 1 s: les på nytt
      j.tries = j.tries + 1
      if j.tries > 4 then j.state, j.text = "noreply", "Mottakeren sluttet å svare. Prøv igjen."; return true end
      j.buf, j.chunk = {}, 0
      readField(j)
    end
    if j.state == "scan" then j.text = "Leser innstillingene " .. j.fid .. " / " .. j.count .. " ..." end
  elseif j.state == "click" then
    push(0x2D, { RX, HS, j.fid, 1 })   -- start
    j.state, j.t0, j.t = "wait", t, t
    j.buf, j.chunk = {}, 0
    j.text = "Sender «" .. j.name .. "» ..."
  elseif j.state == "wait" then
    if t - j.t0 > 800 then
      j.state, j.text = "noreply", "Ingen bekreftelse fra mottakeren. Prøv igjen."
      return true
    end
    if t - j.t >= 50 then j.buf, j.chunk = {}, 0; readField(j) end
  end
  return j.state == "done"
end

return C
