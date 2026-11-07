-- Bot name pool (06-progression.md d.7): original, generic first names, surnames and callsigns. Edit freely: one name
-- per string, no duplicates (case-insensitive), no real gamers or celebrities, no names of characters from games,
-- films or books. The manager picks a name no connected player has (sh_names.lua). Loaded by shared.lua.

local lib = PW.BotsManager --[[@as PW.BotsManagerLib]]

lib.NamePool = {
    -- First names
    "Mike", "Dave", "Tom", "Alex", "Sam", "Nick", "Rob", "Ben", "Leo", "Jake",
    "Owen", "Ryan", "Sean", "Tony", "Vince", "Wes", "Zach", "Carl", "Dan", "Erik",
    "Finn", "Hank", "Ivan", "Jonas", "Kurt", "Luis", "Marco", "Nate", "Oscar", "Pete",
    "Raul", "Stan", "Theo", "Walt", "Yusuf", "Aaron", "Boris", "Ana", "Bea", "Cara",
    "Dana", "Elle", "Gina", "Hana", "Jess", "Kim", "Lena", "Maya", "Rosa", "Tara",
    "Vera", "Zoe",
    -- Surnames
    "Sanchez", "Kowalski", "Novak", "Ortega", "Brennan", "Duarte", "Fischer", "Haddad", "Ibarra", "Jansen",
    "Kovac", "Lindqvist", "Moreau", "Nakamura", "Okafor", "Petrov", "Rossi", "Silva", "Tanaka", "Varga",
    "Weber", "Yilmaz", "Zielinski", "Becker", "Castillo", "Esposito",
    -- Callsigns
    "Doc", "Viper", "Hawk", "Mongoose", "Tank", "Sparks", "Lucky", "Fox", "Bear", "Moose",
    "Spud", "Torch", "Echo", "Ranger", "Slick", "Patch", "Dingo", "Rebel", "Brick", "Pike",
    "Badger", "Gopher"
}
