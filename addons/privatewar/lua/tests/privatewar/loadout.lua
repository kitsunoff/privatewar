-- T-4.1 slots, loadout table, validation, PW_ValidateLoadout, PW_PlayerLoadout (TASKS.md, "Mandatory test cases"
-- T-4.1; 05-loadout.md d.1). Pure cases over plain data and fake players; the last case is the in-game smoke: the
-- host gets the default loadout on spawn in a LIVE match with shortened phase ConVars, restored after.

local listenerId = "PW_Test_Loadout"
local phaseConVars = { "pw_prematch_timeout", "pw_countdown", "pw_postmatch_time", "pw_aftermatch" }

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.LoadoutLib
local function loadout()
    return must(PW.Loadout)
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---@return PW.Module
local function module()
    return must(must(PW.Modules).Get("loadout")) --[[@as PW.Module]]
end

---A player stand-in: a unique table is enough for the hooks and the class store.
---@return Player
local function fakePlayer()
    return { IsValid = function() return true end } --[[@as Player]]
end

---Entities of a fake registry: kind -> id -> fields.
---@param data table<string, table<string, table<string, any>>>
---@return PW.LoadoutLookup
local function lookupOf(data)
    return function(kind, id)
        local kindData = data[kind]
        if kindData == nil then return nil end
        return kindData[id]
    end
end

local catalogue = {
    weapons = {
        pwt_smg = { Category = "smg", Kind = "gun" },
        pwt_pistol = { Category = "pistol", Kind = "gun" },
        pwt_knife = { Kind = "melee" }
    },
    perks = { pwt_perk = { Group = 1 } }
}

---@param filter string[]?
---@return table<string, PW.LoadoutSlot>
local function slotsWithPrimary(filter)
    return { primary = { id = "primary", kind = "weapons", filter = filter } }
end

return {
    groupName = "PW loadout",
    beforeEach = function()
        hook.Remove("PW_ValidateLoadout", listenerId)
        hook.Remove("PW_PlayerLoadout", listenerId)
    end,
    afterEach = function()
        hook.Remove("PW_ValidateLoadout", listenerId)
        hook.Remove("PW_PlayerLoadout", listenerId)
        loadout().RemoveSlot("pwt_perk1")
    end,
    cases = {
        {
            name = "Slots: a slot declared by a module appears with its declaration",
            func = function()
                local before = #loadout().GetSlotIds()
                expect(loadout().GetSlot("pwt_perk1")).to.beNil()
                local decl = { kind = "perks", group = 1, label = "#pw.slot.perk1" }
                expect(loadout().DeclareSlot("pwt_perk1", decl)).to.beTrue()
                local slot = must(loadout().GetSlot("pwt_perk1"))
                expect(slot.id).to.equal("pwt_perk1")
                expect(slot.kind).to.equal("perks")
                expect(slot.group).to.equal(1)
                local ids = loadout().GetSlotIds()
                expect(#ids).to.equal(before + 1)
                expect(ids[#ids]).to.equal("pwt_perk1")
                expect(loadout().DeclareSlot("pwt_perk1", { kind = "perks", group = 2 })).to.beTrue()
                expect(#loadout().GetSlotIds()).to.equal(before + 1)
                expect(must(loadout().GetSlot("pwt_perk1")).group).to.equal(2)
                expect(loadout().RemoveSlot("pwt_perk1")).to.beTrue()
                expect(loadout().GetSlot("pwt_perk1")).to.beNil()
            end
        },
        {
            name = "Slots: a bad declaration is refused and nothing is declared",
            func = function()
                local ok, err = loadout().DeclareSlot("pwt_perk1", {} --[[@as any]])
                expect(ok).to.beFalse()
                expect(err).to.exist()
                expect(loadout().DeclareSlot("", { kind = "perks" })).to.beFalse()
                expect(loadout().DeclareSlot("pwt_perk1", { kind = "perks", count = 0 })).to.beFalse()
                local badFilter = { kind = "perks", filter = { 1 } --[[@as any]] }
                expect(loadout().DeclareSlot("pwt_perk1", badFilter)).to.beFalse()
                expect(loadout().GetSlot("pwt_perk1")).to.beNil()
            end
        },
        {
            name = "Slots: the built-in slots are primary, secondary and melee, weapons only",
            func = function()
                for _, id in ipairs({ "primary", "secondary", "melee" }) do
                    expect(must(loadout().GetSlot(id)).kind).to.equal("weapons")
                end
            end
        },
        {
            name = "Validation: a wrong kind in a slot is rejected",
            func = function()
                local slots = {
                    primary = { id = "primary", kind = "weapons" },
                    perk1 = { id = "perk1", kind = "perks" }
                }
                local lookup = lookupOf(catalogue)
                expect(loadout()._Validate(slots, { primary = "pwt_smg", perk1 = "pwt_perk" }, lookup)).to.beTrue()
                -- A weapon id in a perk slot and a perk id in a weapon slot: not in the slot's kind.
                local ok, err = loadout()._Validate(slots, { perk1 = "pwt_smg" }, lookup)
                expect(ok).to.beFalse()
                expect(err).to.exist()
                expect(loadout()._Validate(slots, { primary = "pwt_perk" }, lookup)).to.beFalse()
                expect(loadout()._Validate(slots, { primary = "pwt_missing" }, lookup)).to.beFalse()
                local wrongType = { primary = 5 }
                expect(loadout()._Validate(slots, wrongType --[[@as any]], lookup)).to.beFalse()
            end
        },
        {
            name = "Validation: an unknown slot is rejected",
            func = function()
                local ok = loadout()._Validate(slotsWithPrimary(nil), { nothere = "pwt_smg" }, lookupOf(catalogue))
                expect(ok).to.beFalse()
            end
        },
        {
            name = "Validation: the filter of the slot is respected",
            func = function()
                local slots = slotsWithPrimary({ "smg", "ar" })
                local lookup = lookupOf(catalogue)
                expect(loadout()._Validate(slots, { primary = "pwt_smg" }, lookup)).to.beTrue()
                expect(loadout()._Validate(slots, { primary = "pwt_pistol" }, lookup)).to.beFalse()
                -- The filter also matches the Kind: the melee weapon has no category.
                local meleeSlots = slotsWithPrimary({ "melee" })
                expect(loadout()._Validate(meleeSlots, { primary = "pwt_knife" }, lookup)).to.beTrue()
                expect(loadout()._Validate(slots, { primary = "pwt_knife" }, lookup)).to.beFalse()
            end
        },
        {
            name = "Validation: a slot holds at most its count of items",
            func = function()
                local slots = { perk1 = { id = "perk1", kind = "perks", count = 2 } }
                local lookup = lookupOf({ perks = { a = {}, b = {}, c = {} } })
                expect(loadout()._Validate(slots, { perk1 = { "a", "b" } }, lookup)).to.beTrue()
                expect(loadout()._Validate(slots, { perk1 = { "a", "b", "c" } }, lookup)).to.beFalse()
                expect(loadout()._Validate(slots, { perk1 = "a" }, lookup)).to.beTrue()
                expect(loadout()._Validate(slotsWithPrimary(nil), { primary = { "pwt_smg", "pwt_pistol" } },
                    lookupOf(catalogue))).to.beFalse()
            end
        },
        {
            name = "Validation: an empty loadout is valid (empty slots are allowed)",
            func = function()
                expect(loadout()._Validate(slotsWithPrimary(nil), {}, lookupOf(catalogue))).to.beTrue()
            end
        },
        {
            name = "Items: a string, a list of strings, anything else is nil",
            func = function()
                expect(table.concat(must(loadout()._Items("a")), ",")).to.equal("a")
                expect(table.concat(must(loadout()._Items({ "a", "b" })), ",")).to.equal("a,b")
                expect(loadout()._Items(5)).to.beNil()
                expect(loadout()._Items({ 5 })).to.beNil()
                expect(loadout()._Items({})).to.beNil()
            end
        },
        {
            name = "PW_ValidateLoadout: a listener answering false or a reason rejects the loadout",
            func = function()
                local ply = fakePlayer()
                local lookup = lookupOf({ weapons = { weapon_smg1 = { Category = "smg" } } })
                expect(loadout().Validate(ply, { primary = "weapon_smg1" }, lookup)).to.beTrue()
                hook.Add("PW_ValidateLoadout", listenerId, function() return false end)
                expect(loadout().Validate(ply, { primary = "weapon_smg1" }, lookup)).to.beFalse()
                hook.Add("PW_ValidateLoadout", listenerId, function() return "too heavy" end)
                local ok, err = loadout().Validate(ply, { primary = "weapon_smg1" }, lookup)
                expect(ok).to.beFalse()
                expect(err).to.equal("too heavy")
            end
        },
        {
            name = "PW_ValidateLoadout: a loadout that fails the slot rules never reaches the hook",
            func = function()
                local asked = false
                hook.Add("PW_ValidateLoadout", listenerId, function() asked = true end)
                expect(loadout().Validate(fakePlayer(), { nothere = "x" }, lookupOf(catalogue))).to.beFalse()
                expect(asked).to.beFalse()
            end
        },
        {
            name = "PW_PlayerLoadout: the mode's loadout replaces the player's class",
            func = function()
                local ply = fakePlayer()
                local class = { primary = "weapon_ar2" }
                local modeLoadout = { primary = "weapon_crossbow" }
                loadout().SetClass(ply, class)
                local picked, source = loadout().Resolve(ply)
                expect(picked).to.equal(class)
                expect(source).to.equal("class")
                local saved = PW.ActiveMode
                PW.ActiveMode = { PW_PlayerLoadout = function() return modeLoadout end } --[[@as any]]
                local ok, err = pcall(function()
                    local pickedByMode, modeSource = loadout().Resolve(ply)
                    expect(pickedByMode).to.equal(modeLoadout)
                    expect(modeSource).to.equal("mode")
                end)
                PW.ActiveMode = saved
                if not ok then error(err, 0) end
                -- A listener answers the same question; a non-table answer is ignored.
                hook.Add("PW_PlayerLoadout", listenerId, function() return false end)
                expect(loadout().Resolve(ply)).to.equal(class)
            end
        },
        {
            name = "PW_PlayerLoadout: without a class and without a mode answer the default is used",
            func = function()
                local picked, source = loadout().Resolve(fakePlayer())
                expect(source).to.equal("default")
                expect(picked.primary).to.equal(loadout().Default().primary)
                loadout().Default().primary = "changed"
                expect(loadout().Default().primary).to.equal("weapon_smg1")
            end
        },
        {
            name = "Default: smg1, pistol and crowbar, valid against the slots and the catalogue",
            func = function()
                local default = loadout().Default()
                expect(default.primary).to.equal("weapon_smg1")
                expect(default.secondary).to.equal("weapon_pistol")
                expect(default.melee).to.equal("weapon_crowbar")
                expect(loadout().Validate(fakePlayer(), default)).to.beTrue()
            end
        },
        {
            name = "Spawn hook: outside LIVE the base gamemode keeps the loadout (hook answers nil, player untouched)",
            func = function()
                expect(match().GetPhase()).to.equal("LOBBY")
                local touched = false
                local ply = setmetatable({}, { __index = function() touched = true end })
                expect(loadout()._OnPlayerLoadout(ply --[[@as Player]])).to.beNil()
                expect(touched).to.beFalse()
                expect(must(module()._EngineHooks).PlayerLoadout).to.exist()
            end
        },
        {
            name = "In-game smoke: the host gets the default loadout on spawn in a LIVE match",
            async = true,
            timeout = 15,
            func = function()
                ---@type table<string, string>
                local saved = {}
                for _, name in ipairs(phaseConVars) do saved[name] = must(GetConVar(name)):GetString() end
                local function restore()
                    for name, value in pairs(saved) do must(GetConVar(name)):SetString(value) end
                end
                must(GetConVar("pw_prematch_timeout")):SetString("0")
                must(GetConVar("pw_countdown")):SetString("0")
                must(GetConVar("pw_postmatch_time")):SetString("0.5")
                must(GetConVar("pw_aftermatch")):SetString("lobby")
                expect(match().GetPhase()).to.equal("LOBBY")
                local tdm = must(PW.Modes.Get("tdm"))
                expect(match().Start(tdm)).to.beTrue()
                local function fail(message)
                    restore()
                    if match().GetPhase() ~= "LOBBY" then match().Abort("loadout smoke: " .. message) end
                    error(message, 0)
                end
                local function waitFor(phase, deadline, after)
                    if match().GetPhase() == phase then return after() end
                    if CurTime() > deadline then
                        fail("phase " .. phase .. " not reached, still " .. match().GetPhase())
                    end
                    timer.Simple(0.1, function() waitFor(phase, deadline, after) end)
                end
                waitFor("LIVE", CurTime() + 5, function()
                    timer.Simple(0.5, function()
                        local ply = must(player.GetHumans()[1])
                        local default = loadout().Default()
                        ---@type string[]
                        local held = {}
                        for _, wep in ipairs(ply:GetWeapons()) do held[#held + 1] = wep:GetClass() end
                        table.sort(held)
                        local wanted = { default.primary --[[@as string]], default.secondary --[[@as string]],
                            default.melee --[[@as string]] }
                        -- T-11.4: the equipment slots add their grenade SWEPs (05-loadout.md d.11 revision).
                        local equipment = must(PW.Equipment)
                        for _, slot in ipairs(equipment.Slots) do
                            local class = equipment._ItemWeapon(default[slot] --[[@as string?]])
                            if class ~= nil then wanted[#wanted + 1] = class end
                        end
                        table.sort(wanted)
                        if table.concat(held, ",") ~= table.concat(wanted, ",") then
                            return fail("host holds " .. table.concat(held, ","))
                        end
                        local smg = must(ply:GetWeapon("weapon_smg1"))
                        if smg:GetPrimaryAmmoType() < 0 or ply:GetAmmoCount(smg:GetPrimaryAmmoType()) <= 0 then
                            return fail("smg1 has no reserve ammo")
                        end
                        PW._MatchRules.teamKills[1] = tdm:Setting("scorelimit")
                        waitFor("LOBBY", CurTime() + 5, function()
                            restore()
                            done()
                        end)
                    end)
                end)
            end
        }
    }
}
