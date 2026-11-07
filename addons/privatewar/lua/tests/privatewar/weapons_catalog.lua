-- T-3.3 weapon catalogue (TASKS.md, "Mandatory test cases" T-3.3; 04-weapons.md d.3; 06-progression.md d.2;
-- docs/api/adapter.md "Weapon catalogue"). Pure cases: fixture adapters in fresh registries of the kind
-- weapon_adapters, weapons registries built by PW.Loader.LoadRoot over a fake file system (declarative files) or
-- by hand. No bots, no real adapters, no engine registry is touched; the store of the catalogue module is released
-- after every case.

local root = "pwt_catalogue"

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.WeaponsCatalogLib
local function catalogue()
    return must(PW.WeaponsCatalog)
end

---A file system holding only a weapons kind declaration and the given declarative weapon files.
---@param declared table<string, table<string, any>> class -> fields of the WEAPON table
---@return PW.LoaderFs
local function fakeFs(declared)
    return {
        find = function(pattern)
            if pattern == root .. "/kinds/*" then return { "weapons.lua" }, {} end
            if pattern ~= root .. "/weapons/*" then return {}, {} end
            ---@type string[]
            local files = {}
            for class in pairs(declared) do files[#files + 1] = class .. ".lua" end
            table.sort(files)
            return files, {}
        end,
        exists = function() return false end,
        run = function(path)
            if path == root .. "/kinds/weapons.lua" then
                local kind = rawget(_G, "KIND") --[[@as table<string, any>]]
                kind.Folder, kind.Global, kind.Subscribe = "weapons", "WEAPON", "never"
                return true
            end
            local class = string.match(path, "weapons/(.+)%.lua$") --[[@as string]]
            local weapon = rawget(_G, "WEAPON") --[[@as table<string, any>]]
            for key, value in pairs(declared[class]) do weapon[key] = istable(value) and table.Copy(value) or value end
            return true
        end,
        send = function() end
    }
end

---Loads the declarative files like the real boot does; returns the registries of the context.
---@param declared table<string, table<string, any>>
---@return table<string, PW.Registry>
local function loadRegistries(declared)
    return PW.Loader.LoadRoot(root, { fs = fakeFs(declared), log = function() end }).registries
end

---@param declared table<string, table<string, any>>
---@return PW.Registry
local function loadWeapons(declared)
    return must(loadRegistries(declared).weapons)
end

---A fixture adapter entity table.
---@param priority number
---@param list PW.WeaponInfo[]
---@param fields? table<string, any>
---@return table<string, any>
local function adapterTable(priority, list, fields)
    local tbl = {
        Priority = priority,
        IsAvailable = function() return true end,
        Claims = function() return true end,
        ListWeapons = function() return list end
    }
    for key, value in pairs(fields or {}) do tbl[key] = value end
    return tbl
end

---The enabled list of a resolved weapon_adapters registry holding the given adapters.
---@param entries table<string, table<string, any>>
---@return PW.Adapter[]
local function adapterList(entries)
    local registry = PW.Registry.New("weapon_adapters", { log = function() end })
    for id, tbl in pairs(entries) do registry.Register(tbl, id) end
    registry.ResolveAll()
    return registry.GetEnabledList() --[[@as PW.Adapter[] ]]
end

---@param class string
---@param fields? table<string, any>
---@return PW.WeaponInfo
local function info(class, fields)
    local value = { class = class, name = "Listed " .. class, kind = "gun", slot = 1 }
    for key, field in pairs(fields or {}) do value[key] = field end
    return value
end

---@param list PW.Entity[]
---@return string
local function ids(list)
    ---@type string[]
    local out = {}
    for index, entity in ipairs(list) do out[index] = entity.ClassName end
    return table.concat(out, ",")
end

local curated = {
    Category = "ar",
    Name = "Declared name",
    Unlock = 4,
    Attachments = { optic_acog = { Unlock = 5 }, muzzle_supp = { Unlock = 12, Cost = 2 }, meme = { Hidden = true } },
    Camos = { gold = { Unlock = 30 } }
}

---A call function without the core's disabling: an erroring method answers nil.
---@param adapter table<string, any>
---@param method string
---@param ... any
---@return any
local function safeCall(adapter, method, ...)
    local ok, result = pcall(adapter[method], adapter, ...)
    if ok then return result end
    return nil
end

return {
    groupName = "PW weapon catalogue",
    afterEach = function()
        catalogue()._Release()
    end,
    cases = {
        {
            name = "Catalogue: a declarative entry beats a programmatic soft entry per field; soft fills the rest",
            func = function()
                local registry = loadWeapons({ pwt_decl = { Category = "ar", Name = "Declared name" } })
                local adapters = adapterList({ pwt_a = adapterTable(0, { info("pwt_decl", { category = "smg" }) }) })
                catalogue().Populate(registry, adapters)
                local entry = must(registry.Get("pwt_decl")) --[[@as PW.Weapon]]
                expect(entry.Category).to.equal("ar")
                expect(entry.Name).to.equal("Declared name")
                expect(entry.Kind).to.equal("gun")
                expect(entry.Slot).to.equal(1)
            end
        },
        {
            name = "Catalogue: the declarative entry wins also when the soft entry is registered first",
            func = function()
                local registry = PW.Registry.New("weapons", { log = function() end })
                local adapters = adapterList({ pwt_a = adapterTable(0, { info("pwt_decl", { category = "smg" }) }) })
                catalogue().Populate(registry, adapters)
                registry.Register({ Category = "ar", Name = "Declared name" }, "pwt_decl")
                registry.ResolveAll()
                local entry = must(registry.Get("pwt_decl")) --[[@as PW.Weapon]]
                expect(entry.Category).to.equal("ar")
                expect(entry.Name).to.equal("Declared name")
                expect(entry.Kind).to.equal("gun")
            end
        },
        {
            name = "Catalogue: a class only an adapter lists becomes an entry with the listed fields",
            func = function()
                local registry = loadWeapons({})
                local adapters = adapterList({ pwt_a = adapterTable(0, { info("pwt_only", { category = "smg" }) }) })
                expect(catalogue().Populate(registry, adapters)).to.equal(1)
                local entry = must(registry.Get("pwt_only")) --[[@as PW.Weapon]]
                expect(entry.Name).to.equal("Listed pwt_only")
                expect(entry.Category).to.equal("smg")
            end
        },
        {
            name = "Catalogue: the higher-Priority adapter fills first; a failing or unavailable adapter is skipped",
            func = function()
                local registry = loadWeapons({})
                local adapters = adapterList({
                    pwt_low = adapterTable(-100, { info("pwt_x", { name = "Low", category = "low" }) }),
                    pwt_high = adapterTable(100, { info("pwt_x", { name = "High" }) }),
                    pwt_off = adapterTable(500, { info("pwt_x", { name = "Off" }),
                        info("pwt_off_only") }, { IsAvailable = function() return false end }),
                    pwt_bad = adapterTable(400, {}, { ListWeapons = function() error("boom") end })
                })
                catalogue().Populate(registry, adapters, safeCall)
                local entry = must(registry.Get("pwt_x")) --[[@as PW.Weapon]]
                expect(entry.Name).to.equal("High")
                expect(entry.Category).to.equal("low")
                expect(registry.Get("pwt_off_only")).to.beNil()
            end
        },
        {
            name = "Catalogue: curation fields (Attachments, Camos, Unlock) survive the merge, nested tables per key",
            func = function()
                local registry = loadWeapons({ pwt_cur = curated })
                local adapters = adapterList({ pwt_a = adapterTable(0, { info("pwt_cur") }) })
                -- a soft curation entry from another listener adds a camo and missing attachment keys only
                registry.Register({
                    Attachments = { optic_acog = { Unlock = 99, Cost = 1 }, grip = { Unlock = 7 } },
                    Camos = { silver = { Unlock = 10 } }
                }, "pwt_cur", { soft = true })
                catalogue().Populate(registry, adapters)
                local entry = must(registry.Get("pwt_cur")) --[[@as PW.Weapon]]
                local attachments = must(entry.Attachments)
                expect(must(attachments.optic_acog).Unlock).to.equal(5)
                expect(must(attachments.optic_acog).Cost).to.equal(1)
                expect(must(attachments.muzzle_supp).Cost).to.equal(2)
                expect(must(attachments.meme).Hidden).to.beTrue()
                expect(must(attachments.grip).Unlock).to.equal(7)
                local camos = must(entry.Camos)
                expect(must(camos.gold).Unlock).to.equal(30)
                expect(must(camos.silver).Unlock).to.equal(10)
                expect(entry.Unlock).to.equal(4)
                expect(entry.Name).to.equal("Declared name")
            end
        },
        {
            name = "Catalogue: a soft fill never aliases the adapter's data",
            func = function()
                local registry = loadWeapons({})
                local list = { info("pwt_alias") }
                catalogue().Populate(registry, adapterList({ pwt_a = adapterTable(0, list) }))
                must(registry.Get("pwt_alias")).Name = "Changed"
                expect(list[1].name).to.equal("Listed pwt_alias")
            end
        },
        {
            name = "Catalogue: a per-weapon enable ConVar hides the weapon from the enabled list",
            func = function()
                local registries = loadRegistries({ pwt_on = { Category = "ar" }, pwt_off = { Category = "ar" } })
                local registry = must(registries.weapons)
                local enable = must(PW.Enable)
                local hidden = enable._ConVarName(enable._KindToken(registries, "weapons"), "pwt_off")
                expect(hidden).to.equal("pw_weapon_pwt_off_enabled")
                expect(enable.ConVarName("weapons", "pwt_off")).to.equal(hidden)
                catalogue().Populate(registry, adapterList({ pwt_a = adapterTable(0, { info("pwt_adapter") }) }))
                local snapshot = enable._TakeSnapshot(registries, function(name) return name ~= hidden end)
                enable._Apply(registries, snapshot)
                expect(ids(registry.GetEnabledList())).to.equal("pwt_adapter,pwt_on")
                expect(ids(catalogue().GetByCategory("ar", registry))).to.equal("pwt_on")
                expect(ids(registry.GetList())).to.equal("pwt_adapter,pwt_off,pwt_on")
            end
        },
        {
            name = "Catalogue: GetByCategory lists only enabled entries of the category, sorted by class",
            func = function()
                local registry = loadWeapons({ pwt_b = { Category = "smg" }, pwt_a = { Category = "smg" } })
                catalogue().Populate(registry, adapterList({
                    pwt_x = adapterTable(0, { info("pwt_c", { category = "ar" }), info("pwt_d") })
                }))
                expect(ids(catalogue().GetByCategory("smg", registry))).to.equal("pwt_a,pwt_b")
                expect(ids(catalogue().GetByCategory("ar", registry))).to.equal("pwt_c")
                expect(ids(catalogue().GetByCategory("none", registry))).to.equal("")
            end
        },
        {
            name = "Catalogue: running the phase twice keeps the entry stable (listeners must tolerate repeats)",
            func = function()
                local registry = loadWeapons({ pwt_decl = { Name = "Declared name" } })
                local adapters = adapterList({ pwt_a = adapterTable(0, { info("pwt_decl", { category = "smg" }) }) })
                catalogue().Populate(registry, adapters)
                catalogue().Populate(registry, adapters)
                local entry = must(registry.Get("pwt_decl")) --[[@as PW.Weapon]]
                expect(entry.Name).to.equal("Declared name")
                expect(entry.Category).to.equal("smg")
                expect(#registry.GetList()).to.equal(1)
            end
        }
    }
}
