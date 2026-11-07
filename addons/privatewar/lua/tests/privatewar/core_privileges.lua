-- T-1.10 privileges and optional CAMI (TASKS.md, "Mandatory test cases"; 00-core.md d.7).
-- Every case runs with an empty privilege store, a capturing logger and the CAMI global saved and restored.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---Creates a bot with the given usergroup and remembers it in state for afterEach to kick.
---@param state GLuaTest_TestState
---@param name string
---@param group string
---@return Player
local function makeBot(state, name, group)
    local bot = player.CreateNextBot(name)
    assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
    bot:SetUserGroup(group)
    ---@type Player[]
    local bots = state.bots
    bots[#bots + 1] = bot
    return bot
end

---Plain stand-in for a player: only the two methods the fallback reads.
---@param admin boolean
---@param superAdmin boolean
---@return Player
local function fakePlayer(admin, superAdmin)
    local fake = {
        IsAdmin = function() return admin end,
        IsSuperAdmin = function() return superAdmin end
    }
    return fake --[[@as Player]]
end

---@class PWTest.CamiCheck
---@field ply any
---@field name string
---@field callback any

---@class PWTest.CamiStub : PW.CamiLib
---@field registered PW.CamiPrivilege[]
---@field checks PWTest.CamiCheck[]
---@field answer boolean

---Stub of the CAMI global: records registrations and access checks, answers with stub.answer.
---@return PWTest.CamiStub
local function newCamiStub()
    ---@type PWTest.CamiStub
    local stub
    stub = {
        registered = {},
        checks = {},
        answer = true,
        RegisterPrivilege = function(priv)
            stub.registered[#stub.registered + 1] = priv
            return priv
        end,
        PlayerHasAccess = function(ply, name, callback)
            stub.checks[#stub.checks + 1] = { ply = ply, name = name, callback = callback }
            return stub.answer
        end
    }
    return stub
end

return {
    groupName = "PW privileges",
    beforeEach = function(state)
        state.bots = {}
        state.previousCami = rawget(_G, "CAMI")
        state.previousStore = PW._Privileges
        ---@type string[]
        local logged = {}
        state.logged = logged
        PW._Privileges = {
            defs = {},
            log = function(message) logged[#logged + 1] = message end
        }
        rawset(_G, "CAMI", nil)
    end,
    afterEach = function(state)
        rawset(_G, "CAMI", state.previousCami)
        PW._Privileges = state.previousStore
        ---@type Player[]
        local bots = state.bots
        for _, bot in ipairs(bots) do
            if IsValid(bot) then bot:Kick("PW privileges test finished") end
        end
    end,
    cases = {
        {
            name = "Without CAMI a superadmin default passes for a superadmin bot and fails for a normal bot",
            func = function(state)
                expect(PW.Privilege("pw.test.super", "superadmin")).to.beTrue()
                local boss = makeBot(state, "PW test superadmin", "superadmin")
                local grunt = makeBot(state, "PW test user", "user")
                expect(PW.Can(boss, "pw.test.super")).to.beTrue()
                expect(PW.Can(grunt, "pw.test.super")).to.beFalse()
            end
        },
        {
            name = "With a CAMI global the privilege is registered in CAMI and checked through it",
            func = function(state)
                local cami = newCamiStub()
                rawset(_G, "CAMI", cami)
                PW.Privilege("pw.test.cami", "superadmin")

                expect(#cami.registered).to.equal(1)
                expect(cami.registered[1].Name).to.equal("pw.test.cami")
                expect(cami.registered[1].MinAccess).to.equal("superadmin")

                local grunt = makeBot(state, "PW test user", "user")
                cami.answer = true
                expect(PW.Can(grunt, "pw.test.cami")).to.beTrue()
                cami.answer = false
                expect(PW.Can(grunt, "pw.test.cami")).to.beFalse()

                expect(#cami.checks).to.equal(2)
                expect(cami.checks[1].ply).to.equal(grunt)
                expect(cami.checks[1].name).to.equal("pw.test.cami")
                expect(cami.checks[1].callback).to.beNil()
            end
        },
        {
            name = "A privilege declared before CAMI appears is registered in CAMI on first check",
            func = function()
                PW.Privilege("pw.test.late", "admin")
                local cami = newCamiStub()
                rawset(_G, "CAMI", cami)
                expect(PW.Can(fakePlayer(false, false), "pw.test.late")).to.beTrue()
                expect(#cami.registered).to.equal(1)
                expect(cami.registered[1].Name).to.equal("pw.test.late")
                PW.Can(fakePlayer(false, false), "pw.test.late")
                expect(#cami.registered).to.equal(1)
            end
        },
        {
            name = "Admin default passes for admins and superadmins only",
            func = function()
                PW.Privilege("pw.test.admin", "admin")
                expect(PW.Can(fakePlayer(true, false), "pw.test.admin")).to.beTrue()
                expect(PW.Can(fakePlayer(true, true), "pw.test.admin")).to.beTrue()
                expect(PW.Can(fakePlayer(false, false), "pw.test.admin")).to.beFalse()
            end
        },
        {
            name = "User default passes for everyone",
            func = function()
                PW.Privilege("pw.test.user", "user")
                expect(PW.Can(fakePlayer(false, false), "pw.test.user")).to.beTrue()
            end
        },
        {
            name = "Unknown privilege is denied with one log line",
            func = function(state)
                expect(PW.Can(fakePlayer(true, true), "pw.test.nope")).to.beFalse()
                expect(#state.logged).to.equal(1)
                expect(string.find(must(state.logged[1]), "pw.test.nope", 1, true)).to.exist()
            end
        },
        {
            name = "Unknown default usergroup is rejected with one log line",
            func = function(state)
                expect(PW.Privilege("pw.test.bad", "owner")).to.beFalse()
                expect(#state.logged).to.equal(1)
                expect(PW.Can(fakePlayer(true, true), "pw.test.bad")).to.beFalse()
            end
        },
        {
            name = "A CAMI check that errors is denied with a log line, not a crash",
            func = function(state)
                local cami = newCamiStub()
                cami.PlayerHasAccess = function() error("admin mod gave no immediate answer") end
                rawset(_G, "CAMI", cami)
                PW.Privilege("pw.test.err", "user")
                expect(PW.Can(fakePlayer(true, true), "pw.test.err")).to.beFalse()
                expect(#state.logged).to.equal(1)
                expect(string.find(must(state.logged[1]), "pw.test.err", 1, true)).to.exist()
            end
        }
    }
}
