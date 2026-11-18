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
}

-- Services ------------------------------------------------------------------
local Services = {
	Config = Config,
	Util = Util,
	Remotes = Remotes,
}

local MapService = require(script.Parent:WaitForChild("MapService"))
local BaseService = require(script.Parent:WaitForChild("BaseService"))
local BrainrotService = require(script.Parent:WaitForChild("BrainrotService"))
local WaveService = require(script.Parent:WaitForChild("WaveService"))
local PlayerService = require(script.Parent:WaitForChild("PlayerService"))

Services.MapService = MapService
Services.BaseService = BaseService
Services.BrainrotService = BrainrotService
Services.WaveService = WaveService
Services.PlayerService = PlayerService

-- The order matters: the map exists before pads, pads exist before brainrots
-- can be banked, and players join last so their pad can be assigned at once.
local bootOrder = {
	{ "MapService", function()
		MapService.build(Services)
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
print("[Brainrot Cash Rush] server ready — 8 brainrots, 6 bases, 1 wave every 90s")
