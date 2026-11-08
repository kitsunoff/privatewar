-- Authoritative deployment must reject nonfinite native inputs before any engine trace.
---@type Player?
local bot

---@return Player
local function owner()
    if bot ~= nil and IsValid(bot) then return bot end
    bot = player.CreateNextBot("PW finite deployment fixture")
    assert(IsValid(bot), "finite deployment fixture needs a free listen-server slot")
    bot:Spawn()
    return bot
end

return {
    groupName = "PW support finite engine boundary",
    afterAll = function() if bot ~= nil and IsValid(bot) then bot:Kick("finite fixture complete") end end,
    cases = {
        {
            name = "Deployment boundary: nonfinite floor never reaches an engine line or hull trace",
            func = function()
                local actor = owner()
                stub(util, "TraceLine").with(function() error("nonfinite floor reached engine trace") end)
                expect(assert(PW.Devices).Validate(actor, "ground_sensor", Vector(0 / 0, 0, 0))).to.beFalse()
                expect(assert(PW.Devices).Validate(actor, "ground_sensor", Vector(math.huge, 0, 0))).to.beFalse()
            end
        },
        {
            name = "Deployment boundary: nonfinite native aim refuses before any engine trace",
            func = function()
                local actor = owner()
                stub(assert(FindMetaTable("Player")), "GetAimVector").returns(Vector(0 / 0, 0, 0))
                stub(util, "TraceLine").with(function() error("nonfinite aim reached engine trace") end)
                expect(assert(PW.Devices).Validate(actor, "ground_sensor", Vector())).to.beFalse()
            end
        }
    }
}
