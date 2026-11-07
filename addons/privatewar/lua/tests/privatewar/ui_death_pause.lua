-- T-7.6 Death class picker and pause menu (10-frontend.md d.1, d.7; 05-loadout.md d.12; 00-core.md "abort to
-- lobby"). Pure cases over plain data: the picker's list model (order, current, N/A), the choice sends the class pick
-- request, the pause items per phase and privilege, the Escape decision with its fallback to the GMod menu, the
-- death watcher (open on death in LIVE, close on respawn), and the router tab sets the in-match roots use.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.UIMatchLib
local function match() return must(must(PW.UI).Match) end

---@return PW.UIRouterLib
local function router() return must(must(PW.UI).Router) end

---@param ref string
---@param name string
---@param available boolean
---@param reason? string
---@return PW.LoadoutClassEntry
local function entry(ref, name, available, reason)
    return { ref = ref, name = name, available = available, reason = reason, removed = {}, loadout = {} }
end

---@return PW.LoadoutClassState
local function state()
    return {
        selected = "preset:close_quarters",
        entries = {
            entry("preset:assault", "Assault", true),
            entry("preset:close_quarters", "Close quarters", true),
            entry("custom:1", "Mine", true),
            entry("custom:2", "Too heavy", false, "over the budget (12 of 10)")
        }
    }
end

---@param items PW.UIPauseItem[]
---@return table<string, PW.UIPauseItem>
local function byId(items)
    ---@type table<string, PW.UIPauseItem>
    local out = {}
    for _, item in ipairs(items) do out[item.id] = item end
    return out
end

---@param phase PW.PhaseName
---@param extra? table<string, any>
---@return PW.UIEscapeFacts
local function escapeFacts(phase, extra)
    ---@type PW.UIEscapeFacts
    local facts = { phase = phase, enabled = true, rootOpen = false, gameUI = false, bypass = false }
    for key, value in pairs(extra or {}) do facts[key] = value end
    return facts
end

---@param alive boolean
---@param phase PW.PhaseName
---@param extra? table<string, any>
---@return PW.UIDeathFacts
local function deathFacts(alive, phase, extra)
    ---@type PW.UIDeathFacts
    local facts = { alive = alive, phase = phase, enabled = true, open = false, otherRoot = false }
    for key, value in pairs(extra or {}) do facts[key] = value end
    return facts
end

return {
    groupName = "PW UI death picker and pause menu",
    cases = {
        {
            name = "Picker list: presets then custom classes in the server's order",
            func = function()
                local cards = match().ClassCards(state())
                expect(#cards).to.equal(4)
                expect(cards[1].id).to.equal("preset:assault")
                expect(cards[2].id).to.equal("preset:close_quarters")
                expect(cards[3].id).to.equal("custom:1")
                expect(cards[4].id).to.equal("custom:2")
                expect(cards[1].title).to.equal("Assault")
                expect(cards[1].tags).to.equal("Preset")
                expect(cards[3].tags).to.equal("Custom class")
            end
        },
        {
            name = "Picker list: the current class is highlighted (selected, badge CURRENT)",
            func = function()
                local cards, current = match().ClassCards(state())
                expect(current).to.equal("preset:close_quarters")
                expect(cards[2].badge).to.equal("CURRENT")
                expect(cards[1].badge).to.beNil()
                expect(cards[2].locked).to.beFalse()
            end
        },
        {
            name = "Picker list: an unavailable class is greyed (locked) with its reason",
            func = function()
                local cards = match().ClassCards(state())
                expect(cards[4].locked).to.beTrue()
                expect(cards[4].badge).to.equal("N/A")
                expect(cards[4].reason).to.equal("Not available: over the budget (12 of 10)")
                expect(cards[4].text).to.equal("over the budget (12 of 10)")
                expect(cards[3].locked).to.beFalse()
            end
        },
        {
            name = "Picker list: no state yet or no pick gives no current class",
            func = function()
                local cards, current = match().ClassCards(nil)
                expect(#cards).to.equal(0)
                expect(current).to.beNil()
                local none = state()
                none.selected = ""
                local _, noPick = match().ClassCards(none)
                expect(noPick).to.beNil()
            end
        },
        {
            name = "Choosing an available class sends the class pick request with its ref",
            func = function()
                ---@type string[]
                local sent = {}
                local result = match().Choose(state(), "custom:1", function(ref) sent[#sent + 1] = ref end)
                expect(result).to.equal("sent")
                expect(#sent).to.equal(1)
                expect(sent[1]).to.equal("custom:1")
            end
        },
        {
            name = "Choosing an N/A, the current or an unknown class sends nothing",
            func = function()
                local count = 0
                local function send() count = count + 1 end
                expect(match().Choose(state(), "custom:2", send)).to.equal("locked")
                expect(match().Choose(state(), "preset:close_quarters", send)).to.equal("current")
                expect(match().Choose(state(), "preset:nope", send)).to.equal("unknown")
                expect(match().Choose(nil, "preset:assault", send)).to.equal("unknown")
                expect(count).to.equal(0)
            end
        },
        {
            name = "Pause items in LIVE for the host: every item in order, all usable (Settings since T-7.2)",
            func = function()
                local items = match().PauseItems({ phase = "LIVE", canAbort = true, classes = true, host = true })
                ---@type string[]
                local ids = {}
                for index, item in ipairs(items) do ids[index] = item.id end
                expect(table.concat(ids, ",")).to.equal("resume,class,settings,lobby,leave,gmod")
                local map = byId(items)
                expect(map.resume.locked).to.beFalse()
                expect(map.class.locked).to.beFalse()
                expect(map.lobby.locked).to.beFalse()
                expect(map.leave.locked).to.beFalse()
                expect(map.gmod.locked).to.beFalse()
                expect(map.settings.locked).to.beFalse()
                expect(map.settings.reason).to.beNil()
                expect(map.leave.confirm).to.equal(match().LeaveHostText)
            end
        },
        {
            name = "Pause items for a guest: Return to lobby is locked with a reason, Leave warns nobody",
            func = function()
                local map = byId(match().PauseItems({ phase = "LIVE", canAbort = false, classes = true, host = false }))
                expect(map.lobby.locked).to.beTrue()
                expect(map.lobby.reason).to.equal("Only the host can end the match")
                expect(map.leave.locked).to.beFalse()
                expect(map.leave.confirm).to.equal(match().LeaveGuestText)
            end
        },
        {
            name = "Pause items per phase: Change class only before and during the match, and only with classes",
            func = function()
                ---@param phase PW.PhaseName
                local function items(phase)
                    return byId(match().PauseItems({ phase = phase, canAbort = true, classes = true, host = true }))
                end
                expect(items("PREMATCH").class.locked).to.beFalse()
                local post = items("POSTMATCH")
                expect(post.class.locked).to.beTrue()
                expect(post.class.reason).to.equal("The match is over")
                expect(post.lobby.locked).to.beFalse()
                local bare = byId(match().PauseItems({ phase = "LIVE", canAbort = true, classes = false, host = true }))
                expect(bare.class.locked).to.beTrue()
                expect(bare.class.reason).to.equal("Classes are not available")
            end
        },
        {
            name = "Escape opens the pause menu during a match (PREMATCH, LIVE, POSTMATCH)",
            func = function()
                for _, phase in ipairs({ "PREMATCH", "LIVE", "POSTMATCH" }) do
                    expect(match().Escape(escapeFacts(phase))).to.equal("pause")
                end
            end
        },
        {
            name = "Escape falls back to the GMod menu: outside a match, bypass (Shift), disabled, or menu shown",
            func = function()
                expect(match().Escape(escapeFacts("LOBBY"))).to.equal("engine")
                expect(match().Escape(escapeFacts("VOTE"))).to.equal("engine")
                expect(match().Escape(escapeFacts("LIVE", { bypass = true }))).to.equal("engine")
                expect(match().Escape(escapeFacts("LIVE", { enabled = false }))).to.equal("engine")
                expect(match().Escape(escapeFacts("LIVE", { gameUI = true }))).to.equal("engine")
                expect(match().Escape(escapeFacts("LIVE", { rootOpen = true, bypass = true }))).to.equal("engine")
            end
        },
        {
            name = "Escape with one of our menus open is Back for that menu (the root's own handler)",
            func = function()
                expect(match().Escape(escapeFacts("LIVE", { rootOpen = true }))).to.equal("root")
            end
        },
        {
            name = "Death watcher: dying in LIVE opens the picker once; respawning closes it",
            func = function()
                local memory = match().NewDeathMemory()
                expect(match().DeathStep(memory, deathFacts(true, "LIVE"))).to.beNil()
                expect(match().DeathStep(memory, deathFacts(false, "LIVE"))).to.equal("open")
                expect(match().DeathStep(memory, deathFacts(false, "LIVE", { open = true }))).to.beNil()
                -- closed by the player while still dead: it does not come back on its own
                expect(match().DeathStep(memory, deathFacts(false, "LIVE"))).to.beNil()
                expect(match().DeathStep(memory, deathFacts(true, "LIVE", { open = true }))).to.equal("close")
            end
        },
        {
            name = "Death watcher: no picker outside LIVE, while disabled or over another menu",
            func = function()
                for _, case in ipairs({
                    { "PREMATCH", {} }, { "POSTMATCH", {} }, { "LIVE", { enabled = false } },
                    { "LIVE", { otherRoot = true } }
                }) do
                    local memory = match().NewDeathMemory()
                    match().DeathStep(memory, deathFacts(true, case[1]))
                    expect(match().DeathStep(memory, deathFacts(false, case[1], case[2]))).to.beNil()
                end
            end
        },
        {
            name = "Death watcher: the first sample only records; leaving LIVE closes an open picker",
            func = function()
                local memory = match().NewDeathMemory()
                expect(match().DeathStep(memory, deathFacts(false, "LIVE"))).to.beNil()
                expect(match().DeathStep(memory, deathFacts(false, "POSTMATCH", { open = true }))).to.equal("close")
            end
        },
        {
            name = "Router tab sets: the in-match tabs build their own roots; the hub ignores them",
            func = function()
                ---@type PW.Screen[]
                local screens = {
                    { ClassName = "hub", Tab = "play", Root = true, Build = function() return 1 end },
                    { ClassName = "pause", Tab = "match", Root = true, Build = function() return 2 end },
                    { ClassName = "pick", Tab = "class", Root = true, Build = function() return 3 end }
                }
                local hub = router().New(screens)
                expect(#hub.tabs).to.equal(4)
                expect(hub.tabById.match).to.beNil()
                local pause = router().New(screens, { "match", "loadout" })
                expect(#pause.tabs).to.equal(2)
                expect(pause.active).to.equal("match")
                expect(must(router().Top(pause)).ClassName).to.equal("pause")
                expect(pause.tabById.match.label).to.equal("MATCH")
                expect(router().Push(pause, "pick")).to.beTrue()
                expect(router().Back(pause, "LIVE")).to.equal("pop")
                expect(router().Back(pause, "LIVE")).to.equal("close")
                local picker = router().New(screens, { "class" })
                expect(must(router().Top(picker)).ClassName).to.equal("pick")
            end
        },
        {
            name = "The pause menu and class picker screens are registered for the in-match tabs",
            func = function()
                local registry = must(PW.Registries["screens"])
                local pause = must(registry.Get("match_pause")) --[[@as PW.Screen]]
                local picker = must(registry.Get("match_classes")) --[[@as PW.Screen]]
                expect(pause.Tab).to.equal("match")
                expect(pause.Root).to.beTrue()
                expect(picker.Tab).to.equal("class")
                expect(picker.Root).to.beTrue()
            end
        }
    }
}
