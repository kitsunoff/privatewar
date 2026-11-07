-- Dev-only GLuaTest start gate for the listen server on the Steam Deck. Never shipped to the Workshop.
-- GLuaTest starts its run on the first server tick, before the host has connected. Test groups that create
-- bots then take player slot 1, the host lands in a later slot, IsListenServerHost() is false for it and it
-- does not get the automatic superadmin usergroup, so commands from the dev bridge (attributed to the host)
-- are denied. This gate replaces GLuaTest's first-tick start: the run begins when the listen host's client has
-- finished loading, or after a timeout when no host joins. Dedicated servers keep GLuaTest's own start.
-- "Finished loading" is the host's first usercmd that is not forced (StartCommand, the wiki's pattern for a loaded
-- client), plus a short delay. Starting at PlayerInitialSpawn was too early: the client was still loading, and the
-- requests it sends from its InitPostEntity (pw_lobby_request) reached the server while test groups had swapped
-- the module stores, so the answer was lost and the lobby screen stayed empty (found by scripts/deck/cp1.sh).
-- Every map load on a listen server prints "[PW] testgate: host <name> loaded" at that moment (with or without
-- GLuaTest): scripts/deck/snap.sh waits for it after its map reload. A map reload is the only way to show new client
-- Lua on the host's screen (pw_reload refreshes the server only, see sh_reload.lua), and snap.sh does not want the
-- whole suite on it: it writes data/privatewar_dev/skip_tests.txt first, and this gate consumes the flag on the next
-- Initialize and skips that one run. scripts/deck/test.sh removes a stale flag before its own map load.

---@type string GLuaTest's own Tick hook that starts the run on the first tick
local runnerHook = "GLuaTest_Runner"

---@type number seconds to wait for the listen host before running the tests anyway
local hostTimeout = 60

---@type string
local timeoutTimer = "PW_TestGate_Timeout"

---@type string
local spawnHook = "PW_TestGate"

---@type number seconds after the host's first real usercmd before the run starts
local settleDelay = 2

---@type string one-shot flag (DATA path) written by scripts/deck/snap.sh: skip the next run
local skipFile = "privatewar_dev/skip_tests.txt"

---@type string DATA path of the backup of the match ConVars that test files override (an interrupted run leaves it)
local backupFile = "privatewar_dev/convars_backup.json"

---@type string[] FCVAR_ARCHIVE ConVars that test files shorten or switch and restore themselves. A test whose own
---restore never runs (an async timeout) would leave them, for example a 0.5 s POSTMATCH that jumps straight to the
---lobby, so the end of every run restores them from the backup too (finishRun), not only an interrupted run.
local guardedConVars = { "pw_prematch_timeout", "pw_countdown", "pw_postmatch_time", "pw_aftermatch", "pw_vote_time" }

local started = false

---Writes the current values of the named ConVars to a JSON file. Unknown ConVars (get returns nil) are skipped.
---@param path string DATA path
---@param names string[]
---@param get fun(name: string): string?
---@return boolean written
local function backupConVars(path, names, get)
    ---@type table<string, string>
    local values = {}
    for _, name in ipairs(names) do
        local value = get(name)
        if value ~= nil then values[name] = value end
    end
    file.CreateDir("privatewar_dev")
    file.Write(path, util.TableToJSON(values))
    return file.Exists(path, "DATA")
end

---Restores the values of a backup and deletes it. Returns the number restored, or nil when there is no usable backup
---(a corrupt file is deleted too).
---@param path string DATA path
---@param set fun(name: string, value: string)
---@return integer?
local function restoreConVars(path, set)
    if not file.Exists(path, "DATA") then return nil end
    local values = util.JSONToTable(file.Read(path, "DATA") or "") --[[@as table<string, string>?]]
    file.Delete(path)
    if values == nil then return nil end
    local count = 0
    for name, value in pairs(values) do
        set(name, tostring(value))
        count = count + 1
    end
    return count
end

---Deletes the backup (a run ended normally). Returns whether it was there.
---@param path string DATA path
---@return boolean
local function discardBackup(path)
    if not file.Exists(path, "DATA") then return false end
    file.Delete(path)
    return true
end

---The end of a run: restores the backup (the values before the run) and deletes it. Returns the number restored, nil
---without a backup.
---@param path string DATA path
---@param set fun(name: string, value: string)
---@return integer?
local function finishRun(path, set)
    return restoreConVars(path, set)
end

---@param name string
---@return string?
local function liveGet(name)
    local cvar = GetConVar(name)
    return cvar and cvar:GetString() or nil
end

---@param name string
---@param value string
local function liveSet(name, value)
    local cvar = GetConVar(name)
    if cvar then cvar:SetString(value) end
end

---Removes a one-shot flag file. Returns whether it was there.
---@param path string DATA path
---@return boolean
local function consumeFlag(path)
    if not file.Exists(path, "DATA") then return false end
    file.Delete(path)
    return true
end

---Starts the GLuaTest run once, or skips it.
---@param reason string
---@param skip boolean
local function start(reason, skip)
    if started then return end
    started = true
    hook.Remove("PlayerInitialSpawn", spawnHook)
    hook.Remove("StartCommand", spawnHook)
    timer.Remove(timeoutTimer)
    if skip then
        print("[PW] testgate: GLuaTest skipped on this map load (" .. reason .. "; " .. skipFile .. ")")
        return
    end
    print("[PW] testgate: starting GLuaTest (" .. reason .. ")")
    backupConVars(backupFile, guardedConVars, liveGet)
    hook.Add("GLuaTest_Finished", spawnHook, function()
        hook.Remove("GLuaTest_Finished", spawnHook)
        local restored = finishRun(backupFile, liveSet)
        if restored ~= nil then print("[PW] testgate: run finished, restored " .. restored .. " match ConVars") end
    end)
    GLuaTest.runAllTests()
end

---Takes GLuaTest's first-tick start away. Returns whether there was one.
---@return boolean
local function takeRunner()
    if GLuaTest == nil then return false end
    local tickHooks = hook.GetTable()["Tick"] --[[@as table<string, function>?]]
    if tickHooks == nil or tickHooks[runnerHook] == nil then return false end
    hook.Remove("Tick", runnerHook)
    return true
end

---The host has loaded: one log line, then the run (when GLuaTest is gated).
---@param ply Player
---@param gated boolean
---@param skip boolean
local function hostLoaded(ply, gated, skip)
    local name = IsValid(ply) and ply:Nick() or "?"
    print("[PW] testgate: host " .. name .. " loaded")
    if gated then start("host " .. name .. " loaded", skip) end
end

---Announces the loaded listen host and replaces GLuaTest's first-tick start with a start after it.
local function install()
    if game.IsDedicated() then return end
    local restored = restoreConVars(backupFile, liveSet)
    if restored ~= nil then
        print("[PW] testgate: interrupted run found, restored " .. restored .. " match ConVars from " .. backupFile)
    end
    local skip = consumeFlag(skipFile)
    local gated = takeRunner()
    if gated and not skip then
        print("[PW] testgate: GLuaTest waits for the listen host (up to " .. hostTimeout .. "s)")
    end

    hook.Add("PlayerInitialSpawn", spawnHook, function(ply)
        if not ply:IsListenServerHost() then return end
        hook.Remove("PlayerInitialSpawn", spawnHook)
        hook.Add("StartCommand", spawnHook, function(cmdPly, cmd)
            if cmdPly ~= ply or cmd:IsForced() then return end
            hook.Remove("StartCommand", spawnHook)
            timer.Simple(settleDelay, function() hostLoaded(ply, gated, skip) end)
        end)
    end)
    if gated then
        timer.Create(timeoutTimer, hostTimeout, 1, function()
            start("no listen host after " .. hostTimeout .. "s", skip)
        end)
    end
end

-- Initialize runs after every autorun file (GLuaTest's included) and before the first tick.
hook.Add("Initialize", "PW_TestGate", function()
    if PW ~= nil then rawset(PW, "_DevTestGate", {
        ConsumeFlag = consumeFlag,
        Backup = backupConVars,
        Restore = restoreConVars,
        Discard = discardBackup,
        Finish = finishRun,
        Guarded = guardedConVars
    }) end
    install()
end)
