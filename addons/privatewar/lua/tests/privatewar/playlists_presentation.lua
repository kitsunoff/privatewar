-- Presentation regressions: author text stays bounded on the existing wire; time never becomes description text.
local function playlist() return assert(PW.Playlist) end

---@param summary PW.PlaylistSummary
---@return PW.PlaylistListState?
local function roundTrip(summary)
    ---@type any[]
    local tokens = {}
    ---@param value any
    local function write(value) tokens[#tokens + 1] = value end
    playlist()._Encode({ list = { summary }, active = "", serial = 1, sampledAt = 1000,
        canPick = true, retained = false, canStart = true },
        { uint = write, number = write, string = write, bool = write })
    local index = 0
    local function read() index = index + 1 return tokens[index] end
    return playlist()._Decode({ uint = read, number = read, string = read, bool = read })
end

return {
    groupName = "PW playlist presentation",
    beforeEach = function(state) state.previous = PW._Playlist end,
    afterEach = function(state) PW._Playlist = state.previous end,
    cases = {
        {
            name = "Custom description propagates from Lua startup definition through server entry and wire summary",
            func = function()
                PW._Playlist = assert(playlist()._NewStore)({
                    luaEntries = function() return { { ClassName = "event", Name = "Event",
                        Description = "Fast rounds. No teams.", Modes = { ffa = 1 } } } end,
                    facts = function() return {} end, phase = function() return "LOBBY" end })
                local entry = assert(assert(playlist().Get)("event"))
                expect(entry.Description).to.equal("Fast rounds. No teams.")
                local decoded = assert(roundTrip(playlist()._Summary(entry, 0)))
                expect(decoded.list[1].summary).to.equal(entry.Description)
            end
        },
        {
            name = "Absent empty and whitespace descriptions fall back while unsafe and oversized values reject",
            func = function()
                for _, text in ipairs({ "", "   " }) do
                    local data = assert(playlist().Normalize({ Name = "Event", Description = text,
                        Modes = { tdm = 1 } }))
                    expect(data.Description).to.equal(nil)
                end
                local data = assert(playlist().Normalize({ Name = "Event", Modes = { tdm = 1 } }))
                local entry = { id = "event", source = "lua", Name = data.Name, Modes = data.Modes,
                    Settings = data.Settings } --[[@as PW.PlaylistEntry]]
                expect(playlist()._Summary(entry, 0).summary).to.equal("tdm on all maps")
                for _, text in ipairs({ false, 42, {}, "line\nfeed", "nul\0byte", string.char(255),
                    string.rep("x", 257) }) do
                    expect(playlist().Normalize({ Name = "Event", Description = text,
                        Modes = { tdm = 1 } })).to.equal(nil)
                end
                entry.Description = string.rep("x", 256)
                expect(assert(roundTrip(playlist()._Summary(entry, 0))).list[1].summary).to.equal(entry.Description)
                entry.Description = string.rep("\195\169", 128)
                local normalized = assert(playlist().Normalize(entry))
                expect(normalized.Description).to.equal(entry.Description)
                expect(assert(roundTrip(playlist()._Summary(entry, 0))).list[1].summary).to.equal(entry.Description)
                local summary = playlist()._Summary(entry, 0)
                for _, text in ipairs({ "bad\ntext", string.char(255), string.rep("x", 257) }) do
                    summary.summary = text
                    expect(roundTrip(summary)).to.equal(nil)
                end
            end
        },
        {
            name = "Event timer uses rounded minutes hours and days with explicit unknown and deadline boundaries",
            func = function()
                local lobby = assert(PW.Lobby)
                local item = { id = "event", name = "Event", summary = "Story", fill = 0, active = true, valid = true }
                    --[[@as PW.PlaylistSummary]]
                for _, pair in ipairs({ { 1, "Ends in 1m" }, { 60, "Ends in 1m" }, { 61, "Ends in 2m" },
                    { 3600, "Ends in 1h 0m" }, { 2150 * 60, "Ends in 1d 11h 50m" },
                    { 86400, "Ends in 1d 0h 0m" }, { 3 * 86400 + 1, "Ends in 3d 0h 1m" } }) do
                    item.nextChange = 1000 + pair[1]
                    expect(lobby._PlaylistTimer(item, 1000)).to.equal(pair[2])
                end
                item.nextChange = nil
                expect(lobby._PlaylistTimer(item, 1000)).to.equal("End time unknown")
                item.nextChange = 1000
                expect(lobby._PlaylistTimer(item, 1000)).to.equal("Updating schedule")
                item.nextChange = 999
                expect(lobby._PlaylistTimer(item, 1000)).to.equal("Updating schedule")
                item.active, item.nextChange = false, 1060
                expect(lobby._PlaylistTimer(item, 1000)).to.equal("Starts in 1m")
                item.nextChange = nil
                expect(lobby._PlaylistTimer(item, 1000)).to.equal("Start time unknown")
                expect(lobby._PlaylistTimer(item, 1000, function(key) return "translated:" .. key end))
                    .to.equal("translated:pw.playlist.start_unknown")
                item.nextChange = 4600
                local phrases = { ["pw.playlist.starts"] = "%s to start", ["pw.playlist.hours"] = "%d hours %d mins" }
                expect(lobby._PlaylistTimer(item, 1000, function(key) return phrases[key] end))
                    .to.equal("1 hours 0 mins to start")
            end
        },
        {
            name = "Hub keeps timer separate from description and bot footer and Custom has no timer",
            func = function()
                local model = assert(PW.Lobby)._Hub({ selection = {}, players = {}, maxPlayers = 12, seen = {},
                    playlists = { active = "event", serial = 1, sampledAt = 1000, retained = false,
                        canPick = true, canStart = true, list = { { id = "event", name = "Event",
                            summary = "Fast rounds.", fill = 12, active = true, valid = true, nextChange = 4600 } } } })
                expect(model.cards[1].text).to.equal("Fast rounds.")
                expect(model.cards[1].timer).to.equal("Ends in 1h 0m")
                expect(model.cards[1].footer).to.equal("Fills to 12 with bots")
                expect(model.cards[2].timer).to.equal(nil)
            end
        },
        {
            name = "Timer row reserves space on collapsed and expanded cards and clamps narrow localized chips",
            func = function()
                local cards = assert(assert(PW.UI).Cards)
                expect(cards.Height(64, 0, true)).to.equal(98)
                expect(cards.Height(64, 100, true)).to.equal(198)
                expect(cards.Height(64, 100, false)).to.equal(164)
                expect(cards.RowHeight({ { id = "custom", title = "Custom" } }, 64)).to.equal(64)
                expect(cards.RowHeight({ { id = "custom", title = "Custom" },
                    { id = "event", title = "Event", timer = "Ends in 1h 0m" } }, 64)).to.equal(98)
                expect(assert(assert(PW.UI).Pager).RowsPerPage(300, 98, 6)).to.equal(2)
                for _, width in ipairs({ 0, 20, 80, 560 }) do
                    local rect = cards.TimerRect(width, 198, 900, 24, 12)
                    expect(rect.x >= 0).to.equal(true)
                    expect(rect.w >= 0 and rect.x + rect.w <= width).to.equal(true)
                    expect(rect.y + rect.h <= 198).to.equal(true)
                    expect(rect.y >= 164).to.equal(true)
                end
                local board = assert(assert(PW.UI).Board)
                local fitted = board.Fit(string.rep("\195\169", 50), 10, function(text) return #text end)
                expect(utf8.len(fitted) ~= nil).to.equal(true)
                expect(#fitted <= 10).to.equal(true)
                expect(board.Fit("Long timer", 1, function(text) return #text end)).to.equal("")
            end
        }
    }
}
