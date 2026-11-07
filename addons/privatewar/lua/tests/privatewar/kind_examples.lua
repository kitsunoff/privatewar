-- T-1.18 kind fixtures (TASKS.md, "Mandatory test cases" T-1.18; 01-extensibility.md d.8, d.15, d.16). One minimal
-- valid entity per built-in kind (kinds, modules, modes, weapons) registers from lua/privatewar_fixtures/examples/;
-- one invalid variant per kind from lua/privatewar_fixtures/examples_invalid/ is rejected with a readable error.
-- The examples double as documentation for addon authors. modes and weapons are declared by the gamemode's own
-- lua/privatewar/kinds/ files, so the loader reads those real declarations (an overlay of the fixture root's
-- kinds/ folder) instead of copies that could drift.

local examplesRoot = "privatewar_fixtures/examples"
local invalidRoot = "privatewar_fixtures/examples_invalid"
local declaredKinds = { "modes", "weapons", "weapon_adapters", "score_events" }

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---The engine file system, with the gamemode's real modes and weapons declarations shown in root/kinds/.
---Fixture files are never sent to clients.
---@param root string
---@return PW.LoaderFs
local function withDeclaredKinds(root)
    local engine = PW.Loader._EngineFs
    local kindsDir = root .. "/kinds"
    ---@param path string
    ---@return string
    local function realPath(path)
        local id = string.match(path, "^" .. string.PatternSafe(kindsDir) .. "/([%w_]+)%.lua$")
        if id ~= nil and table.HasValue(declaredKinds, id) then return "privatewar/kinds/" .. id .. ".lua" end
        return path
    end
    return {
        find = function(pattern)
            local files, dirs = engine.find(pattern)
            if pattern == kindsDir .. "/*" then
                for _, id in ipairs(declaredKinds) do
                    if not table.HasValue(files, id .. ".lua") then files[#files + 1] = id .. ".lua" end
                end
            end
            return files, dirs
        end,
        exists = function(path) return engine.exists(realPath(path)) end,
        run = function(path) return engine.run(realPath(path)) end,
        send = function() end
    }
end

---Loads a fixture root with a capturing logger; afterEach releases its registries.
---@param state table<string, any>
---@param root string
---@return PW.LoadContext context, string[] logged
local function load(state, root)
    ---@type string[]
    local logged = {}
    local context = PW.Loader.LoadRoot(root, {
        fs = withDeclaredKinds(root),
        log = function(message) logged[#logged + 1] = message end
    })
    local registries = state.registries --[[@as PW.Registry[] ]]
    for _, registry in pairs(context.registries) do registries[#registries + 1] = registry end
    return context, logged
end

---Logged lines that contain every one of the texts.
---@param logged string[]
---@param ... string
---@return integer
local function countLines(logged, ...)
    local texts = { ... }
    local count = 0
    for _, line in ipairs(logged) do
        local all = true
        for _, text in ipairs(texts) do
            if not string.find(line, text, 1, true) then all = false end
        end
        if all then count = count + 1 end
    end
    return count
end

return {
    groupName = "PW kind examples",
    beforeEach = function(state)
        state.registries = {}
    end,
    afterEach = function(state)
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
    end,
    cases = {
        {
            name = "The examples root loads without a single log line",
            func = function(state)
                local _, logged = load(state, examplesRoot)
                expect(table.concat(logged, "\n")).to.equal("")
            end
        },
        {
            name = "kinds: the example kind registers and gets its own registry",
            func = function(state)
                local context = load(state, examplesRoot)
                local kind = must(context.registries.kinds.Get("trinkets")) --[[@as PW.KindDef]]
                expect(kind.Folder).to.equal("trinkets")
                expect(kind.Global).to.equal("TRINKET")
                expect(context.registries.trinkets).to.exist()
            end
        },
        {
            name = "modules: the example module registers",
            func = function(state)
                local context = load(state, examplesRoot)
                local module = must(context.registries.modules.Get("hello"))
                expect(module.Name).to.equal("Hello")
                expect(module.PW_MatchStart).to.beA("function")
            end
        },
        {
            name = "modes: the example mode registers against the real modes kind",
            func = function(state)
                local context = load(state, examplesRoot)
                local mode = must(must(context.registries.modes).Get("example_tdm"))
                expect(mode.Name).to.equal("Example TDM")
                expect(mode.Teams).to.equal(2)
                expect(must(mode.Settings).timelimit.default).to.equal(600)
            end
        },
        {
            name = "weapons: the example weapon registers against the real weapons kind",
            func = function(state)
                local context = load(state, examplesRoot)
                local weapon = must(must(context.registries.weapons).Get("weapon_smg1"))
                expect(weapon.Category).to.equal("smg")
                expect(weapon.Name).to.equal("SMG")
            end
        },
        {
            name = "weapon_adapters: the example adapters register, the child inherits the required methods by Base",
            func = function(state)
                local context = load(state, examplesRoot)
                local registry = must(context.registries.weapon_adapters)
                local adapter = must(registry.Get("example_adapter"))
                expect(adapter.Priority).to.equal(10)
                local child = must(registry.Get("example_child"))
                expect(child.Priority).to.equal(20)
                expect(child.Claims).to.beA("function")
                expect(child.ListWeapons).to.beA("function")
            end
        },
        {
            name = "weapon_adapters: an adapter without Claims is rejected with a readable error",
            func = function(state)
                local context, logged = load(state, invalidRoot)
                expect(must(context.registries.weapon_adapters).Get("no_claims")).to.beNil()
                expect(countLines(logged, "weapon_adapters \"no_claims\"", "missing required field Claims (function)"))
                    .to.equal(1)
            end
        },
        {
            name = "score_events: the example event registers against the real score_events kind",
            func = function(state)
                local context = load(state, examplesRoot)
                local event = must(must(context.registries.score_events).Get("example_bonus"))
                expect(event.Points).to.equal(25)
                expect(event.XP).to.equal(40)
                expect(event.Medal).to.beTrue()
            end
        },
        {
            name = "kinds: a declaration without Global is rejected with a readable error",
            func = function(state)
                local context, logged = load(state, invalidRoot)
                expect(context.registries.kinds.Get("no_global")).to.beNil()
                expect(countLines(logged, "kinds \"no_global\"", "missing required field Global (string)"))
                    .to.equal(1)
            end
        },
        {
            name = "modules: a module that errors while loading is rejected with the error text",
            func = function(state)
                local context, logged = load(state, invalidRoot)
                expect(context.registries.modules.Get("broken")).to.beNil()
                expect(countLines(logged, "modules \"broken\"", "example: this module fails while loading"))
                    .to.equal(1)
            end
        },
        {
            name = "modes: a mode with a mistyped Teams is rejected with a readable error",
            func = function(state)
                local context, logged = load(state, invalidRoot)
                expect(must(context.registries.modes).Get("teams_string")).to.beNil()
                expect(countLines(logged, "modes \"teams_string\"", "field Teams must be number, got string"))
                    .to.equal(1)
            end
        },
        {
            name = "weapons: a file whose name is not a valid id is rejected with a readable error",
            func = function(state)
                local context, logged = load(state, invalidRoot)
                expect(#must(context.registries.weapons).GetList()).to.equal(0)
                expect(countLines(logged, "weapons (", "invalid id \"weapon-smg1.lua\"",
                    "use lowercase letters, digits and _")).to.equal(1)
            end
        },
        {
            name = "score_events: an event with a mistyped Points is rejected with a readable error",
            func = function(state)
                local context, logged = load(state, invalidRoot)
                expect(must(context.registries.score_events).Get("points_string")).to.beNil()
                expect(countLines(logged, "score_events \"points_string\"", "field Points must be number, got string"))
                    .to.equal(1)
            end
        }
    }
}
