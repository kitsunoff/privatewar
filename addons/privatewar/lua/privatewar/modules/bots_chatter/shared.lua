-- Independent installed-content adapter, never a dependency on Lambda's entity/AI implementation.
MODULE.Name = "Installed Lambda chatter"
MODULE.Settings = {
    enabled = { scope = "server", type = "bool", default = false, label = "Use installed Lambda names and chatter" },
    voice = { scope = "server", type = "bool", default = true, label = "Bot spatial voice" },
    chat = { scope = "server", type = "bool", default = true, label = "Bot global text chat" },
    interval = { scope = "server", type = "float", default = 20, min = 5, max = 120,
        label = "Minimum bot chatter interval (seconds)" },
    speakers = { scope = "server", type = "int", default = 2, min = 1, max = 4,
        label = "Maximum simultaneous bot voices" },
    volume = { scope = "client", type = "float", default = 1, min = 0, max = 1,
        label = "Bot voice volume (0 mutes)" }
}

local lib = (rawget(PW, "BotChatter") or {}) --[[@as PW.BotChatterLib]]
PW.BotChatter = lib

---@param path any
---@return boolean
function lib._SoundPath(path)
    if type(path) ~= "string" or #path > 240 or path:find("..", 1, true) or path:find("[\\:%c]") then return false end
    -- Explicit roots only; no arbitrary GAME paths or remote URLs.
    local root = path:find("^lambdaplayers/vo/") ~= nil or path:find("^lambdaplayers/voiceprofiles/") ~= nil
        or path:find("^zetaplayer/custom_vo/vp_") ~= nil
    local extension = string.lower(string.GetExtensionFromFilename(path) or "")
    return root and (extension == "wav" or extension == "mp3" or extension == "ogg")
end

---@param value any
---@return string?
function lib._Name(value)
    if type(value) ~= "string" or #value > 32 or value:find("%c") or not utf8.len(value) then return nil end
    value = string.Trim(value)
    if value == "" then return nil end
    return value
end

---@param value any
---@param target string?
---@return string?
function lib._Text(value, target)
    if type(value) ~= "string" or #value > 4096 or value:find("%c") or not utf8.len(value) then return nil end
    if value:find("/keyent/", 1, true) then
        if target == nil then return nil end
        value = string.Replace(value, "/keyent/", target)
    end
    -- Lambda conditional/keyword syntax is not executable PW content. Never send chat commands.
    if value:find("/[%w_]+/") or value:find("|[%w_]+|") then return nil end
    value = string.Trim(value)
    if value == "" or #value > 126 or value:find("%c") or not utf8.len(value) then return nil end
    if value:sub(1, 1) == "!" or value:sub(1, 1) == "/" then return nil end
    return value
end

---@param names string[]
---@param taken table<string, boolean>
---@param roll number
---@return string?
function lib._NameFrom(names, taken, roll)
    ---@type string[]
    local open = {}
    for _, name in ipairs(names) do
        if not taken[string.lower(name)] then open[#open + 1] = name end
    end
    if #open == 0 then return nil end
    return open[math.Clamp(math.floor(roll * #open) + 1, 1, #open)]
end

---@param state PW.ChatterState
---@param now number
---@param nextGlobal number
---@param active integer
---@param limit integer
---@return boolean
function lib._CanSpeak(state, now, nextGlobal, active, limit)
    return now >= state.next and now >= state.speaking and now >= nextGlobal and active < limit
end

---@param profile PW.ChatterLines?
---@param common PW.ChatterLines
---@param event string
---@param roll number
---@return string?
function lib._Line(profile, common, event, roll)
    local lines = profile ~= nil and profile[event] or nil
    if lines == nil or #lines == 0 then lines = common[event] end
    if lines == nil or #lines == 0 then return nil end
    return lines[math.Clamp(math.floor(roll * #lines) + 1, 1, #lines)]
end

---@param contacts table<string, any>[]
---@return boolean
function lib._Visible(contacts)
    for _, contact in ipairs(contacts) do
        if contact.visible and contact.source == "sight" then return true end
    end
    return false
end

---@param states table<any, PW.ChatterState>
---@param bot any
---@param voices string[]
---@param texts string[]
---@param roll number
---@param now number
---@return PW.ChatterState
function lib._Identity(states, bot, voices, texts, roll, now)
    if states[bot] ~= nil then return states[bot] end
    ---@param list string[]
    ---@return string?
    local index = function(list) return list[math.Clamp(math.floor(roll * #list) + 1, 1, math.max(1, #list))] end
    local state = { next = now + 5 + roll * 15, speaking = 0, voice = index(voices), text = index(texts) }
    states[bot] = state
    return state
end
