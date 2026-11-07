-- Map marking module, server glue (T-2.10; 03-mapdata.md d.5). The pw_mark console command: checks the privilege,
-- reads the caller's position and yaw and prints the lines of PW.MapMark._Build to the caller's console and to the
-- server log. The server console has no position and is refused.

local lib = PW.MapMark --[[@as PW.MapMarkLib]]

PW.Privilege(lib.Privilege, "superadmin")

---Default output: the caller's console and the server log.
---@param ply Player
---@param line string
local function printLine(ply, line)
    ply:PrintMessage(HUD_PRINTCONSOLE, line .. "\n")
    print(line)
end

function lib._Command(ply, args, out)
    out = out or printLine
    if not IsValid(ply) then
        print("[PW] pw_mark needs a player position: run it from the game console, not the server console")
        return false
    end
    local caller = ply --[[@as Player]]
    if not PW.Can(caller, lib.Privilege) then
        print(string.format("[PW] pw_mark denied for %s", caller:Nick()))
        return false
    end
    local parsedArgs, usage = lib.ParseArgs(args)
    if parsedArgs == nil then
        out(caller, usage or "usage: pw_mark spawn [team] | pw_mark dom <letter> | pw_mark header")
        return false
    end
    local lines = lib._Build(parsedArgs, caller:GetPos(), caller:EyeAngles().y, game.GetMap())
    if lines == nil then return false end
    for _, line in ipairs(lines) do out(caller, line) end
    return true
end

concommand.Add("pw_mark", function(ply, _, args) lib._Command(ply, args) end, nil,
    "Private War: print a map-data line for your position (spawn [team], dom <letter>, header); needs pw.map.mark")
