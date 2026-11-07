-- T-6.4 Score popups and medals (09-hud.md d.2). Pure: the merge/stack of score popups, the fade, the medal queue,
-- the text of an event, the owner-only server send over an injected sender. Drawing is a checkpoint. No bots.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.HudLib
local function hud()
    return must(PW.HUD)
end

---A player stand-in for the owner-only send (and, with Team and SetNW2Int, for Award).
---@param bot? boolean
---@return Player
local function fakePlayer(bot)
    return {
        IsValid = function() return true end,
        IsBot = function() return bot == true end,
        Team = function() return 0 end,
        SetNW2Int = function() end
    } --[[@as Player]]
end

return {
    groupName = "PW HUD popups",
    cases = {
        {
            name = "Merge: the same event within the window adds its points into one popup and refreshes it",
            func = function()
                local l = hud()
                local state = l._PopupNew()
                l._PopupAdd(state, "kill", "Kill", 100, 10)
                local entry = l._PopupAdd(state, "kill", "Kill", 100, 10 + l.PopupMergeWindow - 0.01)
                expect(state.count).to.equal(1)
                expect(entry.points).to.equal(200)
                expect(entry.label).to.equal("+200 Kill")
                expect(entry.at).to.equal(10 + l.PopupMergeWindow - 0.01)
            end
        },
        {
            name = "Merge: after the window, or for another event, a separate popup is stacked newest first",
            func = function()
                local l = hud()
                local state = l._PopupNew()
                l._PopupAdd(state, "kill", "Kill", 100, 10)
                l._PopupAdd(state, "headshot", "Headshot", 50, 10)
                expect(state.count).to.equal(2)
                expect(must(state.list[1]).id).to.equal("headshot")
                expect(must(state.list[2]).id).to.equal("kill")
                l._PopupAdd(state, "kill", "Kill", 100, 10 + l.PopupMergeWindow + 0.5)
                expect(state.count).to.equal(3)
                expect(must(state.list[1]).points).to.equal(100)
                expect(must(state.list[3]).points).to.equal(100)
            end
        },
        {
            name = "Stack: more than the maximum drops the oldest popup",
            func = function()
                local l = hud()
                local state = l._PopupNew()
                for i = 1, l.PopupMax + 2 do l._PopupAdd(state, "e" .. i, "E" .. i, i, 10) end
                expect(state.count).to.equal(l.PopupMax)
                expect(must(state.list[1]).id).to.equal("e" .. (l.PopupMax + 2))
                expect(must(state.list[l.PopupMax]).id).to.equal("e3")
            end
        },
        {
            name = "Fade: full alpha during the hold, then linear to 0 at hold plus fade, monotonic",
            func = function()
                local l = hud()
                local alpha, hold, fade = l._PopupAlpha, l.PopupHold, l.PopupFade
                expect(alpha(0)).to.equal(1)
                expect(alpha(hold)).to.equal(1)
                expect(alpha(hold + fade / 2) < 1).to.beTrue()
                expect(alpha(hold + fade / 2) > 0).to.beTrue()
                expect(alpha(hold + fade * 0.75) < alpha(hold + fade * 0.25)).to.beTrue()
                expect(alpha(hold + fade)).to.equal(0)
                expect(alpha(hold + fade + 5)).to.equal(0)
                expect(alpha(-1)).to.equal(1)
            end
        },
        {
            name = "Expiry: popups past hold plus fade are removed, younger ones keep their order",
            func = function()
                local l = hud()
                local state = l._PopupNew()
                l._PopupAdd(state, "kill", "Kill", 100, 10)
                l._PopupAdd(state, "headshot", "Headshot", 50, 10 + l.PopupHold)
                l._PopupPrune(state, 10 + l.PopupHold + l.PopupFade + 0.01)
                expect(state.count).to.equal(1)
                expect(must(state.list[1]).id).to.equal("headshot")
                l._PopupPrune(state, 10 + 2 * l.PopupHold + 2 * l.PopupFade)
                expect(state.count).to.equal(0)
                expect(state.list[1]).to.beNil()
            end
        },
        {
            name = "Medal queue: medals show one after another in arrival order, each for the full duration",
            func = function()
                local l = hud()
                local state = l._MedalNew()
                local d = l.MedalDuration
                l._MedalAdd(state, "first_blood", "First Blood", 100, 5)
                l._MedalAdd(state, "double_kill", "Double Kill", 50, 5)
                l._MedalAdd(state, "streak5", "Streak 5", 150, 5.1)
                local first = must(l._MedalCurrent(state, 5))
                expect(first.id).to.equal("first_blood")
                expect(must(l._MedalCurrent(state, 5 + d - 0.01)).id).to.equal("first_blood")
                local second = must(l._MedalCurrent(state, 5 + d))
                expect(second.id).to.equal("double_kill")
                expect(second.startedAt).to.equal(5 + d)
                expect(must(l._MedalCurrent(state, 5 + 2 * d - 0.01)).id).to.equal("double_kill")
                expect(must(l._MedalCurrent(state, 5 + 2 * d)).id).to.equal("streak5")
                expect(l._MedalCurrent(state, 5 + 3 * d)).to.beNil()
                expect(state.count).to.equal(0)
            end
        },
        {
            name = "Medal queue: a late call skips nothing, a medal that waited starts when its turn comes",
            func = function()
                local l = hud()
                local state = l._MedalNew()
                local d = l.MedalDuration
                l._MedalAdd(state, "revenge", "Revenge", 50, 0)
                l._MedalAdd(state, "saviour", "Saviour", 50, 0)
                expect(must(l._MedalCurrent(state, 0)).id).to.equal("revenge")
                -- The first expired long ago, but the second still gets its full duration from now.
                local current = must(l._MedalCurrent(state, d * 4))
                expect(current.id).to.equal("saviour")
                expect(current.startedAt).to.equal(d * 4)
                expect(must(l._MedalCurrent(state, d * 4 + d - 0.01)).id).to.equal("saviour")
                expect(l._MedalCurrent(state, d * 5)).to.beNil()
            end
        },
        {
            name = "Medal queue: the length is capped, extra medals are dropped",
            func = function()
                local l = hud()
                local state = l._MedalNew()
                for i = 1, l.MedalMax + 3 do l._MedalAdd(state, "m" .. i, "M", 1, 0) end
                expect(state.count).to.equal(l.MedalMax)
            end
        },
        {
            name = "Medal fade: in, hold, out; 0 outside the duration",
            func = function()
                local l = hud()
                local alpha, d = l._MedalAlpha, l.MedalDuration
                expect(alpha(0)).to.equal(0)
                expect(alpha(l.MedalFadeIn / 2) > 0 and alpha(l.MedalFadeIn / 2) < 1).to.beTrue()
                expect(alpha(d / 2)).to.equal(1)
                expect(alpha(d - l.MedalFadeOut / 2) > 0 and alpha(d - l.MedalFadeOut / 2) < 1).to.beTrue()
                expect(alpha(d)).to.equal(0)
                expect(alpha(d + 1)).to.equal(0)
            end
        },
        {
            name = "Text: a resolved phrase is used, an unresolved key falls back to the humanised id",
            func = function()
                local l = hud()
                local phrases = { ["#pw.score.kill"] = "Kill" }
                local function phrase(key) return phrases[key] or key:sub(2) end
                expect(l._PopupText("#pw.score.kill", "kill", phrase)).to.equal("Kill")
                expect(l._PopupText("#pw.score.first_blood", "first_blood", phrase)).to.equal("First Blood")
                expect(l._PopupText(nil, "dom_capture", phrase)).to.equal("Dom Capture")
                expect(l._PopupText("Plain", "x", phrase)).to.equal("Plain")
            end
        },
        {
            name = "Kind: a medal popup only for a Medal event that the medals module announces",
            func = function()
                local l = hud()
                local ids = { "first_blood", "double_kill" }
                expect(l._PopupKind(true, "first_blood", ids)).to.equal("medal")
                expect(l._PopupKind(true, "headshot", ids)).to.equal("score")
                expect(l._PopupKind(false, "first_blood", ids)).to.equal("score")
                expect(l._PopupKind(nil, "kill", ids)).to.equal("score")
            end
        },
        {
            name = "Owner only: the send goes to the awarded human once, never to bots, invalid players or zero points",
            func = function()
                local score = must(PW.Score)
                ---@type { ply: Player, id: string, points: integer }[]
                local sent = {}
                local store = score._NewStore()
                store.popup = function(ply, id, points) sent[#sent + 1] = { ply = ply, id = id, points = points } end
                local owner, other = fakePlayer(), fakePlayer()
                expect(score._NotifyOwner(store, owner, "kill", 100)).to.beTrue()
                expect(#sent).to.equal(1)
                expect(must(sent[1]).ply).to.equal(owner)
                expect(must(sent[1]).ply == other).to.beFalse()
                expect(must(sent[1]).id).to.equal("kill")
                expect(must(sent[1]).points).to.equal(100)
                expect(score._NotifyOwner(store, fakePlayer(true), "kill", 100)).to.beFalse()
                expect(score._NotifyOwner(store, owner, "kill", 0)).to.beFalse()
                expect(score._NotifyOwner(store, owner, "kill", -5)).to.beFalse()
                local invalid = { IsValid = function() return false end, IsBot = function() return false end }
                expect(score._NotifyOwner(store, invalid --[[@as Player]], "kill", 100)).to.beFalse()
                expect(#sent).to.equal(1)
            end
        },
        {
            name = "Owner only: Award sends exactly one popup message, to the awarded player, with the final points",
            func = function()
                local score = must(PW.Score)
                ---@type { ply: Player, id: string, points: integer }[]
                local sent = {}
                local store = score._NewStore(function() end)
                store.popup = function(ply, id, points) sent[#sent + 1] = { ply = ply, id = id, points = points } end
                local registry = PW.Registry.New("score_events", { log = function() end, preRegister = function() end })
                registry.Register({ Name = "#pw.score.kill", Points = 100, Medal = false }, "kill")
                registry.ResolveAll()
                local owner = fakePlayer()
                local ok = score._Award(store, registry, owner, "kill")
                registry._Release()
                score._Reset(store)
                expect(ok).to.beTrue()
                expect(#sent).to.equal(1)
                expect(must(sent[1]).ply).to.equal(owner)
                expect(must(sent[1]).points).to.equal(100)
            end
        },
        {
            name = "Wire: points are rounded and clamped to the UInt(16) range",
            func = function()
                local score = must(PW.Score)
                expect(score._PopupPoints(100)).to.equal(100)
                expect(score._PopupPoints(70000)).to.equal(65535)
                expect(score._PopupPoints(12.6)).to.equal(13)
            end
        }
    }
}
