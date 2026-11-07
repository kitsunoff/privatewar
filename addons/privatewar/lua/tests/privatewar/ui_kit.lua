-- T-1.19 widget kit v0: settings form generation (TASKS.md, "Mandatory test cases" T-1.19: the form produces one
-- control per setting of the right type; drawing is a checkpoint; 01-extensibility.md d.17). Pure: the groups come
-- from PW.Settings._Groups over plain entity tables (no registry), so no store is touched.

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.UILib
local function kit()
    return must(PW.UI)
end

local mode = {
    ClassName = "pwt_mode",
    Settings = {
        limit = { type = "int", default = 5, min = 1, max = 10, label = "Limit" },
        ratio = { type = "float", default = 1.5, min = 0, max = 3 },
        free = { type = "int", default = 3 },
        hard = { type = "bool", default = false },
        style = { type = "enum", default = "a", options = { "a", "b" } },
        weapons = { type = "set", default = { "x" }, options = { "x", "y" } },
        tags = { type = "set", default = {} }
    }
}

local module = {
    ClassName = "pwt_mod",
    Settings = {
        count = { type = "int", default = 2, min = 0, max = 4 },
        budget = { scope = "server", type = "float", default = 1 }
    }
}

---Match groups of the test mode and module, values = defaults.
---@return PW.SettingGroup[]
local function groups()
    return PW.Settings._Groups({
        mode = mode, modules = { module }, scope = "match", log = function() end,
        valueOf = function(def) return def.default end
    })
end

---@param section PW.UIFormSection
---@return table<string, PW.UIFormControl>
local function byId(section)
    ---@type table<string, PW.UIFormControl>
    local controls = {}
    for _, control in ipairs(section.controls) do controls[control.id] = control end
    return controls
end

return {
    groupName = "PW ui kit form",
    cases = {
        {
            name = "Settings form generation produces one control per setting of the right type",
            func = function()
                local form = kit().BuildForm(groups(), { pwt_mode = "Test mode" })
                expect(#form).to.equal(2)
                local first, second = must(form[1]), must(form[2])
                expect(first.owner).to.equal("pwt_mode")
                expect(first.ownerKind).to.equal("modes")
                expect(first.title).to.equal("Test mode")
                expect(#first.controls).to.equal(7)
                ---@type table<string, string>
                local widgets = {}
                for id, control in pairs(byId(first)) do widgets[id] = control.widget end
                expect(widgets).to.deepEqual({
                    ["pwt_mode.limit"] = "slider", ["pwt_mode.ratio"] = "slider", ["pwt_mode.free"] = "number",
                    ["pwt_mode.hard"] = "checkbox", ["pwt_mode.style"] = "combo",
                    ["pwt_mode.weapons"] = "multiselect", ["pwt_mode.tags"] = "idlist"
                })
                expect(second.owner).to.equal("pwt_mod")
                expect(second.title).to.equal("pwt_mod")
                expect(#second.controls).to.equal(1)
                expect(must(second.controls[1]).widget).to.equal("slider")
            end
        },
        {
            name = "Controls carry label, value, range, decimals and options from the definition",
            func = function()
                local controls = byId(must(kit().BuildForm(groups())[1]))
                local limit = must(controls["pwt_mode.limit"])
                expect(limit.label).to.equal("Limit")
                expect(limit.value).to.equal(5)
                expect(limit.min).to.equal(1)
                expect(limit.max).to.equal(10)
                expect(limit.decimals).to.equal(0)
                expect(must(controls["pwt_mode.ratio"]).decimals).to.equal(2)
                expect(must(controls["pwt_mode.style"]).options).to.deepEqual({ "a", "b" })
                expect(must(controls["pwt_mode.weapons"]).value).to.deepEqual({ x = true })
                expect(must(controls["pwt_mode.tags"]).label).to.equal("tags")
            end
        },
        {
            name = "No groups make an empty form",
            func = function()
                expect(#kit().BuildForm({})).to.equal(0)
            end
        },
        {
            name = "ToWire gives the text form of pw_settings_match",
            func = function()
                local controls = byId(must(kit().BuildForm(groups())[1]))
                expect(kit().ToWire(must(controls["pwt_mode.limit"]), 7)).to.equal("7")
                expect(kit().ToWire(must(controls["pwt_mode.ratio"]), 2.5)).to.equal("2.5")
                expect(kit().ToWire(must(controls["pwt_mode.hard"]), true)).to.equal("1")
                expect(kit().ToWire(must(controls["pwt_mode.style"]), "b")).to.equal("b")
                expect(kit().ToWire(must(controls["pwt_mode.weapons"]), { y = true, x = true })).to.equal("x,y")
            end
        }
    }
}
