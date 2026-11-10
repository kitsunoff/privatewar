-- Gunsmith, server glue (T-4.8; 05-loadout.md d.15). Thin wrappers around the pure part (sh_gunsmith.lua):
--   save: the adapter's offered options (GetSlots with the build, GetOptions per slot) and its static Validate join the
--     class context, so every class repair checks the builds (sv_classes.lua builds the context);
--   spawn: after Give, ADAPTER:Apply on the first weapon of each slot with a build, then PrepareForBot for a bot;
--     a weapon whose adapter has no Apply (the HL2 fallback) is skipped with a debug line (pw_debug 1);
--   repair: options that did not stick are told to the player in one chat line and dropped from the picked class
--     ("not installed"); the class state is sent again, so the class list shows the removal.

local lib = PW.Loadout --[[@as PW.LoadoutLib]]

local debugVar = GetConVar("pw_debug")

---@param weaponOrClass any
---@return table?
local function adapterOf(weaponOrClass)
    local adapters = rawget(PW, "Adapters") --[[@as PW.AdaptersLib?]]
    if adapters == nil then return nil end
    return adapters.For(weaponOrClass) --[[@as table?]]
end

function lib._AdapterOptions(weaponId, build)
    ---@type table<string, table<string, boolean>>
    local offered = {}
    local adapter = adapterOf(weaponId)
    if adapter == nil then return offered end
    local slots = PW.Adapters.Call(adapter, "GetSlots", weaponId, build) --[[@as PW.Slot[]?]]
    local selectedOnly = next(build) ~= nil
    for _, slot in ipairs(istable(slots) and slots or {}) do
        -- Repair checks only addresses present in this build. Preserve the legacy empty-build discovery query.
        if not selectedOnly or build[slot.id] ~= nil then
            ---@type table<string, boolean>
            local set = {}
            local options = PW.Adapters.Call(adapter, "GetOptions", weaponId, slot.id) --[[@as PW.Option[]?]]
            for _, option in ipairs(istable(options) and options or {}) do set[option.id] = true end
            offered[slot.id] = set
        end
    end
    return offered
end

function lib._AdapterValidate(weaponId, build)
    local adapter = adapterOf(weaponId)
    if adapter == nil then return {} end
    ---@type any[]
    local results = { PW.Adapters.Call(adapter, "Validate", weaponId, build) }
    local rejected = results[2]
    return istable(rejected) and rejected --[[@as table<string, string>]] or {}
end

function lib._HasGunsmith(weaponOrClass)
    local adapter = adapterOf(weaponOrClass)
    return adapter ~= nil and isfunction(adapter.Apply)
end

function lib._GunsmithContext(ctx)
    ctx.adapterOptions = lib._AdapterOptions
    ctx.adapterValidate = lib._AdapterValidate
    return ctx
end

---@param wep any
---@return string
local function weaponName(wep)
    local name = PW.Adapters.CallFor(wep, "GetDisplayName", wep)
    return isstring(name) and name --[[@as string]] or wep:GetClass()
end

---@return PW.LoadoutGunsmithApi
local function liveApi()
    return {
        gunsmith = lib._HasGunsmith,
        apply = function(wep, build) return PW.Adapters.CallFor(wep, "Apply", wep, build) end,
        debug = function(message)
            if debugVar ~= nil and debugVar:GetBool() then print("[PW] " .. message) end
        end,
        tell = function(ply, message) ply:ChatPrint("[PW] " .. message) end,
        name = weaponName
    }
end

---Records what did not stick for the picked class and sends the repaired state. Only a class the player picked is
---repaired; a loadout from the mode or the default is told about but not changed.
---@param ply Player
---@param loadout PW.Loadout
---@param failures PW.GunsmithFailure[]
local function repairPick(ply, loadout, failures)
    local store = PW._LoadoutClasses
    local ref = store.picks[ply]
    if ref == nil or lib.GetClass(ply) ~= loadout then return end
    local perPlayer = store.notInstalled[ply] or {}
    store.notInstalled[ply] = perPlayer
    local drops = perPlayer[ref] or {}
    perPlayer[ref] = drops
    for _, failure in ipairs(failures) do
        local set = drops[failure.slot] or {}
        drops[failure.slot] = set
        for _, option in ipairs(failure.options) do set[option] = true end
    end
    lib.RefreshClasses(ply)
end

function lib._GunsmithOnGive(ply, loadout, weapons, api)
    local calls = api or liveApi()
    local failures = lib._ApplyBuilds(loadout, weapons, calls)
    if #failures > 0 then
        if calls.tell ~= nil and not ply:IsBot() then
            calls.tell(ply, lib._NotInstalledText(failures, calls.name or weaponName))
        end
        repairPick(ply, loadout, failures)
    end
    return failures
end

-- Once per Give for a bot-owned weapon (05 d.15 item 5; adapter.md "Bots").
function lib._PrepareForBot(ply, given)
    if not ply:IsBot() then return end
    for _, wep in ipairs(given) do PW.Adapters.CallFor(wep, "PrepareForBot", ply, wep) end
end
