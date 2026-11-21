-- Progression, client (T-4.10; 06-progression.md d.5). The player's progression lives here, in
-- data/privatewar/progression.json ({ v, xp, weapons, batch }, sh_storage.lua). On join the client uploads it
-- (pw_progression_upload, the top MaxWeapons weapons by XP); the server answers with the levels it computed
-- (pw_progression_levels, read by the client-side IsUnlocked), sends 10 s deltas (pw_progression_delta: applied with
-- the pure _ApplyDelta, a duplicate batch is ignored, the file is written after each applied delta) and the match
-- summary at POSTMATCH (pw_progression_summary: kept for MatchSummary, notified as PW_ProgressionSummary(summary)
-- and printed to the console; the postmatch screen is T-7.7).

---A file-local class: methods of the global MODULE defined in two files are reported as duplicates.
---@class PW.ProgressionModuleClient : PW.Module
local module = MODULE --[[@as PW.ProgressionModuleClient]]

local lib = PW.Progression --[[@as PW.ProgressionLib]]
local unlocks = PW.Unlocks --[[@as PW.UnlocksLib]]

---@type PW.ProgressionLocal
local localState = rawget(lib, "_Local") or {}
rawset(lib, "_Local", localState)
include("privatewar/modules/progression/cl_entitlements.lua")

---@return PW.ProgressionFile
local function loadFile()
    if localState.file == nil then
        localState.file = lib._FileFromJson(util.JSONToTable(file.Read(lib.FilePath, "DATA") or "") or {})
    end
    return localState.file --[[@as PW.ProgressionFile]]
end

---@param stored PW.ProgressionFile
local function saveFile(stored)
    file.CreateDir("privatewar")
    file.Write(lib.FilePath, util.TableToJSON(lib._FileToJson(stored), true))
end

function lib.GetLocalFile()
    return localState.file
end

function lib._LocalView()
    local levels = localState.levels
    if levels == nil then
        local ply = LocalPlayer()
        levels = {
            level = IsValid(ply) and lib.GetLevel(ply) or 1, weapons = {},
            unlockAll = PW.Setting("progression.unlockall") == true, maxAttachments = 5
        }
    end
    local owned = nil
    if lib._OwnedActive() then
        owned = function(key)
            local stored = localState.file
            return stored ~= nil and stored.owned ~= nil and stored.owned[key] == true
        end
    end
    return lib._ViewFromLevels(levels --[[@as PW.ProgressionLevels]], lib._RegistryLookup, owned, function(key)
        return unlocks._LocalFile().grants[key] ~= nil
    end)
end

function lib.GetCurrency()
    local stored = localState.file
    return stored ~= nil and stored.currency or 0
end

function lib.IsOwned(_, key)
    local stored = localState.file
    return stored ~= nil and stored.owned ~= nil and stored.owned[key] == true
end

function lib._LocalSummary()
    return localState.summary
end

local function upload()
    net.Start("pw_progression_upload")
    lib._EncodeState(lib._CheckState(loadFile(), lib.MaxWeapons), lib._NetWriter())
    net.SendToServer()
    unlocks._UploadLocal()
end

---@type PW.UnlockClientIO
local deltaIO = { writeUnlocks = unlocks._WriteLocal, writeProgression = saveFile, notify = PW.Notify }

net.Receive("pw_progression_delta", function()
    if not IsValid(module) then return end
    loadFile()
    unlocks._LocalFile()
    unlocks._ClientDelta(localState, lib._DecodeDelta(lib._NetReader()), LocalPlayer(), deltaIO)
end)

net.Receive("pw_progression_levels", function()
    if not IsValid(module) then return end
    localState.levels = lib._DecodeLevels(lib._NetReader())
end)

---@param summary PW.ProgressionSummary
local function printSummary(summary)
    print(string.format("[PW] match summary: +%d XP, level %d -> %d, %d weapon level up(s), %d medal kind(s)",
        summary.xp, summary.levelBefore, summary.levelAfter, #summary.weapons, #summary.medals))
end

net.Receive("pw_progression_summary", function()
    if not IsValid(module) then return end
    local summary = lib._DecodeSummary(lib._NetReader())
    localState.summary = summary
    printSummary(summary)
    PW.Notify("PW_ProgressionSummary", summary)
end)

PW.HookFor(module, "InitPostEntity", function()
    upload()
end)
