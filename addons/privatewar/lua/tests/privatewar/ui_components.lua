-- U-4 Components v1 (TASKS.md, "Mandatory test cases" U-4; notes/16-frontend-d1-proposal.md §3, §5). Pure models
-- of the kit components: card list, pager, tab bar (locked and "NEW" from the seen-set), player list, mode
-- monogram, status line, timer and hint bar. The form controls are covered by ui_kit.lua (T-7.2 cases).

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.UILib
local function kit() return must(PW.UI) end

---@return PW.UICardsLib
local function cards() return must(kit().Cards) end

---@return PW.UIPagerLib
local function pager() return must(kit().Pager) end

---@return PW.UITabsLib
local function tabs() return must(kit().Tabs) end

---@return PW.UICard[]
local function sampleCards()
    return {
        { id = "a", title = "A" }, { id = "b", title = "B", new = true },
        { id = "c", title = "C", locked = true, reason = "host only" }, { id = "d", title = "D", disabled = true }
    }
end

---@param views PW.UICardView[]
---@return string[]
local function expandedIds(views)
    ---@type string[]
    local out = {}
    for _, view in ipairs(views) do
        if view.expanded then out[#out + 1] = view.id end
    end
    return out
end

---@param name string
---@param opts? { bot?: boolean, host?: boolean, team?: integer }
---@return PW.UIPlayerInfo
local function player(name, opts)
    opts = opts or {}
    return { name = name, bot = opts.bot == true, host = opts.host == true, team = opts.team }
end

---@return PW.UIPlayerInfo[]
local function roster()
    return {
        player("zed", { team = 1 }), player("Bot01", { bot = true, team = 1 }), player("amy", { team = 2 }),
        player("Kilo", { host = true, team = 2 }), player("Bot02", { bot = true, team = 2 }),
        player("Bot03", { bot = true, team = 2 })
    }
end

---@param section PW.UIPlayerSection
---@return string[]
local function rowNames(section)
    ---@type string[]
    local out = {}
    for index, row in ipairs(section.rows) do out[index] = row.name end
    return out
end

---@param items PW.UITabItem[]
---@return table<string, string>
local function tabStates(items)
    ---@type table<string, string>
    local out = {}
    for _, item in ipairs(items) do
        local state = item.locked and "locked" or (item.new and "new" or "open")
        if item.active then state = state .. "+active" end
        out[item.id] = state
    end
    return out
end

---@return PW.UIRouterTab[]
local function routerTabs()
    return {
        { id = "play", label = "PLAY", locked = false }, { id = "loadout", label = "LOADOUT", locked = false },
        { id = "progress", label = "PROGRESS", locked = true, reason = "soon" },
        { id = "store", label = "STORE", locked = true, reason = "soon" }
    }
end

return {
    groupName = "PW UI components",
    cases = {
        {
            name = "Card list: the expanded card is the selected one, and only it",
            func = function()
                local views = cards().View(sampleCards(), "b")
                expect(expandedIds(views)).to.deepEqual({ "b" })
                expect(must(views[2]).selected).to.beTrue()
                expect(must(views[2]).new).to.beTrue()
                expect(cards().Expanded(sampleCards(), "b")).to.equal("b")
                expect(#expandedIds(cards().View(sampleCards(), nil))).to.equal(0)
                expect(#expandedIds(cards().View(sampleCards(), "missing"))).to.equal(0)
                expect(cards().Expanded(sampleCards(), "missing")).to.beNil()
            end
        },
        {
            name = "Card list: selecting moves the expansion; locked and disabled cards cannot be selected",
            func = function()
                local list = sampleCards()
                local selected = cards().Select(list, "a", "b")
                expect(selected).to.equal("b")
                expect(expandedIds(cards().View(list, selected))).to.deepEqual({ "b" })
                expect(cards().Select(list, "b", "c")).to.equal("b")
                expect(cards().Select(list, "b", "d")).to.equal("b")
                expect(cards().Select(list, "b", "missing")).to.equal("b")
                local views = cards().View(list, "a")
                expect(must(views[3]).locked).to.beTrue()
                expect(must(views[3]).reason).to.equal("host only")
                expect(must(views[4]).disabled).to.beTrue()
            end
        },
        {
            name = "Pager: rows per page from the height",
            func = function()
                expect(pager().RowsPerPage(600, 56, 4)).to.equal(10)
                expect(pager().RowsPerPage(596, 56, 4)).to.equal(10)
                expect(pager().RowsPerPage(595, 56, 4)).to.equal(9)
                expect(pager().RowsPerPage(560, 56)).to.equal(10)
                expect(pager().RowsPerPage(30, 56, 4)).to.equal(1)
                expect(pager().RowsPerPage(0, 56, 4)).to.equal(1)
            end
        },
        {
            name = "Pager: page and pages from the count, rows per page and the focused row",
            func = function()
                local state = pager().State(21, 10, 1)
                expect(state.page).to.equal(1)
                expect(state.pages).to.equal(3)
                expect(state.first).to.equal(1)
                expect(state.last).to.equal(10)
                expect(state.atStart).to.beTrue()
                expect(state.atEnd).to.beFalse()
                state = pager().State(21, 10, 19)
                expect(state.page).to.equal(2)
                expect(state.first).to.equal(11)
                expect(state.last).to.equal(20)
                state = pager().State(21, 10, 21)
                expect(state.page).to.equal(3)
                expect(state.first).to.equal(21)
                expect(state.last).to.equal(21)
                expect(state.atEnd).to.beTrue()
                state = pager().State(21, 10, 99)
                expect(state.page).to.equal(3)
                state = pager().State(0, 10, 1)
                expect(state.page).to.equal(1)
                expect(state.pages).to.equal(1)
                expect(state.last).to.equal(0)
                expect(state.atStart and state.atEnd).to.beTrue()
                expect(pager().State(20, 10, 20).pages).to.equal(2)
            end
        },
        {
            name = "Tab model: locked tabs keep their reason and are never NEW; NEW comes from the seen-set",
            func = function()
                ---@type table<string, true>
                local seen = {}
                local items = tabs().Items(routerTabs(), "play", seen)
                expect(tabStates(items)).to.deepEqual({
                    play = "new+active", loadout = "new", progress = "locked", store = "locked"
                })
                expect(must(items[3]).reason).to.equal("soon")
                expect(kit().LockReason("soon")).to.equal("Coming soon")
                expect(kit().LockReason(nil)).to.equal("Locked")
                expect(kit().LockReason("Host only")).to.equal("Host only")
                expect(must(items[1]).label).to.equal("PLAY")
                expect(must(kit().Seen).Mark(seen, tabs().SeenKey("play"))).to.beTrue()
                expect(must(kit().Seen).Mark(seen, tabs().SeenKey("play"))).to.beFalse()
                expect(must(kit().Seen).IsNew(seen, tabs().SeenKey("play"))).to.beFalse()
                expect(tabStates(tabs().Items(routerTabs(), "loadout", seen))).to.deepEqual({
                    play = "open", loadout = "new+active", progress = "locked", store = "locked"
                })
                seen[tabs().SeenKey("progress")] = nil
                local unlocked = routerTabs()
                must(unlocked[3]).locked = false
                expect(tabStates(tabs().Items(unlocked, "play", seen)).progress).to.equal("new")
            end
        },
        {
            name = "Player list in LOBBY: one PARTY section, humans listed host first, bots collapsed to +N",
            func = function()
                local sections = kit().PlayerList(roster(), { phase = "LOBBY", maxPlayers = 12 })
                expect(#sections).to.equal(1)
                local party = must(sections[1])
                expect(party.id).to.equal("party")
                expect(party.title).to.equal("PARTY")
                expect(party.relation).to.equal("neutral")
                expect(rowNames(party)).to.deepEqual({ "Kilo", "amy", "zed" })
                expect(must(party.rows[1]).host).to.beTrue()
                expect(party.humans).to.equal(3)
                expect(party.capacity).to.equal(12)
                expect(party.bots).to.equal(3)
                expect(party.botsText).to.equal("+3 bots")
            end
        },
        {
            name = "Player list in LOBBY: before the match the bot row shows the fill target",
            func = function()
                local humans = { player("solo", { host = true }) }
                local party = must(kit().PlayerList(humans, { phase = "LOBBY", maxPlayers = 12, botsFill = 12 })[1])
                expect(party.bots).to.equal(10)
                local none = must(kit().PlayerList(humans, { phase = "LOBBY", maxPlayers = 12 })[1])
                expect(none.bots).to.equal(0)
                expect(none.botsText).to.beNil()
                local one = must(kit().PlayerList({ player("a"), player("b", { bot = true }) }, { phase = "LOBBY" })[1])
                expect(one.botsText).to.equal("+1 bot")
            end
        },
        {
            name = "Player list from PREMATCH: one section per team, colour relative to the local player",
            func = function()
                local sections = kit().PlayerList(roster(), {
                    phase = "PREMATCH", localTeam = 2,
                    teams = { { id = 1, name = "RED" }, { id = 2, name = "BLUE" } }
                })
                expect(#sections).to.equal(2)
                local red, blue = must(sections[1]), must(sections[2])
                expect(red.title).to.equal("RED")
                expect(red.relation).to.equal("enemy")
                expect(rowNames(red)).to.deepEqual({ "zed" })
                expect(red.bots).to.equal(1)
                expect(blue.relation).to.equal("friendly")
                expect(rowNames(blue)).to.deepEqual({ "Kilo", "amy" })
                expect(blue.bots).to.equal(2)
                local live = kit().PlayerList(roster(), { phase = "LIVE", teams = { { id = 1, name = "RED" } } })
                expect(must(live[1]).relation).to.equal("neutral")
            end
        },
        {
            name = "Player list from PREMATCH without teams (free for all): one PLAYERS section",
            func = function()
                local sections = kit().PlayerList(roster(), { phase = "PREMATCH", teams = {} })
                expect(#sections).to.equal(1)
                expect(must(sections[1]).title).to.equal("PLAYERS")
                expect(rowNames(must(sections[1]))).to.deepEqual({ "Kilo", "amy", "zed" })
            end
        },
        {
            name = "Mode monogram: MODE.Short, else the initials of Name",
            func = function()
                expect(kit().Monogram({ Short = "kc", Name = "Kill Confirmed" })).to.equal("KC")
                expect(kit().Monogram({ Name = "Team Deathmatch" })).to.equal("TD")
                expect(kit().Monogram({ Name = "free-for-all battle royale" })).to.equal("FFA")
                expect(kit().Monogram({ Name = "Dummy (dev)" })).to.equal("DD")
                expect(kit().Monogram({ Short = "", Name = "Gun Game" })).to.equal("GG")
                expect(kit().Monogram({ Name = "" })).to.equal("?")
            end
        },
        {
            name = "Timer and status line: M:SS, warning in the last 10 seconds",
            func = function()
                expect(kit().FormatTime(0)).to.equal("0:00")
                expect(kit().FormatTime(-5)).to.equal("0:00")
                expect(kit().FormatTime(9.2)).to.equal("0:10")
                expect(kit().FormatTime(600)).to.equal("10:00")
                local status = kit().Status({ phase = "LOBBY", humans = 3, maxPlayers = 12, note = "waiting for host" })
                expect(status.text).to.equal("LOBBY  ·  3/12  ·  waiting for host")
                expect(status.warning).to.beFalse()
                status = kit().Status({ phase = "VOTE", remaining = 8, humans = 2, maxPlayers = 12 })
                expect(status.text).to.equal("VOTE  ·  0:08  ·  2/12")
                expect(status.warning).to.beTrue()
                local live = kit().Status({ phase = "LIVE", remaining = 30, humans = 1, maxPlayers = 2 })
                expect(live.warning).to.beFalse()
            end
        },
        {
            name = "Hint bar follows the current input device and the hints setting",
            func = function()
                local input = must(kit().Input)
                local state = input.New()
                local entries = { { action = "back", label = "Back" }, { action = "accept", label = "Select" } }
                local hints = kit().Hints(state, entries)
                expect(must(hints[1]).cap).to.equal("Esc")
                expect(must(hints[1]).label).to.equal("Back")
                expect(must(hints[1]).device).to.equal("keyboard")
                input.Press(state, KEY_XBUTTON_A)
                hints = kit().Hints(state, entries)
                expect(must(hints[2]).cap).to.equal("A")
                expect(must(hints[2]).device).to.equal("controller")
                expect(must(kit().Hints(state, entries, "keyboard")[2]).cap).to.equal("Enter")
            end
        }
    }
}
