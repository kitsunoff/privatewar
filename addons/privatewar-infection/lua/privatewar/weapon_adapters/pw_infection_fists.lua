-- Native fists are semiautomatic. Bots tap normal CUserCmd; human input and stock damage stay untouched.
ADAPTER.Name = "Native fists input"
ADAPTER.Priority = 50

function ADAPTER:IsAvailable() return weapons.GetStored("weapon_fists") ~= nil end

-- The ordinary SWEP catalogue already lists fists. This adapter only specializes their input.
function ADAPTER:ListWeapons() return {} end

function ADAPTER:Claims(class) return class == "weapon_fists" end

function ADAPTER:GetInputRules()
    return { releaseBetweenShots = true }
end
