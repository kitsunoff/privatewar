-- An entity allocated before Spawn errors must still belong to the failed activation and be retired.
---@type PW.StreaksStore?
local previous
---@type Player?
local owner
---@type Entity?
local resource

return {
    groupName = "PW support failed construction ownership",
    beforeEach = function() previous = PW._Streaks end,
    afterEach = function()
        assert(PW.Devices).Clear()
        if resource ~= nil and IsValid(resource) then resource:Remove() end
        if owner ~= nil and IsValid(owner) then owner:Kick("failed construction fixture complete") end
        PW._Streaks = previous
    end,
    cases = {
        {
            name = "Deployment transaction: a post-allocation Spawn error retires the entity and preserves inventory",
            async = true,
            func = function()
                local lib, devices = assert(PW.Streaks), assert(PW.Devices)
                owner = player.CreateNextBot("PW failed device constructor")
                local actor = assert(owner)
                assert(IsValid(actor), "failed construction case needs a free listen-server slot")
                actor:SetTeam(assert(PW.MatchRules).FreeTeam)
                actor:Spawn()
                actor:UnSpectate()
                actor:SetMoveType(MOVETYPE_WALK)
                local legal = false
                for _, area in ipairs(navmesh.GetAllNavAreas() --[[@as CNavArea[] ]]) do
                    if area:GetSizeX() >= 600 and area:GetSizeY() >= 160 then
                        actor:SetPos(area:GetCenter() + Vector(0, 0, 2))
                        actor:SetEyeAngles(Angle())
                        if devices.Prepare(actor, "ammo_cache") ~= nil then legal = true break end
                    end
                end
                assert(legal, "no legal failed-construction scene")
                PW._Streaks = assert(lib._NewStore)({
                    lookup = function(id) return assert(PW.Registries.streaks).Get(id) --[[@as PW.Streak?]] end,
                    phase = function() return "LIVE" end, alive = function() return true end, publish = function() end
                })
                local create = ents.Create
                ---@param class string
                local function allocate(class)
                    local allocated = create(class)
                    if class == "pw_support_device" then
                        resource = allocated
                        rawset(allocated:GetTable(), "Spawn", function() error("intentional device Spawn failure") end)
                    end
                    return allocated
                end
                stub(ents, "Create").with(allocate)
                assert(lib.Give)(actor, "ammo_cache")
                expect(assert(lib.Use)(actor, "ammo_cache")).to.beFalse()
                expect(lib.Inventory(actor)).to.deepEqual({ "ammo_cache" })
                expect(#devices.List()).to.equal(0)
                expect(assert(resource):IsMarkedForDeletion()).to.beTrue()
                timer.Simple(0.05, function()
                    expect(IsValid(resource)).to.beFalse()
                    done()
                end)
            end
        }
    }
}
