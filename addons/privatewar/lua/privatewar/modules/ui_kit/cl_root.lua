-- PWRoot (U-3; tab bar and focus wiring U-4; notes/16 Q1): the full-screen popup that hosts the router. Thin glue:
-- it paints the backdrop (blur + scrim), holds the frame components (PWScreenTitle, PWStatusLine, PWTabBar,
-- PWHintBar), turns key presses into input actions (PW.UI.Input) and gives them to the router first, then to the
-- focused panel, then to the focus graph (PW.UI.Focus over the focus specs of the visible panels), then to the
-- screen. A modal panel (PWDialog) keeps the focus inside it. Back at the root screen of the lobby hub opens the
-- leave dialog (PW.UI.Match.RootBack, cl_match.lua). Escape while the root is open reaches it through the
-- OnPauseMenuShow hook in cl_match.lua (Shift+Escape there stays the GMod menu). All logic lives in the pure files.

local lib = PW.UI --[[@as PW.UILib]]
local router = lib.Router --[[@as PW.UIRouterLib]]
local input = lib.Input --[[@as PW.UIInputLib]]
local focus = lib.Focus --[[@as PW.UIFocusLib]]
local engineInput = _G.input

---@class PWRoot : EditablePanel
---@field model PW.UIRouterModel
---@field input PW.UIInputState
---@field content Panel
---@field title PWScreenTitle
---@field status PWStatusLine
---@field tabBar PWTabBar
---@field hintBar PWHintBar
---@field view any
---@field modal? Panel
---@field modalReturn? Panel the focused panel when the modal opened (focused again when it closes)
---@field focusModel? PW.UIFocusModel
---@field focusId? string
---@field focusPanels table<string, Panel>
---@field focusPanel? Panel
---@field manualFocus boolean the screen gave its own focus model (ctx.SetFocus)
---@field focusDirty integer frames left before the focus is collected again (0: not pending)
---@field lastBackFrame integer
---@field parkX? number cursor position at the last key press (hover is ignored until the cursor moves)
---@field parkY? number
---@field rootId string the kind of root (OpenRoot options): "hub", "pause", "class"
---@field compact boolean T-7.6: no backdrop, title, status or tabs; the content is a panel at the right edge
---@field onClose? fun()
local rootClass = {}

hook.Remove("OnPauseMenuShow", "PW_UI_Root") -- the Escape hook moved to cl_match.lua; drops the old one on pw_reload
local margin, titleTop, tabTop, tabHeight, contentTop, hintHeight = 96, 20, 128, 64, 216, 80
local compactWidth, compactTop = 640, 320 -- below the killfeed (top right)
local defaultHints = { { action = "accept", label = "Select" }, { action = "back", label = "Back" } }
local currentRoot = nil --[[@as PWRoot?]]

---@return PW.PhaseName
local function phase()
    return PW.Phase.GetPhase()
end

-- Seen-set (notes/16 §4a: data/privatewar/ui_seen.json) -----------------------------------------------------------

local seenPath = "privatewar/ui_seen.json"
local seen = nil --[[@as table<string, true>?]]

function lib.SeenSet()
    if seen ~= nil then return seen end
    ---@type table<any, any>
    local loaded = util.JSONToTable(file.Read(seenPath, "DATA") or "") or {}
    ---@type table<string, true>
    local set = {}
    for key, value in pairs(loaded) do
        if type(key) == "string" and value == true then set[key] = true end
    end
    seen = set
    return set
end

function lib.SaveSeen()
    file.CreateDir("privatewar")
    file.Write(seenPath, util.TableToJSON(lib.SeenSet()))
end

-- Frame -------------------------------------------------------------------------------------------------------------

function rootClass:Init()
    self._pwIsRoot = true
    self:SetSize(ScrW(), ScrH())
    self:SetPos(0, 0)
    self:MakePopup()
    self:SetKeyboardInputEnabled(true)
    self.input = input.New()
    self.lastBackFrame, self.focusPanels, self.manualFocus, self.focusDirty = -1, {}, false, 0
    self.rootId, self.compact = "hub", false
    self.content = vgui.Create("Panel", self) --[[@as Panel]]
    self.title = vgui.Create("PWScreenTitle", self) --[[@as PWScreenTitle]]
    self.status = vgui.Create("PWStatusLine", self) --[[@as PWStatusLine]]
    self.tabBar = vgui.Create("PWTabBar", self) --[[@as PWTabBar]]
    self.tabBar:SetInputState(self.input)
    self.tabBar.OnSelect = function(_, id) self:SelectTab(id) end
    self.hintBar = vgui.Create("PWHintBar", self) --[[@as PWHintBar]]
    self.hintBar:SetInputState(self.input)
    local registry = PW.Registries["screens"]
    self.model = router.New(registry ~= nil and registry.GetEnabledList() --[[@as PW.Screen[] ]] or {})
end

---Applies the open options (T-7.6): another tab set, the compact frame, the close callback.
---@param opts PW.UIRootOptions
function rootClass:Setup(opts)
    self.rootId, self.compact, self.onClose = opts.id or "hub", opts.compact == true, opts.onClose
    if opts.tabs ~= nil then
        local registry = PW.Registries["screens"]
        self.model = router.New(registry ~= nil and registry.GetEnabledList() --[[@as PW.Screen[] ]] or {}, opts.tabs)
    end
    for _, part in ipairs({ self.title, self.status, self.tabBar }) do part:SetVisible(not self.compact) end
end

---@param width number
---@param height number
function rootClass:PerformLayout(width, height)
    local px = lib.Draw.Px
    self.title:SetPos(px(margin), px(titleTop))
    self.title:SetSize(math.floor(width * 0.5), px(96))
    self.status:SetPos(width - px(margin) - px(760), px(titleTop) + px(40))
    self.status:SetSize(px(760), px(56))
    self.tabBar:SetPos(px(margin) - px(56), px(tabTop))
    self.tabBar:SetSize(width - 2 * px(margin) + px(56), px(tabHeight))
    self.content:SetPos(0, px(contentTop))
    self.content:SetSize(width, height - px(contentTop) - px(hintHeight))
    self.hintBar:SetPos(0, height - px(hintHeight))
    self.hintBar:SetSize(width, px(hintHeight))
    if self.compact then
        self.content:SetPos(width - px(margin) - px(compactWidth), px(compactTop))
        self.content:SetSize(px(compactWidth), height - px(compactTop) - px(hintHeight))
    end
    if IsValid(self.modal) then (self.modal --[[@as Panel]]):SetSize(width, height) end
end

---@param id string
function rootClass:SelectTab(id)
    if router.SwitchTab(self.model, id) then self:Rebuild() end
end

---Title, tab bar (marks the active tab seen) and hints of the top screen.
---@param top? PW.Screen
function rootClass:UpdateFrame(top)
    local tab = self.model.tabById[self.model.active]
    self.title:SetText((top ~= nil and top.Title) or (tab ~= nil and tab.label) or "")
    local set = lib.SeenSet()
    if lib.Seen.Mark(set, lib.Tabs.SeenKey(self.model.active)) then lib.SaveSeen() end
    self.tabBar:SetItems(lib.Tabs.Items(self.model.tabs, self.model.active, set))
    self.hintBar:SetEntries(top ~= nil and top.Hints or defaultHints)
    self.hintBar:SetReason(nil)
end

---Drops the old view and builds the top screen of the active tab.
function rootClass:Rebuild()
    if IsValid(self.view) then (self.view --[[@as Panel]]):Remove() end
    if IsValid(self.modal) then (self.modal --[[@as Panel]]):Remove() end
    self.view, self.modal, self.focusModel, self.focusId, self.focusPanel = nil, nil, nil, nil, nil
    self.focusPanels, self.manualFocus = {}, false
    self.parkX, self.parkY = gui.MouseX(), gui.MouseY()
    local root = self
    local view, top = router.Build(self.model, {
        parent = self.content, root = self, router = self.model,
        SetFocus = function(model, id) root.focusModel, root.focusId, root.manualFocus = model, id, true end
    })
    self.view = view
    self:UpdateFrame(top)
    self:InvalidateLayout(true)
    self.focusDirty = 2 -- the view lays itself out in the next frames; its rectangles are known after that
end

-- Focus -------------------------------------------------------------------------------------------------------------

---Adds one focusable panel to the collection.
---@param child Panel
---@param spec PW.UIFocusSpec
---@param out PW.UIFocusCollect
local function addNode(child, spec, out)
    local x, y = child:LocalToScreen(0, 0)
    local w, h = child:GetSize()
    out.nodes[#out.nodes + 1] = {
        id = spec.id, group = spec.group, rect = { x = x, y = y, w = w, h = h },
        disabled = spec.disabled == true or not child:IsEnabled(), locked = spec.locked
    }
    out.panels[spec.id] = child
    if out.groups[spec.group] == nil then out.groups[spec.group] = { axis = spec.axis, wrap = spec.wrap } end
end

---Collects the focus nodes of the visible panels under parent.
---@param parent Panel
---@param out PW.UIFocusCollect
local function collect(parent, out)
    ---@type Panel[]
    local children = parent:GetChildren()
    for _, child in ipairs(children) do
        if child:IsVisible() then
            if child._pwFocus ~= nil then addNode(child, child._pwFocus, out) end
            collect(child, out)
        end
    end
end

---Rebuilds the focus model from the visible panels (inside the modal panel when one is open).
function rootClass:RefreshFocus()
    self.focusDirty = 0
    if self.manualFocus then return end
    ---@type PW.UIFocusCollect
    local out = { nodes = {}, panels = {}, groups = {} }
    collect(IsValid(self.modal) and self.modal --[[@as Panel]] or self, out)
    local last = self.focusModel ~= nil and self.focusModel.last or {}
    self.focusModel = focus.New(out.nodes, out.groups)
    self.focusModel.last = last
    self.focusPanels = out.panels
    if self.focusId ~= nil and out.panels[self.focusId] ~= nil then return end
    -- First focus: the top-left node of the screen (the tab bar is reached with up or Q/E).
    ---@type PW.UIFocusNode?
    local best = nil
    for _, node in ipairs(out.nodes) do
        local rect = node.rect
        local better = best == nil or rect.y < best.rect.y or (rect.y == best.rect.y and rect.x < best.rect.x)
        if not node.disabled and node.group ~= "tabs" and better then best = node end
    end
    if best ~= nil then self:FocusPanel(out.panels[best.id], "auto") end
end

---Scrolls the nearest scroll panel so the panel is visible.
---@param panel Panel
local function scrollTo(panel)
    local parent = panel:GetParent() --[[@as Panel?]]
    while parent ~= nil and IsValid(parent) do
        local scroll = parent:GetParent() --[[@as Panel?]]
        local candidate = scroll --[[@as { ScrollToChild?: fun(self: any, child: Panel) }?]]
        if candidate ~= nil and candidate.ScrollToChild ~= nil then
            candidate:ScrollToChild(panel)
            return
        end
        parent = scroll
    end
end

---Moves the focus to a panel (mouse hover, keyboard move, or the first panel of a new screen).
---@param panel? Panel
---@param source? string "mouse", "key" or "auto"
function rootClass:FocusPanel(panel, source)
    if panel == nil or not IsValid(panel) or panel._pwFocus == nil then return end
    local spec = panel._pwFocus --[[@as PW.UIFocusSpec]]
    if source == "mouse" then
        -- A cursor that has not moved since the last key press is parked: a panel appearing under it (a closed
        -- dialog, a new page) must not steal the keyboard focus.
        if gui.MouseX() == self.parkX and gui.MouseY() == self.parkY then return end
        self.parkX, self.parkY = nil, nil
        input.NoteMouse(self.input)
        if spec.disabled or not panel:IsEnabled() then return end
    end
    if IsValid(self.focusPanel) then (self.focusPanel --[[@as Panel]])._pwFocused = false end
    self.focusPanel, self.focusId = panel, spec.id
    panel._pwFocused = true
    if self.focusModel ~= nil then focus.Set(self.focusModel, spec.id) end
    self.hintBar:SetReason(spec.locked and spec.reason or nil)
    if panel.PWOnFocus ~= nil then panel:PWOnFocus() end
    if source == "key" then scrollTo(panel) end
end

---Shows a modal panel: the focus stays inside it until CloseModal.
---@param modal Panel
---@param first? Panel
function rootClass:OpenModal(modal, first)
    self.modal, self.modalReturn = modal, self.focusPanel
    self.focusId = nil
    self:RefreshFocus()
    self:FocusPanel(first, "auto")
end

function rootClass:CloseModal()
    self.modal, self.focusId = nil, nil
    self:RefreshFocus()
    if IsValid(self.modalReturn) then self:FocusPanel(self.modalReturn, "auto") end
    self.modalReturn = nil
end

-- Input -------------------------------------------------------------------------------------------------------------

---A handler of the view (a table or a panel), or nil.
---@param view any
---@param name string
---@return function?
local function viewHandler(view, name)
    if type(view) ~= "table" and not ispanel(view) then return nil end
    ---@type any
    local handler = view[name]
    return type(handler) == "function" and handler or nil
end

---The screen's own actions (secondary, tertiary, settings, ...): view:OnAction(action).
---@param action string
function rootClass:ActView(action)
    local handler = viewHandler(self.view, "OnAction")
    if handler ~= nil then handler(self.view, action) end
end

---Focused panel first (it may consume left/right or page across a list), then the focus graph.
---@param action string
function rootClass:ActFocus(action)
    self:RefreshFocus()
    local model, id = self.focusModel, self.focusId
    if model == nil or id == nil then return self:ActView(action) end
    local panel = self.focusPanels[id]
    if panel ~= nil and IsValid(panel) and panel.PWAct ~= nil then
        local handled, target = panel:PWAct(action)
        if handled then
            if target ~= nil then
                self:RefreshFocus()
                self:FocusPanel(target, "key")
            end
            return
        end
    end
    local nextId, event = focus.Apply(model, id, action)
    if nextId ~= id then
        self.focusId = nextId
        self:FocusPanel(self.focusPanels[nextId], "key")
    end
    if event == "accept" then
        local handler = viewHandler(self.view, "OnAccept")
        if handler ~= nil then return handler(self.view, nextId) end
        if panel ~= nil and IsValid(panel) then lib.Activate(panel) end
    elseif event ~= "move" and event ~= "locked" then
        self:ActView(action)
    end
end

---Back at the root screen of the lobby hub opens the leave dialog instead of the router's "stay" (T-7.6 follow-up).
---@return boolean
function rootClass:BackLeaves()
    local rules = rawget(lib, "Match") --[[@as PW.UIMatchLib?]]
    if rules == nil or lib.OpenLobbyLeave == nil then return false end
    return rules.RootBack({ phase = phase(), rootId = self.rootId, depth = router.Depth(self.model) }) == "leave"
end

---Gives an input action to the router, then to the focus and the screen.
---@param action string
function rootClass:Act(action)
    self.parkX, self.parkY = gui.MouseX(), gui.MouseY()
    if action == "back" then
        if self.lastBackFrame == FrameNumber() then return end
        self.lastBackFrame = FrameNumber()
        if IsValid(self.modal) then
            local modal = self.modal --[[@as Panel]]
            if modal.PWBack ~= nil then return modal:PWBack() end
        elseif self:BackLeaves() then
            return (lib.OpenLobbyLeave --[[@as fun()]])()
        end
    end
    if action == "settings" and not IsValid(self.modal) and not self.compact and lib.Settings ~= nil then
        -- T-7.2, 10-frontend.md d.8: SETTINGS is a hint-bar action (F2 / Start) on every full root.
        if lib.Settings.Open(self.model, "client") then self:Rebuild() end
        return
    end
    if not IsValid(self.modal) then
        local result = router.Act(self.model, action, phase())
        if result == "close" then return self:Remove() end
        if result == "tab" or result == "pop" then return self:Rebuild() end
        if result ~= nil then return end
    end
    self:ActFocus(action)
end

---@param code integer
---@return boolean
function rootClass:OnKeyCodePressed(code)
    -- Shift+Escape is the GMod menu (cl_match.lua), never Back.
    if code == KEY_ESCAPE and engineInput.IsShiftDown() then return true end
    local action = input.Press(self.input, code)
    if action ~= nil then self:Act(action) end
    return true
end

function rootClass:OnMousePressed()
    input.NoteMouse(self.input)
end

function rootClass:Think()
    if self.focusDirty <= 0 then return end
    self.focusDirty = self.focusDirty - 1
    if self.focusDirty == 0 then self:RefreshFocus() end
end

---@param width number
---@param height number
function rootClass:Paint(width, height)
    local paint = lib.Draw
    if self.compact then
        -- The compact picker keeps the scene visible: the scrim only, no blur and no header band.
        paint.Rect(0, 0, width, height, (lib.Style --[[@as PW.UIStyle]]).bg_scrim)
        return
    end
    paint.Backdrop(self, width, height)
    -- A darker band behind the title, status and tabs keeps them readable over a bright scene.
    paint.Rect(0, 0, width, paint.Px(tabTop + tabHeight), (lib.Style --[[@as PW.UIStyle]]).bg_panel)
end

function rootClass:OnRemove()
    if currentRoot == self then currentRoot = nil end
    local onClose = self.onClose
    self.onClose = nil
    if onClose ~= nil then onClose() end
end

vgui.Register("PWRoot", rootClass, "EditablePanel")

---Opens the root (one at a time) and builds the first screen. An open root of the same kind is returned; one of
---another kind (opts.id, default "hub") is closed first, so the lobby replaces a pause menu left open.
---@param opts? PW.UIRootOptions
---@return Panel
function lib.OpenRoot(opts)
    local wanted = opts ~= nil and opts.id or "hub"
    if IsValid(currentRoot) then
        local open = currentRoot --[[@as PWRoot]]
        if open.rootId == wanted then return open end
        open:Remove()
    end
    local root = vgui.Create("PWRoot") --[[@as PWRoot]]
    currentRoot = root
    if opts ~= nil then root:Setup(opts) end
    root.lastBackFrame = FrameNumber() -- the Escape that opened a menu must not also close it
    root:Rebuild()
    return root
end

function lib.CloseRoot()
    if IsValid(currentRoot) then (currentRoot --[[@as PWRoot]]):Remove() end
    currentRoot = nil
end

---@return boolean
function lib.RootOpen()
    return IsValid(currentRoot)
end

function lib.CurrentRoot()
    if IsValid(currentRoot) then return currentRoot end
    return nil
end

concommand.Add("pw_ui_root", function()
    if lib.RootOpen() then lib.CloseRoot() else lib.OpenRoot() end
end, nil, "Private War: open or close the new UI root (router development)")
