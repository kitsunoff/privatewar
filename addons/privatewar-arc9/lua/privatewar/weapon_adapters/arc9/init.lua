-- ARC9 weapon adapter, server part (T-3.6; 04-weapons.md d.2; notes/08 sections 2.3, 2.4 and 6.2). Builds are
-- applied through ARC9's own server-side rebuild sequence (the server branch of its weapon receiver), never through
-- the receiver itself, so the customization lock does not stop them.
if not PW or PW.API ~= 1 then return end

---@param name string
---@return integer
local function subCount(name)
    local arc9 = rawget(_G, "ARC9") --[[@as ARC9Lib]]
    local att = arc9.GetAttTable(name)
    local subs = att ~= nil and att.Attachments or nil
    return istable(subs) and #subs or 0
end

---Static check of a build (05-loadout.md d.15: runs when a class is saved). Reason codes: "unknown_slot" (no such
---slot for this class and build), "unknown_option" (not offered at all), "wrong_slot" (its category does not fit).
---@param class string
---@param build PW.Build
---@return PW.Build clean, table<PW.SlotId, string> rejected
function ADAPTER:Validate(class, build)
    ---@type table<PW.SlotId, PW.Arc9SlotTable>
    local slots = {}
    local arc9 = rawget(_G, "ARC9") --[[@as ARC9Lib]]
    for _, found in ipairs(PW.Arc9._FindSlots(PW.Arc9.ClassSlots(class), build, arc9.GetAttTable)) do
        slots[found.id] = found.slot
    end
    ---@type PW.Build
    local clean = {}
    ---@type table<PW.SlotId, string>
    local rejected = {}
    for id, option in pairs(build) do
        local slot = slots[id]
        local att = isstring(option) and PW.Arc9.Offerable(option --[[@as string]]) or nil
        if slot == nil then
            rejected[id] = "unknown_slot"
        elseif option == false then
            clean[id] = false
        elseif att == nil then
            rejected[id] = "unknown_option"
        elseif not PW.Arc9._Fits(att, slot) then
            rejected[id] = "wrong_slot"
        else
            clean[id] = option
        end
    end
    return clean, rejected
end

---Applies build on a live weapon and returns what stuck. ARC9 prunes what its own rules reject (category,
---elements, Max, blocking hooks) and fills empty integral slots; the result reads the weapon back.
---@param wep Weapon
---@param build PW.Build
---@return PW.Build
function ADAPTER:Apply(wep, build)
    local gun = wep --[[@as PW.Arc9Weapon]]
    if not IsValid(gun) or not gun.ARC9 or not istable(build) then return {} end
    gun:SetNoPresets(true)
    local tree = PW.Arc9._WithBuild(PW.Arc9._TreeOf(gun.Attachments), build, subCount)
    -- The flat slot list is cached for 3 s; clear it so the rebuild sees the current tree.
    gun:DoInvalidateCache()
    gun:BuildSubAttachments(tree)
    gun:DoInvalidateCache()
    gun:PruneAttachments()
    gun:FillIntegralSlots()
    gun:SendWeapon()
    gun:PostModify()
    return PW.Arc9._ReadBuild(gun.Attachments, build)
end

---@param locked boolean
function ADAPTER:SetCustomizationLocked(locked)
    PW.Arc9.SetLocked(locked == true)
end

---ARC9 gives ClipSize * arc9_mult_defaultammo 0.4 s after Initialize unless ForceDefaultAmmo is set; 0 is truthy in
---Lua, so it gives nothing (notes/08 section 2.4).
---@param wep Weapon
function ADAPTER:SuppressDefaultAmmo(wep)
    local gun = wep --[[@as PW.Arc9Weapon]]
    if gun.ARC9 then gun.ForceDefaultAmmo = 0 end
end

---notes/08 section 6.2: no client presets for a bot (they never load and the server build is the only one), no
---default ammo. SendWeapon stays as it is: other clients need it to see the bot's attachments.
---@param _ply Player
---@param wep Weapon
function ADAPTER:PrepareForBot(_ply, wep)
    local gun = wep --[[@as PW.Arc9Weapon]]
    if not gun.ARC9 then return end
    gun:SetNoPresets(true)
    gun.ForceDefaultAmmo = 0
end

---@param gun PW.Arc9Weapon
---@param index integer?
---@return boolean
local function setFiremode(gun, index)
    local modes = gun:GetValue("Firemodes")
    local count = istable(modes) and #modes or 0
    if count == 0 then return false end
    local wanted = index or (gun:GetFiremode() % count) + 1
    if wanted < 1 or wanted > count then return false end
    gun:SetFiremode(wanted)
    return true
end

local reachMins, reachMaxs = Vector(-2, -2, -2), Vector(2, 2, 2)

---Whether a player, NPC or nextbot is within the bash reach along the owner's aim: the longer of BashLungeRange (what
---the swing locks onto and lunges at; 0 in packs without a lunge) and BashRange (the hit trace after PreBashTime).
---@param owner Player
---@param gun PW.Arc9Weapon
---@return boolean
local function inReach(owner, gun)
    local range = math.max(tonumber(gun:GetProcessedValue("BashLungeRange")) or 0,
        tonumber(gun:GetProcessedValue("BashRange")) or 0)
    local from = owner:EyePos()
    local tr = util.TraceHull({ start = from, endpos = from + owner:GetAimVector() * range, mask = MASK_SHOT,
        filter = owner, mins = reachMins, maxs = reachMaxs })
    local hit = tr.Entity
    if hit == nil or not IsValid(hit) then return false end
    return hit:IsPlayer() or hit:IsNPC() or hit:IsNextBot()
end

---@param owner Player
---@param gun PW.Arc9Weapon
---@return PW.Arc9BashState
function PW.Arc9.BashState(owner, gun)
    local now = CurTime()
    ---@param name string
    ---@return number
    local function number(name)
        return tonumber(gun:GetProcessedValue(name, true)) or 0
    end
    return {
        bash = gun:GetProcessedValue("Bash", true) == true or gun:GetProcessedValue("PrimaryBash", true) == true,
        safe = gun:GetSafe(),
        inSights = gun:GetInSights(),
        grenadePrimed = gun:GetGrenadePrimed(),
        bipod = gun:GetBipod(),
        swinging = gun:GetInMeleeAttack(),
        reloading = gun:GetReloading(),
        cancelsReload = gun:GetProcessedValue("BashCancelsReload", true) == true,
        busy = gun:GetAnimLockTime() > now or gun:GetPrimedAttack() or gun:GetHolsterTime() > 0,
        sprintLock = (gun:SprintLock() and gun:GetProcessedValue("BashWhileSprint", true) ~= true)
            or gun:GetIsSprinting(),
        lastMelee = gun:GetLastMeleeTime(),
        preTime = number("PreBashTime"),
        postTime = number("PostBashTime"),
        speed = math.max(number("BashSpeed"), 0.01),
        now = now,
        reach = inReach(owner, gun)
    }
end

---"firemode": arg is the firemode index, or nil for the next one. ARC9 reads its firemode bind from the client, so a
---bot switches through this call.
---"melee" (T-11.6 follow-up): ARC9's own bash (the swing, the hit after PreBashTime, its damage and cooldown), started
---on the server through MeleeAttack: ARC9's melee key is IN_BULLRUSH read by KeyPressed, which the bot input writer
---does not send. True when the swing started; false without a bash (Bash and PrimaryBash off), while ARC9's own key
---would refuse it (PW.Arc9._BashRefusal) and with no target in reach, so a bot never whiffs into the cooldown.
---@param ply Player
---@param wep Weapon
---@param action string
---@param arg any
---@return boolean
function ADAPTER:BotAction(ply, wep, action, arg)
    local gun = wep --[[@as PW.Arc9Weapon]]
    if not IsValid(gun) or not gun.ARC9 then return false end
    if action == "firemode" then return setFiremode(gun, isnumber(arg) and math.floor(arg) or nil) end
    if action ~= "melee" or not IsValid(ply) or gun:GetOwner() ~= ply then return false end
    if PW.Arc9._BashRefusal(PW.Arc9.BashState(ply, gun)) ~= nil then return false end
    -- bypass: the refusals of the key path were checked above, without the fire cadence ARC9 would also wait for.
    gun:MeleeAttack(true)
    return gun:GetInMeleeAttack()
end
