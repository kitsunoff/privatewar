-- Regression of the actual missing source-scope seam: destroying a sensor must preserve same-owner UAV and CUAV.
local key = "PW.SupportRevealRetirement"
---@type PW.RevealStore?
local previous
---@type PW.SupportDevice[]
local oldRecords = {}
---@type PW.Instance?
local instance
---@type Entity?
local entity

---@param index integer
---@return Player
local function fake(index)
    return { IsValid = function() return true end, Alive = function() return true end,
        Team = function() return index end, EntIndex = function() return index end,
        GetPos = function() return Vector(index * 100, 0, 0) end,
        WorldSpaceCenter = function() return Vector(index * 100, 0, 32) end } --[[@as Player]]
end

return {
    groupName = "PW support reveal source retirement",
    beforeEach = function()
        previous, oldRecords = PW._Reveal, assert(PW.Devices)._Records
    end,
    afterEach = function()
        assert(PW.Devices)._Records = oldRecords
        if instance ~= nil then instance:Remove() instance = nil end
        if entity ~= nil and IsValid(entity) then entity:Remove() end
        PW._Reveal = previous
        hook.Remove("PW_IsEnemy", key)
    end,
    cases = {
        {
            name = "Sensor retirement: remove only its radar pulses while same-owner UAV snapshot and CUAV survive",
            func = function()
                local owner, target = fake(1), fake(2)
                local lib = assert(PW.Streaks)
                local resets = 0
                ---@type number[]
                local sent = {}
                PW._Reveal = assert(lib._NewRevealStore)({ clock = function() return 100 end,
                    players = function() return { owner, target } end,
                    members = function(viewer) return { viewer } end,
                    isEnemy = function(a, b) return a ~= b end,
                    send = function(_, _, seconds) sent[#sent + 1] = seconds end,
                    reset = function() resets = resets + 1 end,
                    stimulus = function() end, jamSend = function() end })
                expect(assert(PW.Reveal)(owner, { target }, 3.5, owner)).to.equal(1)
                assert(lib.Jam)(owner, 10)
                entity = ents.Create("base_anim")
                entity:SetPos(Vector())
                instance = PW.Instance({ OnEquip = function() end }, owner)
                local now = CurTime()
                local record = { owner = owner, kind = "ground_sensor", entity = entity, position = Vector(),
                    team = 1, ends = now + 30, instance = instance --[[@as PW.StreakInstance]],
                    pulse = now } --[[@as PW.SupportDevice]]
                assert(PW.Devices)._Records = { record }
                hook.Add("PW_IsEnemy", key, function(a, b) return a ~= b end)
                stub(player, "GetAll").returns({ owner, target })
                stub(util, "TraceLine").returns({ Fraction = 1 })
                PW.Call(assert(PW.Modules.GetStored("support_devices")), "Maintain", now, 0.25)
                expect(sent).to.deepEqual({ 3.5, 2.1 })
                assert(PW.Devices).Remove(record)
                expect(resets).to.equal(1)
                expect(sent[#sent]).to.equal(3.5)
                expect(assert(PW.Reveal)(target, { owner }, 3, target)).to.equal(0)
            end
        }
    }
}
