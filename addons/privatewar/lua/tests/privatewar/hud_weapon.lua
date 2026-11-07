-- T-11.11: live primary ammo presentation and UTF-8 display bounds (no gameplay changes).

---@return PW.HudLib
local function hud()
    assert(PW.HUD ~= nil, "HUD module required")
    return PW.HUD
end

return {
    groupName = "PW HUD weapon",
    cases = {
        {
            name = "Weapon: live name clip reserve update switch empty clip and zero reserve without stale data",
            func = function()
                ---@type PW.HudWeaponModel
                local out = { name = "", text = "" }
                local model = hud()._WeaponModel
                expect(model(true, "Rifle", 30, 1, 90, out)).to.equal(out)
                expect(out.name).to.equal("Rifle")
                expect(out.text).to.equal("30 / 90")
                model(true, "Rifle", 29, 1, 90, out)
                expect(out.clip).to.equal(29)
                model(true, "Pistol", 0, 2, 0, out)
                expect(out.name).to.equal("Pistol")
                expect(out.text).to.equal("0 / 0")
                model(false, "Pistol", 30, 2, 90, out)
                expect(out.name).to.equal("")
                expect(out.text).to.equal("")
                expect(out.clip).to.beNil()
                expect(out.reserve).to.beNil()
            end
        },
        {
            name = "Weapon: melee no primary ammo clipless reserve and invalid counts never invent ammo",
            func = function()
                ---@type PW.HudWeaponModel
                local out = { name = "", text = "" }
                local model = hud()._WeaponModel
                model(true, "Crowbar", -1, -1, 0, out)
                expect(out.name).to.equal("Crowbar")
                expect(out.text).to.equal("")
                model(true, "No primary", 0, nil, 10, out)
                expect(out.text).to.equal("")
                model(true, "Clipless", -1, 1, 12, out)
                expect(out.clip).to.beNil()
                expect(out.reserve).to.equal(12)
                expect(out.text).to.equal("- / 12")
                model(true, "Clipless", -1, 1, -4, out)
                expect(out.text).to.equal("- / 0")
                model(true, "Rifle", 0 / 0, 1, math.huge, out)
                expect(out.text).to.equal("- / 0")
            end
        },
        {
            name = "Names: long localized UTF-8 nicknames and weapon names fit without byte splitting",
            func = function()
                -- Cyrillic letters encoded explicitly: repository prose stays English.
                local cyrillic = string.char(208, 152, 208, 179, 209, 128, 208, 190, 208, 186)
                local mixed = cyrillic .. " Rifle " .. cyrillic
                local function measure(text) return (utf8.len(text) or 0) * 10 end
                expect(hud()._FitText(mixed, 1000, measure)).to.equal(mixed)
                for _, name in ipairs({ string.rep("LongName", 30), mixed, cyrillic }) do
                    for _, width in ipairs({ 0, 10, 30, 50, 100 }) do
                        local text = hud()._FitText(name, width, measure)
                        expect(utf8.len(text) ~= nil).to.beTrue()
                        expect(measure(text) <= width).to.beTrue()
                    end
                end
            end
        }
    }
}
