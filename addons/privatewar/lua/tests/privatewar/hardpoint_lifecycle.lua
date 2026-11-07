-- Integration characterization of mode glue, separate from reducer TDD and real-input movement evidence.
---@return PW.HardpointLib
local function lib()
    return assert(PW.Hardpoint)
end

---@return PW.HardpointMode
local function fixture()
    return { ClassName = "hardpoint", Name = "Hardpoint fixture", Teams = 2,
        _ScoreKey = "pw_hp_score_", Setting = function(_, key)
        return ({ zonetime = 60, scorelimit = 250, timelimit = 600 })[key]
    end } --[[@as PW.HardpointMode]]
end

return {
    groupName = "PW Hardpoint lifecycle",
    cases = {
        {
            name = "Hardpoint: Start publishes one active visit; Cleanup tombstone and repeated cleanup are idempotent",
            func = function()
                local hp, mode = lib(), fixture()
                ---@type PW.HardpointSnapshot[]
                local sent = {}
                stub(hp, "Send").with(function(snapshot) sent[#sent + 1] = snapshot end)
                hp.Start(mode)
                local runtime = assert(mode._Hardpoint)
                expect(#sent).to.equal(1)
                expect(sent[1].active).to.beTrue()
                expect(sent[1].visit).to.equal(1)
                expect(runtime.state.zoneEndsAt - runtime.state.startedAt).to.equal(60)
                expect(runtime.state.matchEndsAt - runtime.state.startedAt).to.equal(600)
                hp.Cleanup(mode)
                expect(mode._Hardpoint).to.beNil()
                expect(#sent).to.equal(2)
                expect(sent[2].active).to.beFalse()
                expect(sent[2].revision > sent[1].revision).to.beTrue()
                expect(hp.AcceptSnapshot(sent[2], sent[1])).to.equal(sent[2])
                hp.Cleanup(mode)
                hp.Think(mode)
                expect(#sent).to.equal(2)
                expect(GetGlobal2Int("pw_hp_score_1", -1)).to.equal(0)
                expect(GetGlobal2Int("pw_hp_score_2", -1)).to.equal(0)
            end
        },
        {
            name = "Hardpoint: visit cleanup notifies shared invalidation once, including repeated cleanup",
            func = function()
                local hp, mode = lib(), fixture()
                local calls, seenId, seenRevision = 0, "", 0
                local name = "PW.HardpointLifecycleInvalidation"
                hook.Add("PW_ObjectiveInvalidated", name, function(id, revision)
                    calls, seenId, seenRevision = calls + 1, id, revision
                end)
                stub(hp, "Send").with(function() end)
                local ok, err = pcall(function()
                    hp.Start(mode)
                    local runtime = assert(mode._Hardpoint)
                    local id, revision = runtime.objectiveId, runtime.objectiveRevision
                    hp.Cleanup(mode)
                    hp.Cleanup(mode)
                    expect(calls).to.equal(1)
                    expect(seenId).to.equal(id)
                    expect(seenRevision).to.equal(revision)
                end)
                hook.Remove("PW_ObjectiveInvalidated", name)
                hp.Cleanup(mode)
                assert(ok, tostring(err))
            end
        },
        {
            name = "Hardpoint: request wrapper rejects non-LIVE senders and payload without sending state",
            func = function()
                expect(assert(PW.Match).GetPhase() ~= "LIVE").to.beTrue()
                local sender = assert(player.GetHumans()[1])
                local sends = 0
                stub(lib(), "Send").with(function() sends = sends + 1 end)
                expect(assert(PW.Net)._Dispatch("pw_hp_request", 0, sender)).to.beFalse()
                expect(assert(PW.Net)._Dispatch("pw_hp_request", 8, sender)).to.beFalse()
                expect(sends).to.equal(0)
            end
        },
        {
            name = "Hardpoint: activation failure creates no runtime score or snapshot and keeps remote schema valid",
            func = function()
                local hp, mode = lib(), fixture()
                local calls = 0
                stub(hp, "CheckActivation").with(function() return false, "synthetic blocked hull" end)
                stub(hp, "Send").with(function() calls = calls + 1 end)
                local ok, err = pcall(hp.Start, mode)
                expect(ok).to.beFalse()
                expect(string.find(tostring(err), "synthetic blocked hull", 1, true) ~= nil).to.beTrue()
                expect(mode._Hardpoint).to.beNil()
                expect(calls).to.equal(0)
                expect(hp.ValidateLayout(assert(PW.Map).GetModeData("hardpoint"))).to.beTrue()
                hp.Cleanup(mode)
            end
        },
        {
            name = "Hardpoint: ordinary kills keep inherited rewards while hold ticks never award score events",
            func = function()
                local hp, mode = lib(), fixture()
                local modeDefinition = assert(PW.Modes.Get("hardpoint"))
                expect(modeDefinition.PW_PlayerKilled).to.equal(assert(PW.Modes.Get("tdm")).PW_PlayerKilled)
                expect(modeDefinition.PW_CanRespawn()).to.beTrue()
                local awards = 0
                stub(assert(PW.Score), "Award").with(function() awards = awards + 1 end)
                stub(hp, "Send").with(function() end)
                hp.Start(mode)
                local state = assert(mode._Hardpoint).state
                local zone = state.layout.zones[1]
                local actors = { { team = 1, pos = zone.pos, alive = true, observer = false, eligible = true } }
                hp.Step(state, { at = state.startedAt, actors = actors })
                hp.Step(state, { at = state.startedAt + 1, actors = actors })
                expect(state.scores[1]).to.equal(1)
                expect(awards).to.equal(0)
                hp.Cleanup(mode)
            end
        }
    }
}
