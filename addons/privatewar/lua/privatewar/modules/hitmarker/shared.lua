-- Hitmarker (T-6.3; 09-hud.md d.2: hitmarker, red on kill). Shared and pure: classifying a damage event, merging the
-- hits of one tick, the fade and who is told. The server glue (init.lua) reads the engine, the client part
-- (cl_init.lua) keeps the marker that hud/hitmarker.lua draws.
--
-- Wire (server -> client, message "pw_hitmarker"): one UInt(2): 1 hit, 2 headshot, 3 kill. Only a human attacker
-- receives it; hits of one tick are merged into one message with the strongest kind.

MODULE.Name = "Hitmarker"

local lib = (rawget(PW, "Hitmarker") or {}) --[[@as PW.HitmarkerLib]]
PW.Hitmarker = lib

lib.Duration = 0.25

lib.Current = lib.Current or { kind = nil, at = 0 }

---@type table<PW.HitKind, integer>
local rank = { hit = 1, headshot = 2, kill = 3 }
---@type PW.HitKind[]
local kinds = { "hit", "headshot", "kill" }

function lib._Classify(facts)
    if facts.killed then return "kill" end
    if facts.dmg <= 0 then return nil end
    if facts.hitgroup == HITGROUP_HEAD then return "headshot" end
    return "hit"
end

function lib._Merge(a, b)
    if a == nil then return b end
    if b == nil then return a end
    if rank[b] > rank[a] then return b end
    return a
end

function lib._Encode(kind)
    return rank[kind]
end

function lib._Decode(value)
    return kinds[value]
end

function lib._Alpha(age, duration)
    if age <= 0 then return 1 end
    if age >= duration then return 0 end
    return 1 - age / duration
end

function lib._Eligible(attacker, victim)
    if attacker == nil or attacker == victim or not IsValid(attacker) then return false end
    local target = attacker --[[@as Player]]
    if not target:IsPlayer() then return false end
    return not target:IsBot()
end
