-- T-1.2 registries and T-1.3 PW_PreRegister (TASKS.md, "Mandatory test cases"). Pure: no engine state.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---Creates a registry with a capturing logger.
---@param preRegister? PW.PreRegisterFn
---@return PW.Registry registry, string[] logged
local function newRegistry(preRegister)
    ---@type string[]
    local logged = {}
    local registry = PW.Registry.New("things", {
        log = function(message) logged[#logged + 1] = message end,
        preRegister = preRegister
    })
    return registry, logged
end

return {
    groupName = "PW registry",
    cases = {
        {
            name = "Base resolves when the child registers before the parent",
            func = function()
                local reg = newRegistry()
                reg.Register({ Name = "Child" }, "child")
                reg.Register({ Name = "Parent", Speed = 5 }, "parent")
                must(reg.GetStored("child")).Base = "parent"
                reg.ResolveAll()
                expect(must(reg.Get("child")).Speed).to.equal(5)
                expect(must(reg.Get("child")).Name).to.equal("Child")
                expect(must(reg.Get("child")).BaseClass).to.equal(reg.Get("parent"))
            end
        },
        {
            name = "Base resolves when the parent registers before the child",
            func = function()
                local reg = newRegistry()
                reg.Register({ Speed = 5 }, "parent")
                reg.Register({ Base = "parent" }, "child")
                reg.ResolveAll()
                expect(must(reg.Get("child")).Speed).to.equal(5)
            end
        },
        {
            name = "Multi-level Base chain inherits from every level",
            func = function()
                local reg = newRegistry()
                reg.Register({ Base = "b", C = 3 }, "c")
                reg.Register({ Base = "a", B = 2 }, "b")
                reg.Register({ A = 1, B = 0 }, "a")
                reg.ResolveAll()
                local c = must(reg.Get("c"))
                expect(c.A).to.equal(1)
                expect(c.B).to.equal(2)
                expect(c.C).to.equal(3)
            end
        },
        {
            name = "Missing base gives a clear error and skips only that entity",
            func = function()
                local reg, logged = newRegistry()
                reg.Register({ Base = "nope" }, "orphan")
                reg.Register({}, "fine")
                reg.ResolveAll()
                expect(reg.Get("orphan")).to.beNil()
                expect(reg.Get("fine")).to.exist()
                expect(#logged).to.equal(1)
                expect(string.find(logged[1], "orphan", 1, true)).to.exist()
                expect(string.find(logged[1], "nope", 1, true)).to.exist()
            end
        },
        {
            name = "Base cycle is reported, not a stack overflow",
            func = function()
                local reg, logged = newRegistry()
                reg.Register({ Base = "y" }, "x")
                reg.Register({ Base = "x" }, "y")
                reg.ResolveAll()
                expect(reg.Get("x")).to.beNil()
                expect(reg.Get("y")).to.beNil()
                expect(#logged > 0).to.beTrue()
            end
        },
        {
            name = "Abstract entities are absent from GetList but usable as a base",
            func = function()
                local reg = newRegistry()
                reg.Register({ Abstract = true, Rounds = 4 }, "round_base")
                reg.Register({ Base = "round_base" }, "snd")
                reg.ResolveAll()
                local list = reg.GetList()
                expect(#list).to.equal(1)
                expect(list[1].ClassName).to.equal("snd")
                expect(list[1].Rounds).to.equal(4)
                expect(list[1].Abstract).to.beNil()
                expect(reg.Get("round_base")).to.exist()
            end
        },
        {
            name = "Re-registering the same id replaces the entry",
            func = function()
                local reg = newRegistry()
                reg.Register({ Name = "Old", Extra = 1 }, "thing")
                reg.ResolveAll()
                reg.Register({ Name = "New" }, "thing")
                expect(must(reg.Get("thing")).Name).to.equal("New")
                expect(must(reg.Get("thing")).Extra).to.beNil()
            end
        },
        {
            name = "Late registration resolves Base immediately",
            func = function()
                local reg = newRegistry()
                reg.Register({ Speed = 7 }, "parent")
                reg.ResolveAll()
                reg.Register({ Base = "parent" }, "late")
                expect(must(reg.Get("late")).Speed).to.equal(7)
            end
        },
        {
            name = "A late registration of an unrelated entity keeps the other resolved entities valid",
            func = function()
                local reg = newRegistry()
                reg.Register({ Speed = 7 }, "parent")
                reg.Register({ Base = "parent" }, "child")
                reg.ResolveAll()
                local parent = must(reg.Get("parent"))
                local child = must(reg.Get("child"))
                reg.Register({ Speed = 1 }, "unrelated")
                expect(reg.Get("parent")).to.equal(parent)
                expect(reg.Get("child")).to.equal(child)
                expect(must(parent.IsValid)(parent)).to.beTrue()
                expect(must(child.IsValid)(child)).to.beTrue()
            end
        },
        {
            name = "A late re-registration of a base re-resolves the entities that inherit it",
            func = function()
                local reg = newRegistry()
                reg.Register({ Speed = 7 }, "parent")
                reg.Register({ Base = "parent" }, "child")
                reg.Register({ Base = "child" }, "grandchild")
                reg.Register({ Speed = 3 }, "other")
                reg.ResolveAll()
                local grandchild = must(reg.Get("grandchild"))
                local other = must(reg.Get("other"))
                reg.Register({ Speed = 9 }, "parent")
                expect(must(grandchild.IsValid)(grandchild)).to.beFalse()
                expect(must(reg.Get("child")).Speed).to.equal(9)
                expect(must(reg.Get("grandchild")).Speed).to.equal(9)
                expect(reg.Get("other")).to.equal(other)
            end
        },
        {
            name = "A late base resolves the entities that were waiting for it",
            func = function()
                local reg = newRegistry()
                reg.Register({ Base = "parent" }, "child")
                reg.ResolveAll()
                expect(reg.Get("child")).to.beNil()
                reg.Register({ Speed = 4 }, "parent")
                expect(must(reg.Get("child")).Speed).to.equal(4)
            end
        },
        {
            name = "Soft registration fills only missing fields, per nested key, never overwrites",
            func = function()
                local reg = newRegistry()
                reg.Register({ Name = "AK-74", Attachments = { optic_acog = { Unlock = 10 } } }, "ak")
                reg.Register({
                    Name = "Auto name",
                    Category = "ar",
                    Attachments = { optic_acog = { Unlock = 1, Cost = 3 }, grip = { Unlock = 2 } }
                }, "ak", { soft = true })
                reg.ResolveAll()
                local ak = must(reg.Get("ak"))
                expect(ak.Name).to.equal("AK-74")
                expect(ak.Category).to.equal("ar")
                expect(ak.Attachments.optic_acog.Unlock).to.equal(10)
                expect(ak.Attachments.optic_acog.Cost).to.equal(3)
                expect(ak.Attachments.grip.Unlock).to.equal(2)
            end
        },
        {
            name = "Soft registration of a new id registers it",
            func = function()
                local reg = newRegistry()
                reg.Register({ Category = "smg" }, "mp5", { soft = true })
                reg.ResolveAll()
                expect(must(reg.Get("mp5")).Category).to.equal("smg")
            end
        },
        {
            name = "PW_PreRegister returning false vetoes the registration",
            func = function()
                local reg = newRegistry(function(_, id) if id == "banned" then return false end end)
                expect(reg.Register({}, "banned")).to.beFalse()
                expect(reg.Register({}, "allowed")).to.beTrue()
                reg.ResolveAll()
                expect(reg.Get("banned")).to.beNil()
                expect(reg.Get("allowed")).to.exist()
            end
        },
        {
            name = "PW_PreRegister field edits are applied and get the kind name",
            func = function()
                ---@type string?
                local seenKind
                local reg = newRegistry(function(kind, _, tbl)
                    seenKind = kind
                    tbl.Patched = true
                end)
                reg.Register({}, "one")
                reg.ResolveAll()
                expect(must(reg.Get("one")).Patched).to.beTrue()
                expect(seenKind).to.equal("things")
            end
        },
        {
            name = "One PW_PreRegister listener patches every id with a prefix",
            func = function()
                local reg = newRegistry(function(_, id, tbl)
                    if string.StartsWith(id, "arc9_") then tbl.Unlock = 99 end
                end)
                reg.Register({}, "arc9_ak")
                reg.Register({}, "arc9_m4")
                reg.Register({}, "tfa_ak")
                reg.ResolveAll()
                expect(must(reg.Get("arc9_ak")).Unlock).to.equal(99)
                expect(must(reg.Get("arc9_m4")).Unlock).to.equal(99)
                expect(must(reg.Get("tfa_ak")).Unlock).to.beNil()
            end
        },
        {
            name = "PW_PreRegister runs for late registrations",
            func = function()
                local calls = 0
                local reg = newRegistry(function() calls = calls + 1 end)
                reg.ResolveAll()
                reg.Register({}, "late")
                expect(calls).to.equal(1)
            end
        },
        {
            name = "The default preRegister fires the PW_PreRegister hook",
            func = function()
                hook.Add("PW_PreRegister", "PW_Test_Veto", function(kind, id)
                    if kind == "things" and id == "vetoed" then return false end
                end)
                local reg = PW.Registry.New("things", { log = function() end })
                local accepted = reg.Register({}, "vetoed")
                hook.Remove("PW_PreRegister", "PW_Test_Veto")
                expect(accepted).to.beFalse()
            end
        },
        {
            name = "Required fields: a child that inherits them from its Base is accepted",
            func = function()
                ---@type string[]
                local logged = {}
                local reg = PW.Registry.New("things", { log = function(message) logged[#logged + 1] = message end,
                    preRegister = function() end, required = { Name = "string", Teams = "number" } })
                reg.Register({ Abstract = true, Name = "Rounds", Teams = 2 }, "round_base")
                reg.Register({ Base = "round_base", Rounds = 4 }, "sd")
                reg.ResolveAll()
                local sd = must(reg.Get("sd"))
                expect(sd.Name).to.equal("Rounds")
                expect(#reg.GetList()).to.equal(1)
                expect(#logged).to.equal(0)
            end
        },
        {
            name = "Required fields: a child whose chain lacks one is rejected with one line, also when late",
            func = function()
                ---@type string[]
                local logged = {}
                local reg = PW.Registry.New("things", { log = function(message) logged[#logged + 1] = message end,
                    preRegister = function() end, required = { Name = "string", Teams = "number" } })
                local class = { Base = "round_base" }
                reg.Register({ Abstract = true, Teams = 2 }, "round_base")
                reg.Register(class, "sd")
                reg.Register({ Name = "Ok", Teams = "two" }, "typo")
                reg.ResolveAll()
                reg.ResolveAll()
                expect(reg.Get("sd")).to.beNil()
                expect(reg.Get("typo")).to.beNil()
                expect(#reg.GetList()).to.equal(0)
                expect(IsValid(class)).to.beFalse()
                table.sort(logged)
                expect(logged).to.deepEqual({
                    "things \"sd\": missing required field Name (string)",
                    "things \"typo\": field Teams must be number, got string"
                })
                reg.Register({ Base = "round_base" }, "late")
                expect(reg.Get("late")).to.beNil()
                expect(logged[3]).to.equal("things \"late\": missing required field Name (string)")
                reg.Register({ Base = "round_base", Name = "Fixed" }, "late")
                expect(must(reg.Get("late")).Teams).to.equal(2)
                expect(#logged).to.equal(3)
            end
        }
    }
}
