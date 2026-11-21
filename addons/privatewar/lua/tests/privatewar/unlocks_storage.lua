-- Versioned unlocks persistence and wire rules (06-progression.md d.5 and d.8).

---@return PW.UnlocksLib
local function unlocks()
    return assert(PW.Unlocks)
end

---@return PW.ProgressionWriter, PW.ProgressionReader
local function wire()
    ---@type { width: integer, value: string|integer|boolean }[]
    local entries = {}
    local pos = 0
    ---@param width integer
    ---@return string|integer|boolean
    local function take(width)
        pos = pos + 1
        local entry = assert(entries[pos], "decoder read past the test wire payload")
        assert(entry.width == width, "decoder used an unexpected width")
        return entry.value
    end
    return {
        uint = function(value, width)
            assert(value >= 0 and value < 2 ^ width, "uint out of range")
            entries[#entries + 1] = { width = width, value = value }
        end,
        string = function(value) entries[#entries + 1] = { width = -1, value = value } end,
        bool = function(value) entries[#entries + 1] = { width = 1, value = value } end
    }, {
        uint = function(width) return take(width) --[[@as integer]] end,
        string = function() return take(-1) --[[@as string]] end,
        bool = function() return take(1) --[[@as boolean]] end
    }
end

return {
    groupName = "PW unlock storage",
    cases = {
        {
            name = "Migration: a v2 progression.json with owned keys and no unlocks.json lists purchases as "
                .. "entitlements; nothing is lost and progression.json stays at version 2",
            func = function()
                local p = assert(PW.Progression)
                local u = unlocks()
                local v2 = { v = 2, xp = 300, weapons = { rifle = 70 }, currency = 220,
                    owned = { "models:operator", "camos:rifle:gold" }, batch = { session = 22, seq = 3 } }
                local old = p._FileFromJson(v2)
                local grants = u._FileFromJson(nil)
                expect(grants.grants).to.deepEqual({})
                expect(u._ListEntitled(old.owned, grants.grants)).to.deepEqual({
                    ["models:operator"] = { source = "purchase", at = 0 },
                    ["camos:rifle:gold"] = { source = "purchase", at = 0 }
                })
                local roundTrip = p._FileToJson(old)
                expect(roundTrip.v).to.equal(2)
                expect(roundTrip.xp).to.equal(300)
                expect(roundTrip.weapons).to.deepEqual({ rifle = 70 })
                expect(roundTrip.currency).to.equal(220)
                expect(roundTrip.owned).to.deepEqual({ "camos:rifle:gold", "models:operator" })
                expect(roundTrip.batch).to.deepEqual({ session = 22, seq = 3 })
                expect(roundTrip.grants).to.beNil()
                expect(roundTrip.claims).to.beNil()
            end
        },
        {
            name = "Migration: a v1 progression.json still loads with no entitlements",
            func = function()
                local p = assert(PW.Progression)
                local u = unlocks()
                local old = p._FileFromJson({ v = 1, xp = 200, weapons = { rifle = 20 } })
                expect(old.xp).to.equal(200)
                expect(old.weapons).to.deepEqual({ rifle = 20 })
                expect(u._ListEntitled(old.owned, u._FileFromJson(nil).grants)).to.deepEqual({})
            end
        },
        {
            name = "Malformed: a missing, empty, non-JSON or wrong-shaped unlocks.json reads as empty; bad entries "
                .. "are dropped",
            func = function()
                local u = unlocks()
                local empty = { v = 1, grants = {}, claims = {}, batch = { session = 0, seq = 0 } }
                expect(u._FileFromJson(nil)).to.deepEqual(empty)
                for _, text in ipairs({ "", "not JSON", "[]", "{\"v\":7}", "{\"v\":1,\"grants\":false}" }) do
                    expect(u._FileFromJson(util.JSONToTable(text, false, true))).to.deepEqual(empty)
                end
                local clean = {
                    v = 1, grants = { ["perks:correct"] = { source = "challenge", at = 20, grant = "123" } },
                    claims = { ["123"] = 20 }, batch = { session = 1, seq = 7 }
                }
                ---@type { v: integer, grants: table<string, table<string, any>>, claims: table<string, number>,
                ---batch: PW.ProgressionBatch }
                local dirty = table.Copy(clean)
                dirty.grants["perks: space"] = { source = "admin", at = 10 }
                dirty.grants["models:source"] = { source = "Admin", at = 10 }
                dirty.grants["models:time"] = { source = "admin", at = -1 }
                dirty.grants["models:fraction"] = { source = "admin", at = 1.2 }
                dirty.grants["models:grant"] = { source = "admin", at = 10, grant = "bad id" }
                dirty.claims["wrong id"] = 10
                dirty.claims.negative = -1
                expect(u._FileFromJson(dirty)).to.deepEqual(clean)
                local output = util.TableToJSON(u._FileToJson(u._FileFromJson(dirty)))
                expect(u._FileFromJson(util.JSONToTable(output, false, true))).to.deepEqual(clean)
                for index = 1, u.MaxGrants + 1 do
                    dirty.grants[string.format("perks:%04d", index)] = { source = "event", at = 0 }
                end
                local grants = u._FileFromJson(dirty).grants
                expect(table.Count(grants)).to.equal(u.MaxGrants)
                expect(grants["perks:0001"]).toNot.beNil()
                expect(grants[string.format("perks:%04d", u.MaxGrants + 1)]).to.beNil()
            end
        },
        {
            name = "Claims: past MaxClaims the oldest are pruned by time, ties by id",
            func = function()
                local u = unlocks()
                ---@type table<string, integer>
                local claims = { newest = 1000, oldest = 0, aa = 1, zz = 1 }
                for index = 1, u.MaxClaims - 2 do claims["later:" .. index] = 2 end
                local kept = u._CheckClaims(claims)
                expect(table.Count(kept)).to.equal(u.MaxClaims)
                expect(kept.newest).to.equal(1000)
                expect(kept.oldest).to.beNil()
                expect(kept.aa).to.equal(1)
                expect(kept.zz).to.beNil()
                expect(claims.oldest).to.equal(0)
            end
        },
        {
            name = "Wire: the unlocks upload and the delta extension survive encode and decode; forged counts are "
                .. "bounded",
            func = function()
                local u = unlocks()
                local claims = { ["weekly:123"] = 55 }
                local grants = { ["camos:rifle:gold"] = { source = "challenge", at = 55, grant = "weekly:123" } }
                local writer, reader = wire()
                u._EncodeUpload({ v = 1, grants = grants, claims = claims, batch = { session = 0, seq = 0 } }, writer)
                expect(u._DecodeUpload(reader)).to.deepEqual({
                    grants = { ["camos:rifle:gold"] = true }, claims = { ["weekly:123"] = true }
                })
                writer, reader = wire()
                local part = { granted = grants, revoked = { ["perks:other"] = "admin" }, claims = claims }
                u._EncodeDeltaPart(part, writer)
                expect(u._DecodeDeltaPart(reader)).to.deepEqual(part)
                expect(u.UploadMaxBytes).to.equal(53893)
                writer, reader = wire()
                writer.uint(1, 8)
                writer.uint(u.MaxGrants + 1, 16)
                expect(u._DecodeUpload(reader)).to.beNil()
                writer, reader = wire()
                writer.uint(1, 8)
                writer.uint(0, 16)
                writer.uint(u.MaxClaims + 1, 16)
                expect(u._DecodeUpload(reader)).to.beNil()
                writer, reader = wire()
                writer.uint(u.MaxDeltaGrants + 1, 8)
                local rejected = u._DecodeDeltaPart(reader)
                expect(rejected.granted or {}).to.deepEqual({})
                expect(rejected.revoked or {}).to.deepEqual({})
                expect(rejected.claims or {}).to.deepEqual({})
            end
        },
        {
            name = "Unlock file delta keeps existing metadata, records claims and changes only once per batch",
            func = function()
                local u = unlocks()
                local current = u._FileFromJson({ v = 1, claims = { earlier = 10 }, batch = { session = 7, seq = 2 },
                    grants = {
                        ["perks:keep"] = { source = "event", at = 10 },
                        ["perks:remove"] = { source = "challenge", at = 10, grant = "earlier" }
                    } })
                local delta = { session = 7, seq = 3, xp = 0, weapons = {}, claims = { reward = 20 },
                    granted = {
                        ["perks:keep"] = { source = "admin", at = 20 },
                        ["perks:add"] = { source = "challenge", at = 20, grant = "reward" }
                    }, revoked = { ["perks:remove"] = "admin", ["perks:not_owned"] = "event" } }
                local updated, applied, changes = u._ApplyDelta(current, delta)
                expect(applied).to.beTrue()
                expect(updated.grants["perks:keep"]).to.deepEqual({ source = "event", at = 10 })
                expect(updated.grants["perks:add"]).to.deepEqual(delta.granted["perks:add"])
                expect(updated.grants["perks:remove"]).to.beNil()
                expect(updated.claims).to.deepEqual({ earlier = 10, reward = 20 })
                expect(assert(changes).revoked).to.deepEqual({ ["perks:remove"] = "admin" })
                expect(assert(changes).granted).to.deepEqual({ ["perks:add"] = delta.granted["perks:add"] })
                local duplicate, repeated, repeatedChanges = u._ApplyDelta(updated, delta)
                expect(duplicate).to.equal(updated)
                expect(repeated).to.beFalse()
                expect(repeatedChanges).to.beNil()
                expect(current.grants["perks:remove"]).toNot.beNil()
                expect(current.grants["perks:add"]).to.beNil()
            end
        }
    }
}
