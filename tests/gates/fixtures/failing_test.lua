-- Gate fixture: a GLuaTest case that always fails. scripts/deck/test.sh --expect-failure deploys it
-- temporarily to prove that a failing case makes the test run exit non-zero.

return {
    groupName = "PW failing fixture",
    cases = {
        {
            name = "Always fails",
            func = function()
                expect(1).to.equal(2)
            end
        }
    }
}
