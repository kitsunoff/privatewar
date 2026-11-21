-- Rules shared by item-owned stim instances and their presentation.
MODULE.Name = "Stims"
MODULE.Settings = {
    use_time = { type = "float", scope = "match", default = 0.4, min = 0, max = 2, label = "Stim injection time (s)" },
    heal_amount = { type = "int", scope = "match", default = 60, min = 10, max = 200, label = "Heal stim health" },
    heal_time = { type = "float", scope = "match", default = 1.5, min = 0, max = 5, label = "Heal stim duration (s)" },
    speed_mult = { type = "float", scope = "match", default = 1.2, min = 1, max = 2, label = "Speed stim multiplier" },
    speed_time = { type = "float", scope = "match", default = 6, min = 1, max = 30, label = "Speed stim duration (s)" },
    armor_amount = { type = "int", scope = "match", default = 50, min = 10, max = 150, label = "Armor stim armor" },
    armor_time = { type = "float", scope = "match", default = 1, min = 0, max = 5, label = "Armor stim duration (s)" },
    armor_max = { type = "int", scope = "match", default = 150, min = 50, max = 255, label = "Armor stim cap" }
}

local lib = (rawget(PW, "Stims") or {}) --[[@as PW.StimsLib]]
PW.Stims = lib

function lib.Param(item, field, settingId)
    local value = item[field]
    if value ~= nil then return value end
    return PW.Setting(settingId)
end

function lib._Ticks(amount, duration, step)
    if duration <= 0 then return { amount } end
    local count = math.ceil(duration / step)
    ---@type number[]
    local ticks = {}
    local allocated = 0
    for i = 1, count - 1 do
        local nextTotal = math.floor(amount * i / count)
        ticks[i] = nextTotal - allocated
        allocated = nextTotal
    end
    ticks[count] = amount - allocated
    return ticks
end

function lib._Step(current, add, cap)
    if current >= cap then return current end
    return math.min(current + add, cap)
end

function lib._EffectLines(now, marks)
    ---@type string[]
    local lines = {}
    if marks.speed > now then lines[1] = string.format("SPEED %.1f", math.ceil((marks.speed - now) * 10) / 10) end
    if marks.heal > now then lines[#lines + 1] = "HEALING" end
    if marks.armor > now then lines[#lines + 1] = "ARMOR" end
    return lines
end
