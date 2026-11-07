-- Kill Confirmed tags, client (T-2.5). The UI part of the feature: every networked tag is drawn as a bobbing glow
-- above its ground position, coloured by what picking it up does for the local player: an enemy's tag (confirm) in
-- gold, a teammate's or one's own tag (deny) in blue. Tags reach the client through TRANSMIT_ALWAYS; the client keeps
-- its own list (entity Initialize / OnRemove), so drawing never searches the entity list.

local lib = PW.KCTags --[[@as PW.KCTagsLib]]

local glow = Material("sprites/light_glow02_add")
local confirmColor = Color(255, 200, 40)
local denyColor = Color(60, 160, 255)
local lift, bob, size = 24, 4, 28

function lib._Init(tag)
    lib._Forget(tag)
    lib._Tags[#lib._Tags + 1] = tag
end

---@param me Player
---@param victim Entity
---@return Color
local function colorFor(me, victim)
    local check = PW.IsEnemy
    if IsValid(victim) and victim:IsPlayer() and check ~= nil and check(me, victim --[[@as Player]]) then
        return confirmColor
    end
    return denyColor
end

PW.HookFor(MODULE, "PostDrawTranslucentRenderables", function(_, depth, skybox)
    if depth or skybox or #lib._Tags == 0 then return end
    local me = LocalPlayer()
    if not IsValid(me) then return end
    local offset = Vector(0, 0, lift + math.sin(CurTime() * 3) * bob)
    render.SetMaterial(glow)
    for _, tag in ipairs(lib._Tags) do
        if IsValid(tag) then
            render.DrawSprite(tag:GetPos() + offset, size, size, colorFor(me, tag:GetVictim()))
        end
    end
end)
