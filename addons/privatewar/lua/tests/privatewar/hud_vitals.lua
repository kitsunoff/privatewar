-- T-11.11: pure presentation and fail-open native HUD replacement. Existing HUD regression suites remain intact.

---@return PW.HudLib
local function hud()
    assert(PW.HUD ~= nil, "HUD module required")
    return PW.HUD
end

return {
    groupName = "PW HUD vitals",
    cases = {
        {
            name = "Health fraction: zero half full clamp out-of-range and invalid maximum are safe",
            func = function()
                local fraction = hud()._HealthFraction
                expect(fraction(0, 100)).to.equal(0)
                expect(fraction(75, 150)).to.equal(0.5)
                expect(fraction(150, 150)).to.equal(1)
                expect(fraction(200, 100)).to.equal(1)
                expect(fraction(-20, 100)).to.equal(0)
                for _, maximum in ipairs({ 0, -1, math.huge, 0 / 0 }) do
                    expect(fraction(50, maximum)).to.equal(0)
                end
                expect(fraction(50, nil)).to.equal(0)
                expect(fraction(nil, 100)).to.equal(0)
                expect(fraction(0 / 0, 100)).to.equal(0)
            end
        },
        {
            name = "Armor: exactly three bounded continuous segments at 0 25 50 75 100 125 150 overflow and negative",
            func = function()
                local out = { 9, 9, 9, 9 }
                for _, armor in ipairs({ -25, 0, 25, 50, 75, 100, 125, 150, 200 }) do
                    expect(hud()._ArmorSegments(armor, out)).to.equal(out)
                    expect(#out).to.equal(3)
                    local sum = 0
                    for i = 1, 3 do
                        local value = out[i] --[[@as number]]
                        expect(value >= 0 and value <= 1).to.beTrue()
                        expect(value).to.equal(math.Clamp((armor - (i - 1) * 50) / 50, 0, 1))
                        sum = sum + value
                    end
                    expect(sum).to.equal(math.Clamp(armor, 0, 150) / 50)
                end
                expect(hud()._ArmorSegments(nil, out)).to.deepEqual({ 0, 0, 0 })
            end
        },
        {
            name = "Layout: nickname above armor above health; left/right anchors clear XP and equipment",
            func = function()
                for _, size in ipairs({ { 1280, 720 }, { 1280, 800 }, { 1920, 1080 } }) do
                    local w, h = size[1], size[2]
                    local box = hud()._PlayerLayout(w, h, {})
                    local scale = math.min(w / 1920, h / 1080)
                    expect(box.left >= 0 and box.left + box.width < w / 2).to.beTrue()
                    expect(box.nameY >= 0 and box.nameY + box.nameHeight < box.armorY).to.beTrue()
                    expect(box.armorY + box.armorHeight < box.healthY).to.beTrue()
                    expect(box.healthY + box.healthHeight).to.equal(box.bottom)
                    expect(box.bottom < h - 28 * scale).to.beTrue()
                    expect(box.weaponX > w / 2 and box.weaponRight <= w).to.beTrue()
                    expect(box.weaponNameY > 900 * h / 1080).to.beTrue()
                    expect(box.weaponAmmoY + 32 * scale <= box.bottom).to.beTrue()
                end
            end
        },
        {
            name = "Lifecycle: only LIVE alive valid non-spectating local players show vitals or weapon",
            func = function()
                local visible = hud()._PlayerVisible
                expect(visible("LIVE", true, true, false)).to.beTrue()
                for _, phase in ipairs({ "LOBBY", "PREMATCH", "POSTMATCH", "VOTE" }) do
                    expect(visible(phase, true, true, false)).to.beFalse()
                end
                expect(visible("LIVE", false, true, false)).to.beFalse()
                expect(visible("LIVE", true, false, false)).to.beFalse()
                expect(visible("LIVE", true, true, true)).to.beFalse()
            end
        },
        {
            name = "Native panels: active painted replacements only; error and disable recover vanilla",
            func = function()
                local registry = PW.Registry.New("test_hud_vitals", { log = function() end })
                registry.Register({ Phases = { "LIVE" }, Draw = function() end }, "vitals")
                registry.Register({ Phases = { "LIVE" }, Draw = function() end }, "weapon")
                registry.ResolveAll()
                local lib = hud()
                local state = lib._NewState()
                expect(lib._NativeHidden("CHudHealth", registry, "LIVE", true)).to.beFalse()
                lib._Paint(state, registry, "LIVE")
                for _, name in ipairs({ "CHudHealth", "CHudBattery", "CHudAmmo", "CHudSecondaryAmmo" }) do
                    expect(lib._NativeHidden(name, registry, "LIVE", true)).to.beTrue()
                    expect(lib._NativeHidden(name, registry, "LIVE", false)).to.beFalse()
                    expect(lib._NativeHidden(name, nil, "LIVE", true)).to.beFalse()
                    expect(lib._NativeHidden(name, registry, "LOBBY", true)).to.beFalse()
                end
                expect(lib._NativeHidden("CHudCrosshair", registry, "LIVE", true)).to.beFalse()
                expect(lib._NativeHidden("CHudDeathNotice", registry, "LIVE", true)).to.beFalse()
                registry._Disable("vitals", "test")
                expect(lib._NativeHidden("CHudHealth", registry, "LIVE", true)).to.beFalse()
                expect(lib._NativeHidden("CHudAmmo", registry, "LIVE", true)).to.beTrue()
                registry.Register({ Draw = function() error("weapon draw failed") end }, "weapon")
                registry.ResolveAll()
                state.dirty = true
                lib._Paint(state, registry, "LIVE")
                expect(lib._NativeHidden("CHudAmmo", registry, "LIVE", true)).to.beFalse()
                registry._Release()
            end
        },
        {
            name = "Native panels: missing replacement or visibility veto never hides vanilla",
            func = function()
                local registry = PW.Registry.New("test_hud_veto", { log = function() end })
                registry.Register({ ShouldDraw = function() return false end, Draw = function() end }, "vitals")
                registry.ResolveAll()
                hud()._Paint(hud()._NewState(), registry, "LIVE")
                expect(hud()._NativeHidden("CHudHealth", registry, "LIVE", true)).to.beFalse()
                expect(hud()._NativeHidden("CHudAmmo", registry, "LIVE", true)).to.beFalse()
                registry._Release()
            end
        }
    }
}
