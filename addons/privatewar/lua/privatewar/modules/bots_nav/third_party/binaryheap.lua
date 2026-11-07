-- Third-party code: binaryheap.lua by Thijs Schreijer (Tieske).
--
--   Upstream:  https://github.com/Tieske/binaryheap.lua
--   Version:   0.4 (tag version_0v4)
--   Commit:    579662c1ac47bec954f29195a1d5fd9b4d5f5cb6
--   Source:    https://raw.githubusercontent.com/Tieske/binaryheap.lua/version_0v4/src/binaryheap.lua
--   Licence:   MIT/X11 (upstream README: "License: MIT/X11"; rockspec: license = "MIT/X11")
--
-- Copyright 2015-2018 Thijs Schreijer
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
-- documentation files (the "Software"), to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and
-- to permit persons to whom the Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all copies or substantial portions of
-- the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
-- THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
-- CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
-- IN THE SOFTWARE.
--
-- Changes made for Private War (the algorithm is the upstream one; the kept functions behave as upstream):
--   * only the min-heap with unique payloads (`minUnique`) is kept; the plain heaps and the max heaps are removed;
--   * reformatted (4-space indent, locals named in one style, type annotations) so the project's lint and type
--     gates pass without exceptions; the upstream file does not pass them as it is;
--   * type annotations added for the type gate.
-- A heap holds `values` (the sort keys) and `payloads` (unique keys); `reverse[payload]` is the position of a payload.

---@class PW.BinaryHeap
---@field values any[] sort keys, values[1] is the top
---@field payloads any[] payload at each position
---@field reverse table<any, integer> position of each payload
---@field lt fun(a: any, b: any): boolean
---@field insert fun(self: PW.BinaryHeap, value: any, payload: any)
---@field update fun(self: PW.BinaryHeap, payload: any, value: any)
---@field remove fun(self: PW.BinaryHeap, payload: any): any, any
---@field pop fun(self: PW.BinaryHeap): any, any
---@field peek fun(self: PW.BinaryHeap): any, any
---@field peekValue fun(self: PW.BinaryHeap): any
---@field valueByPayload fun(self: PW.BinaryHeap, payload: any): any
---@field size fun(self: PW.BinaryHeap): integer

---@type fun(x: number): integer
local floor = math.floor

local lib = {}

---Swaps two positions: values, payloads and the reverse map.
---@param heap PW.BinaryHeap
---@param a integer
---@param b integer
local function swap(heap, a, b)
    local payloadA, payloadB = heap.payloads[a], heap.payloads[b]
    heap.reverse[payloadA], heap.reverse[payloadB] = b, a
    heap.payloads[a], heap.payloads[b] = payloadB, payloadA
    heap.values[a], heap.values[b] = heap.values[b], heap.values[a]
end

---@param heap PW.BinaryHeap
---@param pos integer
local function bubbleUp(heap, pos)
    local values = heap.values
    while pos > 1 do
        local parent = floor(pos / 2) --[[@as integer]]
        if not heap.lt(values[pos], values[parent]) then break end
        swap(heap, parent, pos)
        pos = parent
    end
end

---@param heap PW.BinaryHeap
---@param pos integer
local function sinkDown(heap, pos)
    local values = heap.values
    ---@type integer
    local last = #values
    while true do
        ---@type integer
        local min = pos
        ---@type integer
        local child = 2 * pos
        for c = child, child + 1 do
            if c <= last and heap.lt(values[c], values[min]) then min = c end
        end
        if min == pos then break end
        swap(heap, pos, min)
        pos = min
    end
end

---@param heap PW.BinaryHeap
---@param pos integer
---@return any value
local function removeAt(heap, pos)
    ---@type integer
    local last = #heap.values
    if pos < 1 or pos > last then return nil end
    local value = heap.values[pos]
    if pos < last then swap(heap, pos, last) end
    heap.reverse[heap.payloads[last]] = nil
    heap.payloads[last] = nil
    heap.values[last] = nil
    if pos < last then
        bubbleUp(heap, pos)
        sinkDown(heap, pos)
    end
    return value
end

---Updates the value of a payload that is in the heap.
---@param self PW.BinaryHeap
---@param payload any
---@param newValue any
local function update(self, payload, newValue)
    assert(newValue ~= nil, "cannot add 'nil' as value")
    ---@type integer?
    local pos = self.reverse[payload]
    assert(pos ~= nil, "illegal payload")
    self.values[pos] = newValue
    if pos > 1 then bubbleUp(self, pos) end
    if pos < #self.values then sinkDown(self, pos) end
end

---Inserts a payload with a value; the payload must not be in the heap.
---@param self PW.BinaryHeap
---@param value any
---@param payload any
local function insert(self, value, payload)
    assert(value ~= nil, "cannot add 'nil' as value")
    assert(self.reverse[payload] == nil, "duplicate payload")
    ---@type integer
    local pos = #self.values + 1
    self.reverse[payload] = pos
    self.payloads[pos] = payload
    self.values[pos] = value
    bubbleUp(self, pos)
end

---Removes a payload from the heap.
---@param self PW.BinaryHeap
---@param payload any
---@return any value, any payload value and payload, or nil when the payload is not in the heap
local function remove(self, payload)
    ---@type integer?
    local pos = self.reverse[payload]
    if pos == nil then return nil, nil end
    local value = removeAt(self, pos)
    return value, payload
end

---Removes the top and returns its payload and value; nil when the heap is empty.
---@param self PW.BinaryHeap
---@return any payload, any value
local function pop(self)
    if self.values[1] == nil then return nil, nil end
    local payload = self.payloads[1]
    local value = removeAt(self, 1)
    return payload, value
end

---@param self PW.BinaryHeap
---@return any payload, any value
local function peek(self)
    return self.payloads[1], self.values[1]
end

---@param self PW.BinaryHeap
---@return any
local function peekValue(self)
    return self.values[1]
end

---@param self PW.BinaryHeap
---@param payload any
---@return any
local function valueByPayload(self, payload)
    return self.values[self.reverse[payload]]
end

---@param self PW.BinaryHeap
---@return integer
local function size(self)
    return #self.values
end

---Creates a min-heap with unique payloads: the smallest value is at the top.
---@param lt? fun(a: any, b: any): boolean comparison (less than), default a < b
---@return PW.BinaryHeap
function lib.minUnique(lt)
    ---@type PW.BinaryHeap
    return {
        values = {}, payloads = {}, reverse = {},
        lt = lt or function(a, b) return a < b end,
        insert = insert, update = update, remove = remove, pop = pop, peek = peek, peekValue = peekValue,
        valueByPayload = valueByPayload, size = size
    }
end

return lib
