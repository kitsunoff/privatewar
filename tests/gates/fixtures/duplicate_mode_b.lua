-- Gate fixture: a mode written the idiomatic way. Two such files define MODE:Start twice, which the type gate
-- accepts in entity folders and rejects everywhere else (scripts/check/types.sh).

MODE.Name = "Gate mode b"
MODE.Teams = 2

function MODE:Start()
    print(self.Name)
end
