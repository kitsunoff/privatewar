-- U-5 Hub and custom game (TASKS.md, "Mandatory test cases" U-5, T-8.1, T-8.2; notes/16-frontend-d1-proposal.md
-- §4a, §4b; 10-frontend.md d.8, d.9, d.10; 08-lobby.md d.2, d.3). Pure models of the lobby screens (PW.Lobby._Hub,
-- PW.Lobby._Custom, lobby_ui/sh_hub.lua): plain lobby state, playlist state and player records in, what the screens
-- draw out. The drawing itself is a checkpoint item.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.LobbyLib
local function lobby()
    return must(PW.Lobby)
end

---A mode group with three settings and the bots module group with bots.fill.
---@param fill integer
---@return PW.SettingGroup[]
local function groupsWith(fill)
    return PW.Settings._Groups({
        mode = {
            ClassName = "pwt_tdm",
            Settings = {
                alpha = { type = "int", default = 75, min = 1, max = 200, label = "Score limit" },
                beta = { type = "bool", default = true, label = "Hardcore" },
                gamma = { type = "enum", default = "wave", options = { "wave", "instant" }, label = "Respawn" },
                delta = { type = "int", default = 3, label = "Fourth" }
            }
        },
        modules = {
            {
                ClassName = "bots",
                Settings = {
                    fill = { scope = "match", type = "int", default = fill, min = 0, max = 128, label = "Fill" }
                }
            }
        },
        scope = "match", log = function() end, valueOf = function(def) return def.default end
    })
end

---A lobby state: two modes, two maps; the host flags by argument.
---@param host boolean
---@param fill? integer
---@return PW.LobbyState
local function sampleState(host, fill)
    return {
        map = "gm_pw_here", maps = { "gm_pw_here", "gm_pw_there" },
        modes = {
            { id = "pwt_tdm", name = "Team Deathmatch", groups = groupsWith(fill or 12) },
            { id = "pwt_ffa", name = "Free for all", groups = {} }
        },
        toggles = host and { { kind = "modes", id = "pwt_ffa", name = "Free for all", enabled = true } } or {},
        canStart = host, canEdit = host, canToggle = host,
        nav = { areas = 412, generating = false, canGenerate = host, fastDefault = true, result = "" }
    }
end

---@return PW.PlaylistListState
local function samplePlaylists(active, fill)
    return {
        list = {
            { id = "night", name = "Night ops", summary = "pwt_tdm on all maps", fill = fill or 12 },
            { id = "ship", name = "Shipment 24/7", summary = "pwt_tdm, pwt_ffa on 1 map", fill = 0 }
        },
        active = active or "", canPick = true
    }
end

---@return PW.UIPlayerInfo[]
local function players()
    return {
        { name = "Friend", team = 0 }, { name = "Kilo", host = true, team = 0 },
        { name = "Bot01", bot = true, team = 0 }
    }
end

---@param host boolean
---@param extra? table<string, any>
---@return PW.LobbyHubInput
local function hubInput(host, extra)
    ---@type PW.LobbyHubInput
    local input = {
        state = sampleState(host), selection = {}, playlists = samplePlaylists(), players = players(),
        maxPlayers = 12, seen = {}
    }
    for key, value in pairs(extra or {}) do input[key] = value end
    return input
end

---@param list PW.UICard[]
---@param id string
---@return PW.UICard
local function cardOf(list, id)
    for _, card in ipairs(list) do
        if card.id == id then return card end
    end
    error("no card " .. id)
end

---Locked with a non-empty reason.
---@param action PW.LobbyAction
---@return boolean
local function lockedWithReason(action)
    return action.locked == true and isstring(action.reason) and action.reason ~= ""
end

---Open: not locked, no reason.
---@param action PW.LobbyAction
---@return boolean
local function open(action)
    return action.locked == false and action.reason == nil
end

return {
    groupName = "PW ui hub",
    cases = {
        {
            name = "Hub model: a guest sees Start, Mode and Map and Game Setup locked with a reason",
            func = function()
                local hub = lobby()._Hub(hubInput(false))
                expect(lockedWithReason(hub.start)).to.beTrue()
                expect(lockedWithReason(hub.modeMap)).to.beTrue()
                expect(lockedWithReason(hub.setup)).to.beTrue()
                expect(hub.note).to.equal("waiting for host")
            end
        },
        {
            name = "Hub model: the host sees Start, Mode and Map and Game Setup enabled",
            func = function()
                local hub = lobby()._Hub(hubInput(true))
                expect(open(hub.start)).to.beTrue()
                expect(open(hub.modeMap)).to.beTrue()
                expect(open(hub.setup)).to.beTrue()
                expect(hub.note).to.beNil()
                expect(hub.start.request).to.deepEqual({ mode = "pwt_tdm", map = "gm_pw_here" })
            end
        },
        {
            name = "Hub model: before the lobby state arrives everything is locked as waiting",
            func = function()
                local hub = lobby()._Hub(hubInput(true, { state = false }))
                expect(hub.ready).to.beFalse()
                expect(lockedWithReason(hub.start)).to.beTrue()
                expect(hub.start.reason).to.equal("Waiting for the server")
                expect(lockedWithReason(hub.setup)).to.beTrue()
            end
        },
        {
            name = "Hub model: Start is locked while a navmesh generation runs",
            func = function()
                local input = hubInput(true)
                must(must(input.state).nav).generating = true
                local hub = lobby()._Hub(input)
                expect(lockedWithReason(hub.start)).to.beTrue()
                expect(string.find(must(hub.start.reason), "navmesh", 1, true)).to.exist()
            end
        },
        {
            name = "Summary is the mode name plus the map",
            func = function()
                local hub = lobby()._Hub(hubInput(true))
                expect(hub.summary.mode).to.equal("Team Deathmatch")
                expect(hub.summary.map).to.equal("gm_pw_here")
                expect(hub.summary.text).to.equal("Team Deathmatch on gm_pw_here")
                local other = lobby()._Hub(hubInput(true, { selection = { mode = "pwt_ffa", map = "gm_pw_there" } }))
                expect(other.summary.text).to.equal("Free for all on gm_pw_there")
                local picked = { selection = { mode = "pwt_ffa", map = "gm_pw_there" } }
                local custom = lobby()._Custom(hubInput(true, picked))
                expect(custom.summary.text).to.equal("Free for all on gm_pw_there")
            end
        },
        {
            name = "Mode badge text: MODE.Short if set, else the initials of Name",
            func = function()
                local plain = lobby()._Hub(hubInput(true))
                expect(plain.summary.badge).to.equal("TD")
                local short = lobby()._Hub(hubInput(true, {
                    shortOf = function(id) return id == "pwt_tdm" and "tdm" or nil end
                }))
                expect(short.summary.badge).to.equal("TDM")
                local custom = lobby()._Custom(hubInput(true))
                expect(cardOf(custom.modeCards, "pwt_ffa").badge).to.equal("FFA")
            end
        },
        {
            name = "The maxplayers warning appears when bots.fill exceeds the slots (T-8.2)",
            func = function()
                expect(lobby()._SlotWarning(16, 12)).to.equal("Bots fill to 16 players, the server has 12 slots")
                expect(lobby()._SlotWarning(12, 12)).to.beNil()
                expect(lobby()._SlotWarning(nil, 12)).to.beNil()
                local over = hubInput(true, { state = sampleState(true, 16) })
                expect(lobby()._Hub(over).warning).to.equal("Bots fill to 16 players, the server has 12 slots")
                expect(lobby()._Custom(over).warning).to.equal("Bots fill to 16 players, the server has 12 slots")
                expect(lobby()._Hub(hubInput(true)).warning).to.beNil()
                local playlist = hubInput(true, { playlists = samplePlaylists("night", 20) })
                expect(lobby()._Hub(playlist).warning).to.equal("Bots fill to 20 players, the server has 12 slots")
            end
        },
        {
            name = "The NEW badge comes from the seen-set",
            func = function()
                expect(lobby()._SeenKey("night")).to.equal("playlist:night")
                local fresh = lobby()._Hub(hubInput(true))
                expect(cardOf(fresh.cards, "night").new).to.beTrue()
                expect(cardOf(fresh.cards, "ship").new).to.beTrue()
                local seen = lobby()._Hub(hubInput(true, { seen = { ["playlist:night"] = true } }))
                expect(cardOf(seen.cards, "night").new).to.beFalse()
                expect(cardOf(seen.cards, "ship").new).to.beTrue()
                expect(cardOf(seen.cards, "@custom").new).to.beFalse()
                expect(seen.seenKeys).to.deepEqual({ "playlist:night", "playlist:ship" })
            end
        },
        {
            name = "Hub cards: playlists, then Custom game; the active playlist is selected and starts",
            func = function()
                local hub = lobby()._Hub(hubInput(true, { playlists = samplePlaylists("ship") }))
                expect(#hub.cards).to.equal(3)
                expect(must(hub.cards[3]).id).to.equal("@custom")
                expect(hub.selected).to.equal("ship")
                expect(cardOf(hub.cards, "night").footer).to.equal("Fills to 12 with bots")
                expect(cardOf(hub.cards, "ship").footer).to.beNil()
                expect(hub.start.label).to.equal("START PLAYLIST")
                expect(hub.start.request).to.deepEqual({ playlist = "ship" })
                local custom = lobby()._Hub(hubInput(true))
                expect(custom.selected).to.equal("@custom")
                expect(custom.start.label).to.equal("START MATCH")
                local bare = lobby()._Hub(hubInput(true, { playlists = false }))
                expect(#bare.cards).to.equal(1)
                expect(bare.selected).to.equal("@custom")
            end
        },
        {
            name = "Hub cards: a guest may focus but not pick playlists; Custom game stays open to view",
            func = function()
                local hub = lobby()._Hub(hubInput(false))
                expect(cardOf(hub.cards, "night").locked).to.beTrue()
                expect(cardOf(hub.cards, "night").reason).to.equal("Only the host can pick the playlist")
                expect(cardOf(hub.cards, "@custom").locked).to.beFalse()
            end
        },
        {
            name = "Hub match card: mode and map, three settings of the mode, the bots fill",
            func = function()
                local hub = lobby()._Hub(hubInput(true))
                expect(hub.rows).to.deepEqual({
                    { "Score limit", "75" }, { "Hardcore", "On" }, { "Fourth", "3" }, { "Bots fill", "12" }
                })
                local playlist = lobby()._Hub(hubInput(true, { playlists = samplePlaylists("night") }))
                expect(must(playlist.rows[1])).to.deepEqual({ "Playlist", "Night ops" })
            end
        },
        {
            name = "Hub party: one PARTY section in LOBBY, host first, bots up to bots.fill",
            func = function()
                local hub = lobby()._Hub(hubInput(true))
                expect(#hub.party).to.equal(1)
                local party = must(hub.party[1])
                expect(party.title).to.equal("PARTY")
                expect(must(party.rows[1]).name).to.equal("Kilo")
                expect(party.capacity).to.equal(12)
                expect(party.botsText).to.equal("+9 bots")
            end
        },
        {
            name = "Custom model: actions in order; a guest sees every action locked with a reason",
            func = function()
                local guest = lobby()._Custom(hubInput(false))
                ---@type string[]
                local ids = {}
                for index, card in ipairs(guest.actions) do
                    ids[index] = card.id
                    expect(card.locked).to.beTrue()
                    expect(isstring(card.reason) and card.reason ~= "").to.beTrue()
                end
                expect(ids).to.deepEqual({ "start", "modemap", "setup", "content", "navmesh" })
                local host = lobby()._Custom(hubInput(true))
                for _, card in ipairs(host.actions) do expect(card.locked).to.beFalse() end
                expect(host.canEdit).to.beTrue()
                expect(guest.canEdit).to.beFalse()
            end
        },
        {
            name = "Custom model: mode and map cards with the selection, maps filtered by the fits test",
            func = function()
                local input = hubInput(true, {
                    selection = { mode = "pwt_ffa" },
                    fits = function(mode, map) return mode ~= "pwt_ffa" or map == "gm_pw_there" end
                })
                local custom = lobby()._Custom(input)
                expect(#custom.modeCards).to.equal(2)
                expect(custom.modeSelected).to.equal("pwt_ffa")
                expect(#custom.mapCards).to.equal(1)
                expect(must(custom.mapCards[1]).id).to.equal("gm_pw_there")
                expect(custom.mapSelected).to.equal("gm_pw_there")
                expect(cardOf(custom.mapCards, "gm_pw_there").locked).to.beFalse()
                local guest = lobby()._Custom(hubInput(false))
                expect(cardOf(guest.mapCards, "gm_pw_here").locked).to.beTrue()
                expect(cardOf(guest.modeCards, "pwt_tdm").locked).to.beTrue()
            end
        },
        {
            name = "Custom model: navmesh line and action; no navmesh action without the navgen block",
            func = function()
                local custom = lobby()._Custom(hubInput(true))
                expect(custom.navLine).to.equal("Navmesh: 412 areas.")
                local input = hubInput(true)
                must(input.state).nav = nil
                local bare = lobby()._Custom(input)
                expect(bare.navLine).to.equal("")
                for _, card in ipairs(bare.actions) do expect(card.id ~= "navmesh").to.beTrue() end
            end
        },
        {
            name = "Setting values are shown in a readable form",
            func = function()
                local def = { type = "set", options = { "a", "b" } }
                expect(lobby()._ShowValue({ type = "bool" }, false)).to.equal("Off")
                expect(lobby()._ShowValue({ type = "enum" }, "wave")).to.equal("WAVE")
                expect(lobby()._ShowValue({ type = "float" }, 2.5)).to.equal("2.5")
                expect(lobby()._ShowValue(def, { a = true, b = true })).to.equal("A, B")
                expect(lobby()._ShowValue(def, {})).to.equal("None")
            end
        }
    }
}
