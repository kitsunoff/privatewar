-- Cache only normally transmitted/drawn public devices; no hidden device position messages.
local lib = PW.Devices --[[@as PW.DevicesLib]]
---@type table<PW.SupportDeviceEntity, PW.DeviceMarker>
local tracked = setmetatable({}, { __mode = "k" })
lib.Markers = {}
local hud = PW.HUD
lib.MarkerFont = hud ~= nil and hud.Font ~= nil and hud.Font("support", 24, 700) or "DermaDefaultBold"

function lib.ClientTrack(entity)
    if tracked[entity] == nil then tracked[entity] = { x = 0, y = 0, text = "", visible = false } end
end

---@param viewer Player
---@param entity PW.SupportDeviceEntity
---@param row PW.DeviceMarker
---@param now number
---@return boolean
local function marker(viewer, entity, row, now)
    local owner = entity:GetDeviceOwner()
    local cfg = lib.Config[entity:GetDeviceKind()]
    row.visible = false
    if cfg == nil or not IsValid(owner) or entity:GetDeviceEnds() <= now
        or viewer:GetPos():DistToSqr(entity:GetPos()) > 1800 * 1800 then return false end
    local tr = util.TraceLine({ start = viewer:EyePos(), endpos = entity:WorldSpaceCenter(),
        filter = viewer, mask = MASK_VISIBLE })
    if tr.Entity ~= entity and tr.Fraction < 0.99 then return false end
    local screen = (entity:WorldSpaceCenter() + Vector(0, 0, 20)):ToScreen()
    row.x, row.y, row.visible = screen.x, screen.y, screen.visible
    row.text = cfg.name .. " / " .. owner:Nick() .. " / " .. math.ceil(entity:GetDeviceEnds() - now) .. "s"
    return true
end

local nextTick = 0
PW.HookFor(MODULE, "Think", function()
    local now = CurTime()
    if now < nextTick then return end
    nextTick = now + 0.1
    local viewer = LocalPlayer()
    if not IsValid(viewer) then return end
    local n = 0
    for entity, row in pairs(tracked) do
        if not IsValid(entity) then tracked[entity] = nil
        elseif marker(viewer, entity, row, now) then
            n = n + 1
            lib.Markers[n] = row
        end
    end
    for i = #lib.Markers, n + 1, -1 do lib.Markers[i] = nil end
    lib.Notice = viewer:GetNW2Float("pw_support_notice_end", 0) > now and viewer:GetNW2String("pw_support_notice", "")
        or ""
end)
