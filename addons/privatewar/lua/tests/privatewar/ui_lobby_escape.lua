-- Esc in the lobby offers to leave (10-frontend.md d.7; T-7.6 escape rules). Pure cases over plain data: Esc (or any
-- Back: Backspace, gamepad B) at the root of the lobby hub maps to the leave dialog, inside a pushed screen it stays
-- Back, Shift+Esc stays the GMod menu, the in-match pause rules are unchanged, and the dialog warns the host.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.UIMatchLib
local function match() return must(must(PW.UI).Match) end

---@param phase PW.PhaseName
---@param extra? table<string, any>
---@return PW.UIEscapeFacts
local function facts(phase, extra)
    ---@type PW.UIEscapeFacts
    local out = { phase = phase, enabled = true, rootOpen = false, gameUI = false, bypass = false }
    for key, value in pairs(extra or {}) do out[key] = value end
    return out
end

---@param extra? table<string, any>
---@return PW.UIEscapeFacts
local function lobbyRoot(extra)
    ---@type table<string, any>
    local merged = { rootOpen = true, rootId = "hub", depth = 1 }
    for key, value in pairs(extra or {}) do merged[key] = value end
    return facts("LOBBY", merged)
end

return {
    groupName = "PW UI lobby escape",
    cases = {
        {
            name = "Esc at the lobby hub root maps to the leave dialog",
            func = function()
                expect(match().Escape(lobbyRoot())).to.equal("leave")
                expect(match().RootBack({ phase = "LOBBY", rootId = "hub", depth = 1 })).to.equal("leave")
                -- the setting pausemenu does not matter in the lobby
                expect(match().Escape(lobbyRoot({ enabled = false }))).to.equal("leave")
            end
        },
        {
            name = "Esc inside a pushed lobby screen maps to Back",
            func = function()
                expect(match().Escape(lobbyRoot({ depth = 2 }))).to.equal("root")
                expect(match().Escape(lobbyRoot({ depth = 3 }))).to.equal("root")
                expect(match().RootBack({ phase = "LOBBY", rootId = "hub", depth = 2 })).to.equal("router")
            end
        },
        {
            name = "Esc with a dialog open in the lobby cancels it (Back of the modal)",
            func = function()
                expect(match().Escape(lobbyRoot({ modal = true }))).to.equal("root")
            end
        },
        {
            name = "Shift+Esc maps to the GMod menu in the lobby, at the root and deeper",
            func = function()
                expect(match().Escape(lobbyRoot({ bypass = true }))).to.equal("engine")
                expect(match().Escape(lobbyRoot({ bypass = true, depth = 2 }))).to.equal("engine")
                expect(match().Escape(lobbyRoot({ gameUI = true }))).to.equal("engine")
                expect(match().Escape(facts("LOBBY"))).to.equal("engine")
            end
        },
        {
            name = "In-match Esc is unchanged: pause, Back of an open root, GMod menu fallbacks",
            func = function()
                for _, phase in ipairs({ "PREMATCH", "LIVE", "POSTMATCH" }) do
                    expect(match().Escape(facts(phase))).to.equal("pause")
                    local pause = facts(phase, { rootOpen = true, rootId = "pause", depth = 1 })
                    expect(match().Escape(pause)).to.equal("root")
                    local hub = facts(phase, { rootOpen = true, rootId = "hub", depth = 1 })
                    expect(match().Escape(hub)).to.equal("root")
                    expect(match().RootBack({ phase = phase, rootId = "pause", depth = 1 })).to.equal("router")
                end
                expect(match().Escape(facts("LIVE", { bypass = true }))).to.equal("engine")
                expect(match().Escape(facts("LIVE", { enabled = false }))).to.equal("engine")
                -- the vote root is a "hub" root too, but the vote is not the lobby
                expect(match().Escape(facts("VOTE", { rootOpen = true, rootId = "hub", depth = 1 }))).to.equal("root")
            end
        },
        {
            name = "The leave dialog warns the host that the server closes for everyone",
            func = function()
                local host = match().LobbyLeave(true)
                expect(host.text).to.equal(match().LeaveHostText)
                expect(host.confirm).to.equal("LEAVE GAME")
                expect(host.alt).to.equal("GMOD MENU")
                expect(host.cancel).to.equal("CANCEL")
                local guest = match().LobbyLeave(false)
                expect(guest.text).to.equal(match().LobbyGuestText)
                expect(guest.text).notTo.equal(match().LeaveHostText)
                expect(guest.confirm).to.equal("LEAVE GAME")
            end
        }
    }
}
