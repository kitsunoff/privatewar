-- Legal perception data only. Normal navigation, aim and CUserCmd own every engine action.
local lib = (rawget(PW, "InfectionAI") or {}) --[[@as PW.InfectionAILib]]
PW.InfectionAI = lib

function lib.Contact(contacts)
    for _, contact in ipairs(contacts) do
        if contact.visible and IsValid(contact.ent) then return contact end
    end
    return nil
end

function lib.Plan(pos, contact, walkSpeed)
    local dist = pos:Distance(contact.pos)
    if dist > 120 then return { sprint = true, point = contact.pos, forward = 0 } end
    return { sprint = false, forward = dist > 42 and walkSpeed or 0, target = contact.ent }
end
