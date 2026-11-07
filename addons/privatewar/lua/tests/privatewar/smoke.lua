-- Smoke test of the harness (T-0.4): the gamemode is loaded and exposes its namespace.

return {
    groupName = "PW smoke",
    cases = {
        {
            name = "Exposes the PW namespace with a version",
            func = function()
                expect(PW).to.exist()
                expect(PW.Version).to.beA("string")
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
