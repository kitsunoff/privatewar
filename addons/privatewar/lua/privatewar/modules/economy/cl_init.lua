-- Economy, client (T-4.12; 06-progression.md d.6). RequestBuy sends the one-key purchase request; the server answers
-- with pw_economy_result (kept in PW.Economy.LastResult and fired as the notification PW_EconomyResult(result)). The
-- currency and the purchased items arrive through the progression deltas (T-4.10) into the local file; the store
-- screen (T-7.5) reads GetCurrency, IsOwned and GetStore.

---A file-local class: methods of the global MODULE defined in two files are reported as duplicates.
---@class PW.EconomyModuleClient : PW.Module
local module = MODULE --[[@as PW.EconomyModuleClient]]

local lib = PW.Economy --[[@as PW.EconomyLib]]

function lib.RequestBuy(key)
    if not IsValid(module) or not isstring(key) then return end
    net.Start("pw_economy_buy")
    lib._EncodeRequest(key, PW.Progression._NetWriter())
    net.SendToServer()
end

net.Receive("pw_economy_result", function()
    if not IsValid(module) then return end
    local result = lib._DecodeResult(PW.Progression._NetReader())
    lib.LastResult = result
    PW.Notify("PW_EconomyResult", result)
end)
