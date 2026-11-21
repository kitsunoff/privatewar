---@return table<string, any>
local function stims()
    return assert(rawget(PW, "Stims"), "stims module is not implemented")
end

return {
    groupName = "PW item-owned stim effects",
    cases = {
        {
            name = "Played sends pw_stim_used to the owner only with the item index",
            func = function()
                ---@type table[]
                local signals = {}
                local owner = {
                    IsValid = function() return true end, IsBot = function() return false end,
                    EmitSound = function(_, sound) signals[#signals + 1] = { "sound", sound --[[@as string]] } end,
                    ViewPunch = function(_, angle)
                        local value = angle --[[@as Angle]]
                        signals[#signals + 1] = { "punch", value.p }
                    end
                }
                stub(net, "Start").with(function(channel) signals[#signals + 1] = { "start", channel } end)
                stub(net, "WriteUInt").with(function(index, bits)
                    signals[#signals + 1] = { "uint", index, bits }
                end)
                stub(net, "Send").with(function(ply) signals[#signals + 1] = { "send", ply } end)
                stub(net, "Broadcast").with(function() error("presentation broadcast") end)
                stims().Played(owner, { ClassName = "stim_speed", Sound = "items/battery_pickup.wav" })
                expect(signals).to.deepEqual({
                    { "sound", "items/battery_pickup.wav" }, { "punch", 2 },
                    { "start", "pw_stim_used" }, { "uint", 2, 8 }, { "send", owner }
                })
            end
        }
    }
}
