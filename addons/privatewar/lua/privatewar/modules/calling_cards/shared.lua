-- Calling cards, selection rules and bounded wire (06-progression.md d.6).
local module = MODULE
module.Name = "Calling Cards"

local lib = (rawget(PW, "CallingCards") or {}) --[[@as PW.CallingCardsLib]]
PW.CallingCards = lib

lib.Default = "default"
lib.ChoiceNet = "pw_card_choice"
lib.KillNet = "pw_kill_card"
lib.ChoiceMaxLen = 34
local fieldMax = 32
local stringMaxBits = (fieldMax + 1) * 8

function lib._Active()
    return IsValid(module)
end

function lib._ValidChoice(id)
    return isstring(id) and #id <= fieldMax and (id == "" or id:match("^[a-z0-9_]+$") ~= nil)
end

function lib._CardDefinition(id)
    local registry = PW.Registries.cards
    if registry == nil then return nil end
    return registry.Get(id) --[[@as PW.CallingCard?]]
end

---Include disabled cards so host enable settings do not silently overwrite a saved preference.
---@return string[]
local function settingOptions()
    local registry = PW.Registries.cards
    local ids = { lib.Default }
    if registry == nil then return ids end
    for _, card in ipairs(registry.GetList()) do
        local id = card.ClassName
        if id ~= lib.Default and id ~= "" and lib._ValidChoice(id) then ids[#ids + 1] = id end
    end
    return ids
end

module.Settings = {
    selected = {
        scope = "client", type = "enum", default = lib.Default, options = settingOptions,
        label = "Calling card (pick it in LOADOUT > CALLING CARD)"
    },
    banner = { scope = "client", type = "bool", default = true, label = "Show kill card banner" }
}

function lib._Resolve(id, facts)
    if not lib._ValidChoice(id) then return facts.previous or lib.Default end
    ---@cast id string
    if id ~= "" and facts.registered(id) and facts.enabled(id) and facts.unlocked(id) then return id end
    return lib.Default
end

function lib._BotCard(ids, rng)
    if #ids == 0 then return nil end
    return ids[math.Clamp(math.floor(rng() * #ids) + 1, 1, #ids)]
end

function lib._VictimName(name)
    local clean = string.gsub(name, "%c", " ")
    local text = string.sub(utf8.force(clean), 1, fieldMax)
    while not utf8.len(text) do text = string.sub(text, 1, -2) end
    return text
end

-- WriteString is a NUL-terminated byte string. Read no more bytes than the declared
-- length, never through the bool or beyond a missing terminator.
---@param reader PW.CardReader
---@param bits integer
---@return string?, integer unused bits
local function readString(reader, bits)
    local text = ""
    for _ = 1, fieldMax + 1 do
        if bits < 8 then break end
        local value = reader.ReadUInt(8)
        bits = bits - 8
        if value == 0 then return text, bits end
        text = text .. string.char(value)
    end
    return nil, bits
end

function lib._ReadChoice(reader, bits)
    if bits < 8 or bits > stringMaxBits or bits % 8 ~= 0 then return nil end
    local value, remaining = readString(reader, bits)
    if remaining == 0 and lib._ValidChoice(value) then return value end
    return nil
end

function lib._Encode(state, writer)
    writer.WriteString(lib._VictimName(state.name))
    writer.WriteString(lib._ValidChoice(state.card) and state.card or "")
    writer.WriteBool(state.bot)
end

function lib._Decode(reader, bits)
    if bits < 17 or bits > 2 * stringMaxBits + 1 or bits % 8 ~= 1 then return nil end
    local name, remaining = readString(reader, bits)
    if name == nil or not utf8.len(name) or name:find("%c") ~= nil then return nil end
    local id, tail = readString(reader, remaining - 1)
    if tail ~= 0 or id == nil or not lib._ValidChoice(id) then return nil end
    return { name = name, card = id, bot = reader.ReadBool() }
end

function lib._BannerAlpha(startedAt, now, fadeIn, hold, fadeOut)
    local elapsed = now - startedAt
    if elapsed < 0 then return 0 end
    if elapsed < fadeIn then return elapsed / fadeIn end
    elapsed = elapsed - fadeIn
    if elapsed <= hold then return 1 end
    if fadeOut <= 0 then return 0 end
    return math.Clamp(1 - (elapsed - hold) / fadeOut, 0, 1)
end

function lib._BannerRect(scrW, scrH, scale)
    local w, h = 400 * scale, 100 * scale
    -- Match the XP strip's vertical scaling and minimum thickness (hud/progression.lua).
    local sy = scrH / 1080
    local xpTop = scrH - math.floor(10 * sy) - math.max(2, math.floor(6 * sy))
    return (scrW - w) / 2, xpTop - 24 * scale - h, w, h
end

function lib._PushBanner(banner, packet, now)
    banner.packet, banner.startedAt = packet, now
end

function lib._VisibleAlpha(banner, enabled, now)
    if not enabled or banner.packet == nil or banner.startedAt == nil then return 0 end
    return assert(lib._BannerAlpha)(banner.startedAt, now, 0.15, 2.5, 0.3)
end

function lib._PlateStyle(hasMaterial, width, height)
    if not hasMaterial or width <= 0 or height <= 0 then return "missing" end
    return width <= 32 and height <= 32 and "icon" or "art"
end

function lib._PaintPlate(card, draw, name, label, rect)
    local x, y, w, h = rect.x, rect.y, rect.w, rect.h
    if card.style ~= "art" then draw.plate(card.rarity, x, y, w, h) end
    if card.style == "art" then
        draw.art(card, x, y, w, h)
    elseif card.style == "icon" then
        local sourceW, sourceH = card.width or 16, card.height or 16
        local fit = math.min(1, w / sourceW, h / sourceH)
        local iconW, iconH = sourceW * fit, sourceH * fit
        draw.art(card, x + (w - iconW) / 2, y + (h - iconH) / 2, iconW, iconH)
    end
    draw.gradient(x, y, w * 0.55, h, 0.85)
    draw.text(name, label, card.style == "missing" and card.title or "", x, y, w, h)
end
