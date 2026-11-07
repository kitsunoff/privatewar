-- T-1.1 kind loader (TASKS.md, "Mandatory test cases"). Pure cases use fake listings; in-game cases load
-- the fixture tree lua/privatewar_fixtures/, which declares its own kind "gadgets".

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---Loads the fixture tree into a fresh context with a capturing logger.
---@return PW.LoadContext context, string[] logged
local function loadFixtures()
    ---@type string[]
    local logged = {}
    local context = PW.Loader.LoadRoot("privatewar_fixtures", {
        log = function(message) logged[#logged + 1] = message end
    })
    return context, logged
end

---Counts logged lines that mention a text.
---@param logged string[]
---@param text string
---@return integer
local function countMentions(logged, text)
    local count = 0
    for _, line in ipairs(logged) do
        if string.find(line, text, 1, true) then count = count + 1 end
    end
    return count
end

return {
    groupName = "PW loader",
    cases = {
        {
            name = "Detects single-file and folder forms from a listing",
            func = function()
                local entries, errors = PW.Loader.ParseListing({ "uav.lua", "readme.txt" }, { "airstrike" })
                expect(#errors).to.equal(0)
                expect(#entries).to.equal(2)
                expect(entries[1].id).to.equal("airstrike")
                expect(entries[1].form).to.equal("folder")
                expect(entries[2].id).to.equal("uav")
                expect(entries[2].form).to.equal("file")
            end
        },
        {
            name = "Rejects invalid ids and file/folder conflicts",
            func = function()
                local entries, errors = PW.Loader.ParseListing({ "Bad Name.lua", "uav.lua" }, { "uav" })
                expect(#entries).to.equal(1)
                expect(entries[1].form).to.equal("folder")
                expect(#errors).to.equal(2)
            end
        },
        {
            name = "Validates required fields: missing and mistyped",
            func = function()
                local required = { Name = "string", Cost = "number" }
                expect(PW.Loader.ValidateRequired({ Name = "A", Cost = 1 }, required)).to.beTrue()
                local okMissing, errMissing = PW.Loader.ValidateRequired({ Name = "A" }, required)
                expect(okMissing).to.beFalse()
                expect(errMissing).to.equal("missing required field Cost (number)")
                local okType, errType = PW.Loader.ValidateRequired({ Name = "A", Cost = "x" }, required)
                expect(okType).to.beFalse()
                expect(errType).to.equal("field Cost must be number, got string")
            end
        },
        {
            name = "Derives the registry accessor name from the folder",
            func = function()
                expect(PW.Loader.AccessorName("streaks")).to.equal("Streaks")
                expect(PW.Loader.AccessorName("weapon_adapters")).to.equal("WeaponAdapters")
            end
        },
        {
            name = "A kind declared in kinds/ of another root is scanned without core changes",
            func = function()
                local context = loadFixtures()
                expect(context.registries.gadgets).to.exist()
            end
        },
        {
            name = "Single-file and folder forms both register",
            func = function()
                local gadgets = loadFixtures().registries.gadgets
                expect(must(gadgets.Get("single")).Name).to.equal("Single")
                local folder = must(gadgets.Get("folder"))
                expect(folder.Name).to.equal("Folder")
                expect(folder.ServerPart).to.beTrue()
                expect(folder.ClientPart).to.beNil()
            end
        },
        {
            name = "The global class table is cleared after each file",
            func = function()
                local gadgets = loadFixtures().registries.gadgets
                expect(_G.GADGET).to.beNil()
                expect(must(gadgets.Get("z_after")).SawPrevious).to.beFalse()
            end
        },
        {
            name = "Syntax and runtime errors skip the file with one log line each; the next file loads",
            func = function()
                local context, logged = loadFixtures()
                local gadgets = context.registries.gadgets
                expect(gadgets.Get("broken_syntax")).to.beNil()
                expect(gadgets.Get("broken_runtime")).to.beNil()
                expect(countMentions(logged, "broken_syntax")).to.equal(1)
                expect(countMentions(logged, "broken_runtime")).to.equal(1)
                expect(gadgets.Get("z_after")).to.exist()
            end
        },
        {
            name = "Missing or mistyped required fields skip the entity with a readable error",
            func = function()
                local context, logged = loadFixtures()
                local gadgets = context.registries.gadgets
                expect(gadgets.Get("missing_field")).to.beNil()
                expect(gadgets.Get("wrong_type")).to.beNil()
                expect(countMentions(logged, "missing required field Cost")).to.equal(1)
                expect(countMentions(logged, "field Cost must be number, got string")).to.equal(1)
            end
        },
        {
            name = "The real tree loads the built-in kinds and installs accessors",
            func = function()
                expect(PW.Kinds).to.exist()
                expect(PW.Modules).to.exist()
                expect(PW.Registries.kinds).to.equal(PW.Kinds)
            end
        }
    }
}
