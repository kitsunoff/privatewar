-- Operators, pure rules (06-progression.md d.7; 10-frontend.md d.6). Plain data in, plain data out, so the
-- server-side test runner covers them:
--   List: the operator list of one player: the active economy `models` entries (owned or free ones selectable, the
--     others locked with their price or level) and every stock player model (player_manager.AllValidModels, which
--     includes installed Workshop playermodels). A stock entry whose model path belongs to an active economy entry is
--     dropped: the economy rule governs that model.
--   Resolve: the entry a choice gives: the chosen entry when it exists and is not locked, else the player's own GMod
--     model (cl_playermodel) when it is a selectable stock entry, else the stock fallback, else the first selectable
--     entry. The choice "auto" goes straight to cl_playermodel.
--   CheckChoice: the wire check of a requested choice (a short printable string).
--   BotPick: a random entry for a bot, locks ignored. Colour: the player colour (team colour in team modes).
--   Cards: the picker cards (screens/loadout_operator.lua).
-- Loaded by shared.lua.

local lib = PW.Operators --[[@as PW.OperatorsLib]]

lib.Auto = "auto"
lib.FallbackName = "kleiner"
lib.FallbackPath = "models/player/kleiner.mdl"
lib.MaxChoiceBytes = 64
lib.DefaultColour = { 0.24, 0.34, 0.41 }

---@param path string
---@return string
function lib.NormalPath(path)
    local slashed = string.gsub(path, "\\", "/")
    return string.lower(slashed)
end

---"male_07" -> "Male 07".
---@param name string
---@return string
function lib.Pretty(name)
    local spaced = string.gsub(name, "[_%-]+", " ")
    local titled = string.gsub(spaced, "(%a)([%w']*)", function(first, rest) return string.upper(first) .. rest end)
    return titled
end

---@param entry PW.OperatorEconomyInput
---@param unlocked fun(id: string): boolean
---@return PW.OperatorEntry
local function economyEntry(entry, unlocked)
    local open = unlocked(entry.id)
    local price = isnumber(entry.price) and entry.price > 0 and math.floor(entry.price) or nil
    local unlock = isnumber(entry.unlock) and math.floor(entry.unlock) or nil
    return {
        id = "models:" .. entry.id, name = entry.name, path = entry.path, source = "store", locked = not open,
        price = not open and price or nil, unlock = not open and unlock or nil
    }
end

---@param a PW.OperatorEntry
---@param b PW.OperatorEntry
---@return boolean
local function byName(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
end

function lib.List(input)
    ---@type PW.OperatorEntry[], PW.OperatorEntry[]
    local store, stock = {}, {}
    ---@type table<string, true>
    local governed = {}
    local unlocked = input.unlocked or function() return true end
    for _, entry in ipairs(input.economy or {}) do
        if isstring(entry.id) and isstring(entry.path) and entry.path ~= "" then
            store[#store + 1] = economyEntry(entry, unlocked)
            governed[lib.NormalPath(entry.path)] = true
        end
    end
    for name, path in pairs(input.stock or {}) do
        if isstring(name) and name ~= "" and isstring(path) and not governed[lib.NormalPath(path)] then
            stock[#stock + 1] = { id = name, name = lib.Pretty(name), path = path, source = "stock", locked = false }
        end
    end
    table.sort(store, byName)
    table.sort(stock, byName)
    for _, entry in ipairs(stock) do store[#store + 1] = entry end
    return store
end

function lib.OptionIds(entries)
    ---@type string[]
    local ids = { lib.Auto }
    for _, entry in ipairs(entries) do ids[#ids + 1] = entry.id end
    return ids
end

---@param entries PW.OperatorEntry[]
---@param id string?
---@return PW.OperatorEntry?
local function find(entries, id)
    if id == nil then return nil end
    for _, entry in ipairs(entries) do
        if entry.id == id then return entry end
    end
    return nil
end

---@param entry PW.OperatorEntry?
---@return boolean
local function usable(entry)
    return entry ~= nil and not entry.locked
end

---@param entries PW.OperatorEntry[]
---@return PW.OperatorEntry?
local function fallback(entries)
    local stock = find(entries, lib.FallbackName)
    if usable(stock) then return stock end
    for _, entry in ipairs(entries) do
        if not entry.locked then return entry end
    end
    return nil
end

function lib.Resolve(entries, choice, auto)
    ---@type PW.OperatorReject?
    local reason = nil
    if isstring(choice) and choice ~= lib.Auto then
        local chosen = find(entries, choice)
        if usable(chosen) then return chosen, nil end
        reason = chosen == nil and "unknown" or "locked"
    end
    local own = find(entries, isstring(auto) and auto or nil)
    if usable(own) and (own --[[@as PW.OperatorEntry]]).source == "stock" then return own, reason end
    return fallback(entries), reason
end

function lib.CheckChoice(choice)
    if not isstring(choice) then return false end
    local length = #choice
    if length == 0 or length > lib.MaxChoiceBytes then return false end
    return string.find(choice, "%c") == nil
end

function lib.BotPick(entries, roll)
    if #entries == 0 then return nil end
    local index = math.floor(roll() * #entries) + 1
    return entries[math.Clamp(index, 1, #entries)]
end

---"r g b" in 0..1 (cl_playercolor), else nil.
---@param text string?
---@return number[]?
function lib.ParseColour(text)
    if not isstring(text) then return nil end
    local r, g, b = string.match(text --[[@as string]], "^%s*([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*$")
    local values = { tonumber(r), tonumber(g), tonumber(b) }
    if values[1] == nil or values[2] == nil or values[3] == nil then return nil end
    for index, value in ipairs(values) do values[index] = math.Clamp(value, 0, 1) end
    return values
end

function lib.Colour(facts)
    local teamColour = facts.teamColour
    if facts.teams > 0 and facts.team >= 1 and facts.team <= facts.teams and teamColour ~= nil then
        return { teamColour.r / 255, teamColour.g / 255, teamColour.b / 255 }
    end
    if facts.own ~= nil then return { facts.own[1], facts.own[2], facts.own[3] } end
    local parsed = lib.ParseColour(facts.info)
    if parsed ~= nil then return parsed end
    local default = lib.DefaultColour
    return { default[1], default[2], default[3] }
end

---@param entry PW.OperatorEntry
---@return string? lockText
---@return string? reason
local function lockOf(entry)
    if not entry.locked then return nil, nil end
    if entry.price ~= nil then
        return string.format("%d CR", entry.price), string.format("Buy it in the STORE for %d", entry.price)
    end
    if entry.unlock ~= nil then
        return "LV " .. entry.unlock, "Unlocks at level " .. entry.unlock
    end
    return nil, "Locked"
end

function lib.Cards(entries, choice, auto)
    local own = lib.Resolve(entries, lib.Auto, auto)
    ---@type PW.UICard[]
    local cards = {
        {
            id = lib.Auto, title = "Auto",
            text = "Your Garry's Mod player model" .. (own ~= nil and (": " .. own.name) or "") .. "."
        }
    }
    for _, entry in ipairs(entries) do
        local lockText, reason = lockOf(entry)
        cards[#cards + 1] = {
            id = entry.id, title = entry.name, locked = entry.locked, lockText = lockText, reason = reason,
            badge = entry.source == "store" and not entry.locked and "STORE" or nil,
            text = entry.source == "store" and "From the store." or "Stock player model.", footer = entry.path
        }
    end
    local selected = lib.Auto
    local chosen = find(entries, choice)
    if usable(chosen) then selected = (chosen --[[@as PW.OperatorEntry]]).id end
    return cards, selected
end
