-- In-match menus (T-7.6; 10-frontend.md d.1, d.7; 05-loadout.md d.12; 00-core.md "abort and return to lobby"):
-- the death class picker and the pause menu. Pure and shared, so the server-side test runner covers it: the picker's
-- card model, the class choice, the pause items per phase and privilege, the Escape decision (with its fallbacks to
-- the GMod menu; at the lobby hub root Escape or Back offers to leave) and the death watcher. The client glue is
-- cl_match.lua; the screens are screens/match_pause.lua and screens/match_classes.lua. The client decides nothing:
-- the server repairs and checks every pick and abort again.

local lib = (rawget(PW, "UI") or {}) --[[@as PW.UILib]]
PW.UI = lib

-- Client settings (01-extensibility.md d.17): pw_ui_kit_pausemenu and pw_ui_kit_deathpicker. Turning the pause menu
-- off gives Escape back to the GMod menu entirely.
local moduleTable = rawget(_G, "MODULE")
if moduleTable ~= nil then
    moduleTable.Settings = moduleTable.Settings or {}
    moduleTable.Settings.pausemenu = {
        scope = "client", type = "bool", default = true, label = "Escape opens the match menu"
    }
    moduleTable.Settings.deathpicker = {
        scope = "client", type = "bool", default = true, label = "Class picker on death"
    }
end

local match = (rawget(lib, "Match") or {}) --[[@as PW.UIMatchLib]]
lib.Match = match

match.PausePhases = { PREMATCH = true, LIVE = true, POSTMATCH = true }
match.LeaveHostText = "You are the host: leaving closes the server for everyone."
match.LeaveGuestText = "You leave the server. You can join again while the match runs."
match.LobbyText = "End the match for everyone and return to the lobby?"
match.LobbyGuestText = "You leave the server. You can join again while it runs."

---@param state? PW.LoadoutClassState
---@return string?
local function currentOf(state)
    if state == nil or state.selected == "" then return nil end
    return state.selected
end

function match.ClassCards(state)
    ---@type PW.UICard[]
    local cards = {}
    local current = currentOf(state)
    for index, entry in ipairs(state ~= nil and state.entries or {}) do
        local tags = string.sub(entry.ref, 1, 7) == "custom:" and "Custom class" or "Preset"
        ---@type PW.UICard
        local card = { id = entry.ref, title = entry.name, tags = tags, locked = false }
        if not entry.available then
            card.locked, card.badge, card.text = true, "N/A", entry.reason
            card.reason = "Not available: " .. (entry.reason or "")
        elseif entry.ref == current then
            card.badge, card.text = "CURRENT", "In use from your next spawn."
        end
        cards[index] = card
    end
    return cards, current
end

function match.Choose(state, ref, send)
    for _, entry in ipairs(state ~= nil and state.entries or {}) do
        if entry.ref == ref then
            if not entry.available then return "locked" end
            if ref == currentOf(state) then return "current" end
            send(ref)
            return "sent"
        end
    end
    return "unknown"
end

---@param id PW.UIPauseItemId
---@param label string
---@param reason? string the lock reason; nil means usable
---@return PW.UIPauseItem
local function item(id, label, reason)
    return { id = id, label = label, locked = reason ~= nil, reason = reason }
end

---@param facts PW.UIPauseFacts
---@return string?
local function classReason(facts)
    if not facts.classes then return "Classes are not available" end
    if facts.phase ~= "PREMATCH" and facts.phase ~= "LIVE" then return "The match is over" end
    return nil
end

function match.PauseItems(facts)
    local resume = item("resume", "RESUME")
    resume.variant = "primary"
    local lobby = item("lobby", "RETURN TO LOBBY", not facts.canAbort and "Only the host can end the match" or nil)
    lobby.confirm = match.LobbyText
    local leave = item("leave", "LEAVE GAME")
    leave.variant, leave.confirm = "danger", facts.host and match.LeaveHostText or match.LeaveGuestText
    local gmod = item("gmod", "GMOD MENU")
    gmod.variant = "secondary"
    return {
        resume, item("class", "CHANGE CLASS", classReason(facts)), item("settings", "SETTINGS"), lobby, leave, gmod
    }
end

function match.RootBack(facts)
    if facts.phase == "LOBBY" and facts.rootId == "hub" and (facts.depth or 1) <= 1 then return "leave" end
    return "router"
end

function match.Escape(facts)
    if facts.bypass or facts.gameUI then return "engine" end
    if facts.rootOpen then
        if not facts.modal and match.RootBack(facts --[[@as PW.UIRootBackFacts]]) == "leave" then return "leave" end
        return "root"
    end
    if not facts.enabled or not match.PausePhases[facts.phase] then return "engine" end
    return "pause"
end

function match.LobbyLeave(host)
    return {
        title = "Leave game", text = host and match.LeaveHostText or match.LobbyGuestText,
        confirm = "LEAVE GAME", alt = "GMOD MENU", cancel = "CANCEL"
    }
end

function match.NewDeathMemory()
    return {}
end

function match.DeathStep(memory, facts)
    local was = memory.alive
    memory.alive = facts.alive
    if facts.open and (facts.alive or facts.phase ~= "LIVE") then return "close" end
    if was ~= true or facts.alive or facts.open then return nil end
    if facts.phase ~= "LIVE" or not facts.enabled or facts.otherRoot then return nil end
    return "open"
end
