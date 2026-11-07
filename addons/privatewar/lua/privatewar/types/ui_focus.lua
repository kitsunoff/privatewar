---@meta
-- Types of layout, focus and input (U-2, notes/16-frontend-d1-proposal.md Q1, Q5, Q6).
-- Source: lua/privatewar/modules/ui_kit/ (sh_layout.lua, sh_focus.lua, sh_input.lua). Pure and shared.

---@class PW.UIRect
---@field x number
---@field y number
---@field w number
---@field h number

---Columns spec, every size in design units (1920x1080). A missing left or right means no such column.
---@class PW.UIColumnsSpec
---@field margin? number outer horizontal margin (default 0)
---@field left? number left column width
---@field right? number right column width
---@field gap? number gap between columns (default 0)
---@field top? number height reserved at the top (title, tabs)
---@field bottom? number height reserved at the bottom (hint bar)

---Rectangles in pixels. Left is anchored to the left edge, right to the right edge, the centre fills the rest.
---@class PW.UIColumns
---@field left? PW.UIRect
---@field centre PW.UIRect
---@field right? PW.UIRect

---@class PW.UILayoutLib
---Pure: column rectangles for a screen of w x h pixels. S maps design units to pixels (default: uniform
---min(w / 1920, h / 1080), rounded).
---@field Columns fun(w: number, h: number, spec: PW.UIColumnsSpec, S?: fun(n: number): number): PW.UIColumns

---@alias PW.UIDirection "up"|"down"|"left"|"right"

---@class PW.UIFocusNode
---@field id string
---@field group string
---@field rect PW.UIRect
---@field disabled? boolean skipped by focus
---@field locked? boolean focusable, not activatable

---@class PW.UIFocusGroup
---@field axis? "vertical"|"horizontal" default "vertical"
---@field wrap? boolean wrap at the ends (tab bar)

---@class PW.UIFocusModel
---@field nodes PW.UIFocusNode[]
---@field byId table<string, PW.UIFocusNode>
---@field groups table<string, PW.UIFocusGroup>
---@field last table<string, string> last focused node id per group

---@class PW.UIFocusLib
---@field New fun(nodes: PW.UIFocusNode[], groups?: table<string, PW.UIFocusGroup>): PW.UIFocusModel
---Records id as the last focused node of its group.
---@field Set fun(model: PW.UIFocusModel, id: string)
---Moves focus; returns the new id (the current one when there is no candidate) and remembers it.
---@field Move fun(model: PW.UIFocusModel, current: string, dir: PW.UIDirection): string
---True when the node exists, is not disabled and not locked.
---@field Activatable fun(model: PW.UIFocusModel, id: string): boolean
---Feeds an action: up/down/left/right move, accept gives "accept" or "locked", other actions give the action name.
---@field Apply fun(model: PW.UIFocusModel, current: string, action: string): string, string?

---@alias PW.UIDevice "keyboard"|"mouse"|"controller"

---@class PW.UIActionDef
---@field keyboard integer[] KEY codes
---@field controller integer[] KEY_X* codes
---@field cap string label of the key cap hint
---@field pad string label of the pad badge hint

---@class PW.UIInputState
---@field device PW.UIDevice

---@class PW.UIHint
---@field device "keyboard"|"controller"
---@field label string

---@class PW.UIInputLib
---@field Actions table<string, PW.UIActionDef>
---@field New fun(): PW.UIInputState
---Action bound to a key or controller code, or nil.
---@field ActionOf fun(code: integer): string?
---Records the device of a key press and returns its action (nil for an unbound code, device unchanged).
---@field Press fun(state: PW.UIInputState, code: integer): string?
---@field NoteMouse fun(state: PW.UIInputState)
---@field Device fun(state: PW.UIInputState): PW.UIDevice
---Hint label for an action: override "auto" (default), "keyboard" or "gamepad" (the ui_kit hints setting).
---@field Hint fun(state: PW.UIInputState, action: string, override?: string): PW.UIHint

---@class PW.UILib
---@field Layout? PW.UILayoutLib
---@field Focus? PW.UIFocusLib
---@field Input? PW.UIInputLib
