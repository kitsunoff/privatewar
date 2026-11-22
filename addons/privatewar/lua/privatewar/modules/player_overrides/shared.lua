-- Temporary role stats; ordinary player initialization remains owned by the base spawn path.
MODULE.Name = "Player overrides"
local lib = (rawget(PW, "PlayerOverrides") or {}) --[[@as PW.PlayerOverridesLib]]
PW.PlayerOverrides = lib

function lib._SpeedFactor(sources)
    if sources == nil then return 1 end
    local ids = table.GetKeys(sources) --[[@as string[] ]]
    table.sort(ids)
    local product = 1
    for _, id in ipairs(ids) do
        local value = sources[id]
        if isnumber(value) and value > 0 and value < math.huge then
            local factor = value --[[@as number]]
            product = product * factor
        end
    end
    return product
end
