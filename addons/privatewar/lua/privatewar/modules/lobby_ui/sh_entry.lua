-- Entry hints (T-8.3; 08-lobby.md d.2). Pure and shared: the facts about how the game was started in, the hints the
-- hub shows out. Singleplayer (or maxplayers 1) cannot run bots or a match: the hint blocks Start and says how to
-- start a listen server. P2P off is a hint for the host only and never blocks solo play. A listen server with free
-- slots gets no hint. The maxplayers vs bots.fill warning is a separate rule (PW.Lobby._SlotWarning, T-8.2).

local lib = (rawget(PW, "Lobby") or {}) --[[@as PW.LobbyLib]]
PW.Lobby = lib

lib.EntryText = {
    listenTitle = "Needs a listen server",
    listenText = "Bots and matches need a listen server. Start a New Game, set Max Players to 2 or more "
        .. "(12 recommended) and turn P2P on.",
    listenReason = "Singleplayer cannot run a match: start a New Game with Max Players 2 or more",
    p2pTitle = "Friends cannot join yet",
    p2pText = "P2P is off, so friends cannot join through Steam. Turn it on in the New Game menu "
        .. "(console: p2p_enabled 1). Solo play with bots is not affected."
}

function lib._Entry(facts)
    local text = lib.EntryText
    if facts.singlePlayer or facts.maxPlayers <= 1 then
        return {
            hints = { { id = "listen", title = text.listenTitle, text = text.listenText, blocking = true } },
            startReason = text.listenReason
        }
    end
    if facts.host and facts.p2p == false then
        return { hints = { { id = "p2p", title = text.p2pTitle, text = text.p2pText, blocking = false } } }
    end
    return { hints = {} }
end
