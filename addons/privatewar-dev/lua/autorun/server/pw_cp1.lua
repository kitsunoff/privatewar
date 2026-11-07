-- Dev-only server probes for scripts/deck/cp1.sh (checkpoint CP-1, TASKS.md). Never shipped (T-10.2).
-- Every line starts with "[PW] cp1 " and is key=value, so the script can parse the console log:
--   pw_cp1_state <tag>                   phase machine, the three phase NW2 globals, map and phase ConVars
--   PW_PhaseChange                       one "phase" line per transition, with the NW2 values after publishing
--   pw_cp1_mount <tag> <path>            game.MountGMA(path), path relative to garrysmod/ (shadowing tests)
--   pw_cp1_include <tag> <lua path>      include() a file and print what it returned (shadowing tests)
-- The commands answer the server console and the listen host only (the dev bridge); other players are ignored.

---@type string[]
local cvarNames = { "pw_countdown", "pw_postmatch_time", "pw_vote_time", "pw_prematch_timeout", "pw_aftermatch" }

---@param name string
---@return string
local function cvarValue(name)
    local cv = GetConVar(name)
    if cv == nil then return "?" end
    return cv:GetString()
end

---@return string
local function nw2Fields()
    return string.format("nwphase=%s nwseq=%d nwend=%.2f now=%.2f map=%s",
        GetGlobal2String("pw_phase", "?"), GetGlobal2Int("pw_phase_seq", -1), GetGlobal2Float("pw_phase_end", -2),
        CurTime(), game.GetMap())
end

---The server console or the listen host: on a listen server game.ConsoleCommand (the dev bridge) runs the
---command as the host player, not with a NULL player.
---@param ply any
---@return boolean
local function fromConsole(ply)
    return not IsValid(ply) or (ply --[[@as Player]]):IsListenServerHost()
end

---@param tag string?
---@return string
local function tagOf(tag)
    if tag == nil or tag == "" then return "-" end
    return tag
end

concommand.Add("pw_cp1_state", function(ply, _, args)
    if not fromConsole(ply) then return end
    local match = PW ~= nil and PW.Match or nil
    local machine, abort = "?", ""
    if match ~= nil then
        machine = match.GetPhase()
        abort = tostring(match.GetAbortReason() or "")
    end
    local changing = PW ~= nil and PW.MapChange ~= nil and PW.MapChange.IsChanging() or false
    ---@type string[]
    local cvars = {}
    for _, name in ipairs(cvarNames) do cvars[#cvars + 1] = name .. "=" .. cvarValue(name) end
    -- The abort reason may contain spaces: it is the last field and runs to the end of the line.
    print(string.format("[PW] cp1 state tag=%s phase=%s %s changing=%s %s abort=%s", tagOf(args[1]), machine,
        nw2Fields(), tostring(changing), table.concat(cvars, " "), abort))
end, nil, "Private War dev (CP-1): print the phase state in one line")

hook.Add("PW_PhaseChange", "pw_cp1", function(to, from, endsAt)
    print(string.format("[PW] cp1 phase from=%s to=%s ends=%.2f %s", tostring(from), tostring(to), endsAt,
        nw2Fields()))
end)

concommand.Add("pw_cp1_mount", function(ply, _, args)
    if not fromConsole(ply) then return end
    local path = args[2] or ""
    local ok, files = game.MountGMA(path)
    local count = istable(files) and #files or 0
    print(string.format("[PW] cp1 mount tag=%s ok=%s files=%d path=%s", tagOf(args[1]), tostring(ok), count, path))
end, nil, "Private War dev (CP-1): mount a GMA (path relative to garrysmod/)")

concommand.Add("pw_cp1_include", function(ply, _, args)
    if not fromConsole(ply) then return end
    local path = args[2] or ""
    local ok, result = pcall(include, path)
    local found = file.Exists(path, "LUA")
    print(string.format("[PW] cp1 include tag=%s ok=%s exists=%s winner=%s path=%s", tagOf(args[1]), tostring(ok),
        tostring(found), ok and tostring(result) or "none", path))
end, nil, "Private War dev (CP-1): include a Lua file and print what it returned")
