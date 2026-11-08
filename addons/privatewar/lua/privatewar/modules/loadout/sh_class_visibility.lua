-- T-11.15 (05-loadout.md d.13-d.14): human picker/id policy, never registry or bot-pool eligibility.
-- The pure helper partitions existing entries without changing their order, contents or identity.

local lib = PW.Loadout --[[@as PW.LoadoutLib]]

function lib._HumanClassEntries(entries, customOnly, lookup)
    ---@type PW.LoadoutClassEntry[]
    local customs = {}
    ---@type PW.LoadoutClassEntry[]
    local presets = {}
    for _, entry in ipairs(entries) do
        local source, key = lib._ParseRef(entry.ref)
        if source == "custom" then
            customs[#customs + 1] = entry
        elseif source == "preset" and not customOnly then
            local preset = lookup(key --[[@as string]])
            if preset == nil or preset.Hidden ~= true then presets[#presets + 1] = entry end
        end
    end
    for _, entry in ipairs(presets) do customs[#customs + 1] = entry end
    return customs
end

function lib.HumanClassState(state, customOnly)
    local registry = rawget(PW, "Classes") --[[@as PW.Registry?]]
    local entries = lib._HumanClassEntries(state.entries, customOnly == true, function(id)
        return (registry ~= nil and registry.Get(id) or nil) --[[@as PW.ClassPreset?]]
    end)
    local selected = ""
    for _, entry in ipairs(entries) do
        if entry.ref == state.selected then selected = entry.ref end
    end
    return { selected = selected, entries = entries }
end
