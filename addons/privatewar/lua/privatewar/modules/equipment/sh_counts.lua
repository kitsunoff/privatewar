-- New additive sources run only after the legacy first-answer result, once on grant.
local lib = PW.Equipment --[[@as PW.EquipmentLib]]
---@type table<Player, table<string, PW.EquipmentCountSource>>
local sources = setmetatable({}, { __mode = "k" })

function lib.CountSource(ply, id, fn)
    local list = sources[ply] or {}
    list[id] = fn
    sources[ply] = next(list) ~= nil and list or nil
end

function lib._ComposeCount(base, legacy, contributors, ply, slot, itemId)
    local count = lib._CountFor(base, legacy)
    local ids = table.GetKeys(contributors) --[[@as string[] ]]
    table.sort(ids)
    for _, id in ipairs(ids) do
        local ok, value = pcall(contributors[id], ply, slot, itemId)
        if ok and isnumber(value) and value >= 0 and value < math.huge then
            count = count + math.floor(value --[[@as number]])
        end
    end
    return count
end

function lib._ResolveCount(ply, slot, itemId, base)
    local legacy = PW.Ask("PW_EquipmentCount", ply, slot, itemId, base)
    return lib._ComposeCount(base, legacy, sources[ply] or {}, ply, slot, itemId)
end
