-- Synthetic host rows: no dependency on shipped weekly templates, catalogues or client files.
---@class PW.ChallengeViewTestModel
---@field weekLabel string
---@field countdown string
---@field label string
---@field rows { id: string, name: string, description: string, tier: string, fraction: number, progressText: string,
---    done: boolean, reward: string, objectives: { scope: string }[] }[]
---@field bonus { completed: integer, needed: integer, fraction: number, done: boolean, reward: string }

---@class PW.ChallengeViewTestDeps
---@field getProgress fun(id: string): PW.ChallengeProgress?
---@field getTemplate fun(id: string): PW.Challenge?
---@field describe fun(item: PW.ChallengeRewardItem): string

---@class PW.ChallengeViewTestToast
---@field id string
---@field kind "milestone"|"complete"|"bonus"
---@field threshold? integer
---@field duration number

---@alias PW.ChallengeViewTestBuild fun(week: PW.ChallengeWeek, now: integer,
---    deps: PW.ChallengeViewTestDeps): PW.ChallengeViewTestModel
---@alias PW.ChallengeViewTestUpdate fun(queue: PW.ChallengeViewTestToast[], before: PW.ChallengeViewTestModel?,
---    after: PW.ChallengeViewTestModel): PW.ChallengeViewTestToast[]
---@alias PW.ChallengePreviewTestRows fun(snapshot: PW.ChallengeViewTestModel?): { text: string, fraction: number }[]

local reset = 1795392000

---@param id string
---@param target integer
---@return PW.ChallengeInstance
local function instance(id, target)
    return { id = id, template = "fixture_drill", tier = "medium", params = { category = "smg" },
        targets = { target }, reward = { xp = 5000, currency = 100 } }
end

---@param items? PW.ChallengeInstance[]
---@return PW.ChallengeWeek
local function week(items)
    return { label = "2026-W47", index = 2967, startsAt = reset - 7 * 86400, endsAt = reset,
        seed = 0, items = items or { instance("fixture_drill.smg", 25) },
        bonus = { needed = 4,
            reward = { xp = 10000, currency = 300, items = { { kind = "cards", id = "fixture_card" } } } }
    }
end

---@param items table<string, PW.ChallengeProgress>
---@return PW.ChallengeViewTestDeps
local function deps(items)
    local template = {
        ClassName = "fixture_drill",
        Name = "Fixture Drill: {param.category}",
        Description = "Reach {target} with {param.category}",
        Params = { category = { values = { "smg" }, names = { smg = "SMG" } } },
        Scope = "match",
        Event = "kill",
        Target = 25
    } --[[@as PW.Challenge]]
    return {
        getProgress = function(id) return items[id] end,
        getTemplate = function(id) return id == "fixture_drill" and template or nil end,
        describe = function(item) return item.id == "fixture_card" and "Fixture Calling Card" or item.id end
    }
end

---@param item PW.ChallengeInstance
---@param count integer
---@param done? boolean
---@return PW.ChallengeProgress
local function progress(item, count, done)
    return { values = { count }, targets = item.targets, done = done == true }
end

---@param active PW.ChallengeWeek
---@param counts integer[]
---@return PW.ChallengeViewTestModel
local function view(active, counts)
    local build = rawget(assert(PW.Challenges), "_BuildChallengeView") --[[@as PW.ChallengeViewTestBuild?]]
    assert(build ~= nil, "weekly challenges must build a pure screen view")
    ---@type table<string, PW.ChallengeProgress>
    local rows = {}
    for i, item in ipairs(active.items) do
        local count = counts[i] or 0
        rows[item.id] = progress(item, count, count >= item.targets[1])
    end
    return build(active, reset - 2 * 86400 - 14 * 3600, deps(rows))
end

---@param queue PW.ChallengeViewTestToast[]
---@param before PW.ChallengeViewTestModel?
---@param after PW.ChallengeViewTestModel
---@return PW.ChallengeViewTestToast[]
local function toasts(queue, before, after)
    local update = rawget(assert(PW.Challenges), "_UpdateChallengeToasts") --[[@as PW.ChallengeViewTestUpdate?]]
    assert(update ~= nil, "weekly challenges must enqueue toasts from successive snapshots")
    return update(queue, before, after)
end

---@return PW.ChallengeWeek
local function collection()
    return week({ instance("fixture_a", 8), instance("fixture_b", 8), instance("fixture_c", 8),
        instance("fixture_d", 8), instance("fixture_e", 3) })
end

---@class PW.ChallengeEntryTestPanel
---@field text? string
---@field DoClick? fun(self: PW.ChallengeEntryTestPanel)

---@param model PW.UIRouterModel
---@return PW.ChallengeEntryTestPanel[]
local function buildHome(model)
    local source = assert(CompileFile("privatewar/screens/progress_home.lua"))
    local screen = {}
    local active = week()
    local localPlayer = {} --[[@as Player]]
    ---@type PW.ChallengeEntryTestPanel[]
    local focusable = {}
    local kit = assert(PW.UI)
    local ui = setmetatable({
        Focusable = function(panel) focusable[#focusable + 1] = panel --[[@as PW.ChallengeEntryTestPanel]] end
    }, { __index = kit })
    local env = setmetatable({
        SCREEN = screen, LocalPlayer = function() return localPlayer end,
        IsValid = function(value) return value ~= nil end,
        PW = { UI = ui, Modules = PW.Modules, Challenges = {
            GetWeek = function() return active end,
            GetProgress = function(ply, id)
                assert(ply == localPlayer and id == active.items[1].id)
                return progress(active.items[1], 25, true)
            end
        } },
        vgui = { Create = function()
            local panel = { SetText = function(self, text) self.text = text end }
            return setmetatable(panel, { __index = function() return function() end end })
        end }
    }, { __index = _G })
    setfenv(source, env)()
    local root = { model = model, Rebuild = function() end }
    local build = assert(rawget(screen, "Build")) --[[@as fun(self: table, ctx: table)]]
    build(screen, { root = root, parent = {}, router = model, SetFocus = function() end })
    return focusable
end

local function hudFixture()
    local path = "privatewar/hud/challenges.lua"
    assert(file.Exists(path, "LUA"), "weekly challenges must register a toast HUD element")
    local source = assert(CompileFile(path))
    ---@type { Order: integer?, Phases: PW.PhaseName[]? }
    local hud = {}
    local active = week()
    local item = active.items[1]
    local owner = {} --[[@as Player]]
    local fixture = { hud = hud, reads = 0, count = 0 }
    ---@type table<string, function>
    local handlers = {}
    local lib = setmetatable({
        GetWeek = function() return active end,
        GetProgress = function(ply, id)
            assert(ply == owner and id == item.id)
            fixture.reads = fixture.reads + 1
            return progress(item, fixture.count, fixture.count == item.targets[1])
        end
    }, { __index = assert(PW.Challenges) })
    local api = {
        Challenges = lib, UI = PW.UI, Modules = PW.Modules, Phase = { GetPhase = function() return "LIVE" end },
        HUD = { PlayerVisible = function() return true end },
        HookFor = function(_, name, fn) handlers[name --[[@as string]]] = fn --[[@as function]] end,
        Notify = function(name, payload)
            local receive = assert(handlers[name --[[@as string]]], "toast HUD must observe PW_ChallengesChanged")
            receive(hud, payload)
        end
    }
    local env = setmetatable({
        PW = api, CLIENT = true, SERVER = false, HUDELEMENT = hud,
        LocalPlayer = function() return owner end, IsValid = function(value) return value ~= nil end,
        surface = { PlaySound = function() end }
    }, { __index = _G })
    setfenv(source, env)()
    return fixture, function() api.Notify("PW_ChallengesChanged", active) end
end

return {
    groupName = "PW weekly challenges view and toast rules",
    cases = {
        {
            name = "View: rows hold text with placeholders filled, fraction, tier, scope text and reward summary",
            func = function()
                local model = view(week(), { 12 })
                local row = model.rows[1]
                expect(model.weekLabel).to.equal("WEEK 47 · 2026")
                expect(row.id).to.equal("fixture_drill.smg")
                expect(row.name).to.equal("Fixture Drill: SMG")
                expect(row.description).to.equal("Reach 25 with SMG")
                expect(row.tier).to.equal("medium")
                expect(row.fraction).to.equal(12 / 25)
                expect(row.progressText).to.equal("12 / 25")
                expect(row.objectives[1].scope).to.equal("in a single match")
                expect(row.reward).to.equal("+5 000 XP · 100 CR")
                expect(row.done).to.beFalse()
            end
        },
        {
            name = "View: countdown text for days, hours and minutes, never negative",
            func = function()
                local countdown = rawget(assert(PW.Challenges), "_ChallengeCountdown")
                    --[[@as (fun(endsAt: integer, now: integer): string)?]]
                assert(countdown ~= nil, "weekly challenges must format their reset countdown")
                expect(view(week(), {}).countdown).to.equal("Resets in 2d 14h")
                expect(countdown(reset, reset - 3600 - 120)).to.equal("Resets in 1h 2m")
                expect(countdown(reset, reset - 540)).to.equal("Resets in 9m")
                expect(countdown(reset, reset)).to.equal("Resets in 0m")
                expect(countdown(reset, reset + 3600)).to.equal("Resets in 0m")
            end
        },
        {
            name = "View: bonus card shows completed of needed and the reward",
            func = function()
                local active = collection()
                local bonus = view(active, { 8, 8, 4, 0, 0 }).bonus
                expect(bonus.completed).to.equal(2)
                expect(bonus.needed).to.equal(4)
                expect(bonus.fraction).to.equal(0.5)
                expect(bonus.done).to.beFalse()
                expect(bonus.reward).to.equal("+10 000 XP · 300 CR · Fixture Calling Card")
                local completed = view(active, { 8, 8, 8, 8, 3 }).bonus
                expect(completed.completed).to.equal(5)
                expect(completed.fraction).to.equal(1)
                expect(completed.done).to.beTrue()
            end
        },
        {
            name = "Toast: milestones at 25, 50 and 75 percent and completion; "
                .. "no toast for unchanged values; queue limit",
            func = function()
                local active = collection()
                local zero, quarter, half, threeQuarters =
                    view(active, {}), view(active, { 2 }), view(active, { 4 }), view(active, { 6 })
                expect(#toasts({}, nil, quarter)).to.equal(0)
                expect(#toasts({}, zero, zero)).to.equal(0)
                local queue = toasts({}, zero, quarter)
                expect(#queue).to.equal(1)
                expect(queue[1].kind).to.equal("milestone")
                expect(queue[1].threshold).to.equal(25)
                expect(queue[1].duration).to.equal(2.5)
                queue = toasts(queue, quarter, quarter)
                expect(#queue).to.equal(1)
                queue = toasts(queue, quarter, half)
                expect(#queue).to.equal(1)
                expect(queue[1].threshold).to.equal(50)
                queue = toasts(queue, half, threeQuarters)
                expect(#queue).to.equal(1)
                expect(queue[1].threshold).to.equal(75)
                local fourMilestones = view(active, { 6, 2, 2, 2, 1 })
                queue = toasts(queue, threeQuarters, fourMilestones)
                expect(#queue).to.equal(3)
                expect(#toasts({}, zero, view(active, { 0, 0, 0, 0, 2 }))).to.equal(0)
                local completed = view(active, { 8, 2, 2, 2, 1 })
                queue = toasts(queue, fourMilestones, completed)
                expect(#queue).to.equal(1)
                expect(queue[1].kind).to.equal("complete")
                expect(queue[1].id).to.equal("fixture_a")
                expect(queue[1].duration).to.equal(4)
                expect(#toasts({}, completed, completed)).to.equal(0)
                local allDone = view(active, { 8, 8, 8, 8, 3 })
                queue = toasts(queue, completed, allDone)
                expect(#queue).to.equal(3)
                expect(queue[#queue].kind).to.equal("bonus")
            end
        },
        {
            name = "Weekly challenge HUD listens to owner snapshots and is active in Live and Postmatch only",
            func = function()
                local f, notify = hudFixture()
                expect(f.hud.Order).to.equal(32)
                expect(f.hud.Phases).to.deepEqual({ "LIVE", "POSTMATCH" })
                local before = f.reads
                notify()
                expect(f.reads).to.equal(before + 1)
                f.count = 8
                notify()
                expect(f.reads).to.equal(before + 2)
            end
        },
        {
            name = "PLAY weekly preview shows short text and independent progress for each challenge",
            func = function()
                local lib = assert(PW.Challenges)
                local rows = rawget(lib, "_PlayPreviewRows") --[[@as PW.ChallengePreviewTestRows?]]
                assert(rows ~= nil, "PLAY must expose the weekly preview rows")
                local active = week({ instance("fixture_a", 8), instance("fixture_b", 20) })
                local preview = rows(view(active, { 2, 15 }))
                expect(#preview).to.equal(2)
                expect(preview[1].text).to.equal("Reach 8 with SMG")
                expect(preview[1].fraction).to.equal(0.25)
                expect(preview[2].text).to.equal("Reach 20 with SMG")
                expect(preview[2].fraction).to.equal(0.75)
                expect(#rows(nil)).to.equal(0)
            end
        },
        {
            name = "PLAY weekly preview opens Progress Weekly Challenges without stacking duplicates",
            func = function()
                local kit = assert(PW.UI)
                local registry = assert(PW.Registries.screens)
                local model = kit.Router.New(registry.GetEnabledList() --[[@as PW.Screen[] ]], { "play", "progress" })
                local open = rawget(assert(PW.Challenges), "_OpenPlayPreview")
                    --[[@as (fun(model: PW.UIRouterModel): boolean)?]]
                assert(open ~= nil, "PLAY must route directly to Weekly Challenges")
                expect(kit.Router.SwitchTab(model, "play")).to.beTrue()
                expect(assert(kit.Router.Top(model)).ClassName).to.equal("lobby_hub")
                expect(open(model)).to.beTrue()
                expect(assert(kit.Router.Top(model)).ClassName).to.equal("progress_challenges")
                expect(kit.Router.SwitchTab(model, "play")).to.beTrue()
                expect(open(model)).to.beTrue()
                local action = assert(kit.Input.Press(kit.Input.New(), KEY_XBUTTON_B))
                expect(kit.Router.Act(model, action, "LOBBY")).to.equal("pop")
                expect(assert(kit.Router.Top(model)).ClassName).to.equal("progress_home")
            end
        },
        {
            name = "Weekly challenges entry shows owner completion and controller Back returns to Progress",
            func = function()
                local kit = assert(PW.UI)
                local registry = assert(PW.Registries.screens)
                local details = assert(registry.Get("progress_challenges"), "weekly challenges must register a screen")
                    --[[@as PW.Screen]]
                expect(details.Tab).to.equal("progress")
                expect(details.Root ~= true).to.beTrue()
                expect(details.Hints).to.deepEqual({ { action = "accept", label = "Details" },
                    { action = "back", label = "Back" } })
                local model = kit.Router.New(registry.GetEnabledList() --[[@as PW.Screen[] ]], { "progress" })
                expect(assert(kit.Router.Top(model)).ClassName).to.equal("progress_home")
                local buttons = buildHome(model)
                expect(#buttons).to.equal(1)
                local entry = buttons[1]
                expect(entry.text).to.equal("WEEKLY CHALLENGES · 1 / 1")
                assert(entry.DoClick)(entry)
                expect(assert(kit.Router.Top(model)).ClassName).to.equal("progress_challenges")
                local action = assert(kit.Input.Press(kit.Input.New(), KEY_XBUTTON_B))
                expect(kit.Router.Act(model, action, "LOBBY")).to.equal("pop")
                expect(assert(kit.Router.Top(model)).ClassName).to.equal("progress_home")
            end
        }
    }
}
