-- Content-independent chatter rules; no Lambda assets or live bot slots required.
local function lib()
    assert(PW.BotChatter ~= nil, "chatter module must load")
    return PW.BotChatter
end

return {
    groupName = "PW bot chatter",
    cases = {
        {
            name = "Chatter safety: paths stay inside mounted Lambda sound roots",
            func = function()
                expect(lib()._SoundPath("lambdaplayers/voiceprofiles/test/idle/hello.mp3")).to.beTrue()
                expect(lib()._SoundPath("lambdaplayers/../secret.wav")).to.beFalse()
                expect(lib()._SoundPath("https://example.com/a.mp3")).to.beFalse()
                expect(lib()._SoundPath("lambdaplayers/vo/idle/a.lua")).to.beFalse()
            end
        },
        {
            name = "Chatter text: literal target substitution and unsupported syntax fail closed",
            func = function()
                expect(lib()._Text("hello /keyent/", "A%1")).to.equal("hello A%1")
                expect(lib()._Text("hello /keyent/", nil)).to.equal(nil)
                expect(lib()._Text("hello /keyent/", "bad\nname")).to.equal(nil)
                expect(lib()._Text("/unknown/", "A")).to.equal(nil)
                expect(lib()._Text("|lowhp| hello", nil)).to.equal(nil)
                expect(lib()._Text("hello\nworld", nil)).to.equal(nil)
                expect(lib()._Text("https://example.com", nil)).to.equal("https://example.com")
                expect(lib()._Text("{literal}", nil)).to.equal("{literal}")
                expect(lib()._Text("!command", nil)).to.equal(nil)
                expect(lib()._Text(string.rep("a", 127), nil)).to.equal(nil)
            end
        },
        {
            name = "Chatter names: reject malformed display names without content censorship",
            func = function()
                expect(lib()._Name("Joke Name")).to.equal("Joke Name")
                expect(lib()._Name(" ")).to.equal(nil)
                expect(lib()._Name("bad\nname")).to.equal(nil)
                expect(lib()._Name(string.rep("a", 33))).to.equal(nil)
                expect(lib()._Name(string.char(255))).to.equal(nil)
            end
        },
        {
            name = "Chatter names: collisions and exhausted external lists preserve built-in fallback",
            func = function()
                expect(lib()._NameFrom({ "Same", "Free" }, { same = true }, 0)).to.equal("Free")
                expect(lib()._NameFrom({ "Same" }, { same = true }, 0)).to.equal(nil)
                expect(lib()._NameFrom({}, {}, 0)).to.equal(nil)
            end
        },
        {
            name = "Chatter limits: bot cooldown global spacing and concurrency are independent",
            func = function()
                local state = { next = 10, speaking = 5 }
                expect(lib()._CanSpeak(state, 9, 0, 0, 2)).to.beFalse()
                expect(lib()._CanSpeak(state, 10, 11, 0, 2)).to.beFalse()
                expect(lib()._CanSpeak(state, 10, 0, 2, 2)).to.beFalse()
                expect(lib()._CanSpeak(state, 10, 0, 1, 2)).to.beTrue()
            end
        },
        {
            name = "Chatter discovery: installed names voice folders and text lists without Lambda globals",
            func = function()
                local files = {
                    ["materials/lambdaplayers/data/names.vmt"] = "[\"Joke Name\",\"bad\\nname\",\"\"]",
                    ["lambdaplayers/customnames.json"] = "[\"Custom\"]",
                    ["materials/lambdaplayers/data/texttypes/idle.vmt"] = "[\"hello\"]",
                    ["materials/lambdaplayers/textprofiles/test/kill.txt"] = "nice /keyent/"
                }
                stub(file, "Size").with(function(path) return #(files[path] or "") end)
                stub(file, "Read").with(function(path) return files[path] end)
                stub(file, "Find").with(function(path)
                    if path == "sound/lambdaplayers/voiceprofiles/*" then return {}, { "test" } end
                    if path == "materials/lambdaplayers/textprofiles/*" then return {}, { "test" } end
                    if path == "sound/lambdaplayers/voiceprofiles/test/idle/*" then
                        return { "hello.mp3", "unsafe.lua" }, {}
                    end
                    if path == "materials/lambdaplayers/data/texttypes/*" then return { "idle.vmt" }, {} end
                    if path == "materials/lambdaplayers/textprofiles/test/*" then return { "kill.txt" }, {} end
                    return {}, {}
                end)
                local data = lib()._Discover()
                expect(#data.names).to.equal(2)
                expect(data.names[1]).to.equal("Joke Name")
                expect(data.names[2]).to.equal("Custom")
                expect(#data.voices.test.idle).to.equal(1)
                expect(data.voices.test.idle[1]).to.equal("lambdaplayers/voiceprofiles/test/idle/hello.mp3")
                expect(data.text.idle[1]).to.equal("hello")
                expect(data.texts.test.kill[1]).to.equal("nice /keyent/")
            end
        },
        {
            name = "Chatter discovery: absent malformed and oversized content preserves silent fallback",
            func = function()
                stub(file, "Size").with(function(path)
                    if path == "lambdaplayers/customnames.json" then return 1048577 end
                    return 5
                end)
                stub(file, "Read").with(function() return "false" end)
                stub(file, "Find").with(function() return {}, {} end)
                local data = lib()._Discover()
                expect(#data.voiceIds).to.equal(0)
                expect(#data.textIds).to.equal(0)
                expect(#data.names).to.equal(0)
                expect(lib()._Line(nil, data.voice, "idle", 0)).to.equal(nil)
            end
        },
        {
            name = "Chatter spotting: only reaction-delayed direct sight counts, never hearing or sharing",
            func = function()
                expect(lib()._Visible({ { visible = true, source = "shared" } })).to.beFalse()
                expect(lib()._Visible({ { visible = false, source = "sight" } })).to.beFalse()
                expect(lib()._Visible({ { visible = true, source = "sound" } })).to.beFalse()
                expect(lib()._Visible({ { visible = true, source = "sight" } })).to.beTrue()
            end
        },
        {
            name = "Chatter identity: respawn retains voice and text without changing combat personality",
            func = function()
                local states = {}
                local original = lib()._Identity(states, "bot", { "voice" }, { "text" }, 0, 0)
                original.death = true
                original.death, original.seen = false, false
                local again = lib()._Identity(states, "bot", { "other" }, { "other" }, 1, 200)
                expect(again).to.equal(original)
                expect(again.voice).to.equal("voice")
                expect(again.text).to.equal("text")
                expect(lib()._Identity({}, "bot", {}, {}, 0, 0).voice).to.equal(nil)
            end
        },
        {
            name = "Chatter selection: missing profile category falls back to common pool or silence",
            func = function()
                local common = { idle = { "fallback" } }
                expect(lib()._Line({ idle = { "own" } }, common, "idle", 0)).to.equal("own")
                expect(lib()._Line({}, common, "idle", 0)).to.equal("fallback")
                expect(lib()._Line({}, common, "death", 0)).to.equal(nil)
            end
        }
    }
}
