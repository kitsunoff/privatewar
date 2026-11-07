-- Bots debug overlay, client (T-5.4; 07-bots.md d.11). Receives the snapshot of pw_bot_debug (only a client with
-- pw.bots.debug gets it) and draws, for each bot in view, a 3D2D label (behaviour, reason, target), the goal marker
-- and the path polyline, plus the scheduler perf line in the top-left corner. Colours and fonts come from the ui_kit
-- tokens (PW.UI.Style, the "small" font step). The snapshot is turned into drawable data (Vectors, label lines) once
-- per message, so the paint hooks only read; the paint hooks allocate nothing of their own (the per-bot position
-- Vector of ent:GetPos() is the engine's).

---A file-local class: methods of the global MODULE defined in two files are reported as duplicates.
---@class PW.BotDebugModuleClient : PW.Module
local module = MODULE --[[@as PW.BotDebugModuleClient]]

local lib = PW.BotDebug --[[@as PW.BotDebugLib]]

local drawDistanceSqr = 2000 * 2000
local labelScale = 0.12
local labelHeight = 84

---@class PW.BotDebugDraw
---@field index integer
---@field lines string[] label lines: name, behaviour and reason, target
---@field goal? Vector
---@field goalText? string
---@field path Vector[]

---@type { perf: string, bots: PW.BotDebugDraw[] }
local view = { perf = "", bots = {} }
local receivedAt = -math.huge
local staleAfter = 2

---@param entry PW.BotDebugEntry
---@return PW.BotDebugDraw
local function drawable(entry)
    local behavior = entry.behavior ~= "" and entry.behavior or "-"
    if entry.reason ~= "" then behavior = behavior .. ": " .. entry.reason end
    ---@type string[]
    local lines = { entry.name, behavior }
    if entry.target ~= "" then lines[3] = "target " .. entry.target end
    ---@type PW.BotDebugDraw
    local out = { index = entry.index, lines = lines, path = {} }
    if entry.goal ~= nil then
        out.goal = Vector(entry.goal.x, entry.goal.y, entry.goal.z)
        out.goalText = "goal " .. entry.goal.status
    end
    for i = 1, #entry.path, 3 do
        out.path[#out.path + 1] = Vector(entry.path[i], entry.path[i + 1], entry.path[i + 2])
    end
    return out
end

net.Receive(lib.Message, function()
    local snapshot = lib.Decode({ uint = net.ReadUInt, int = net.ReadInt, string = net.ReadString,
        bool = net.ReadBool })
    ---@type PW.BotDebugDraw[]
    local bots = {}
    for i, entry in ipairs(snapshot.bots) do bots[i] = drawable(entry) end
    view = { perf = snapshot.perf, bots = bots }
    receivedAt = SysTime()
end)

---@return boolean
local function fresh()
    return SysTime() - receivedAt < staleAfter
end

---@return string
local function fontName()
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    if ui ~= nil and ui.Font ~= nil then return ui.Font("small") end
    return "DermaDefault"
end

---@return PW.UIStyle?
local function style()
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    return ui ~= nil and ui.Style or nil
end

local white, black = Color(255, 255, 255), Color(0, 0, 0, 200)
local labelAngle = Angle(0, 0, 90)

---@param lines string[]
---@param font string
---@param text Color
---@param muted Color
local function drawLines(lines, font, text, muted)
    for i = 1, #lines do
        draw.SimpleTextOutlined(lines[i], font, 0, (i - 1) * 24 - #lines * 24, i == 1 and text or muted,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, black)
    end
end

PW.HookFor(module, "PostDrawTranslucentRenderables", function(_, skybox)
    if skybox or not fresh() then return end
    local tokens = style()
    local text, muted, accent = tokens and tokens.text or white, tokens and tokens.text_muted or white,
        tokens and tokens.accent or white
    local font = fontName()
    local eye = EyePos()
    labelAngle.y = EyeAngles().y - 90
    for i = 1, #view.bots do
        local bot = view.bots[i] --[[@as PW.BotDebugDraw]]
        local ent = Entity(bot.index)
        if IsValid(ent) and ent:GetPos():DistToSqr(eye) < drawDistanceSqr then
            cam.Start3D2D(ent:GetPos() + Vector(0, 0, labelHeight), labelAngle, labelScale)
            drawLines(bot.lines, font, text, muted)
            cam.End3D2D()
            local path = bot.path
            for p = 1, #path - 1 do render.DrawLine(path[p], path[p + 1], accent, false) end
            if bot.goal ~= nil then render.DrawWireframeSphere(bot.goal, 14, 8, 8, accent, false) end
        end
    end
end)

PW.HookFor(module, "HUDPaint", function()
    if not fresh() then return end
    local tokens = style()
    draw.SimpleTextOutlined(view.perf, fontName(), 16, 16, tokens and tokens.text or white, TEXT_ALIGN_LEFT,
        TEXT_ALIGN_TOP, 1, black)
end)
