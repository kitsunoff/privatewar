local module = MODULE
local lib = assert(PW.Challenges)
local uploadName = "pw_challenges_upload"

---@class PW.ChallengeClientView
---@field week PW.ChallengeWeek
---@field bonusDone boolean
---@field progress table<string, PW.ChallengeProgress>

---@class PW.ChallengeClientSession
---@field view? PW.ChallengeClientView
---@field stored? PW.ChallengeFile
---@field readOnly? boolean
---@field uploaded? boolean

-- Keep the same upload guard and persisted batch across Lua refreshes in this connection.
---@type PW.ChallengeClientSession
local client = rawget(lib, "_Client") or {}
rawset(lib, "_Client", client)

---@return PW.ChallengeFile
local function loadFile()
    local cached = client.stored
    if cached ~= nil then return cached end
    local stored, readOnly = lib._FileFromJson(file.Read(lib.FilePath, "DATA"))
    client.stored, client.readOnly = stored, readOnly
    if readOnly then print("[PW] challenges: newer client file version; progress storage is read-only") end
    return stored
end

---@param stored PW.ChallengeFile
local function saveFile(stored)
    local json = lib._FileToJson(stored, lib.WeekIndex(os.time()))
    if json == nil then
        print("[PW] challenges: could not encode client progress")
        return
    end
    file.CreateDir("privatewar")
    if not file.Write(lib.FilePath, json) then
        print("[PW] challenges: could not write client progress")
        return
    end
    -- Keep the cache in sync with the pruned file so a later clock change cannot restore discarded weeks.
    client.stored = lib._FileFromJson(json)
end

---@return PW.ChallengeClientView?
local function activeView()
    if not module:IsValid() then return nil end
    return client.view
end

function lib.GetWeek()
    local view = activeView()
    return view ~= nil and view.week or nil
end

function lib.GetActive()
    local view = activeView()
    return view ~= nil and view.week.items or {}
end

function lib.GetProgress(ply, id)
    if ply ~= LocalPlayer() or not IsValid(ply) then return nil end
    local view = activeView()
    return view ~= nil and view.progress[id] or nil
end

PW.HookFor(module, "InitPostEntity", function()
    if client.uploaded or not module:IsValid() or util.NetworkStringToID(uploadName) == 0 then return end
    local stored = loadFile()
    net.Start(uploadName)
    lib._WriteWire("upload", stored.weeks, net.WriteUInt)
    net.SendToServer()
    client.uploaded = true
end)

net.Receive("pw_challenges_state", function(bits)
    if not module:IsValid() then return end
    local packet = lib._ReadWire("state", bits, net.ReadUInt) --[[@as PW.ChallengeWireState?]]
    if packet == nil then return end
    ---@type PW.ChallengeClientView
    local view = { week = packet.week, bonusDone = packet.bonus, progress = {} }
    for _, instance in ipairs(packet.week.items) do
        local item = packet.items[instance.id]
        view.progress[instance.id] = { values = item.p, targets = instance.targets, done = item.done == true }
    end
    client.view = view
    PW.Notify("PW_ChallengesChanged", view.week)
end)

net.Receive("pw_challenges_progress", function(bits)
    local view = activeView()
    if view == nil then return end
    local items = lib._ReadWire("progress", bits, net.ReadUInt) --[[@as PW.ChallengeFileItems?]]
    if items == nil or next(items) == nil then return end
    for id, item in pairs(items) do
        local current = view.progress[id]
        if current == nil or #item.p ~= #current.targets then return end
    end
    for id, item in pairs(items) do
        local current = view.progress[id]
        for slot, target in ipairs(current.targets) do item.p[slot] = math.min(item.p[slot], target) end
        view.progress[id] = { values = item.p, targets = current.targets, done = item.done == true }
    end
    PW.Notify("PW_ChallengesChanged", view.week)
end)

net.Receive("pw_challenges_delta", function(bits)
    if not module:IsValid() then return end
    local delta = lib._ReadWire("delta", bits, net.ReadUInt) --[[@as PW.ChallengeDelta?]]
    if delta == nil then return end
    local current = loadFile()
    if client.readOnly then return end
    local stored, applied = lib._ApplyDelta(current, delta)
    if not applied then return end
    client.stored = stored
    saveFile(stored)
end)
