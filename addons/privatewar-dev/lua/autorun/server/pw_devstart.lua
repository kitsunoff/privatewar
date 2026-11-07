-- Dev-only: "pw_dev_start [map]" starts a match of the dummy mode (lua/privatewar/modes/pw_dummy.lua) through
-- PW.Match.Start, and every phase change is printed to the log. Never shipped (T-10.2).
--
-- Checkpoint CP-1 item 2 (TASKS.md), from the Mac while the game runs on the Deck:
--   1. Optional, shorter phases: bash scripts/deck/cmd.sh "pw_countdown 5" "pw_postmatch_time 5"
--   2. bash scripts/deck/cmd.sh pw_dev_start            (pw_aftermatch lobby: ends back in LOBBY)
--   3. bash scripts/deck/logs.sh --once                 "[PW] dev: phase ..." lines, LOBBY -> PREMATCH ->
--      PREMATCH (countdown) -> LIVE -> POSTMATCH -> LOBBY; "ends in" is pw_phase_end - CurTime().
--   4. Map change: bash scripts/deck/cmd.sh "pw_dev_start gm_flatgrass"; the new map comes up in PREMATCH.
--   5. Restore what step 1 changed: bash scripts/deck/cmd.sh "pw_countdown 10" "pw_postmatch_time 15"

---@type string
local privilege = "pw.dev.start"

---@param ply any nil or NULL for the server console (the dev bridge)
---@param args string[]
local function devStart(ply, args)
    if PW == nil or PW.Match == nil or PW.Modes == nil then
        print("[PW] dev: pw_dev_start needs the Private War gamemode")
        return
    end
    if IsValid(ply) then
        if PW._Privileges.defs[privilege] == nil then PW.Privilege(privilege, "superadmin") end
        if not PW.Can(ply, privilege) then
            print(string.format("[PW] dev: pw_dev_start denied for %s", tostring(ply:Nick())))
            return
        end
    end
    local mode = PW.Modes.Get("pw_dummy")
    if mode == nil then
        print("[PW] dev: mode pw_dummy is not registered")
        return
    end
    ---@type string?
    local map = args[1]
    if map == "" then map = nil end
    print(string.format("[PW] dev: pw_dev_start pw_dummy on %s", map or game.GetMap()))
    PW.Match.Start(mode, map)
end

concommand.Add("pw_dev_start", function(ply, _, args) devStart(ply, args) end, nil,
    "Private War dev: start a match of the dummy mode [map]")

hook.Add("PW_PhaseChange", "pw_devstart", function(to, from, endsAt)
    local ends = endsAt >= 0 and string.format("ends in %.1f s", endsAt - CurTime()) or "no end"
    print(string.format("[PW] dev: phase %s -> %s (%s)", tostring(from), tostring(to), ends))
end)
