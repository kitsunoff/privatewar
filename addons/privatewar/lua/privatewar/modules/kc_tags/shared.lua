-- Kill Confirmed tags (T-2.5; 02-modes.md d.5; README.md "worth stealing": a data-only, TRANSMIT_ALWAYS tag with
-- network vars and server-validated pickup). Owns PW.KCTags and the scripted entity pw_kc_tag. Shared: the API, the
-- gameplay values, the pure rules and the entity class, whose methods only call the per-realm parts:
--   init.lua (server): spawning, the trigger setup, the touch handler (pickup), expiry, removal;
--   cl_init.lua (client): the client tag list and drawing.
-- Pickup is the engine's own trigger touch (SetTrigger: StartTouch/Touch), no searches in Think (DESIGN.md
-- performance rule 1). The module does not score: a pickup fires the notification
-- PW_KCTagCollected(collector, victim, verdict) and the active mode scores there.

MODULE.Name = "Kill Confirmed tags"

local lib = (rawget(PW, "KCTags") or {}) --[[@as PW.KCTagsLib]]
PW.KCTags = lib

-- Gameplay values, reported for confirmation (T-2.5).
lib.Class = "pw_kc_tag"
lib.MaxTags = 64
lib.GroundTrace = 256
lib.Mins = Vector(-20, -20, 0)
lib.Maxs = Vector(20, 20, 48)

lib._Tags = lib._Tags or {}

---@param info PW.KCTouchInfo
---@return PW.KCVerdict?
function lib._Verdict(info)
    if not info.player or not info.alive then return nil end
    if info.enemy then return "confirm" end
    return "deny"
end

---@param now number
---@param lifetime number
---@return number
function lib._ExpireAt(now, lifetime)
    if lifetime > 0 then return now + lifetime end
    return 0
end

---@param at number
---@param now number
---@return boolean
function lib._Expired(at, now)
    return at > 0 and now >= at
end

---@param count integer
---@param max integer
---@return integer
function lib._Evict(count, max)
    return math.max(0, count - max + 1)
end

---@param tag PW.KCTag
function lib._Forget(tag)
    for i, entry in ipairs(lib._Tags) do
        if entry == tag then
            table.remove(lib._Tags, i)
            return
        end
    end
end

---@return PW.KCTag[]
function lib.GetAll()
    ---@type PW.KCTag[]
    local list = {}
    for _, tag in ipairs(lib._Tags) do
        if IsValid(tag) then list[#list + 1] = tag end
    end
    return list
end

-- The entity: methods are thin calls into the realm parts above, so a reload (pw_reload) replaces behaviour without
-- touching tags that already exist.
local tagClass = {} --[[@as PW.KCTag]]
tagClass.Type = "anim"
tagClass.Base = "base_anim"
tagClass.PrintName = "Kill Confirmed tag"
tagClass.Spawnable = false
tagClass.AdminOnly = true
tagClass.DisableDuplicator = true
tagClass.PhysgunDisabled = true

function tagClass:SetupDataTables()
    self:NetworkVar("Entity", 0, "Victim")
    self:NetworkVar("Float", 0, "ExpireAt")
end

function tagClass:Initialize()
    local init = lib._Init
    if init ~= nil then init(self) end
end

function tagClass:UpdateTransmitState()
    return TRANSMIT_ALWAYS
end

---@param other Entity
function tagClass:StartTouch(other)
    local touch = lib._Touch
    if touch ~= nil then touch(self, other) end
end

---@param other Entity
function tagClass:Touch(other)
    local touch = lib._Touch
    if touch ~= nil then touch(self, other) end
end

function tagClass:Think()
    local think = lib._Think
    if think ~= nil then return think(self) end
end

function tagClass:OnRemove()
    lib._Forget(self)
end

scripted_ents.Register(tagClass, lib.Class)
