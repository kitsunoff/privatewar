-- Operators module (06-progression.md d.7; 10-frontend.md d.6; docs/api/operators.md). One global operator (player
-- model) per player, used in every match and in the lobby operator panel:
--   The choice is the client setting operators.model (ConVar pw_operators_model, Personal settings): "auto" (the
--     player's own GMod cl_playermodel), a stock player model by its player_manager name (Workshop playermodels
--     included) or an economy `models` entry as "models:<id>" (owned or free ones only).
--   The client sends the choice on join and on every change (pw_operator_model, PW.Net.Receive). The server checks
--     it again (a valid model; an economy model must be unlocked or bought) and applies it in PlayerSetModel, with
--     the player colour set to the team colour in team modes.
--   Bots get a random operator (economy models too, ownership ignored) when they first spawn and keep it.
-- Pure rules: sh_rules.lua. Server glue: init.lua. Client glue and the picker: cl_init.lua,
-- screens/loadout_operator.lua.

MODULE.Name = "Operators"

local lib = (rawget(PW, "Operators") or {}) --[[@as PW.OperatorsLib]]
PW.Operators = lib
lib.Setting = "operators.model"
lib.NetName = "pw_operator_model"

if SERVER then AddCSLuaFile("privatewar/modules/operators/sh_rules.lua") end
include("privatewar/modules/operators/sh_rules.lua")

---@param entity table<string, any>
---@return PW.OperatorEconomyInput?
local function economyInput(entity)
    local path = entity.Model
    if not isstring(path) or path == "" then return nil end
    return {
        id = tostring(entity.ClassName), name = isstring(entity.Name) and entity.Name or tostring(entity.ClassName),
        path = path, price = tonumber(entity.Price), unlock = tonumber(entity.Unlock)
    }
end

---@param all boolean every entry (the setting's options) instead of the enabled ones
---@return PW.OperatorEconomyInput[]
local function economyEntries(all)
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    local registry = registries ~= nil and registries.models or nil
    ---@type PW.OperatorEconomyInput[]
    local list = {}
    if registry == nil then return list end
    for _, entity in ipairs(all and registry.GetList() or registry.GetEnabledList()) do
        local input = economyInput(entity --[[@as table<string, any>]])
        if input ~= nil then list[#list + 1] = input end
    end
    return list
end

---@return table<string, string>
local function stockModels()
    local all = player_manager.AllValidModels()
    return istable(all) and all or {}
end

function lib.LiveInput(unlocked)
    return { stock = stockModels(), economy = economyEntries(false), unlocked = unlocked }
end

MODULE.Settings = {
    model = {
        scope = "client", type = "enum", default = "auto", label = "Operator (pick it in LOADOUT > OPERATOR)",
        options = function()
            return lib.OptionIds(lib.List({ stock = stockModels(), economy = economyEntries(true) }))
        end
    }
}
