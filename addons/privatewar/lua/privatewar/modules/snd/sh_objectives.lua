-- Public objective facts only: defender orders never reveal the hidden carrier or dropped-bomb coordinates.
local lib = PW.SND --[[@as PW.SNDLib]]

---@param state PW.SNDState
---@param team integer
---@param carrierOnly boolean
---@return table<integer, boolean>
local function eligible(state, team, carrierOnly)
    ---@type table<integer, boolean>
    local out = {}
    for id, member in pairs(state.roster) do
        if member.connected and member.alive and member.team == team and (not carrierOnly or state.carrier == id) then
            out[member.userId] = true
        end
    end
    return out
end

---@param state PW.SNDState
---@param team integer
---@param site PW.SNDSite
---@param action string
---@param want integer
---@return PW.BotObjective
local function objective(state, team, site, action, want)
    return { id = "snd_" .. site.id .. "_" .. action, pos = site.approach, radius = site.radius,
        action = action, weight = 1, want = want, revision = state.generation,
        eligible = eligible(state, team, action == "plant"),
        zone = { pos = site.pos, radius = site.radius, above = site.above, below = site.below } }
end

function lib.Objectives(state, team)
    if state.phase == "resolved" or (team ~= 1 and team ~= 2) then return {} end
    if state.phase == "planted" then
        local site = state.map.sites[1]
        for _, entry in ipairs(state.map.sites) do if entry.id == state.site then site = entry end end
        local obj = objective(state, team, site, team == 1 and "hold" or "defuse", team == 1 and 128 or 1)
        obj.pos = state.pos
        if team == 2 then
            obj.radius = 72
            obj.zone = { pos = state.pos, radius = 48, above = 48, below = 16 }
        end
        return { obj }
    end
    if team == 1 and state.phase == "dropped" then
        return { { id = "snd_bomb", pos = state.pos, radius = 32, action = "collect", weight = 1, want = 1,
            revision = state.generation, eligible = eligible(state, 1, false) } }
    end
    if team == 1 then return { objective(state, team, state.map.sites[1], "plant", 1) } end
    ---@type PW.BotObjective[]
    local out = {}
    for i, site in ipairs(state.map.sites) do out[i] = objective(state, team, site, "hold", 128) end
    return out
end
