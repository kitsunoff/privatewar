---@meta
-- Types of the optional Quick Slide support for bots (T-11.6; 07-bots.md d.13 revision 2026-11-07). Code:
-- lua/privatewar/modules/bots_input/sh_quickslide.lua.

---What the engine says about the addon (PW.BotQuickSlide.Probe).
---@class PW.BotQuickSlideProbe
---@field getSliding boolean Player:GetSliding exists (the addon's public player method)
---@field convar boolean the ConVar sv_qslide_duration exists
---@field hook boolean the addon's SetupMove hook "qslide" is installed
---@field duration? number the value of sv_qslide_duration

---@class PW.BotQuickSlideLib
---@field ConVar string "sv_qslide_duration"
---@field DefaultDuration number 0.75, the addon's default
---Pure: the addon is present: Player:GetSliding and either the ConVar or the hook.
---@field Detect fun(probe: PW.BotQuickSlideProbe): boolean
---Engine: probes the addon now.
---@field Probe fun(): PW.BotQuickSlideProbe
---Whether bots may slide: detected once on the first call, then cached for the session.
---@field Available fun(): boolean
---Seconds a slide lasts (the ConVar at detection, else DefaultDuration).
---@field Duration fun(): number
---Internal: forget the detection (tests; the next Available() probes again).
---@field _Reset fun()

---Internal: the cached detection.
---@class PW.BotQuickSlideStore
---@field detected? boolean
---@field duration? number

---@class PW
---@field BotQuickSlide? PW.BotQuickSlideLib
---@field _BotQuickSlide PW.BotQuickSlideStore internal
