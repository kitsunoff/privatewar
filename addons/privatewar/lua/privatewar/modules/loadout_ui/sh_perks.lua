-- Warnings follow selected class weapons, not unsupported claims about absent integrations.
local lib = PW.LoadoutUI --[[@as PW.LoadoutUILib]]
local keys = { "reload_time", "draw_time", "ads_time", "sprint_to_fire", "recoil", "spread" }

function lib.PerkDescription(definition, classes)
    local text = (definition.Description or "") --[[@as string]]
    if definition.Stats == nil then return text end
    for _, class in ipairs(classes) do
        local supported = (PW.Adapters.CallFor(class, "SupportedStatMods") or {}) --[[@as table<string, boolean>]]
        ---@type string[]
        local missing = {}
        for _, key in ipairs(keys) do
            if definition.Stats[key] ~= nil and not supported[key] then missing[#missing + 1] = key end
        end
        if #missing > 0 then
            text = text .. " Unsupported on " .. class .. ": " .. table.concat(missing, ", ") .. "."
        end
    end
    return text
end
