-- Execute the real client Gather glue in an isolated engine boundary; no renderer or live UI is replaced.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "postmatch extension dependency is missing")
    return value
end

---@class PW.PostmatchExtensionFixture
---@field pm PW.UIPostmatchLib
---@field hooks table<string, function>
---@field timer function
---@field phase PW.PhaseName
---@field root? table
---@field gathered integer
---@field rebuilt integer
---@field enabled boolean
---@field listener? fun(data: PW.UIPostmatchData, ownId: integer)

---@param progression boolean
---@param summary boolean
---@return PW.PostmatchExtensionFixture
local function fixture(progression, summary)
    local ui = must(PW.UI)
    local pm = table.Copy(must(ui.Postmatch)) -- pure functions only; no registry definition is copied
    local f = { pm = pm, hooks = {}, timer = function() end, phase = "LOBBY", gathered = 0,
        rebuilt = 0, enabled = true } --[[@as PW.PostmatchExtensionFixture]]
    local me = { UserID = function() return 7 end, Team = function() return 1000 end,
        Nick = function() return "Fixture" end, IsBot = function() return false end,
        Frags = function() return 2 end, Deaths = function() return 1 end,
        GetNW2Bool = function() return false end }
    local kit = { Postmatch = pm, CurrentRoot = function() return f.root end }
    local prog = { GetProgress = function() return 0, 100 end,
        _Params = function() return { xpBase = 100, xpExp = 1 } end, _XpToNext = function() return 100 end }
    local api = { UI = kit, Modules = { Get = function(id)
        return { IsValid = function() return id == "ui_kit" and f.enabled or (id == "progression" and progression) end }
    end }, Registries = {}, Progression = prog, Phase = { GetPhase = function() return f.phase end },
        Setting = function() end, Notify = function(name, data, ownId)
            if name ~= "PW_PostmatchGathered" then return end
            f.gathered = f.gathered + 1
            if f.listener ~= nil then f.listener(data, ownId) end
        end }
    local env = setmetatable({ PW = api, LocalPlayer = function() return me end,
        player = { GetAll = function() return { me } end },
        GetGlobal2Int = function(_, default) return default end,
        GetGlobal2Bool = function(_, default) return default end,
        hook = { Add = function(name, _, callback) f.hooks[name] = callback end },
        timer = { Create = function(_, _, _, callback) f.timer = callback end },
        concommand = { Add = function() end } }, { __index = _G })
    local source = must(CompileFile("privatewar/modules/ui_kit/cl_postmatch.lua"))
    setfenv(source, env)()
    if summary then
        f.hooks.PW_ProgressionSummary({ levelBefore = 1, levelAfter = 1, xp = 0, medals = {}, weapons = {} })
    end
    return f
end

return {
    groupName = "PW postmatch extension integration",
    cases = {
        {
            name = "Postmatch Gather: extension fires once on complete data for progression off"
                .. " no summary and full summary",
            func = function()
                for _, flags in ipairs({ { false, false }, { true, false }, { true, true } }) do
                    local f = fixture(flags[1], flags[2])
                    f.listener = function(data, ownId)
                        expect(ownId).to.equal(7)
                        expect(data.map).to.equal(game.GetMap())
                        expect(data.sections[1].rows[1].kills).to.equal(2)
                        expect(#data.steps).to.equal(flags[1] and flags[2] and 1 or 0)
                        data.result.subtitle = "EXTENSION"
                        data.scoreLabel = "ROUND WINS"
                    end
                    local data = must(f.pm.Gather)()
                    expect(f.gathered).to.equal(1)
                    expect(data.result.subtitle).to.equal("EXTENSION")
                    expect(data.scoreLabel).to.equal("ROUND WINS")
                end
            end
        },
        {
            name = "Postmatch Gather: missing extension preserves ordinary kills placement score and default labels",
            func = function()
                local f = fixture(false, false)
                local data = must(f.pm.Gather)()
                expect(f.gathered).to.equal(1)
                expect(data.result.subtitle).to.equal("1ST OF 1")
                expect(data.sections[1].rows[1].score).to.equal(0)
                expect(data.scoreLabel).to.beNil()
            end
        },
        {
            name = "Postmatch late data: rebuild only an enabled open POSTMATCH root, never reopen or poll Gather",
            func = function()
                local f = fixture(false, false)
                expect(f.hooks.PW_PostmatchDataChanged).to.exist()
                local changed = must(f.hooks.PW_PostmatchDataChanged)
                f.phase = "POSTMATCH"
                changed()
                expect(f.rebuilt).to.equal(0)
                f.root = { rootId = "other", Rebuild = function() f.rebuilt = f.rebuilt + 1 end }
                changed()
                expect(f.rebuilt).to.equal(0)
                f.root.rootId = f.pm.RootId
                changed()
                expect(f.rebuilt).to.equal(1)
                f.timer()
                expect(f.gathered).to.equal(0)
                expect(f.rebuilt).to.equal(1)
                f.phase = "LIVE"
                changed()
                f.phase, f.enabled = "POSTMATCH", false
                changed()
                expect(f.rebuilt).to.equal(1)
            end
        }
    }
}
