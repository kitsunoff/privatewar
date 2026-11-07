-- Classes, server glue (T-4.7; 05-loadout.md d.12, d.13). Thin wrappers around the pure part (sh_classes*.lua):
--   pw_loadout_classes (client -> server, PW.Net.Receive: any player, 0.5 per s, ClassesMaxBytes): the player's
--     custom classes, sent on join. Kept as sent (at most loadout.classes of them) and repaired on every use.
--   pw_loadout_pick (client -> server, PW.Net.Receive: any player, 4 per s, 64 bytes): a class ref to use.
--   pw_loadout_class_state (server -> client): presets and custom classes, each repaired under the current match
--     settings with its availability and reason, and the ref in use. Sent after an upload, a pick and a phase
--     change (the match settings may have changed).
-- An available pick becomes the player's class (PW.Loadout.SetClass) and applies at the next spawn through
-- Resolve. When the settings make the picked class unavailable, the pick is kept (shown N/A) and the player gets
-- the default loadout for that match. Engine calls (net, settings) are store fields, so tests inject them.

---A file-local class: methods of the global MODULE defined in two files are reported as duplicates.
---@class PW.LoadoutModuleServer : PW.Module
local module = MODULE --[[@as PW.LoadoutModuleServer]]

local lib = PW.Loadout --[[@as PW.LoadoutLib]]

util.AddNetworkString("pw_loadout_class_state")

---@return integer
local function maxClasses()
    local value = PW.Setting("loadout.classes")
    return isnumber(value) and math.floor(value --[[@as number]]) or 10
end

---@param ply Player
---@param state PW.LoadoutClassState
local function sendState(ply, state)
    net.Start("pw_loadout_class_state")
    lib._EncodeClassState(state, lib._NetWriter())
    net.Send(ply)
end

function lib._NewClassStore(opts)
    opts = opts or {}
    return {
        uploads = setmetatable({}, { __mode = "k" }),
        picks = setmetatable({}, { __mode = "k" }),
        notInstalled = setmetatable({}, { __mode = "k" }),
        read = opts.read or function() return lib._DecodeClasses(lib._NetReader(), maxClasses()) end,
        readPick = opts.readPick or function() return net.ReadString() end,
        send = opts.send or sendState,
        -- T-4.8: the live context also carries the adapter's save-time checks (sv_gunsmith.lua).
        context = opts.context or function() return lib._GunsmithContext(lib._LiveContext(lib._RegistryLookup)) end
    }
end

do -- a reload keeps the uploads and picks, the functions are new
    local previous = rawget(PW, "_LoadoutClasses") --[[@as PW.LoadoutClassStore?]]
    local store = lib._NewClassStore()
    if previous ~= nil then
        store.uploads, store.picks = previous.uploads, previous.picks
        store.notInstalled = previous.notInstalled or store.notInstalled
    end
    PW._LoadoutClasses = store
end

---@return PW.ClassPreset[]
local function presets()
    local registry = rawget(PW, "Classes") --[[@as PW.Registry?]]
    if registry == nil then return {} end
    return registry.GetEnabledList() --[[@as PW.ClassPreset[] ]]
end

---@param ply Player
---@param ref string
---@param raw PW.Loadout
---@param ctx PW.LoadoutContext
---@return PW.LoadoutClassStatus
local function statusOf(ply, ref, raw, ctx)
    local slots = PW._Loadout.slots
    -- T-4.8: options that did not stick on the live weapon are dropped from this class first.
    local drops = (PW._LoadoutClasses.notInstalled[ply] or {})[ref]
    local loadout, notInstalled = lib._DropOptions(raw, drops, "not installed")
    local status = lib._ClassStatus(slots, loadout, ctx, function(value)
        local ok, err = lib._Validate(slots, value, ctx.lookup, ctx)
        if not ok then return false, err end
        return lib._AskValidate(ply, value)
    end)
    for _, line in ipairs(status.removed) do notInstalled[#notInstalled + 1] = line end
    status.removed = notInstalled
    return status
end

---@param ref string
---@param name string
---@param status PW.LoadoutClassStatus
---@return PW.LoadoutClassEntry
local function entryOf(ref, name, status)
    return {
        ref = ref, name = name, loadout = status.loadout, removed = status.removed,
        available = status.available, reason = status.reason
    }
end

---The context of one player: the match rules plus the unlock checks of the progression module, when it exists.
---@param ply Player
---@return PW.LoadoutContext
local function contextFor(ply)
    local ctx = PW._LoadoutClasses.context()
    local progression = rawget(PW, "Progression") --[[@as PW.ProgressionLib?]]
    if progression == nil or progression.IsUnlocked == nil then return ctx end
    ctx.isUnlocked = function(kind, id) return progression.IsUnlocked(ply, kind, id) end
    ctx.lockedOptions = function(weaponId, build) return progression.LockedOptions(ply, weaponId, build) end
    -- T-4.8: the progression count limit is the weapon level; the match cap (with wildcards) is checked apart.
    ctx.attachmentLimit = function(weaponId)
        if PW.Setting("progression.unlockall") == true or lib._RegistryLookup("weapons", weaponId) == nil then
            return nil
        end
        return progression.GetWeaponLevel(ply, weaponId)
    end
    return ctx
end

function lib.ClassState(ply)
    local store = PW._LoadoutClasses
    local ctx = contextFor(ply)
    ---@type PW.LoadoutClassEntry[]
    local entries = {}
    for _, preset in ipairs(presets()) do
        entries[#entries + 1] = entryOf("preset:" .. preset.ClassName, preset.Name,
            statusOf(ply, "preset:" .. preset.ClassName, preset.Loadout, ctx))
    end
    for index, class in ipairs(store.uploads[ply] or {}) do
        local ref = "custom:" .. index
        entries[#entries + 1] = entryOf(ref, class.name, statusOf(ply, ref, class.loadout, ctx))
    end
    return { selected = store.picks[ply] or "", entries = entries }
end

---@param state PW.LoadoutClassState
---@param ref string
---@return PW.LoadoutClassEntry?
local function findEntry(state, ref)
    for _, entry in ipairs(state.entries) do
        if entry.ref == ref then return entry end
    end
    return nil
end

function lib.RefreshClasses(ply)
    local store = PW._LoadoutClasses
    local state = lib.ClassState(ply)
    if store.picks[ply] ~= nil then
        local entry = findEntry(state, state.selected)
        lib.SetClass(ply, entry ~= nil and entry.available and entry.loadout or nil)
    end
    store.send(ply, state)
    return state
end

function lib._OnClasses(ply, classes)
    ---@type PW.LoadoutClass[]
    local kept = {}
    for index = 1, math.min(#classes, maxClasses()) do kept[index] = classes[index] end
    PW._LoadoutClasses.uploads[ply] = kept
    -- A new upload is a new set of builds: what did not stick before is tried again at the next spawn.
    PW._LoadoutClasses.notInstalled[ply] = nil
    return lib.RefreshClasses(ply)
end

function lib._OnPick(ply, ref)
    local store = PW._LoadoutClasses
    local state = lib.ClassState(ply)
    local entry = lib._ParseRef(ref) ~= nil and findEntry(state, ref) or nil
    local taken = entry ~= nil and entry.available
    if taken then
        store.picks[ply] = ref
        state.selected = ref
        lib.SetClass(ply, (entry --[[@as PW.LoadoutClassEntry]]).loadout)
    end
    store.send(ply, state)
    return taken
end

function lib._RegisterClassNet(owner)
    PW.Net.Receive("pw_loadout_classes", { who = "any", rate = 0.5, maxLen = lib.ClassesMaxBytes, owner = owner },
        function(ply) lib._OnClasses(ply, PW._LoadoutClasses.read()) end)
    PW.Net.Receive("pw_loadout_pick", { who = "any", rate = 4, maxLen = 64, owner = owner },
        function(ply) lib._OnPick(ply, PW._LoadoutClasses.readPick()) end)
end

lib._RegisterClassNet(module)

---The match settings may change with the phase (the snapshot is taken on entering PREMATCH, dropped in LOBBY):
---every player who uploaded gets the state again, one frame later, after the snapshot.
function module:PW_PhaseChange()
    timer.Simple(0, function()
        if not IsValid(module) then return end
        for ply in pairs(PW._LoadoutClasses.uploads) do
            if IsValid(ply) then lib.RefreshClasses(ply) end
        end
    end)
end
