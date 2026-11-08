-- K1: geometry is tested separately from the reveal owner's CUAV/concealment service.

---@return PW.SupportStreaksLib
local function rules()
    return assert(PW.SupportStreaks, "support streak rules are not loaded")
end

---@param position Vector
---@param visible boolean
---@param time number
---@return PW.BotContact
local function contact(position, visible, time)
    return { ent = NULL, pos = position, vel = Vector(), time = time, visible = visible, source = "sight" }
end

return {
    groupName = "PW support directional scan",
    cases = {
        {
            name = "Scan: cone range and LOS filter targets before disclosure",
            func = function()
                local scan = rules().ScanEligible
                local origin, facing = Vector(), Vector(1, 0, 0)
                expect(scan(origin, facing, Vector(1800, 0, 0), true)).to.beTrue()
                expect(scan(origin, facing, Vector(1800.01, 0, 0), true)).to.beFalse()
                expect(scan(origin, facing, Vector(100, 100, 0), true)).to.beTrue()
                expect(scan(origin, facing, Vector(100, 100.01, 0), true)).to.beFalse()
                expect(scan(origin, facing, Vector(100, -100, 0), true)).to.beTrue()
                expect(scan(origin, facing, Vector(100, -100.01, 0), true)).to.beFalse()
                expect(scan(origin, facing, Vector(-100, 0, 0), true)).to.beFalse()
                expect(scan(origin, facing, Vector(100, 0, 0), false)).to.beFalse()
            end
        },
        {
            name = "Scan: total cone is ninety degrees rather than ninety per side",
            func = function()
                local scan = rules().ScanEligible
                expect(scan(Vector(), Vector(10, 0, 0), Vector(100, 173, 0), true)).to.beFalse()
                expect(scan(Vector(), Vector(10, 0, 0), Vector(100, 0, 100), true)).to.beTrue()
                expect(scan(Vector(), Vector(10, 0, 0), Vector(100, 0, 101), true)).to.beFalse()
            end
        },
        {
            name = "Scan: nonfinite and degenerate geometry never selects a target",
            func = function()
                local scan = rules().ScanEligible
                expect(scan(Vector(), Vector(), Vector(1, 0, 0), true)).to.beFalse()
                expect(scan(Vector(), Vector(1, 0, 0), Vector(), true)).to.beFalse()
                expect(scan(Vector(), Vector(1, 0, 0), Vector(math.huge, 0, 0), true)).to.beFalse()
                expect(scan(Vector(), Vector(0 / 0, 0, 0), Vector(1, 0, 0), true)).to.beFalse()
            end
        },
        {
            name = "Scan: bot direction uses contacts or a public lane not hidden enemies",
            func = function()
                local direction = rules().ScanDirection
                local facing = Vector(1, 0, 0)
                expect(direction(Vector(), facing, {})).to.equal(facing)
                expect(direction(Vector(), facing, {}, Vector(0, 100, 0))).to.equal(Vector(0, 1, 0))
                local contacts = { contact(Vector(0, -100, 0), true, 20) }
                expect(direction(Vector(), facing, contacts, Vector(0, 100, 0))).to.equal(Vector(0, -1, 0))
                -- The API cannot query a live entity position: only the stored recognized snapshot is available.
                contacts[1].ent = { GetPos = function() error("hidden live position queried") end } --[[@as Entity]]
                expect(direction(Vector(), facing, contacts)).to.equal(Vector(0, -1, 0))
            end
        },
        {
            name = "Scan: invalid contact and public points fall back to current facing",
            func = function()
                local facing = Vector(0, 1, 0)
                local contacts = { contact(Vector(math.huge, 0, 0), true, 1), contact(Vector(), true, 2) }
                expect(rules().ScanDirection(Vector(), facing, contacts, Vector(0 / 0, 0, 0))).to.equal(facing)
            end
        },
        {
            name = "Scan: registered content has approved initial unlock cost and snapshot lifetime",
            func = function()
                local registry = assert(PW.Registries.streaks)
                local def = assert(registry.Get("directional_scan"), "directional_scan is missing")
                expect(def.Name).to.equal("Directional Scan")
                expect({ def.Kills, def.Score, def.Unlock }).to.deepEqual({ 2, 200, 1 })
                expect(isfunction(def.Prepare)).to.beTrue()
            end
        }
    }
}
