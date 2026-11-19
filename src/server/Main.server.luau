-- Main: bootstraps the server. Builds the world, wires the shared Remotes and
-- starts each service in dependency order. Only RemoteEvents for HUD requests
-- (rebirth) and one-way effects travel between client and server; every rule is
-- enforced here on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

-- Remotes -------------------------------------------------------------------
local existing = ReplicatedStorage:FindFirstChild("Remotes")
if existing then
	existing:Destroy()
end
local RemotesFolder = Instance.new("Folder")
RemotesFolder.Name = "Remotes"
RemotesFolder.Parent = ReplicatedStorage

local function remote(name: string): RemoteEvent
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = RemotesFolder
	return event
end

local Remotes = {
	Rebirth = remote(Config.REMOTES.Rebirth),
	FX = remote(Config.REMOTES.FX),
	ShopBuy = remote(Config.REMOTES.ShopBuy),
	QuestClaim = remote(Config.REMOTES.QuestClaim),
	TutorialAction = remote(Config.REMOTES.TutorialAction),
	State = remote(Config.REMOTES.State),
	Leaderboard = remote(Config.REMOTES.Leaderboard),
}

-- Services ------------------------------------------------------------------
local Services = {
	Config = Config,
	Util = Util,
	Remotes = Remotes,
}

local MapService = require(script.Parent:WaitForChild("MapService"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local BrainrotService = require(script.Parent:WaitForChild("BrainrotService"))
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
Services.WaveService = WaveService
Services.UpgradeService = UpgradeService
Services.QuestService = QuestService
Services.LeaderboardService = LeaderboardService
Services.OnboardingService = OnboardingService
Services.StateService = StateService
Services.PlayerService = PlayerService

-- The order matters: the map exists before pads and the leaderboard board,
-- persistence exists before any service reads upgrades, pads exist before
-- brainrots can be banked, and players join last so every per-player service
-- (shop, quests, index, onboarding, leaderboard) is already listening.
local bootOrder = {
	{ "MapService", function()
		MapService.build(Services)
	end },
	{ "DataService", function()
		DataService.init(Services)
	end },
	{ "BaseService", function()
		BaseService.init(Services)
	end },
	{ "BrainrotService", function()
		BrainrotService.init(Services)
	end },
	{ "WaveService", function()
		WaveService.init(Services)
	end },
	{ "UpgradeService", function()
		UpgradeService.init(Services)
	end },
	{ "QuestService", function()
		QuestService.init(Services)
	end },
	{ "LeaderboardService", function()
		LeaderboardService.init(Services)
	end },
	{ "OnboardingService", function()
		OnboardingService.init(Services)
	end },
	{ "StateService", function()
		StateService.init(Services)
	end },
	{ "PlayerService", function()
		PlayerService.init(Services)
	end },
}

for _, step in ipairs(bootOrder) do
	local ok, err = pcall(step[2])
	if not ok then
		warn(string.format("[Brainrot Cash Rush] %s failed to start: %s", step[1], tostring(err)))
	end
end

Workspace:SetAttribute("BrainrotCashRush", true)
print(string.format("[Brainrot Cash Rush] server ready — %d brainrots, 6 bases, 6 upgrades, 3 quests/player, 1 wave every 90s", #Config.BRAINROTS))
