-- T-7.7 Postmatch summary (TASKS.md "Mandatory test cases": T-7.4 to T-7.7 each screen's data model built
-- without drawing; 08-lobby.md d.4, d.5; 10-frontend.md d.1 POSTMATCH). Pure cases of PW.UI.Postmatch
-- (ui_kit/sh_postmatch.lua): the result text for a win, a loss, a draw and the FFA placement, the scoreboard order, the
-- level bar steps across several level-ups, the medal and weapon lists, and when the screen opens (POSTMATCH, the
-- summary) and closes (VOTE, LOBBY). The drawing and the keys are checkpoint items (the local checklist).

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.UIPostmatchLib
local function pm() return must(must(PW.UI).Postmatch) end

---@param id integer
---@param name string
---@param team integer
---@param kills integer
---@param deaths integer
---@param score integer
---@param extra? table<string, any>
---@return PW.UIBoardRow
local function row(id, name, team, kills, deaths, score, extra)
    ---@type PW.UIBoardRow
    local out = { id = id, name = name, team = team, kills = kills, deaths = deaths, score = score, bot = false,
        me = false }
    for key, value in pairs(extra or {}) do out[key] = value end
    return out
end

---@param section PW.UIBoardSection
---@return string[]
local function names(section)
    ---@type string[]
    local out = {}
    for index, entry in ipairs(section.rows) do out[index] = entry.name end
    return out
end

---@return PW.UIBoardRow[]
local function ffaRows()
    return {
        row(1, "Ann", 1000, 12, 5, 1300), row(2, "Bob", 1000, 20, 3, 2100), row(3, "Cid", 1000, 12, 9, 1250),
        row(4, "Dee", 1000, 4, 10, 400, { spectator = false }), row(5, "Eve", 1000, 30, 1, 0, { spectator = true })
    }
end

---@param phase PW.PhaseName
---@param extra? table<string, any>
---@return PW.UIPostmatchOpenFacts
local function openFacts(phase, extra)
    ---@type PW.UIPostmatchOpenFacts
    local facts = { phase = phase, enabled = true, open = false, otherRoot = false, dismissed = false }
    for key, value in pairs(extra or {}) do facts[key] = value end
    return facts
end

---XP to the next level: 100 at level 1, 200 at level 2, ... (easy sums for the cases).
---@param level integer
---@return number
local function needOf(level) return level * 100 end

---@param ownId integer
---@param winner integer
---@param draw? boolean
---@return PW.UIPostmatchResult
local function ffa(ownId, winner, draw)
    return pm().Result({
        draw = draw == true, winner = winner, teams = 0, ownTeam = 1000, ownId = ownId, rows = ffaRows()
    })
end

---@param step PW.UILevelStep
---@return any[]
local function tuple(step) return { step.level, step.from, step.to, step.levelUp } end

---@param frame PW.UILevelFrame
---@return any[]
local function frameTuple(frame) return { frame.level, frame.fraction, frame.levelUps, frame.done } end

---@param before integer
---@param after integer
---@param xp number
---@param into number
---@param need number
---@return PW.UILevelStep[]
local function steps(before, after, xp, into, need)
    return pm().LevelSteps({ levelBefore = before, levelAfter = after, xp = xp, into = into, need = need }, needOf)
end

return {
    groupName = "PW ui postmatch",
    cases = {
        {
            name = "Result: the own team won is VICTORY with the team score",
            func = function()
                local result = pm().Result({
                    draw = false, winner = 2, teams = 2, ownTeam = 2, ownId = 7, teamScores = { [1] = 60, [2] = 75 }
                })
                expect(result.kind).to.equal("victory")
                expect(result.title).to.equal("VICTORY")
                expect(result.token).to.equal("positive")
                expect(result.subtitle).to.equal("75 : 60")
            end
        },
        {
            name = "Result: the other team won is DEFEAT, a draw is DRAW, no team is MATCH OVER",
            func = function()
                local scores = { [1] = 75, [2] = 60 }
                local loss = pm().Result({
                    draw = false, winner = 1, teams = 2, ownTeam = 2, ownId = 7, teamScores = scores
                })
                expect(loss.kind).to.equal("defeat")
                expect(loss.title).to.equal("DEFEAT")
                expect(loss.token).to.equal("negative")
                expect(loss.subtitle).to.equal("60 : 75")
                local draw = pm().Result({ draw = true, winner = 0, teams = 2, ownTeam = 1, ownId = 7 })
                expect(draw.kind).to.equal("draw")
                expect(draw.title).to.equal("DRAW")
                expect(draw.subtitle).to.equal("")
                local outside = pm().Result({ draw = false, winner = 1, teams = 2, ownTeam = 1001, ownId = 7 })
                expect(outside.title).to.equal("MATCH OVER")
                local none = pm().Result({ draw = false, winner = 0, teams = 0, ownTeam = 1000, ownId = 7 })
                expect(none.kind).to.equal("over")
            end
        },
        {
            name = "Result: FFA placement by kills, tied players share the place, spectators are not counted",
            func = function()
                local win = ffa(2, 2)
                expect(win.kind).to.equal("victory")
                expect(win.placement).to.equal(1)
                expect(win.subtitle).to.equal("1ST OF 4")
                local second = ffa(3, 2)
                expect(second.kind).to.equal("defeat")
                expect(second.placement).to.equal(2)
                expect(second.subtitle).to.equal("2ND OF 4")
                local last = ffa(4, 2)
                expect(last.subtitle).to.equal("4TH OF 4")
                local tie = ffa(1, 0, true)
                expect(tie.title).to.equal("DRAW")
                expect(tie.subtitle).to.equal("2ND OF 4")
            end
        },
        {
            name = "Ordinals and numbers",
            func = function()
                ---@type string[]
                local out = {}
                for _, n in ipairs({ 1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111 }) do
                    out[#out + 1] = pm().Ordinal(n)
                end
                expect(out).to.deepEqual({
                    "1ST", "2ND", "3RD", "4TH", "11TH", "12TH", "13TH", "21ST", "22ND", "23RD", "101ST", "111TH"
                })
                expect(pm().Number(0)).to.equal("0")
                expect(pm().Number(999)).to.equal("999")
                expect(pm().Number(1250)).to.equal("1,250")
                expect(pm().Number(1234567)).to.equal("1,234,567")
            end
        },
        {
            name = "Scoreboard: teams by team score, players by score, kills, deaths, then name",
            func = function()
                local rows = {
                    row(1, "zed", 1, 5, 2, 500), row(2, "Amy", 1, 5, 2, 500), row(3, "Bo", 2, 9, 1, 900),
                    row(4, "Cy", 1, 7, 3, 700), row(5, "Di", 2, 2, 2, 200, { bot = true }),
                    row(6, "Ed", 1, 5, 1, 500),
                    row(7, "Spec", 1001, 0, 0, 0), row(8, "Jip", 2, 0, 0, 0, { spectator = true })
                }
                local sections = pm().Board(rows, {
                    teams = 2, ownTeam = 1, teamScores = { [1] = 30, [2] = 41 }, teamNames = { [1] = "Rebels" }
                })
                expect(#sections).to.equal(2)
                expect(sections[1].id).to.equal(2)
                expect(sections[1].score).to.equal(41)
                expect(sections[1].relation).to.equal("enemy")
                expect(sections[1].title).to.equal("TEAM 2")
                expect(names(sections[1])).to.deepEqual({ "Bo", "Di" })
                expect(sections[2].id).to.equal(1)
                expect(sections[2].relation).to.equal("friendly")
                expect(sections[2].title).to.equal("REBELS")
                expect(names(sections[2])).to.deepEqual({ "Cy", "Ed", "Amy", "zed" })
                expect(sections[2].rows[1].place).to.equal(1)
            end
        },
        {
            name = "Scoreboard: equal team scores keep the team order; FFA is one section ordered by kills",
            func = function()
                local tied = pm().Board({ row(1, "A", 2, 1, 1, 1), row(2, "B", 1, 1, 1, 1) },
                    { teams = 2, ownTeam = 3, teamScores = { [1] = 5, [2] = 5 } })
                expect({ tied[1].id, tied[2].id }).to.deepEqual({ 1, 2 })
                expect(tied[1].relation).to.equal("neutral")
                local board = pm().Board(ffaRows(), { teams = 0, ownTeam = 1000 })
                expect(#board).to.equal(1)
                expect(board[1].title).to.equal("PLAYERS")
                expect(board[1].relation).to.equal("neutral")
                expect(names(board[1])).to.deepEqual({ "Bob", "Ann", "Cid", "Dee" })
                ---@type integer[]
                local places = {}
                for index, entry in ipairs(board[1].rows) do places[index] = entry.place end
                expect(places).to.deepEqual({ 1, 2, 2, 4 })
                expect(#pm().Board({}, { teams = 0, ownTeam = 1000 })[1].rows).to.equal(0)
            end
        },
        {
            name = "Level bar: no level-up is one segment from the start to the end fraction",
            func = function()
                expect(#steps(3, 3, 60, 150, 300)).to.equal(1)
                expect(tuple(steps(3, 3, 60, 150, 300)[1])).to.deepEqual({ 3, 0.3, 0.5, false })
            end
        },
        {
            name = "Level bar: several level-ups fill the bar once per level, then the last level to the end",
            func = function()
                -- Level 2 with 150 of 200, gains 700: 50 to level 3, 300 to level 4, 350 into level 4 of 400.
                local list = steps(2, 4, 700, 350, 400)
                expect(#list).to.equal(3)
                expect(tuple(list[1])).to.deepEqual({ 2, 0.75, 1, true })
                expect(tuple(list[2])).to.deepEqual({ 3, 0, 1, true })
                expect(tuple(list[3])).to.deepEqual({ 4, 0, 0.875, false })
                -- At the level cap the last bar is full.
                expect(steps(2, 3, 300, 0, 0)[2].to).to.equal(1)
            end
        },
        {
            name = "Level bar animation: frames walk the segments, count level-ups and stop at the end",
            func = function()
                local list = steps(2, 4, 700, 350, 400)
                local timing = { stepTime = 1, maxTime = 6, delay = 0.5 }
                expect(frameTuple(pm().BarAt(list, 0, timing))).to.deepEqual({ 2, 0.75, 0, false })
                local half = pm().BarAt(list, 1, timing)
                expect(half.level).to.equal(2)
                expect(half.fraction).to.equal(0.875)
                local second = pm().BarAt(list, 2, timing)
                expect({ second.level, second.levelUps }).to.deepEqual({ 3, 1 })
                local third = pm().BarAt(list, 3, timing)
                expect({ third.level, third.levelUps }).to.deepEqual({ 4, 2 })
                expect(frameTuple(pm().BarAt(list, 10, timing))).to.deepEqual({ 4, 0.875, 2, true })
                -- Many level-ups are squeezed into maxTime.
                local many = steps(1, 21, 1e6, 0, 100)
                expect(#many).to.equal(21)
                expect(pm().BarAt(many, 7, timing).done).to.beTrue()
                expect(pm().BarAt(many, 3.5, timing).done).to.beFalse()
                expect(pm().BarAt({}, 1, timing).done).to.beTrue()
            end
        },
        {
            name = "Medals: most earned first, then the medal order, then by id; names from nameOf",
            func = function()
                local list = {
                    { id = "streak5", count = 1 }, { id = "zzz_custom", count = 1 }, { id = "double_kill", count = 3 },
                    { id = "first_blood", count = 1 }
                }
                local order = { "first_blood", "revenge", "saviour", "double_kill", "triple_kill", "streak5" }
                local medals = pm().Medals(list, order, function(id)
                    return id == "first_blood" and "First Blood" or id
                end)
                ---@type string[]
                local ids = {}
                for index, medal in ipairs(medals) do ids[index] = medal.id end
                expect(ids).to.deepEqual({ "double_kill", "first_blood", "streak5", "zzz_custom" })
                expect(medals[1].text).to.equal("x3")
                expect(medals[2].name).to.equal("First Blood")
                expect(#pm().Medals({})).to.equal(0)
            end
        },
        {
            name = "Weapons: the largest gain first, then by name, with the new level",
            func = function()
                local weapons = pm().Weapons({
                    { class = "weapon_smg1", before = 2, after = 3 }, { class = "weapon_ar2", before = 1, after = 4 },
                    { class = "weapon_pistol", before = 5, after = 6 }
                })
                expect(weapons[1].class).to.equal("weapon_ar2")
                expect(weapons[1].text).to.equal("LVL 4  (+3)")
                expect({ weapons[2].class, weapons[3].class }).to.deepEqual({ "weapon_pistol", "weapon_smg1" })
            end
        },
        {
            name = "Currency earned is the wallet change since the match started",
            func = function()
                expect(pm().Earned(250, 400)).to.equal(150)
                expect(pm().Earned(250, 250)).to.equal(0)
                expect(pm().Earned(400, 250)).to.equal(0)
                expect(pm().Earned(nil, 250)).to.beNil()
            end
        },
        {
            name = "The screen opens on POSTMATCH and on the summary, refreshes when the summary arrives",
            func = function()
                expect(pm().Decide("phase", openFacts("POSTMATCH"))).to.equal("open")
                -- Entering POSTMATCH replaces an open pause menu or class picker.
                expect(pm().Decide("phase", openFacts("POSTMATCH", { otherRoot = true }))).to.equal("open")
                expect(pm().Decide("summary", openFacts("POSTMATCH"))).to.equal("open")
                expect(pm().Decide("summary", openFacts("POSTMATCH", { open = true }))).to.equal("refresh")
                expect(pm().Decide("tick", openFacts("POSTMATCH", { open = true }))).to.beNil()
                expect(pm().Decide("tick", openFacts("POSTMATCH"))).to.equal("open")
                -- Closed by the player: stays closed; another root open: wait.
                expect(pm().Decide("summary", openFacts("POSTMATCH", { dismissed = true }))).to.beNil()
                expect(pm().Decide("tick", openFacts("POSTMATCH", { dismissed = true }))).to.beNil()
                expect(pm().Decide("tick", openFacts("POSTMATCH", { otherRoot = true }))).to.beNil()
                expect(pm().Decide("phase", openFacts("POSTMATCH", { enabled = false }))).to.beNil()
            end
        },
        {
            name = "The screen closes on VOTE and LOBBY and never opens outside POSTMATCH",
            func = function()
                expect(pm().Decide("phase", openFacts("VOTE", { open = true }))).to.equal("close")
                expect(pm().Decide("phase", openFacts("LOBBY", { open = true }))).to.equal("close")
                expect(pm().Decide("tick", openFacts("VOTE", { open = true }))).to.equal("close")
                local disabled = openFacts("POSTMATCH", { open = true, enabled = false })
                expect(pm().Decide("phase", disabled)).to.equal("close")
                for _, phase in ipairs({ "LOBBY", "PREMATCH", "LIVE", "VOTE" }) do
                    expect(pm().Decide("phase", openFacts(phase))).to.beNil()
                    expect(pm().Decide("summary", openFacts(phase))).to.beNil()
                end
            end
        },
        {
            name = "The postmatch root has its own tab with one root screen",
            func = function()
                local screens = { { ClassName = "postmatch", Tab = pm().Tab, Root = true, Build = function() end } }
                local model = must(PW.UI).Router.New(screens --[[@as PW.Screen[] ]], { pm().Tab })
                expect(model.active).to.equal("summary")
                expect(must(PW.UI).Router.Back(model, "POSTMATCH")).to.equal("close")
                expect(pm().RootId).to.equal("postmatch")
            end
        }
    }
}
