---@meta
-- Globals GLuaTest injects into the environment of every test case (type checker only, never loaded).

---@type fun(subject: any, ...): GLuaTest_Expect
expect = nil

---@type StubFunction
stub = nil

---Async cases: signals that the case finished.
---@type fun()
done = nil

---Async cases: fails the case with a reason.
---@type fun(reason?: string)
fail = nil
