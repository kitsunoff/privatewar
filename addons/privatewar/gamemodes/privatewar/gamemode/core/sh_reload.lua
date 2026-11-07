-- Hot reload (T-1.15, 01-extensibility.md d.12). Shared. PW.Reload.Run reloads this realm: PW.Loader.Boot rescans
-- every kind folder (new files are found, a changed file replaces its entry), resolves Base and fires
-- PW_RegistriesLoaded. It runs from GM:OnReloaded (auto refresh, each realm on its own), from the pw_reload command
-- on the server (sv_reload.lua) and on every client when the server sends pw_reload.
-- A reload does not touch the running match: the active mode stays valid (PW.Loader._KeepFor) and the match
-- snapshots of PW.Enable and PW.Settings are kept; reloaded definitions take effect at the next match.
-- Clients run only files the server sent with AddCSLuaFile, from the server's Lua datapack filled at map load.
-- Measured on the listen server host (Deck, 2026-11-07): after pw_reload the client still runs the map-load content
-- of a changed file and still finds a file deleted since; a new file is found only one pw_reload later. A map reload
-- (or reconnect) is the way to run new client code: scripts/deck/snap.sh reloads the map. Remote clients are not
-- better off. Auto refresh of a gamemode file also re-runs shared.lua, which boots once more.

local reload = (rawget(PW, "Reload") or {}) --[[@as PW.ReloadLib]]
PW.Reload = reload

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

local function boot()
    PW.Loader.Boot()
end

local function send()
    net.Start("pw_reload")
    net.Broadcast()
end

-- One tick later: the client's list of downloadable Lua files (updated by the server's AddCSLuaFile during the
-- reload) reaches the client after a message sent in the same tick, so a client reloading at once misses new files.
-- Measured on the Deck (listen server host): sent at once, a new file was missing on the client in 2 of 2 runs;
-- sent one tick later, it was found in 2 of 2 runs.
local function broadcast()
    if SERVER then timer.Simple(0, send) end
end

function reload._NewStore(opts)
    opts = opts or {}
    return {
        log = opts.log or defaultLog,
        boot = opts.boot or boot,
        broadcast = opts.broadcast or broadcast
    }
end

PW._Reload = PW._Reload or reload._NewStore()

function reload._Summary(registries)
    ---@type string[]
    local kinds = {}
    for kindId in pairs(registries) do kinds[#kinds + 1] = kindId end
    table.sort(kinds)
    ---@type string[]
    local parts = {}
    for _, kindId in ipairs(kinds) do
        parts[#parts + 1] = kindId .. " " .. #registries[kindId].GetList()
    end
    return table.concat(parts, ", ")
end

function reload.Run(reason)
    local store = PW._Reload
    local realm = SERVER and "server" or "client"
    local ok, err = pcall(store.boot)
    if not ok then
        store.log(string.format("reload (%s, %s) failed: %s", realm, reason, tostring(err)))
        return false
    end
    store.log(string.format("reloaded (%s, %s): %s", realm, reason, reload._Summary(PW.Registries or {})))
    return true
end

-- GM:OnReloaded, set through rawset because the GLua API annotations already declare the method.
rawset(GM, "OnReloaded", function() reload.Run("auto refresh") end)

if CLIENT then
    net.Receive("pw_reload", function() reload.Run("pw_reload from the server") end)
end
