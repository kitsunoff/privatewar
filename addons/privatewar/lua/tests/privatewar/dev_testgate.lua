-- Dev-only GLuaTest start gate (dev/privatewar_dev/.../pw_testgate.lua): the one-shot skip flag that
-- scripts/deck/snap.sh writes before its map reload. The gate consumes the flag on Initialize, so a stale flag never
-- skips more than one run, and a missing flag never skips one.

---@type string a flag of this test only, never the real one (data/privatewar_dev/skip_tests.txt)
local probeFile = "privatewar_dev/testgate_probe.txt"

---@return fun(path: string): boolean
local function consumeFlag()
    local gate = rawget(PW, "_DevTestGate") --[[@as table?]]
    assert(gate ~= nil, "PW._DevTestGate is missing: the dev addon is not loaded")
    return gate.ConsumeFlag --[[@as fun(path: string): boolean]]
end

---@type string a backup of this test only, never the real one (data/privatewar_dev/convars_backup.json)
local backupProbe = "privatewar_dev/testgate_backup_probe.json"

---@class PW.DevConVarBackup
---@field Backup fun(path: string, names: string[], get: fun(name: string): string?): boolean
---@field Restore fun(path: string, set: fun(name: string, value: string)): integer?
---@field Discard fun(path: string): boolean

---@return PW.DevConVarBackup
local function backupApi()
    local gate = rawget(PW, "_DevTestGate") --[[@as table?]]
    assert(gate ~= nil, "PW._DevTestGate is missing: the dev addon is not loaded")
    return gate --[[@as PW.DevConVarBackup]]
end

local function dropProbe()
    if file.Exists(backupProbe, "DATA") then file.Delete(backupProbe) end
end

return {
    groupName = "PW dev test gate",
    cases = {
        {
            name = "A present skip flag is consumed once: true and the file is gone, then false",
            func = function()
                file.CreateDir("privatewar_dev")
                file.Write(probeFile, "snap")
                expect(consumeFlag()(probeFile)).to.beTrue()
                expect(file.Exists(probeFile, "DATA")).to.beFalse()
                expect(consumeFlag()(probeFile)).to.beFalse()
            end,
            cleanup = function()
                if file.Exists(probeFile, "DATA") then file.Delete(probeFile) end
            end
        },
        {
            name = "Without a skip flag nothing is skipped",
            func = function()
                if file.Exists(probeFile, "DATA") then file.Delete(probeFile) end
                expect(consumeFlag()(probeFile)).to.beFalse()
            end
        },
        {
            name = "Backup writes the current values; Restore sets them back, reports the count and deletes the file",
            func = function()
                local api = backupApi()
                local values = { pw_a = "10", pw_b = "0.5" }
                expect(api.Backup(backupProbe, { "pw_a", "pw_b" }, function(name) return values[name] end)).to.beTrue()
                expect(file.Exists(backupProbe, "DATA")).to.beTrue()
                ---@type table<string, string>
                local restored = {}
                local count = api.Restore(backupProbe, function(name, value) restored[name] = value end)
                expect(count).to.equal(2)
                expect(restored.pw_a).to.equal("10")
                expect(restored.pw_b).to.equal("0.5")
                expect(file.Exists(backupProbe, "DATA")).to.beFalse()
            end,
            cleanup = dropProbe
        },
        {
            name = "Backup skips ConVars that do not exist",
            func = function()
                local api = backupApi()
                local function get(name) return name == "pw_a" and "3" or nil end
                api.Backup(backupProbe, { "pw_a", "pw_missing" }, get)
                ---@type table<string, string>
                local restored = {}
                expect(api.Restore(backupProbe, function(name, value) restored[name] = value end)).to.equal(1)
                expect(restored.pw_missing).to.beNil()
            end,
            cleanup = dropProbe
        },
        {
            name = "Restore without a backup does nothing and returns nil",
            func = function()
                dropProbe()
                local called = false
                expect(backupApi().Restore(backupProbe, function() called = true end)).to.beNil()
                expect(called).to.beFalse()
            end
        },
        {
            name = "Restore deletes a corrupt backup without setting anything",
            func = function()
                file.CreateDir("privatewar_dev")
                file.Write(backupProbe, "not json {")
                local called = false
                expect(backupApi().Restore(backupProbe, function() called = true end)).to.beNil()
                expect(called).to.beFalse()
                expect(file.Exists(backupProbe, "DATA")).to.beFalse()
            end,
            cleanup = dropProbe
        },
        {
            name = "Discard (normal end of a run) deletes the backup; a second call returns false",
            func = function()
                local api = backupApi()
                api.Backup(backupProbe, { "pw_a" }, function() return "1" end)
                expect(api.Discard(backupProbe)).to.beTrue()
                expect(file.Exists(backupProbe, "DATA")).to.beFalse()
                expect(api.Discard(backupProbe)).to.beFalse()
            end,
            cleanup = dropProbe
        }
    }
}
