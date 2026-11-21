-- Run the real client panel callbacks with a fake VGUI boundary; these cases also run on the server.
---@param path string
---@param env table
local function loadGlue(path, env)
    local chunk = assert(CompileFile("privatewar/modules/" .. path))
    setfenv(chunk, env)()
end

---@class PW.HintClickFixture
---@field bar any
---@field root any
---@field calls string[]
---@field mouse { x: number, y: number }
---@field env any
---@field standalone fun(): any
---@field setOverride fun(value: string)

---@return PW.HintClickFixture
local function fixture()
    local noop = function() end
    ---@type table<string, table<string, function>>
    local classes = {}
    ---@type string[]
    local calls = {}
    local mouse, override = { x = 100, y = 40 }, "auto"
    local ui = assert(PW.UI)
    local kit = setmetatable({
        FontName = function(name) return name end,
        HintOverride = function() return override end,
        Style = {},
        Draw = { Rect = noop, Lock = noop, Px = function(n) return n end,
            KeyCap = function(_, _, _, y) return 24, math.floor(y - 12), 24 end },
        Settings = { Open = function() calls[#calls + 1] = "settings" return false end }
    }, { __index = ui })
    ---@param name string
    ---@return any
    local function panel(name)
        return setmetatable({
            visible = true, captured = false, width = 800, height = 80,
            SetSize = noop, SetPos = noop, MakePopup = noop, SetKeyboardInputEnabled = noop,
            SetMouseInputEnabled = noop, InvalidateLayout = noop,
            SetCard = function(self, card) self.card = card end,
            SetText = noop, SetVariant = noop,
            GetSize = function(self) return self.width, self.height end,
            CursorPos = function() return mouse.x, mouse.y end,
            IsVisible = function(self) return self.visible end,
            IsHovered = function(self) return self.visible and mouse.y >= 0 and mouse.y < self.height end,
            MouseCapture = function(self, on) self.captured = on end
        }, { __index = classes[name] })
    end
    ---@param name string
    ---@param class table<string, function>
    local function register(name, class) classes[name] = class end
    ---@type any
    local env = setmetatable({
        PW = { UI = kit, Registries = {}, Phase = { GetPhase = function() return "LOBBY" end } },
        vgui = { Register = register, Create = function(name)
            local child = panel(name)
            if child.Init ~= nil then child:Init() end
            return child
        end },
        IsValid = function(value) return type(value) == "table" end,
        draw = { SimpleText = function(label) return #label * 8, 20 end },
        gui = { MouseX = function() return mouse.x end, MouseY = function() return mouse.y end },
        hook = { Remove = noop }, concommand = { Add = noop }, FrameNumber = function() return 1 end,
        ScrW = function() return 800 end, ScrH = function() return 600 end
    }, { __index = _G })
    for _, fileName in ipairs({ "cl_components.lua", "cl_hint_bar.lua", "cl_root.lua" }) do
        loadGlue("ui_kit/" .. fileName, env)
    end
    local root = env.vgui.Create("PWRoot") --[[@as any]]
    root.ActFocus = function(_, action) calls[#calls + 1] = action --[[@as string]] end
    root.RefreshFocus = noop
    return {
        bar = root.hintBar --[[@as any]], root = root, calls = calls, mouse = mouse, env = env, standalone = function()
            return env.vgui.Create("PWHintBar")
        end,
        setOverride = function(value) override = value end
    }
end

---@param f PW.HintClickFixture
---@return any, integer[]
local function voteFixture(f)
    local env = f.env
    ---@type integer[]
    local casts = {}
    local receive = function() end
    local options = { { mode = "test", name = "Test", map = "gm_one", votes = 0 },
        { mode = "test", name = "Test", map = "gm_two", votes = 0 } }
    local state = { options = options, mine = 0, canPick = false }
    env.MODULE = {}
    env.PW.Phase = { GetPhase = function() return "VOTE" end, Remaining = function() return 15 end }
    env.PW.Modules = { Get = function() return { IsValid = function() return true end } end }
    env.PW.Vote = { _Decode = function() return state end }
    env.player = { GetHumans = function() return {} end }
    env.net = {
        Receive = function(_, callback) receive = callback end, Start = function() end,
        WriteUInt = function(index) casts[#casts + 1] = index --[[@as integer]] end, SendToServer = function() end
    }
    for _, name in ipairs({ "sh_cards.lua", "cl_init.lua" }) do
        loadGlue("vote/" .. name, env)
    end
    env.PW.Vote.Open()
    receive()
    return env.PW.Vote._View, casts
end

local function show(bar, entries)
    bar:SetEntries(entries)
    bar:Think()
    bar:Paint(bar.width, bar.height)
end

local function click(bar, code)
    bar:OnMousePressed(code)
    bar:OnMouseReleased(code)
end

return {
    groupName = "PW clickable hint bar",
    cases = {
        {
            name = "Select, Save, Settings and Back clicks use the same root actions as keyboard and controller",
            func = function()
                local f = fixture()
                local bar, root = f.bar, f.root
                -- Back exercises the native router pop without closing a real menu.
                root.model = { stacks = { [""] = { "root", "child" } }, active = "" }
                root.BackLeaves = function() return false end
                root.Rebuild = function() f.calls[#f.calls + 1] = "back" end
                local entries = { { action = "accept", label = "Select" }, { action = "tertiary", label = "Save" },
                    { action = "settings", label = "Settings" }, { action = "back", label = "Back" } }
                root.focusId = "selected"
                root:OnKeyCodePressed(KEY_ENTER)
                root:OnKeyCodePressed(KEY_XBUTTON_Y)
                root:OnKeyCodePressed(KEY_F2)
                root:OnKeyCodePressed(KEY_BACKSPACE)
                root.model.stacks[""][2], root.lastBackFrame = "child", -1
                show(bar, entries)
                f.mouse.x = 150 -- Select label, not just the glyph
                click(bar, MOUSE_LEFT)
                f.mouse.x = 220
                click(bar, MOUSE_LEFT)
                f.mouse.x = 325
                click(bar, MOUSE_LEFT)
                f.mouse.x = 460
                click(bar, MOUSE_LEFT)
                expect(f.calls).to.deepEqual({ "accept", "tertiary", "settings", "back", "accept", "tertiary",
                    "settings", "back" })
                expect(root.focusId).to.equal("selected")
                expect(root.input.device).to.equal("mouse")
            end
        },
        {
            name = "Clicking Select does not activate a locked focused node",
            func = function()
                local f = fixture()
                local root = f.root
                local focus = assert(assert(PW.UI).Focus)
                local node = { id = "selected", group = "main", rect = { x = 0, y = 0, w = 10, h = 10 },
                    locked = true }
                rawset(root, "ActFocus", nil) -- use the real focus routing instead of its recording seam
                root.focusId = node.id
                root.view = { OnAccept = function() f.calls[#f.calls + 1] = "accepted" end }
                show(f.bar, { { action = "accept", label = "Select" } })
                root.focusModel = focus.New({ node })
                click(f.bar, MOUSE_LEFT)
                expect(#f.calls).to.equal(0)
                node.locked = false
                root.focusModel = focus.New({ node })
                click(f.bar, MOUSE_LEFT)
                expect(f.calls).to.deepEqual({ "accepted" })
            end
        },
        {
            name = "Only a matching left press and release on a painted actionable hint dispatches once",
            func = function()
                local f = fixture()
                local bar = f.standalone()
                local entries = { { action = "accept", label = "Vote" },
                    { action = "unknown", label = "Unknown" }, { action = "back", label = "Guidance", passive = true } }
                bar:SetReason("Locked")
                show(bar, entries)
                click(bar, MOUSE_LEFT) -- standalone is passive until its owner supplies a handler
                bar.OnAction = function(_, action) f.calls[#f.calls + 1] = action --[[@as string]] end
                click(bar, MOUSE_RIGHT)
                f.mouse.x = 175 -- inter-hint gap
                click(bar, MOUSE_LEFT)
                f.mouse.x = 215 -- passive guidance
                click(bar, MOUSE_LEFT)
                f.mouse.x = 400 -- lock reason
                click(bar, MOUSE_LEFT)
                f.mouse.x, f.mouse.y = 100, 5 -- bar background, outside glyph and label
                click(bar, MOUSE_LEFT)
                f.mouse.y = 40
                bar:OnMousePressed(MOUSE_LEFT)
                f.mouse.x = 215
                bar:OnMouseReleased(MOUSE_LEFT)
                expect(#f.calls).to.equal(0)
                f.mouse.x = 100
                click(bar, MOUSE_LEFT)
                bar:OnMouseReleased(MOUSE_LEFT)
                expect(f.calls).to.deepEqual({ "accept" })
                expect(bar.captured).to.beFalse()
            end
        },
        {
            name = "Vote overlay clicks navigate and cast through its own action handler",
            func = function()
                local f = fixture()
                local vote, casts = voteFixture(f)
                local bar = vote.hintBar --[[@as any]]
                bar:Think()
                bar:Paint(bar.width, bar.height)
                vote.frame:OnKeyCodePressed(KEY_ENTER)
                f.mouse.x = 240 -- Next
                click(bar, MOUSE_LEFT)
                f.mouse.x = 340 -- Vote
                click(bar, MOUSE_LEFT)
                f.mouse.x = 450 -- no Pick myself when the player lacks permission
                click(bar, MOUSE_LEFT)
                vote.picking = true
                f.mouse.x = 340
                click(bar, MOUSE_LEFT)
                expect(casts).to.deepEqual({ 1, 2 })
                expect(vote.focus).to.equal(2)
            end
        },
        {
            name = "A modal, replacement entries, hidden bar or changed glyphs cannot release a stale click",
            func = function()
                local f = fixture()
                local bar, root = f.bar, f.root
                local select = { { action = "accept", label = "Select" } }
                show(bar, select)
                bar:OnMousePressed(MOUSE_LEFT)
                root:OpenModal({})
                root:CloseModal()
                bar:OnMouseReleased(MOUSE_LEFT)
                root:OpenModal({})
                click(bar, MOUSE_LEFT)
                bar:OnMousePressed(MOUSE_LEFT)
                root:CloseModal()
                bar:OnMouseReleased(MOUSE_LEFT)
                bar:OnMousePressed(MOUSE_LEFT)
                bar:SetEntries({ { action = "tertiary", label = "Save" } })
                click(bar, MOUSE_LEFT)
                show(bar, select)
                bar:OnMousePressed(MOUSE_LEFT)
                f.setOverride("gamepad")
                bar:Think()
                bar:Paint(bar.width, bar.height)
                bar:OnMouseReleased(MOUSE_LEFT)
                bar.visible = false
                click(bar, MOUSE_LEFT)
                expect(#f.calls).to.equal(0)
                expect(bar.captured).to.beFalse()
            end
        }
    }
}
