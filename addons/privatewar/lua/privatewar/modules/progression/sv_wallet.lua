-- Progression wallet, server (T-4.12; 06-progression.md d.6). The currency and the purchased items live in the session
-- state next to the XP (the client file is the storage, d.5) and travel in the same deltas: earned and spent currency
-- and newly owned keys join the player's pending delta. The economy module (modules/economy/) decides what is sold and
-- what is earned; this file only keeps the numbers safe: whole amounts, never below 0, never above MaxCurrency.
-- Included by init.lua.

local lib = PW.Progression --[[@as PW.ProgressionLib]]

---@param value any
---@return integer?
local function wholeAmount(value)
    if not isnumber(value) then return nil end
    local number = value --[[@as number]]
    if number ~= number or number < 1 or number > lib.MaxCurrency then return nil end
    return math.floor(number)
end

---@param store PW.ProgressionStore
---@param ply Player
---@return table<string, boolean>
function lib._GetOwned(store, ply)
    return lib._StateOf(store, ply).owned or {}
end

---@param store PW.ProgressionStore
---@param ply Player
---@param amount number
function lib._AddCurrency(store, ply, amount)
    local whole = wholeAmount(amount)
    if whole == nil then return end
    local state = lib._StateOf(store, ply)
    local before = state.currency or 0
    state.currency = math.min(before + whole, lib.MaxCurrency)
    local pending = lib._PendingOf(store, ply)
    pending.earned = pending.earned + (state.currency - before)
end

---@param store PW.ProgressionStore
---@param ply Player
---@param amount number
---@return boolean
function lib._SpendCurrency(store, ply, amount)
    local whole = wholeAmount(amount)
    local state = lib._StateOf(store, ply)
    if whole == nil or (state.currency or 0) < whole then return false end
    state.currency = (state.currency or 0) - whole
    local pending = lib._PendingOf(store, ply)
    pending.spent = pending.spent + whole
    return true
end

---@param store PW.ProgressionStore
---@param ply Player
---@param keys string[]
---@return integer
function lib._GrantOwned(store, ply, keys)
    local state = lib._StateOf(store, ply)
    local owned = state.owned or {}
    local pending = lib._PendingOf(store, ply)
    local added = 0
    for key in pairs(lib._CheckOwned(keys, lib.MaxOwned)) do
        if owned[key] ~= true then
            owned[key] = true
            pending.owned[key] = true
            added = added + 1
        end
    end
    state.owned = owned
    return added
end

function lib.GetCurrency(ply)
    return lib._StateOf(PW._Progression, ply).currency or 0
end

function lib.AddCurrency(ply, amount)
    lib._AddCurrency(PW._Progression, ply, amount)
end

function lib.SpendCurrency(ply, amount)
    return lib._SpendCurrency(PW._Progression, ply, amount)
end

function lib.GrantOwned(ply, keys)
    return lib._GrantOwned(PW._Progression, ply, keys)
end

function lib.IsOwned(ply, key)
    return lib._GetOwned(PW._Progression, ply)[key] == true
end

function lib.Flush(ply)
    lib._Flush(PW._Progression, ply)
end
