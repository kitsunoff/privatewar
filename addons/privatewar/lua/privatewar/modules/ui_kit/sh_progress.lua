-- Progress view model (T-7.5; 06-progression.md d.1, d.4; 10-frontend.md d.1 "PROGRESS: player level, weapon levels,
-- unlocks"). Pure and shared, so the server-side test runner covers it: the level card (level, XP text, bar), the next
-- unlocks (entities whose Unlock level is above the player's level, the closest first), the weapon levels list (every
-- weapon of the registry and every class with XP, highest level first) and the rows of the last match summary. The
-- screen is screens/progress_home.lua; the data is the NW2 level values, the local progression file and the registries.
-- Loaded after sh_store.lua (number format and kind labels).

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

local progress = (rawget(lib, "Progress") or {}) --[[@as PW.UIProgressLib]]
lib.Progress = progress

---@return PW.UIStoreLib
local function store()
    return lib.Store --[[@as PW.UIStoreLib]]
end

---@param into number
---@param need number
---@return number
local function fraction(into, need)
    if need <= 0 then return 1 end
    return math.Clamp(into / need, 0, 1)
end

function progress.LevelView(level, into, need)
    local maxed = need <= 0
    local text = "Max level"
    if not maxed then
        text = string.format("%s / %s XP", store().FormatNumber(into), store().FormatNumber(need))
    end
    return { title = "LEVEL " .. tostring(level), xpText = text, fraction = fraction(into, need), maxed = maxed }
end

---The level an Unlock field asks for (an integer or { level = N }), nil without one.
---@param unlock any
---@return integer?
local function unlockLevel(unlock)
    if isnumber(unlock) then return math.floor(unlock --[[@as number]]) end
    if istable(unlock) and isnumber((unlock --[[@as table<string, any>]]).level) then
        return math.floor((unlock --[[@as table<string, any>]]).level --[[@as number]])
    end
    return nil
end

---@param a PW.UIProgressUnlock
---@param b PW.UIProgressUnlock
---@return boolean
local function closerFirst(a, b)
    if a.level ~= b.level then return a.level < b.level end
    if a.name ~= b.name then return a.name < b.name end
    if a.kind ~= b.kind then return a.kind < b.kind end
    return a.id < b.id
end

function progress.NextUnlocks(catalogue, level, limit)
    ---@type PW.UIProgressUnlock[]
    local unlocks = {}
    for kind, entities in pairs(catalogue) do
        for id, entity in pairs(entities) do
            local wanted = istable(entity) and entity.Hidden ~= true and unlockLevel(entity.Unlock) or nil
            if wanted ~= nil and wanted > level then
                local name = isstring(entity.Name) and entity.Name --[[@as string]] or id
                unlocks[#unlocks + 1] = { kind = kind, id = id, name = name, level = wanted }
            end
        end
    end
    table.sort(unlocks, closerFirst)
    if limit ~= nil then
        for index = #unlocks, limit + 1, -1 do unlocks[index] = nil end
    end
    return unlocks
end

function progress.UnlockRows(unlocks)
    ---@type { [1]: string, [2]: string }[]
    local rows = {}
    for index, unlock in ipairs(unlocks) do
        rows[index] = {
            "LV " .. tostring(unlock.level), string.format("%s (%s)", unlock.name, store().KindLabel(unlock.kind))
        }
    end
    return rows
end

---@param a PW.UIProgressWeapon
---@param b PW.UIProgressWeapon
---@return boolean
local function strongerFirst(a, b)
    if a.level ~= b.level then return a.level > b.level end
    if a.xp ~= b.xp then return a.xp > b.xp end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
end

function progress.Weapons(weapons, xp, levelOf)
    ---@type table<string, boolean>
    local seen = {}
    ---@type PW.UIProgressWeapon[]
    local rows = {}
    local function add(id)
        if seen[id] then return end
        seen[id] = true
        local entity = weapons[id]
        local total = xp[id] or 0
        local level, into, need = levelOf(total)
        local name = entity ~= nil and isstring(entity.Name) and entity.Name --[[@as string]] or id
        rows[#rows + 1] = {
            id = id, name = name, xp = total, level = level, into = into, need = need,
            fraction = fraction(into, need), maxed = need <= 0
        }
    end
    for id in pairs(weapons) do add(id) end
    for id in pairs(xp) do add(id) end
    table.sort(rows, strongerFirst)
    return rows
end

function progress.WeaponCards(rows)
    local format = store().FormatNumber
    ---@type PW.UICard[]
    local cards = {}
    for index, row in ipairs(rows) do
        local text = "Max level"
        if not row.maxed then
            text = string.format("%s / %s XP to level %d", format(row.into), format(row.need), row.level + 1)
        end
        cards[index] = {
            id = row.id, title = row.name, badge = "LV " .. tostring(row.level), text = text,
            footer = format(row.xp) .. " XP in total", locked = false
        }
    end
    return cards
end

function progress.SummaryRows(summary, nameOf)
    if summary == nil then return nil end
    ---@type { [1]: string, [2]: string }[]
    local rows = {
        { "XP", "+" .. store().FormatNumber(summary.xp) },
        { "LEVEL", string.format("%d > %d", summary.levelBefore, summary.levelAfter) }
    }
    for _, gain in ipairs(summary.weapons or {}) do
        local name = nameOf ~= nil and nameOf(gain.class) or gain.class
        rows[#rows + 1] = { name, string.format("LV %d > %d", gain.before, gain.after) }
    end
    local medals = 0
    for _, medal in ipairs(summary.medals or {}) do medals = medals + medal.count end
    if medals > 0 then rows[#rows + 1] = { "MEDALS", tostring(medals) } end
    return rows
end
