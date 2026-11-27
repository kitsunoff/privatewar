-- Only server-observed completions enqueue rewards. Unlocks owns the idempotency ledger and the payout batch.
local lib = assert(PW.Challenges)

---@param unlocks PW.UnlocksLib
---@param ply Player
---@param reward PW.ChallengeReward
---@return (PW.UnlockItem|string)[], number
local function resolveItems(unlocks, ply, reward)
    ---@type (PW.UnlockItem|string)[]
    local items = {}
    local currency = reward.currency or 0
    local substitute = reward.duplicateCurrency or 0
    for _, item in ipairs(reward.items or {}) do
        local description = unlocks.Describe(item)
        if not description.valid or unlocks.IsUnlocked(ply, description.kind, description.id) then
            currency = currency + substitute
        else
            items[#items + 1] = description.key
        end
    end
    return items, currency
end

---@param server PW.ChallengeServer
---@param ply Player
---@param claim string
---@param reward PW.ChallengeReward
---@return boolean
local function pay(server, ply, claim, reward)
    local unlocks = PW.Unlocks
    if unlocks == nil or not unlocks.IsReady(ply) then return false end
    if unlocks.HasClaim(ply, claim) then return true end
    local items, currency = resolveItems(unlocks, ply, reward)
    ---@type PW.UnlockGrantOptions
    local opts = { source = "challenge", grant = claim, xp = reward.xp or 0, currency = currency }
    local _, reason = unlocks.Grant(ply, items, opts)
    if (reason == "full" or reason == "toomany") and #items > 0 then
        opts.currency = currency + #items * (reward.duplicateCurrency or 0)
        _, reason = unlocks.Grant(ply, {}, opts)
    end
    if reason == nil or reason == "claimed" then return true end
    server.deps.log("challenges: reward " .. claim .. " deferred: " .. reason)
    return false
end

---@param server PW.ChallengeServer
---@param ply Player
---@param queue table<string, PW.ChallengePendingReward>
---@param claim string
---@param entry PW.ChallengePendingReward
local function attempt(server, ply, queue, claim, entry)
    if entry.busy then return end
    entry.busy = true
    if pay(server, ply, claim, entry.reward) then queue[claim] = nil end
    entry.busy = false
end

---@param week PW.ChallengeWeek
---@param id string
---@return PW.ChallengeReward?
local function getReward(week, id)
    if id == "bonus" then return week.bonus.reward end
    for _, item in ipairs(week.items) do if item.id == id then return item.reward end end
    return nil
end

function lib._QueueChallengeReward(server, ply, week, id)
    local reward = getReward(week, id)
    if reward == nil then return end
    local connection = lib._ChallengeConnection(server, ply)
    local queue = connection.rewards or {}
    connection.rewards = queue
    local claim = "challenge:" .. week.label .. ":" .. id
    if queue[claim] ~= nil then return end
    local entry = { reward = reward }
    queue[claim] = entry
    attempt(server, ply, queue, claim, entry)
end

function lib._RetryChallengeRewards(server)
    for ply, connection in pairs(server.players) do
        local queue = connection.rewards
        if queue ~= nil and lib._ChallengeHuman(server, ply) then
            for claim, entry in pairs(queue) do attempt(server, ply, queue, claim, entry) end
        end
    end
end
