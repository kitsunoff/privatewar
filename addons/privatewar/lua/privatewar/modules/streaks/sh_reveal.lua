-- Streaks module, shared and pure (T-4.6): the deliberate reveal rules (DESIGN.md net rule: never send enemy positions
-- that are not deliberately revealed; PW.Reveal in sv_reveal.lua is that path), the radar wire and the airstrike line.
--
-- Wire (server -> client, "pw_reveal"): UInt(1) kind. Kind 0, blips: UInt(TimeBits) duration in tenths of a second,
-- UInt(CountBits) count, then per blip UInt(IndexBits) entity index and three Int(PosBits) coordinates divided by
-- PosScale. Kind 1, jam: UInt(TimeBits) duration in tenths. Only revealed positions travel; nothing else.
--
-- A Counter-UAV is a jam { owner, ends }: until it ends, a target that is not an enemy of the owner is hidden from a
-- viewer that is an enemy of the owner (the owner's side vanishes from hostile UAVs).

local lib = PW.Streaks --[[@as PW.StreaksLib]]

lib.RevealNet = "pw_reveal"
lib.TimeBits, lib.CountBits, lib.IndexBits, lib.PosBits = 9, 7, 8, 15
lib.PosScale = 2
lib.MaxBlips = 2 ^ lib.CountBits - 1

function lib._Visible(target, ref, jams, now, isEnemy)
    for _, jam in ipairs(jams) do
        if jam.ends > now and not isEnemy(jam.owner, target) and isEnemy(jam.owner, ref) then return false end
    end
    return true
end

function lib._Filter(targets, ref, jams, now, isEnemy)
    ---@type any[]
    local out = {}
    for _, target in ipairs(targets) do
        if lib._Visible(target, ref, jams, now, isEnemy) then out[#out + 1] = target end
    end
    return out
end

function lib._Prune(jams, now)
    for i = #jams, 1, -1 do
        if jams[i].ends <= now then table.remove(jams, i) end
    end
    return jams
end

function lib._Quantize(value)
    local limit = 2 ^ (lib.PosBits - 1) - 1
    local q = math.floor(value / lib.PosScale + 0.5)
    return math.max(-limit, math.min(limit, q))
end

function lib._Dequantize(value)
    return value * lib.PosScale
end

function lib._EncodeTime(seconds)
    local tenths = math.floor((tonumber(seconds) or 0) * 10 + 0.5)
    return math.max(0, math.min(2 ^ lib.TimeBits - 1, tenths))
end

function lib._DecodeTime(tenths)
    return tenths / 10
end

function lib._AirstrikePoints(center, dir, count, spacing)
    local flat = Vector(dir.x, dir.y, 0)
    if flat:LengthSqr() < 1e-6 then flat = Vector(1, 0, 0) end
    flat:Normalize()
    ---@type Vector[]
    local points = {}
    local first = -(count - 1) / 2
    for i = 1, count do
        points[i] = center + flat * ((first + i - 1) * spacing)
    end
    return points
end

function lib._Live(blips, now, out)
    local n = 0
    for _, blip in ipairs(blips) do
        if (blip.ends or 0) > now then
            n = n + 1
            out[n] = blip
        end
    end
    for i = #out, n + 1, -1 do out[i] = nil end
    return out
end
