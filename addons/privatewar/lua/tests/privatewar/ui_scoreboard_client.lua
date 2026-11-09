-- Execute the actual client hooks with isolated engine boundaries. No game, input or live UI is changed.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "scoreboard client dependency is missing")
    return value
end

---@return table<string, any>
local function fixture()
    ---@type table<string, function>
    local hooks = {}
    local f = { hooks = hooks, phase = "LIVE", enabled = true, focused = true, menu = false, console = false, now = 1,
        creates = 0, updates = 0, removes = 0, gathers = 0, scroll = 0, held = true }
    local sb = table.Copy(must(must(PW.UI).Scoreboard))
    f.sb = sb
    local me = { Team = function() return 1 end, UserID = function() return 7 end }
    local api = { UI = { Scoreboard = sb, ScaleFor = must(PW.UI).ScaleFor,
        CurrentRoot = function() return f.root end,
        Postmatch = { Rows = function()
            f.gathers = f.gathers + 1
            return { { id = 7, name = "Me", team = 1, bot = false, me = true, kills = 3, deaths = 1, score = 500 } }
        end } }, Modules = { Get = function() return { IsValid = function() return f.enabled end } end },
        Phase = { GetPhase = function() return f.phase end }, Notify = function() end }
    sb.Create = function()
        f.creates = f.creates + 1
        if f.fail then error("fixture create failure") end
        local panel = { valid = true, Update = function() f.updates = f.updates + 1 end,
            Scroll = function(_, delta) f.scroll = f.scroll + delta end,
            GetViewportHeight = function() return 500 end }
        panel.Remove = function() panel.valid = false f.removes = f.removes + 1 end
        if f.failUpdate then panel.Update = function() error("fixture update failure") end end
        return panel
    end
    ---@param value any
    ---@return boolean
    local function valid(value)
        return value ~= nil and (value --[[@as table<string, any>]]).valid ~= false
    end
    ---@param name string
    ---@param _ string
    ---@param fn function
    local function addHook(name, _, fn) hooks[name] = fn end
    local env = setmetatable({ PW = api, LocalPlayer = function() return me end, IsValid = valid,
        RealTime = function() return f.now end, IsFirstTimePredicted = function() return true end,
        GetConVar = function() return nil end, GetGlobal2Int = function(key, default)
            if key == "pw_teams" then return 2 end
            if key == "pw_dom_score_1" then return 123 end
            return default
        end, GetGlobal2String = function(key, default)
            return key == "pw_hud_score" and "pw_dom_score_" or default
        end, GetGlobal2Float = function(_, default) return default end,
        system = { HasFocus = function() return f.focused end },
        gui = { IsGameUIVisible = function() return f.menu end, IsConsoleVisible = function() return f.console end },
        input = { LookupBinding = function() return "TAB" end, GetKeyCode = function() return KEY_TAB end,
            IsButtonDown = function() return f.held end },
        hook = { Add = addHook }, ErrorNoHalt = function() end }, { __index = _G })
    local source = must(CompileFile("privatewar/modules/ui_kit/cl_scoreboard.lua"))
    setfenv(source, env)()
    f.reload = function() setfenv(source, env)() end
    f.me, f.api = me, api
    return f
end

return {
    groupName = "PW scoreboard client integration",
    cases = {
        {
            name = "Tab hooks: repeated show is idempotent, hide removes only the board, no polling while closed",
            func = function()
                local f = fixture()
                f.hooks.Think()
                expect(f.gathers).to.equal(0)
                expect(f.hooks.ScoreboardShow()).to.equal(true)
                expect(f.hooks.ScoreboardShow()).to.equal(true)
                expect(f.creates).to.equal(1)
                expect(f.sb.IsOpen()).to.equal(true)
                f.hooks.ScoreboardHide()
                expect(f.sb.IsOpen()).to.equal(false)
                expect(f.removes).to.equal(1)
                f.now = 2
                f.hooks.Think()
                expect(f.gathers).to.equal(1)
            end
        },
        {
            name = "Live Gather uses pw_teams and the mode score prefix, never terminal result team count",
            func = function()
                local f = fixture()
                local data = f.sb.Gather() --[[@as PW.UIScoreboardData]]
                expect(data.sections[1].score).to.equal(123)
                expect(data.sections[1].rows[1].kills).to.equal(3)
                expect(data.sections[1].rows[1].deaths).to.equal(1)
                expect(data.sections[1].rows[1].me).to.equal(true)
            end
        },
        {
            name = "Refresh is bounded to four per second and only while the board is visible",
            func = function()
                local f = fixture()
                f.hooks.ScoreboardShow()
                for _ = 1, 10 do f.hooks.Think() end
                expect(f.gathers).to.equal(1)
                f.now = 1.3
                f.hooks.Think()
                expect(f.gathers).to.equal(2)
                expect(f.creates).to.equal(1)
            end
        },
        {
            name = "Lifecycle: release, lost focus, native menu, pause, disable and phase exit remove immediately",
            func = function()
                for _, change in ipairs({ { held = false }, { focused = false }, { menu = true }, { console = true },
                    { root = { rootId = "pause" } }, { enabled = false }, { phase = "POSTMATCH" } }) do
                    local f = fixture()
                    f.hooks.ScoreboardShow()
                    for key, value in pairs(change) do f[key] = value end
                    f.hooks.Think()
                    expect(f.sb.IsOpen()).to.equal(false)
                    expect(f.removes).to.equal(1)
                end
                local f = fixture()
                f.hooks.ScoreboardShow()
                f.hooks.PW_PhaseChanged("POSTMATCH")
                expect(f.sb.IsOpen()).to.equal(false)
            end
        },
        {
            name = "Native View button holds the board; d-pad scrolls without opening or replacing a PWRoot",
            func = function()
                local f = fixture()
                f.root = { rootId = "class" }
                local root = f.root
                f.hooks.PlayerButtonDown(f.me, KEY_XBUTTON_BACK)
                expect(f.sb.IsOpen()).to.equal(true)
                f.hooks.PlayerButtonDown(f.me, KEY_XBUTTON_DOWN)
                expect(f.scroll > 0).to.equal(true)
                f.hooks.PlayerButtonUp(f.me, KEY_XBUTTON_BACK)
                expect(f.sb.IsOpen()).to.equal(false)
                expect(f.root).to.equal(root)
                f.hooks.PlayerButtonDown(f.me, KEY_XBUTTON_BACK)
                local data = f.sb.Gather() --[[@as PW.UIScoreboardData]]
                expect(data.gamepad).to.equal(true)
                f.held = false -- missed release hook is caught for joystick buttons too
                f.hooks.Think()
                expect(f.sb.IsOpen()).to.equal(false)
            end
        },
        {
            name = "Death picker keyboard capture: raw bound key opens and scrolls the overlay"
                .. " without root replacement",
            func = function()
                local f = fixture()
                f.root = { rootId = "class" }
                local root = f.root
                expect(f.sb.HandleKey(KEY_TAB)).to.equal(true)
                expect(f.sb.IsOpen()).to.equal(true)
                expect(f.sb.HandleKey(KEY_DOWN)).to.equal(true)
                expect(f.scroll > 0).to.equal(true)
                expect(f.sb.HandleKey(KEY_W)).to.equal(false)
                expect(f.root).to.equal(root)
                f.held = false
                f.hooks.Think()
                expect(f.sb.IsOpen()).to.equal(false)
            end
        },
        {
            name = "Alternative binding is tracked from the actual event; scrolling consumes only its own binds",
            func = function()
                local f = fixture()
                f.hooks.PlayerBindPress(f.me, "+showscores", true, KEY_F)
                expect(f.hooks.ScoreboardShow()).to.equal(true)
                expect(f.hooks.PlayerBindPress(f.me, "noclip", true, KEY_XBUTTON_DOWN)).to.equal(true)
                expect(f.hooks.PlayerBindPress(f.me, "+forward", true, KEY_W)).to.equal(nil)
                f.held = false
                f.hooks.Think()
                expect(f.sb.IsOpen()).to.equal(false)
            end
        },
        {
            name = "Failure and disabled kit: do not suppress the base scoreboard or leave a panel behind",
            func = function()
                local f = fixture()
                f.fail = true
                expect(f.hooks.ScoreboardShow()).to.equal(nil)
                expect(f.sb.IsOpen()).to.equal(false)
                local disabled = fixture()
                disabled.enabled = false
                expect(disabled.hooks.ScoreboardShow()).to.equal(nil)
                expect(disabled.creates).to.equal(0)
                local update = fixture()
                update.failUpdate = true
                expect(update.hooks.ScoreboardShow()).to.equal(nil)
                expect(update.removes).to.equal(1)
                expect(update.sb.IsOpen()).to.equal(false)
            end
        },
        {
            name = "Infection: own published round wins only, no fabricated live personal leaderboard",
            func = function()
                local module = {} --[[@as table<string, any>]]
                local api = { Infection = { View = { active = true, personalWins = 2, round = 3 } },
                    Phase = { GetPhase = function() return "LIVE" end } }
                local env = setmetatable({ PW = api, MODULE = module, SERVER = false,
                    include = function() end }, { __index = _G })
                local source = must(CompileFile("privatewar/modules/pw_infection_rules/shared.lua"))
                setfenv(source, env)()
                expect(module.PW_ScoreboardGathered ~= nil).to.equal(true)
                local data = { sections = { { id = 1, title = "TEAM 1", score = 3, rows = {} },
                    { id = 2, title = "TEAM 2", score = 1, rows = {} } } }
                module:PW_ScoreboardGathered(data, 7)
                expect(data.note).to.equal("ROUND 3  |  YOUR ROUND WINS 2  |  Full standings at match end")
                expect(data.sections[1].title).to.equal("SURVIVORS")
                expect(data.sections[2].title).to.equal("INFECTED")
                expect(data.sections[1].score).to.equal(nil)
                expect(data.sections[2].score).to.equal(nil)
                expect(#data.sections[1].rows).to.equal(0)
            end
        },
        {
            name = "Reload and shutdown: old panel is removed and repeated cleanup is harmless",
            func = function()
                local f = fixture()
                f.hooks.ScoreboardShow()
                f.reload()
                expect(f.sb.IsOpen()).to.equal(false)
                expect(f.removes).to.equal(1)
                f.hooks.ScoreboardShow()
                f.hooks.ShutDown()
                f.hooks.ShutDown()
                expect(f.removes).to.equal(2)
                expect(f.sb.IsOpen()).to.equal(false)
            end
        }
    }
}
