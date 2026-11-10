-- A scheduled closure can outlive its player even while an injected board remains available.

---@param id integer
---@return Player, fun()
local function actor(id)
    local valid = true
    local bot = {
        IsValid = function() return valid end,
        Alive = function() assert(valid, "Tried to use a NULL entity!") return true end,
        UserID = function() return id end,
        EyePos = function() assert(valid, "removed actor eye access") return Vector() end,
        GetAimVector = function() assert(valid, "removed actor aim access") return Vector(1, 0, 0) end
    }
    return bot --[[@as Player]], function() valid = false end
end

---@param replace fun(target: table, name: string): GLuaTest_Stub
---@return PW.SupportDevice
local function fixture(replace)
    ---@type table<string, any>
    local record = {
        owner = { IsValid = function() return true end },
        entity = { IsValid = function() return true end, WorldSpaceCenter = function() return Vector(100, 0, 0) end }
    }
    -- Deliberately retain a board for removed actors: validity must not be inferred from this service.
    replace(assert(PW.Bot), "Get").returns({ difficulty = { fov = 110, reaction_mean = 0 }, contacts = {} })
    replace(assert(PW.Devices), "List").returns({ record })
    replace(PW, "IsEnemy").returns(true)
    replace(assert(PW.BotDevices), "CanObserve").returns(true)
    replace(util, "TraceLine").returns({ Fraction = 1 })
    return record --[[@as PW.SupportDevice]]
end

return {
    groupName = "PW device removed actor safety",
    cases = {
        {
            name = "Device scheduler: removed actor with stale board cannot disable scans for subsequent live actors",
            func = function()
                local record = fixture(stub)
                local lib, module = assert(PW.BotDevices), assert(PW.Modules.Get("bots_devices"))
                local removed, remove = actor(-9101)
                local live, removeLive = actor(-9102)
                local bots = { removed, live }
                ---@type table<string, fun()>
                local callbacks = {}
                stub(assert(PW.BotScheduler), "Register").with(function(id, callback) callbacks[id] = callback end)
                stub(assert(PW.BotScheduler), "Unregister").with(function(id) callbacks[id] = nil end)
                stub(player, "GetBots").with(function() return bots end)
                local think = (hook.GetTable() --[[@as table<string, table<any, function>>]]).Think[module]
                assert(think, "device registration hook is missing")(module)
                local staleScan, liveScan = assert(callbacks["devices:-9101"]), assert(callbacks["devices:-9102"])
                remove()
                staleScan() -- Actual registered closure -> PW.Call -> ScanBot -> Step, before unregistration.
                local survived = module:IsValid()
                liveScan()
                local contact = lib.Contact(live)
                -- Remove our registrations even if the production call disabled the module in a RED run.
                removeLive()
                bots = {}
                think(module)
                expect(survived).to.beTrue()
                expect(module:IsValid()).to.beTrue()
                expect(contact ~= nil and contact.device == record).to.beTrue()
            end
        },
        {
            name = "Device contact: removed recognized actor is rejected before Contact or Step calls engine methods",
            func = function()
                fixture(stub)
                local lib = assert(PW.BotDevices)
                local bot, remove = actor(-9103)
                lib.Step(bot)
                expect(lib.Contact(bot) ~= nil).to.beTrue()
                remove()
                local ok, contact = pcall(lib.Contact, bot)
                expect(ok).to.beTrue()
                expect(contact).to.beNil()
                expect(pcall(lib.Step, bot)).to.beTrue()
            end
        },
        {
            name = "Device NULL: stale board cannot make engine NULL safe to call Alive on",
            func = function()
                fixture(stub)
                local lib = assert(PW.BotDevices)
                local bot = NULL --[[@as Player]]
                expect(IsValid(bot)).to.beFalse()
                expect(assert(PW.Bot).Get(bot) ~= nil).to.beTrue()
                expect(pcall(lib.Step, bot)).to.beTrue()
                local ok, contact = pcall(lib.Contact, bot)
                expect(ok).to.beTrue()
                expect(contact).to.beNil()
            end
        }
    }
}
