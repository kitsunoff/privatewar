-- Dev-only command bridge for the Steam Deck dev loop (TASKS.md, "Dev loop on the Steam Deck").
-- scripts/deck/cmd.sh appends console commands to data/privatewar_dev/cmd.txt; this file runs them
-- on the server once per second while pw_dev is 1 (the default: this addon only exists on dev machines;
-- a "+pw_dev 1" launch argument would be lost because it runs before this ConVar exists).
-- Never shipped to the Workshop.

---@type string
local cmdFile = "privatewar_dev/cmd.txt"

---@type number seconds between polls
local pollInterval = 1

local cvDev = CreateConVar("pw_dev", "1", nil, "Enable Private War dev tools (command bridge)", 0, 1)

---Reads and clears the queued commands.
---@return string[] commands non-empty lines, in order
local function takeQueuedCommands()
    local raw = file.Read(cmdFile, "DATA")
    if raw == nil or raw == "" then
        return {}
    end
    file.Write(cmdFile, "")

    ---@type string[]
    local commands = {}
    for line in string.gmatch(raw, "[^\r\n]+") do
        local trimmed = string.Trim(line)
        if trimmed ~= "" then
            commands[#commands + 1] = trimmed
        end
    end
    return commands
end

---Runs one bridge line and logs it with the [PW] tag.
---Prefixes:
---  "lua <code>"      run Lua on the server (game.ConsoleCommand blocks lua_run, echo and similar)
---  "client <cmd>"    run a console command on the listen host's client (screenshots: "client jpeg")
---  anything else     server console command via game.ConsoleCommand (map, changelevel, pw_reload, ...)
---@param line string
local function runLine(line)
    print("[PW] devbridge: " .. line)

    local luaCode = string.match(line, "^lua%s+(.+)$")
    if luaCode ~= nil then
        local err = RunString(luaCode, "pw_devbridge", false)
        if err ~= nil then
            print("[PW] devbridge lua error: " .. tostring(err))
        end
        return
    end

    local clientCmd = string.match(line, "^client%s+(.+)$")
    if clientCmd ~= nil then
        local host = Entity(1)
        if IsValid(host) and host:IsPlayer() then
            ---@cast host Player
            host:ConCommand(clientCmd)
        else
            print("[PW] devbridge: no host player for client command")
        end
        return
    end

    game.ConsoleCommand(line .. "\n")
end

local function poll()
    if not cvDev:GetBool() then
        return
    end
    for _, command in ipairs(takeQueuedCommands()) do
        runLine(command)
    end
end

file.CreateDir("privatewar_dev")
timer.Create("PW_DevBridge", pollInterval, 0, poll)
print("[PW] devbridge loaded (pw_dev=" .. cvDev:GetString() .. ")")
