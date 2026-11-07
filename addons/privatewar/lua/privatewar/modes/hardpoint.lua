-- Occupancy, not ownership: kills retain ordinary rewards but never advance the objective score.
MODE.Base = "tdm"
MODE.Name = "Hardpoint"
MODE.Short = "HP"
MODE.Teams = 2
MODE.MapData = true
MODE.Description = "Occupy the active zone alone as a team. Contested or empty zones score nothing."
MODE.Settings = {
    zonetime = { type = "int", default = 60, min = 5, max = 600, label = "Zone duration (s)" },
    scorelimit = { type = "int", default = 250, min = 1, max = 1000, label = "Score limit (points)" },
    timelimit = { type = "int", default = 600, min = 60, max = 3600, label = "Match duration (s)" }
}

local mode = MODE --[[@as PW.HardpointMode]]
mode._ScoreKey = "pw_hp_score_"

---@param data any
---@return boolean, string?
function mode:ValidateMapData(data)
    local module = PW.Modules.Get("hardpoint")
    if PW.Hardpoint == nil or not IsValid(module) then return false, "Hardpoint module unavailable" end
    return PW.Hardpoint.ValidateLayout(data)
end

function mode:Start()
    assert(IsValid(PW.Modules.Get("hardpoint")), "Hardpoint module unavailable")
    assert(PW.Hardpoint, "Hardpoint module unavailable").Start(self)
end

function mode:Think()
    if not IsValid(PW.Modules.Get("hardpoint")) then
        self:Cleanup()
        assert(PW.Match).Abort("Hardpoint module unavailable")
        return
    end
    if PW.Hardpoint ~= nil then PW.Hardpoint.Think(self) end
end

function mode:Cleanup()
    if PW.Hardpoint ~= nil then PW.Hardpoint.Cleanup(self) end
end

---@param side integer
---@return PW.BotObjective[]
function mode:BotObjectives(side)
    return PW.Hardpoint ~= nil and PW.Hardpoint.Objectives(self, side) or {}
end
