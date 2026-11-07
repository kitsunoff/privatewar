-- Test fixture (T-1.15): the entity the reload cases change, and the stand-in mode of the reload-during-LIVE case
-- (it counts its own Start/Think/Cleanup calls in self.Calls and declares one match setting).
GADGET.Name = "Alpha"
GADGET.Teams = 0
GADGET.Settings = { rounds = { type = "int", default = 3, min = 1, max = 9 } }

---@type table<string, any>
local widget = GADGET
for _, method in ipairs({ "Start", "Think", "Cleanup" }) do
    ---@param self table<string, any>
    widget[method] = function(self)
        ---@type table<string, integer>
        local calls = self.Calls or {}
        calls[method] = (calls[method] or 0) + 1
        self.Calls = calls
    end
end
