-- World label layout is pure and cached outside the paint loop.
---@param x number
---@param y number
---@return PW.DeviceMarker
local function marker(x, y)
    return { x = x, y = y, text = "SUPPORT / OWNER / 30s", visible = true, width = 200, height = 20 }
end

return {
    groupName = "PW support marker layout",
    cases = {
        {
            name = "Device markers: nearby owned labels are separated without changing device visibility",
            func = function()
                local rows = { marker(640, 300), marker(640, 300), marker(640, 300) }
                assert(PW.SupportStreaks).LayoutMarkers(rows, 1280, 720)
                expect(rows[1].y).to.equal(300)
                expect(rows[2].y >= rows[1].y + 24).to.beTrue()
                expect(rows[3].y >= rows[2].y + 24).to.beTrue()
                expect(rows[3].visible).to.beTrue()
            end
        },
        {
            name = "Device markers: eight simultaneous labels retain padding at 720p 800p and 1080p",
            func = function()
                for _, size in ipairs({ { 1280, 720 }, { 1280, 800 }, { 1920, 1080 } }) do
                    ---@type PW.DeviceMarker[]
                    local rows = {}
                    for i = 1, 8 do rows[i] = marker(1, 1) end
                    assert(PW.SupportStreaks).LayoutMarkers(rows, size[1], size[2])
                    for i, row in ipairs(rows) do
                        expect(row.x >= 108 and row.x <= size[1] - 108).to.beTrue()
                        expect(row.y >= 28 and row.y <= size[2] - 8).to.beTrue()
                        if i > 1 then expect(row.y >= rows[i - 1].y + 24).to.beTrue() end
                    end
                end
            end
        },
        {
            name = "Device markers: bottom-edge labels stack upwards and distant columns keep their anchors",
            func = function()
                local rows = { marker(1200, 719), marker(1200, 719), marker(200, 719) }
                assert(PW.SupportStreaks).LayoutMarkers(rows, 1280, 720)
                expect(rows[1].y).to.equal(712)
                expect(rows[2].y <= rows[1].y - 24).to.beTrue()
                expect(rows[3].y).to.equal(712)
            end
        }
    }
}
