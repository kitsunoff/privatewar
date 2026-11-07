-- Example (T-1.18): a module, the form of all subsystem code (01-extensibility.md d.16). A folder
-- lua/privatewar/modules/<id>/ with shared.lua (both realms), init.lua (server) and cl_init.lua (client); all of
-- them fill the same MODULE table. Modules are auto-subscribed (d.18): MODULE:PW_X listens to the hook PW_X.

MODULE.Name = "Hello"

---Runs on PW_MatchStart while the module is enabled.
function MODULE:PW_MatchStart()
    print("[hello] the match is live")
end
