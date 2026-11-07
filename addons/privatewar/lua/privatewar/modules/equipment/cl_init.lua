-- Equipment module, client (T-4.5, T-11.4). Slot keys: the default physical keys are the client ConVars
-- pw_key_lethal (g) and pw_key_tactical (4); the console commands pw_lethal and pw_tactical do the same for players
-- who bind keys themselves (the gamepad d-pad runs them too). A press in LIVE selects the slot's grenade SWEP when
-- it has ammo (input.SelectWeapon); it never throws: the SWEP throws on release of attack. While the player holds
-- an item in a slot during LIVE, the engine bind of that key (slot4 for the 4 key) is swallowed, so the tactical
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

---@type PW.SlotWeapons
local weapons = {}
---@type PW.GrenadeAmmo
local ammo = {}

---The local player when grenades may be selected (alive, LIVE), and the grenade SWEP and ammo per slot filled.
---@return Player?
local function facts()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or PW.Phase.GetPhase() ~= "LIVE" then return nil end
    table.Empty(weapons)
    table.Empty(ammo)
    for _, slot in ipairs(lib.Slots) do
        local class = lib._ItemWeapon(lib.Item(ply, slot))
        if class ~= nil then weapons[slot], ammo[class] = class, lib.Count(ply, slot) end
    end
    return ply
end

---@param ply Player
---@param class string?
local function selectWeapon(ply, class)
    local wep = class ~= nil and ply:GetWeapon(class) or nil
    if wep ~= nil and IsValid(wep) and ply:GetActiveWeapon() ~= wep then input.SelectWeapon(wep) end
end

for _, slot in ipairs(lib.Slots) do
    concommand.Add(lib.Keys[slot].command, function()
        local ply = facts()
        if ply ~= nil then selectWeapon(ply, lib._SlotWeapon(slot, weapons, ammo)) end
    end, nil, "Switch to the " .. slot .. " grenade")
end

PW.HookFor(MODULE, "PlayerButtonDown", function(_, ply, button)
    if not IsFirstTimePredicted() or ply ~= LocalPlayer() then return end
    if lib._KeySlot(button, currentCodes()) == nil or facts() == nil then return end
    selectWeapon(ply, lib._KeyWeapon(button, currentCodes(), weapons, ammo))
end)

PW.HookFor(MODULE, "PlayerBindPress", function(_, ply, _, pressed, code)
    if not pressed or PW.Phase.GetPhase() ~= "LIVE" then return end
    local slot = lib._KeySlot(code, currentCodes())
    if slot ~= nil and lib.Item(ply, slot) ~= nil then return true end
end)
