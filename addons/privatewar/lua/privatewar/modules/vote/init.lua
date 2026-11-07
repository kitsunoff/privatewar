-- Vote module, server glue (T-2.13; 08-lobby.md d.5; 00-core.md d.2, d.5). Thin wrappers around the pure rules in
-- shared.lua. Entering VOTE opens a session: options sampled from the active playlist (pw_playlist_active), or in
-- Custom the current mode on the curated map list (PW.MapList.GetList; 03-mapdata.md d.9). Humans vote through
-- pw_vote_cast; when every human has voted, or the host picks ("Pick myself", privilege pw.vote.pick), the vote
-- ends at once through PW.Match.EndVote. The core asks the question hook PW_NextMatch at the end of VOTE; the
-- answer here is the host's pick or the winner (a tie broken at random), and the core starts it through its usual
-- path (a map change included). Engine calls are fields of the store, so tests drive everything with fakes.
--
-- Recent maps: the map of every match that goes live is pushed to the archived ConVar pw_vote_recent (newest
-- first, two kept), so the list survives the map change and a restart. Only matches of the real modes registry
-- open a vote or count as played (the core's tests drive the machine with modes of their own registries).

---A file-local class: methods of the global MODULE defined in two files are reported as duplicates.
---@class PW.VoteModuleServer : PW.Module
local module = MODULE --[[@as PW.VoteModuleServer]]

local lib = PW.Vote --[[@as PW.VoteLib]]

PW.Privilege(lib.Privilege, "superadmin")

util.AddNetworkString("pw_vote_state")

local recentVar = "pw_vote_recent"
CreateConVar(recentVar, "", { FCVAR_ARCHIVE }, "Private War: recently played maps, newest first (vote module)")

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

---@return PW.Registry?
local function modesRegistry()
    local registries = rawget(PW, "Registries") or {}
    return registries.modes
end

---The active playlist's modes and maps; nil in Custom or when the playlists module is missing.
---@return PW.VoteSource?
local function defaultSource()
    local playlists = rawget(PW, "Playlist") --[[@as PW.PlaylistLib?]]
    if playlists == nil or playlists.GetActive == nil or playlists.Get == nil then return nil end
    local id = playlists.GetActive()
    local entry = id ~= "" and playlists.Get(id) or nil
    if entry == nil then return nil end
    return { modes = entry.Modes, maps = entry.Maps }
end

---@return string[]
local function defaultPool()
    local mapList = rawget(PW, "MapList") --[[@as PW.MapListLib?]]
    return mapList ~= nil and mapList.GetList ~= nil and mapList.GetList() or {}
end

---The playlists module's "mode is enabled and offered on the map" test (installed map, MODE.MapData rule).
---@param modeId string
---@param map string
---@return boolean
local function defaultFits(modeId, map)
    local store = rawget(PW, "_Playlist") --[[@as PW.PlaylistStore?]]
    if store == nil then return false end
    return store.fits(modeId, map)
end

---@return PW.VoteOption?
local function defaultCurrent()
    local mode = PW.ActiveMode
    if mode == nil then return nil end
    return { mode = mode.ClassName --[[@as string]], map = game.GetMap() }
end

---@param id string
---@return table?
local function defaultResolve(id)
    local modes = modesRegistry()
    local mode = modes ~= nil and modes.Get(id) or nil
    if mode == nil or not mode:IsValid() then return nil end
    return mode
end

---@param mode any
---@return boolean
local function defaultIsMatchMode(mode)
    if not istable(mode) then return false end
    local own = rawget(mode, "_Registry") --[[@as PW.Registry?]]
    return own ~= nil and own.Kind == "modes"
end

---@param ply Player
---@param state PW.VoteState
local function sendState(ply, state)
    net.Start("pw_vote_state")
    lib._Encode(state, { uint = net.WriteUInt, string = net.WriteString, bool = net.WriteBool })
    net.Send(ply)
end

---@return string, string
local function readPick()
    local mode = net.ReadString()
    return mode, net.ReadString()
end

function lib._NewStore(opts)
    opts = opts or {}
    return {
        log = opts.log or defaultLog,
        rng = opts.rng or math.random,
        source = opts.source or defaultSource,
        pool = opts.pool or defaultPool,
        fits = opts.fits or defaultFits,
        current = opts.current or defaultCurrent,
        getRecent = opts.getRecent or function() return lib.ParseRecent(GetConVar(recentVar):GetString()) end,
        setRecent = opts.setRecent or function(list) GetConVar(recentVar):SetString(lib.FormatRecent(list)) end,
        humans = opts.humans or function() return lib.Humans(player.GetAll()) end,
        endVote = opts.endVote or function() return assert(PW.Match).EndVote() end,
        send = opts.send or sendState,
        resolveMode = opts.resolveMode or defaultResolve,
        count = opts.count or function() return tonumber(PW.Setting("vote.options")) or 3 end,
        allowRepeat = opts.allowRepeat or function() return PW.Setting("vote.allowrepeat") == true end,
        canPick = opts.canPick or function(ply) return PW.Can(ply, lib.Privilege) end,
        readIndex = opts.readIndex or function() return net.ReadUInt(8) end,
        readPick = opts.readPick or readPick,
        isMatchMode = opts.isMatchMode or defaultIsMatchMode
    }
end

PW._Vote = PW._Vote or lib._NewStore()

---@return PW.VoteStore
local function store()
    return PW._Vote
end

---@param ply any
---@return string
local function nick(ply)
    return istable(ply) and tostring(ply) or (IsValid(ply) and ply:Nick() or tostring(ply))
end

---@param st PW.VoteStore
---@param session PW.VoteSession
---@param ply any
---@return PW.VoteState
local function stateFor(st, session, ply)
    local counts = lib.Tally(session.votes, #session.options)
    ---@type PW.VoteStateOption[]
    local options = {}
    for index, option in ipairs(session.options) do
        local mode = st.resolveMode(option.mode)
        local name = mode ~= nil and tostring(mode.Name or option.mode) or option.mode
        options[index] = { mode = option.mode, name = name, map = option.map, votes = counts[index] }
    end
    return { options = options, mine = session.votes[ply] or 0, canPick = st.canPick(ply) }
end

function lib._SendState(ply)
    local st = store()
    local session = st.session
    if session == nil then return end
    st.send(ply, stateFor(st, session, ply))
end

local function broadcast()
    for _, ply in ipairs(store().humans()) do lib._SendState(ply) end
end

function lib.Open()
    local st = store()
    local current = st.current()
    local source = st.source()
    if source == nil then source = { modes = current ~= nil and { [current.mode] = 1 } or {} } end
    local options = lib.Candidates({
        modes = source.modes, maps = source.maps or st.pool(), fits = st.fits, recent = st.getRecent(),
        current = current, allowRepeat = st.allowRepeat(), count = st.count(), rng = st.rng
    })
    if #options == 0 then
        st.session = nil
        st.log("vote: nothing to offer, the same mode repeats")
        return nil
    end
    st.session = lib.NewSession(options)
    broadcast()
    return st.session
end

function lib.Close()
    store().session = nil
end

---Ends the vote early (once): every later vote is refused.
---@param st PW.VoteStore
---@param session PW.VoteSession
---@param why string
local function finish(st, session, why)
    session.ended = true
    st.log("vote ended early: " .. why)
    st.endVote()
end

function lib._Cast(ply, index)
    local st = store()
    local session = st.session
    if session == nil then return false, "closed" end
    local ok, reason = lib.Cast(session, ply, ply:IsBot() == true, index)
    if not ok then return false, reason end
    broadcast()
    if lib.AllVoted(st.humans(), session.votes) then finish(st, session, "every human voted") end
    return true
end

function lib._Pick(ply, modeId, map)
    local st = store()
    local session = st.session
    if session == nil then return false, "closed" end
    if session.ended then return false, "ended" end
    if not isstring(modeId) or not isstring(map) or st.resolveMode(modeId) == nil or not st.fits(modeId, map) then
        st.log(string.format("vote pick from %s refused: %s on %s does not fit", nick(ply), tostring(modeId),
            tostring(map)))
        return false, "fits"
    end
    session.picked = { mode = modeId, map = map }
    finish(st, session, string.format("%s picked %s on %s", nick(ply), modeId, map))
    return true
end

---@param st PW.VoteStore
---@param session PW.VoteSession
---@return PW.VoteOption
local function decide(st, session)
    if session.result ~= nil then return session.result end
    local result = session.picked
    if result == nil then
        local counts = lib.Tally(session.votes, #session.options)
        result = session.options[lib.Winner(counts, st.rng) or 1]
        st.log(string.format("vote result: %s on %s", result.mode, result.map))
    end
    session.result = result
    return result
end

function lib.Result()
    local st = store()
    local session = st.session
    if session == nil then return nil end
    local result = decide(st, session)
    local mode = st.resolveMode(result.mode)
    if mode == nil then
        st.log(string.format("vote result %s is no longer a mode, the same mode repeats", result.mode))
        return nil
    end
    return { mode = mode, map = result.map }
end

function lib._Played(map)
    local st = store()
    st.setRecent(lib.PushRecent(st.getRecent(), map))
end

---@param phase PW.PhaseName
---@param oldPhase PW.PhaseName
function module:PW_PhaseChange(phase, oldPhase)
    local st = store()
    if phase ~= "VOTE" then lib.Close() end
    if not st.isMatchMode(PW.ActiveMode) then return end
    if phase == "VOTE" then
        lib.Open()
    elseif phase == "LIVE" and oldPhase == "PREMATCH" then
        lib._Played(game.GetMap())
    end
end

---@return PW.NextMatch?
function module:PW_NextMatch()
    return lib.Result()
end

PW.HookFor(module, "PlayerDisconnected", function(_, ply)
    local session = store().session
    if session ~= nil then session.votes[ply] = nil end
end)

function lib._RegisterNet(owner)
    local netLib = assert(PW.Net)
    owner = owner or module
    netLib.Receive("pw_vote_cast", { who = "any", phases = { "VOTE" }, rate = 4, maxLen = 4, owner = owner },
        function(ply) lib._Cast(ply, store().readIndex()) end)
    netLib.Receive("pw_vote_pick", { who = lib.Privilege, phases = { "VOTE" }, rate = 2, maxLen = 160, owner = owner },
        function(ply)
            local modeId, map = store().readPick()
            lib._Pick(ply, modeId, map)
        end)
    netLib.Receive("pw_vote_request", { who = "any", phases = { "VOTE" }, rate = 2, maxLen = 8, owner = owner },
        function(ply) lib._SendState(ply) end)
end

lib._RegisterNet()
