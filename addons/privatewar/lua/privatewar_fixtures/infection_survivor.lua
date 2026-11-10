-- Test-only setup: keep the authored sight lane until native perception and the ordinary brain admit escape.
---@class PW.TestInfectionSurvivor
local fixture = {}

---@param board PW.BotBoard?
---@param threat Player
---@return boolean
local function acquired(board, threat)
    if board == nil or board.behavior == nil or board.behavior.id ~= "pw_infection_escape" then return false end
    for _, contact in ipairs(board.contacts or {}) do
        if contact.ent == threat and contact.visible then return true end
    end
    return false
end

---@param bot Player
---@param threat Player
---@param wait fun()
function fixture.Acquire(bot, threat, wait)
    local input = assert(PW.BotInput)
    input.SetScripted(bot, { buttons = 0, view = bot:EyeAngles() })
    local deadline, ready = CurTime() + 4, false
    repeat
        wait()
        ready = acquired(assert(PW.Bot).Get(bot), threat)
    until ready or CurTime() >= deadline
    input.SetScripted(bot, nil)
    assert(ready, "survivor fixture did not acquire native infected sight and escape behavior")
end

return fixture
