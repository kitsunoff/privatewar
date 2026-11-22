local cvarName = "arc_medshot_replacevial"
local missingLogged = false

---@return table<string, any>
local function integration()
    return assert(rawget(PW, "StimsArctic"), "Private War Arctic integration is not mounted")
end

---@return boolean
local function missingArctic()
    if GetConVar(cvarName) ~= nil then return false end
    if not missingLogged then
        missingLogged = true
        print("[PW] Arctic stim session case SKIPPED: installed Arctic vial-replacement ConVar is absent")
    end
    return true
end

---@param id string
---@param owner Player
---@param overrides table<string, number>
---@return PW.Instance
local function activate(id, owner, overrides)
    local base = assert(assert(PW.Registries).equipment.Get(id))
    local def = table.Copy(base) --[[@as table<string, any>]]
    rawset(def, "IsValid", nil) -- keep test overrides away from the real registry definition
    for field, value in pairs(overrides) do def[field] = value end
    local inst = PW.Instance(def, owner)
    return inst
end

return {
    groupName = "PW optional Arctic stim animation integration",
    afterEach = function(state)
        if state.heal ~= nil then state.heal:Remove() end
        if state.speed ~= nil then state.speed:Remove() end
        if state.restoreSession ~= nil then state.restoreSession() end
    end,
    cases = {
        {
            name = "PickBackend prefers GCAL, falls back to VManip, nil when the animation is missing",
            func = function()
                local backend = integration()._PickBackend
                expect(backend(true, true, true, true)).to.equal("gcal")
                expect(backend(true, true, false, true)).to.equal("vmanip")
                expect(backend(false, true, false, true)).to.equal("vmanip")
                expect(backend(true, true, false, false)).to.beNil()
                expect(backend(false, false, true, true)).to.beNil()
            end
        },
        {
            name = "AnimFor returns the table entry or nil",
            func = function()
                local lib = integration()
                expect(lib._AnimFor("stim_heal", lib.Anims)).to.equal("arc_vm_medshot_inject")
                expect(lib._AnimFor("stim_speed", lib.Anims)).to.equal("arc_vm_medshot_inject")
                expect(lib._AnimFor("stim_armor", lib.Anims)).to.beNil()
                expect(lib._AnimFor("custom", { custom = "example" })).to.equal("example")
                expect(lib.Anims.stim_heal.skin).to.equal(0)
                expect(lib.Anims.stim_speed.skin).to.equal(1)
            end
        },
        {
            name = "ShouldSwap only when the ConVar exists and is not 0",
            func = function()
                local swap = integration()._ShouldSwap
                expect(swap(nil)).to.beFalse()
                expect(swap("0")).to.beFalse()
                expect(swap("1")).to.beTrue()
            end
        },
        {
            name = "Missing Arctic addon: integration does nothing and core stims still heal and boost",
            func = function(state)
                local processed = 0
                ---@type table<string, number>
                local marks = {}
                local ownerState = { hp = 40, max = 100, walk = 200, run = 400 }
                local owner = {
                    IsValid = function() return true end, IsPlayer = function() return true end,
                    IsBot = function() return true end, Alive = function() return true end,
                    Health = function() return ownerState.hp end, GetMaxHealth = function() return ownerState.max end,
                    GetWalkSpeed = function() return ownerState.walk end,
                    GetRunSpeed = function() return ownerState.run end,
                    SetHealth = function(_, n) ownerState.hp = n end,
                    SetMaxHealth = function(_, n) ownerState.max = n end,
                    SetWalkSpeed = function(_, n) ownerState.walk = n end,
                    SetRunSpeed = function(_, n) ownerState.run = n end,
                    EmitSound = function() processed = processed + 1 end, ViewPunch = function() end,
                    GetNW2Float = function(_, key, default) return marks[key] or default end,
                    SetNW2Float = function(_, key, value) marks[key --[[@as string]]] = value --[[@as number]] end
                } --[[@as Player]]
                local clientModule = { IsValid = function() return true end }
                local env = setmetatable({
                    MODULE = clientModule, PW = { API = 1, StimsArctic = integration() },
                    LocalPlayer = function() return owner end
                }, { __index = _G })
                rawset(env, "_G", env)
                setfenv(assert(CompileFile("privatewar/modules/stims_arctic/cl_init.lua")), env)()
                local notify = assert(rawget(clientModule, "PW_StimInjected"))
                notify(clientModule, "stim_heal")
                notify(clientModule, "stim_speed")
                expect(processed).to.equal(0)
                local storedMode = PW.ActiveMode
                PW.ActiveMode = nil
                local ok, reason = pcall(function()
                    state.heal = activate("stim_heal", owner, { UseTime = 0, Time = 0 })
                    state.speed = activate("stim_speed", owner, { UseTime = 0 })
                    assert(PW.Call(state.heal, "OnUse", owner) == true, "core heal refused")
                    assert(PW.Call(state.speed, "OnUse", owner) == true, "core speed refused")
                end)
                PW.ActiveMode = storedMode
                assert(ok, reason)
                expect({ ownerState.hp, ownerState.walk, ownerState.run, processed }).to.deepEqual({ 100, 240, 480, 2 })
            end
        },
        {
            name = "With Arctic installed: vial replacement is off during the session and restored on shutdown",
            skip = missingArctic,
            func = function(state)
                local cvar = assert(GetConVar(cvarName))
                local module = assert(PW.Modules.Get("stims_arctic"), "Private War Arctic integration is not mounted")
                local start = assert(hook.GetTable().InitPostEntity[module])
                local stop = assert(hook.GetTable().ShutDown["PW.StimsArctic.Vials"])
                expect(cvar:GetString()).to.equal("0")
                stop()
                local original = cvar:GetString()
                state.restoreSession = function()
                    cvar:SetString(original)
                    start(module)
                end
                cvar:SetString("1")
                start(module)
                expect(cvar:GetString()).to.equal("0")
                stop()
                expect(cvar:GetString()).to.equal("1")
            end
        }
    }
}
