-- Loadout module, client (T-4.7; 05-loadout.md d.12). The player's custom classes live in
-- data/privatewar/classes.json ({ "version": 1, "classes": [ { "name": ..., "loadout": { ... } } ] }), so they
-- travel between friends' servers. On join the client uploads them (pw_loadout_classes, the explicit encoding of
-- sh_classes.lua, trimmed to fit ClassesMaxBytes); the server answers pw_loadout_class_state, which the LOADOUT
-- screen (screens/loadout_classes.lua) reads. The client decides nothing: the server repairs and checks again.
-- Editing classes (and writing the file) is the class editor's job (T-4.8, T-7.4).

---A file-local class: methods of the global MODULE defined in two files are reported as duplicates.
---@class PW.LoadoutModuleClient : PW.Module
local module = MODULE --[[@as PW.LoadoutModuleClient]]

local lib = PW.Loadout --[[@as PW.LoadoutLib]]

local filePath = "privatewar/classes.json"

---@class PW.LoadoutClientView
---@field state? PW.LoadoutClassState

---@type PW.LoadoutClientView
local view = rawget(lib, "_ClientView") or {}
rawset(lib, "_ClientView", view)

---@return integer
local function maxClasses()
    local value = PW.Setting("loadout.classes")
    return isnumber(value) and math.floor(value --[[@as number]]) or 10
end

---The size in bytes the classes take on the wire (net strings are zero-terminated).
---@param classes PW.LoadoutClass[]
---@return integer
local function wireBytes(classes)
    local total = 0
    lib._EncodeClasses(classes, {
        uint = function(_, width) total = total + width end,
        string = function(value) total = total + (#value + 1) * 8 end,
        bool = function() total = total + 1 end
    })
    return math.ceil(total / 8)
end

function lib.GetClassState()
    return view.state
end

function lib.UploadClasses()
    local classes = lib._ClassesFromJson(util.JSONToTable(file.Read(filePath, "DATA") or "") or {}, maxClasses())
    while #classes > 0 and wireBytes(classes) > lib.ClassesMaxBytes do
        print("[PW] classes.json: class " .. classes[#classes].name .. " left out, the upload is too large")
        classes[#classes] = nil
    end
    net.Start("pw_loadout_classes")
    lib._EncodeClasses(classes, lib._NetWriter())
    net.SendToServer()
end

function lib.SendPick(ref)
    net.Start("pw_loadout_pick")
    net.WriteString(ref)
    net.SendToServer()
end

---Asks the open screen to redraw from the current data (its view's PWRefresh).
local function notify()
    local ui = rawget(PW, "UI") --[[@as PW.UILib?]]
    local root = ui ~= nil and ui.CurrentRoot ~= nil and ui.CurrentRoot() or nil
    local shown = root ~= nil and (root --[[@as PWRoot]]).view or nil --[[@as Panel?]]
    if shown ~= nil and IsValid(shown) and shown.PWRefresh ~= nil then shown:PWRefresh() end
end

net.Receive("pw_loadout_class_state", function()
    if not IsValid(module) then return end
    view.state = lib._DecodeClassState(lib._NetReader())
    notify()
end)

PW.HookFor(module, "InitPostEntity", function()
    lib.UploadClasses()
end)
