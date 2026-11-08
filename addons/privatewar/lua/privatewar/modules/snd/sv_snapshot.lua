-- Server-only recipient-specific, fixed-shape snapshots. No client request and no hidden enemy/carrier payload.
local lib = PW.SND --[[@as PW.SNDLib]]
local phases = { carried = 1, dropped = 2, planted = 3, resolved = 4 }
util.AddNetworkString("pw_snd_state")

---@param state PW.SNDState?
---@param ply Player
local function send(state, ply)
    local member = state ~= nil and state.roster[lib.Identity(ply)] or nil
    local side = member ~= nil and member.team or 0
    local view = state ~= nil and lib.Snapshot(state, side, lib.Identity(ply), CurTime()) or nil
    net.Start("pw_snd_state")
    net.WriteUInt(PW._SND.generation, 32)
    net.WriteUInt(PW._SND.serial, 32)
    net.WriteUInt(view ~= nil and phases[view.phase] or 0, 3)
    if view ~= nil then
        net.WriteFloat(view.deadline)
        net.WriteFloat(view.fuse)
        net.WriteString(view.site or "")
        net.WriteUInt(view.carrier or 0, 16)
        net.WriteBool(view.pos ~= nil)
        if view.pos ~= nil then net.WriteVector(view.pos) end
        net.WriteUInt(view.action == "plant" and 1 or (view.action == "defuse" and 2 or 0), 2)
        net.WriteUInt(math.floor(view.progress * 255 + 0.5), 8)
    end
    net.Send(ply)
end

function lib.Publish(state, force)
    local store, now = PW._SND, CurTime()
    if state ~= nil and not force and now < store.nextSnapshot then return end
    store.nextSnapshot = now + 0.2
    store.serial = store.serial + 1
    for _, ply in ipairs(player.GetHumans()) do send(state, ply) end
end
