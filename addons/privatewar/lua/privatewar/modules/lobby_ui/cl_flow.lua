-- Map change popup, client (Phase 11 match flow fixes; 00-core.md d.9 delayed change). While the server announces a
-- map change (PW.Phase.GetMapChange: map, mode, end time), a centred card over every screen (the lobby, the vote
-- overlay) shows MAP CHANGE, the map's display name, the mode name and the seconds left. The model is pure
-- (PW.Lobby._MapChangePopup, sh_flow.lua); this file reads the engine and paints after the VGUI (PostRenderVGUI), so
-- the card is above the PWRoot popups. Included by cl_init.lua.

---@class PW.LobbyFlowModuleClient : PW.Module
local module = MODULE --[[@as PW.LobbyFlowModuleClient]]

local lib = PW.Lobby --[[@as PW.LobbyLib]]

local fallback = Color(255, 255, 255)
local shade = Color(0, 0, 0, 160)

---@return PW.UILib?
local function kit()
    return rawget(PW, "UI") --[[@as PW.UILib?]]
end

---@param token string
---@return Color
local function colour(token)
    local ui = kit()
    if ui == nil then return fallback end
    return (ui.Style --[[@as table<string, Color>]])[token] or fallback
end

---@param id string
---@return string?
local function modeName(id)
    local modes = (rawget(PW, "Registries") or {}).modes --[[@as PW.Registry?]]
    local mode = modes ~= nil and modes.Get(id) or nil
    local name = mode ~= nil and mode.Name or nil
    return isstring(name) and name --[[@as string]] or id
end

---@param map string
---@return string?
local function mapName(map)
    local maps = rawget(PW, "Map") --[[@as PW.MapLib?]]
    local entry = maps ~= nil and maps.Get ~= nil and maps.Get(map) or nil
    local name = entry ~= nil and entry.Name or nil
    return isstring(name) and name --[[@as string]] or nil
end

---@param popup PW.LobbyPopup
local function paint(popup)
    local ui = kit()
    if ui == nil then return end
    local px = ui.Draw.Px
    local w, h = px(720), px(260)
    local x, y = math.floor((ScrW() - w) / 2), math.floor((ScrH() - h) / 2)
    surface.SetDrawColor(shade)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    ui.Draw.Rect(x, y, w, h, colour("bg_raised"))
    ui.Draw.Rect(x, y, w, px(6), colour("accent"))
    ui.Draw.Outline(x, y, w, h, colour("border"))
    local cx = x + w / 2
    draw.SimpleText(popup.title, ui.Font("h2"), cx, y + px(52), colour("accent"), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(popup.map, ui.Font("title"), cx, y + px(120), colour("text"), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(popup.mode, ui.Font("h2"), cx, y + px(178), colour("text_muted"), TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
    draw.SimpleText(popup.line, ui.Font("body"), cx, y + px(226), colour("text"), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

---@type PW.LobbyPopupFacts
local facts = { changeAt = -1, now = 0, map = "" }

PW.HookFor(module, "PostRenderVGUI", function()
    local map, mode, at = PW.Phase.GetMapChange()
    if at < 0 then return end
    facts.changeAt, facts.now, facts.map = at, CurTime(), map
    facts.mapName, facts.modeName = mapName(map), modeName(mode)
    local popup = lib._MapChangePopup(facts)
    if popup ~= nil then paint(popup) end
end)
