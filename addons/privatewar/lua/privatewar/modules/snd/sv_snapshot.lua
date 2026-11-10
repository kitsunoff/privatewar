-- Server-only recipient-specific, fixed-shape snapshots. No client request and no hidden enemy/carrier payload.
local lib = PW.SND --[[@as PW.SNDLib]]
util.AddNetworkString("pw_snd_state")
util.AddNetworkString("pw_snd_sites")

---@param state PW.SNDState?
---@param ply Player
local function send(state, ply)
    local member = state ~= nil and state.roster[lib.Identity(ply)] or nil
    local side = member ~= nil and member.team or 0
    local view = state ~= nil and lib.Snapshot(state, side, lib.Identity(ply), CurTime()) or nil
    net.Start("pw_snd_state")
    lib._WriteState(net --[[@as PW.SNDWire]], PW._SND.generation, PW._SND.serial, view)
    net.Send(ply)
    -- Legacy clients have no receiver for this optional message; their original state remains usable.
    net.Start("pw_snd_sites")
    lib._WriteSites(net --[[@as PW.SNDWire]], PW._SND.generation, PW._SND.serial,
        view ~= nil and view.sites or nil)
    net.Send(ply)
end

function lib.Publish(state, force)
    local store, now = PW._SND, CurTime()
    if state ~= nil and not force and now < store.nextSnapshot then return end
    store.nextSnapshot = now + 0.2
    store.serial = store.serial + 1
    for _, ply in ipairs(player.GetHumans()) do send(state, ply) end
end
