local message = "pw_equipment_use"
local stimCounts = { stim_heal = 1, stim_speed = 2, stim_armor = 1 }
---@type { bot: Player?, owned: boolean }
local pool = { owned = false }

---@return PW.EquipmentLib
local function equipment()
    return assert(PW.Equipment)
end

---@param ply Player
---@param slot string
---@return boolean
local function clientUse(ply, slot)
    local use = assert(rawget(equipment(), "_ClientUse"), "client equipment use is not implemented")
    return use(ply, slot)
end

---@return Player
local function botOf()
    local bot = pool.bot
    if bot ~= nil and IsValid(bot) then return bot end
    bot = player.GetBots()[1]
    if not IsValid(bot) then
        bot = player.CreateNextBot("PW stim equipment test")
        pool.owned = true
    end
    assert(IsValid(bot) and bot:IsBot(), "equipment wire test needs one native bot slot")
    pool.bot = bot
    return bot
end

---@param state table<string, any>
---@param id string
local function equipItem(state, id)
    state.actualItem = id
    assert(equipment()._Lookup(id), id .. " is not registered")
    assert(equipment()._OnSpawn)(state.ply)
end

return {
    groupName = "PW stim equipment key and inventory",
    beforeAll = function()
        pool.bot, pool.owned = nil, false
    end,
    afterAll = function()
        local bot = pool.bot
        if bot ~= nil and pool.owned and IsValid(bot) then bot:Kick("PW stim equipment complete") end
    end,
    beforeEach = function(state)
        state.previousEquipment = PW._Equipment
        state.previousNet = PW._Net
        rawset(state, "actualItem", nil)
        rawset(state, "perk", nil)
        state.phase, state.now, state.uses, state.accept = "LIVE", 1, 0, true
        ---@type table<string, number>
        local marks = {}
        state.ply = {
            IsValid = function() return true end, IsBot = function() return true end,
            Alive = function() return true end,
            Health = function() return 40 end, GetMaxHealth = function() return 100 end,
            Armor = function() return 0 end,
            EmitSound = function() end, ViewPunch = function() end,
            GetNW2Float = function(_, key, default) return marks[key] or default end,
            SetNW2Float = function(_, key, value) marks[key --[[@as string]]] = value --[[@as number]] end
        } --[[@as Player]]
        state.item = {
            ClassName = "test_stim_key", Name = "Test Stim", Count = 2,
            OnUse = function(self, owner)
                state.uses, state.owner, state.instance = state.uses + 1, owner, self
                return state.accept
            end
        }
        PW._Equipment = assert(equipment()._NewStore)({
            lookup = function(id)
                if id == "test_stim_key" then return state.item end
                return equipment()._Lookup(id)
            end,
            resolve = function() return { tactical = state.actualItem or "test_stim_key" } end,
            publish = function() end,
            clock = function() return state.now end,
            phase = function() return state.phase end,
            alive = function() return true end
        })
        PW._Net = assert(PW.Net)._NewStore({
            clock = function() return state.now end,
            phase = function() return state.phase end,
            log = function() end
        })
        PW._Net.defs[message] = state.previousNet.defs[message]
    end,
    afterEach = function(state)
        if state.perk ~= nil then state.perk:Remove() end
        for ply in pairs(assert(PW._Equipment).players) do assert(equipment()._Clear)(ply) end
        PW._Equipment, PW._Net = state.previousEquipment, state.previousNet
    end,
    cases = {
        {
            name = "KeyAction: select for grenade items, use for weapon-less items, nil when empty",
            func = function()
                local action = assert(rawget(equipment(), "_KeyAction"), "equipment key decision is not implemented")
                expect(action("flash", "weapon_pw_flash", 1)).to.equal("select")
                expect(action("stim_heal", nil, 1)).to.equal("use")
                expect(action(nil, nil, 3)).to.beNil()
                expect(action("stim_heal", nil, 0)).to.beNil()
                expect(action("flash", "weapon_pw_flash", 0)).to.beNil()
            end
        },
        {
            name = "ClientUse: weapon-less item spends one use and runs OnUse",
            func = function(state)
                expect(clientUse(state.ply, "tactical")).to.beTrue()
                expect(equipment().Count(state.ply, "tactical")).to.equal(1)
                expect(state.uses).to.equal(1)
                expect(state.owner).to.equal(state.ply)
                expect(state.instance).to.equal(assert(PW._Equipment).players[state.ply].tactical.instance)
                expect(state.instance).toNot.equal(state.item)
            end
        },
        {
            name = "ClientUse: refuses grenade items",
            func = function(state)
                state.item.Weapon = "weapon_pw_flash"
                expect(clientUse(state.ply, "tactical")).to.beFalse()
                expect(state.uses).to.equal(0)
                expect(equipment().Count(state.ply, "tactical")).to.equal(2)
                local bot = botOf()
                local receiver = assert(net.Receivers[message])
                local reads = 0
                stub(net, "ReadUInt").with(function(bits)
                    assert(bits == 2)
                    reads = reads + 1
                    return 2
                end)
                receiver(2, bot)
                expect(reads).to.equal(1)
                expect(state.uses).to.equal(0)
                expect(equipment().Count(bot, "tactical")).to.equal(2)
                expect(assert(PW._Equipment).players[bot].tactical.last).to.equal(-math.huge)
            end
        },
        {
            name = "pw_equipment_use from a bot sender with a valid index uses the tactical slot",
            func = function(state)
                local bot = botOf()
                local read = 0
                stub(net, "ReadUInt").with(function(bits)
                    assert(bits == 2, "slot index must be two bits")
                    read = read + 1
                    return 2
                end)
                expect(assert(PW.Net)._Dispatch(message, 2, bot)).to.beTrue()
                expect({ read, state.uses, equipment().Count(bot, "tactical") }).to.deepEqual({ 1, 1, 1 })
                expect(state.owner).to.equal(bot)
                local spec = assert(PW._Net.defs[message])
                expect({ spec.who, spec.rate, spec.maxLen, IsValid(spec.owner) }).to.deepEqual({ "any", 4, 1, true })
            end
        },
        {
            name = "pw_equipment_use outside LIVE or with an unknown index does nothing",
            func = function(state)
                local bot = botOf()
                local value, reads = 2, 0
                stub(net, "ReadUInt").with(function()
                    reads = reads + 1
                    return value
                end)
                local wire = assert(PW.Net)
                state.phase = "PREMATCH"
                expect({ wire._Dispatch(message, 2, bot) }).to.deepEqual({ false, "phase" })
                state.phase = "LIVE"
                expect({ wire._Dispatch(message, 9, bot) }).to.deepEqual({ false, "length" })
                expect(reads).to.equal(0)
                for _, bad in ipairs({ 0, 3 }) do
                    value = bad
                    expect(wire._Dispatch(message, 2, bot)).to.beTrue()
                end
                expect({ reads, state.uses, equipment().Count(bot, "tactical") }).to.deepEqual({ 2, 0, 0 })
            end
        },
        {
            name = "Refusal returns false and keeps the count and the cooldown",
            func = function(state)
                state.accept = false
                expect(clientUse(state.ply, "tactical")).to.beFalse()
                expect(equipment().Count(state.ply, "tactical")).to.equal(2)
                local entry = assert(PW._Equipment).players[state.ply].tactical
                expect(entry.last).to.equal(-math.huge)
                state.accept = true
                expect(clientUse(state.ply, "tactical")).to.beTrue()
                expect(entry.last).to.equal(state.now)
            end
        },
        {
            name = "Speed stim has two uses and refuses the second while active",
            func = function(state)
                equipItem(state, "stim_speed")
                ---@type function?
                local inject
                stub(_G.timer, "Create").with(function(_, _, _, fn) if inject == nil then inject = fn end end)
                ---@type number?
                local source
                stub(assert(PW.PlayerOverrides), "MoveSource").with(function(_, _, mult) source = mult end)
                expect(equipment().Count(state.ply, "tactical")).to.equal(2)
                expect(clientUse(state.ply, "tactical")).to.beTrue()
                assert(inject)()
                expect(source).to.equal(1.2)
                local now = state.now --[[@as number]]
                state.now = now + 1
                expect(clientUse(state.ply, "tactical")).to.beFalse()
                expect(equipment().Count(state.ply, "tactical")).to.equal(1)
            end
        },
        {
            name = "Counts refill on spawn",
            func = function(state)
                for id, count in pairs(stimCounts) do
                    equipItem(state, id)
                    expect(equipment().Count(state.ply, "tactical")).to.equal(count)
                    expect(clientUse(state.ply, "tactical")).to.beTrue()
                    expect(equipment().Count(state.ply, "tactical")).to.equal(count - 1)
                    expect(assert(equipment()._OnSpawn)(state.ply)).to.beTrue()
                    expect(equipment().Count(state.ply, "tactical")).to.equal(count)
                end
            end
        },
        {
            name = "Stockpile adds one use to a stim in the tactical slot",
            func = function(state)
                equipItem(state, "stim_speed")
                local stockpile = assert(PW.Registries).perks.Get("stockpile")
                state.perk = PW.Instance(assert(stockpile), state.ply)
                assert(equipment()._GiveWeapons)(state.ply)
                expect(equipment().Count(state.ply, "tactical")).to.equal(3)
                expect(clientUse(state.ply, "tactical")).to.beTrue()
                assert(equipment()._GiveWeapons)(state.ply)
                expect(equipment().Count(state.ply, "tactical")).to.equal(2)
            end
        },
        {
            name = "Item sounds exist in the mounted game content",
            func = function()
                for id in pairs(stimCounts) do
                    local definition = assert(equipment()._Lookup(id), id)
                    expect(file.Exists("sound/" .. assert(rawget(definition, "Sound")), "GAME")).to.beTrue()
                end
            end
        },
        {
            name = "Loadout accepts each stim in the tactical slot and rejects it in the lethal slot",
            func = function(state)
                local loadout = assert(PW.Loadout)
                for id in pairs(stimCounts) do
                    expect(loadout.Validate(state.ply, { tactical = id })).to.beTrue()
                    expect(loadout.Validate(state.ply, { lethal = id })).to.beFalse()
                end
            end
        }
    }
}
