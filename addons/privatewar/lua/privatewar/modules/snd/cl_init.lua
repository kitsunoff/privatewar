-- Fixed-shape, server-authoritative S&D state. No enemy lookup, client request or locally inferred bomb facts.
local lib = PW.SND --[[@as PW.SNDLib]]
---@type PW.SNDSnapshot?
local current
local generation, serial = -1, -1
---@type PW.SNDSitesPacket?
local latestSites
---@type PW.SNDDisplay
local display = { title = "", line = "", progress = 0, markers = {} }
local nextDisplay = 0

function lib.View()
    if PW.Phase.GetPhase() ~= "LIVE" then return nil end
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
    display.title, display.line = lib.HudText(view, now)
    display.progress = view.action ~= nil and view.progress or 0
    local count = 0
    if view.sites ~= nil then
        for _, site in ipairs(view.sites) do
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
    local packet = lib._ReadState(net --[[@as PW.SNDWire]], length)
    if packet == nil then return end
    local nextGeneration, nextSerial = packet.generation, packet.serial
    if nextGeneration < generation or (nextGeneration == generation and nextSerial <= serial) then return end
    local view = packet.view
    if view == nil then
        generation, serial, current = nextGeneration, nextSerial, nil
        latestSites = nil
        return
    end
    view.sites = lib._SitesFor(latestSites, nextGeneration, nextSerial)
    -- A legacy server has no optional sites packet. Keep its state usable without guessing site geometry.
    generation, serial, current = nextGeneration, nextSerial, view
end)

net.Receive("pw_snd_sites", function(length)
    local packet = lib._ReadSites(net --[[@as PW.SNDWire]], length)
    if packet == nil or packet.generation < generation
        or (packet.generation == generation and packet.serial < serial) then return end
    if latestSites ~= nil and (packet.generation < latestSites.generation
        or (packet.generation == latestSites.generation and packet.serial <= latestSites.serial)) then return end
    latestSites = packet
    if current ~= nil and packet.generation == generation and packet.serial == serial then
        current.sites = lib._SitesFor(packet, generation, serial)
    end
end)

---@param phase PW.PhaseName
function MODULE:PW_PhaseChanged(phase)
    if phase ~= "LIVE" then current, latestSites = nil, nil end
end

if file.Exists("tests/privatewar/snd_wire_native.lua", "LUA") then
    include("tests/privatewar/snd_wire_native.lua")
end
