-- Optional bot-only candidate provider. Never registers classes or edits human/progression state.
if not PW or PW.API ~= 1 then return end

MODULE.Name = "Generated ARC9 bot loadouts"
MODULE.Settings = {
    generate = { scope = "match", type = "bool", default = true, label = "Generate ARC9 loadouts",
        description = "Add up to 18 map-stable bot-only builds to the existing class pool. " ..
            "Budget, bans and enabled items still apply. Unavailable builds use the existing pool." }
}

local lib = (rawget(PW, "Arc9BotLoadouts") or {}) --[[@as PW.Arc9BotLoadoutsLib]]
PW.Arc9BotLoadouts = lib

lib.Version = 1
lib.Archetypes = { "smg", "ar", "shotgun", "lmg", "sniper", "pistol" }

-- One perk per existing group. Pistol-only prioritizes explosive resistance and health regeneration.
lib.Perks = {
    smg = { "fleet_foot", "quick_draw", "quiet_steps" },
    ar = { "ready_up", "recoil_control", "adrenaline" },
    shotgun = { "flash_guard", "sleight_of_hand", "adrenaline" },
    lmg = { "flak_jacket", "sleight_of_hand", "retaliation" },
    sniper = { "soft_landing", "sightline", "ghost" },
    pistol = { "flak_jacket", "quick_draw", "adrenaline" }
}

function lib.Available(arc9, adapter)
    return arc9 ~= nil and adapter ~= nil and adapter:IsValid() and adapter:IsAvailable()
end

function lib.DescribeWeapon(class, category, kind, stored)
    if kind ~= "gun" and kind ~= "melee" then return nil end
    -- These public pack flags exclude scripted special guns even when their ARC9 enum says SMG/shotgun.
    if kind == "gun" and (stored.ShootEnt or stored.NotForNPCs == true) then return nil end
    local sub = string.lower(tostring(stored.SubCategory or ""))
    if kind == "gun" and (sub == "light machine guns" or string.find(class, "_lm_", 1, true)) then
        category = "lmg"
    end
    return { class = class, category = kind == "gun" and category or nil,
        knife = kind == "melee" and (stored.HoldType == "knife" or string.find(class, "_knife", 1, true) ~= nil) }
end

function lib.OptionRole(att)
    if att == nil or att.AdminOnly or att.Ignore then return nil end
    local categories = istable(att.Category) and att.Category or { att.Category }
    for _, category in ipairs(categories) do
        if category == "universal_camo" and isstring(att.CustomCamoTexture) and att.CustomCamoTexture ~= "" then
            return "camo"
        end
    end
    -- Only accessories, not ammo, receivers, perks, conversion kits or underbarrel firearms.
    for _, category in ipairs(categories) do
        local text = string.lower(tostring(category))
        for _, role in ipairs({ "optic", "scope", "muzzle", "grip", "stock", "laser" }) do
            if string.find(text, role, 1, true) then return role == "scope" and "optic" or role end
        end
    end
    return nil
end

function lib.Candidates(state, map, enabled)
    if not enabled or state == nil or state.map ~= map or state.version ~= lib.Version
        or state.status ~= "ready" then return {} end
    return state.entries
end

function lib.Keep(state, map)
    if state == nil or state.map ~= map then return nil end
    if state.version ~= lib.Version then
        state.status, state.entries, state.job = "stale", {}, nil
    elseif state.status == "working" then
        -- A coroutine closes over old code/adapters. Do not resume it or reroll the same map on reload.
        state.status, state.entries, state.job = "failed", {}, nil
        state.error = "generation interrupted by reload"
    end
    return state
end

if SERVER then AddCSLuaFile("privatewar/modules/bots_arc9_loadouts/sh_generate.lua") end
include("privatewar/modules/bots_arc9_loadouts/sh_generate.lua")
