-- Cleanup observers stay active only to revoke effects; they never grant gameplay.
local lib = PW.Perks --[[@as PW.PerksLib]]

function lib._PublishEffects(ply, entry)
    local s = PW._Perks --[[@as PW.PerksStore]]
    s.silent = s.silent or setmetatable({}, { __mode = "k" })
    local silent = false
    if entry ~= nil then
        for _, instance in ipairs(entry.instances) do
            if instance:IsValid() and instance.SilentFootsteps then silent = true break end
        end
    end
    s.silent[ply] = silent or nil
    if IsValid(ply) and isfunction(ply.SetNW2Bool) then ply:SetNW2Bool("pw_silent_steps", silent) end
    PW.Notify("PW_PlayerStatsChanged", ply)
end

---@param entry PW.PerksEntry
---@param definition table
---@return boolean
local function removeDefinition(entry, definition)
    local changed = false
    for i = #entry.instances, 1, -1 do
        if entry.instances[i]._Definition == definition then
            table.remove(entry.instances, i)
            table.remove(entry.ids, i)
            changed = true
        end
    end
    return changed
end

hook.Add("PW_EntityDisabled", "PW.Perks.Cleanup", function(kind, id, definition)
    local s = PW._Perks
    if s == nil then return end
    if kind == "modules" and id == "perks" then
        for ply in pairs(s.players) do lib._Clear(ply) end
    elseif kind == "perks" then
        for ply, entry in pairs(s.players) do
            if removeDefinition(entry, definition) then lib._Recompute(ply) end
        end
    end
end)
