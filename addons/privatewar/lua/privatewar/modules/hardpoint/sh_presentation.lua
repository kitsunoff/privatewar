local hp = assert(PW.Hardpoint)

function hp.ControlToken(control, contested, ownTeam)
    if contested then return "warning" end
    if control ~= 1 and control ~= 2 then return "text" end
    if ownTeam ~= 1 and ownTeam ~= 2 then return "text" end
    return control == ownTeam and "team_friendly" or "team_enemy"
end

function hp.PublicSnapshot(state, revision)
    local zone = state.layout.zones[state.index]
    return { generation = state.generation, revision = revision, visit = state.visit, active = not state.finished,
        zone = { id = zone.id, pos = zone.pos, radius = zone.radius, above = zone.above, below = zone.below },
        zoneEndsAt = state.zoneEndsAt, matchEndsAt = state.matchEndsAt,
        control = state.control, contested = state.contested, scores = { state.scores[1], state.scores[2] } }
end

function hp.AcceptSnapshot(current, incoming)
    if current ~= nil then
        if incoming.generation < current.generation then return current end
        if incoming.generation == current.generation and (incoming.visit < current.visit
            or incoming.revision <= current.revision) then return current end
    end
    return incoming
end

function hp.View(snapshot, now, out)
    out.zoneId = snapshot.active and snapshot.zone.id or ""
    out.zoneRemaining = snapshot.active and math.max(0, snapshot.zoneEndsAt - now) or 0
    out.matchRemaining = snapshot.active and math.max(0, snapshot.matchEndsAt - now) or 0
    return out
end

---@param value number
---@return boolean
local function finite(value) return value == value and math.abs(value) < math.huge end

function hp.ProjectWaypoint(right, up, forward, fov, width, height, out)
    out.x, out.y, out.angle, out.edge, out.visible = 0, 0, 0, false, false
    if not finite(right) or not finite(up) or not finite(forward) or not finite(fov)
        or width <= 0 or height <= 0 or not finite(width) or not finite(height) then return out end
    local cx, cy = width * 0.5, height * 0.5
    local focal = width * 0.5 / math.tan(math.rad(math.Clamp(fov, 20, 160)) * 0.5)
    local dx, dy = right * focal / math.max(math.abs(forward), 0.001), -up * focal
        / math.max(math.abs(forward), 0.001)
    local left, top, edgeX, bottom = width * 0.26, height * 0.26, width * 0.82, height * 0.72
    local edge = forward <= 0 or cx + dx < left or cx + dx > edgeX or cy + dy < top or cy + dy > bottom
    if forward <= 0 and dx == 0 and dy == 0 then dy = 1 end -- exact-behind: turn cue, never a divide by zero
    out.angle = math.deg(math.atan2(dy, dx))
    if edge then
        local scale = math.huge
        if dx > 0 then scale = math.min(scale, (edgeX - cx) / dx)
        elseif dx < 0 then scale = math.min(scale, (left - cx) / dx) end
        if dy > 0 then scale = math.min(scale, (bottom - cy) / dy)
        elseif dy < 0 then scale = math.min(scale, (top - cy) / dy) end
        dx, dy = dx * scale, dy * scale
    end
    out.x, out.y = math.Clamp(cx + dx, left, edgeX), math.Clamp(cy + dy, top, bottom)
    out.edge, out.visible = edge, true
    return out
end

function hp.Guidance(snapshot, phase, mode, playerVisible, ownTeam, distance, out)
    out.visible, out.zoneId, out.action, out.token, out.distance = false, "", "", "text", 0
    if snapshot == nil or not snapshot.active or phase ~= "LIVE" or mode ~= "hardpoint" or not playerVisible
        or (ownTeam ~= 1 and ownTeam ~= 2) or not finite(distance) or distance < 0 then return out end
    out.visible, out.zoneId = true, snapshot.zone.id
    out.action = snapshot.contested and "contested" or snapshot.control == ownTeam and "defend" or "capture"
    out.token = hp.ControlToken(snapshot.control, snapshot.contested, ownTeam)
    out.distance = math.floor(distance * 0.0254 + 0.5)
    return out
end
