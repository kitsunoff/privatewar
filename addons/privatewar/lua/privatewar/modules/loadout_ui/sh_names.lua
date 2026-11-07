-- LOADOUT tab editors, pure part 1 (T-7.4; 05-loadout.md d.12): class names, the classes.json shape, the save flow
-- with injected file and net calls, the server's answer to a save and the pick after a delete. Loaded by shared.lua.

local lib = PW.LoadoutUI --[[@as PW.LoadoutUILib]]

local loadout = rawget(PW, "Loadout") --[[@as PW.LoadoutLib?]]
lib.NameMax = loadout ~= nil and loadout.ClassNameMax or 32

function lib.ValidateName(name, others)
    if not isstring(name) then return nil, "Enter a name" end
    local clean = string.Trim(name --[[@as string]])
    if clean == "" then return nil, "Enter a name" end
    if #clean > lib.NameMax then return nil, "At most " .. lib.NameMax .. " characters" end
    if string.find(clean, "%c") ~= nil then return nil, "No control characters" end
    local lower = string.lower(clean)
    for _, other in ipairs(others) do
        if string.lower(other) == lower then return nil, "Another class is called " .. other end
    end
    return clean, nil
end

function lib.FreeName(base, others)
    local stem = string.sub(string.Trim(base), 1, lib.NameMax)
    if stem == "" then stem = "Class" end
    local number = 1
    while true do
        local suffix = number == 1 and "" or (" " .. number)
        local candidate = string.Trim(string.sub(stem, 1, lib.NameMax - #suffix)) .. suffix
        if lib.ValidateName(candidate, others) ~= nil then return candidate end
        number = number + 1
    end
end

function lib.ToFile(classes)
    ---@type table<string, any>[]
    local list = {}
    for index, class in ipairs(classes) do
        list[index] = { name = class.name, loadout = table.Copy(class.loadout) }
    end
    return { version = 1, classes = list }
end

function lib._Save(classes, draft, io)
    ---@type PW.LoadoutClass[]
    local copy = {}
    for index, class in ipairs(classes) do copy[index] = { name = class.name, loadout = table.Copy(class.loadout) } end
    copy[draft.index] = { name = draft.name, loadout = table.Copy(draft.loadout) }
    io.write(lib.ToFile(copy))
    io.upload()
    return copy
end

function lib.UploadDelay(now, last, gap)
    if last == nil then return 0 end
    return math.max(0, last + gap - now)
end

---@param state? PW.LoadoutClassState
---@param ref string
---@return PW.LoadoutClassEntry?
local function entryOf(state, ref)
    for _, entry in ipairs(state ~= nil and state.entries or {}) do
        if entry.ref == ref then return entry end
    end
    return nil
end

function lib.SaveResult(state, ref, answered)
    if not answered then return { status = "waiting", title = "Saving: waiting for the server", lines = {} } end
    local entry = entryOf(state, ref)
    if entry == nil then
        return { status = "missing", title = "The server did not list this class (too many classes?)", lines = {} }
    end
    ---@type string[]
    local lines = {}
    if not entry.available then
        lines[1] = entry.reason or "not available"
        for _, line in ipairs(entry.removed) do lines[#lines + 1] = line end
        return { status = "unavailable", title = "Saved, but not usable in this match", lines = lines }
    end
    if #entry.removed > 0 then
        for index, line in ipairs(entry.removed) do lines[index] = line end
        return { status = "repaired", title = "Saved. The server removed:", lines = lines }
    end
    return { status = "accepted", title = "Saved. The server accepted the class.", lines = lines }
end

function lib.PickAfterDelete(selected, deleted, fallback)
    local index = tonumber(string.match(selected or "", "^custom:(%d+)$") or "")
    if index == nil or index < deleted then return nil end
    if index == deleted then return fallback end
    return "custom:" .. (index - 1)
end

---@param id PW.LoadoutUIActionId
---@param label string
---@param reason? string the lock reason, nil when open
---@return PW.LoadoutUIAction
local function action(id, label, reason)
    return { id = id, label = label, locked = reason ~= nil, reason = reason }
end

function lib.ClassActions(ref, count, max)
    local kind = ref ~= nil and string.match(ref, "^(%l+):") or nil
    local full = count >= max and ("You have " .. count .. " custom classes, the server keeps " .. max) or nil
    local pick = "Pick a class on the left"
    ---@type string?
    local custom = nil
    if kind == "preset" then
        custom = "Presets cannot be changed: copy it"
    elseif kind ~= "custom" then
        custom = pick
    end
    return {
        action("edit", "EDIT", custom),
        action("copy", "COPY", kind == nil and pick or full),
        action("rename", "RENAME", custom),
        action("delete", "DELETE", custom),
        action("new", "NEW CLASS", full)
    }
end
