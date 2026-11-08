-- LOADOUT tab editors (T-7.4; 05-loadout.md d.2-d.5, d.12, d.13, d.15; 10-frontend.md d.1): the class list actions
-- (create, copy, rename, delete), the class editor (slots, Pick X budget) and the gunsmith. Shared and pure, so the
-- server-side test runner covers it: sh_names.lua (names, the save flow, the server's answer), sh_editor.lua (the
-- editor model over the effective slot set), sh_gunsmith.lua (the gunsmith model). The client glue (classes.json,
-- uploads, the live registries) is cl_init.lua; the screens are screens/loadout_classes.lua, loadout_editor.lua and
-- loadout_gunsmith.lua. The client decides nothing: the server repairs and checks every uploaded class again.
--
-- Decisions of the lane agent:
--   1. A class edit is a draft; SAVE (and leaving the editor with unsaved changes) writes classes.json and uploads
--      the whole list (the only class message the server has). NEW CLASS and COPY create the class at once.
--   2. Uploads are spaced 2.1 s apart (the server takes 0.5 per second); a save inside that time waits.
--   3. Deleting the class in use moves the pick to the first available preset; later custom refs shift down by one.
--   4. The client's budget and cap come from the lobby's match settings (the host's pending values), else the
--      defaults: the client has no match snapshot (core.md "Known limits"). The server's answer is authoritative.

MODULE.Name = "Loadout screens"

local lib = (rawget(PW, "LoadoutUI") or {}) --[[@as PW.LoadoutUILib]]
PW.LoadoutUI = lib

for _, name in ipairs({ "names", "editor", "gunsmith", "perks" }) do
    local path = "privatewar/modules/loadout_ui/sh_" .. name .. ".lua"
    if SERVER then AddCSLuaFile(path) end
    include(path)
end

-- The client glue is cl_init.lua (loaded by the module loader); it includes the shared look of the two screens.
if SERVER then AddCSLuaFile("privatewar/modules/loadout_ui/cl_widgets.lua") end
