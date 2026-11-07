---@meta
-- Types of the postmatch summary screen (T-7.7; 08-lobby.md d.4, d.5; 10-frontend.md d.1 POSTMATCH). Source:
-- lua/privatewar/modules/ui_kit/sh_postmatch.lua (pure, shared) and cl_postmatch.lua (client glue); the screen is
-- lua/privatewar/screens/postmatch.lua.

---@alias PW.UIPostmatchKind "victory"|"defeat"|"draw"|"over"

---What the result banner depends on (the match_rules NW2 result and the local player).
---@class PW.UIPostmatchFacts
---@field draw boolean
---@field winner integer team index (team modes) or UserID (FFA); 0 when there is none
---@field teams integer team count of the match; 0 for FFA
---@field ownTeam integer the local player's team
---@field ownId integer the local player's UserID
---@field rows? PW.UIBoardRow[] the players (FFA placement)
---@field teamScores? table<integer, integer> score per team index (team modes: the subtitle)

---@class PW.UIPostmatchResult
---@field kind PW.UIPostmatchKind
---@field title string VICTORY, DEFEAT, DRAW or MATCH OVER
---@field token string the style token of the title
---@field subtitle string the FFA placement ("2ND OF 8") or the team score ("75 : 60"); "" when unknown
---@field placement? integer FFA only: the local player's place (tied players share it)

---One player of the scoreboard (plain data, read from the engine by the client glue).
---@class PW.UIBoardRow
---@field id integer UserID
---@field name string
---@field team integer
---@field kills integer
---@field deaths integer
---@field score integer
---@field bot boolean
---@field me boolean the local player
---@field spectator? boolean held out of the match (not listed)
---@field place? integer set by Board: the position in its section (tied players share it)

---@alias PW.UIBoardRelation "friendly"|"enemy"|"neutral"

---@class PW.UIBoardSection
---@field id integer team index; 0 for the FFA section
---@field title string
---@field score? integer the team score (team modes)
---@field relation PW.UIBoardRelation relative to the local player
---@field rows PW.UIBoardRow[]

---@class PW.UIBoardOpts
---@field teams integer team count; 0 for FFA
---@field ownTeam integer
---@field teamScores? table<integer, integer>
---@field teamNames? table<integer, string>

---Input of the level bar: the summary levels, the XP gained and the local player's progress at the end.
---@class PW.UILevelInput
---@field levelBefore integer
---@field levelAfter integer
---@field xp number XP gained this match
---@field into number XP into levelAfter at the end
---@field need number XP for the next level after levelAfter; 0 at the cap

---One segment of the level bar animation.
---@class PW.UILevelStep
---@field level integer the level shown during this segment
---@field from number bar fraction at the start (0..1)
---@field to number bar fraction at the end (0..1)
---@field levelUp boolean the segment fills the bar and the level goes up after it

---One frame of the level bar animation.
---@class PW.UILevelFrame
---@field level integer
---@field fraction number
---@field levelUps integer level-ups passed so far
---@field done boolean

---@class PW.UILevelTiming
---@field stepTime number seconds per segment
---@field maxTime number the whole animation never takes longer
---@field delay? number seconds before the bar starts

---@class PW.UIPostmatchMedal
---@field id string
---@field count integer
---@field name string
---@field text string the count as shown ("x2")

---@class PW.UIPostmatchWeapon
---@field class string
---@field name string
---@field before integer
---@field after integer
---@field text string "LVL 4  (+2)"

---Display name of an id (a medal id or a weapon class).
---@alias PW.UINameOf fun(id: string): string

---@alias PW.UIPostmatchEvent "phase"|"summary"|"tick"
---@alias PW.UIPostmatchAction "open"|"close"|"refresh"

---@class PW.UIPostmatchOpenFacts
---@field phase PW.PhaseName
---@field enabled boolean ui_kit valid
---@field open boolean the postmatch root is open
---@field otherRoot boolean another PWRoot (the pause menu, the class picker) is open
---@field dismissed boolean the player closed the summary in this POSTMATCH

---The data the screen draws (client: PW.UI.Postmatch.Gather).
---@class PW.UIPostmatchData
---@field result PW.UIPostmatchResult
---@field sections PW.UIBoardSection[]
---@field summary? PW.ProgressionSummary
---@field progression boolean the progression module is present
---@field steps PW.UILevelStep[]
---@field medals PW.UIPostmatchMedal[]
---@field weapons PW.UIPostmatchWeapon[]
---@field earned? integer currency earned this match (nil without the economy module or a baseline)
---@field map string

---@class PW.UIPostmatchLib
---@field Titles table<PW.UIPostmatchKind, string>
---@field Tokens table<PW.UIPostmatchKind, string>
---@field RootId string "postmatch"
---@field Tab string "summary"
---"1ST", "2ND", "3RD", "4TH", "11TH", "21ST".
---@field Ordinal fun(n: integer): string
---Thousands separated: 1250 -> "1,250".
---@field Number fun(n: number): string
---The local player's FFA place (1 + players with more kills; spectators skipped) and the player count; nil place
---when the local player is not listed.
---@field Placement fun(rows: PW.UIBoardRow[], ownId: integer): integer?, integer
---The result banner: victory, defeat, draw or "match over" (no result, or the local player outside the match teams).
---@field Result fun(facts: PW.UIPostmatchFacts): PW.UIPostmatchResult
---The final scoreboard: team modes one section per team (best team first), FFA one section; rows best first.
---@field Board fun(rows: PW.UIBoardRow[], opts: PW.UIBoardOpts): PW.UIBoardSection[]
---The level bar segments from levelBefore to levelAfter; needOf(level) is the XP from level to level + 1.
---@field LevelSteps fun(input: PW.UILevelInput, needOf: fun(level: integer): number): PW.UILevelStep[]
---The animation frame at elapsed seconds.
---@field BarAt fun(steps: PW.UILevelStep[], elapsed: number, timing: PW.UILevelTiming): PW.UILevelFrame
---Medals for display: most earned first, then the order of PW.Medals.Ids, then by id.
---@field Medals fun(list: PW.ProgressionMedalCount[], order?: string[], nameOf?: PW.UINameOf): PW.UIPostmatchMedal[]
---Weapon level-ups for display: the largest gain first, then by name.
---@field Weapons fun(list: PW.ProgressionWeaponGain[], nameOf?: PW.UINameOf): PW.UIPostmatchWeapon[]
---Currency earned since the baseline; nil without a baseline.
---@field Earned fun(start?: number, now: number): integer?
---What the client does on an event: open, close, refresh the open screen, or nothing.
---@field Decide fun(event: PW.UIPostmatchEvent, facts: PW.UIPostmatchOpenFacts): PW.UIPostmatchAction?
---Client: everything the screen shows, read now.
---@field Gather? fun(): PW.UIPostmatchData
---Client: the currency earned now (refreshed while the screen is open: the match bonus arrives with a later delta).
---@field EarnedNow? fun(): integer?
---Client: opens the pause menu over the summary; the summary comes back when the menu closes.
---@field Pause? fun()

---@class PW.UILib
---@field Postmatch? PW.UIPostmatchLib
---Client (cl_postmatch.lua): opens the postmatch summary; false when it could not be built.
---@field OpenPostmatch? fun(): boolean
