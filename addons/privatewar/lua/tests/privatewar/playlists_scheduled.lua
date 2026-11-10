-- Approved Lua playlist contract. No engine run is claimed by adding these cases.
local function lib()
    return assert(PW.Playlist)
end

---@param state table<string, any>
---@param entries table<string, any>[]
local function install(state, entries)
    state.now, state.phase, state.active, state.calls = 1000, "LOBBY", "", 0
    state.fits, state.accept, state.invalid, state.starts = true, true, false, 0
    state.entries, state.logs = entries, {}
    PW._Playlist = assert(lib()._NewStore)({
        luaEntries = function() return state.entries end,
        facts = function() return {} end,
        time = function() return state.now end,
        phase = function() return state.phase end,
        getActive = function() return state.active end,
        setActive = function(id) state.active = id end,
        log = function(text)
            local logs = state.logs --[[@as string[] ]]
            logs[#logs + 1] = text
        end,
        fits = function() return state.fits ~= false end,
        start = function(mode, map)
            lib()._AcceptStart(mode, map)
            state.starts = (state.starts or 0) + 1
            return state.accept ~= false
        end,
        broadcast = function() end,
        setSetting = function() return true end
    })
end

---@param state table<string, any>
local function entry(state)
    return { ClassName = "event", Name = "Event", Modes = { tdm = 1 }, Maps = { "gm_a" },
        IsActive = function(_, now)
            state.calls = state.calls + 1
            if state.invalid then error("bad predicate") end
            return now < 1100, now < 1100 and 1100 or nil
        end }
end

---@param state PW.PlaylistListState
---@param mutate? fun(tokens: any[])
---@return PW.PlaylistListState?
local function wire(state, mutate)
    ---@type any[]
    local tokens = {}
    local function write(value) tokens[#tokens + 1] = value end
    lib()._Encode(state, { uint = write, number = write, string = write, bool = write })
    if mutate ~= nil then mutate(tokens) end
    local at = 0
    local function read() at = at + 1 return tokens[at] end
    return lib()._Decode({ uint = read, number = read, string = read, bool = read })
end

return {
    groupName = "PW scheduled playlists",
    beforeEach = function(state) state.previous = PW._Playlist end,
    afterEach = function(state) PW._Playlist = state.previous end,
    cases = {
        {
            name = "Startup resolvers run once in Modes Maps Settings order and hold copied session data",
            func = function(state)
                ---@type string[]
                local order = {}
                local modes = { tdm = 1 }
                install(state, { { ClassName = "dynamic", Name = "Dynamic",
                    Modes = function(self)
                        ---@cast self table<string, any>
                        order[#order + 1] = "Modes" expect(self.Name).to.equal("Dynamic") return modes
                    end,
                    Maps = function() order[#order + 1] = "Maps" return { "gm_a" } end,
                    Settings = function() order[#order + 1] = "Settings" return nil end } })
                local first = assert(lib().GetList)()
                modes.tdm = 999
                expect(assert(lib().GetList)()[1].Modes.tdm).to.equal(1)
                expect(first[1].Settings).to.deepEqual({})
                expect(order).to.deepEqual({ "Modes", "Maps", "Settings" })
            end
        },
        {
            name = "Resolver errors and invalid outputs reject only that entry with a readable log",
            func = function(state)
                install(state, {
                    { ClassName = "bad", Name = "Bad", Modes = function() error("resolver failed") end },
                    { ClassName = "wrong", Name = "Wrong", Modes = function() return false end },
                    { ClassName = "good", Name = "Good", Modes = { tdm = 1 } }
                })
                local list = assert(lib().GetList)()
                expect(#list).to.equal(1)
                expect(list[1].id).to.equal("good")
                expect(#state.logs).to.equal(2)
            end
        },
        {
            name = "Startup admission bounds snapshots and later enablement never reruns a resolver",
            func = function(state)
                install(state, {})
                local entries = state.entries --[[@as table<string, any>[] ]]
                for index = 1, lib()._MaxEntries + 1 do
                    entries[index] = { ClassName = string.format("entry_%03d", index),
                        Name = string.format("Playlist %03d", index), Modes = { tdm = 1 } }
                end
                expect(#assert(lib().GetList)()).to.equal(lib()._MaxEntries)
                expect(#state.logs).to.equal(1)
                install(state, {})
                local count, enabled = 0, false
                local definition = { ClassName = "dynamic", Name = "Dynamic", Modes = function()
                    count = count + 1 return { tdm = 1 }
                end }
                PW._Playlist.allLuaEntries = function() return { definition } end
                PW._Playlist.luaEntries = function() return enabled and { definition } or {} end
                expect(#assert(lib().GetList)()).to.equal(0)
                enabled = true
                expect(#assert(lib().GetList)()).to.equal(1)
                expect(count).to.equal(1)
            end
        },
        {
            name = "Absent predicate is always active and invalid boundaries never invalidate a boolean",
            func = function()
                expect(lib()._Evaluate({}, 1000)).to.deepEqual({ active = true, valid = true })
                for _, boundary in ipairs({ 0, 1000, 0 / 0, math.huge, -math.huge, "later" }) do
                    local result = lib()._Evaluate({ IsActive = function() return true, boundary end }, 1000)
                    expect(result).to.deepEqual({ active = true, valid = true })
                end
                expect(lib()._Evaluate({ IsActive = function() return false, 2000 end }, 1000))
                    .to.deepEqual({ active = false, valid = true, nextChange = 2000 })
                expect(lib()._Evaluate({ IsActive = function() return 1 end }, 1000).valid).to.beFalse()
            end
        },
        {
            name = "UTC samples handle startup forward and backward jumps without replay and isolate predicate errors",
            func = function(state)
                install(state, {})
                state.entries = { entry(state), { ClassName = "always", Name = "Always", Modes = { tdm = 1 } } }
                assert(lib().RefreshAvailability)(1000)
                expect(assert(assert(lib().GetAvailability)("event")).active).to.beTrue()
                assert(lib().RefreshAvailability)(5000)
                expect(assert(assert(lib().GetAvailability)("event")).active).to.beFalse()
                assert(lib().RefreshAvailability)(1000)
                expect(state.calls).to.equal(3)
                state.invalid = true
                assert(lib().RefreshAvailability)(1001)
                expect(assert(assert(lib().GetAvailability)("event")).valid).to.beFalse()
                expect(assert(assert(lib().GetAvailability)("always")).active).to.beTrue()
                expect(#state.logs > 0).to.beTrue()
            end
        },
        {
            name = "Polling covers unknown boundaries within 60 seconds and never evaluates during any match phase",
            func = function(state)
                install(state, {}) state.entries = { entry(state) }
                lib()._Poll()
                expect(state.calls).to.equal(1)
                state.now = 1060 lib()._Poll()
                expect(state.calls).to.equal(2)
                for _, phase in ipairs({ "PREMATCH", "LIVE", "POSTMATCH" }) do
                    state.phase, state.now = phase, state.now + 60
                    lib()._Poll() assert(lib().RefreshAvailability)(state.now)
                end
                expect(state.calls).to.equal(2)
                state.phase, state.now = "VOTE", 1200 lib()._Poll()
                expect(state.calls).to.equal(3)
                state.now = 1260 lib()._Poll()
                expect(state.calls).to.equal(4)
            end
        },
        {
            name = "Selected expiry grants exactly one start and rejected preflight preserves the grant",
            func = function(state)
                install(state, {}) state.entries = { entry(state) }
                expect(assert(lib().SetActive)("event")).to.beTrue()
                state.now = 1100 assert(lib().RefreshAvailability)(state.now)
                expect(assert(lib().GetSelection)()).to.deepEqual({ id = "event", retained = true, canStart = true })
                state.fits = false
                expect(assert(lib().Start)("event")).to.beFalse()
                expect(assert(lib().GetSelection)().canStart).to.beTrue()
                state.fits = true
                expect(assert(lib().Start)("event")).to.beTrue()
                expect(assert(lib().GetSelection)().canStart).to.beFalse()
                expect(assert(lib().SetActive)("event")).to.beFalse()
                expect(assert(lib().Start)("event")).to.beFalse()
                expect(state.starts).to.equal(1)
                state.now = 1000 assert(lib().RefreshAvailability)(state.now)
                state.now = 1100 assert(lib().RefreshAvailability)(state.now)
                expect(assert(lib().GetSelection)().canStart).to.beFalse()
            end
        },
        {
            name = "Replacement restart and invalid predicate cannot replenish or bypass retained entitlement",
            func = function(state)
                install(state, {}) state.entries = { entry(state) }
                assert(lib().SetActive)("event")
                state.now = 1100 assert(lib().RefreshAvailability)(state.now)
                state.invalid = true assert(lib().RefreshAvailability)(state.now)
                expect(assert(lib().GetSelection)().canStart).to.beFalse()
                expect(assert(lib().Start)("event")).to.beFalse()
                state.invalid = false
                assert(lib().SetActive)("")
                expect(assert(lib().SetActive)("event")).to.beFalse()
                install(state, {}) state.entries = { entry(state) } state.active, state.now = "event", 1100
                assert(lib().RefreshAvailability)(state.now)
                expect(assert(lib().GetSelection)().canStart).to.beFalse()
            end
        },
        {
            name = "Failed accepted activation does not refund an expired start",
            func = function(state)
                install(state, {}) state.entries = { entry(state) }
                assert(lib().SetActive)("event")
                state.now = 1100 state.accept = false
                expect(assert(lib().Start)("event")).to.beFalse()
                expect(assert(lib().GetSelection)().canStart).to.beFalse()
            end
        },
        {
            name = "Concurrent active retained and inclusive 48-hour upcoming rows precede Custom",
            func = function()
                local state = { serial = 1, sampledAt = 1000, active = "expired", retained = true,
                    canStart = true, canPick = true, list = {
                        { id = "active", name = "Active", summary = "", fill = 0,
                            active = true, valid = true, nextChange = 1060 },
                        { id = "other", name = "Other", summary = "", fill = 0, active = true, valid = true },
                        { id = "expired", name = "Expired", summary = "", fill = 0, active = false, valid = true },
                        { id = "soon", name = "Soon", summary = "", fill = 0,
                            active = false, valid = true, nextChange = 173800 },
                        { id = "late", name = "Late", summary = "", fill = 0,
                            active = false, valid = true, nextChange = 173801 },
                        { id = "unknown", name = "Unknown", summary = "", fill = 0, active = false, valid = true }
                    } }
                local model = lib()._Items(state, 12)
                expect(#model.items).to.equal(5)
                expect(model.items[4].id).to.equal("soon")
                expect(model.items[5].id).to.equal(lib().CustomRow)
                expect(string.find(model.items[1].label, "ends in 1m", 1, true)).to.exist()
                state.list, state.active = {}, ""
                expect(lib()._Items(state, 12).items).to.deepEqual({ { id = lib().CustomRow,
                    label = "Custom (pick mode and map)" } })
            end
        },
        {
            name = "Snapshots round-trip late-join state and reject stale versions malformed ids and boundaries",
            func = function()
                local state = { serial = 4, sampledAt = 1000, active = "event", retained = true,
                    canStart = true, canPick = false, list = {
                        { id = "event", name = "Event", summary = "tdm", fill = 12,
                            active = false, valid = true, nextChange = 2000 }
                    } }
                expect(wire(state)).to.deepEqual(state)
                expect(lib()._Newer(nil, state)).to.beTrue()
                expect(lib()._Newer(state, state)).to.beFalse()
                local newer = table.Copy(state) newer.serial = 5
                expect(lib()._Newer(state, newer)).to.beTrue()
                expect(lib()._Newer(newer, state)).to.beFalse()
                expect(wire(state, function(tokens) tokens[1] = 99 end)).to.beNil()
                expect(wire(state, function(tokens) tokens[4] = 129 end)).to.beNil()
                expect(wire(state, function(tokens) tokens[5] = "../evil" end)).to.beNil()
                expect(wire(state, function(tokens) tokens[12] = 999 end)).to.beNil()
            end
        },
        {
            name = "Pending continuation binds accepted playlist mode and map without predicates",
            func = function(state)
                install(state, {}) state.entries = { entry(state) }
                assert(lib().SetActive)("event")
                state.now = 1100
                PW._Playlist.start = function(mode, map)
                    lib()._AcceptStart(mode, map)
                    expect(lib()._PendingStart(mode, map)).to.equal("event")
                    expect(lib()._PendingStart(mode, "other")).to.beNil()
                    return true
                end
                expect(assert(lib().Start)("event")).to.beTrue()
                local calls = state.calls --[[@as number]]
                state.phase = "PREMATCH"
                expect(lib()._RestoreStart("event")).to.beTrue()
                expect(state.calls).to.equal(calls)
                expect(lib()._RestoreStart("missing")).to.beFalse()
            end
        },
        {
            name = "Completion samples freshly and an expired playlist cannot continue or launch a vote result",
            func = function(state)
                install(state, {}) state.entries = { entry(state) }
                assert(lib().SetActive)("event")
                state.now, state.phase = 1200, "POSTMATCH"
                local calls = state.calls --[[@as number]]
                expect(lib()._Complete()).to.beFalse()
                expect(state.calls).to.equal(calls + 1)
                state.phase = "VOTE"
                expect(lib()._RotationAllowed(true)).to.beFalse()
            end
        },
        {
            name = "Playlist JSON APIs are absent and listing never accesses playlist storage",
            func = function(state)
                install(state, { { ClassName = "lua", Name = "Lua", Modes = { tdm = 1 } } })
                for _, name in ipairs({ "FromJson", "ToJson", "FileId", "LoadDir", "Save", "Version", "DataDir" }) do
                    expect(rawget(lib(), name)).to.beNil()
                end
                local reads, writes, finds, deletes = 0, 0, 0, 0
                stub(file, "Read").with(function() reads = reads + 1 end)
                stub(file, "Write").with(function() writes = writes + 1 end)
                stub(file, "Find").with(function() finds = finds + 1 return {} end)
                stub(file, "Delete").with(function() deletes = deletes + 1 end)
                local list = assert(lib().GetList)()
                expect(#list).to.equal(1)
                expect({ reads, writes, finds, deletes }).to.deepEqual({ 0, 0, 0, 0 })
            end
        }
    }
}
