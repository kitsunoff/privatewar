-- Readable stock-device ownership/expiry and generic activation/refusal feedback, cached outside HUDPaint.
HUDELEMENT.Order = 35
HUDELEMENT.Phases = { "LIVE" }
local text = Color(232, 237, 233)
local shade = Color(11, 15, 12, 230)

function HUDELEMENT:Draw()
    local lib = PW.Devices
    if lib == nil or lib.Markers == nil then return end
    for _, row in ipairs(lib.Markers) do
        if row.visible then
            draw.SimpleTextOutlined(row.text, "PW_SupportMarker", row.x, row.y, text,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 2, shade)
        end
    end
    if lib.Notice ~= nil and lib.Notice ~= "" then
        draw.SimpleTextOutlined(lib.Notice, "PW_SupportMarker", ScrW() * 0.5, ScrH() * 0.75, text,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, shade)
    end
end
