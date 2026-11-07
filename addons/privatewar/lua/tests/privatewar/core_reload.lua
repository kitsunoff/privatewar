-- T-1.15 pw_reload and GM:OnReloaded (TASKS.md, "Mandatory test cases" T-1.15; 01-extensibility.md d.12, d.16;
-- 00-core.md d.7). The server cannot write .lua files (file.Write only writes DATA, with a fixed extension list),
-- so "a file added after load" and "a changed file" are simulated honestly one level down: the loader takes an
-- injectable file system (PW.LoadOptions.fs), and the cases overlay virtual files (compiled with CompileString) on
-- the real fixture tree lua/privatewar_fixtures/reload/. The rescan itself is the real PW.Loader._Rescan that
-- PW.Loader.Boot (and so pw_reload) runs. The command cases swap PW._Reload, so they never reload for real; the
-- LIVE case runs the real Boot on fresh match, settings, enable and call stores and boots again afterwards.

local root = "privatewar_fixtures/reload"
local pingHook = "PW_TestReloadPing"

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.ReloadLib
local function reload()
    return must(PW.Reload)
end

---@return PW.MatchLib
local function match()
    return must(PW.Match)
end

---Runs a virtual file the way the engine runs a real one: compile errors and runtime errors come back as text.
---@param path string
---@param source string
---@return boolean ok
---@return string? err
local function runSource(path, source)
    local fn = CompileString(source, path, false) --[[@as function|string|nil]]
    if not isfunction(fn) then return false, tostring(fn) end
    local ok, err = pcall(fn --[[@as function]])
    if not ok then return false, tostring(err) end
    return true
end

---The engine file system with virtual files on top: path -> Lua source. A virtual file shadows a real one.
---@param virtual table<string, string>
---@return PW.LoaderFs
local function overlayFs(virtual)
    local engine = PW.Loader._EngineFs
    return {
        find = function(pattern)
            local files, dirs = engine.find(pattern)
            local dir = string.match(pattern, "^(.*)/%*$")
            for path in pairs(virtual) do
                local parent, name = string.match(path, "^(.*)/([^/]+)$")
                if parent == dir and not table.HasValue(files, name) then files[#files + 1] = name end
            end
            return files, dirs
        end,
        exists = function(path) return virtual[path] ~= nil or engine.exists(path) end,
        run = function(path)
            local source = virtual[path]
            if source == nil then return engine.run(path) end
            return runSource(path, source)
        end,
        send = function(path)
            if virtual[path] == nil then engine.send(path) end
        end
    }
end

---Keeps every registry a case creates so afterEach releases it.
---@param state table<string, any>
---@param context PW.LoadContext
---@return PW.LoadContext
local function track(state, context)
    local registries = state.registries --[[@as PW.Registry[] ]]
    for _, registry in pairs(context.registries) do registries[#registries + 1] = registry end
    return context
end

---@param state table<string, any>
---@param virtual table<string, string>
---@param previous? table<string, PW.Registry>
---@param active? table[]
---@return PW.LoadContext
local function rescan(state, virtual, previous, active)
    return track(state, PW.Loader._Rescan(previous, {
        root = root, fs = overlayFs(virtual), log = function() end, active = active
    }))
end

---@param context PW.LoadContext
---@return PW.Registry
local function widgets(context)
    return must(context.registries.widgets)
end

---@param entity table
---@return boolean
local function valid(entity)
    return must(entity.IsValid)(entity)
end

---Number of listeners of a hook.
---@param name string
---@return integer
local function listenerCount(name)
    local count = 0
    for _ in pairs(hook.GetTable()[name] or {}) do count = count + 1 end
    return count
end

---Swaps in a reload store that only records what it would do.
---@param state table<string, any>
---@param bootFails? boolean
local function installReloadStore(state, bootFails)
    state.boots = 0
    state.broadcasts = 0
    state.logged = {}
    PW._Reload = reload()._NewStore({
        log = function(message)
            local logged = state.logged --[[@as string[] ]]
            logged[#logged + 1] = message
        end,
        boot = function()
            state.boots = state.boots + 1
            if bootFails then error("boot failed on purpose") end
        end,
        broadcast = function() state.broadcasts = state.broadcasts + 1 end
    })
end

---Fresh match, settings, enable and call stores for a real match on the fixture mode.
---@param state table<string, any>
local function installMatchStores(state)
    state.now = 1000
    PW._Match = match()._NewStore({
        log = function() end,
        clock = function() return state.now end,
        players = function() return {} end,
        settings = function()
            return { prematch = 60, countdown = 10, postmatch = 15, vote = 15, afterMatch = "lobby" }
        end
    })
    PW._Settings = must(PW.Settings)._NewStore()
    PW._Enable = must(PW.Enable)._NewStore({ registries = function() return {} end })
    PW._Call = { log = function() end, failed = setmetatable({}, { __mode = "k" }), profile = {} }
end

---@param state table<string, any>
local function expire(state)
    state.now = PW._Match.endsAt
    match()._Tick()
end

local cases = {
    {
        name = "A new kind file added after load is picked up",
        func = function(state)
            ---@type table<string, string>
            local virtual = {}
            local first = rescan(state, virtual)
            expect(widgets(first).Get("beta")).to.beNil()
            virtual[root .. "/widgets/beta.lua"] = "GADGET.Name = \"Beta\""
            local second = rescan(state, virtual, first.registries)
            expect(must(widgets(second).Get("beta")).Name).to.equal("Beta")
            expect(must(widgets(second).Get("alpha")).Name).to.equal("Alpha")
        end
    },
    {
        name = "A changed file replaces its entry",
        func = function(state)
            ---@type table<string, string>
            local virtual = {}
            local first = rescan(state, virtual)
            local old = must(widgets(first).Get("alpha"))
            expect(old.Name).to.equal("Alpha")
            virtual[root .. "/widgets/alpha.lua"] = "GADGET.Name = \"Alpha v2\""
            local second = rescan(state, virtual, first.registries)
            local new = must(widgets(second).Get("alpha"))
            expect(new.Name).to.equal("Alpha v2")
            expect(new.Think).to.beNil()
            expect(valid(old)).to.beFalse()
            expect(valid(new)).to.beTrue()
        end
    },
    {
        name = "A rescan releases the replaced registries but keeps an active entity valid",
        func = function(state)
            local first = rescan(state, {})
            local active = must(widgets(first).Get("alpha"))
            local pinger = must(must(first.registries.modules).Get("pinger"))
            rescan(state, {}, first.registries, { active })
            expect(valid(active)).to.beTrue()
            expect(valid(pinger)).to.beFalse()
        end
    },
    {
        name = "_KeepFor keeps only active entities of the replaced registries",
        func = function()
            local replaced = PW.Registry.New("pwt_keep", { log = function() end, preRegister = function() end })
            local other = PW.Registry.New("pwt_keep", { log = function() end, preRegister = function() end })
            replaced.Register({}, "one")
            other.Register({}, "two")
            replaced.ResolveAll()
            other.ResolveAll()
            local keep = PW.Loader._KeepFor({ pwt_keep = replaced },
                { must(replaced.Get("one")), must(other.Get("two")), { ClassName = "loose" } })
            expect(must(keep.pwt_keep).one).to.beTrue()
            expect(must(keep.pwt_keep).two).to.beNil()
            expect(table.Count(keep)).to.equal(1)
            expect(table.Count(PW.Loader._KeepFor(nil, { must(replaced.Get("one")) }))).to.equal(0)
            replaced._Release()
            other._Release()
        end
    },
    {
        name = "Repeated reloads leave exactly one subscription per PW_ method",
        func = function(state)
            local context = rescan(state, {})
            for _ = 1, 3 do context = rescan(state, {}, context.registries) end
            expect(listenerCount(pingHook)).to.equal(1)
            local listeners = must(hook.GetTable()[pingHook]) --[[@as table<any, function>]]
            expect(listeners[must(must(context.registries.modules).Get("pinger"))]).to.exist()
        end
    },
    {
        name = "The reload privilege is declared with the superadmin default",
        func = function()
            expect(reload().Privilege).to.equal("pw.reload")
            expect(must(PW._Privileges.defs["pw.reload"]).MinAccess).to.equal("superadmin")
        end
    },
    {
        name = "pw_reload from a player without the privilege is refused: nothing reloads, clients are not told",
        func = function(state)
            installReloadStore(state)
            local bot = must(state.bot) --[[@as Player]]
            expect(bot:IsSuperAdmin()).to.beFalse()
            expect(reload()._Command(bot)).to.beFalse()
            expect(state.boots).to.equal(0)
            expect(state.broadcasts).to.equal(0)
            expect(#state.logged).to.equal(1)
        end
    },
    {
        name = "pw_reload from the server console reloads the server and tells the clients once",
        func = function(state)
            installReloadStore(state)
            expect(reload()._Command(NULL)).to.beTrue()
            expect(state.boots).to.equal(1)
            expect(state.broadcasts).to.equal(1)
        end
    },
    {
        name = "A failing reload is logged and not sent to the clients",
        func = function(state)
            installReloadStore(state, true)
            expect(reload()._Command(NULL)).to.beFalse()
            expect(state.boots).to.equal(1)
            expect(state.broadcasts).to.equal(0)
            expect(string.find(must((state.logged --[[@as string[] ]])[1]), "boot failed on purpose", 1, true))
                .to.exist()
        end
    },
    {
        name = "GM:OnReloaded (auto refresh) reloads the registries without telling the clients",
        func = function(state)
            installReloadStore(state)
            must(GAMEMODE.OnReloaded)(GAMEMODE)
            expect(state.boots).to.equal(1)
            expect(state.broadcasts).to.equal(0)
        end
    },
    {
        name = "The summary counts entities per kind, sorted by kind",
        func = function(state)
            local context = rescan(state, {})
            expect(reload()._Summary(context.registries)).to.equal("kinds 1, modules 1, widgets 1")
        end
    },
    {
        name = "The next match takes the reloaded definition; a mode gone after a reload is not started",
        func = function(state)
            local first = rescan(state, {})
            local old = must(widgets(first).Get("alpha"))
            local second = rescan(state, {}, first.registries, { old })
            local definition = match()._Definition
            local current = must(widgets(second).Get("alpha"))
            expect(definition(current, {})).to.equal(current)
            expect(definition(old, second.registries)).to.equal(current)
            expect(definition(old, first.registries)).to.equal(old)
            local gone = rescan(state, { [root .. "/widgets/alpha.lua"] = "error(\"removed\")" }, second.registries)
            expect(definition(old, gone.registries)).to.beNil()
            local loose = { ClassName = "loose" }
            expect(definition(loose, gone.registries)).to.equal(loose)
        end
    },
    {
        name = "A reload during LIVE keeps PW.ActiveMode and the match snapshots",
        func = function(state)
            local context = rescan(state, {})
            state.replacedReal = true
            PW.Registries = context.registries
            installMatchStores(state)
            local mode = must(widgets(context).Get("alpha")) --[[@as table<string, any>]]
            expect(match().Start(mode)).to.beTrue()
            expect(PW.Setting("alpha.rounds")).to.equal(3)
            expire(state)
            expire(state)
            expect(match().GetPhase()).to.equal("LIVE")
            local settingsSnapshot = PW._Settings.snapshot
            local enableSnapshot = PW._Enable.snapshot
            expect(settingsSnapshot).to.exist()
            expect(enableSnapshot).to.exist()

            PW.Loader.Boot()

            expect(PW.Registries).notTo.equal(context.registries)
            expect(PW.ActiveMode).to.equal(mode)
            expect(valid(mode)).to.beTrue()
            expect(PW._Settings.snapshot).to.equal(settingsSnapshot)
            expect(PW._Enable.snapshot).to.equal(enableSnapshot)
            expect(PW.Setting("alpha.rounds")).to.equal(3)
            ---@type integer
            local thinks = mode.Calls.Think
            match()._Tick()
            expect(mode.Calls.Think).to.equal(thinks + 1)
            match().Abort("reload test finished")
            expect(mode.Calls.Cleanup).to.equal(1)
        end
    }
}

return {
    groupName = "PW reload",
    beforeAll = function(state)
        local bot = player.CreateNextBot("pw_test_reload") --[[@as Player?]]
        state.bot = bot
    end,
    afterAll = function(state)
        local bot = state.bot --[[@as Player?]]
        if bot ~= nil and IsValid(bot) then bot:Kick("PW reload test finished") end
    end,
    beforeEach = function(state)
        state.registries = {}
        state.replacedReal = false
        state.realRegistries = PW.Registries
        state.previousReload = PW._Reload
        state.previousMatch = PW._Match
        state.previousSettings = PW._Settings
        state.previousEnable = PW._Enable
        state.previousCall = PW._Call
        state.previousMode = PW.ActiveMode
    end,
    afterEach = function(state)
        for _, registry in ipairs(state.registries --[[@as PW.Registry[] ]]) do registry._Release() end
        PW._Reload = state.previousReload
        PW._Match = state.previousMatch
        PW._Settings = state.previousSettings
        PW._Enable = state.previousEnable
        PW._Call = state.previousCall
        PW.ActiveMode = state.previousMode
        if state.replacedReal then
            for _, registry in pairs(state.realRegistries --[[@as table<string, PW.Registry>]]) do
                registry._Release()
            end
            PW.Loader.Boot()
        end
    end,
    cases = cases
}
