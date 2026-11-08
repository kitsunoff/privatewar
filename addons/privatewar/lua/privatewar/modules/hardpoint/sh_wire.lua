-- Explicit bounded allowlist. No actor, roster, other zone, or next-visit geometry reaches the wire.
local hp = assert(PW.Hardpoint)

function hp.WriteSnapshot(snapshot)
    net.WriteUInt(snapshot.generation, 32)
    net.WriteUInt(snapshot.revision, 32)
    net.WriteUInt(snapshot.visit, 16)
    net.WriteBool(snapshot.active)
    local zone = snapshot.zone
    net.WriteString(zone.id)
    net.WriteVector(zone.pos)
    net.WriteFloat(zone.radius)
    net.WriteFloat(zone.above)
    net.WriteFloat(zone.below)
    net.WriteFloat(snapshot.zoneEndsAt)
    net.WriteFloat(snapshot.matchEndsAt)
    net.WriteUInt(snapshot.control, 2)
    net.WriteBool(snapshot.contested)
    net.WriteUInt(snapshot.scores[1], 10)
    net.WriteUInt(snapshot.scores[2], 10)
end

function hp.ReadSnapshot()
    local generation, revision, visit, active = net.ReadUInt(32), net.ReadUInt(32), net.ReadUInt(16), net.ReadBool()
    local zone = { id = net.ReadString(), pos = net.ReadVector(), radius = net.ReadFloat(),
        above = net.ReadFloat(), below = net.ReadFloat() }
    local zoneEndsAt, matchEndsAt = net.ReadFloat(), net.ReadFloat()
    local control, contested = net.ReadUInt(2), net.ReadBool()
    return { generation = generation, revision = revision, visit = visit, active = active, zone = zone,
        zoneEndsAt = zoneEndsAt, matchEndsAt = matchEndsAt, control = control, contested = contested,
        scores = { net.ReadUInt(10), net.ReadUInt(10) } }
end
