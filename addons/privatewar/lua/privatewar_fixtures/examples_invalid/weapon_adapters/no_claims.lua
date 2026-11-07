-- Invalid example (T-3.1): an adapter without Claims is rejected with the log line
-- 'weapon_adapters "no_claims": missing required field Claims (function)'.

function ADAPTER:IsAvailable()
    return true
end

function ADAPTER:ListWeapons()
    return {}
end
