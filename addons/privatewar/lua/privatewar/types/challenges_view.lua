---@meta

---@class PW.ChallengeViewDeps
---@field getProgress fun(id: string): PW.ChallengeProgress?
---@field getTemplate fun(id: string): PW.Challenge?
---@field describe fun(item: PW.ChallengeRewardItem): string
---@field getName? fun(kind: string, id: string): string

---@class PW.ChallengeObjectiveView
---@field label string
---@field scope string
---@field fraction number
---@field progressText string

---@class PW.ChallengeRowView
---@field id string
---@field name string
---@field description string
---@field tier PW.ChallengeTier
---@field fraction number
---@field target integer
---@field progressText string
---@field done boolean
---@field reward string
---@field payout string
---@field objectives PW.ChallengeObjectiveView[]
---@field requirements string[]

---@class PW.ChallengeBonusView
---@field completed integer
---@field needed integer
---@field fraction number
---@field done boolean
---@field reward string
---@field itemNames string

---@class PW.ChallengeWeekView
---@field weekLabel string
---@field label string
---@field countdown string
---@field endsAt integer
---@field rows PW.ChallengeRowView[]
---@field bonus PW.ChallengeBonusView
---@field byId table<string, PW.ChallengeRowView>

---@class PW.ChallengePreviewRow
---@field text string
---@field fraction number
---@field progressText string

---@class PW.ChallengeToast
---@field id string
---@field kind "milestone"|"complete"|"bonus"
---@field threshold? integer
---@field duration number
---@field title string
---@field detail string
---@field reward? string
---@field fraction? number

---@alias PW.ChallengeViewBuilder fun(week: PW.ChallengeWeek, now: integer,
---    deps: PW.ChallengeViewDeps): PW.ChallengeWeekView
---@alias PW.ChallengeToastUpdater fun(queue: PW.ChallengeToast[], before: PW.ChallengeWeekView?,
---    after: PW.ChallengeWeekView): PW.ChallengeToast[]

---@class PW.ChallengesViewLib : PW.ChallengesLib
---@field _BuildChallengeView PW.ChallengeViewBuilder
---@field _ChallengeCountdown fun(endsAt: integer, now: integer): string
---@field _UpdateChallengeToasts PW.ChallengeToastUpdater
---@field _OwnerChallengeView fun(api: PW, owner: Player, now: integer): PW.ChallengeWeekView?
---@field _PlayPreviewRows fun(snapshot: PW.ChallengeWeekView?): PW.ChallengePreviewRow[]
---@field _OpenPlayPreview fun(model: PW.UIRouterModel): boolean
