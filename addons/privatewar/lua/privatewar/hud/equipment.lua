-- Equipment (T-4.5; 05-loadout.md d.11): one small line per equipment slot at the bottom right, above the HL2 ammo
-- panel: the key hint in brackets, the item name and the uses left ("[G] FRAG x1"; "[D-DOWN] FRAG x1" when Button
-- hints is gamepad). An empty slot is not drawn; a spent one is dimmed. Item ids are the player's NW2 values; the
-- count is the ammo of the slot's grenade SWEP (T-11.4; PW.Equipment.Count on the client), the NW2 count for an
-- item without one. No traffic of its own. The key selects the grenade, it does not throw. A frame allocates
-- nothing: the text of a slot is rebuilt only when its item, count or key changes.
HUDELEMENT.Order = 30
HUDELEMENT.Phases = { "LIVE" }

local hud = PW.HUD --[[@as PW.HudLib]]

-- Design units (1920x1080): right edge, baseline of the lowest line, line height.
local right, bottom, lineHeight = 1880, 900, 30

local fallback = Color(255, 255, 255)
local fallbackMuted = Color(150, 150, 150)

---@class PW.HudEquipmentLine
---@field id string
---@field count integer
---@field key string
---@field text string

---@type table<string, PW.HudEquipmentLine>
local lines = {}

---@type table<string, ConVar>
local keyVars = {}

---The key name a slot's ConVar holds ("" when the ConVar does not exist yet).
---@param name string
---@return string
local function keyOf(name)
    local var = keyVars[name]
    if var == nil then
        var = GetConVar(name)
        if var == nil then return "" end
        keyVars[name] = var
    end
    return var:GetString()
end

---@param token string
---@param default Color
---@return Color
local function colour(token, default)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui == nil then return default end
    return (ui.Style --[[@as table<string, Color>]])[token] or default
end

---@return string
local function font()
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui ~= nil then return ui.FontName("small") end
    return (hud.Font --[[@as fun(id: string, size: number, weight?: number): string]])("equipment", 22, 700)
end

---The d-pad glyph of a slot (ui_kit sh_gamepad.lua: the actions are named after the slots) when Button hints is
---gamepad, else nil.
---@param slot string
---@return string?
local function glyphOf(slot)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    local pad = ui ~= nil and ui.Gamepad or nil
    if pad == nil or pad.HudGlyph == nil then return nil end
    return pad.HudGlyph(slot)
end

---The display name of an item id (its Name, else the id).
---@param id string
---@return string
local function nameOf(id)
    local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
    local registry = registries ~= nil and registries.equipment or nil
    local def = registry ~= nil and registry.Get(id) or nil
    if def == nil then return id end
    return tostring((def --[[@as PW.EquipmentItem]]).Name)
end

---The cached line of a slot, rebuilt when the item, the count or the key changed.
---@param slot string
---@param id string
---@param count integer
---@param key string
---@return string
local function textOf(slot, id, count, key)
    local line = lines[slot]
    if line ~= nil and line.id == id and line.count == count and line.key == key then return line.text end
    local text = "[" .. string.upper(key) .. "] " .. string.upper(nameOf(id)) .. " x" .. count
    lines[slot] = { id = id, count = count, key = key, text = text }
    return text
end

function HUDELEMENT:Draw()
    local ply = LocalPlayer()
    local lib = rawget(PW, "Equipment") --[[@as PW.EquipmentLib?]]
    if lib == nil or not IsValid(ply) or not ply:Alive() then return end
    local slots = lib.Slots
    local y = bottom
    for i = #slots, 1, -1 do
        local slot = slots[i] --[[@as string]]
        local id = lib.Item(ply, slot)
        if id ~= nil then
            local count = lib.Count(ply, slot)
            local key = glyphOf(slot) or keyOf(lib.Keys[slot].convar)
            local tint = count > 0 and colour("text", fallback) or colour("text_muted", fallbackMuted)
            draw.SimpleText(textOf(slot, id, count, key), font(), hud.X(right), hud.Y(y), tint, TEXT_ALIGN_RIGHT,
                TEXT_ALIGN_BOTTOM)
            y = y - lineHeight
        end
    end
end
