-- Equipment module, client (T-4.5, T-11.4). Slot keys: the default physical keys are the client ConVars
-- pw_key_lethal (g) and pw_key_tactical (4); the console commands pw_lethal and pw_tactical do the same for players
-- who bind keys themselves (the gamepad d-pad runs them too). A press in LIVE selects the slot's grenade SWEP when
-- it has ammo, or requests use of a weapon-less item. Grenades still only throw on release of attack. A held item
-- in LIVE swallows the engine bind of its key (slot4 for the 4 key), so the tactical
-- key does not also switch to weapon slot 4.

local lib = PW.Equipment --[[@as PW.EquipmentLib]]

---@type table<string, ConVar>
local convars = {}
for _, slot in ipairs(lib.Slots) do
    local key = lib.Keys[slot]
    convars[slot] = CreateClientConVar(key.convar, key.default, true, false,
        "Key that uses the " .. slot .. " equipment slot (a key name such as g or 4)")
end

---@type table<string, integer>
local codes = {}
---@type table<string, string>
local codeNames = {}

---The key code per slot, refreshed when a ConVar changed (no allocation otherwise).
---@return table<string, integer>
local function currentCodes()
    for slot, convar in pairs(convars) do
        local name = convar:GetString()
        if codeNames[slot] ~= name then
            codeNames[slot] = name
            codes[slot] = input.GetKeyCode(name)
        end
    end
    return codes
end

---@param ply Player
---@param class string?
local function selectWeapon(ply, class)
    local wep = class ~= nil and ply:GetWeapon(class) or nil
    if wep ~= nil and IsValid(wep) and ply:GetActiveWeapon() ~= wep then input.SelectWeapon(wep) end
end

---@param ply Player
---@param slot string
---@param index integer
local function keyAction(ply, slot, index)
    if not IsValid(ply) or not ply:Alive() or PW.Phase.GetPhase() ~= "LIVE" then return end
    local id = lib.Item(ply, slot)
    local class = lib._ItemWeapon(id)
    local action = lib._KeyAction(id, class, lib.Count(ply, slot))
    if action == "select" then
        selectWeapon(ply, class)
    elseif action == "use" then
        net.Start("pw_equipment_use")
        net.WriteUInt(index, 2)
        net.SendToServer()
    end
end

---@type table<string, integer>
local slotIndices = {}
for index, slot in ipairs(lib.Slots) do
    slotIndices[slot] = index
    concommand.Add(lib.Keys[slot].command, function()
        keyAction(LocalPlayer(), slot, index)
    end, nil, "Select or use the " .. slot .. " equipment")
end

PW.HookFor(MODULE, "PlayerButtonDown", function(_, ply, button)
    if not IsFirstTimePredicted() or ply ~= LocalPlayer() then return end
    local slot = lib._KeySlot(button, currentCodes())
    if slot ~= nil then keyAction(ply, slot, slotIndices[slot]) end
end)

PW.HookFor(MODULE, "PlayerBindPress", function(_, ply, _, pressed, code)
    if not pressed or PW.Phase.GetPhase() ~= "LIVE" then return end
    local slot = lib._KeySlot(code, currentCodes())
    if slot ~= nil and lib.Item(ply, slot) ~= nil then return true end
end)
