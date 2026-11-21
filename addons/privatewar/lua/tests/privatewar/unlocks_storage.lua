-- Versioned unlocks persistence and wire rules (06-progression.md d.5 and d.8).

---@return PW.UnlocksLib
local function unlocks()
    return assert(PW.Unlocks)
end

---@return PW.ProgressionWriter, PW.ProgressionReader
local function wire()
    ---@type { width: integer, value: string|integer|boolean }[]
    local entries = {}
    local pos = 0
    ---@param width integer
    ---@return string|integer|boolean
    local function take(width)
        pos = pos + 1
        local entry = assert(entries[pos], "decoder read past the test wire payload")
        assert(entry.width == width, "decoder used an unexpected width")
        return entry.value
    end
    return {
        uint = function(value, width)
            assert(value >= 0 and value < 2 ^ width, "uint out of range")
            entries[#entries + 1] = { width = width, value = value }
        end,
        string = function(value) entries[#entries + 1] = { width = -1, value = value } end,
        bool = function(value) entries[#entries + 1] = { width = 1, value = value } end
    }, {
        uint = function(width) return take(width) --[[@as integer]] end,
        string = function() return take(-1) --[[@as string]] end,
        bool = function() return take(1) --[[@as boolean]] end
    }
end

local item = "perks:scavenger"

---@param bot? boolean
---@return Player
local function playerStub(bot)
    return {
        IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return bot == true end
    } --[[@as Player]]
end

---@return PW.ProgressionStore, PW.ProgressionDelta[], any[][], Player[]
local function server()
    ---@type PW.ProgressionDelta[], any[][], Player[]
    local deltas, notes, refreshes = {}, {}, {}
    local store = assert(PW.Progression)._NewStore({
        read = function() return nil end,
        publish = function() end,
        notify = function(...) notes[#notes + 1] = { ... } end,
        sendDelta = function(_, delta) deltas[#deltas + 1] = delta end,
        refresh = function(ply) refreshes[#refreshes + 1] = ply end
    })
    return store, deltas, notes, refreshes
end

return {
    groupName = "PW unlock storage",
    cases = {
        {
            name = "Grant: adds new keys once; a repeated grant id adds nothing and answers claimed",
            func = function()
                local u = unlocks()
                local store, deltas = server()
                local ply = playerStub()
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                local opts = { source = "challenge", grant = "weekly:1" }
                local added, reason = u._Grant(store, ply, { item, item, { kind = "perks", id = "scavenger" } }, opts)
                expect(added).to.equal(1)
                expect(reason).to.beNil()
                expect({ u._Grant(store, ply, { "perks:soft_landing" }, opts) }).to.deepEqual({ 0, "claimed" })
                expect(#deltas).to.equal(1)
                local entry = assert(assert(store.players[ply].grants)[item])
                expect(entry.source).to.equal("challenge")
                expect(entry.grant).to.equal("weekly:1")
                expect(entry.at > 0).to.beTrue()
                expect(assert(store.players[ply].grants)["perks:soft_landing"]).to.beNil()
            end
        },
        {
            name = "Grant: refuses bots, bad sources, bad grant ids, malformed and unknown items, too many items "
                .. "and a full set",
            func = function()
                local u = unlocks()
                local store, deltas = server()
                local ply = playerStub()
                local opts = { source = "event" }
                expect({ u._Grant(store, playerStub(true), { item }, opts) }).to.deepEqual({ 0, "bot" })
                expect({ u._Grant(store, NULL --[[@as Player]], { item }, opts) }).to.deepEqual({ 0, "badplayer" })
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                expect({ u._Grant(store, ply, { item }, { source = "Bad" }) }).to.deepEqual({ 0, "badsource" })
                expect({ u._Grant(store, ply, { item }, { source = "event", grant = "bad id" }) })
                    .to.deepEqual({ 0, "badgrant" })
                expect({ u._Grant(store, ply, { item, "bad id" }, opts) }).to.deepEqual({ 0, "badkey" })
                expect({ u._Grant(store, ply, { item, "perks:pwtest_missing_unlock" }, opts) })
                    .to.deepEqual({ 0, "unknown" })
                ---@type string[]
                local tooMany = {}
                for index = 1, u.MaxGrantPerCall + 1 do tooMany[index] = item end
                expect({ u._Grant(store, ply, tooMany, opts) }).to.deepEqual({ 0, "toomany" })
                expect(assert(store.players[ply].grants)).to.deepEqual({})
                local full = playerStub()
                ---@type table<string, boolean>
                local uploaded = {}
                for index = 1, u.MaxGrants do uploaded["perks:full_" .. index] = true end
                expect(u._OnUpload(store, full, { grants = uploaded, claims = {} })).to.beTrue()
                expect({ u._Grant(store, full, { item }, opts) }).to.deepEqual({ 0, "full" })
                expect(table.Count(assert(store.players[full].grants))).to.equal(u.MaxGrants)
                expect(#deltas).to.equal(0)
            end
        },
        {
            name = "Revoke: removes grants only, never purchases; revoking twice removes nothing more",
            func = function()
                local u = unlocks()
                local p = assert(PW.Progression)
                local store, deltas = server()
                local ply = playerStub()
                expect({ u._Revoke(store, ply, { item }, { source = "admin" }) }).to.deepEqual({ 0, "notready" })
                p._SetState(store, ply, { xp = 0, weapons = {}, owned = { [item] = true } })
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                local opts = { source = "challenge", grant = "reward" }
                expect({ u._Grant(store, ply, { item }, opts) }).to.deepEqual({ 1 })
                expect({ u._Revoke(store, ply, { item }, { source = "admin" }) }).to.deepEqual({ 1 })
                expect({ u._Revoke(store, ply, { item }, { source = "admin" }) }).to.deepEqual({ 0 })
                expect(assert(store.players[ply].grants)[item]).to.beNil()
                expect(assert(store.players[ply].owned)[item]).to.beTrue()
                expect(u._HasClaim(store.players[ply].claims, "reward")).to.beTrue()
                expect(#deltas).to.equal(2)
                expect(deltas[2].revoked).to.deepEqual({ [item] = "admin" })
            end
        },
        {
            name = "Grant and revoke: the delta carries them and the client file applies them once per batch id",
            func = function()
                local u = unlocks()
                local p = assert(PW.Progression)
                local store, deltas = server()
                local ply = playerStub()
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                expect({ u._Grant(store, ply, { item }, { source = "event" }) }).to.deepEqual({ 1 })
                expect({ u._Revoke(store, ply, { item }, { source = "admin" }) }).to.deepEqual({ 1 })
                local current = u._FileFromJson(nil)
                expect(#deltas).to.equal(2)
                for index, delta in ipairs(deltas) do
                    local writer, reader = wire()
                    p._EncodeDelta(delta, writer)
                    local fromWire = p._DecodeDelta(reader)
                    expect(fromWire.granted or {}).to.deepEqual(delta.granted or {})
                    expect(fromWire.revoked or {}).to.deepEqual(delta.revoked or {})
                    local updated, applied = u._ApplyDelta(current, fromWire)
                    expect(applied).to.beTrue()
                    expect(updated.grants[item] ~= nil).to.equal(index == 1)
                    local _, again = u._ApplyDelta(updated, fromWire)
                    expect(again).to.beFalse()
                    current = updated
                end
            end
        },
        {
            name = "Grant: classes are refreshed at once and PW_UnlockGranted fires with the new keys, source and "
                .. "grant id",
            func = function()
                local u = unlocks()
                local store, _, notes, refreshes = server()
                local ply = playerStub()
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                local opts = { source = "challenge", grant = "weekly:2" }
                expect({ u._Grant(store, ply, { item }, opts) }).to.deepEqual({ 1 })
                expect(refreshes).to.deepEqual({ ply, ply })
                expect(notes).to.deepEqual({ { "PW_UnlockGranted", ply, { item }, "challenge", "weekly:2" } })
            end
        },
        {
            name = "Upload: keys and claims are validated, bounded and accepted once; Grant waits for readiness",
            func = function()
                local u = unlocks()
                local store, _, _, refreshes = server()
                local ply = playerStub()
                expect(u._IsReady(store, ply)).to.beFalse()
                local writer, reader = wire()
                writer.uint(1, 8)
                writer.uint(u.MaxGrants + 1, 16)
                expect(u._OnUpload(store, ply, u._DecodeUpload(reader))).to.beFalse()
                expect(u._IsReady(store, ply)).to.beFalse()
                expect(u._IsReady(store, NULL --[[@as Player]])).to.beFalse()
                expect(u._IsReady(store, playerStub(true))).to.beFalse()
                expect({ u._Grant(store, ply, { item }, { source = "admin" }) }).to.deepEqual({ 0, "notready" })
                expect(u._OnUpload(store, ply, { grants = { [item] = true, ["bad key"] = true },
                    claims = { ["weekly:1"] = true, ["bad id"] = true } })).to.beTrue()
                expect(u._IsReady(store, ply)).to.beTrue()
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beFalse()
                expect(assert(store.players[ply].grants)).to.deepEqual({ [item] = { source = "grant", at = 0 } })
                expect(store.players[ply].claims).to.deepEqual({ ["weekly:1"] = 0 })
                expect(refreshes).to.deepEqual({ ply })
            end
        },
        {
            name = "Upload: keys of content not installed on this host are kept",
            func = function()
                local u = unlocks()
                local store = server()
                local ply = playerStub()
                local absent = "camos:pwtest_not_installed:gold"
                expect(u._OnUpload(store, ply, { grants = { [absent] = true }, claims = {} })).to.beTrue()
                expect(assert(store.players[ply].grants)[absent]).to.deepEqual({ source = "grant", at = 0 })
            end
        },
        {
            name = "Net: pw_unlocks_upload is registered with an owner, a rate and the size bound; a second upload "
                .. "is ignored",
            func = function()
                local u = unlocks()
                local p = assert(PW.Progression)
                local store, _, _, refreshes = server()
                local ply = player.GetHumans()[1] or playerStub()
                local definition = assert(PW._Net.defs.pw_unlocks_upload)
                expect(definition.who).to.equal("any")
                expect(definition.rate).to.equal(0.5)
                expect(definition.maxLen).to.equal(u.UploadMaxBytes)
                local owner = assert(definition.owner)
                expect(owner).to.equal(assert(PW.Registries.modules.GetStored("progression")))
                expect(IsValid(owner)).to.beTrue()
                expect(util.NetworkStringToID("pw_unlocks_upload") > 0).to.beTrue()
                local readerCalls = 0
                stub(p, "_NetReader").with(function()
                    readerCalls = readerCalls + 1
                    local writer, reader = wire()
                    u._EncodeUpload(u._FileFromJson(nil), writer)
                    return reader
                end)
                local previous = PW._Progression
                PW._Progression = store
                local ok, err = pcall(function()
                    expect(u.IsReady(ply)).to.beFalse()
                    definition.handler(ply, 39)
                    expect(u.IsReady(ply)).to.beFalse()
                    definition.handler(ply, 40)
                    expect(u.IsReady(ply)).to.beTrue()
                    definition.handler(ply, 40)
                    expect(readerCalls).to.equal(1)
                    expect(refreshes).to.deepEqual({ ply })
                end)
                PW._Progression = previous
                assert(ok, err)
            end
        },
        {
            name = "Server rejects a locked loadout choice: a grant-only item in an uploaded class is repaired away "
                .. "until granted",
            func = function()
                local u, p, loadout = unlocks(), assert(PW.Progression), assert(PW.Loadout)
                local store = server()
                local ply = playerStub()
                local lookup = p._RegistryLookup
                stub(p, "_RegistryLookup").with(function(kind, id)
                    if kind == "perks" and id == "scavenger" then
                        return { Name = "Scavenger", Group = 2, Cost = 1, Unlock = false }
                    end
                    return lookup(kind, id)
                end)
                stub(p, "IsUnlocked").with(function() return true end)
                local classes = loadout._NewClassStore({
                    context = function() return { lookup = p._RegistryLookup, budget = 0, maxattachments = 5 } end,
                    send = function() end
                })
                local oldProgress, oldClasses = PW._Progression, PW._LoadoutClasses
                PW._Progression, PW._LoadoutClasses = store, classes
                local ok, err = pcall(function()
                    expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                    local data = { { name = "Reward", loadout = { primary = "weapon_ar2", perk2 = "scavenger" } } }
                    local locked = loadout._OnClasses(ply, data).entries[1]
                    expect(locked.ref).to.equal("custom:1")
                    expect(locked.loadout.perk2).to.beNil()
                    expect(locked.loadout.primary).to.equal("weapon_ar2")
                    expect(locked.removed).to.deepEqual({ "scavenger (locked)" })
                    expect({ u._Grant(store, ply, { item }, { source = "challenge" }) }).to.deepEqual({ 1 })
                    local open = loadout.ClassState(ply).entries[1]
                    expect(open.loadout.perk2).to.equal("scavenger")
                    expect(open.removed).to.deepEqual({})
                end)
                PW._Progression, PW._LoadoutClasses = oldProgress, oldClasses
                assert(ok, err)
            end
        },
        {
            name = "Server rejects a locked operator: a grant-only model choice is refused until granted",
            func = function()
                local u, p, ops = unlocks(), assert(PW.Progression), assert(PW.Operators)
                local store = server()
                local path, fallback = "models/player/combine_super_soldier.mdl", ops.FallbackPath
                local applied = ""
                local ply = {
                    IsValid = function() return true end, IsPlayer = function() return true end,
                    IsBot = function() return false end, Alive = function() return false end,
                    GetInfo = function() return ops.FallbackName end, Nick = function() return "Test operator" end,
                    SetModel = function(_, value) applied = value end, SetPlayerColor = function() end,
                    Team = function() return 0 end
                } --[[@as Player]]
                local lookup = p._RegistryLookup
                stub(p, "_RegistryLookup").with(function(kind, id)
                    if kind == "models" and id == "combine_elite" then return { Model = path, Unlock = false } end
                    return lookup(kind, id)
                end)
                stub(p, "IsUnlocked").with(function() return true end)
                local operators = assert(ops._NewStore)({
                    log = function() end, stock = function() return { [ops.FallbackName] = fallback } end,
                    economy = function() return { { id = "combine_elite", name = "Elite", path = path } } end
                })
                local oldStore, key = PW._Progression, "models:combine_elite"
                PW._Progression = store
                local request, spawn = assert(ops._OnRequest), assert(ops._OnSetModel)
                local ok, err = pcall(function()
                    expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                    expect(request(operators, ply, ops.Auto)).to.beTrue()
                    expect({ request(operators, ply, key) }).to.deepEqual({ false, "locked" })
                    expect(operators.requested[ply]).to.equal(ops.Auto)
                    expect(spawn(operators, ply)).to.equal(fallback)
                    expect(applied).to.equal(fallback)
                    expect(u._Grant(store, ply, { key }, { source = "challenge" })).to.equal(1)
                    expect(request(operators, ply, key)).to.beTrue()
                    expect(spawn(operators, ply)).to.equal(path)
                    expect(applied).to.equal(path)
                    expect(u._Revoke(store, ply, { key }, { source = "admin" })).to.equal(1)
                    expect(spawn(operators, ply)).to.equal(fallback)
                    expect(operators.requested[ply]).to.equal(key)
                end)
                PW._Progression = oldStore
                assert(ok, err)
            end
        },
        {
            name = "Bots unaffected: bot pools and bot operators never call PW.Unlocks.IsUnlocked; Grant refuses bots",
            async = true,
            timeout = 10,
            func = function()
                local u, p, ops = unlocks(), assert(PW.Progression), assert(PW.Operators)
                local bots = assert(PW.BotLoadouts)
                ---@type Player?
                local prior = player.GetBots()[1]
                if prior ~= nil and prior:GetModel() == nil then prior = nil end
                local bot = prior or player.CreateNextBot("PW unlock bot test")
                assert(IsValid(bot), "could not reuse or create a bot")
                local originalModel, originalColour = bot:GetModel(), bot:GetPlayerColor()
                local ok, err = pcall(function()
                    local count = 0
                    stub(u, "IsUnlocked").with(function() count = count + 1 return false, "override" end)
                    stub(p, "IsUnlocked").with(function() count = count + 1 return false end)
                    stub(bots, "Harvest").with(function() end)
                    local settings = PW.Setting
                    stub(PW, "Setting").with(function(id)
                        if id == "bots.classes" then return { preset = true } end
                        return settings(id)
                    end)
                    expect(#bots.PoolFor(bot) > 0).to.beTrue()
                    local operators = ops._NewStore({ roll = function() return 0 end })
                    expect(ops._OnSetModel(operators, bot) ~= "").to.beTrue()
                    expect(count).to.equal(0)
                    local result = { u._Grant(server(), bot, { item }, { source = "event" }) }
                    expect(result).to.deepEqual({ 0, "bot" })
                end)
                if prior ~= nil then
                    bot:SetModel(assert(originalModel))
                    bot:SetPlayerColor(originalColour)
                    assert(ok, err)
                    done()
                    return
                end
                bot:Kick("unlock tests done")
                -- The entity can still be visible to the next test until the engine processes the kick.
                local function finish()
                    if IsValid(bot) then return timer.Simple(0.05, finish) end
                    assert(ok, err)
                    done()
                end
                finish()
            end
        },
        {
            name = "Economy: a granted item counts as owned in a quote; a purchase refreshes the classes",
            func = function()
                local u = unlocks()
                local p, economy = assert(PW.Progression), assert(PW.Economy)
                local store, deltas, _, refreshes = server()
                local ply = playerStub()
                local buyable = "perks:soft_landing"
                p._SetState(store, ply, { xp = 0, weapons = {}, currency = 200 })
                expect(u._OnUpload(store, ply, { grants = { [item] = true }, claims = {} })).to.beTrue()
                local shop = economy._NewStore({
                    progression = store,
                    catalogue = function()
                        return { perks = {
                            scavenger = { Name = "Scavenger", Price = 100, Unlock = false },
                            soft_landing = { Name = "Soft Landing", Price = 80 }
                        } }
                    end,
                    read = function() return nil end,
                    notify = function() end
                })
                local context = economy._Context(shop, ply)
                expect(context.owned(item)).to.beTrue()
                expect(context.unlocked("perks", "scavenger")).to.beFalse()
                expect(p._GetOwned(store, ply)[item]).to.beNil()
                local quote, reason = economy._Quote(context, item)
                expect(quote).to.beNil()
                expect(reason).to.equal("owned")
                expect({ economy._Buy(shop, ply, item) }).to.deepEqual({ false, "owned" })
                expect(store.players[ply].currency).to.equal(200)
                expect(#refreshes).to.equal(1)
                expect({ economy._Buy(shop, ply, buyable) }).to.deepEqual({ true, "" })
                expect(store.players[ply].currency).to.equal(120)
                expect(p._GetOwned(store, ply)[buyable]).to.beTrue()
                expect(assert(store.players[ply].grants)[buyable]).to.beNil()
                expect(refreshes).to.deepEqual({ ply, ply })
                expect(#deltas).to.equal(1)
            end
        },
        {
            name = "Claim only: an empty grant with a grant id records the claim once; HasClaim answers on both realms",
            func = function()
                local u = unlocks()
                local store, deltas, notes = server()
                local ply = playerStub()
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                local options = { source = "challenge", grant = "weekly:xp" }
                local count, reason = u._Grant(store, ply, {}, options)
                expect(count).to.equal(0)
                expect(reason).to.beNil()
                expect({ u._Grant(store, ply, {}, options) }).to.deepEqual({ 0, "claimed" })
                expect(#deltas).to.equal(1)
                expect(#notes).to.equal(0)
                local localFile = u._ApplyDelta(u._FileFromJson(nil), deltas[1])
                expect(u._HasClaim(store.players[ply].claims, "weekly:xp")).to.beTrue()
                expect(u._HasClaim(localFile.claims, "weekly:xp")).to.beTrue()
                expect(u._HasClaim(localFile.claims, "missing")).to.beFalse()
            end
        },
        {
            name = "Batching: XP and currency queued before a Grant travel in its delta; the client writes "
                .. "unlocks.json before progression.json",
            func = function()
                local u = unlocks()
                local p = assert(PW.Progression)
                local store, deltas = server()
                local ply = playerStub()
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                p._OnScoreEvent(store, ply, "kill", 0, 25)
                p._AddCurrency(store, ply, 10)
                expect(#deltas).to.equal(0)
                local opts = { source = "challenge", grant = "weekly:xp" }
                expect({ u._Grant(store, ply, { item }, opts) }).to.deepEqual({ 1 })
                expect(#deltas).to.equal(1)
                local batch = deltas[1]
                expect(batch.xp).to.equal(25)
                expect(batch.earned).to.equal(10)
                expect(assert(batch.granted)[item].grant).to.equal("weekly:xp")
                expect(assert(batch.claims)["weekly:xp"] > 0).to.beTrue()
                expect(store.pending[ply]).to.beNil()
                ---@type PW.ProgressionLocal
                local client = {}
                ---@type string[]
                local writes = {}
                ---@type PW.UnlockClientIO
                local io = {
                    writeUnlocks = function(stored)
                        writes[#writes + 1] = "unlocks.json"
                        expect(u._HasClaim(stored.claims, "weekly:xp")).to.beTrue()
                        expect(client.file).to.beNil()
                    end,
                    writeProgression = function(stored)
                        writes[#writes + 1] = "progression.json"
                        expect(u._HasClaim(assert(client.unlocks).claims, "weekly:xp")).to.beTrue()
                        expect(stored.xp).to.equal(25)
                        expect(stored.currency).to.equal(10)
                    end,
                    notify = function() end
                }
                expect(u._ClientDelta(client, batch, ply, io)).to.beTrue()
                expect(u._ClientDelta(client, batch, ply, io)).to.beFalse()
                expect(writes).to.deepEqual({ "unlocks.json", "progression.json" })
            end
        },
        {
            name = "Grant before upload: no items or claims applied, no delta flushed; full upload is preserved",
            func = function()
                local u = unlocks()
                local p = assert(PW.Progression)
                local store, deltas, notes, refreshes = server()
                local ply = playerStub()
                p._AddCurrency(store, ply, 5)
                local pending = store.pending[ply]
                local opts = { source = "challenge", grant = "weekly:first" }
                expect(u._IsReady(store, ply)).to.beFalse()
                expect({ u._Grant(store, ply, { item }, opts) }).to.deepEqual({ 0, "notready" })
                expect({ u._Grant(store, ply, {}, opts) }).to.deepEqual({ 0, "notready" })
                expect(u._HasClaim(store.players[ply].claims, "weekly:first")).to.beFalse()
                expect(assert(store.players[ply].grants)[item]).to.beNil()
                expect(store.pending[ply]).to.equal(pending)
                expect(#deltas + #notes + #refreshes).to.equal(0)
                ---@type table<string, boolean>
                local keys = {}
                for index = 1, u.MaxGrants do keys["perks:uploaded_" .. index] = true end
                expect(u._OnUpload(store, ply, { grants = keys, claims = {} })).to.beTrue()
                expect(u._IsReady(store, ply)).to.beTrue()
                expect({ u._Grant(store, ply, { item }, opts) }).to.deepEqual({ 0, "full" })
                expect(u._HasClaim(store.players[ply].claims, "weekly:first")).to.beFalse()
                local kept = assert(store.players[ply].grants)
                expect(table.Count(kept)).to.equal(u.MaxGrants)
                for key in pairs(keys) do expect(kept[key]).toNot.beNil() end
                expect(kept[item]).to.beNil()
                expect(store.pending[ply]).to.equal(pending)
                expect(#deltas + #notes).to.equal(0)
                expect(refreshes).to.deepEqual({ ply })
            end
        },
        {
            name = "Revoke: both realms notify the revoking source once",
            func = function()
                local u = unlocks()
                local store, deltas, notes = server()
                local ply = playerStub()
                expect(u._OnUpload(store, ply, { grants = {}, claims = {} })).to.beTrue()
                expect({ u._Grant(store, ply, { item }, { source = "challenge" }) }).to.deepEqual({ 1 })
                expect({ u._Revoke(store, ply, { item }, { source = "admin" }) }).to.deepEqual({ 1 })
                expect({ u._Revoke(store, ply, { item }, { source = "admin" }) }).to.deepEqual({ 0 })
                expect(notes).to.deepEqual({
                    { "PW_UnlockGranted", ply, { item }, "challenge" },
                    { "PW_UnlockRevoked", ply, { item }, "admin" }
                })
                expect(deltas[2].revoked).to.deepEqual({ [item] = "admin" })
                ---@type PW.ProgressionLocal
                local client = {}
                ---@type any[][]
                local notices = {}
                ---@type PW.UnlockClientIO
                local io = {
                    writeUnlocks = function() end,
                    writeProgression = function() end,
                    notify = function(...) notices[#notices + 1] = { ... } end
                }
                expect(u._ClientDelta(client, deltas[1], ply, io)).to.beTrue()
                local localGrants = assert(client.unlocks).grants
                localGrants["perks:already_granted"] = { source = "event", at = 1 }
                localGrants["models:other"] = { source = "challenge", at = 1 }
                local incoming = table.Copy(deltas[2])
                local revoked = assert(incoming.revoked)
                revoked["perks:already_granted"] = "admin"
                revoked["models:other"] = "event"
                revoked["perks:never_granted"] = "admin"
                expect(u._ClientDelta(client, incoming, ply, io)).to.beTrue()
                expect(u._ClientDelta(client, incoming, ply, io)).to.beFalse()
                expect(assert(client.unlocks).grants).to.deepEqual({})
                expect(notices).to.deepEqual({
                    { "PW_UnlockGranted", ply, { item }, "challenge" },
                    { "PW_UnlockRevoked", ply, { "perks:already_granted", item }, "admin" },
                    { "PW_UnlockRevoked", ply, { "models:other" }, "event" }
                })
            end
        },
        {
            name = "Migration: a v2 progression.json with owned keys and no unlocks.json lists purchases as "
                .. "entitlements; nothing is lost and progression.json stays at version 2",
            func = function()
                local p = assert(PW.Progression)
                local u = unlocks()
                local v2 = { v = 2, xp = 300, weapons = { rifle = 70 }, currency = 220,
                    owned = { "models:operator", "camos:rifle:gold" }, batch = { session = 22, seq = 3 } }
                local old = p._FileFromJson(v2)
                local grants = u._FileFromJson(nil)
                expect(grants.grants).to.deepEqual({})
                expect(u._ListEntitled(old.owned, grants.grants)).to.deepEqual({
                    ["models:operator"] = { source = "purchase", at = 0 },
                    ["camos:rifle:gold"] = { source = "purchase", at = 0 }
                })
                local roundTrip = p._FileToJson(old)
                expect(roundTrip.v).to.equal(2)
                expect(roundTrip.xp).to.equal(300)
                expect(roundTrip.weapons).to.deepEqual({ rifle = 70 })
                expect(roundTrip.currency).to.equal(220)
                expect(roundTrip.owned).to.deepEqual({ "camos:rifle:gold", "models:operator" })
                expect(roundTrip.batch).to.deepEqual({ session = 22, seq = 3 })
                expect(roundTrip.grants).to.beNil()
                expect(roundTrip.claims).to.beNil()
            end
        },
        {
            name = "Migration: a v1 progression.json still loads with no entitlements",
            func = function()
                local p = assert(PW.Progression)
                local u = unlocks()
                local old = p._FileFromJson({ v = 1, xp = 200, weapons = { rifle = 20 } })
                expect(old.xp).to.equal(200)
                expect(old.weapons).to.deepEqual({ rifle = 20 })
                expect(u._ListEntitled(old.owned, u._FileFromJson(nil).grants)).to.deepEqual({})
            end
        },
        {
            name = "Malformed: a missing, empty, non-JSON or wrong-shaped unlocks.json reads as empty; bad entries "
                .. "are dropped",
            func = function()
                local u = unlocks()
                local empty = { v = 1, grants = {}, claims = {}, batch = { session = 0, seq = 0 } }
                expect(u._FileFromJson(nil)).to.deepEqual(empty)
                for _, text in ipairs({ "", "not JSON", "[]", "{\"v\":7}", "{\"v\":1,\"grants\":false}" }) do
                    expect(u._FileFromJson(util.JSONToTable(text, false, true))).to.deepEqual(empty)
                end
                local clean = {
                    v = 1, grants = { ["perks:correct"] = { source = "challenge", at = 20, grant = "123" } },
                    claims = { ["123"] = 20 }, batch = { session = 1, seq = 7 }
                }
                ---@type { v: integer, grants: table<string, table<string, any>>, claims: table<string, number>,
                ---batch: PW.ProgressionBatch }
                local dirty = table.Copy(clean)
                dirty.grants["perks: space"] = { source = "admin", at = 10 }
                dirty.grants["models:source"] = { source = "Admin", at = 10 }
                dirty.grants["models:time"] = { source = "admin", at = -1 }
                dirty.grants["models:fraction"] = { source = "admin", at = 1.2 }
                dirty.grants["models:grant"] = { source = "admin", at = 10, grant = "bad id" }
                dirty.claims["wrong id"] = 10
                dirty.claims.negative = -1
                expect(u._FileFromJson(dirty)).to.deepEqual(clean)
                local output = util.TableToJSON(u._FileToJson(u._FileFromJson(dirty)))
                expect(u._FileFromJson(util.JSONToTable(output, false, true))).to.deepEqual(clean)
                for index = 1, u.MaxGrants + 1 do
                    dirty.grants[string.format("perks:%04d", index)] = { source = "event", at = 0 }
                end
                local grants = u._FileFromJson(dirty).grants
                expect(table.Count(grants)).to.equal(u.MaxGrants)
                expect(grants["perks:0001"]).toNot.beNil()
                expect(grants[string.format("perks:%04d", u.MaxGrants + 1)]).to.beNil()
            end
        },
        {
            name = "Claims: past MaxClaims the oldest are pruned by time, ties by id",
            func = function()
                local u = unlocks()
                ---@type table<string, integer>
                local claims = { newest = 1000, oldest = 0, aa = 1, zz = 1 }
                for index = 1, u.MaxClaims - 2 do claims["later:" .. index] = 2 end
                local kept = u._CheckClaims(claims)
                expect(table.Count(kept)).to.equal(u.MaxClaims)
                expect(kept.newest).to.equal(1000)
                expect(kept.oldest).to.beNil()
                expect(kept.aa).to.equal(1)
                expect(kept.zz).to.beNil()
                expect(claims.oldest).to.equal(0)
            end
        },
        {
            name = "Wire: the unlocks upload and the delta extension survive encode and decode; forged counts are "
                .. "bounded",
            func = function()
                local u = unlocks()
                local claims = { ["weekly:123"] = 55 }
                local grants = { ["camos:rifle:gold"] = { source = "challenge", at = 55, grant = "weekly:123" } }
                local writer, reader = wire()
                u._EncodeUpload({ v = 1, grants = grants, claims = claims, batch = { session = 0, seq = 0 } }, writer)
                expect(u._DecodeUpload(reader)).to.deepEqual({
                    grants = { ["camos:rifle:gold"] = true }, claims = { ["weekly:123"] = true }
                })
                writer, reader = wire()
                local part = { granted = grants, revoked = { ["perks:other"] = "admin" }, claims = claims }
                u._EncodeDeltaPart(part, writer)
                expect(u._DecodeDeltaPart(reader)).to.deepEqual(part)
                expect(u.UploadMaxBytes).to.equal(53893)
                writer, reader = wire()
                writer.uint(1, 8)
                writer.uint(u.MaxGrants + 1, 16)
                expect(u._DecodeUpload(reader)).to.beNil()
                writer, reader = wire()
                writer.uint(1, 8)
                writer.uint(0, 16)
                writer.uint(u.MaxClaims + 1, 16)
                expect(u._DecodeUpload(reader)).to.beNil()
                writer, reader = wire()
                writer.uint(u.MaxDeltaGrants + 1, 8)
                local rejected = u._DecodeDeltaPart(reader)
                expect(rejected.granted or {}).to.deepEqual({})
                expect(rejected.revoked or {}).to.deepEqual({})
                expect(rejected.claims or {}).to.deepEqual({})
            end
        },
        {
            name = "Unlock file delta keeps existing metadata, records claims and changes only once per batch",
            func = function()
                local u = unlocks()
                local current = u._FileFromJson({ v = 1, claims = { earlier = 10 }, batch = { session = 7, seq = 2 },
                    grants = {
                        ["perks:keep"] = { source = "event", at = 10 },
                        ["perks:remove"] = { source = "challenge", at = 10, grant = "earlier" }
                    } })
                local delta = { session = 7, seq = 3, xp = 0, weapons = {}, claims = { reward = 20 },
                    granted = {
                        ["perks:keep"] = { source = "admin", at = 20 },
                        ["perks:add"] = { source = "challenge", at = 20, grant = "reward" }
                    }, revoked = { ["perks:remove"] = "admin", ["perks:not_owned"] = "event" } }
                local updated, applied, changes = u._ApplyDelta(current, delta)
                expect(applied).to.beTrue()
                expect(updated.grants["perks:keep"]).to.deepEqual({ source = "event", at = 10 })
                expect(updated.grants["perks:add"]).to.deepEqual(delta.granted["perks:add"])
                expect(updated.grants["perks:remove"]).to.beNil()
                expect(updated.claims).to.deepEqual({ earlier = 10, reward = 20 })
                expect(assert(changes).revoked).to.deepEqual({ ["perks:remove"] = "admin" })
                expect(assert(changes).granted).to.deepEqual({ ["perks:add"] = delta.granted["perks:add"] })
                local duplicate, repeated, repeatedChanges = u._ApplyDelta(updated, delta)
                expect(duplicate).to.equal(updated)
                expect(repeated).to.beFalse()
                expect(repeatedChanges).to.beNil()
                expect(current.grants["perks:remove"]).toNot.beNil()
                expect(current.grants["perks:add"]).to.beNil()
            end
        }
    }
}
