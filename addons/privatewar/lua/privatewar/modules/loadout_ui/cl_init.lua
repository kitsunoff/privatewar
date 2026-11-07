-- LOADOUT tab editors, client glue (T-7.4; 05-loadout.md d.12). Thin wrappers around the pure part:
--   classes.json: read with the loadout module's own reader (PW.Loadout._ClassesFromJson), written in the same shape;
--   uploads: the loadout module's PW.Loadout.UploadClasses (the whole list, pw_loadout_classes), spaced 2.1 s apart;
--   the draft: the class being edited, shared by the editor and the gunsmith screens;
--   live inputs: the registries, the client-side progression checks, the adapter's slots and options, and the
--     lobby's match settings (the host's pending values) for the budget, the cap and the bans.
-- The server's answer is the class state it sends after every upload (pw_loadout_class_state); the open screen
-- redraws through its PWRefresh.

local lib = PW.LoadoutUI --[[@as PW.LoadoutUILib]]

include("privatewar/modules/loadout_ui/cl_widgets.lua")

local filePath = "privatewar/classes.json"
local uploadGap, uploadTimer = 2.1, "PW.LoadoutUIUpload"
-- Read every class in the file, so a rewrite never drops classes past the server's limit.
local readLimit = 99

---@class PW.LoadoutUIClientStore
---@field last? number SysTime of the last upload
---@field after? fun()[] callbacks to run once the pending upload is sent

---@type PW.LoadoutUIClientStore
local store = rawget(lib, "_ClientStore") or {}
rawset(lib, "_ClientStore", store)

---@return PW.LoadoutLib
local function loadout()
    return PW.Loadout --[[@as PW.LoadoutLib]]
end

function lib.MaxClasses()
    local value = PW.Setting("loadout.classes")
    return isnumber(value) and math.floor(value --[[@as number]]) or 10
end

function lib.ReadClasses()
    local data = util.JSONToTable(file.Read(filePath, "DATA") or "") or {}
    return loadout()._ClassesFromJson(data, readLimit)
end

---@param data table<string, any>
local function writeFile(data)
    file.CreateDir("privatewar")
    file.Write(filePath, util.TableToJSON(data, true))
end

local function sendNow()
    store.last = SysTime()
    if loadout().UploadClasses ~= nil then loadout().UploadClasses() end
    local after = store.after or {}
    store.after = nil
    for _, callback in ipairs(after) do callback() end
end

---Uploads the classes now, or when the server's rate limit allows; then runs after (in order).
---@param after? fun()
local function upload(after)
    if after ~= nil then
        store.after = store.after or {}
        store.after[#store.after + 1] = after
    end
    local delay = lib.UploadDelay(SysTime(), store.last, uploadGap)
    if delay <= 0 then return sendNow() end
    timer.Create(uploadTimer, delay, 1, sendNow)
end

function lib.WriteClasses(classes)
    writeFile(lib.ToFile(classes))
    upload()
end

-- Live inputs ----------------------------------------------------------------------------------------------------

---@param groups PW.SettingGroup[]
---@param id string
---@return boolean found, any value
local function fieldValue(groups, id)
    for _, group in ipairs(groups) do
        for _, field in ipairs(group.fields) do
            if field.def.id == id then return true, field.value end
        end
    end
    return false, nil
end

---A match setting as the lobby shows it (the host's pending value for the selected mode), else PW.Setting.
---@param id string
---@return any
local function setting(id)
    local lobby = rawget(PW, "Lobby") --[[@as PW.LobbyLib?]]
    local view = (lobby ~= nil and rawget(lobby, "_View") or nil) --[[@as PW.LobbyClientView?]]
    local state = view ~= nil and view.state or nil
    local inLobby = PW.Phase ~= nil and PW.Phase.GetPhase() == "LOBBY"
    if view == nil or state == nil or not inLobby then return PW.Setting(id) end
    local wanted = view.selection ~= nil and view.selection.mode or nil
    for _, mode in ipairs(state.modes) do
        local found, value = false, nil
        if wanted == nil or mode.id == wanted then found, value = fieldValue(mode.groups, id) end
        if found then return value end
    end
    return PW.Setting(id)
end

function lib.LiveInput(value)
    local lib_ = loadout()
    local ctx = lib_._LiveContext(lib_._RegistryLookup)
    local rules = lib_._Context(setting, lib_._RegistryLookup)
    ctx.budget, ctx.maxattachments = rules.budget, rules.maxattachments
    ctx.bannedWeapons, ctx.bannedAttachments = rules.bannedWeapons, rules.bannedAttachments
    local progression = rawget(PW, "Progression") --[[@as PW.ProgressionLib?]]
    if progression ~= nil and progression.IsUnlocked ~= nil then
        ctx.isUnlocked = function(kind, id) return progression.IsUnlocked(LocalPlayer(), kind, id) end
    end
    return {
        declared = PW._Loadout.slots, order = PW._Loadout.order, loadout = value, ctx = ctx,
        list = function(kind)
            local registries = rawget(PW, "Registries") --[[@as table<string, PW.Registry>?]]
            local registry = registries ~= nil and registries[kind] or nil
            return registry ~= nil and registry.GetEnabledList() or {}
        end
    }
end

---@param text string
---@return string
local function phrase(text)
    if string.sub(text, 1, 1) == "#" then return language.GetPhrase(string.sub(text, 2)) end
    return text
end

---The weapon level and unlockall of the local player (nothing locked without the progression module).
---@param weaponId string
---@return integer level, boolean unlockAll
local function weaponProgress(weaponId)
    local progression = rawget(PW, "Progression") --[[@as PW.ProgressionLib?]]
    if progression == nil or progression.GetWeaponLevel == nil then return 1, true end
    local localView = rawget(progression, "_LocalView")
    local unlockAll = localView ~= nil and localView().unlockAll == true or false
    return progression.GetWeaponLevel(LocalPlayer(), weaponId), unlockAll
end

function lib.LiveGunsmith(draft)
    local slotId = draft.weaponSlot
    local items = slotId ~= nil and loadout()._Items(draft.loadout[slotId]) or nil
    if slotId == nil or items == nil then return nil end
    local weaponId = items[1]
    local input = lib.LiveInput(draft.loadout)
    local slot = lib.Editor(input).slots[slotId]
    local builds = istable(draft.loadout.builds) and draft.loadout.builds --[[@as table<string, any>]] or {}
    local build = istable(builds[slotId]) and builds[slotId] or {}
    local adapters = rawget(PW, "Adapters") --[[@as PW.AdaptersLib?]]
    local slots = adapters ~= nil and adapters.CallFor(weaponId, "GetSlots", weaponId, build) or {}
    local weapon = loadout()._RegistryLookup("weapons", weaponId) or {}
    local level, unlockAll = weaponProgress(weaponId)
    return {
        weaponId = weaponId, weapon = weapon, weaponName = phrase(isstring(weapon.Name) and weapon.Name or weaponId),
        build = build, slots = istable(slots) and slots or {}, weaponLevel = level, unlockAll = unlockAll,
        cap = slot ~= nil and slot.maxattachments or input.ctx.maxattachments,
        banned = input.ctx.bannedAttachments or {},
        options = function(id)
            local options = adapters ~= nil and adapters.CallFor(weaponId, "GetOptions", weaponId, id) or nil
            return istable(options) and options or {}
        end
    }
end

-- Draft and navigation -------------------------------------------------------------------------------------------

---@param screen string
local function push(screen)
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    local root = ui ~= nil and ui.CurrentRoot() --[[@as PWRoot?]] or nil
    if root == nil or ui == nil then return end
    if ui.Router.Push(root.model, screen) then root:Rebuild() end
end

function lib.Edit(index, focusName)
    local class = lib.ReadClasses()[index]
    if class == nil then return false end
    lib.Draft = {
        index = index, name = class.name, loadout = table.Copy(class.loadout), dirty = false, saved = false,
        focusName = focusName
    }
    push("loadout_editor")
    return true
end

function lib.OpenGunsmith(slotId)
    local draft = lib.Draft
    if draft == nil then return end
    draft.weaponSlot, draft.navigating = slotId, true
    push("loadout_gunsmith")
end

function lib.Create(base, value)
    local classes = lib.ReadClasses()
    local max = lib.MaxClasses()
    if #classes >= max then return nil, "You have " .. #classes .. " custom classes, the server keeps " .. max end
    ---@type string[]
    local names = {}
    for index, class in ipairs(classes) do names[index] = class.name end
    classes[#classes + 1] = { name = lib.FreeName(base, names), loadout = table.Copy(value) }
    lib.WriteClasses(classes)
    return #classes
end

function lib.Delete(index)
    local classes = lib.ReadClasses()
    if classes[index] == nil then return end
    table.remove(classes, index)
    writeFile(lib.ToFile(classes))
    local state = loadout().GetClassState ~= nil and loadout().GetClassState() or nil
    local fallback = ""
    for _, entry in ipairs(state ~= nil and state.entries or {}) do
        if fallback == "" and entry.available and string.sub(entry.ref, 1, 7) == "preset:" then fallback = entry.ref end
    end
    local pick = state ~= nil and lib.PickAfterDelete(state.selected, index, fallback) or nil
    upload(function()
        if pick ~= nil and pick ~= "" and loadout().SendPick ~= nil then loadout().SendPick(pick) end
    end)
end

function lib.SaveDraft()
    local draft = lib.Draft
    if draft == nil then return end
    lib._Save(lib.ReadClasses(), draft, {
        write = writeFile,
        upload = function()
            draft.savedState = nil
            upload(function()
                local get = loadout().GetClassState
                draft.savedState = get ~= nil and get() or false
            end)
        end
    })
    draft.dirty, draft.saved = false, true
end

function lib.DraftResult()
    local draft = lib.Draft
    if draft == nil or not draft.saved then return nil end
    local get = loadout().GetClassState
    local state = get ~= nil and get() or nil
    local seen = draft.savedState
    local answered = seen ~= nil and state ~= nil and state ~= seen
    return lib.SaveResult(state, "custom:" .. draft.index, answered)
end
