-- Gate fixture: must be rejected by the type checker (string passed to a number parameter).

---@param n number
---@return number
local function double(n)
    return n * 2
end

print(double("x"))
