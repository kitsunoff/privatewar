-- Operators, client glue (06-progression.md d.7; docs/api/operators.md). The choice lives in the client setting
-- operators.model (ConVar pw_operators_model): it is sent to the server once the client is in the game
-- (InitPostEntity) and again on every change of the ConVar, whoever changed it (the picker, the Personal settings
-- form or the console). LocalModel is what the lobby operator panel shows: the choice resolved for the local
-- player (a locked or unknown choice falls back the same way as on the server).

---A file-local class: methods of the global MODULE defined in two files are reported as duplicates.
---@class PW.OperatorsModuleClient : PW.Module
local module = MODULE --[[@as PW.OperatorsModuleClient]]

local lib = PW.Operators --[[@as PW.OperatorsLib]]

---@param id string
---@return boolean
local function localUnlocked(id)
    local progression = rawget(PW, "Progression") --[[@as PW.ProgressionLib?]]
    local me = LocalPlayer()
    if progression == nil or progression.IsUnlocked == nil or not IsValid(me) then return true end
    return progression.IsUnlocked(me, "models", id)
end

---@return string
local function ownModel()
    local convar = GetConVar("cl_playermodel")
    return convar ~= nil and convar:GetString() or ""
end

function lib.LocalList()
    return lib.List(lib.LiveInput(localUnlocked))
end

function lib.LocalChoice()
    local value = PW.Setting(lib.Setting)
    return isstring(value) and value --[[@as string]] or lib.Auto
end

function lib.LocalModel()
    local entry = lib.Resolve(lib.LocalList(), lib.LocalChoice(), ownModel())
    return entry ~= nil and entry.path or lib.FallbackPath
end

function lib.Send()
    if not IsValid(module) then return end
    net.Start(lib.NetName)
    net.WriteString(lib.LocalChoice())
    net.SendToServer()
end

function lib.Choose(choice)
    if choice ~= lib.Auto then
        local entry = nil
        for _, item in ipairs(lib.LocalList()) do
            if item.id == choice then entry = item end
        end
        if entry == nil or entry.locked then return false end
    end
    local ok = PW.Settings.Set(lib.Setting, choice)
    return ok == true
end

function lib.OpenPicker()
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    local root = ui ~= nil and ui.CurrentRoot() --[[@as PWRoot?]] or nil
    if root == nil or ui == nil then return end
    local model = root.model
    if model.active ~= "loadout" and not ui.Router.SwitchTab(model, "loadout") then return end
    ui.Router.Push(model, "loadout_operator")
    root:Rebuild()
end

concommand.Add("pw_operator", function() lib.OpenPicker() end, nil,
    "Private War: open the operator picker (LOADOUT > OPERATOR) in the open menu")

local convarName = "pw_operators_model"

---The setting's ConVar exists from Boot on (created before PW_RegistriesLoaded); a change sends the new choice.
function module:PW_RegistriesLoaded()
    cvars.AddChangeCallback(convarName, function() lib.Send() end, "PW.Operators")
end

PW.HookFor(module, "InitPostEntity", function()
    lib.Send()
end)
