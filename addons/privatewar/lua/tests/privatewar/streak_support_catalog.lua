-- Isolate the actual cache consumer from placement; genuine owned weapons deliberately expose positive capacity.
---@type Player?
local recipient
---@type Entity?
local entity
---@type PW.Instance?
local instance
---@type PW.SupportDevice[]
local previous = {}

return {
    groupName = "PW support cache public catalogue eligibility",
    beforeEach = function() previous = assert(PW.Devices)._Records end,
    afterEach = function()
        assert(PW.Devices)._Records = previous
        if instance ~= nil then instance:Remove() instance = nil end
        if entity ~= nil and IsValid(entity) then entity:Remove() end
        if recipient ~= nil and IsValid(recipient) then recipient:Kick("cache catalogue fixture complete") end
    end,
    cases = {
        {
            name = "Cache catalogue: positive-capacity launcher and non-PW grenade never enter ordinary reserve supply",
            func = function()
                local owner = player.CreateNextBot("PW cache catalogue fixture")
                assert(IsValid(owner), "cache catalogue case needs a free listen-server slot")
                recipient = owner
                owner:SetTeam(assert(PW.MatchRules).FreeTeam)
                owner:Spawn()
                owner:GodEnable()
                owner:StripWeapons()
                local pistol = assert(owner:Give("weapon_pistol"))
                local launcher = assert(owner:Give("weapon_rpg"))
                local grenade = assert(owner:Give("weapon_frag"))
                local catalogue = assert(PW.Weapons)
                expect(assert(catalogue.Get(launcher:GetClass())).Kind).to.equal("launcher")
                expect(assert(catalogue.Get(grenade:GetClass())).Kind).to.equal("throwable")
                local original = PW.Adapters.CallFor
                ---@param weapon Weapon|string
                ---@param method string
                local function adapter(weapon, method, ...)
                    if method == "GetClip" and (weapon == launcher or weapon == grenade) then return 1, 2 end
                    return original(weapon, method, ...)
                end
                stub(PW.Adapters, "CallFor").with(adapter)
                owner:SetAmmo(0, pistol:GetPrimaryAmmoType())
                owner:SetAmmo(0, launcher:GetPrimaryAmmoType())
                owner:SetAmmo(0, grenade:GetPrimaryAmmoType())
                entity = ents.Create("base_anim")
                entity:SetPos(owner:GetPos() + Vector(80, 0, 0))
                entity:Spawn()
                instance = PW.Instance({ OnEquip = function() end }, owner)
                local now = CurTime()
                assert(PW.Devices)._Records = { { owner = owner, kind = "ammo_cache", entity = entity,
                    position = owner:GetPos() + Vector(80, 0, 0), team = owner:Team(), ends = now + 45,
                    instance = instance --[[@as PW.StreakInstance]], charges = 10, receipts = {}, pulse = now } }
                stub(util, "TraceLine").returns({ Fraction = 1 })
                PW.Call(assert(PW.Modules.GetStored("support_devices")), "Maintain", now, 0.25)
                expect(owner:GetAmmoCount(pistol:GetPrimaryAmmoType())).to.equal(18)
                expect(owner:GetAmmoCount(launcher:GetPrimaryAmmoType())).to.equal(0)
                expect(owner:GetAmmoCount(grenade:GetPrimaryAmmoType())).to.equal(0)
            end
        }
    }
}
