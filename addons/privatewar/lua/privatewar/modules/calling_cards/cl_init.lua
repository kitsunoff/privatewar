-- Client choice upload and material-backed presentation shared by the HUD and its picker preview.
---@class PW.CallingCardsModuleClient : PW.Module
local module = MODULE --[[@as PW.CallingCardsModuleClient]]
local lib = assert(PW.CallingCards)
local pushBanner, visibleAlpha, bannerRect = assert(lib._PushBanner), assert(lib._VisibleAlpha), assert(lib._BannerRect)
local plateStyle, paintPlate = assert(lib._PlateStyle), assert(lib._PaintPlate)

---@type PW.CardBanner
local banner = {}
---@type PW.CardPlate
local plain = { style = "missing", title = "", rarity = "neutral" }
---@type PW.UIRect
local rect = { x = 0, y = 0, w = 0, h = 0 }
local currentPlate, currentName = plain, ""
local bannerVar = nil --[[@as ConVar?]]
---@type table<string, { definition: PW.CallingCard, plate: PW.CardPlate }>
local materials = {}

local gradient = Material("vgui/gradient-l") -- opaque on the left, transparent on the right
local text, muted, shade, shadow = Color(232, 237, 233), Color(138, 149, 141), Color(11, 15, 12), Color(0, 0, 0)
---@type table<string, Color>
local rarities = {
    common = Color(138, 149, 141), rare = Color(79, 195, 247),
    epic = Color(180, 124, 255), legendary = Color(255, 181, 71)
}
local neutral = Color(31, 42, 34)
local nameFont, labelFont = "DermaDefaultBold", "DermaDefault"

---@return PW.UIStyle?
local function uiStyle()
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    return ui ~= nil and ui.Style or nil
end

---@type PW.CardPainter
local painter = {
    plate = function(rarity, x, y, w, h)
        surface.SetDrawColor(rarities[rarity] or neutral)
        surface.DrawRect(x, y, w, h)
    end,
    art = function(card, x, y, w, h)
        if card.material == nil then return end
        surface.SetMaterial(card.material)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(x, y, w, h)
    end,
    gradient = function(x, y, w, h, alpha)
        local style = uiStyle()
        local colour = style ~= nil and style.bg or shade
        surface.SetMaterial(gradient)
        surface.SetDrawColor(colour.r, colour.g, colour.b, math.floor(alpha * 255 + 0.5))
        surface.DrawTexturedRect(x, y, w, h)
    end,
    text = function(name, label, fallback, x, y, w, h)
        local style = uiStyle()
        local foreground = style ~= nil and style.text or text
        local caption = style ~= nil and style.text_muted or muted
        local left, right = x + h * 0.14, x + w - h * 0.14
        local nameY, labelY = y + h * 0.61, y + h * 0.34
        draw.SimpleText(label, labelFont, left + 1, labelY + 1, shadow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(label, labelFont, left, labelY, caption, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(name, nameFont, left + 1, nameY + 1, shadow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(name, nameFont, left, nameY, foreground, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if fallback == "" then return end
        draw.SimpleText(fallback, labelFont, right + 1, y + h / 2 + 1, shadow, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        draw.SimpleText(fallback, labelFont, right, y + h / 2, foreground, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
}

---@param id string
---@return PW.CardPlate
local function plateFor(id)
    if id == "" then return plain end
    local definition = lib._CardDefinition(id)
    if definition == nil or not definition:IsValid() then return plain end
    local existing = materials[id]
    if existing ~= nil and existing.definition == definition then return existing.plate end
    local material = Material(definition.Material)
    local loaded = not material:IsError()
    local w, h = loaded and material:Width() or 0, loaded and material:Height() or 0
    ---@type PW.CardPlate
    local result = {
        style = plateStyle(loaded, w, h), rarity = definition.Rarity or "neutral",
        title = language.GetPhrase(definition.Name), width = w, height = h, material = loaded and material or nil
    }
    materials[id] = { definition = definition, plate = result }
    return result
end

---@param value string
---@return number
local function measure(value)
    local w = surface.GetTextSize(value)
    return w
end

---@param name string
---@param width number
---@return string
local function fitName(name, width)
    local hud = rawget(PW, "HUD") --[[@as PW.HudLib?]]
    if hud == nil then return name end
    surface.SetFont(nameFont)
    return hud._FitText(name, width * 0.40, measure)
end

---@param card PW.CardPlate
---@param name string
---@param label string
---@param bounds PW.UIRect
---@param alpha number
local function drawPlate(card, name, label, bounds, alpha)
    local previous = surface.GetAlphaMultiplier()
    surface.SetAlphaMultiplier(previous * alpha)
    paintPlate(card, painter, name, label, bounds)
    surface.SetAlphaMultiplier(previous)
end

lib._PlateFor, lib._FitName, lib._DrawPlate = plateFor, fitName, drawPlate

local function refreshView()
    local packet = banner.packet
    if packet == nil then return end
    currentPlate = plateFor(packet.card)
    currentName = fitName(packet.name, rect.w)
end

local function refreshLayout()
    local w, h = ScrW(), ScrH()
    local scale = math.min(w / 1920, h / 1080)
    rect.x, rect.y, rect.w, rect.h = bannerRect(w, h, scale)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui ~= nil then
        if ui.RefreshFonts ~= nil then ui.RefreshFonts() end
        local font = ui.FontData({ id = "medium", family = "body", size = 28, weight = 700 }, scale)
        surface.CreateFont(font.name, font)
        nameFont, labelFont = ui.FontName("medium"), ui.FontName("small")
    end
    refreshView()
end

function lib._DrawBanner()
    if not lib._Active() then return end
    local alpha = visibleAlpha(banner, bannerVar == nil or bannerVar:GetBool(), RealTime())
    if alpha > 0 then drawPlate(currentPlate, currentName, "ELIMINATED", rect, alpha) end
end

---@return string
local function localChoice()
    local id = PW.Setting("calling_cards.selected")
    return isstring(id) and id --[[@as string]] or lib.Default
end

lib.LocalChoice = localChoice

---@param value? string
---@return string?
local function phrase(value)
    if value ~= nil and value:sub(1, 1) == "#" then return language.GetPhrase(value:sub(2)) end
    return value
end

---@param ply Player
---@param id string
---@return PW.UnlockRequirement
local function requirement(ply, id)
    local unlocks = PW.Unlocks
    if unlocks ~= nil and IsValid(ply) then return unlocks.Requirement(ply, "cards", id) end
    if id == lib.Default then return { unlocked = true, reason = "default" } end
    return { unlocked = false, reason = "unknown", lockText = "LOCKED", text = "Not available" }
end

---@return PW.UICard[]
local function pickerCards()
    local registry = PW.Registries.cards
    ---@type PW.UICard[]
    local rows = {}
    if registry == nil then return rows end
    local ply, rowOf = LocalPlayer(), assert(lib._PickerCard)
    for _, entity in ipairs(registry.GetEnabledList()) do
        local definition = entity --[[@as PW.CallingCard]]
        local id = definition.ClassName
        if id ~= "" and lib._ValidChoice(id) then
            local row = rowOf(id, language.GetPhrase(definition.Name), requirement(ply, id))
            row.reason, row.lockText = phrase(row.reason), phrase(row.lockText)
            if id == lib.Default then table.insert(rows, 1, row) else rows[#rows + 1] = row end
        end
    end
    return rows
end

lib._PickerCards = pickerCards

function lib.Choose(id)
    if not lib._Active() then return false end
    return assert(lib._SelectPickerCard)(pickerCards(), id, function(key, value)
        local ok = PW.Settings.Set(key, value)
        return ok
    end)
end

function lib.OpenPicker()
    if not lib._Active() then return end
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    local root = ui ~= nil and ui.CurrentRoot() --[[@as PWRoot?]] or nil
    if root ~= nil and assert(lib._PushPicker)(root.model) then root:Rebuild() end
end

local function sendChoice()
    if not lib._Active() then return end
    local id = localChoice()
    if not lib._ValidChoice(id) then return end
    net.Start(lib.ChoiceNet)
    net.WriteString(id)
    net.SendToServer()
end

net.Receive(lib.KillNet, function(bits)
    if not lib._Active() then return end
    local packet = lib._Decode(net --[[@as PW.CardReader]], bits)
    if packet ~= nil then
        pushBanner(banner, packet, RealTime())
        refreshView()
    end
end)

function module:PW_RegistriesLoaded()
    materials = {}
    bannerVar = GetConVar("pw_calling_cards_banner")
    cvars.AddChangeCallback("pw_calling_cards_selected", sendChoice, "PW.CallingCards")
    refreshLayout()
end

---@param phase PW.PhaseName
function module:PW_PhaseChanged(phase)
    if phase ~= "LIVE" then banner.packet, banner.startedAt = nil, nil end
end

PW.HookFor(module, "OnScreenSizeChanged", refreshLayout)
PW.HookFor(module, "InitPostEntity", function()
    -- Defer until the join uploads from progression have been sent.
    timer.Simple(0, sendChoice)
end)
