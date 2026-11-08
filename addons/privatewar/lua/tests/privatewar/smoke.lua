-- Smoke test of the harness (T-0.4): the gamemode is loaded and exposes its namespace.

return {
    groupName = "PW smoke",
    cases = {
        {
            name = "Exposes the PW namespace with a version",
            func = function()
                expect(PW).to.exist()
                expect(PW.Version).to.beA("string")
                expect(string.match(PW.Version, "^%d+%.%d+%.%d+$") ~= nil).to.beTrue()
                for part in string.gmatch(PW.Version, "%d+") do
                    expect(#part == 1 or string.sub(part, 1, 1) ~= "0").to.beTrue()
                end
            end
        },
        {
            name = "Runs inside the Private War gamemode",
            func = function()
                expect(GAMEMODE.Name).to.equal("Private War")
            end
        }
    }
}
