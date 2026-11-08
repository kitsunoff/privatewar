-- Actual support producers through the shared reveal owner; engine geometry is isolated from disclosure policy.
local key = "PW.SupportDisclosureTest"
---@type PW.RevealStore?
local oldReveal
---@type PW.StreaksStore?
local oldStreaks
---@type PW.SupportDevice[]
local oldRecords = {}
---@type PW.Instance?
local instance
---@type { packets: PW.RevealBlip[][], stimuli: Player[], reads: table<Player, integer>, owner: Player? }
local seen = { packets = {}, stimuli = {}, reads = {} }

---@param index integer
---@return Player
local function fake(index)
    local pos = Vector(index * 100, 0, 0)
    ---@type Player
    local entity
    entity = { IsValid = function() return true end, Alive = function() return true end,
        Team = function() return index end, EntIndex = function() return index end,
        EyePos = function() return Vector(0, 0, 32) end, GetAimVector = function() return Vector(1, 0, 0) end,
        WorldSpaceCenter = function() return pos + Vector(0, 0, 32) end,
        GetPos = function() seen.reads[entity] = (seen.reads[entity] or 0) + 1 return pos end } --[[@as Player]]
    return entity
end

---@return PW.StreaksLib
local function streaks() return assert(PW.Streaks) end

---@param owner Player
local function scan(owner)
    assert(streaks().Give)(owner, "directional_scan")
    assert(assert(streaks().Use)(owner, "directional_scan"), "scan refused")
end

---@param owner Player
local function sensor(owner)
    local now = CurTime()
    instance = PW.Instance({ OnEquip = function() end }, owner)
    local entity = { IsValid = function() return true end,
        WorldSpaceCenter = function() return Vector(0, 0, 16) end } --[[@as Entity]]
    assert(PW.Devices)._Records = { { owner = owner, kind = "ground_sensor", entity = entity,
        position = Vector(), team = owner:Team(), ends = now + 30,
        instance = instance --[[@as PW.StreakInstance]], pulse = now } }
    PW.Call(assert(PW.Modules.GetStored("support_devices")), "Maintain", now, 0.25)
end

return {
    groupName = "PW support producer disclosure",
    beforeEach = function()
        oldReveal, oldStreaks, oldRecords = PW._Reveal, PW._Streaks, assert(PW.Devices)._Records
        seen = { packets = {}, stimuli = {}, reads = {} }
        PW._Streaks = assert(streaks()._NewStore)({
            lookup = function(id) return assert(PW.Registries.streaks).Get(id) --[[@as PW.Streak?]] end,
            phase = function() return "LIVE" end, alive = function() return true end, publish = function() end
        })
    end,
    afterEach = function()
        hook.Remove("PW_CanReveal", key)
        hook.Remove("PW_IsEnemy", key)
        assert(PW.Devices)._Records = oldRecords
        if instance ~= nil then instance:Remove() instance = nil end
        for inst in pairs(assert(streaks()._Instances)) do
            if inst.ClassName == "directional_scan" then inst:Remove() assert(streaks()._Instances)[inst] = nil end
        end
        PW._Reveal, PW._Streaks = oldReveal, oldStreaks
    end,
    cases = {
        {
            name = "Support producers: scan and sensor use identical concealment before human packets and bot stimuli",
            func = function()
                local owner, hidden, shown = fake(1), fake(2), fake(3)
                local all = { owner, hidden, shown }
                PW._Reveal = assert(streaks()._NewRevealStore)({
                    clock = CurTime, players = function() return all end,
                    members = function() return { owner } end,
                    isEnemy = function(a, b) return a ~= b end,
                    send = function(_, blips) seen.packets[#seen.packets + 1] = blips end,
                    stimulus = function(_, target) seen.stimuli[#seen.stimuli + 1] = target end
                })
                hook.Add("PW_CanReveal", key, function(_, target, source)
                    seen.owner = source
                    if target == hidden then return false end
                end)
                hook.Add("PW_IsEnemy", key, function(a, b) return a ~= b end)
                stub(util, "TraceLine").returns({ Fraction = 1 })
                stub(player, "GetAll").returns(all)
                scan(owner)
                sensor(owner)
                expect(#seen.packets).to.equal(2)
                expect(seen.packets[1][1].index).to.equal(3)
                expect(seen.packets[2][1].index).to.equal(3)
                expect({ #seen.packets[1], #seen.packets[2] }).to.deepEqual({ 1, 1 })
                expect(seen.stimuli).to.deepEqual({ shown, shown })
                expect(seen.owner).to.equal(owner)
            end
        },
        {
            name = "Support reveal: target veto precedes GetPos and independent Counter-UAV filtering",
            func = function()
                local owner, hidden = fake(1), fake(2)
                PW._Reveal = assert(streaks()._NewRevealStore)({
                    clock = CurTime, players = function() return { owner, hidden } end,
                    members = function() return { owner } end, isEnemy = function(a, b) return a ~= b end,
                    send = function(_, blips) seen.packets[#seen.packets + 1] = blips end,
                    jamSend = function() end,
                    stimulus = function(_, target) seen.stimuli[#seen.stimuli + 1] = target end
                })
                hook.Add("PW_CanReveal", key, function(_, target) if target == hidden then return false end end)
                expect(assert(PW.Reveal)(owner, { hidden }, 2.1, owner)).to.equal(0)
                expect(seen.reads[hidden]).to.beNil()
                hook.Remove("PW_CanReveal", key)
                assert(streaks().Jam)(hidden, 5)
                expect(assert(PW.Reveal)(owner, { hidden }, 1.5, owner)).to.equal(0)
                expect(seen.reads[hidden]).to.beNil()
                expect({ #seen.packets, #seen.stimuli }).to.deepEqual({ 0, 0 })
            end
        },
        {
            name = "Scan feedback: concealed and empty results use the same generic activation line without counts",
            func = function()
                local owner, hidden = fake(1), fake(2)
                local all = { owner, hidden }
                PW._Reveal = assert(streaks()._NewRevealStore)({ clock = CurTime,
                    players = function() return all end, members = function() return { owner } end,
                    isEnemy = function(a, b) return a ~= b end,
                    send = function() error("concealed scan sent a position") end })
                hook.Add("PW_CanReveal", key, function() return false end)
                stub(util, "TraceLine").returns({ Fraction = 1 })
                ---@type string[]
                local lines = {}
                ---@param text string
                local function feedback(_, text) lines[#lines + 1] = text end
                stub(assert(PW.Devices), "Feedback").with(feedback)
                scan(owner)
                all = { owner }
                scan(owner)
                expect(lines).to.deepEqual({ "SCAN ACTIVATED", "SCAN ACTIVATED" })
            end
        }
    }
}
