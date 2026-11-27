-- One session week and separate owner-local progress/file batches.
local lib = assert(PW.Challenges)

function lib._ChallengeHuman(server, ply)
    return server.deps.isPlayer(ply) and not ply:IsBot()
end

function lib._ChallengeParticipant(server, ply)
    return lib._ChallengeHuman(server, ply) and ply:Team() ~= TEAM_SPECTATOR and ply:GetObserverMode() == OBS_MODE_NONE
end

---@param deps PW.ChallengeServerDeps
---@param index integer
---@return PW.ChallengeWeek, table<string, PW.ChallengeTemplate>, table<string, PW.ChallengeCombine>
local function selectWeek(deps, index)
    local candidates = deps.catalogue()
    local week = lib._Select(index, candidates, deps.options ~= nil and deps.options() or {})
    ---@type table<string, PW.ChallengeTemplate>
    local templates = {}
    for _, candidate in ipairs(candidates) do templates[candidate.template.id] = candidate.template end
    ---@type table<string, PW.ChallengeCombine>
    local modes = {}
    for _, instance in ipairs(week.items) do modes[instance.id] = templates[instance.template].mode end
    return week, templates, modes
end

function lib._NewServer(deps)
    local index = lib.WeekIndex(deps.utc())
    local week, templates, modes = selectWeek(deps, index)
    ---@type PW.ChallengeServer
    local server = { deps = deps, week = week, templates = templates, modes = modes,
        plan = lib._ProgressPlan(week, templates, false), players = {}, serial = 0, roundOpen = false,
        backwardsLogged = false, weaponFacts = {} }
    lib._ScheduleServer(server)
    return server
end

function lib._ChallengeConnection(server, ply)
    local existing = server.players[ply]
    if existing ~= nil then return existing end
    ---@type PW.ChallengeConnection
    local connection = { progress = lib._NewProgress(server.plan), dirty = {}, persist = false,
        lifeKills = 0, attachments = {} }
    server.players[ply] = connection
    if server.match ~= nil then
        lib._ResetProgress(server.plan, connection.progress, "match_start")
        if server.roundOpen then lib._ResetProgress(server.plan, connection.progress, "round_start") end
    end
    return connection
end

---@param server PW.ChallengeServer
---@param ply Player
---@param keys? table<string, boolean>
---@return PW.ChallengeFileItems
local function viewItems(server, ply, keys)
    local connection = lib._ChallengeConnection(server, ply)
    ---@type PW.ChallengeFileItems
    local out = {}
    for id in pairs(keys or server.plan.entries) do
        local progress = lib._ReadProgress(server.plan, connection.progress, id)
        if progress ~= nil then out[id] = { p = progress.values, done = progress.done } end
    end
    return out
end

function lib._SendChallengeState(server, ply)
    if not lib._ChallengeHuman(server, ply) then return end
    local connection = lib._ChallengeConnection(server, ply)
    server.deps.sendState(ply, {
        week = server.week, items = viewItems(server, ply), bonus = connection.progress.bonus
    })
end

function lib._FlushChallengeProgress(server, ply, force)
    local connection = server.players[ply]
    if connection == nil or next(connection.dirty) == nil or not lib._ChallengeHuman(server, ply) then return end
    local now = server.deps.clock()
    if not force and connection.lastSend ~= nil and now - connection.lastSend < lib.ProgressInterval then return end
    local keys = connection.dirty
    connection.dirty, connection.lastSend = {}, now
    local items = viewItems(server, ply, keys)
    if next(items) ~= nil then server.deps.sendProgress(ply, items) end
end

function lib._FlushChallengeDelta(server, ply)
    local connection = server.players[ply]
    if connection == nil or not connection.persist or not lib._ChallengeHuman(server, ply) then return end
    local batch = connection.batch
    if batch == nil then
        batch = { session = math.random(1, 2147483647), seq = 0 }
        connection.batch = batch
    end
    batch.seq = batch.seq + 1
    connection.persist = false
    local saved = lib._SaveProgress(server.plan, connection.progress)
    server.deps.sendDelta(ply, { session = batch.session, seq = batch.seq, label = server.week.label,
        index = saved.index, items = saved.items, bonus = saved.bonus == true })
end

function lib._FlushChallenges(server, view, file, force)
    for ply in pairs(server.players) do
        if view then lib._FlushChallengeProgress(server, ply, force) end
        if file then lib._FlushChallengeDelta(server, ply) end
    end
end

function lib._ScheduleServer(server)
    local schedule = server.deps.schedule
    schedule("PW.Challenges.Week", 60, 0, function() lib._RefreshWeek(server) end)
    schedule("PW.Challenges.Progress", lib.ProgressInterval, 0, function()
        lib._FlushChallenges(server, true, false)
    end)
    schedule("PW.Challenges.Delta", 10, 0, function() lib._FlushChallenges(server, false, true) end)
end

---@param server PW.ChallengeServer
---@param connection PW.ChallengeConnection
---@param rows PW.ChallengeFileWeeks?
local function reproject(server, connection, rows)
    local profile = lib._UploadWeek(rows or {}, server.week, server.modes)
    connection.progress = lib._NewProgress(server.plan, profile)
    connection.dirty, connection.persist, connection.lastSend = {}, false, nil
    if server.match ~= nil then
        lib._ResetProgress(server.plan, connection.progress, "match_start")
        if server.roundOpen then lib._ResetProgress(server.plan, connection.progress, "round_start") end
    end
end

function lib._AcceptUpload(server, ply, rows)
    if not lib._ChallengeHuman(server, ply) then return end
    local connection = lib._ChallengeConnection(server, ply)
    if connection.upload ~= nil then return end
    -- Wire decoding has already bounded counts, keys and counters. Retain all validated rows,
    -- but every activation independently projects the matching label/index against current targets.
    ---@type PW.ChallengeFileWeeks
    local validated = {}
    for label, row in pairs(rows) do
        if lib.WeekLabel(row.index) == label then validated[label] = row end
    end
    connection.upload = validated
    reproject(server, connection, validated)
    lib._SendChallengeState(server, ply)
end

---Week payloads are acyclic plain data. Compare without depending on the order
---of map keys or on the wire's omission of server-only rewards metadata.
---@param a table<any, any>
---@param b table<any, any>
---@return boolean
local function same(a, b)
    for key, value in pairs(a) do
        local other = b[key]
        if type(value) == "table" then
            if type(other) ~= "table" or not same(value, other) then return false end
        elseif value ~= other then
            return false
        end
    end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

function lib._RefreshWeek(server, refreshCatalogue)
    if server.match ~= nil or server.deps.phase() == "LIVE" then return end
    local index = lib.WeekIndex(server.deps.utc())
    if index < server.week.index then
        if not server.backwardsLogged then
            server.backwardsLogged = true
            server.deps.log("challenges: UTC moved backwards; keeping the session week")
        end
        return
    end
    local changed = index ~= server.week.index
    if not changed and not refreshCatalogue then return end
    local week, templates, modes = selectWeek(server.deps, index)
    if not changed and same(week, server.week) then
        server.templates, server.modes = templates, modes
        return
    end
    lib._FlushChallenges(server, true, true, true)
    local previous = server.plan
    server.week, server.templates, server.modes = week, templates, modes
    server.plan = lib._ProgressPlan(week, templates, false)
    for _, connection in pairs(server.players) do
        local rows = connection.upload
        if not changed then rows = { [week.label] = lib._SaveProgress(previous, connection.progress) } end
        reproject(server, connection, rows)
    end
    if changed then PW.Notify("PW_ChallengeWeek", week.label, week) end
    for _, ply in ipairs(server.deps.players()) do lib._SendChallengeState(server, ply) end
end

function lib._OpenMatch(server)
    local context = server.deps.matchContext()
    local oldPlan = server.plan
    server.match, server.serial = context, server.serial + 1
    local rounds = table.HasValue(context.modeBase, "round_base") or context.mode == "round_base"
    server.roundOpen = rounds and server.roundOpen
    server.plan = lib._ProgressPlan(server.week, server.templates, rounds)
    for _, connection in pairs(server.players) do
        connection.progress = lib._NewProgress(server.plan, lib._SaveProgress(oldPlan, connection.progress))
        lib._ResetProgress(server.plan, connection.progress, "match_start")
        if server.roundOpen then lib._ResetProgress(server.plan, connection.progress, "round_start") end
    end
    local now = server.deps.clock()
    for _, ply in ipairs(server.deps.players()) do
        if lib._ChallengeParticipant(server, ply) then lib._ChallengeConnection(server, ply).presentAt = now end
        lib._SendChallengeState(server, ply)
    end
end
