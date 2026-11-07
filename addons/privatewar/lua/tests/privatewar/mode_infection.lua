-- Phase 1 optional-addon boundary scaffold, not gameplay or an observed RED/GREEN result.
-- Presence is established from the mounted source, never from successful registration: an installed but broken
-- mode must fail instead of looking like an absent optional addon. A manifest/type-only scaffold is not a mode.

local modeId = "pw_infection"
local modePath = "privatewar/modes/" .. modeId .. ".lua"

return {
    groupName = "PW Infection addon boundary",
    cases = {
        {
            name = "Infection: base modes remain registered with or without the optional addon",
            func = function()
                for _, id in ipairs({ "tdm", "ffa", "dom", "kc", "round_base" }) do
                    expect(PW.Modes.Get(id)).to.exist()
                end
            end
        },
        {
            name = "Infection: mounted mode source requires registration; absence leaves no mode entry",
            func = function()
                local stored = PW.Modes.GetStored(modeId)
                if file.Exists(modePath, "LUA") then
                    assert(stored ~= nil, "mounted Infection source failed to register; this is not an absent addon")
                    local mode = PW.Modes.Get(modeId)
                    assert(mode ~= nil, "mounted Infection mode failed Base resolution")
                    expect(mode.Base).to.equal("round_base")
                    expect(mode.Teams).to.equal(2)
                    expect(mode.Abstract == true).to.beFalse()
                else
                    expect(stored).to.beNil()
                    expect(PW.Modes.Get(modeId)).to.beNil()
                end
            end
        }
    }
}
