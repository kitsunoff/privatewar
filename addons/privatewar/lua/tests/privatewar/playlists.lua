-- T-2.6 playlists (TASKS.md, "Mandatory test cases" T-2.6: weighted sampling respects weights over many draws;
-- host-saved JSON loads and validates like Lua playlists; invalid JSON is rejected with a message; 02-modes.md
-- d.1-d.5b; docs/api/modes.md "Playlists"). Pure cases run over plain data with a deterministic RNG. The server
-- cases swap in a playlists store with fakes and a test-only data folder (privatewar_test/playlists), whose files
-- every case removes. Net cases call the receive path (PW.Net._Dispatch) with one pool bot.

local testDir = "privatewar_test/playlists"

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.PlaylistLib
local function lib()
    return must(PW.Playlist)
end

---Park-Miller generator: deterministic numbers in [0, 1).
---@param seed integer
---@return fun(): number
local function seeded(seed)
    local value = seed
    return function()
        value = (value * 16807) % 2147483647
        return value / 2147483647
    end
end

---@param id string
---@param decl PW.SettingDecl
---@return PW.SettingDef
local function def(id, decl)
    local owner, key = string.match(id, "^(.-)%.(.+)$")
    -- A mode's settings must be match settings (core.md "Settings"): the server one is a module's.
    local kind = decl.scope == "server" and "modules" or "modes"
    return must(PW.Settings._CheckDef(owner, kind, key, decl))
end

---Facts of a small fake game: three modes, match settings (one clamped, one enum) and a server setting.
---@return PW.PlaylistFacts
local function facts()
    return {
        modes = { tdm = true, ffa = true, dom = true },
        settings = {
            ["tdm.scorelimit"] = def("tdm.scorelimit", { type = "int", default = 75, min = 10, max = 1000 }),
            ["bots.fill"] = def("bots.fill", { type = "int", default = 12, min = 0, max = 128 }),
            ["bots.difficulty"] = def("bots.difficulty",
                { type = "enum", default = "regular", options = { "recruit", "regular" } }),
            ["pwt.srv"] = def("pwt.srv", { type = "int", default = 1, scope = "server" })
        },
        validate = PW.Settings._Validate
    }
end

---@return table
local function goodPlaylist()
    return {
        Name = "TDM and FFA",
        Modes = { tdm = 2, ffa = 1 },
        Maps = { "gm_construct", "gm_flatgrass" },
        Settings = { ["tdm.scorelimit"] = 100, ["bots.fill"] = 24 }
    }
end

---Invalid playlists: a change to goodPlaylist and a text the message must contain.
---@return { change: fun(p: table<string, any>), word: string }[]
local function badCases()
    return {
        { change = function(p) rawset(p, "Name", nil) end, word = "Name" },
        { change = function(p) p.Name = "" end, word = "Name" },
        { change = function(p) p.Modes = {} end, word = "Modes" },
        { change = function(p) p.Modes = { nope = 1 } end, word = "unknown mode" },
        { change = function(p) p.Modes = { tdm = 0 } end, word = "weight" },
        { change = function(p) p.Modes = { tdm = -2 } end, word = "weight" },
        { change = function(p) p.Modes = { tdm = "heavy" } end, word = "weight" },
        { change = function(p) p.Modes = { "tdm" } end, word = "mode id" },
        { change = function(p) p.Maps = {} end, word = "Maps is empty" },
        { change = function(p) p.Maps = { "../evil" } end, word = "Maps" },
        { change = function(p) p.Settings = { ["tdm.nope"] = 1 } end, word = "unknown setting" },
        { change = function(p) p.Settings = { ["pwt.srv"] = 2 } end, word = "not a match" },
        { change = function(p) p.Settings = { ["bots.difficulty"] = "god" } end, word = "bad value" },
        { change = function(p) p.Settings = { fill = 3 } end, word = "full setting id" }
    }
end

---@param text any
---@param word string
---@return boolean
local function mentions(text, word)
    return string.find(tostring(text), word, 1, true) ~= nil
end

---@param state table<string, any>
---@return string[]
local function logs(state)
    return state.logs --[[@as string[] ]]
end

---@param state table<string, any>
---@return table[]
local function started(state)
    return state.started --[[@as table[] ]]
end

---@param state table<string, any>
---@return table[]
local function applied(state)
    return state.applied --[[@as table[] ]]
end

---@param state table<string, any>
---@return table[]
local function sent(state)
    return state.sent --[[@as table[] ]]
end

---@param state table<string, any>
---@param name string
---@param text string
local function writeFile(state, name, text)
    file.CreateDir(testDir)
    file.Write(testDir .. "/" .. name, text)
    local written = state.written --[[@as string[] ]]
    written[#written + 1] = name
end

---@param state table<string, any>
---@param luaEntries? fun(): table[]
local function installStore(state, luaEntries)
    state.logs, state.started, state.applied, state.sent = {}, {}, {}, {}
    state.active = ""
    PW._Playlist = must(lib()._NewStore)({
        log = function(message) logs(state)[#logs(state) + 1] = message end,
        dir = testDir,
        luaEntries = luaEntries or function() return {} end,
        facts = facts,
        pool = function() return { "gm_a", "gm_b" } end,
        fits = function() return true end,
        rng = seeded(7),
        setSetting = function(fullId, value)
            applied(state)[#applied(state) + 1] = { fullId, value }
            return fullId ~= "bots.difficulty", "refused"
        end,
        start = function(modeId, map)
            started(state)[#started(state) + 1] = { mode = modeId, map = map }
            return true
        end,
        readId = function() return state.request --[[@as string]] end,
        send = function(ply, list) sent(state)[#sent(state) + 1] = { ply = ply, state = list } end,
        getActive = function() return state.active --[[@as string]] end,
        setActive = function(id) state.active = id end
    })
end

---Returns the one pool bot with the given usergroup (one bot for the whole group: the suite is close to maxplayers).
---@param state table<string, any>
---@param group string
---@return Player
local function makeBot(state, group)
    local pool = state.pool --[[@as table<string, Player>]]
    local bot = pool.bot
    if bot == nil or not IsValid(bot) then
        bot = player.CreateNextBot("PW playlist test")
        assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
        pool.bot = bot
    end
    bot:SetUserGroup(group)
    return bot
end

---Sends one message from ply through the real wrapper (2 s after the previous one).
---@param state table<string, any>
---@param name string
---@param ply Player
---@param id string
---@return boolean
---@return string?
local function send(state, name, ply, id)
    state.request = id
    local now = state.now --[[@as number]]
    state.now = now + 2
    return must(PW.Net)._Dispatch(name, 64, ply)
end

---@param raw table<string, any>
---@return string
local function jsonOf(raw)
    return util.TableToJSON({ Name = raw.Name, Modes = raw.Modes, Maps = raw.Maps, Settings = raw.Settings })
end

---Encodes and decodes a list state through recorded writes.
---@param state PW.PlaylistListState
---@return PW.PlaylistListState
local function roundTrip(state)
    ---@type any[]
    local bits = {}
    lib()._Encode(state, {
        uint = function(value, width) bits[#bits + 1] = { value, width } end,
        string = function(value) bits[#bits + 1] = value end,
        bool = function(value) bits[#bits + 1] = value end
    })
    local at = 0
    local function nextBit()
        at = at + 1
        return bits[at]
    end
    return lib()._Decode({
        uint = function() return must(nextBit())[1] end,
        string = function() return nextBit() end,
        bool = function() return nextBit() end
    })
end

local pureCases = {
    {
        -- Async on purpose, and first: a bot kicked by an earlier group frees its slot only after a frame.
        name = "The pick privilege is the lobby's start privilege with the superadmin default",
        async = true,
        timeout = 3,
        func = function()
            expect(lib().Privilege).to.equal("pw.match.start")
            expect(must(PW._Privileges.defs["pw.match.start"]).MinAccess).to.equal("superadmin")
            timer.Simple(0.2, function() done() end)
        end
    },
    {
        name = "Weighted sampling respects the weights over many draws (deterministic RNG)",
        func = function()
            local data = must(lib().Normalize({ Name = "W", Modes = { tdm = 1, ffa = 3, dom = 6 }, Maps = { "gm_a" } }))
            local rng = seeded(12345)
            local counts = { tdm = 0, ffa = 0, dom = 0 }
            local draws = 20000
            for _ = 1, draws do
                local pick = must(lib().Sample(data, { rng = rng }))
                counts[pick.mode] = counts[pick.mode] + 1
            end
            expect(math.abs(counts.tdm / draws - 0.1) < 0.015).to.beTrue()
            expect(math.abs(counts.ffa / draws - 0.3) < 0.015).to.beTrue()
            expect(math.abs(counts.dom / draws - 0.6) < 0.015).to.beTrue()
        end
    },
    {
        name = "PickWeighted visits ids in sorted order, follows the RNG boundaries and ignores weights up to 0",
        func = function()
            local weights = { b = 1, a = 1, z = 0, y = -3 }
            expect(lib().PickWeighted(weights, function() return 0 end)).to.equal("a")
            expect(lib().PickWeighted(weights, function() return 0.49 end)).to.equal("a")
            expect(lib().PickWeighted(weights, function() return 0.5 end)).to.equal("b")
            expect(lib().PickWeighted(weights, function() return 0.999999 end)).to.equal("b")
            expect(lib().PickWeighted(weights, function() return 1 end)).to.equal("b")
            expect(lib().PickWeighted({}, function() return 0.3 end)).to.beNil()
            expect(lib().PickWeighted({ a = 0 }, function() return 0.3 end)).to.beNil()
        end
    },
    {
        name = "Sample takes a map of the pool, only for modes that fit, and uses opts.maps when Maps is nil",
        func = function()
            local data = must(lib().Normalize({ Name = "S", Modes = { tdm = 1, ffa = 1 } }))
            local rng = seeded(99)
            ---@type table<string, true>
            local seen = {}
            for _ = 1, 200 do
                local pick = must(lib().Sample(data, { rng = rng, maps = { "gm_a", "gm_b", "gm_c" },
                    fits = function(modeId, map) return modeId == "ffa" and map ~= "gm_c" end }))
                seen[pick.mode .. "@" .. pick.map] = true
            end
            expect(seen).to.deepEqual({ ["ffa@gm_a"] = true, ["ffa@gm_b"] = true })
            local none = { rng = rng, maps = { "gm_a" }, fits = function() return false end }
            local pick, reason = lib().Sample(data, none)
            expect(pick).to.beNil()
            expect(reason).to.exist()
            expect(lib().Sample(data, { rng = rng })).to.beNil()
        end
    },
    {
        name = "A valid playlist is normalized to a clean copy; Maps = nil stays nil; Settings default to empty",
        func = function()
            local raw = goodPlaylist()
            raw.Extra = "ignored"
            local data = must(lib().Normalize(raw, facts()))
            expect(data).to.deepEqual({ Name = "TDM and FFA", Modes = { tdm = 2, ffa = 1 },
                Maps = { "gm_construct", "gm_flatgrass" },
                Settings = { ["tdm.scorelimit"] = 100, ["bots.fill"] = 24 } })
            local open = must(lib().Normalize({ Name = "Open", Modes = { tdm = 1 } }, facts()))
            expect(open.Maps).to.beNil()
            expect(open.Settings).to.deepEqual({})
        end
    },
    {
        name = "Invalid playlists are rejected with a message naming the problem",
        func = function()
            for _, case in ipairs(badCases()) do
                local raw = goodPlaylist()
                case.change(raw)
                local data, err = lib().Normalize(raw, facts())
                expect(data).to.beNil()
                expect(mentions(err, case.word)).to.beTrue()
            end
            expect(select(2, lib().Normalize("text", facts()))).to.exist()
        end
    },
    {
        name = "Setting values are checked against the schema and clamped",
        func = function()
            local raw = goodPlaylist()
            raw.Settings = { ["tdm.scorelimit"] = 5000, ["bots.fill"] = 11.6 }
            local data = must(lib().Normalize(raw, facts()))
            expect(data.Settings).to.deepEqual({ ["tdm.scorelimit"] = 1000, ["bots.fill"] = 12 })
        end
    },
    {
        name = "Host-saved JSON loads and validates like a Lua playlist: same result, same rejections",
        func = function()
            local fromLua = must(lib().Normalize(goodPlaylist(), facts()))
            local fromJson = must(lib().FromJson(lib().ToJson(fromLua), facts()))
            expect(fromJson).to.deepEqual(fromLua)
            local noMaps = must(lib().FromJson([[{"Name":"Open","Modes":{"tdm":1}}]], facts()))
            expect(noMaps.Maps).to.beNil()
            expect(noMaps.Settings).to.deepEqual({})
            for _, case in ipairs(badCases()) do
                local bad = goodPlaylist()
                case.change(bad)
                local _, luaErr = lib().Normalize(bad, facts())
                local data, jsonErr = lib().FromJson(jsonOf(bad), facts())
                expect(data).to.beNil()
                expect(jsonErr).to.equal(luaErr)
            end
        end
    },
    {
        name = "Invalid JSON is rejected with a readable message",
        func = function()
            for _, text in ipairs({ "", "   ", "{", "not json at all", "[1, 2, 3]", [["a string"]], "42" }) do
                local data, err = lib().FromJson(text, facts())
                expect(data).to.beNil()
                expect(mentions(err, "invalid JSON")).to.beTrue()
            end
            expect(select(2, lib().FromJson(nil, facts()))).to.exist()
            local _, version = lib().FromJson([[{"Version":2,"Name":"x","Modes":{"tdm":1}}]], facts())
            expect(mentions(version, "Version")).to.beTrue()
            local _, field = lib().FromJson([[{"Name":"x","Modes":{"tdm":1},"Colour":"red"}]], facts())
            expect(mentions(field, "Colour")).to.beTrue()
        end
    },
    {
        name = "The file id is the name of a *.json file made of lowercase letters, digits and _",
        func = function()
            expect(lib().FileId("night_ffa2.json")).to.equal("night_ffa2")
            for _, name in ipairs({ "Night.json", "a b.json", "a.txt", ".json", "x.json.bak", "../a.json" }) do
                expect(lib().FileId(name)).to.beNil()
            end
            expect(lib().FileId(5)).to.beNil()
        end
    },
    {
        name = "The list round-trips through the explicit wire encoding; the rows show Custom first and the warning",
        func = function()
            local state = { list = {
                { id = "a", name = "Alpha", summary = "tdm on 2 maps", fill = 0 },
                { id = "b", name = "Beta", summary = "ffa on all maps", fill = 24 }
            }, active = "b", canPick = true }
            expect(roundTrip(state)).to.deepEqual(state)
            local rows = lib()._Items(state, 16)
            expect(rows.items[1].id).to.equal(lib().CustomRow)
            expect(#rows.items).to.equal(3)
            expect(rows.selected).to.equal("b")
            expect(rows.warning).to.equal("Beta expects 24 players, the server has 16")
            expect(lib()._Items(state, 24).warning).to.beNil()
            state.active = ""
            expect(lib()._Items(state, 16).selected).to.equal(lib().CustomRow)
        end
    }
}

local serverCases = {
    {
        name = "The shipped playlists are listed from the playlists registry and pass the real validation",
        func = function(state)
            PW._Playlist = state.previousStore
            expect(PW.Registries.playlists).to.exist()
            ---@type table<string, string>
            local ids = {}
            for _, entry in ipairs(must(lib().GetList)()) do ids[entry.id] = entry.source end
            expect(ids.tdm_ffa).to.equal("lua")
            expect(ids.free_for_all).to.equal("lua")
            local shipped = must(PW.Playlists).Get("tdm_ffa")
            expect(must(lib().Normalize(shipped, must(PW._Playlist).facts())).Name).to.equal("TDM & FFA")
        end
    },
    {
        name = "The bots module declares the match settings bots.fill, difficulty, classes, classrepick and no more",
        func = function()
            ---@type table<string, PW.SettingDef>
            local fields = {}
            for _, group in ipairs(PW.Settings.GetGroups("match")) do
                if group.owner == "bots" then
                    for _, field in ipairs(group.fields) do fields[field.def.key] = field.def end
                end
            end
            expect(fields.fill.scope).to.equal("match")
            expect(fields.fill.type).to.equal("int")
            expect(fields.fill.default).to.equal(12)
            expect(fields.difficulty.type).to.equal("enum")
            -- T-5.13 (05-loadout.md d.14): the class sources and the re-pick chance of the bot loadouts
            expect(fields.classes.type).to.equal("set")
            expect(fields.classrepick.type).to.equal("float")
            expect(table.Count(fields)).to.equal(4)
        end
    },
    {
        name = "JSON files load with the id of the file name; an invalid file is rejected with a message, not loaded",
        func = function(state)
            writeFile(state, "pwt_good.json", lib().ToJson(must(lib().Normalize(goodPlaylist(), facts()))))
            writeFile(state, "pwt_broken.json", "{ this is not json")
            writeFile(state, "pwt_wrong.json", jsonOf({ Name = "Wrong", Modes = { nope = 1 } }))
            writeFile(state, "bad name.json", jsonOf(goodPlaylist()))
            local list, errors = must(lib().LoadDir)()
            expect(#list).to.equal(1)
            expect(list[1].id).to.equal("pwt_good")
            expect(list[1].source).to.equal("json")
            expect(list[1].Settings["tdm.scorelimit"]).to.equal(100)
            ---@type table<string, string>
            local byFile = {}
            for _, failure in ipairs(errors) do byFile[failure.file] = failure.message end
            expect(mentions(byFile["pwt_broken.json"], "invalid JSON")).to.beTrue()
            expect(mentions(byFile["pwt_wrong.json"], "unknown mode")).to.beTrue()
            expect(byFile["bad name.json"]).to.exist()
            expect(#logs(state)).to.equal(3)
        end
    },
    {
        name = "The list holds Lua and JSON playlists sorted by name; a Lua playlist wins over a JSON file of its id",
        func = function(state)
            local entities = {
                { ClassName = "pwt_lua", Name = "Zulu", Modes = { tdm = 1 } },
                { ClassName = "pwt_same", Name = "Lua wins", Modes = { ffa = 1 } },
                { ClassName = "pwt_bad", Name = "Bad", Modes = { nope = 1 } }
            }
            installStore(state, function() return entities end)
            writeFile(state, "pwt_same.json", jsonOf({ Name = "Json loses", Modes = { tdm = 1 } }))
            writeFile(state, "pwt_json.json", jsonOf({ Name = "Alpha", Modes = { dom = 1 } }))
            ---@type string[]
            local names = {}
            for _, entry in ipairs(must(lib().GetList)()) do names[#names + 1] = entry.id .. ":" .. entry.Name end
            expect(names).to.deepEqual({ "pwt_json:Alpha", "pwt_same:Lua wins", "pwt_lua:Zulu" })
            expect(must(lib().Get)("pwt_lua").source).to.equal("lua")
            expect(must(lib().Get)("pwt_nope")).to.beNil()
        end
    },
    {
        name = "Save validates like a load and writes a file the loader reads back",
        func = function(state)
            local ok, err = must(lib().Save)("pwt_saved", { Name = "Saved", Modes = { nope = 1 } })
            expect({ ok, mentions(err, "unknown mode") }).to.deepEqual({ false, true })
            expect(must(lib().Save)("Bad Id", goodPlaylist())).to.beFalse()
            expect(file.Exists(testDir .. "/pwt_saved.json", "DATA")).to.beFalse()
            local written = state.written --[[@as string[] ]]
            written[#written + 1] = "pwt_saved.json"
            expect(must(lib().Save)("pwt_saved", goodPlaylist())).to.beTrue()
            local entry = must(must(lib().Get)("pwt_saved"))
            expect(entry.Name).to.equal("TDM and FFA")
            expect(entry.Modes).to.deepEqual({ tdm = 2, ffa = 1 })
        end
    },
    {
        name = "Start applies the settings that apply, remembers the playlist and starts a sampled mode and map",
        func = function(state)
            writeFile(state, "pwt_start.json", jsonOf({ Name = "Go", Modes = { ffa = 1 }, Maps = { "gm_a", "gm_b" },
                Settings = { ["bots.fill"] = 20, ["bots.difficulty"] = "recruit" } }))
            expect(must(lib().Start)("pwt_start")).to.beTrue()
            expect(applied(state)).to.deepEqual({ { "bots.difficulty", "recruit" }, { "bots.fill", 20 } })
            expect(state.active).to.equal("pwt_start")
            expect(#started(state)).to.equal(1)
            expect(started(state)[1].mode).to.equal("ffa")
            expect(table.HasValue({ "gm_a", "gm_b" }, started(state)[1].map)).to.beTrue()
            expect(#logs(state) >= 1).to.beTrue()
            local ok, reason = must(lib().Start)("pwt_missing")
            expect({ ok, mentions(reason, "unknown playlist") }).to.deepEqual({ false, true })
            expect(#started(state)).to.equal(1)
        end
    }
}

local netCases = {
    {
        name = "Start and pick require the privilege; the list request answers any player",
        func = function(state)
            writeFile(state, "pwt_net.json", jsonOf({ Name = "Net", Modes = { tdm = 1 }, Maps = { "gm_a" } }))
            local bot = makeBot(state, "user")
            expect({ send(state, "pw_playlist_start", bot, "pwt_net") }).to.deepEqual({ false, "privilege" })
            expect({ send(state, "pw_playlist_pick", bot, "pwt_net") }).to.deepEqual({ false, "privilege" })
            expect(#started(state)).to.equal(0)
            expect(state.active).to.equal("")
            expect(send(state, "pw_playlist_request", bot, "")).to.beTrue()
            expect(sent(state)[1].state.canPick).to.beFalse()
            makeBot(state, "superadmin")
            expect(send(state, "pw_playlist_pick", bot, "pwt_net")).to.beTrue()
            expect(state.active).to.equal("pwt_net")
            expect(sent(state)[2].state.active).to.equal("pwt_net")
            expect(sent(state)[2].state.canPick).to.beTrue()
            expect(send(state, "pw_playlist_start", bot, "pwt_net")).to.beTrue()
            expect(started(state)).to.deepEqual({ { mode = "tdm", map = "gm_a" } })
        end
    },
    {
        name = "Pick accepts Custom and refuses an unknown id; a request after a removal reports Custom",
        func = function(state)
            local bot = makeBot(state, "superadmin")
            expect(send(state, "pw_playlist_pick", bot, "pwt_missing")).to.beTrue()
            expect(state.active).to.equal("")
            expect(#sent(state)).to.equal(0)
            state.active = "pwt_gone"
            expect(send(state, "pw_playlist_request", bot, "")).to.beTrue()
            expect(sent(state)[1].state.active).to.equal("")
            expect(send(state, "pw_playlist_pick", bot, "")).to.beTrue()
            expect(state.active).to.equal("")
        end
    },
    {
        name = "A start from outside the lobby, or with an unknown playlist, starts nothing",
        func = function(state)
            local bot = makeBot(state, "superadmin")
            state.phase = "LIVE"
            expect({ send(state, "pw_playlist_start", bot, "x") }).to.deepEqual({ false, "phase" })
            state.phase = "LOBBY"
            send(state, "pw_playlist_start", bot, "pwt_missing")
            expect(#started(state)).to.equal(0)
        end
    },
    {
        name = "A disabled playlists module drops its messages before the handlers run",
        func = function(state)
            local bot = makeBot(state, "superadmin")
            state.ownerValid = false
            expect({ send(state, "pw_playlist_request", bot, "") }).to.deepEqual({ false, "disabled" })
            expect({ send(state, "pw_playlist_start", bot, "x") }).to.deepEqual({ false, "disabled" })
            expect(#sent(state)).to.equal(0)
        end
    },
    {
        name = "The messages registered when the module loaded are in the real net store, owned by playlists",
        func = function(state)
            local real = state.previousNet --[[@as PW.NetStore]]
            local owner = must(PW.Modules.GetStored("playlists"))
            for _, name in ipairs({ "pw_playlist_request", "pw_playlist_pick", "pw_playlist_start" }) do
                expect(must(real.defs[name]).owner).to.equal(owner)
            end
            expect(util.NetworkStringToID("pw_playlist_list")).toNot.equal(0)
        end
    },
    {
        name = "The playlists client file checks its module with IsValid(module), never module:IsValid()",
        func = function()
            local source = must(file.Read("privatewar/modules/playlists/cl_init.lua", "LUA"))
            expect(string.find(source, "module:IsValid()", 1, true)).to.beNil()
            expect(string.find(source, "IsValid(module)", 1, true)).to.exist()
        end
    }
}

---@param ...  table[]
---@return table[]
local function join(...)
    ---@type table[]
    local all = {}
    for _, group in ipairs({ ... }) do
        for _, case in ipairs(group) do all[#all + 1] = case end
    end
    return all
end

return {
    groupName = "PW playlists",
    beforeAll = function(state)
        state.pool = {}
    end,
    afterAll = function(state)
        local bot = (state.pool --[[@as table<string, Player>]]).bot
        if bot ~= nil and IsValid(bot) then bot:Kick("PW playlist test finished") end
    end,
    beforeEach = function(state)
        state.previousNet = PW._Net
        state.previousStore = PW._Playlist
        state.written = {}
        state.now = 1000
        state.phase = "LOBBY"
        state.ownerValid = true
        installStore(state)
        PW._Net = must(PW.Net)._NewStore({ log = function() end, clock = function() return state.now end,
            phase = function() return state.phase end })
        must(lib()._RegisterNet)({ IsValid = function() return state.ownerValid end })
    end,
    afterEach = function(state)
        for _, name in ipairs(state.written --[[@as string[] ]]) do file.Delete(testDir .. "/" .. name) end
        PW._Net = state.previousNet
        PW._Playlist = state.previousStore
    end,
    cases = join(pureCases, serverCases, netCases)
}
