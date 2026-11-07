-- T-6.3 Hitmarker (09-hud.md d.2: hitmarker, red on kill). Pure: the classification of a hit from damage facts, the
-- fade over time, the merge of several hits of one tick, who gets told. The server path runs over an injected sender
-- and deferral; humans are plain tables, the one bot is real. Drawing is a checkpoint.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.HitmarkerLib
local function lib()
    return must(PW.Hitmarker)
end

---A human attacker stand-in.
---@return table
local function human()
    return { IsValid = function() return true end, IsPlayer = function() return true end,
        IsBot = function() return false end }
end

---@class PW.HitmarkerTestRig
---@field sent { ply: any, kind: integer }[]
---@field queue function[]
---@field store PW.HitmarkerStore

---A store whose sender records and whose deferral queues until the "end of the tick".
---@return PW.HitmarkerTestRig
local function rig()
    ---@type { ply: any, kind: integer }[]
    local sent = {}
    ---@type function[]
    local queue = {}
    local store = lib()._NewStore({
        send = function(ply, kind) sent[#sent + 1] = { ply = ply, kind = kind } end,
        defer = function(fn) queue[#queue + 1] = fn end
    })
    return { sent = sent, queue = queue, store = store }
end

---@param r PW.HitmarkerTestRig
local function endTick(r)
    local queue = r.queue
    for i = 1, #queue do queue[i]() end
    for i = #queue, 1, -1 do queue[i] = nil end
end

---@param r PW.HitmarkerTestRig
---@param attacker any
---@param victim any
---@param dmg number
---@param killed boolean
---@param hitgroup integer
local function hit(r, attacker, victim, dmg, killed, hitgroup)
    lib()._Handle(r.store, { attacker = attacker, victim = victim, dmg = dmg, killed = killed, hitgroup = hitgroup })
end

return {
    groupName = "PW HUD hitmarker",
    cases = {
        {
            name = "Classification: a damaging hit is a hit, a head hit a headshot, a lethal one a kill",
            func = function()
                local classify = lib()._Classify
                expect(classify({ dmg = 20, killed = false, hitgroup = HITGROUP_CHEST })).to.equal("hit")
                expect(classify({ dmg = 20, killed = false, hitgroup = HITGROUP_HEAD })).to.equal("headshot")
                expect(classify({ dmg = 20, killed = true, hitgroup = HITGROUP_CHEST })).to.equal("kill")
                expect(classify({ dmg = 20, killed = true, hitgroup = HITGROUP_HEAD })).to.equal("kill")
                expect(classify({ dmg = 0, killed = true, hitgroup = HITGROUP_GENERIC })).to.equal("kill")
                expect(classify({ dmg = 0, killed = false, hitgroup = HITGROUP_HEAD })).to.beNil()
                expect(classify({ dmg = -5, killed = false, hitgroup = HITGROUP_GENERIC })).to.beNil()
            end
        },
        {
            name = "Wire: kinds map to 1..3 and back, anything else decodes to nil",
            func = function()
                local l = lib()
                expect(l._Encode("hit")).to.equal(1)
                expect(l._Encode("headshot")).to.equal(2)
                expect(l._Encode("kill")).to.equal(3)
                expect(l._Decode(1)).to.equal("hit")
                expect(l._Decode(2)).to.equal("headshot")
                expect(l._Decode(3)).to.equal("kill")
                expect(l._Decode(0)).to.beNil()
                expect(l._Decode(4)).to.beNil()
            end
        },
        {
            name = "Fade: alpha starts at 1, falls monotonically and is 0 at and after the duration",
            func = function()
                local alpha, d = lib()._Alpha, lib().Duration
                expect(d >= 0.2 and d <= 0.3).to.beTrue()
                expect(alpha(0, d)).to.equal(1)
                expect(alpha(d / 2, d) < alpha(d / 4, d)).to.beTrue()
                expect(alpha(d / 2, d) > 0).to.beTrue()
                expect(alpha(d, d)).to.equal(0)
                expect(alpha(d * 10, d)).to.equal(0)
                expect(alpha(-1, d)).to.equal(1)
            end
        },
        {
            name = "Merge: the strongest kind wins whatever the order",
            func = function()
                local merge = lib()._Merge
                expect(merge(nil, "hit")).to.equal("hit")
                expect(merge("hit", "headshot")).to.equal("headshot")
                expect(merge("kill", "hit")).to.equal("kill")
                expect(merge("headshot", "kill")).to.equal("kill")
                expect(merge("headshot", "hit")).to.equal("headshot")
            end
        },
        {
            name = "Several hits within one tick merge into one marker with the strongest kind",
            func = function()
                local r = rig()
                local attacker, victim = human(), {}
                hit(r, attacker, victim, 10, false, HITGROUP_CHEST)
                hit(r, attacker, victim, 10, true, HITGROUP_CHEST)
                hit(r, attacker, victim, 10, false, HITGROUP_HEAD)
                expect(#r.sent).to.equal(0)
                expect(#r.queue).to.equal(1)
                endTick(r)
                expect(#r.sent).to.equal(1)
                expect(must(r.sent[1]).ply).to.equal(attacker)
                expect(must(r.sent[1]).kind).to.equal(3)
                -- The next tick starts clean.
                hit(r, attacker, victim, 10, false, HITGROUP_CHEST)
                endTick(r)
                expect(#r.sent).to.equal(2)
                expect(must(r.sent[2]).kind).to.equal(1)
            end
        },
        {
            name = "Two attackers in one tick get one marker each",
            func = function()
                local r = rig()
                local victim = {}
                hit(r, human(), victim, 10, false, HITGROUP_CHEST)
                hit(r, human(), victim, 10, true, HITGROUP_CHEST)
                endTick(r)
                expect(#r.sent).to.equal(2)
            end
        },
        {
            name = "The server tells only a human attacker: never a bot, a world or NPC attacker, or self-damage",
            func = function()
                local r = rig()
                local human1 = human()
                local bot = player.CreateNextBot("PW hitmarker test")
                assert(IsValid(bot), "could not create a bot: needs a listen server with free slots")
                local ok, err = pcall(function()
                    local victim = {}
                    hit(r, bot, victim, 10, false, HITGROUP_CHEST)
                    hit(r, game.GetWorld(), victim, 10, false, HITGROUP_CHEST)
                    hit(r, nil, victim, 10, false, HITGROUP_CHEST)
                    hit(r, { IsValid = function() return true end, IsPlayer = function() return false end }, victim,
                        10, false, HITGROUP_CHEST)
                    hit(r, human1, human1, 10, false, HITGROUP_CHEST)
                    endTick(r)
                    expect(#r.sent).to.equal(0)
                    expect(lib()._Eligible(bot, victim)).to.beFalse()
                    expect(lib()._Eligible(human1, victim)).to.beTrue()
                    hit(r, human1, victim, 10, false, HITGROUP_CHEST)
                    endTick(r)
                    expect(#r.sent).to.equal(1)
                    expect(must(r.sent[1]).ply).to.equal(human1)
                end)
                bot:Kick("PW hitmarker test finished")
                assert(ok, err)
            end
        },
        {
            name = "A hit without damage and an attacker gone before the tick end send nothing",
            func = function()
                local r = rig()
                local attacker = human()
                hit(r, attacker, {}, 0, false, HITGROUP_HEAD)
                expect(#r.queue).to.equal(0)
                hit(r, attacker, {}, 5, false, HITGROUP_HEAD)
                attacker.IsValid = function() return false end
                endTick(r)
                expect(#r.sent).to.equal(0)
            end
        },
        {
            name = "The hitmarker element is registered",
            func = function()
                local registry = must(PW.Registries["hud"])
                expect(registry.Get("hitmarker")).to.exist()
            end
        }
    }
}
