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
