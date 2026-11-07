-- Additional activation and actual codec seams, written before engine glue.
---@return PW.HardpointLib
local function lib()
    return assert(PW.Hardpoint)
end

---@return PW.HardpointLayout
local function layout()
    return { zones = {
        { id = "one", pos = Vector(0, 0, 0), radius = 100, above = 80, below = 8 },
        { id = "two", pos = Vector(400, 0, 0), radius = 100, above = 80, below = 8 }
    } }
end

return {
    groupName = "PW Hardpoint activation and wire",
    cases = {
        {
            name = "Hardpoint: activation rejects blocked floor hull or unreachable zone; structural filters stay pure",
            func = function()
                local data = layout()
                expect(lib().ValidateLayout(data)).to.beTrue()
                local calls = 0
                expect(lib().ValidateActivation(data, function()
                    calls = calls + 1
                    return calls ~= 2
                end)).to.beFalse()
                expect(calls).to.equal(2)
                expect(lib().ValidateLayout(data)).to.beTrue()
                expect(lib().ValidateActivation(data, function() return true end)).to.beTrue()
                expect(lib().ValidateActivation({ zones = {} }, function() error("must not probe malformed data") end))
                    .to.beFalse()
            end
        },
        {
            name = "Hardpoint: actual bounded codec round trips only active-zone public fields and cleanup tombstones",
            func = function()
                local hp = lib()
                local state = hp.NewState(layout(), { pointTime = 60, scoreLimit = 250, matchTime = 600 }, 10, 7)
                local public = hp.PublicSnapshot(state, 4)
                local names = { "UInt", "Bool", "String", "Vector", "Float" }
                ---@type table<string, any>, {name: string, value: any, width: integer?}[]
                local saved, wire = {}, {}
                local bits, cursor = 0, 0
                for _, name in ipairs(names) do
                    saved["Write" .. name], saved["Read" .. name] = net["Write" .. name], net["Read" .. name]
                    rawset(net, "Write" .. name, function(value, width)
                        ---@cast value any
                        ---@cast width integer?
                        wire[#wire + 1] = { name = name, value = value, width = width }
                        bits = bits + (width or (name == "Bool" and 1 or name == "Vector" and 96
                            or name == "String" and (#value + 1) * 8 or 32))
                    end)
                    rawset(net, "Read" .. name, function(width)
                        cursor = cursor + 1
                        local entry = assert(wire[cursor])
                        assert(entry.name == name and entry.width == width, "codec field order mismatch")
                        return entry.value
                    end)
                end
                local ok, err = pcall(function()
                    hp.WriteSnapshot(public)
                    expect(bits <= 1024).to.beTrue()
                    local decoded = hp.ReadSnapshot()
                    expect(decoded.generation).to.equal(7)
                    expect(decoded.visit).to.equal(1)
                    expect(decoded.zone.id).to.equal("one")
                    expect(decoded.zoneEndsAt).to.equal(70)
                    expect(decoded.matchEndsAt).to.equal(610)
                    expect(cursor).to.equal(#wire)
                    state.finished = true
                    wire, bits, cursor = {}, 0, 0
                    hp.WriteSnapshot(hp.PublicSnapshot(state, 5))
                    expect(hp.ReadSnapshot().active).to.beFalse()
                end)
                for name, value in pairs(saved) do rawset(net, name, value) end
                assert(ok, tostring(err))
            end
        },
        {
            name = "Hardpoint: authored construct geometry passes real activation with three zones and unchanged DOM",
            func = function()
                local map = assert(assert(PW.Map).Get("gm_construct"))
                local data = map.Modes.hardpoint --[[@as PW.HardpointLayout]]
                expect(#data.zones).to.equal(3)
                expect(lib().ValidateLayout(data)).to.beTrue()
                if game.GetMap() == "gm_construct" then expect(lib().CheckActivation(data)).to.beTrue() end
                expect(map.Modes.dom.flags.A).to.equal(Vector(703, -800.34, -143))
                expect(map.Modes.dom.flags.B).to.equal(Vector(823.85, -32, -143))
                expect(map.Modes.dom.flags.C).to.equal(Vector(968.61, 721.69, -143))
                expect(#map.Modes.snd.sites).to.equal(2)
            end
        }
    }
}
