-- Bot names, pure (06-progression.md d.7): a name from the pool (sh_name_pool.lua) that no connected player has,
-- compared without case. When every pool name is taken, the first pool name with the lowest free number
-- ("Mike 2"), independent of RNG. An empty pool uses "Operator" instead. Loaded by shared.lua.

local lib = PW.BotsManager --[[@as PW.BotsManagerLib]]

---@param taken table<string, boolean> lowercase names in use
---@param name string
---@return boolean
local function free(taken, name)
    return not taken[string.lower(name)]
end

function lib._PickName(pool, taken, roll)
    ---@type string[]
    local open = {}
    for _, name in ipairs(pool) do
        if free(taken, name) then open[#open + 1] = name end
    end
    if #open > 0 then return open[math.Clamp(math.floor(roll() * #open) + 1, 1, #open)] end
    local base = pool[1] or "Operator"
    local number = 2
    while not free(taken, base .. " " .. number) do number = number + 1 end
    return base .. " " .. number
end

function lib._TakenNames(entries)
    ---@type table<string, boolean>
    local taken = {}
    for _, entry in ipairs(entries) do
        if isstring(entry.name) then taken[string.lower(entry.name --[[@as string]])] = true end
    end
    return taken
end
