-- In-match Tab board: pure policy, public-data projection, layout and shared result-board rendering model.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "scoreboard dependency is missing")
    return value
end

---@return PW.UIScoreboardLib
local function scoreboard() return must(must(PW.UI).Scoreboard) end

---@return PW.UIBoardLib
local function board() return must(must(PW.UI).Board) end

---@param id integer
---@param team integer
---@param score integer
---@param kills integer
---@return PW.UIBoardRow
local function row(id, team, score, kills)
    return { id = id, name = "Player " .. id, team = team, score = score, kills = kills, deaths = 2,
        bot = id == 2, me = id == 1 }
end

---@param changes? table<string, any>
---@return PW.UIScoreboardFacts
local function facts(changes)
    local out = { phase = "LIVE", enabled = true, playerValid = true, gameUI = false, focused = true }
    for key, value in pairs(changes or {}) do out[key] = value end
    return out --[[@as PW.UIScoreboardFacts]]
end

return {
    groupName = "PW in-match scoreboard",
    cases = {
        {
            name = "Tab policy: LIVE only, disabled or invalid player falls back, focus and menus close it",
            func = function()
                expect(scoreboard().Allowed(facts())).to.equal(true)
                expect(scoreboard().Allowed(facts({ rootId = "class" }))).to.equal(true)
                for _, phase in ipairs({ "LOBBY", "PREMATCH", "POSTMATCH", "VOTE" }) do
                    expect(scoreboard().Allowed(facts({ phase = phase }))).to.equal(false)
                end
                for _, change in ipairs({ { enabled = false }, { playerValid = false }, { focused = false },
                    { gameUI = true }, { rootId = "pause" }, { rootId = "hub" } }) do
                    expect(scoreboard().Allowed(facts(change))).to.equal(false)
                end
            end
        },
        {
            name = "Teams: own section first, public mode totals retained, stable score ranking and ties",
            func = function()
                local rows = { row(1, 1, 500, 3), row(2, 2, 900, 9), row(3, 1, 500, 5) }
                local original = table.Copy(rows)
                local sections = scoreboard().Sections(rows, {
                    teams = 2, ownTeam = 1, teamScores = { 20, 40 }, teamNames = { "Blue", "Red" }
                })
                expect(sections[1].id).to.equal(1)
                expect(sections[1].title).to.equal("BLUE")
                expect(sections[1].score).to.equal(20)
                expect(sections[1].relation).to.equal("friendly")
                expect(sections[2].relation).to.equal("enemy")
                expect(sections[1].rows[1].id).to.equal(3)
                expect(sections[1].rows[2].place).to.equal(1)
                expect(rows).to.deepEqual(original)
            end
        },
        {
            name = "FFA: kills decide order and ties, not score, no invented team scores",
            func = function()
                local sections = scoreboard().Sections({ row(1, 1000, 900, 4), row(2, 1000, 100, 8),
                    row(3, 1000, 300, 8) }, { teams = 0, ownTeam = 1000 })
                expect(#sections).to.equal(1)
                expect(sections[1].rows[1].id).to.equal(3)
                expect(sections[1].rows[2].place).to.equal(1)
                expect(sections[1].rows[3].place).to.equal(3)
                expect(sections[1].score).to.equal(nil)
            end
        },
        {
            name = "Observers: spectator and JIP holdouts separated, no alive or tactical state projected",
            func = function()
                local observer, held, active = row(2, 1002, 0, 0), row(3, 1, 0, 0), row(1, 1, 10, 1)
                observer.spectator, held.spectator = true, true
                local secret = active --[[@as table<string, any>]]
                secret.position, secret.alive, secret.bomb, secret.target = "secret", true, true, "secret"
                local sections = scoreboard().Sections({ observer, held, active }, { teams = 2, ownTeam = 1 })
                expect(#sections).to.equal(3)
                expect(#sections[1].rows).to.equal(1)
                expect(sections[3].title).to.equal("SPECTATORS")
                expect(#sections[3].rows).to.equal(2)
                local projected = sections[1].rows[1] --[[@as table<string, any>]]
                expect(projected.position).to.equal(nil)
                expect(projected.alive).to.equal(nil)
                expect(projected.bomb).to.equal(nil)
                expect(projected.target).to.equal(nil)
                local lines = board().Lines(sections)
                expect(lines[#lines].kills).to.equal("")
                expect(lines[#lines].score).to.equal("")
            end
        },
        {
            name = "Roster refresh: disconnects disappear, role/team changes move rows, empty teams remain",
            func = function()
                local rows = { row(1, 1, 0, 0), row(2, 2, 0, 0) }
                local opts = { teams = 2, ownTeam = 1 }
                local first = scoreboard().Sections(rows, opts)
                rows[1].team, rows[2] = 2, nil
                local nextBoard = scoreboard().Sections(rows, opts)
                expect(#first[1].rows).to.equal(1)
                expect(#nextBoard[1].rows).to.equal(0)
                expect(#nextBoard[2].rows).to.equal(1)
                expect(nextBoard[2].rows[1].me).to.equal(true)
                expect(#scoreboard().Sections({}, { teams = 0, ownTeam = 1000 })).to.equal(1)
            end
        },
        {
            name = "Modes: team totals are objective or round wins, never summed personal score",
            func = function()
                for _, total in ipairs({ 75, 200, 6, 3 }) do
                    local sections = scoreboard().Sections({ row(1, 1, 1200, 20) },
                        { teams = 2, ownTeam = 1, teamScores = { total, 0 } })
                    expect(sections[1].score).to.equal(total)
                    expect(sections[1].rows[1].score).to.equal(1200)
                end
            end
        },
        {
            name = "Result board reuse: headers, own accent and bot flags retained, strings built outside Paint",
            func = function()
                local lines = board().Lines({ { id = 1, title = "BLUE", score = 12, relation = "friendly",
                    rows = { row(1, 1, 500, 3), row(2, 1, 200, 2) } } })
                expect(#lines).to.equal(3)
                expect(lines[1].header).to.equal(true)
                expect(lines[1].score).to.equal("12")
                expect(lines[2].me).to.equal(true)
                expect(lines[3].bot).to.equal(true)
                expect(lines[2].kills).to.equal("3")
                expect(board().Height(lines)).to.equal(164)
                expect(board().Height({})).to.equal(36)
            end
        },
        {
            name = "Scale: board and hints stay inside 720p, Deck 800p, 1080p and ultrawide at all HUD scales",
            func = function()
                for _, size in ipairs({ { 1280, 720 }, { 1280, 800 }, { 1920, 1080 }, { 3440, 1440 } }) do
                    for _, multiplier in ipairs({ 0.75, 1, 1.25, 1.5 }) do
                        local scale = math.min(size[1] / 1920, size[2] / 1080) * multiplier
                        local rect = scoreboard().Layout(size[1], size[2], scale)
                        expect(rect.x >= 0 and rect.y >= 0).to.equal(true)
                        expect(rect.x + rect.w <= size[1]).to.equal(true)
                        expect(rect.y + rect.h <= size[2]).to.equal(true)
                        expect(rect.boardH >= 240 * scale).to.equal(true)
                        expect(rect.boardY + rect.boardH < rect.h).to.equal(true)
                    end
                end
            end
        },
        {
            name = "Input: arrows, pages and d-pad scroll; movement, attack and streak keys are not borrowed",
            func = function()
                expect(scoreboard().Scroll(KEY_DOWN, 500, 1)).to.equal(120)
                expect(scoreboard().Scroll(KEY_UP, 500, 1)).to.equal(-120)
                expect(scoreboard().Scroll(KEY_PAGEDOWN, 500, 1)).to.equal(500)
                expect(scoreboard().Scroll(KEY_PAGEUP, 500, 1)).to.equal(-500)
                expect(scoreboard().Scroll(KEY_XBUTTON_DOWN, 500, 1)).to.equal(120)
                expect(scoreboard().Scroll(KEY_XBUTTON_UP, 500, 1)).to.equal(-120)
                for _, code in ipairs({ KEY_W, KEY_S, KEY_SPACE, KEY_F, KEY_XBUTTON_A }) do
                    expect(scoreboard().Scroll(code, 500, 1)).to.equal(nil)
                end
            end
        },
        {
            name = "Names: UTF-8 ellipsis and control stripping run at layout time and never split a codepoint",
            func = function()
                local text = string.char(0xD0, 0x90):rep(20)
                local function measure(value) return #(value:gsub("[\128-\191]", "")) end
                local fit = board().Fit(text, 10, measure)
                expect(measure(fit) <= 10).to.equal(true)
                expect(utf8.len(fit) ~= nil).to.equal(true)
                expect(board().Fit("a\nb\tc", 20, measure)).to.equal("a b c")
                expect(board().Fit(text, 2, measure)).to.equal("")
            end
        }
    }
}
