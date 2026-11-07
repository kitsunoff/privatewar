-- Gate fixture: the rule gate must reject net.WriteTable outside lua/tests/ (DESIGN.md global rule 4).

---@param data table
local function send(data)
    net.Start("pw_fixture")
    net.WriteTable(data)
    net.Broadcast()
end

return send
