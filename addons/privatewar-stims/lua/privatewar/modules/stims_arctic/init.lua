if not PW or PW.API ~= 1 then return end
local lib = PW.StimsArctic --[[@as PW.StimsArcticLib]]
local vialSetting = "arc_medshot_replacevial"

PW.HookFor(MODULE, "InitPostEntity", function()
    local convar = GetConVar(vialSetting)
    if convar == nil then return end
    local original = convar:GetString()
    if not lib._ShouldSwap(original) then return end
    if lib._VialOriginal == nil then lib._VialOriginal = original end
    convar:SetString("0")
end)

-- Restoration must survive a mid-session module disable or registry reload.
hook.Add("ShutDown", "PW.StimsArctic.Vials", function()
    local original = lib._VialOriginal
    if original == nil then return end
    local convar = GetConVar(vialSetting)
    if convar ~= nil then convar:SetString(original) end
    lib._VialOriginal = nil
end)
