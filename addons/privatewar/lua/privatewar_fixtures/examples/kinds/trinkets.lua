-- Example (T-1.18): declaring a new kind (01-extensibility.md d.8, d.16). An addon ships
-- lua/privatewar/kinds/<id>.lua; the core then scans lua/privatewar/<Folder>/ and runs every file there with a
-- fresh class table named <Global>. The registry of the kind is PW.<Id> (here PW.Trinkets).

-- Folder scanned under lua/privatewar/.
KIND.Folder = "trinkets"
-- Name of the class table inside each trinket file: TRINKET.Name = "Lucky coin".
KIND.Global = "TRINKET"
-- Fields every trinket must set, with their Lua types; a trinket without them is skipped with one log line (d.15).
KIND.Required = { Name = "string" }
-- "always" subscribes the PW_* methods of every trinket to those hooks; "never" (the default) does not (d.18).
KIND.Subscribe = "never"
