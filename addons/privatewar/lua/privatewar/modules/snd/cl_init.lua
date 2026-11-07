-- Fixed-shape, server-authoritative S&D state. No enemy lookup, client request or locally inferred bomb facts.
local lib = PW.SND --[[@as PW.SNDLib]]
local phases = { "carried", "dropped", "planted", "resolved" }
---@type PW.SNDSnapshot?
local current
local generation, serial = -1, -1
---@type PW.SNDDisplay
local display = { title = "", line = "", progress = 0, markers = {} }
local nextDisplay = 0

function lib.View()
    if assert(PW.Match).GetPhase() ~= "LIVE" then return nil end
    return current
end

function lib.Display()
    return lib.View() ~= nil and display or nil
end

---@param pos Vector
---@param text string
---@param index integer
local function marker(pos, text, index)
    local point = (pos + Vector(0, 0, 48)):ToScreen()
    local item = display.markers[index] or { x = 0, y = 0, text = "", visible = false }
    item.x, item.y, item.text, item.visible = point.x, point.y, text, point.visible
    display.markers[index] = item
end

PW.HookFor(MODULE, "Think", function()
    local now = CurTime()
    if now < nextDisplay then return end
    nextDisplay = now + 0.05
    local view = lib.View()
    if view == nil then return end
    display.title = "SEARCH AND DESTROY"
    if view.phase == "planted" then
        display.title = "BOMB PLANTED  " .. math.ceil(math.max(0, view.fuse - now)) .. "s"
    elseif view.phase == "resolved" then
        display.title = "ROUND OVER"
    elseif view.carrier ~= nil then
        display.title = "BOMB CARRIER  #" .. view.carrier
    end
    display.line = view.action ~= nil and ("HOLD E TO " .. string.upper(view.action)) or "SITES A / B"
    display.progress = view.action ~= nil and view.progress or 0
    local data = PW.Map ~= nil and PW.Map.GetModeData("snd") or nil
    local count = 0
    if data ~= nil then
        for _, site in ipairs(data.sites --[[@as PW.SNDSite[] ]]) do
            count = count + 1
            marker(site.pos, site.id, count)
        end
    end
    if view.pos ~= nil then
        count = count + 1
        marker(view.pos, "BOMB", count)
    end
    for index = #display.markers, count + 1, -1 do display.markers[index] = nil end
end)

net.Receive("pw_snd_state", function(length)
    if length < 67 or length > 1024 then return end
    local nextGeneration, nextSerial, phase = net.ReadUInt(32), net.ReadUInt(32), net.ReadUInt(3)
    if nextGeneration < generation or (nextGeneration == generation and nextSerial <= serial) then return end
    if phase == 0 then
        generation, serial, current = nextGeneration, nextSerial, nil
        return
    end
    if phases[phase] == nil or length < 166 then return end
    ---@type PW.SNDSnapshot
    local view = { generation = nextGeneration, phase = phases[phase], deadline = net.ReadFloat(),
        fuse = net.ReadFloat(), site = net.ReadString(), carrier = net.ReadUInt(16), progress = 0 }
    if #assert(view.site) > 32 or view.deadline ~= view.deadline or view.fuse ~= view.fuse
        or view.deadline < 0 or view.fuse < 0 or view.deadline >= math.huge or view.fuse >= math.huge then return end
    if view.site == "" then view.site = nil end
    if view.carrier == 0 then view.carrier = nil end
    if net.ReadBool() then
        local pos = net.ReadVector()
        if pos.x ~= pos.x or pos.y ~= pos.y or pos.z ~= pos.z or math.abs(pos.x) >= math.huge
            or math.abs(pos.y) >= math.huge or math.abs(pos.z) >= math.huge then return end
        view.pos = pos
    end
    local action = net.ReadUInt(2)
    view.action = action == 1 and "plant" or (action == 2 and "defuse" or nil)
    view.progress = net.ReadUInt(8) / 255
    generation, serial, current = nextGeneration, nextSerial, view
end)

---@param phase PW.PhaseName
function MODULE:PW_PhaseChange(phase)
    if phase ~= "LIVE" then current = nil end
end
