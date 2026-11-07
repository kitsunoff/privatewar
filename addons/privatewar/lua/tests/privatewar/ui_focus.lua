-- U-2 Layout, focus, input (notes/16-frontend-d1-proposal.md Q1, Q5, Q6; TASKS.md T-7.1 part). Pure: plain
-- rectangles and nodes, no vgui, no drawing.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.UILayoutLib
local function layout() return must(must(PW.UI).Layout) end

---@return PW.UIFocusLib
local function focus() return must(must(PW.UI).Focus) end

---@return PW.UIInputLib
local function input() return must(must(PW.UI).Input) end

---@type PW.UIColumnsSpec
local spec = { margin = 64, left = 520, right = 480, gap = 32, top = 120, bottom = 100 }

---Scale function of a design-unit scale factor: rounds to whole pixels.
---@param factor number
---@return fun(n: number): number
local function scaleOf(factor)
    return function(n) return math.floor(n * factor + 0.5) end
end

---The GLuaTest `expect` exists only inside a case function, so it is passed in.
---@param expectFn fun(value: any): any
---@param rect PW.UIRect
---@param x number
---@param y number
---@param w number
---@param h number
local function expectRect(expectFn, rect, x, y, w, h)
    expectFn({ rect.x, rect.y, rect.w, rect.h }).to.deepEqual({ x, y, w, h })
end

---@param w number
---@param h number
---@return PW.UIColumns
local function columns(w, h)
    local factor = math.min(w / 1920, h / 1080)
    return layout().Columns(w, h, spec, scaleOf(factor))
end

---One node; rect in plain numbers.
---@param id string
---@param group string
---@param x number
---@param y number
---@param extra? table<string, any>
---@return PW.UIFocusNode
local function node(id, group, x, y, extra)
    ---@type PW.UIFocusNode
    local out = { id = id, group = group, rect = { x = x, y = y, w = 100, h = 40 } }
    for key, value in pairs(extra or {}) do out[key] = value end
    return out
end

---A screen: tab bar on top (wraps), a card list below on the left, a button column below on the right.
---@return PW.UIFocusModel
local function screen()
    return focus().New({
        node("tab1", "tabs", 0, 0), node("tab2", "tabs", 120, 0), node("tab3", "tabs", 240, 0),
        node("card1", "cards", 0, 100), node("card2", "cards", 0, 150), node("card3", "cards", 0, 200),
        node("btn1", "buttons", 300, 100), node("btn2", "buttons", 300, 150)
    }, {
        tabs = { axis = "horizontal", wrap = true },
        cards = { axis = "vertical" },
        buttons = { axis = "vertical" }
    })
end

return {
    groupName = "U-2 layout, focus, input",
    cases = {
        {
            name = "Columns at 1920x1080 anchor left and right and the centre fills",
            func = function()
                local c = columns(1920, 1080)
                expectRect(expect, must(c.left), 64, 120, 520, 860)
                expectRect(expect, must(c.right), 1376, 120, 480, 860)
                expectRect(expect, c.centre, 616, 120, 728, 860)
            end
        },
        {
            name = "Columns at 1280x800 scale with the smaller factor",
            func = function()
                local c = columns(1280, 800)
                expectRect(expect, must(c.left), 43, 80, 347, 653)
                expectRect(expect, must(c.right), 917, 80, 320, 653)
                expectRect(expect, c.centre, 411, 80, 485, 653)
            end
        },
        {
            name = "Columns at 2560x1440 keep the proportions",
            func = function()
                local c = columns(2560, 1440)
                expectRect(expect, must(c.left), 85, 160, 693, 1147)
                expectRect(expect, must(c.right), 1835, 160, 640, 1147)
                expectRect(expect, c.centre, 821, 160, 971, 1147)
            end
        },
        {
            name = "Columns at 3440x1440 give the extra width to the centre",
            func = function()
                local c = columns(3440, 1440)
                expectRect(expect, must(c.left), 85, 160, 693, 1147)
                expectRect(expect, must(c.right), 2715, 160, 640, 1147)
                expectRect(expect, c.centre, 821, 160, 1851, 1147)
            end
        },
        {
            name = "Columns without a side column leave the centre the whole width",
            func = function()
                local c = layout().Columns(1000, 500, { margin = 10, gap = 5 }, scaleOf(1))
                expect(c.left).to.beNil()
                expect(c.right).to.beNil()
                expectRect(expect, c.centre, 10, 0, 980, 500)
            end
        },
        {
            name = "Focus moves down and up in a vertical list and stops at the ends",
            func = function()
                local m = screen()
                expect(focus().Move(m, "card1", "down")).to.equal("card2")
                expect(focus().Move(m, "card2", "down")).to.equal("card3")
                expect(focus().Move(m, "card3", "up")).to.equal("card2")
                local single = focus().New({ node("a", "list", 0, 0), node("b", "list", 0, 50) }, {})
                expect(focus().Move(single, "b", "down")).to.equal("b")
                expect(focus().Move(single, "a", "up")).to.equal("a")
            end
        },
        {
            name = "Focus wraps in the tab bar",
            func = function()
                local m = screen()
                expect(focus().Move(m, "tab3", "right")).to.equal("tab1")
                expect(focus().Move(m, "tab1", "left")).to.equal("tab3")
                expect(focus().Move(m, "tab1", "right")).to.equal("tab2")
            end
        },
        {
            name = "Focus skips disabled nodes",
            func = function()
                local m = focus().New({
                    node("a", "list", 0, 0), node("b", "list", 0, 50, { disabled = true }), node("c", "list", 0, 100)
                }, {})
                expect(focus().Move(m, "a", "down")).to.equal("c")
                expect(focus().Move(m, "c", "up")).to.equal("a")
                local tail = focus().New({ node("a", "list", 0, 0), node("b", "list", 0, 50, { disabled = true }) }, {})
                expect(focus().Move(tail, "a", "down")).to.equal("a")
            end
        },
        {
            name = "Focus stops on locked nodes, which cannot be activated",
            func = function()
                local m = focus().New({
                    node("a", "list", 0, 0), node("b", "list", 0, 50, { locked = true }), node("c", "list", 0, 100)
                }, {})
                expect(focus().Move(m, "a", "down")).to.equal("b")
                expect(focus().Activatable(m, "b")).to.beFalse()
                expect(focus().Activatable(m, "a")).to.beTrue()
                local id, event = focus().Apply(m, "b", "accept")
                expect(id).to.equal("b")
                expect(event).to.equal("locked")
                local _, event2 = focus().Apply(m, "a", "accept")
                expect(event2).to.equal("accept")
            end
        },
        {
            name = "Focus crosses to the neighbour group by geometry",
            func = function()
                local m = screen()
                expect(focus().Move(m, "card2", "right")).to.equal("btn2")
                expect(focus().Move(m, "btn1", "left")).to.equal("card1")
                expect(focus().Move(m, "tab2", "down")).to.equal("card1")
                expect(focus().Move(m, "card1", "up")).to.equal("tab1")
                local fresh = screen()
                expect(focus().Move(fresh, "tab3", "down")).to.equal("btn1")
            end
        },
        {
            name = "Focus restores the last focused node of the group it enters",
            func = function()
                local m = screen()
                focus().Set(m, "card3")
                expect(focus().Move(m, "btn1", "left")).to.equal("card3")
                expect(focus().Move(m, "card3", "up")).to.equal("card2")
                expect(focus().Move(m, "tab1", "down")).to.equal("card2")
            end
        },
        {
            name = "Focus stays when there is no candidate",
            func = function()
                local m = screen()
                expect(focus().Move(m, "card1", "left")).to.equal("card1")
                expect(focus().Move(m, "tab1", "up")).to.equal("tab1")
                expect(focus().Move(m, "btn2", "right")).to.equal("btn2")
                expect(focus().Move(m, "unknown", "down")).to.equal("unknown")
            end
        },
        {
            name = "Every input action has a keyboard key and a controller code",
            func = function()
                local names = { "up", "down", "left", "right", "accept", "back", "tab_prev", "tab_next",
                    "secondary", "tertiary", "page_up", "page_down", "settings" }
                for _, name in ipairs(names) do
                    local def = must(input().Actions[name])
                    expect(#def.keyboard > 0).to.beTrue()
                    expect(#def.controller > 0).to.beTrue()
                    expect(isstring(def.cap) and def.cap ~= "").to.beTrue()
                    expect(isstring(def.pad) and def.pad ~= "").to.beTrue()
                    expect(input().ActionOf(def.keyboard[1])).to.equal(name)
                    expect(input().ActionOf(def.controller[1])).to.equal(name)
                end
            end
        },
        {
            name = "The input device switches on the last input",
            func = function()
                local state = input().New()
                expect(input().Device(state)).to.equal("keyboard")
                expect(input().Press(state, KEY_XBUTTON_A)).to.equal("accept")
                expect(input().Device(state)).to.equal("controller")
                expect(input().Press(state, KEY_W)).to.equal("up")
                expect(input().Device(state)).to.equal("keyboard")
                expect(input().Press(state, KEY_XBUTTON_B)).to.equal("back")
                input().NoteMouse(state)
                expect(input().Device(state)).to.equal("mouse")
                expect(input().Hint(state, "back").label).to.equal("Esc")
                expect(input().Press(state, KEY_NONE)).to.beNil()
                expect(input().Device(state)).to.equal("mouse")
            end
        },
        {
            name = "The pw_ui_hints override fixes the hint device",
            func = function()
                local state = input().New()
                input().Press(state, KEY_XBUTTON_B)
                expect(input().Hint(state, "back", "auto")).to.deepEqual({ device = "controller", label = "B" })
                expect(input().Hint(state, "back", "keyboard")).to.deepEqual({ device = "keyboard", label = "Esc" })
                input().Press(state, KEY_ESCAPE)
                expect(input().Hint(state, "back")).to.deepEqual({ device = "keyboard", label = "Esc" })
                expect(input().Hint(state, "back", "gamepad")).to.deepEqual({ device = "controller", label = "B" })
                expect(input().Hint(state, "back", "bogus")).to.deepEqual({ device = "keyboard", label = "Esc" })
            end
        }
    }
}
