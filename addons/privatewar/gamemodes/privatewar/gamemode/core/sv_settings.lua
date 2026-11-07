-- Settings on the server (T-1.5, 01-extensibility.md d.17; 00-core.md d.7, d.8, d.9). The match snapshot is taken
-- by PW.Match when a new match enters PREMATCH, right after the enable snapshot, from the host's pending values
-- (defaults for the rest) of the mode and the enabled modules, and stays fixed until the next match. Changes come
-- from clients as two messages through PW.Net.Receive, both behind the "pw.settings.change" privilege:
-- pw_settings_match (LOBBY only; edits the pending values of the next match) and pw_settings_server (any phase;
-- writes the ConVar). Each carries the full id and the value as two strings (sh_settings.lua _Format). The
-- pending match file carries the would-be snapshot across changelevel; the new map restores it as pending values.

local settingsLib = PW.Settings

-- Bytes of one change message: two strings; a set value is a comma-separated list of ids.
local maxLen = 1024
-- Messages per second per player; a settings form sends one per edited control.
local rate = 10

---@param mode table?
---@return PW.SettingValues
local function snapshotFor(mode)
    local store = PW._Settings
    return settingsLib._TakeSnapshot(mode, settingsLib._EnabledModules(), store.pending, settingsLib._LogOnce)
end

function settingsLib._NewMatch(mode)
    PW._Settings.snapshot = snapshotFor(mode)
end

function settingsLib._EndMatch()
    PW._Settings.snapshot = nil
end

function settingsLib._ForFile(mode)
    return snapshotFor(mode)
end

function settingsLib._FromFile(values)
    local store = PW._Settings
    local index = settingsLib._CurrentIndex()
    store.pending = {}
    for id, value in pairs(values) do
        local def = index[id]
        if def == nil or def.scope ~= "match" then
            store.log(string.format("pending match: %q is not a match setting, dropped", tostring(id)))
        else
            local ok, stored, note = settingsLib._Validate(def, value)
            if ok then
                store.pending[id] = stored
            else
                store.log(string.format("pending match: setting %s dropped: %s", id, tostring(note)))
            end
        end
    end
end

---@param ply Player
---@return string
local function senderName(ply)
    if IsValid(ply) then return ply:Nick() end
    return tostring(ply)
end

function settingsLib._OnChange(scope, ply)
    local store = PW._Settings
    local id, text = store.readChange()
    local def = settingsLib._CurrentIndex()[id]
    if def == nil or def.scope ~= scope then
        store.log(string.format("settings change from %s dropped: %q is not a %s setting", senderName(ply),
            tostring(id), scope))
        return false
    end
    local ok, value, note = settingsLib._Parse(def, text)
    local reason = note
    if ok then ok, reason = settingsLib.Set(def.id, value) end
    if not ok then
        store.log(string.format("settings change of %s from %s dropped: %s", def.id, senderName(ply),
            tostring(reason)))
        return false
    end
    store.log(string.format("setting %s set to %s by %s%s", def.id, settingsLib._Format(def, value), senderName(ply),
        note ~= nil and " (" .. note .. ")" or ""))
    return true
end

function settingsLib._RegisterNet()
    local netLib = PW.Net
    if netLib == nil then return end
    netLib.Receive("pw_settings_match", { who = settingsLib.Privilege, phases = { "LOBBY" }, rate = rate,
        maxLen = maxLen }, function(ply) settingsLib._OnChange("match", ply) end)
    netLib.Receive("pw_settings_server", { who = settingsLib.Privilege, rate = rate, maxLen = maxLen },
        function(ply) settingsLib._OnChange("server", ply) end)
end

settingsLib._RegisterNet()
