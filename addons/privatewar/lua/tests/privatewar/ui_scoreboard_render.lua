-- Exercise the real shared table renderer with fake surface/panel boundaries; never replaces live vgui.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "board render dependency is missing")
    return value
end

---@return table<string, any>
local function fixture()
    local f = { measured = 0, drawn = 0, class = {} } --[[@as table<string, any>]]
    local ui = must(PW.UI)
    local env = setmetatable({ PW = { UI = { Board = ui.Board, Style = ui.Style,
        Draw = { Px = function(value) return value end, Rect = function() end },
        Font = function(step) return step end } },
        surface = { SetFont = function() end, GetTextSize = function(text)
            f.measured = f.measured + 1
            return #text * 10
        end }, draw = { SimpleText = function() f.drawn = f.drawn + 1 end },
        IsValid = function(value) return value ~= nil end,
        vgui = { Register = function(_, class) f.class = class end } }, { __index = _G })
    local source = must(CompileFile("privatewar/modules/ui_kit/cl_board.lua"))
    setfenv(source, env)()
    local panel = setmetatable({ width = 1000, height = 0, SetMouseInputEnabled = function() end,
        SetKeyboardInputEnabled = function() end, LocalToScreen = function() return 0, 0 end,
        SetTall = function(self, height) self.height = height end,
        InvalidateLayout = function(self) f.class.PerformLayout(self, self.width) end }, { __index = f.class })
    f.panel = panel
    f.class.Init(panel)
    return f
end

return {
    groupName = "PW shared result and live table renderer",
    cases = {
        {
            name = "Paint: zero text measurement after layout, and large rosters draw only viewport rows",
            func = function()
                local f = fixture()
                ---@type PW.UIBoardRow[]
                local rows = {}
                for index = 1, 128 do
                    rows[index] = { id = index, name = "Long player name " .. index, bot = true, me = index == 1,
                        team = 1, kills = index, deaths = 2, score = index * 100 }
                end
                f.panel:SetSections({ { id = 1, title = "BLUE", relation = "friendly", score = 12, rows = rows } })
                f.panel:SetViewport({ LocalToScreen = function() return 0, 0 end, GetTall = function() return 480 end })
                expect(f.measured > 0).to.equal(true)
                local measured = f.measured
                f.class.Paint(f.panel, 1000, f.panel.height)
                expect(f.measured).to.equal(measured)
                expect(f.drawn < 100).to.equal(true)
                expect(f.panel.height > 480).to.equal(true)
            end
        },
        {
            name = "Refresh and resize: same table panel reuses result data and recalculates fitted labels",
            func = function()
                local f = fixture()
                local section = { id = 0, title = "PLAYERS", relation = "neutral",
                    rows = { { id = 1, name = string.rep("Name", 100), bot = false, me = true,
                        team = 1000, kills = 5, deaths = 1, score = 500 } } }
                f.panel:SetSections({ section }, "SCORE")
                local first = f.panel.lines[2].name --[[@as string]]
                f.panel.width = 700
                f.class.PerformLayout(f.panel, 700)
                expect(#f.panel.lines[2].name < #first).to.equal(true)
                expect(f.panel.lines[2].kills).to.equal("5")
                section.rows[1].kills = 8
                f.panel:SetSections({ section }, "ROUND WINS")
                expect(f.panel.lines[2].kills).to.equal("8")
                expect(f.panel.label).to.equal("ROUND WINS")
            end
        }
    }
}
