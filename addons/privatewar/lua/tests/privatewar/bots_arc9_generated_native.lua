-- Mounted evidence: normal adapter Apply/PrepareForBot and actual ARC9 camo state. No private addon calls.

---@class PW.GeneratedArc9NativeTest
---@field bot? Player
---@field started? boolean
---@field saved? table<string, string>

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value")
    return value
end

---@param entry PW.BotClassEntry
---@param bot Player
---@return integer camos
local function apply(entry, bot)
    local builds = (entry.loadout.builds or {}) --[[@as table<string, PW.Build>]]
    local camos = 0
    for slot, build in pairs(builds) do
        local class = entry.loadout[slot] --[[@as string]]
        ---@type Weapon?
        local wep = bot:GetWeapon(class)
        if not IsValid(wep) then wep = PW.WeaponAmmo.Give(bot, class) end
        assert(IsValid(wep), "failed to give generated firearm: " .. class)
        wep = must(wep)
        local adapter = must(PW.Adapters.For(wep))
        local stuck = PW.Adapters.Call(adapter, "Apply", wep, table.Copy(build)) --[[@as PW.Build]]
        PW.Adapters.Call(adapter, "PrepareForBot", bot, wep)
        for id, option in pairs(build) do
            local att = isstring(option) and must(ARC9).GetAttTable(option --[[@as string]]) or nil
            if att ~= nil and isstring(att.CustomCamoTexture) then
                assert(stuck[id] == option, "actual camo did not stick: " .. tostring(option))
                local texture = (wep --[[@as PW.Arc9Weapon]]):GetProcessedValue("CustomCamoTexture", true)
                assert(texture == att.CustomCamoTexture, "ARC9 processed texture did not match attachment")
                camos = camos + 1
            end
        end
        -- ARC9 PostModify has deferred callbacks. Keep instances alive until those have drained, not same-tick Remove.
    end
    return camos
end

return {
    groupName = "PW generated ARC9 mounted",
    skip = function()
        if PW.Arc9BotLoadouts ~= nil and ARC9 ~= nil then return false end
        print("[PW] Generated ARC9 mounted tests skipped: ARC9 or integration not installed")
        return true
    end,
    cases = {
        {
            name = "Mounted: stable cache, current bans/budget/settings, no progression, real bot builds and camo",
            async = true,
            timeout = 90,
            ---@param test PW.GeneratedArc9NativeTest
            cleanup = function(test)
                if test.bot ~= nil and IsValid(test.bot) then test.bot:Kick("generated tests cleanup") end
                if test.started and must(PW.Match).GetPhase() ~= "LOBBY" then
                    must(PW.Match).Abort("generated tests cleanup")
                end
                for name, value in pairs(test.saved or {}) do must(GetConVar(name)):SetString(value) end
            end,
            ---@param test PW.GeneratedArc9NativeTest
            func = function(test)
                local lib = must(PW.Arc9BotLoadouts)
                local deadline = CurTime() + 60
                ---@type table<string, string>
                test.saved = {}
                for _, name in ipairs({ "pw_prematch_timeout", "pw_countdown" }) do
                    test.saved[name] = must(GetConVar(name)):GetString()
                    must(GetConVar(name)):SetString("0")
                end
                local match = must(PW.Match)
                expect(match.GetPhase()).to.equal("LOBBY")
                test.started = true
                expect(match.Start(must(PW.Modes.Get("tdm")))).to.beTrue()
                local function wait()
                    local state = PW._Arc9BotLoadouts
                    if state == nil or state.status == "working" or match.GetPhase() ~= "LIVE" then
                        assert(CurTime() < deadline, "generation not ready within 60 seconds")
                        timer.Simple(0.05, wait)
                        return
                    end
                    expect(state.status).to.equal("ready")
                    expect(#state.entries).to.equal(18)
                    local original = table.Copy(state.entries)
                    lib.Start()
                    expect(PW._Arc9BotLoadouts == state).to.beTrue()
                    local invalid = table.Copy(state.entries[1]) --[[@as PW.BotClassEntry]]
                    invalid.loadout.builds = { primary = { invalid_slot = "invalid_camo" } }
                    expect(lib.Legal(invalid)).to.beFalse()
                    local bot = player.CreateNextBot("PW generated loadout test")
                    assert(IsValid(bot), "no bot slot")
                    test.bot = bot
                    bot:Spawn()
                    local setting, locked = PW.Setting, 0
                    local enabled, budget = true, 10
                    ---@type table<string, boolean>
                    local banned = {}
                    stub(PW, "Setting").with(function(id)
                        if id == "bots_arc9_loadouts.generate" then return enabled end
                        if id == "loadout.budget" then return budget end
                        if id == "loadout.bannedweapons" then return banned end
                        return setting(id)
                    end)
                    local progression = must(PW.Progression)
                    stub(progression, "IsUnlocked").with(function() locked = locked + 1 return false end)
                    local bots = must(PW.BotLoadouts)
                    stub(bots, "Harvest").with(function() end) -- isolate bot validation from human upload repair
                    ---@return integer
                    local function generatedCount()
                        local n = 0
                        for _, entry in ipairs(bots.PoolFor(bot)) do
                            if entry.source == "generated" then n = n + 1 end
                        end
                        return n
                    end
                    local ok, problem = pcall(function()
                        expect(generatedCount() > 0).to.beTrue()
                        enabled = false
                        expect(generatedCount()).to.equal(0)
                        enabled, budget = true, 1
                        expect(generatedCount()).to.equal(0)
                        budget = 10
                        for _, entry in ipairs(state.entries) do
                            local firearm = (entry.loadout.primary or entry.loadout.secondary) --[[@as string]]
                            banned[firearm] = true
                        end
                        expect(generatedCount()).to.equal(0)
                        expect(locked).to.equal(0)
                    end)
                    if not ok then bot:Kick("generated tests failed") error(problem) end
                    banned = {}
                    local index, camos = 1, 0
                    local function nextBuild()
                        local entry = state.entries[index]
                        if entry ~= nil then
                            local success, count = pcall(apply, entry, bot)
                            if not success then bot:Kick("generated apply failed") error(count) end
                            camos, index = camos + count, index + 1
                            timer.Simple(0, nextBuild)
                            return
                        end
                        expect(camos > 0).to.beTrue()
                        expect(state.entries).to.deepEqual(original)
                        print(string.format("[PW] ARC9 generated mounted: %d actual camos, %.2f ms max slice",
                            camos, state.maxFrameSeconds * 1000))
                        -- The public match owns the body lifetime; let ARC9's 0.1 s callbacks finish before cleanup.
                        timer.Simple(0.5, function()
                            match.Abort("generated tests done")
                            done()
                        end)
                    end
                    timer.Simple(0.3, nextBuild) -- let PlayerInitialSpawn/Spawn finish before giving native weapons
                end
                wait()
            end
        }
    }
}
