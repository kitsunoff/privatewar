-- T-3.6 ARC9 integration addon (TASKS.md, "Mandatory test cases" T-3.6 to T-3.8; 04-weapons.md d.2, d.4, d.6;
-- notes/08 sections 2 and 6.2). Pure cases check the helpers of the module arc9 on plain data and run without ARC9.
-- In-game cases need ARC9 and at least one ARC9 weapon pack: without ARC9 they are skipped with one log line, never
-- passed silently. Two bots live for the whole group (beforeAll creates them, afterAll kicks them).

---Fails the case when a value is nil; returns it narrowed for the type checker.
---@generic T
---@param value T?
---@return T
local function must(value)
    assert(value ~= nil, "expected a value, got nil")
    return value
end

---@return PW.Arc9Lib
local function lib()
    return must(rawget(PW, "Arc9") --[[@as PW.Arc9Lib?]])
end

---Fake ConVars for one realm of the perf profile: every ConVar of the realm at value; returns the table and a copy.
---@param realm PW.Arc9PerfRealm
---@param value string
---@return table<string, string> current
---@return table<string, string> original
local function perfConVars(realm, value)
    ---@type table<string, string>
    local current = {}
    ---@type table<string, string>
    local original = {}
    local values = lib().PerfConVars[realm] --[[@as PW.Arc9ConVarValues]]
    for name in pairs(values) do
        current[name], original[name] = value, value
    end
    return current, original
end

---@param current table<string, string>
---@param onSet? fun()
---@return PW.Arc9ConVarIO
local function perfIO(current, onSet)
    return {
        get = function(name) return current[name] end,
        set = function(name, value)
            if onSet ~= nil then onSet() end
            current[name] = value
        end
    }
end

---A backup store in memory for the perf profile; box.data is what the file would hold, nil when there is none.
---@return PW.Arc9PerfBackup backup
---@return { data: table<string, string>?, writes: integer } box
local function perfBackup()
    ---@type { data: table<string, string>?, writes: integer }
    local box = { data = nil, writes = 0 }
    ---@type PW.Arc9PerfBackup
    local backup = {
        read = function() return box.data ~= nil and table.Copy(box.data) or nil end,
        write = function(values)
            box.writes = box.writes + 1
            box.data = table.Copy(values)
        end,
        remove = function() box.data = nil end
    }
    return backup, box
end

local skipLogged = false
local unmountedLogged = false

---Skip rule of the helper cases: the addon privatewar-arc9 must be mounted (GMod mounts a new addon folder only
---at game start). Logs the reason once.
---@return boolean
local function noAddon()
    if rawget(PW, "Arc9") ~= nil then return false end
    if not unmountedLogged then
        unmountedLogged = true
        print("[PW] ARC9 helper cases SKIPPED: PW.Arc9 is missing, the addon privatewar-arc9 is not mounted " ..
            "(a newly deployed addon folder loads after the next game start)")
    end
    return true
end

---Skip rule of the in-game cases: ARC9 must be installed. Logs the reason once.
---@return boolean
local function noArc9()
    if rawget(_G, "ARC9") ~= nil then return false end
    if not skipLogged then
        skipLogged = true
        ---@type string[]
        local seen = {}
        for _, addon in ipairs(engine.GetAddons() --[[@as table<string, any>[] ]]) do
            local title = tostring(addon.title)
            if string.find(string.lower(title), "arc9", 1, true) then
                local state = string.format(" (%s, mounted=%s)", tostring(addon.wsid), tostring(addon.mounted))
                seen[#seen + 1] = title .. state
            end
        end
        print("[PW] ARC9 integration cases SKIPPED: ARC9 is not installed (the global ARC9 is missing); " ..
            "Workshop items named ARC9: " .. (#seen > 0 and table.concat(seen, "; ") or "none"))
    end
    return true
end

---@return PW.Adapter
local function adapter()
    local registry = must(rawget(PW, "WeaponAdapters") --[[@as PW.Registry?]])
    local found = registry.Get("arc9") --[[@as PW.Adapter?]]
    assert(found ~= nil, "the arc9 adapter is not registered: is integrations/privatewar-arc9 deployed and mounted?")
    return found
end

---@param method string
---@param ... any
---@return any
local function call(method, ...)
    return PW.Adapters.Call(adapter(), method, ...)
end

---@return ARC9Lib
local function arc9()
    return must(rawget(_G, "ARC9") --[[@as ARC9Lib?]])
end

---A gun of the installed packs and a top slot with two options that fit it; optionally a second top slot whose
---categories reject the first option (a conflict).
---@class PWTestArc9Pick
---@field class string
---@field slot PW.SlotId
---@field options PW.OptionId[]
---@field other? PW.SlotId
---@field otherOption? PW.OptionId an option of other that fits it

---@param list PW.Option[]
---@return PW.OptionId[]
local function ids(list)
    ---@type PW.OptionId[]
    local result = {}
    for _, option in ipairs(list) do result[#result + 1] = option.id end
    return result
end

---@param class string
---@param slot PW.SlotId
---@return PW.OptionId[]
local function optionsOf(class, slot)
    return ids(call("GetOptions", class, slot) --[[@as PW.Option[] ]])
end

---A second slot of class whose options do not include option, and one option that fits it.
---@param class string
---@param slots PW.Slot[]
---@param slot PW.SlotId
---@param option PW.OptionId
---@return PW.SlotId?, PW.OptionId?
local function conflictFor(class, slots, slot, option)
    for _, other in ipairs(slots) do
        local otherOptions = optionsOf(class, other.id)
        local rejects = #otherOptions >= 1 and not table.HasValue(otherOptions, option)
        if other.id ~= slot and not other.cosmetic and rejects then
            return other.id, otherOptions[1]
        end
    end
    return nil, nil
end

---@param class string
---@param needConflict boolean
---@return PWTestArc9Pick?
local function pickIn(class, needConflict)
    local slots = call("GetSlots", class, nil) --[[@as PW.Slot[] ]]
    for _, slot in ipairs(slots) do
        local options = optionsOf(class, slot.id)
        local usable = not slot.cosmetic and #options >= 2
        local other, otherOption = nil, nil
        if usable and needConflict then other, otherOption = conflictFor(class, slots, slot.id, options[1]) end
        if usable and (not needConflict or other ~= nil) then
            return { class = class, slot = slot.id, options = options, other = other, otherOption = otherOption }
        end
    end
    return nil
end

---@param needConflict boolean
---@return PWTestArc9Pick
local function pick(needConflict)
    for _, info in ipairs(call("ListWeapons") --[[@as PW.WeaponInfo[] ]]) do
        if info.kind == "gun" then
            local found = pickIn(info.class, needConflict)
            if found ~= nil then return found end
        end
    end
    error("no ARC9 gun of the installed packs has a slot with two options" ..
        (needConflict and " and a second slot that rejects one of them" or ""))
end

---@param state table<string, any>
---@param key "a"|"b"
---@return Player
local function bot(state, key)
    local pool = state.pool --[[@as table<string, Player>]]
    local found = pool[key]
    if found == nil or not IsValid(found) then
        found = player.CreateNextBot("PW arc9 test " .. key)
        assert(IsValid(found), "could not create a bot: needs a listen server with free slots")
        pool[key] = found
    end
    if not found:Alive() then found:Spawn() end
    return found
end

---Gives class to ply through the ammo module (the loadout path); a held copy is stripped first.
---@param ply Player
---@param class string
---@return PW.Arc9Weapon
local function give(ply, class)
    if ply:HasWeapon(class) then ply:StripWeapon(class) end
    local wep = PW.WeaponAmmo.Give(ply, class, { magazines = 1 })
    assert(IsValid(wep), "could not give " .. class .. " to " .. ply:Nick())
    return wep --[[@as PW.Arc9Weapon]]
end

---@param wep PW.Arc9Weapon
---@param slot PW.SlotId
---@return string|false
local function installed(wep, slot)
    local read = lib()._ReadBuild(wep.Attachments, { [slot] = false })
    return read[slot] or false
end

---An ARC9 rifle of the installed packs whose bash is on (SWEP.Bash).
---@return string
local function bashRifle()
    for _, info in ipairs(call("ListWeapons") --[[@as PW.WeaponInfo[] ]]) do
        local swep = info.kind == "gun" and info.category == "ar" and weapons.Get(info.class) or nil
        if swep ~= nil and swep.Bash == true then return info.class end
    end
    error("no ARC9 rifle of the installed packs has its bash on")
end

---Whether a second player fits 48 units from a standing spot along yaw. Players do not count as obstacles.
---@param from Vector
---@param yaw number
---@return Vector? spot, string why
local function roomAt(from, yaw)
    local spot = from + Angle(0, yaw, 0):Forward() * 48
    local hull = { mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 64), filter = player.GetAll(),
        mask = MASK_PLAYERSOLID, start = from + Vector(0, 0, 8), endpos = spot + Vector(0, 0, 8) }
    local tr = util.TraceHull(hull)
    if tr.Hit then return nil, "blocked by " .. tostring(tr.Entity) end
    return spot, ""
end

---Puts ply on a standing spot (where it is, else a player spawn point) with room for a target 48 units along its
---current aim; returns the target's spot. The aim is the bot's own: its CUserCmd decides it, not this test.
---@param ply Player
---@return Vector
local function roomAhead(ply)
    local yaw = ply:EyeAngles().y
    ---@type Vector[]
    local spots = { ply:GetPos() }
    for _, class in ipairs({ "info_player_start", "info_player_deathmatch", "info_player_combine",
        "info_player_rebel" }) do
        for _, ent in ipairs(ents.FindByClass(class)) do spots[#spots + 1] = ent:GetPos() end
    end
    ---@type string[]
    local tried = {}
    for _, from in ipairs(spots) do
        local spot, why = roomAt(from, yaw)
        if spot ~= nil then
            ply:SetPos(from)
            return spot
        end
        if #tried < 3 then tried[#tried + 1] = tostring(from) .. ": " .. why end
    end
    error("no room for a target at close range on " .. game.GetMap() .. " (" .. table.concat(tried, "; ") .. ")")
end

local known = { ar = true, smg = true, sniper = true, shotgun = true, pistol = true, lmg = true, special = true }

return {
    groupName = "PW ARC9 integration",
    beforeAll = function(state)
        state.pool = {}
    end,
    afterAll = function(state)
        hook.Remove("EntityTakeDamage", "PW test arc9 bash")
        for _, ply in pairs(state.pool --[[@as table<string, Player>]]) do
            PW.BotInput.SetScripted(ply, nil)
            if IsValid(ply) then ply:Kick("PW arc9 test finished") end
        end
    end,
    cases = {
        {
            name = "Helpers: slot ids are address paths, parents ordered before children",
            skip = noAddon,
            func = function()
                expect(lib()._ParseAddress("3")[1]).to.equal(3)
                local nested = must(lib()._ParseAddress("3.12"))
                expect(#nested).to.equal(2)
                expect(nested[2]).to.equal(12)
                expect(lib()._ParseAddress("0")).to.beNil()
                expect(lib()._ParseAddress("a.1")).to.beNil()
                expect(lib()._ParseAddress(3)).to.beNil()
                local order = lib()._Order({ ["2.1"] = "x", ["10"] = false, ["2"] = "y", ["1"] = "z" })
                expect(table.concat(order, " ")).to.equal("1 2 10 2.1")
            end
        },
        {
            name = "Helpers: a build changes the tree copy; a changed slot drops its sub-slots, gaps are filled",
            skip = noAddon,
            func = function()
                local tree = {
                    { Installed = "optic_a", SubAttachments = { { Installed = "mount_a" } } },
                    { Installed = "grip_a" }
                }
                local subs = { optic_b = 2, optic_a = 1 }
                local result = lib()._WithBuild(tree, { ["1"] = "optic_b", ["1.2"] = "mount_b", ["2"] = false },
                    function(att) return subs[att] or 0 end)
                expect(tree[1].Installed).to.equal("optic_a")
                expect(result[1].Installed).to.equal("optic_b")
                local sub = must(result[1].SubAttachments)
                expect(#sub).to.equal(2)
                expect(sub[1].Installed).to.beNil()
                expect(sub[2].Installed).to.equal("mount_b")
                expect(result[2].Installed).to.beNil()
            end
        },
        {
            name = "Helpers: an unknown top slot or a sub-slot of an empty slot cannot stick",
            skip = noAddon,
            func = function()
                local tree = { { Installed = nil } }
                local result = lib()._WithBuild(tree, { ["5"] = "x", ["1.1"] = "y" }, function() return 1 end)
                expect(#result).to.equal(1)
                expect(result[1].SubAttachments).to.beNil()
                local read = lib()._ReadBuild({ { Installed = false } }, { ["5"] = "x", ["1.1"] = "y", ["1"] = "z" })
                expect(read["5"]).to.beFalse()
                expect(read["1.1"]).to.beFalse()
                expect(read["1"]).to.beFalse()
            end
        },
        {
            name = "Helpers: catalogue info from the ARC9 weapon type, throwables and melee to equipment",
            skip = noAddon,
            func = function()
                local rifle = lib()._InfoFrom({ ClassName = "arc9_x", PrintName = "X" }, 4)
                expect(rifle.category).to.equal("ar")
                expect(rifle.kind).to.equal("gun")
                expect(rifle.slot).to.equal(1)
                local pistol = lib()._InfoFrom({ ClassName = "arc9_p" }, 1)
                expect(pistol.slot).to.equal(2)
                expect(pistol.name).to.equal("arc9_p")
                local nade = lib()._InfoFrom({ ClassName = "arc9_n", Throwable = true }, 8)
                expect(nade.kind).to.equal("throwable")
                expect(nade.slot).to.equal(3)
                expect(nade.category).to.beNil()
                local knife = lib()._InfoFrom({ ClassName = "arc9_k", PrimaryBash = true }, 0)
                expect(knife.kind).to.equal("melee")
                local rpg = lib()._InfoFrom({ ClassName = "arc9_r" }, 6)
                expect(rpg.kind).to.equal("launcher")
                expect(rpg.category).to.equal("special")
            end
        },
        {
            name = "Helpers: a bot bash is refused without bash, while busy, before the cooldown and out of reach",
            skip = noAddon,
            func = function()
                local refusal = lib()._BashRefusal
                ---@param changes table<string, any>
                ---@return PW.Arc9BashState
                local function state(changes)
                    ---@type PW.Arc9BashState
                    local s = { bash = true, safe = false, inSights = false, grenadePrimed = false, bipod = false,
                        swinging = false, reloading = false, cancelsReload = false, busy = false, sprintLock = false,
                        lastMelee = 0, preTime = 0.5, postTime = 0.5, speed = 1, now = 10, reach = true }
                    for key, value in pairs(changes) do (s --[[@as table<string, any>]])[key] = value end
                    return s
                end
                expect(refusal(state({}))).to.beNil()
                expect(refusal(state({ bash = false }))).to.equal("no_bash")
                expect(refusal(state({ bash = false, reach = false }))).to.equal("no_bash")
                expect(refusal(state({ safe = true }))).to.equal("safe")
                expect(refusal(state({ inSights = true }))).to.equal("sights")
                expect(refusal(state({ grenadePrimed = true }))).to.equal("grenade")
                expect(refusal(state({ bipod = true }))).to.equal("bipod")
                expect(refusal(state({ swinging = true }))).to.equal("swinging")
                expect(refusal(state({ reloading = true }))).to.equal("reloading")
                expect(refusal(state({ reloading = true, cancelsReload = true }))).to.beNil()
                expect(refusal(state({ busy = true }))).to.equal("busy")
                expect(refusal(state({ sprintLock = true }))).to.equal("sprint")
                expect(refusal(state({ reach = false }))).to.equal("out_of_reach")
                -- ARC9's own wait: the swing (pre time / speed) plus the recovery (post time, not scaled).
                expect(refusal(state({ lastMelee = 9.2 }))).to.equal("cooldown")
                expect(refusal(state({ lastMelee = 9 }))).to.beNil()
                expect(refusal(state({ lastMelee = 9.3, speed = 2 }))).to.equal("cooldown")
                expect(refusal(state({ lastMelee = 9.25, speed = 2 }))).to.beNil()
            end
        },
        {
            name = "Helpers: slots of a class and the sub-slots a build opens",
            skip = noAddon,
            func = function()
                local atts = { optic_a = { Attachments = { { Category = "mount" } } } }
                local top = {
                    { Category = "optic", PrintName = "Optic", Installed = "optic_a" }, { Category = "camo" }
                }
                local found = lib()._FindSlots(top, { ["1"] = "optic_a" }, function(name) return atts[name] end)
                -- Depth first: a sub-slot follows its parent.
                expect(#found).to.equal(3)
                expect(found[2].id).to.equal("1.1")
                expect(found[2].parent).to.equal("1")
                expect(found[3].id).to.equal("2")
                expect(#lib()._FindSlots(top, nil, function(name) return atts[name] end)).to.equal(2)
                expect(lib()._IsCosmetic(top[2], { camo = true })).to.beTrue()
                expect(lib()._Fits({ Category = { "optic", "x" } }, top[1])).to.beTrue()
                expect(lib()._Fits({ Category = "grip" }, top[1])).to.beFalse()
                expect(lib()._Fits({ Category = "*" }, top[1])).to.beTrue()
            end
        },
        {
            name = "Helpers: session ConVars are set once, the replaced values restored, missing ones skipped",
            skip = noAddon,
            func = function()
                local values = { a = "1", b = "0", missing = "1" }
                local current = { a = "0", b = "1" }
                local sets = 0
                local access = {
                    get = function(name) return current[name] end,
                    set = function(name, value)
                        sets = sets + 1
                        current[name] = value
                    end
                }
                ---@type PW.Arc9ConVarSwap
                local swap = { on = false, saved = {} }
                lib()._SwapConVars(swap, values, true, access)
                expect(current.a).to.equal("1")
                expect(current.b).to.equal("0")
                expect(current.missing).to.beNil()
                expect(sets).to.equal(2)
                lib()._SwapConVars(swap, values, true, access)
                expect(sets).to.equal(2)
                lib()._SwapConVars(swap, values, false, access)
                expect(current.a).to.equal("0")
                expect(current.b).to.equal("1")
                expect(swap.on).to.beFalse()
                expect(next(swap.saved)).to.beNil()
            end
        },
        {
            name = "Helpers: the memo computes a key once per revision and starts over when the revision changes",
            skip = noAddon,
            func = function()
                ---@type PW.Arc9Memo
                local memo = { revision = nil, values = {} }
                local runs = 0
                local function compute()
                    runs = runs + 1
                    return { runs }
                end
                local first = lib()._Memo(memo, "r1", "a", compute)
                expect(lib()._Memo(memo, "r1", "a", compute)).to.equal(first)
                expect(runs).to.equal(1)
                lib()._Memo(memo, "r1", "b", compute)
                expect(runs).to.equal(2)
                local after = lib()._Memo(memo, "r2", "a", compute)
                expect(runs).to.equal(3)
                expect(after).toNot.equal(first)
                expect(memo.values.b).to.beNil()
            end
        },
        {
            name = "Cache: repeated GetSlots and GetOptions neither copy the SWEP table nor rescan the attachments",
            skip = noArc9,
            func = function()
                local chosen = pick(false)
                local first = call("GetOptions", chosen.class, chosen.slot) --[[@as PW.Option[] ]]
                local slots = call("GetSlots", chosen.class, nil) --[[@as PW.Slot[] ]]
                local copies, scans = 0, 0
                local realGet, realScan = weapons.Get, arc9().GetAttsForCats
                stub(weapons, "Get").with(function(...)
                    copies = copies + 1
                    return realGet(...)
                end)
                stub(arc9(), "GetAttsForCats").with(function(...)
                    scans = scans + 1
                    return realScan(...)
                end)
                local again = call("GetOptions", chosen.class, chosen.slot) --[[@as PW.Option[] ]]
                local slotsAgain = call("GetSlots", chosen.class, nil) --[[@as PW.Slot[] ]]
                expect(copies).to.equal(0)
                expect(scans).to.equal(0)
                expect(table.concat(ids(again), " ")).to.equal(table.concat(ids(first), " "))
                expect(#slotsAgain).to.equal(#slots)
                -- A caller that changes its list does not change the cached one.
                again[1] = nil
                expect(#(call("GetOptions", chosen.class, chosen.slot) --[[@as PW.Option[] ]])).to.equal(#first)
            end
        },
        {
            name = "HUD: ARC9's own HUD and hints are off while the gamemode runs; the crosshair stays",
            skip = noArc9,
            func = function()
                expect(GetConVar("arc9_hud_force_disable"):GetBool()).to.beTrue()
                expect(PW._Arc9.hud.on).to.beTrue()
                expect(lib().ClientHudConVars.arc9_hud_hints).to.equal("0")
                -- 09-hud.md d.1: the crosshair stays the weapon base's own.
                expect(lib().HudConVars.arc9_cross_enable).to.beNil()
                expect(lib().ClientHudConVars.arc9_cross_enable).to.beNil()
            end
        },
        {
            name = "Precache: ARC9's startup precache of weapon and attachment models is on and stays on",
            skip = noArc9,
            func = function()
                expect(lib().PrecacheConVars.arc9_precache_wepmodels_onstartup).to.equal("1")
                expect(lib().PrecacheConVars.arc9_precache_attsmodels_onstartup).to.equal("1")
                expect(GetConVar("arc9_precache_wepmodels_onstartup"):GetBool()).to.beTrue()
                expect(GetConVar("arc9_precache_attsmodels_onstartup"):GetBool()).to.beTrue()
                -- Not a session swap: ShutDown restores the lock and the HUD only.
                expect(PW._Arc9.lock.saved.arc9_precache_wepmodels_onstartup).to.beNil()
                expect(PW._Arc9.hud.saved.arc9_precache_wepmodels_onstartup).to.beNil()
            end
        },
        {
            name = "Perf: deck sets the values of its realm and backs up the originals; off restores, drops the backup",
            skip = noAddon,
            func = function()
                for realm, values in pairs(lib().PerfConVars) do
                    local current, original = perfConVars(realm, "5")
                    local backup, box = perfBackup()
                    ---@type PW.Arc9ConVarSwap
                    local swap = { on = false, saved = {} }
                    lib()._ApplyPerf(swap, "deck", realm, perfIO(current), backup)
                    expect(next(values)).toNot.beNil()
                    for name, value in pairs(values) do expect(current[name]).to.equal(value) end
                    expect(box.data).to.deepEqual(original)
                    expect(box.writes).to.equal(1)
                    -- Applying twice keeps the originals: neither the swap nor the backup gets the profile values.
                    lib()._ApplyPerf(swap, "deck", realm, perfIO(current), backup)
                    expect(box.writes).to.equal(1)
                    expect(swap.saved).to.deepEqual(original)
                    expect(box.data).to.deepEqual(original)
                    lib()._ApplyPerf(swap, "off", realm, perfIO(current), backup)
                    for name, value in pairs(original) do expect(current[name]).to.equal(value) end
                    expect(next(swap.saved)).to.beNil()
                    expect(box.data).to.beNil()
                end
                local client, server = lib().PerfConVars.client, lib().PerfConVars.server
                expect(lib()._PerfValues("deck", "client")).to.deepEqual({
                    arc9_tpik_others = "0", arc9_lod_distance = "0.4", arc9_cheapscopes = "1", arc9_fx_rtvm = "0",
                    arc9_muzzle_others = "0", arc9_eject_fx = "0"
                })
                expect(lib()._PerfValues("deck", "server")).to.deepEqual({
                    arc9_bullet_physics = "0", arc9_ricochet = "0"
                })
                expect(lib()._PerfValues("off", "client")).to.deepEqual({})
                expect(lib()._PerfValues("off", "server")).to.deepEqual({})
                -- A copy: changing it does not change the profile.
                lib()._PerfValues("deck", "server").arc9_ricochet = "1"
                expect(server.arc9_ricochet).to.equal("0")
                -- The realm split: no ConVar is set by both realms; each realm has its own backup file.
                for name in pairs(client) do expect(server[name]).to.beNil() end
                expect(lib().PerfBackupPath("client")).toNot.equal(lib().PerfBackupPath("server"))
                expect(lib()._PerfAction("deck")).to.equal("apply")
                expect(lib()._PerfAction("off")).to.equal("restore")
                expect(lib()._PerfAction("default")).to.equal("none")
                expect(lib()._PerfAction("bogus")).to.equal("none")
            end
        },
        {
            name = "Perf: a missing ConVar (ARC9 not installed or an older ARC9) is skipped without error",
            skip = noAddon,
            func = function()
                for realm, values in pairs(lib().PerfConVars) do
                    local current, original = perfConVars(realm, "5")
                    local missing = next(values) --[[@as string]]
                    current[missing], original[missing] = nil, nil
                    local backup, box = perfBackup()
                    ---@type PW.Arc9ConVarSwap
                    local swap = { on = false, saved = {} }
                    lib()._ApplyPerf(swap, "deck", realm, perfIO(current), backup)
                    expect(current[missing]).to.beNil()
                    expect(box.data).to.deepEqual(original)
                    lib()._RestorePerf(swap, realm, perfIO(current), backup)
                    expect(current[missing]).to.beNil()
                    for name, value in pairs(original) do expect(current[name]).to.equal(value) end
                    -- Nothing exists at all: nothing is set, the backup is empty.
                    ---@type table<string, string>
                    local none = {}
                    ---@type PW.Arc9ConVarSwap
                    local bare = { on = false, saved = {} }
                    lib()._ApplyPerf(bare, "deck", realm, perfIO(none), backup)
                    expect(next(none)).to.beNil()
                    expect(box.data).to.deepEqual({})
                end
            end
        },
        {
            name = "Perf: off leaves ARC9 alone after the restore; the player's later changes stay",
            skip = noAddon,
            func = function()
                for realm in pairs(lib().PerfConVars) do
                    local current = perfConVars(realm, "5")
                    local backup, box = perfBackup()
                    local sets = 0
                    local access = perfIO(current, function() sets = sets + 1 end)
                    ---@type PW.Arc9ConVarSwap
                    local swap = { on = false, saved = {} }
                    lib()._ApplyPerf(swap, "off", realm, access, backup)
                    expect(sets).to.equal(0)
                    expect(box.writes).to.equal(0)
                    lib()._ApplyPerf(swap, "deck", realm, access, backup)
                    lib()._ApplyPerf(swap, "off", realm, access, backup)
                    for name in pairs(current) do current[name] = "9" end
                    local afterRestore = sets
                    lib()._ApplyPerf(swap, "off", realm, access, backup)
                    expect(sets).to.equal(afterRestore)
                    for _, value in pairs(current) do expect(value).to.equal("9") end
                    expect(swap.on).to.beFalse()
                end
            end
        },
        {
            name = "Perf: ShutDown restores the originals and deletes the backup; precache is not restored",
            skip = noAddon,
            func = function()
                for realm in pairs(lib().PerfConVars) do
                    local current, original = perfConVars(realm, "7")
                    current.arc9_precache_wepmodels_onstartup = "1"
                    local backup, box = perfBackup()
                    ---@type PW.Arc9ConVarSwap
                    local swap = { on = false, saved = {} }
                    lib()._ApplyPerf(swap, "deck", realm, perfIO(current), backup)
                    lib()._RestorePerf(swap, realm, perfIO(current), backup)
                    for name, value in pairs(original) do expect(current[name]).to.equal(value) end
                    expect(swap.on).to.beFalse()
                    expect(box.data).to.beNil()
                    expect(current.arc9_precache_wepmodels_onstartup).to.equal("1")
                    -- A second ShutDown (map change after a restore) writes nothing.
                    local sets = 0
                    lib()._RestorePerf(swap, realm, perfIO(current, function() sets = sets + 1 end), backup)
                    expect(sets).to.equal(0)
                end
                for name in pairs(lib().PrecacheConVars) do
                    expect(lib().PerfConVars.server[name]).to.beNil()
                    expect(lib().PerfConVars.client[name]).to.beNil()
                end
            end
        },
        {
            name = "Perf: a backup left without ShutDown restores the originals first, then deck applies again",
            skip = noAddon,
            func = function()
                for realm, values in pairs(lib().PerfConVars) do
                    -- The crashed session left the deck values in ARC9's archived ConVars and the backup on disk.
                    ---@type table<string, string>
                    local current = {}
                    for name, value in pairs(values) do current[name] = value end
                    local _, original = perfConVars(realm, "3")
                    local backup, box = perfBackup()
                    local left = table.Copy(original) --[[@as table<string, string>]]
                    left.arc9_not_in_profile = "1"
                    box.data = left
                    ---@type PW.Arc9ConVarSwap
                    local swap = { on = false, saved = {} }
                    expect(lib()._RecoverPerf(swap, realm, perfIO(current), backup)).to.equal(table.Count(original))
                    for name, value in pairs(original) do expect(current[name]).to.equal(value) end
                    expect(current.arc9_not_in_profile).to.beNil()
                    expect(box.data).to.beNil()
                    lib()._ApplyPerf(swap, "deck", realm, perfIO(current), backup)
                    -- The new backup holds the real originals, not the deck values the crash left behind.
                    expect(box.data).to.deepEqual(original)
                    -- A reload while the profile is on (backup present, swap on) recovers nothing.
                    expect(lib()._RecoverPerf(swap, realm, perfIO(current), backup)).to.equal(0)
                    for name, value in pairs(values) do expect(current[name]).to.equal(value) end
                    -- No backup: nothing to recover.
                    ---@type PW.Arc9ConVarSwap
                    local fresh = { on = false, saved = {} }
                    local empty = perfBackup()
                    expect(lib()._RecoverPerf(fresh, realm, perfIO(current), empty)).to.equal(0)
                end
            end
        },
        {
            name = "Perf: arc9.perf is a host setting in the schema, deck by default, with a description",
            skip = noAddon,
            func = function()
                ---@type PW.SettingDef?
                local found = nil
                for _, group in ipairs(PW.Settings.GetGroups("server")) do
                    for _, field in ipairs(group.fields) do
                        if field.def.id == "arc9.perf" then found = field.def end
                    end
                end
                local def = must(found)
                expect(def.scope).to.equal("server")
                expect(def.type).to.equal("enum")
                expect(def.default).to.equal("deck")
                expect(table.concat(must(def.options), " ")).to.equal("deck off")
                expect(string.find(def.label, "ARC9", 1, true)).toNot.beNil()
                expect(string.find(must(def.description), "Steam Deck", 1, true)).toNot.beNil()
            end
        },
        {
            name = "Perf: the live server ConVars follow the profile, the backup file exists while deck is on",
            skip = noArc9,
            func = function()
                local active = PW.Setting("arc9.perf")
                local server = lib().PerfConVars.server
                local path = lib().PerfBackupPath("server")
                for name in pairs(server) do
                    local convar = must(GetConVar(name))
                    expect(convar:IsFlagSet(FCVAR_REPLICATED)).to.beTrue()
                end
                if active == "deck" then
                    expect(PW._Arc9.perf.on).to.beTrue()
                    expect(file.Exists(path, "DATA")).to.beTrue()
                    for name, value in pairs(server) do expect(GetConVar(name):GetString()).to.equal(value) end
                end
                lib().ApplyPerf("off")
                expect(PW._Arc9.perf.on).to.beFalse()
                expect(file.Exists(path, "DATA")).to.beFalse()
                ---@type table<string, string>
                local original = {}
                for name in pairs(server) do original[name] = GetConVar(name):GetString() end
                lib().ApplyPerf("deck")
                expect(file.Exists(path, "DATA")).to.beTrue()
                for name, value in pairs(server) do expect(GetConVar(name):GetString()).to.equal(value) end
                lib().RestorePerf()
                expect(file.Exists(path, "DATA")).to.beFalse()
                for name, value in pairs(original) do expect(GetConVar(name):GetString()).to.equal(value) end
                lib().ApplyPerf(active)
            end
        },
        {
            name = "Adapter: claims ARC9 classes above the fallback; absent ARC9 makes it unavailable",
            skip = noArc9,
            func = function()
                local a = adapter()
                expect((a.Priority or 0) > -100).to.beTrue()
                expect(a:IsAvailable()).to.beTrue()
                local first = must((call("ListWeapons") --[[@as PW.WeaponInfo[] ]])[1])
                expect(PW.Adapters.For(first.class)).to.equal(a)
                expect(a:Claims("weapon_smg1", nil)).to.beFalse()
            end
        },
        {
            name = "Catalogue: the pack's weapons are listed with categories and reach the weapons registry",
            skip = noArc9,
            func = function()
                local list = call("ListWeapons") --[[@as PW.WeaponInfo[] ]]
                assert(#list > 0, "ARC9 is installed but no ARC9 weapon pack is: the catalogue is empty")
                ---@type table<string, integer>
                local counts = {}
                for _, info in ipairs(list) do
                    expect(weapons.IsBasedOn(info.class, "arc9_base")).to.beTrue()
                    local key = info.category or "none"
                    counts[key] = (counts[key] or 0) + 1
                    if info.category ~= nil then expect(known[info.category]).to.beTrue() end
                end
                local categorized = #list - (counts.none or 0)
                expect(categorized > 0).to.beTrue()
                ---@type string[]
                local parts = {}
                local keys = table.GetKeys(counts) --[[@as string[] ]]
                table.sort(keys)
                for _, key in ipairs(keys) do parts[#parts + 1] = key .. "=" .. counts[key] end
                print(string.format("[PW] ARC9 catalogue: %d weapons (%s)", #list, table.concat(parts, " ")))
                for _, info in ipairs(list) do
                    local entry = PW.Weapons.Get(info.class) --[[@as PW.Weapon?]]
                    expect(entry ~= nil).to.beTrue()
                    if entry ~= nil and info.category ~= nil then expect(entry.Category).to.equal(info.category) end
                end
            end
        },
        {
            name = "Apply on a bot's weapon returns the applied build",
            skip = noArc9,
            func = function(state)
                local chosen = pick(false)
                local wep = give(bot(state, "a"), chosen.class)
                local option = chosen.options[1]
                local result = call("Apply", wep, { [chosen.slot] = option }) --[[@as PW.Build]]
                expect(result[chosen.slot]).to.equal(option)
                expect(installed(wep, chosen.slot)).to.equal(option)
                expect(adapter():IsValid()).to.beTrue()
            end
        },
        {
            name = "Apply with a conflicting build returns what stuck",
            skip = noArc9,
            func = function(state)
                local chosen = pick(true)
                local wep = give(bot(state, "a"), chosen.class)
                local wrong = chosen.options[1]
                local other = must(chosen.other)
                local build = { [chosen.slot] = chosen.options[2], [other] = wrong }
                local result = call("Apply", wep, build) --[[@as PW.Build]]
                expect(result[chosen.slot]).to.equal(chosen.options[2])
                expect(result[other]).toNot.equal(wrong)
                expect(result[other]).to.equal(installed(wep, other))
                expect(result["99"]).to.beNil()
            end
        },
        {
            name = "Customization lock: ARC9's own customization paths refuse",
            skip = noArc9,
            func = function(state)
                expect(GetConVar("arc9_atts_nocustomize"):GetBool()).to.beTrue()
                expect(GetConVar("arc9_free_atts"):GetBool()).to.beFalse()
                expect(GetConVar("arc9_atts_anarchy"):GetBool()).to.beFalse()
                local chosen = pick(false)
                local ply = bot(state, "a")
                local wep = give(ply, chosen.class)
                ply:SelectWeapon(chosen.class)
                local before = installed(wep, chosen.slot)
                local address = must(lib()._ParseAddress(chosen.slot))[1]
                local slot = wep.Attachments[address]
                expect(wep:CanAttach(address, chosen.options[2], slot)).to.beFalse()
                expect(wep:CanDetach(address)).to.beFalse()
                -- The receiver of arc9_networkweapon ends in ReceiveWeapon: it returns before reading anything.
                wep:ReceiveWeapon()
                expect(installed(wep, chosen.slot)).to.equal(before)
                -- The randomize receiver needs arc9_free_atts; nothing is queued.
                local receiver = must((net.Receivers --[[@as table<string, function?>]])["arc9_randomizeatts"])
                receiver(0, ply)
                expect(table.HasValue(arc9().RandomizeQueue, wep)).to.beFalse()
            end
        },
        {
            name = "Stat mods change the server-side reload time and removal restores it",
            skip = noArc9,
            async = true,
            timeout = 5,
            func = function(state)
                local chosen = pick(false)
                local ply = bot(state, "a")
                local wep = give(ply, chosen.class)
                local base = wep:GetProcessedValue("ReloadTime") --[[@as number]]
                PW.SetStatMods(ply, { reload_time = 0.5 })
                timer.Simple(0.3, function()
                    local faster = wep:GetProcessedValue("ReloadTime") --[[@as number]]
                    expect(math.abs(faster - base * 0.5) < 1e-6).to.beTrue()
                    expect(call("SupportedStatMods").reload_time).to.beTrue()
                    PW.SetStatMods(ply, {})
                    timer.Simple(0.3, function()
                        local restored = wep:GetProcessedValue("ReloadTime") --[[@as number]]
                        expect(math.abs(restored - base) < 1e-6).to.beTrue()
                        done()
                    end)
                end)
            end
        },
        {
            name = "Bash: a bot with an ARC9 rifle and no melee weapon bashes a target at close range",
            skip = noArc9,
            async = true,
            timeout = 12,
            func = function(state)
                local class = bashRifle()
                local a, b = bot(state, "a"), bot(state, "b")
                -- In the lobby a teamless player is an observer (not solid, cannot be hit): two teams, spawned.
                a:SetTeam(1)
                b:SetTeam(2)
                a:Spawn()
                b:Spawn()
                a:StripWeapons()
                local wep = give(a, class)
                call("PrepareForBot", a, wep)
                a:SelectWeapon(class)
                -- Both stand still: an intent without a view keeps the eye angles.
                PW.BotInput.SetScripted(a, { buttons = 0, weapon = class })
                PW.BotInput.SetScripted(b, { buttons = 0 })
                local hits = 0
                hook.Add("EntityTakeDamage", "PW test arc9 bash", function(target, dmg)
                    if target == b and dmg:GetInflictor() == wep then hits = hits + 1 end
                end)
                -- fight asks again until ARC9 lets the swing start (the draw animation locks the weapon first). The
                -- target stands 48 units along the attacker's aim, chest at eye height.
                local tries = 0
                local function try()
                    tries = tries + 1
                    -- A moved player's hitboxes follow on the next ticks: a fresh move waits for the next try.
                    local spot = roomAhead(a)
                    local placed = b:GetPos():Distance(spot) <= 4
                    if not placed then b:SetPos(spot) end
                    b:SetHealth(100)
                    local started = placed and a:GetActiveWeapon() == wep
                        and call("BotAction", a, wep, "melee", nil) == true
                    if not started and tries < 24 then
                        timer.Simple(0.25, try)
                        return
                    end
                    if not started then
                        local s = lib().BashState(a, wep)
                        print(string.format("[PW] ARC9 bash refused: %s; eye %s aim %s, target at %s, %s alive %s",
                            tostring(lib()._BashRefusal(s)), tostring(a:EyePos()), tostring(a:GetAimVector()),
                            tostring(b:GetPos()), tostring(a:GetActiveWeapon()), tostring(b:Alive())))
                    end
                    expect(started).to.beTrue()
                    expect(wep:GetInMeleeAttack()).to.beTrue()
                    timer.Simple(1.5, function()
                        hook.Remove("EntityTakeDamage", "PW test arc9 bash")
                        PW.BotInput.SetScripted(a, nil)
                        PW.BotInput.SetScripted(b, nil)
                        expect(wep:GetInMeleeAttack()).to.beFalse()
                        a:SetTeam(TEAM_UNASSIGNED)
                        b:SetTeam(TEAM_UNASSIGNED)
                        a:Spawn()
                        b:Spawn()
                        expect(hits).to.equal(1)
                        done()
                    end)
                end
                timer.Simple(0.25, try)
            end
        },
        {
            name = "Bash: BotAction melee on a weapon without bash returns false",
            skip = noArc9,
            func = function(state)
                local class = bashRifle()
                local a = bot(state, "a")
                local wep = give(a, class)
                a:SelectWeapon(class)
                -- The instance's own value is what ARC9's stat pipeline reads first; the cache must forget the class's.
                wep.Bash = false
                wep.PrimaryBash = false
                wep:DoInvalidateCache()
                expect(call("BotAction", a, wep, "melee", nil)).to.beFalse()
                expect(wep:GetInMeleeAttack()).to.beFalse()
                expect(call("BotAction", a, wep, "no_such_action", nil)).to.beFalse()
            end
        },
        {
            name = "PrepareForBot runs without errors; two bots keep different builds of the same class",
            skip = noArc9,
            async = true,
            timeout = 5,
            func = function(state)
                local chosen = pick(false)
                local a, b = bot(state, "a"), bot(state, "b")
                local wepA, wepB = give(a, chosen.class), give(b, chosen.class)
                call("PrepareForBot", a, wepA)
                call("PrepareForBot", b, wepB)
                expect(adapter():IsValid()).to.beTrue()
                local first, second = chosen.options[1], chosen.options[2]
                local resultA = call("Apply", wepA, { [chosen.slot] = first }) --[[@as PW.Build]]
                expect(resultA[chosen.slot]).to.equal(first)
                expect((call("Apply", wepB, { [chosen.slot] = second }) --[[@as PW.Build]])[chosen.slot])
                    .to.equal(second)
                expect(installed(wepA, chosen.slot)).to.equal(first)
                expect(installed(wepB, chosen.slot)).to.equal(second)
                local stored = weapons.GetStored(chosen.class) --[[@as table<string, any>]]
                local storedSlots = stored.Attachments --[[@as PW.Arc9SlotTable[]? ]]
                if storedSlots ~= nil then
                    local storedNow = installed({ Attachments = storedSlots } --[[@as any]], chosen.slot)
                    expect(storedNow ~= first or storedNow ~= second).to.beTrue()
                end
                timer.Simple(0.5, function()
                    expect(installed(wepA, chosen.slot)).to.equal(first)
                    expect(installed(wepB, chosen.slot)).to.equal(second)
                    done()
                end)
            end
        }
    }
}
