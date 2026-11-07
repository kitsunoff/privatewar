-- Map marking module (T-2.10; 03-mapdata.md d.5; docs/api/map.md "pw_mark"). Owns PW.MapMark: the authoring tool
-- that prints one Lua line for the caller's position, to paste into lua/privatewar/maps/<id>.lua. Shared: the
-- privilege name and the pure formatter, parser and argument rules (plain data in, plain data out). The console
-- command (position, privilege check, printing): init.lua. Spawn and dom are the kinds the design names; a mode
-- cannot add its own kind yet (the map module does not know mode rules, d.6).

MODULE.Name = "Map marking"

local lib = (rawget(PW, "MapMark") or {}) --[[@as PW.MapMarkLib]]
PW.MapMark = lib

lib.Privilege = "pw.map.mark"

local usage = "usage: pw_mark spawn [team] | pw_mark dom <letter> | pw_mark header"
local maxTeam = 16

---A number with at most two decimals, never in exponent form, "-0" never.
---@param value number
---@return string
local function num(value)
    local text = string.format("%.2f", value)
    if string.find(text, ".", 1, true) then
        text = string.gsub(text, "0+$", "")
        text = string.gsub(text, "%.$", "")
    end
    if text == "-0" then return "0" end
    return text
end

---Yaw normalised to [-180, 180) with one decimal at most.
---@param yaw number
---@return number
local function normalYaw(yaw)
    local wrapped = (yaw + 180) % 360 - 180
    return math.floor(wrapped * 10 + 0.5) / 10
end

---@param pos Vector
---@return string
local function vectorText(pos)
    return string.format("Vector(%s, %s, %s)", num(pos.x), num(pos.y), num(pos.z))
end

function lib.Format(kind, pos, yaw)
    if kind == "dom" then return vectorText(pos) end
    return string.format("{ pos = %s, yaw = %s }", vectorText(pos), num(normalYaw(yaw)))
end

local numberPattern = "(-?%d+%.?%d*)"
local vectorPattern = "Vector%(" .. numberPattern .. ", " .. numberPattern .. ", " .. numberPattern .. "%)"

function lib.Parse(line)
    local x, y, z = string.match(line, "^" .. vectorPattern .. "$")
    if x ~= nil then
        return { kind = "dom", pos = Vector(tonumber(x), tonumber(y), tonumber(z)) }
    end
    local sx, sy, sz, yaw = string.match(line, "^{ pos = " .. vectorPattern .. ", yaw = " .. numberPattern .. " }$")
    if sx == nil then return nil, "not a pw_mark entry line" end
    return { kind = "spawn", pos = Vector(tonumber(sx), tonumber(sy), tonumber(sz)), yaw = tonumber(yaw) }
end

function lib.ParseArgs(args)
    local sub = args[1]
    if sub == "header" then return { kind = "header" } end
    if sub == "spawn" then
        local team = 1
        if args[2] ~= nil then
            team = tonumber(args[2]) or -1
            if team < 0 or team > maxTeam or team ~= math.floor(team) then return nil, usage end
        end
        return { kind = "spawn", team = team }
    end
    if sub == "dom" then
        local letter = args[2]
        if letter == nil or not string.match(letter, "^%a$") then return nil, usage end
        return { kind = "dom", letter = string.upper(letter) }
    end
    return nil, usage
end

function lib._Build(args, pos, yaw, mapName)
    if args.kind == "header" then
        local path = "lua/privatewar/maps/" .. (PW.Map --[[@as PW.MapLib]]).Id(mapName) .. ".lua"
        return { "-- " .. path, "MAP.Name = \"" .. mapName .. "\"" }
    end
    if args.kind == "spawn" then
        return { "-- MAP.Spawns[" .. tostring(args.team) .. "]", lib.Format("spawn", pos, yaw) }
    end
    if args.kind == "dom" then
        return { "-- MAP.Modes.dom.flags." .. tostring(args.letter), lib.Format("dom", pos, yaw) }
    end
    return nil
end
