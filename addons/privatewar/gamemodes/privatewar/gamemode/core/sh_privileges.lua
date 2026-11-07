-- Named privileges with optional CAMI (T-1.10, 00-core.md d.7). Modules declare privileges; the core
-- declares none (01-extensibility.md d.16). The CAMI global is read on every call, so an admin mod
-- loaded later (or a test stub) is picked up; a privilege is registered once per CAMI table.
--
-- The CAMI check is synchronous: PW.Can returns a boolean because its callers (the net wrapper,
-- console commands) decide on the spot. CAMI.PlayerHasAccess without a callback returns the answer
-- at once and raises an error when the admin mod cannot answer immediately; that error counts as
-- "denied" with one log line.

---@param message string
local function defaultLog(message)
    print("[PW] " .. message)
end

---@type PW.PrivilegeStore
PW._Privileges = PW._Privileges or { defs = {}, log = defaultLog }

---Fallback checks by default usergroup.
---@type table<string, fun(ply: Player): boolean>
local groupChecks = {
    user = function() return true end,
    admin = function(ply) return ply:IsAdmin() end,
    superadmin = function(ply) return ply:IsSuperAdmin() end
}

---@return PW.CamiLib?
local function currentCami()
    return rawget(_G, "CAMI")
end

---@param def PW.PrivilegeDef
---@param cami PW.CamiLib
local function registerInCami(def, cami)
    if def.cami == cami then return end
    cami.RegisterPrivilege({ Name = def.Name, MinAccess = def.MinAccess })
    def.cami = cami
end

---@param name string
---@param defaultGroup string
---@return boolean
function PW.Privilege(name, defaultGroup)
    local store = PW._Privileges
    if groupChecks[defaultGroup] == nil then
        store.log(string.format("privilege %q has unknown default usergroup %q", name, tostring(defaultGroup)))
        return false
    end
    ---@type PW.PrivilegeDef
    local def = { Name = name, MinAccess = defaultGroup --[[@as PW.Usergroup]] }
    store.defs[name] = def
    local cami = currentCami()
    if cami ~= nil then registerInCami(def, cami) end
    return true
end

---@param ply Player
---@param name string
---@return boolean
function PW.Can(ply, name)
    local store = PW._Privileges
    local def = store.defs[name]
    if def == nil then
        store.log(string.format("unknown privilege %q denied", name))
        return false
    end
    local cami = currentCami()
    if cami == nil then return groupChecks[def.MinAccess](ply) end
    registerInCami(def, cami)
    local ok, allowed = pcall(cami.PlayerHasAccess, ply, name)
    if not ok then
        store.log(string.format("CAMI check of privilege %q failed, denied: %s", name, tostring(allowed)))
        return false
    end
    return allowed == true
end
