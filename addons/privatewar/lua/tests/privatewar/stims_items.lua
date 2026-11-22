---@return table<string, any>
local function stims()
    return assert(rawget(PW, "Stims"), "stims module is not implemented")
end

---@param id string
---@return PW.EquipmentItem
local function item(id)
    local registry = assert(PW.Registries).equipment
    return assert(registry.Get(id), id .. " is not registered") --[[@as PW.EquipmentItem]]
end

---@class PW.StimTestTimer
---@field at number
---@field delay number
---@field reps integer
---@field fn function

---@param state table<string, any>
---@param seconds number
local function advance(state, seconds)
    local start = state.now --[[@as number]]
    local stop = start + seconds
    local timers = state.timers --[[@as table<string, PW.StimTestTimer>]]
    while true do
        ---@type string?
        local nextName
        ---@type PW.StimTestTimer?
        local due
        for name, entry in pairs(timers) do
            if entry.at <= stop + 0.00001 and (due == nil or entry.at < due.at) then nextName, due = name, entry end
        end
        if due == nil or nextName == nil then break end
        state.now = due.at
        due.reps = due.reps - 1
        if due.reps == 0 then timers[nextName] = nil else due.at = due.at + due.delay end
        due.fn()
    end
    state.now = stop
end

---@param state table<string, any>
---@param id string
---@return PW.EquipmentEntry
local function equip(state, id)
    local lib = assert(PW.Equipment)
    state.id = id
    assert(lib._OnSpawn)(state.ply)
    return assert(assert(PW._Equipment).players[state.ply].tactical, id .. " is not equipped")
end

---@param state table<string, any>
---@return boolean
local function use(state)
    return assert(assert(PW.Equipment).Use)(state.ply, "tactical")
end

return {
    groupName = "PW item-owned stim effects",
    beforeEach = function(state)
        state.oldEquipment = PW._Equipment
        state.hp, state.max, state.armor, state.now = 330, 400, 95, 10
        ---@type table<string, PW.StimTestTimer>
        local timers = {}
        ---@type table<string, number>
        local marks = {}
        ---@type table<string, number?>
        local sources = {}
        state.timers, state.marks, state.sources = timers, marks, sources
        state.ply = {
            IsValid = function() return true end, IsPlayer = function() return true end,
            Alive = function() return true end, IsBot = function() return true end,
            Health = function() return state.hp end, GetMaxHealth = function() return state.max end,
            Armor = function() return state.armor end,
            SetHealth = function(_, value) state.hp = value end,
            SetArmor = function(_, value) state.armor = value end,
            EmitSound = function() end, ViewPunch = function() end,
            GetNW2Float = function(_, key, default) return marks[key] or default end,
            SetNW2Float = function(_, key, value) marks[key --[[@as string]]] = value --[[@as number]] end
        }
        PW._Equipment = assert(assert(PW.Equipment)._NewStore)({
            resolve = function()
                local id = state.id --[[@as string?]]
                return { tactical = id }
            end,
            lookup = function(id)
                if state.variant ~= nil then return state.variant end
                return assert(PW.Equipment)._Lookup(id)
            end,
            phase = function() return "LIVE" end, clock = function() return state.now end,
            alive = function() return true end, publish = function() end
        })
        stub(_G, "CurTime").with(function() return state.now end)
        -- GLuaTest's case-local timer table is separate from the global used by PW.Instance.
        local engineTimer = _G.timer
        stub(engineTimer, "Create").with(function(name, delay, reps, fn)
            assert(reps > 0, "stim timers must be finite")
            local now = state.now --[[@as number]]
            timers[name] = { at = now + delay, delay = delay, reps = reps, fn = fn }
        end)
        local remove = engineTimer.Remove
        stub(engineTimer, "Remove").with(function(name)
            if timers[name] == nil then remove(name) else timers[name] = nil end
        end)
        local overrides = assert(PW.PlayerOverrides)
        if isfunction(rawget(overrides, "MoveSource")) then
            -- Record source boundaries here; real baseline composition has its own test group.
            stub(overrides, "MoveSource").with(function(_, id, value) sources[id] = value end)
        end
    end,
    afterEach = function(state)
        if state.savedOverrides ~= nil then rawset(PW, "PlayerOverrides", state.savedOverrides) end
        if state.disabled ~= nil then assert(PW.Registries).equipment._Enable(state.disabled) end
        if state.disabledModule then PW.Modules._Enable("stims") end
        assert(assert(PW.Equipment)._Clear)(state.ply)
        PW._Equipment = state.oldEquipment
    end,
    cases = {
        {
            name = "stim_heal: refused at or above max health, charge kept",
            func = function(state)
                local entry = equip(state, "stim_heal")
                for _, hp in ipairs({ 400, 410 }) do
                    state.hp = hp
                    expect(use(state)).to.beFalse()
                    expect({ entry.count, entry.last, state.hp }).to.deepEqual({ 1, -math.huge, hp })
                end
            end
        },
        {
            name = "stim_heal: heals after the use time in ticks and stops at max health",
            func = function(state)
                equip(state, "stim_heal")
                state.hp = 355
                expect(use(state)).to.beTrue()
                advance(state, 0.39)
                expect(state.hp).to.equal(355)
                advance(state, 0.01)
                expect(state.hp).to.equal(355)
                expect(state.marks.pw_stim_heal_until).to.equal(11.9)
                advance(state, 0.25)
                expect(state.hp).to.equal(365)
                state.hp = 361 -- damage does not interrupt the remaining ticks
                advance(state, 0.25)
                expect(state.hp).to.equal(371)
                advance(state, 1)
                expect({ state.hp, state.marks.pw_stim_heal_until }).to.deepEqual({ 400, 0 })
            end
        },
        {
            name = "stim_heal: refused while its heal is pending or running",
            func = function(state)
                local entry = equip(state, "stim_heal")
                entry.count = 3
                expect(use(state)).to.beTrue()
                -- Bypass only the ordinary per-slot cooldown so the item's pending guard is what refuses.
                entry.last = -math.huge
                expect(use(state)).to.beFalse()
                advance(state, 0.8)
                expect(use(state)).to.beFalse()
                expect({ entry.count, entry.last }).to.deepEqual({ 2, -math.huge })
            end
        },
        {
            name = "stim_armor: refused at or above stims.armor_max, charge kept",
            func = function(state)
                local entry = equip(state, "stim_armor")
                for _, armor in ipairs({ 150, 155 }) do
                    state.armor = armor
                    expect(use(state)).to.beFalse()
                    expect({ entry.count, entry.last, state.armor }).to.deepEqual({ 1, -math.huge, armor })
                end
            end
        },
        {
            name = "stim_armor: adds armor in ticks up to the cap",
            func = function(state)
                equip(state, "stim_armor")
                expect(use(state)).to.beTrue()
                advance(state, 0.4)
                expect(state.armor).to.equal(95)
                expect(state.marks.pw_stim_armor_until).to.equal(11.4)
                advance(state, 0.25)
                expect(state.armor == 107 or state.armor == 108).to.beTrue()
                advance(state, 0.75)
                expect({ state.armor, state.marks.pw_stim_armor_until }).to.deepEqual({ 145, 0 })
                equip(state, "stim_armor")
                expect(use(state)).to.beTrue()
                advance(state, 1.4)
                expect(state.armor).to.equal(150)
            end
        },
        {
            name = "stim_speed: sets the move source after the use time and marks the end time",
            func = function(state)
                equip(state, "stim_speed")
                expect(use(state)).to.beTrue()
                advance(state, 0.39)
                expect(state.sources.stim_speed).to.beNil()
                expect(state.marks.pw_stim_speed_until).to.beNil()
                advance(state, 0.01)
                expect(state.sources.stim_speed).to.equal(1.2)
                expect(state.marks.pw_stim_speed_until).to.equal(16.4)
            end
        },
        {
            name = "stim_speed: expiry removes the move source and clears the mark",
            func = function(state)
                local entry = equip(state, "stim_speed")
                expect(use(state)).to.beTrue()
                advance(state, 6.39)
                expect(state.sources.stim_speed).to.equal(1.2)
                advance(state, 0.01)
                expect(state.sources.stim_speed).to.beNil()
                expect(state.marks.pw_stim_speed_until).to.equal(0)
                expect(entry.instance:IsValid()).to.beTrue()
                expect(use(state)).to.beTrue()
            end
        },
        {
            name = "stim_speed: refused while active, charge kept",
            func = function(state)
                local entry = equip(state, "stim_speed")
                expect(use(state)).to.beTrue()
                entry.last = -math.huge
                expect(use(state)).to.beFalse() -- pending, not the ordinary cooldown
                advance(state, 1)
                expect(use(state)).to.beFalse()
                expect({ entry.count, entry.last }).to.deepEqual({ 1, -math.huge })
            end
        },
        {
            name = "stim_speed: OnUnequip removes the move source (death, match end, disable)",
            func = function(state)
                local module = assert(PW.Modules.Get("equipment"))
                local registry = assert(PW.Registries).equipment
                ---@type function[]
                local endPaths = {
                    function() assert(hook.GetTable().PostPlayerDeath[module])(module, state.ply) end,
                    function() PW.Call(module, "PW_MatchEnd", {}) end,
                    function()
                        state.disabled = "stim_speed"
                        registry._Disable(state.disabled, "stim cleanup fixture")
                    end
                }
                for _, finish in ipairs(endPaths) do
                    local entry = equip(state, "stim_speed")
                    expect(use(state)).to.beTrue()
                    advance(state, 0.4)
                    expect(state.sources.stim_speed).to.equal(1.2)
                    finish()
                    expect(entry.instance:IsValid()).to.beFalse()
                    expect(state.sources.stim_speed).to.beNil()
                    expect(state.marks.pw_stim_speed_until).to.equal(0)
                    expect(table.Count(state.timers)).to.equal(0)
                end
            end
        },
        {
            name = "Instance removal stops pending heal and armor ticks",
            func = function(state)
                for _, id in ipairs({ "stim_heal", "stim_armor" }) do
                    local pending = equip(state, id).instance
                    local hp = state.hp --[[@as number]]
                    local armor = state.armor --[[@as number]]
                    expect(use(state)).to.beTrue()
                    pending:Remove()
                    advance(state, 3)
                    expect({ state.hp, state.armor, table.Count(state.timers) }).to.deepEqual({ hp, armor, 0 })
                    local active = equip(state, id).instance
                    expect(use(state)).to.beTrue()
                    advance(state, 0.65)
                    local currentHP = state.hp --[[@as number]]
                    local currentArmor = state.armor --[[@as number]]
                    expect(currentHP + currentArmor > hp + armor).to.beTrue()
                    hp, armor = currentHP, currentArmor
                    active:Remove()
                    advance(state, 3)
                    expect({ state.hp, state.armor, table.Count(state.timers) }).to.deepEqual({ hp, armor, 0 })
                end
            end
        },
        {
            name = "Missing player_overrides module refuses the speed stim",
            func = function(state)
                local entry = equip(state, "stim_speed")
                state.savedOverrides = PW.PlayerOverrides
                rawset(PW, "PlayerOverrides", nil)
                expect(use(state)).to.beFalse()
                expect({ entry.count, entry.last }).to.deepEqual({ 2, -math.huge })
            end
        },
        {
            name = "Round end and stims module disable cancel pending and active effects synchronously",
            func = function(state)
                local pending = equip(state, "stim_heal").instance
                expect(use(state)).to.beTrue()
                PW.Notify("PW_RoundEnd", 1, false, {})
                expect(pending:IsValid()).to.beFalse()
                advance(state, 4)
                expect(state.hp).to.equal(330)
                local active = equip(state, "stim_speed").instance
                expect(use(state)).to.beTrue()
                advance(state, 0.4)
                expect(state.sources.stim_speed).to.equal(1.2)
                state.disabledModule = true
                PW.Modules._Disable("stims", "stim module cleanup fixture")
                expect(active:IsValid()).to.beFalse()
                expect(state.sources.stim_speed).to.beNil()
                expect(state.marks.pw_stim_speed_until).to.equal(0)
                expect(table.Count(state.timers)).to.equal(0)
                local refused = equip(state, "stim_armor")
                expect(use(state)).to.beFalse()
                expect(refused.count).to.equal(1)
            end
        },
        {
            name = "Zero-duration health and armor apply at the end of injection without an active mark",
            func = function(state)
                local setting = PW.Setting
                stub(PW, "Setting").with(function(id)
                    if id == "stims.heal_time" or id == "stims.armor_time" then return 0 end
                    return setting(id)
                end)
                equip(state, "stim_heal")
                expect(use(state)).to.beTrue()
                advance(state, 0.39)
                expect(state.hp).to.equal(330)
                advance(state, 0.01)
                expect(state.hp).to.equal(390)
                expect(state.marks.pw_stim_heal_until).to.beNil()
                equip(state, "stim_armor")
                expect(use(state)).to.beTrue()
                advance(state, 0.4)
                expect(state.armor).to.equal(145)
                expect(state.marks.pw_stim_armor_until).to.beNil()
            end
        },
        {
            name = "A Base variant inherits OnUse and uses its own Mult and Time",
            func = function(state)
                local registry = PW.Registry.New("test_stim_items", { log = function() end })
                local speed = item("stim_speed")
                registry.Register({ OnUse = speed.OnUse, OnUnequip = speed.OnUnequip }, "base")
                registry.Register({ Base = "base", Count = 1, Mult = 1.35, Time = 4 }, "variant")
                registry.ResolveAll()
                state.variant = assert(registry.Get("variant"))
                equip(state, "variant")
                expect(state.variant.OnUse).to.equal(speed.OnUse)
                expect(use(state)).to.beTrue()
                advance(state, 0.4)
                expect(state.sources.variant).to.equal(1.35)
                expect(state.sources.stim_speed).to.beNil()
                expect(state.marks.pw_stim_speed_until).to.equal(14.4)
            end
        },
        {
            name = "Played sends pw_stim_used to the owner only with the item index",
            func = function()
                ---@type table[]
                local signals = {}
                local owner = {
                    IsValid = function() return true end, IsBot = function() return false end,
                    EmitSound = function(_, sound) signals[#signals + 1] = { "sound", sound --[[@as string]] } end,
                    ViewPunch = function(_, angle)
                        local value = angle --[[@as Angle]]
                        signals[#signals + 1] = { "punch", value.p }
                    end
                }
                stub(net, "Start").with(function(channel) signals[#signals + 1] = { "start", channel } end)
                stub(net, "WriteUInt").with(function(index, bits)
                    signals[#signals + 1] = { "uint", index, bits }
                end)
                stub(net, "Send").with(function(ply) signals[#signals + 1] = { "send", ply } end)
                stub(net, "Broadcast").with(function() error("presentation broadcast") end)
                stims().Played(owner, { ClassName = "stim_speed", Sound = "items/battery_pickup.wav" })
                expect(signals).to.deepEqual({
                    { "sound", "items/battery_pickup.wav" }, { "punch", 2 },
                    { "start", "pw_stim_used" }, { "uint", 2, 8 }, { "send", owner }
                })
            end
        }
    }
}
