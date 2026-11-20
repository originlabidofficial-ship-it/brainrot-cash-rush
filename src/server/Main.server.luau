--!strict
-- Main.server.luau — the only bootstrap script on the server.
--
-- Responsibilities, in order:
--   1. create the shared RemoteEvent folder exactly once,
--   2. require every service in a fixed dependency order,
--   3. start them in that same order, isolating failures with pcall,
--   4. stop them in reverse order when the server closes.
--
-- Services never start themselves at require time. Requiring a module here is
-- pure: all side effects happen inside start(), which keeps boot order explicit
-- and makes a single failed service a warning instead of a dead server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

-- Remotes ------------------------------------------------------------------

local oldFolder = ReplicatedStorage:FindFirstChild("Remotes")
if oldFolder then
	oldFolder:Destroy()
end

local remoteFolder = Instance.new("Folder")
remoteFolder.Name = "Remotes"
remoteFolder.Parent = ReplicatedStorage

local function makeRemote(name: string): RemoteEvent
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remoteFolder
	return event
end

local Remotes = {
	Rebirth = makeRemote(Config.REMOTES.Rebirth),
	FX = makeRemote(Config.REMOTES.FX),
	ShopBuy = makeRemote(Config.REMOTES.ShopBuy),
	QuestClaim = makeRemote(Config.REMOTES.QuestClaim),
	CraftRequest = makeRemote(Config.REMOTES.CraftRequest),
	TutorialAction = makeRemote(Config.REMOTES.TutorialAction),
	State = makeRemote(Config.REMOTES.State),
	Leaderboard = makeRemote(Config.REMOTES.Leaderboard),
}

-- Service container --------------------------------------------------------

local Services: any = {
	Config = Config,
	Util = Util,
	Remotes = Remotes,
}

-- Require order is part of the contract: map -> persistence -> bases ->
-- creatures -> waves -> upgrades -> quests -> leaderboard -> onboarding ->
-- state -> players. PlayerService goes last so every per-player service is
-- ready before the first player can join.
local MapService = require(script.Parent:WaitForChild("MapService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local BrainrotService = require(script.Parent:WaitForChild("BrainrotService"))
local MutationService = require(script.Parent:WaitForChild("MutationService"))
local CraftService = require(script.Parent:WaitForChild("CraftService"))
local WaveService = require(script.Parent:WaitForChild("WaveService"))
local UpgradeService = require(script.Parent:WaitForChild("UpgradeService"))
local QuestService = require(script.Parent:WaitForChild("QuestService"))
local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))
local OnboardingService = require(script.Parent:WaitForChild("OnboardingService"))
local StateService = require(script.Parent:WaitForChild("StateService"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))

Services.MapService = MapService
Services.DataService = DataService
Services.BaseService = BaseService
Services.BrainrotService = BrainrotService
Services.MutationService = MutationService
Services.CraftService = CraftService
Services.WaveService = WaveService
Services.UpgradeService = UpgradeService
Services.QuestService = QuestService
Services.LeaderboardService = LeaderboardService
Services.OnboardingService = OnboardingService
Services.StateService = StateService
Services.PlayerService = PlayerService

-- Start order --------------------------------------------------------------

local bootOrder = {
	{ "MapService", MapService },
	{ "DataService", DataService },
	{ "BaseService", BaseService },
	{ "BrainrotService", BrainrotService },
	{ "MutationService", MutationService },
	{ "CraftService", CraftService },
	{ "WaveService", WaveService },
	{ "UpgradeService", UpgradeService },
	{ "QuestService", QuestService },
	{ "LeaderboardService", LeaderboardService },
	{ "OnboardingService", OnboardingService },
	{ "StateService", StateService },
	{ "PlayerService", PlayerService },
}

local started: { any } = {}

for _, step in ipairs(bootOrder) do
	local label = step[1]
	local service = step[2]
	local ok, err = pcall(service.start, Services)
	if ok then
		table.insert(started, service)
	else
		warn(string.format("[Brainrot Cash Rush] %s failed to start: %s", label, tostring(err)))
	end
end

Workspace:SetAttribute("BrainrotCashRush", true)
Workspace:SetAttribute("BrainrotVersion", Config.VERSION)
print(string.format(
	"[Brainrot Cash Rush] server ready — %d brainrots, %d bases, %d upgrades, %d quests/player, 1 wave every %ds",
	#Config.BRAINROTS,
	Config.PAD_COUNT,
	#Config.UPGRADES,
	Config.QUEST_SLOTS,
	Config.WAVE_INTERVAL
))

-- Shutdown in reverse order: players first, then the world they were using.
local closing = false
game:BindToClose(function()
	if closing then
		return
	end
	closing = true
	for index = #started, 1, -1 do
		local service = started[index]
		if service.stop then
			pcall(service.stop)
		end
	end
	task.wait(0.5)
end)
