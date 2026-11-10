-- Lambda format evidence: upstream autorun_includes/shared/filesystem.lua and d_registervoicetypes.lua.
-- Read only mounted files; do not call third-party functions, mutate globals or distribute content.
local lib = PW.BotChatter --[[@as PW.BotChatterLib]]
local definition = MODULE
local events = { "idle", "taunt", "kill", "death" }
local budget = { files = 8192, dirs = 1024, bytes = 8388608 }

---@param path string
---@param realm string
---@return table<any, any>
local function readList(path, realm)
    local size = file.Size(path, realm)
    if size < 1 or size > 1048576 or size > budget.bytes then return {} end
    budget.bytes = budget.bytes - size
    local bytes = file.Read(path, realm)
    if bytes == nil then return {} end
    local data = util.JSONToTable(bytes)
    if istable(data) then return data --[[@as table<any, any>]] end
    local extension = string.GetExtensionFromFilename(path)
    if extension == "json" or extension == "vmt" then return {} end
    return string.Explode("\n", bytes)
end

---@param root string
---@param visit fun(path: string)
local function walk(root, visit)
    local pending, cursor, visited = { root }, 1, 0
    while cursor <= #pending and cursor <= 512 and visited < 8192 and budget.dirs > 0 and budget.files > 0 do
        local dir = pending[cursor]
        cursor = cursor + 1
        budget.dirs = budget.dirs - 1
        local files, dirs = file.Find(dir .. "/*", "GAME", "nameasc")
        ---@cast files string[]
        ---@cast dirs string[]
        for _, name in ipairs(files) do
            if visited >= 8192 or budget.files <= 0 then break end
            visited = visited + 1
            budget.files = budget.files - 1
            visit(dir .. "/" .. name)
        end
        for _, name in ipairs(dirs) do
            if #pending < 512 then pending[#pending + 1] = dir .. "/" .. name end
        end
    end
end

---@param dest string[]
---@param values table<any, any>
---@param names boolean
local function append(dest, values, names)
    for i, value in ipairs(values) do
        if i > 4096 or #dest >= 8192 then break end
        local valid = type(value) == "string" and #value <= 4096 and value or nil
        if names then valid = lib._Name(value) end
        if valid ~= nil then dest[#dest + 1] = valid end
    end
end

---@param root string
---@return table<string, string[]>
local function voiceAt(root)
    ---@type table<string, string[]>
    local result = {}
    for _, event in ipairs(events) do
        result[event] = {}
        walk("sound/" .. root .. "/" .. event, function(path)
            local relative = path:sub(7)
            if lib._SoundPath(relative) then table.insert(result[event], relative) end
        end)
    end
    return result
end

---@param root string
---@param realm string
---@return table<string, string[]>
local function textAt(root, realm)
    ---@type table<string, string[]>
    local result = {}
    local files = file.Find(root .. "/*", realm, "nameasc") --[[@as string[] ]]
    for i, name in ipairs(files) do
        if i > 128 then break end
        local event = string.StripExtension(name):match("^([^_]+)")
        if event ~= nil and table.HasValue(events, event) then
            result[event] = result[event] or {}
            append(result[event], readList(root .. "/" .. name, realm), false)
        end
    end
    return result
end

---@return PW.ChatterContent
local function loadContent()
    budget = { files = 8192, dirs = 1024, bytes = 8388608 }
    ---@type PW.ChatterContent
    local content = { names = {}, voices = {}, texts = {}, voice = {}, text = {}, voiceIds = {}, textIds = {} }
    append(content.names, readList("materials/lambdaplayers/data/names.vmt", "GAME"), true)
    append(content.names, readList("lambdaplayers/customnames.json", "DATA"), true)
    walk("materials/lambdaplayers/data/customnames", function(path)
        append(content.names, readList(path, "GAME"), true)
    end)
    content.voice = voiceAt("lambdaplayers/vo")
    content.text = textAt("materials/lambdaplayers/data/texttypes", "GAME")
    for _, source in ipairs({ { "materials/lambdaplayers/texttypes", "GAME" },
        { "lambdaplayers/texttypes", "DATA" } }) do
        for event, lines in pairs(textAt(source[1], source[2])) do
            content.text[event] = content.text[event] or {}
            append(content.text[event], lines, false)
        end
    end
    local _, voices = file.Find("sound/lambdaplayers/voiceprofiles/*", "GAME", "nameasc")
    ---@cast voices string[]
    for i, id in ipairs(voices) do
        if i > 128 then break end
        content.voices[id] = voiceAt("lambdaplayers/voiceprofiles/" .. id)
        content.voiceIds[#content.voiceIds + 1] = id
    end
    local _, texts = file.Find("materials/lambdaplayers/textprofiles/*", "GAME", "nameasc")
    ---@cast texts string[]
    for i, id in ipairs(texts) do
        if i > 128 then break end
        content.texts[id] = textAt("materials/lambdaplayers/textprofiles/" .. id, "GAME")
        content.textIds[#content.textIds + 1] = id
    end
    return content
end

lib._Discover = loadContent
---@type PW.ChatterContent?
local content
---@return PW.ChatterContent
local function getContent()
    if content == nil then content = loadContent() end
    return content
end

---@param taken table<string, boolean>
---@param roll fun(): number
---@return string?
function lib.PickName(taken, roll)
    if not definition:IsValid() or PW.Setting("bots_chatter.enabled") ~= true then return nil end
    local names = getContent().names
    -- All external names occupied: use the established built-in overflow/fallback instead.
    return lib._NameFrom(names, taken, roll())
end

return getContent
