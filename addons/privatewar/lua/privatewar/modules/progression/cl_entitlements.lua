-- Client storage and upload of earned entitlements, separate from purchases and progression.
local lib = PW.Unlocks --[[@as PW.UnlocksLib]]
local progression = PW.Progression --[[@as PW.ProgressionLib]]
local state = rawget(progression, "_Local") --[[@as PW.ProgressionLocal]]
local upload = "pw_unlocks_upload"

function lib._LocalFile()
    if state.unlocks == nil then
        local text = file.Read(lib.FilePath, "DATA")
        state.unlocks = lib._FileFromJson(text ~= nil and util.JSONToTable(text, false, true) or nil)
    end
    return state.unlocks --[[@as PW.UnlocksFile]]
end

function lib._WriteLocal(stored)
    file.CreateDir("privatewar")
    file.Write(lib.FilePath, util.TableToJSON(lib._FileToJson(stored), true))
end

function lib._UploadLocal()
    if util.NetworkStringToID(upload) == 0 then return end
    net.Start(upload)
    lib._EncodeUpload(lib._LocalFile(), progression._NetWriter())
    net.SendToServer()
end

function lib.HasClaim(_, grant)
    return lib._HasClaim(lib._LocalFile().claims, grant)
end
