-- Weapon registration phase (T-1.17, 04-weapons.md d.3; 01-extensibility.md d.16 step 7). Shared. SWEPs load
-- after the gamemode, so in InitPostEntity of each realm the core fires PW_RegisterWeapons(reg), reg being the
-- weapons registry (reg.Register(tbl, class, { soft = true })), then PW_WeaponsLoaded; both are notifications
-- through PW.Notify. Consumers (loadout, bots, HUD) wait for PW_WeaponsLoaded.
-- Reload (01-extensibility.md d.12): every PW.Loader.Boot builds a new weapons registry holding only the declared
-- files, so after InitPostEntity each Boot (pw_reload, auto refresh) runs the phase again on the new registries,
-- after PW_RegistriesLoaded. Before InitPostEntity (the Boot at gamemode load) nothing runs.

local phase = (rawget(PW, "WeaponPhase") or {}) --[[@as PW.WeaponPhaseLib]]
PW.WeaponPhase = phase

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

function phase._NewStore(opts)
    opts = opts or {}
    return { log = opts.log or defaultLog, ready = false, runs = 0 }
end

PW._WeaponPhase = PW._WeaponPhase or phase._NewStore()

function phase._Run(store, registries, reason)
    local realm = SERVER and "server" or "client"
    local registry = registries.weapons
    if registry == nil then
        store.log(string.format("weapon phase (%s, %s) skipped: no weapons kind is declared", realm, reason))
        return false
    end
    ---@type PW.WeaponPhaseRun
    local run = { reason = reason, sweps = #weapons.GetList() }
    store.runs = store.runs + 1
    store.first = store.first or run
    store.last = run
    local ok, err = pcall(PW.Notify, "PW_RegisterWeapons", registry)
    if not ok then
        store.log(string.format("weapon phase (%s, %s): a PW_RegisterWeapons listener failed: %s", realm, reason,
            tostring(err)))
    end
    PW.Notify("PW_WeaponsLoaded")
    return true
end

function phase._OnInitPostEntity()
    local store = PW._WeaponPhase
    store.ready = true
    phase._Run(store, PW.Registries or {}, "InitPostEntity")
end

function phase._OnBoot()
    local store = PW._WeaponPhase
    if store.ready then phase._Run(store, PW.Registries or {}, "reload") end
end

hook.Add("InitPostEntity", "PW.WeaponPhase", function() phase._OnInitPostEntity() end)
