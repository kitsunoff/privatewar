-- Starter content integrates the compiled catalogue with existing rewards and modes.
local ids = {
    "kills", "headshots", "kills_category", "headshots_category", "kills_weapon", "kills_mode", "kills_playlist",
    "longshots", "hipfire", "captures", "kc_confirms", "snd_plants", "streaks_earned", "streak_kills",
    "medals_multikill", "wins", "matches_played", "match_kills", "life_kills", "quick_kills", "combo_objective",
    "win_streak"
}

---@type table<string, string>
local cards = {
    headshots = "challenge_headshots", longshots = "challenge_longshots", captures = "challenge_captures",
    streak_kills = "challenge_streak_kills", life_kills = "challenge_life_kills", wins = "challenge_wins"
}

---@type table<PW.ChallengeTier, { xp: integer, currency: integer }>
local defaults = { easy = { xp = 2500, currency = 50 }, medium = { xp = 5000, currency = 100 },
    hard = { xp = 10000, currency = 200 } }

---@param id string
---@return PW.ChallengeTemplate
local function template(id)
    local lib = assert(PW.Challenges)
    local registry = assert(PW.Registries.challenges)
    local def = assert(registry.GetStored(id), "missing starter challenge " .. id)
    local parsed, reason = lib._Compile(id, def, lib._CustomEventTypes)
    return assert(parsed, "invalid starter challenge " .. id .. ": " .. (reason or "unknown reason"))
end

return {
    groupName = "PW starter weekly challenges",
    cases = {
        {
            name = "Starter pool: every core challenge definition validates",
            func = function()
                for _, id in ipairs(ids) do expect(template(id).id).to.equal(id) end
            end
        },
        {
            name = "Starter pool: the normal enabled catalogue fills two easy, two medium and one hard slot",
            func = function()
                local lib = assert(PW.Challenges)
                local catalogue = lib._ChallengeCatalogue()
                local week = lib._Select(2967, catalogue, { count = 5, seed = 0 })
                local counts = { easy = 0, medium = 0, hard = 0 }
                for _, instance in ipairs(week.items) do counts[instance.tier] = counts[instance.tier] + 1 end
                expect(#week.items).to.equal(5)
                expect(counts).to.deepEqual({ easy = 2, medium = 2, hard = 1 })
            end
        },
        {
            name = "Starter pool: card rewards use the intended item on every existing tier",
            func = function()
                local unlocks = assert(PW.Unlocks)
                for id, card in pairs(cards) do
                    local compiled = template(id)
                    local entry = { kind = "cards", id = card }
                    expect(unlocks.Describe(entry).valid).to.beTrue()
                    expect(compiled.definition.Rewards ~= nil).to.beTrue()
                    local rewards = assert(compiled.definition.Rewards)
                        --[[@as table<PW.ChallengeTier, PW.ChallengeReward>]]
                    for _, tier in ipairs(compiled.tiers) do
                        local reward = rewards[tier]
                        expect(reward ~= nil).to.beTrue()
                        expect(reward.xp).to.equal(defaults[tier].xp)
                        expect(reward.currency).to.equal(defaults[tier].currency)
                        expect(reward.items).to.deepEqual({ entry })
                    end
                    if id == "life_kills" then expect(compiled.tiers).to.deepEqual({ "medium", "hard" }) end
                end
            end
        }
    }
}
