---@return table<string, any>
local function fixture()
    local source = assert(CompileFile("privatewar/hud/stims.lua"), "stim HUD element is not implemented")
    ---@type table<string, function>
    local hooks = {}
    ---@type table[]
    local draws = {}
    local state = {
        now = 10, valid = true, builds = 0, marks = {}, draws = draws, class = {}
    } --[[@as table<string, any>]]
    local ply = {
        GetNW2Float = function(_, key, default) return state.marks[key] or default end
    }
    local stims = assert(rawget(PW, "Stims"))
    local env = setmetatable({
        CLIENT = true, HUDELEMENT = state.class,
        LocalPlayer = function() return ply end,
        CurTime = function() return state.now end,
        PW = {
            HUD = {
                PlayerVisible = function() return state.valid end,
                X = function(value) return value end, Y = function(value) return value end
            },
            UI = { Style = { text = Color(255, 255, 255) }, FontName = function(size) return size end },
            Modules = { Get = function() return { IsValid = function() return true end } end },
            HookFor = function(_, name, fn) hooks[name --[[@as string]]] = fn --[[@as function]] end,
            Stims = {
                _EffectLines = function(now, marks)
                    state.builds = state.builds + 1
                    return stims._EffectLines(now, marks)
                end
            }
        },
        draw = { SimpleText = function(text, font, x, y)
            draws[#draws + 1] = {
                text = text --[[@as string]], font = font --[[@as string]],
                x = x --[[@as number]], y = y --[[@as number]]
            }
        end }
    }, { __index = _G })
    setfenv(source, env)()
    state.step = function()
        assert(hooks.Think)(state.class)
        state.class.Draw(state.class)
    end
    return state
end

return {
    groupName = "PW live stim HUD",
    cases = {
        {
            name = "Stims HUD lines are cached until the effect state changes",
            func = function()
                local f = fixture()
                expect(f.class.Order).to.equal(31)
                expect(f.class.Phases).to.deepEqual({ "LIVE" })
                f.marks.pw_stim_speed_until = 14.21
                f.marks.pw_stim_heal_until = 11
                f.step()
                expect(f.draws[1].text).to.equal("SPEED 4.3")
                expect(f.draws[2]).to.deepEqual({ text = "HEALING", font = "small", x = 1880, y = 830 })
                expect(f.draws[1].y < 830).to.beTrue()
                expect(f.builds).to.equal(1)
                f.now = 10.005
                f.step()
                expect(f.builds).to.equal(1)
                f.now = 10.02
                f.step()
                expect(f.builds).to.equal(2)
                expect(f.draws[5].text).to.equal("SPEED 4.2")
                f.marks.pw_stim_heal_until = 12 -- a different unchanged visible label doesn't require a rebuild
                f.step()
                expect(f.builds).to.equal(2)
            end
        },
        {
            name = "Stims HUD draws nothing without active effects",
            func = function()
                local f = fixture()
                f.step()
                expect(#f.draws).to.equal(0)
                f.marks.pw_stim_armor_until = 11
                f.step()
                expect(f.draws[1].text).to.equal("ARMOR")
                f.valid = false
                f.step()
                expect(#f.draws).to.equal(1)
                f.valid, f.now = true, 11
                f.step()
                expect(#f.draws).to.equal(1)
            end
        }
    }
}
