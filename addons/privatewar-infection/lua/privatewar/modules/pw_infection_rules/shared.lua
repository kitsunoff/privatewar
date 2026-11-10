-- Optional addon-owned rules and presentation; no framework or asset dependency.
MODULE.Name = "Infection rules"
PW.Infection = (rawget(PW, "Infection") or { Revision = 0 }) --[[@as PW.InfectionLib]]
if SERVER then
    AddCSLuaFile("privatewar/modules/pw_infection_rules/sh_rules.lua")
    AddCSLuaFile("privatewar/modules/pw_infection_rules/sh_presentation.lua")
    AddCSLuaFile("privatewar/modules/pw_infection_rules/sh_pursuit.lua")
    AddCSLuaFile("privatewar/modules/pw_infection_rules/sh_results.lua")
end
include("privatewar/modules/pw_infection_rules/sh_rules.lua")
include("privatewar/modules/pw_infection_rules/sh_presentation.lua")
include("privatewar/modules/pw_infection_rules/sh_pursuit.lua")
include("privatewar/modules/pw_infection_rules/sh_results.lua")

---@param data PW.UIPostmatchData
---@param ownId integer
function MODULE:PW_PostmatchGathered(data, ownId)
    local terminal = assert(PW.Infection).Terminal
    if terminal == nil or not terminal.active or PW.Phase.GetPhase() ~= "POSTMATCH" then return end
    assert(PW.InfectionPresentation).ApplyPostmatch(data, terminal, ownId)
end

---@param data PW.UIScoreboardData
---@param _ integer
function MODULE:PW_ScoreboardGathered(data, _)
    local view = assert(PW.Infection).View
    if view == nil or view.active == false or PW.Phase.GetPhase() ~= "LIVE" then return end
    data.note = "ROUND " .. view.round .. "  |  YOUR ROUND WINS " .. view.personalWins
        .. "  |  Full standings at match end"
    for _, section in ipairs(data.sections) do
        if section.id == 1 or section.id == 2 then
            section.title = section.id == 1 and "SURVIVORS" or "INFECTED"
            section.score = nil -- changing roles are not the personal match standings
        end
    end
end
