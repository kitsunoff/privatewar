-- Example (T-3.1): a weapon adapter (04-weapons.md d.1; docs/api/adapter.md). One file per adapter in
-- lua/privatewar/weapon_adapters/; the file name is the adapter id. IsAvailable, Claims and ListWeapons are
-- required; every other method is optional and has a default in the core (PW.Adapters.Defaults). Several adapters
-- may claim one class: the highest Priority wins (ties: the lowest id).

ADAPTER.Priority = 10

function ADAPTER:IsAvailable()
    return true
end

function ADAPTER:Claims(class)
    return class == "weapon_smg1"
end

function ADAPTER:ListWeapons()
    return { { class = "weapon_smg1", name = "SMG", kind = "gun", category = "smg", slot = 1 } }
end
