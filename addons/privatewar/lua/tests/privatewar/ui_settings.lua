-- T-7.2 settings forms generated from schemas (TASKS.md, "Mandatory test cases" T-7.2: one control per setting,
-- correct widget per type, values written back through the validated path; 01-extensibility.md d.17;
-- 10-frontend.md d.1, d.8). Pure cases over plain data: the row model per type, value clamping, which forms are
-- editable for the privilege and the phase, the diff that is sent, the message per scope, the sections of the
-- SETTINGS screen, and the pause menu's SETTINGS item opening the client settings. No bots, no store is touched.

---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.UISettingsLib
local function settings()
    return must(must(PW.UI).Settings)
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
        budget = { scope = "server", type = "float", default = 1, min = 0.5, max = 10,
            description = "Time per tick" },
        hints = { scope = "client", type = "enum", default = "auto", options = { "auto", "pad" } }
    }
}

---@param scope PW.SettingScope
---@param values? table<string, any> shown values by full id (default: the defaults)
---@return PW.SettingGroup[]
local function groups(scope, values)
    return PW.Settings._Groups({
        mode = scope == "match" and mode or nil, modules = { module }, scope = scope, log = function() end,
        valueOf = function(def)
            if values ~= nil and values[def.id] ~= nil then return values[def.id] end
            return def.default
        end
    })
end

---@param scope PW.SettingScope
---@param facts? PW.UISettingsFacts
---@param values? table<string, any>
---@return PW.UISettingsModel
local function model(scope, facts, values)
    return settings().Model(scope, groups(scope, values), {
        titles = { pwt_mode = "Test mode", pwt_mod = "Test module" },
        facts = facts or { phase = "LOBBY", canChange = true }
    })
end

---@param form PW.UISettingsModel
---@return table<string, PW.UIFormControl>
local function rows(form)
    ---@type table<string, PW.UIFormControl>
    local out = {}
    for _, section in ipairs(form.sections) do
        for _, control in ipairs(section.controls) do out[control.id] = control end
    end
    return out
end

---@param form PW.UISettingsModel
---@param id string
---@return PW.SettingDef
local function defOf(form, id)
    return must(form.defs[id])
end

---@param screens string[]
---@param tabs string[]
---@return PW.UIRouterModel
local function routerWith(screens, tabs)
    ---@type PW.Screen[]
    local list = {}
    for index, id in ipairs(screens) do
        local tab = string.match(id, "^root_(.+)$")
        local screen = { ClassName = id, Tab = tab or "play", Root = tab ~= nil, Build = function() end }
        list[index] = screen --[[@as PW.Screen]]
    end
    return must(must(PW.UI).Router).New(list, tabs)
end

return {
    groupName = "PW UI settings forms",
    cases = {
        {
            name = "Row model: one row per setting with the widget of its type, grouped per owner, mode first",
            func = function()
                local form = model("match")
                expect(form.scope).to.equal("match")
                expect(#form.sections).to.equal(2)
                local first, second = must(form.sections[1]), must(form.sections[2])
                expect(first.owner).to.equal("pwt_mode")
                expect(first.title).to.equal("Test mode")
                expect(second.title).to.equal("Test module")
                ---@type table<string, string>
                local widgets = {}
                for id, control in pairs(rows(form)) do widgets[id] = control.widget end
                expect(widgets).to.deepEqual({
                    ["pwt_mode.limit"] = "slider", ["pwt_mode.ratio"] = "slider", ["pwt_mode.free"] = "number",
                    ["pwt_mode.hard"] = "checkbox", ["pwt_mode.style"] = "combo",
                    ["pwt_mode.weapons"] = "multiselect", ["pwt_mode.tags"] = "idlist", ["pwt_mod.count"] = "slider"
                })
            end
        },
        {
            name = "Row model per scope: server and client forms list only the settings of their scope",
            func = function()
                local server = rows(model("server"))
                expect(table.GetKeys(server)).to.deepEqual({ "pwt_mod.budget" })
                expect(must(server["pwt_mod.budget"]).widget).to.equal("slider")
                expect(must(server["pwt_mod.budget"]).decimals).to.equal(2)
                local client = rows(model("client"))
                expect(table.GetKeys(client)).to.deepEqual({ "pwt_mod.hints" })
                expect(must(client["pwt_mod.hints"]).widget).to.equal("combo")
                expect(must(client["pwt_mod.hints"]).options).to.deepEqual({ "auto", "pad" })
            end
        },
        {
            name = "Row model: rows show the current values, clamped, and keep label, range and options",
            func = function()
                local form = model("match", nil, { ["pwt_mode.limit"] = 7, ["pwt_mode.hard"] = true })
                local controls = rows(form)
                local limit = must(controls["pwt_mode.limit"])
                expect(limit.value).to.equal(7)
                expect(limit.label).to.equal("Limit")
                expect(limit.min).to.equal(1)
                expect(limit.max).to.equal(10)
                expect(must(controls["pwt_mode.hard"]).value).to.beTrue()
                expect(must(controls["pwt_mode.weapons"]).value).to.deepEqual({ x = true })
                expect(form.values["pwt_mode.limit"]).to.equal(7)
                local wild = rows(model("match", nil, { ["pwt_mode.limit"] = 99, ["pwt_mode.style"] = "zzz" }))
                expect(must(wild["pwt_mode.limit"]).value).to.equal(10)
                expect(must(wild["pwt_mode.style"]).value).to.equal("a")
            end
        },
        {
            name = "Row model: a setting's description reaches its control and the notes of the form",
            func = function()
                local form = model("server")
                local budget = must(rows(form)["pwt_mod.budget"])
                expect(budget.description).to.equal("Time per tick")
                expect(settings().Notes(form)).to.deepEqual({ "budget: Time per tick" })
                expect(settings().Notes(model("client"))).to.deepEqual({})
            end
        },
        {
            name = "Clamping: numbers are rounded and clamped, invalid values are refused with a reason",
            func = function()
                local form = model("match")
                local limit, ratio = defOf(form, "pwt_mode.limit"), defOf(form, "pwt_mode.ratio")
                local value, note = settings().Clamp(limit, 4.6)
                expect(value).to.equal(5)
                expect(note).to.beNil()
                value, note = settings().Clamp(limit, 42)
                expect(value).to.equal(10)
                expect(note).to.equal("clamped")
                value, note = settings().Clamp(limit, -3)
                expect(value).to.equal(1)
                expect(note).to.equal("clamped")
                value = settings().Clamp(ratio, 2.25)
                expect(value).to.equal(2.25)
                value, note = settings().Clamp(defOf(form, "pwt_mode.style"), "zzz")
                expect(value).to.beNil()
                expect(note).to.beA("string")
                value = settings().Clamp(defOf(form, "pwt_mode.hard"), "yes")
                expect(value).to.beNil()
                value = settings().Clamp(defOf(form, "pwt_mode.weapons"), { "y" })
                expect(value).to.deepEqual({ y = true })
            end
        },
        {
            name = "Editability: client always; server needs the privilege in any phase; match also needs LOBBY",
            func = function()
                local editable = settings().Editable
                expect(editable("client", { phase = "LIVE", canChange = false })).to.beTrue()
                expect(editable("server", { phase = "LIVE", canChange = true })).to.beTrue()
                local ok, reason = editable("server", { phase = "LOBBY", canChange = false })
                expect(ok).to.beFalse()
                expect(reason).to.equal(settings().Reasons.privilege)
                expect(editable("match", { phase = "LOBBY", canChange = true })).to.beTrue()
                ok, reason = editable("match", { phase = "LIVE", canChange = true })
                expect(ok).to.beFalse()
                expect(reason).to.equal(settings().Reasons.phase)
                ok, reason = editable("match", { phase = "LOBBY", canChange = false })
                expect(ok).to.beFalse()
                expect(reason).to.equal(settings().Reasons.privilege)
            end
        },
        {
            name = "Editability reaches the model: a guest's server form is read only with the reason",
            func = function()
                local guest = model("server", { phase = "LOBBY", canChange = false })
                expect(guest.editable).to.beFalse()
                expect(guest.reason).to.equal(settings().Reasons.privilege)
                local host = model("server", { phase = "LIVE", canChange = true })
                expect(host.editable).to.beTrue()
                expect(host.reason).to.beNil()
            end
        },
        {
            name = "Diff: only changed values are sent, in their text form, sorted by id",
            func = function()
                local form = model("match", nil, { ["pwt_mode.limit"] = 7 })
                local changes = settings().Diff(form, {
                    ["pwt_mode.limit"] = 7, ["pwt_mode.ratio"] = 2, ["pwt_mode.hard"] = true,
                    ["pwt_mode.weapons"] = { x = true }
                })
                expect(#changes).to.equal(2)
                expect(must(changes[1]).id).to.equal("pwt_mode.hard")
                expect(must(changes[1]).text).to.equal("1")
                expect(must(changes[2]).id).to.equal("pwt_mode.ratio")
                expect(must(changes[2]).value).to.equal(2)
                expect(must(changes[2]).text).to.equal("2")
            end
        },
        {
            name = "Diff: a value clamped back to the current one, an invalid value and an unknown id send nothing",
            func = function()
                local form = model("match", nil, { ["pwt_mode.limit"] = 10 })
                local changes = settings().Diff(form, {
                    ["pwt_mode.limit"] = 500, ["pwt_mode.style"] = "zzz", ["nope.nothing"] = 1
                })
                expect(#changes).to.equal(0)
                local clamped = settings().Diff(form, { ["pwt_mode.ratio"] = 9 })
                expect(#clamped).to.equal(1)
                expect(must(clamped[1]).value).to.equal(3)
                expect(must(clamped[1]).text).to.equal("3")
            end
        },
        {
            name = "Diff: after Apply the same edit is not sent again; a read-only form sends nothing",
            func = function()
                local form = model("match")
                local changes = settings().Diff(form, { ["pwt_mode.limit"] = 8 })
                expect(#changes).to.equal(1)
                settings().Apply(form, changes)
                expect(form.values["pwt_mode.limit"]).to.equal(8)
                expect(#settings().Diff(form, { ["pwt_mode.limit"] = 8 })).to.equal(0)
                local guest = model("match", { phase = "LOBBY", canChange = false })
                expect(#settings().Diff(guest, { ["pwt_mode.limit"] = 8 })).to.equal(0)
            end
        },
        {
            name = "Each scope writes back through its validated path",
            func = function()
                expect(settings().Target("match")).to.equal("pw_settings_match")
                expect(settings().Target("server")).to.equal("pw_settings_server")
                expect(settings().Target("client")).to.equal("local")
                expect(model("server").target).to.equal("pw_settings_server")
            end
        },
        {
            name = "SETTINGS sections: Personal is open, Host and Enabled content explain their locks",
            func = function()
                local host = settings().Sections({ phase = "LOBBY", canChange = true, canToggle = true })
                ---@type string[]
                local ids = {}
                for index, card in ipairs(host) do ids[index] = card.id end
                expect(table.concat(ids, ",")).to.equal("client,server,content")
                for _, card in ipairs(host) do expect(card.locked).to.beFalse() end
                local guest = settings().Sections({ phase = "LIVE", canChange = false, canToggle = false })
                expect(must(guest[1]).locked).to.beFalse()
                expect(must(guest[2]).locked).to.beTrue()
                expect(must(guest[2]).reason).to.equal(settings().Reasons.privilege)
                expect(must(guest[3]).locked).to.beTrue()
                local live = settings().Sections({ phase = "LIVE", canChange = true, canToggle = true })
                expect(must(live[2]).locked).to.beFalse()
                expect(must(live[3]).locked).to.beTrue()
                expect(must(live[3]).reason).to.equal(settings().Reasons.content)
            end
        },
        {
            name = "Pause menu: the SETTINGS item is usable in every match phase",
            func = function()
                local match = must(must(PW.UI).Match)
                for _, phase in ipairs({ "PREMATCH", "LIVE", "POSTMATCH" }) do
                    local facts = { phase = phase, canAbort = false, classes = false, host = false }
                    for _, item in ipairs(match.PauseItems(facts)) do
                        if item.id == "settings" then
                            expect(item.locked).to.beFalse()
                            expect(item.reason).to.beNil()
                        end
                    end
                end
            end
        },
        {
            name = "Pause SETTINGS opens the client settings on the MATCH stack; Back returns to the pause menu",
            func = function()
                local router = must(must(PW.UI).Router)
                local nav = routerWith({ "root_match", "settings" }, { "match", "loadout" })
                expect(settings().Open(nav, "client")).to.beTrue()
                expect(must(router.Top(nav)).ClassName).to.equal("settings")
                expect(settings().TakeSection()).to.equal("client")
                expect(settings().TakeSection()).to.beNil()
                expect(settings().Open(nav, "client")).to.beFalse()
                expect(router.Depth(nav)).to.equal(2)
                expect(router.Back(nav, "LIVE")).to.equal("pop")
                expect(must(router.Top(nav)).ClassName).to.equal("root_match")
            end
        },
        {
            name = "Open does nothing without the settings screen or on an empty tab",
            func = function()
                expect(settings().Open(routerWith({ "root_match" }, { "match" }), "client")).to.beFalse()
                expect(settings().Open(routerWith({ "settings" }, { "match" }), "client")).to.beFalse()
                settings().TakeSection()
            end
        }
    }
}
