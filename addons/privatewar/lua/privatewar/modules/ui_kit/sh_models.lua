-- Component models of kit v1 (U-4; notes/16-frontend-d1-proposal.md §3): card list, pager, seen-set and tab bar,
-- mode monogram, timer and status line, hint bar. Pure and shared, so the server-side test runner covers them; the
-- vgui classes (cl_*.lua) only draw what these return. The player list model is sh_players.lua.

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

-- Cards ----------------------------------------------------------------------------------------------------------

local cards = (rawget(lib, "Cards") or {}) --[[@as PW.UICardsLib]]
lib.Cards = cards

---@param list PW.UICard[]
---@param id? string
---@return PW.UICard?
local function cardById(list, id)
    if id == nil then return nil end
    for _, card in ipairs(list) do
        if card.id == id then return card end
    end
    return nil
end

function cards.Expanded(list, selected)
    local card = cardById(list, selected)
    return card ~= nil and card.id or nil
end

function cards.View(list, selected)
    local expanded = cards.Expanded(list, selected)
    ---@type PW.UICardView[]
    local out = {}
    for index, card in ipairs(list) do
        out[index] = {
            id = card.id, card = card, selected = card.id == expanded, expanded = card.id == expanded,
            new = card.new == true, locked = card.locked == true, disabled = card.disabled == true,
            reason = card.reason
        }
    end
    return out
end

function cards.Select(list, current, id)
    local card = cardById(list, id)
    if card == nil or card.locked or card.disabled then return current end
    return card.id
end

-- Pager ----------------------------------------------------------------------------------------------------------

local pager = (rawget(lib, "Pager") or {}) --[[@as PW.UIPagerLib]]
lib.Pager = pager

function pager.RowsPerPage(height, rowHeight, gap)
    local step = rowHeight + (gap or 0)
    if step <= 0 then return 1 end
    return math.max(1, math.floor((height + (gap or 0)) / step))
end

function pager.State(count, perPage, index)
    perPage = math.max(1, perPage)
    local pages = math.max(1, math.ceil(count / perPage))
    local row = math.Clamp(index, 1, math.max(1, count))
    local page = math.ceil(row / perPage)
    local first = (page - 1) * perPage + 1
    return {
        page = page, pages = pages, first = first, last = math.min(count, first + perPage - 1),
        atStart = page == 1, atEnd = page == pages
    }
end

-- Seen-set and tabs ----------------------------------------------------------------------------------------------

local seenLib = (rawget(lib, "Seen") or {}) --[[@as PW.UISeenLib]]
lib.Seen = seenLib

function seenLib.IsNew(seen, key)
    return seen[key] ~= true
end

function seenLib.Mark(seen, key)
    if seen[key] == true then return false end
    seen[key] = true
    return true
end

local tabs = (rawget(lib, "Tabs") or {}) --[[@as PW.UITabsLib]]
lib.Tabs = tabs

function tabs.SeenKey(id)
    return "tab:" .. id
end

function tabs.Items(list, active, seen)
    ---@type PW.UITabItem[]
    local out = {}
    for index, tab in ipairs(list) do
        out[index] = {
            id = tab.id, label = tab.label, active = tab.id == active, locked = tab.locked, reason = tab.reason,
            new = not tab.locked and seenLib.IsNew(seen, tabs.SeenKey(tab.id))
        }
    end
    return out
end

---Text of the lock reasons the router and the screens use.
local lockReasons = {
    soon = "Coming soon", error = "Unavailable: the screen failed to load", locked = "Locked"
}

function lib.LockReason(reason)
    local key = reason or "locked"
    return lockReasons[key] or key
end

-- Mode monogram (10-frontend.md d.10) ----------------------------------------------------------------------------

local monogramLength = 3

function lib.Monogram(mode)
    local short = mode.Short
    if type(short) == "string" and short ~= "" then return string.upper(short) end
    ---@type string[]
    local letters = {}
    for word in string.gmatch(mode.Name or "", "%w+") do
        if #letters < monogramLength then letters[#letters + 1] = string.upper(string.sub(word, 1, 1)) end
    end
    if #letters == 0 then return "?" end
    return table.concat(letters)
end

-- Timer and status line ------------------------------------------------------------------------------------------

local warningSeconds = 10
local separator = "  ·  "

function lib.FormatTime(seconds)
    local total = math.max(0, math.ceil(seconds))
    return string.format("%d:%02d", math.floor(total / 60), total % 60)
end

function lib.Status(info)
    ---@type string[]
    local parts = { string.upper(info.phase) }
    local remaining = info.remaining or -1
    local timed = remaining >= 0
    if timed then parts[#parts + 1] = lib.FormatTime(remaining) end
    parts[#parts + 1] = string.format("%d/%d", info.humans, info.maxPlayers)
    if info.note ~= nil and info.note ~= "" then parts[#parts + 1] = info.note end
    return { text = table.concat(parts, separator), warning = timed and remaining <= warningSeconds }
end

-- Hint bar -------------------------------------------------------------------------------------------------------

function lib.Hints(state, entries, override)
    local input = lib.Input --[[@as PW.UIInputLib]]
    ---@type PW.UIHintItem[]
    local out = {}
    for _, entry in ipairs(entries) do
        if input.Actions[entry.action] ~= nil then
            local hint = input.Hint(state, entry.action, override)
            out[#out + 1] = { label = entry.label, cap = hint.label, device = hint.device }
        end
    end
    return out
end
