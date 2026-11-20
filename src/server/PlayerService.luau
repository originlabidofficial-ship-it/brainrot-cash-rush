--!strict
-- PlayerService — per-player round state and the only path that can rebirth.
--
-- It owns cash balances, the leaderstats mirror, character setup, pad claiming
-- on join and the ordered shutdown of every per-player service on leave.
-- Cash is kept in a server table (not in a client value), and every mutation
-- goes through setCash/addCash/spendCash so the leaderstats, attributes and
-- the leaderboard stay in sync.

local Players = game:GetService("Players")

local PlayerService = {}

local Config: any = nil
local Util: any = nil
local deps: any = nil

local state = {
	running = false,
	balances = {} :: { [Player]: number },
	joined = {} :: { [Player]: boolean },
	lastRebirthAt = {} :: { [Player]: number },
	characterLinks = {} :: { [Player]: { RBXScriptConnection } },
}

local function alive(player: Player?): boolean
	return player ~= nil and player.Parent ~= nil
end

local function readStat(player: Player, name: string): any
	local folder = player:FindFirstChild("leaderstats")
	return folder and folder:FindFirstChild(name) or nil
end

-- Push the authoritative numbers into leaderstats and attributes in one place.
local function publish(player: Player)
	if not alive(player) then
		return
	end
	local cash = math.floor(state.balances[player] or 0)
	local rebirth = math.floor(tonumber(player:GetAttribute("Rebirths")) or 0)
	local multiplier = tonumber(player:GetAttribute("Multiplier")) or 1

	local cashValue = readStat(player, "Cash")
	if cashValue and cashValue:IsA("IntValue") then
		cashValue.Value = cash
	end
	local rebirthValue = readStat(player, "Rebirths")
	if rebirthValue and rebirthValue:IsA("IntValue") then
		rebirthValue.Value = rebirth
	end
	local multiplierValue = readStat(player, "Multiplier")
	if multiplierValue and multiplierValue:IsA("NumberValue") then
		multiplierValue.Value = multiplier
	end
	player:SetAttribute("Cash", cash)
end

-- Public money API ---------------------------------------------------------

function PlayerService.getCash(player: Player): number
	return math.floor(state.balances[player] or 0)
end

function PlayerService.getMultiplier(player: Player): number
	return tonumber(player:GetAttribute("Multiplier")) or 1
end

function PlayerService.getRebirths(player: Player): number
	return tonumber(player:GetAttribute("Rebirths")) or 0
end

function PlayerService.setCash(player: Player, amount: number)
	if not alive(player) then
		return
	end
	state.balances[player] = math.max(0, tonumber(amount) or 0)
	publish(player)
end

function PlayerService.addCash(player: Player, amount: number)
	if not alive(player) then
		return
	end
	local delta = tonumber(amount) or 0
	if delta == 0 then
		return
	end
	state.balances[player] = math.max(0, (state.balances[player] or 0) + delta)
	publish(player)
	if delta > 0 and deps.LeaderboardService then
		pcall(function()
			deps.LeaderboardService.recordEarn(player, delta)
		end)
	end
end

-- Atomic debit: returns false and changes nothing when the player is short, so
-- a stale client price can never overdraw an account.
function PlayerService.spendCash(player: Player, amount: number): boolean
	if not alive(player) then
		return false
	end
	local price = tonumber(amount) or 0
	if price <= 0 then
		return false
	end
	local balance = state.balances[player] or 0
	if balance < price then
		return false
	end
	state.balances[player] = balance - price
	publish(player)
	return true
end

function PlayerService.setPadsInfo(player: Player)
	if not alive(player) then
		return
	end
	player:SetAttribute("Carried", tonumber(player:GetAttribute("Carried")) or 0)
	player:SetAttribute("Placed", tonumber(player:GetAttribute("Placed")) or 0)
	player:SetAttribute("IncomePerSec", tonumber(player:GetAttribute("IncomePerSec")) or 0)
end

-- Rebirth ------------------------------------------------------------------

function PlayerService.tryRebirth(player: Player)
	if not alive(player) then
		return
	end
	local now = os.clock()
	if now - (state.lastRebirthAt[player] or 0) < Config.LIMITS.rebirth then
		return
	end
	state.lastRebirthAt[player] = now

	local cash = PlayerService.getCash(player)
	local cost = Config.REBIRTH_COST
	if cash < cost then
		Util.toast(deps.Remotes, player, string.format("Need $%d to rebirth (you have $%s).", cost, Util.formatCash(cash)), "bad", Config.TOAST.short)
		return
	end

	local rebirths = PlayerService.getRebirths(player) + 1
	local multiplier = 1 + Config.REBIRTH_BONUS * rebirths

	-- Return every placed creature to the wild *before* wiping the base, so no
	-- model is orphaned and no pad slot stays marked occupied.
	pcall(function()
		deps.BrainrotService.clearBaseForRebirth(player)
	end)

	state.balances[player] = 0
	player:SetAttribute("Rebirths", rebirths)
	player:SetAttribute("Multiplier", multiplier)
	player:SetAttribute("IncomePerSec", 0)
	player:SetAttribute("Placed", 0)
	publish(player)

	pcall(function()
		deps.BaseService.onRebirth(player, rebirths)
	end)
	pcall(function()
		deps.QuestService.recordEvent(player, "rebirth", 1)
	end)
	pcall(function()
		deps.OnboardingService.progress(player, "rebirth")
	end)

	Util.toast(deps.Remotes, player, string.format("REBIRTH %d! Permanent x%.2f cash multiplier.", rebirths, multiplier), "rebirth", Config.TOAST.rebirth)
	Util.broadcastToast(deps.Remotes, string.format("%s rebirthed to level %d!", player.DisplayName, rebirths), "rebirth", Config.TOAST.long)
	Util.fireAll(deps.Remotes.FX, {
		kind = "rebirth",
		level = rebirths,
		position = deps.BaseService.getPadCenter(player),
	})

	pcall(function()
		deps.DataService.updateBest(player, deps.LeaderboardService.getTotalEarned(player), rebirths)
	end)
	pcall(function()
		deps.StateService.push(player)
	end)
end

-- Join / leave -------------------------------------------------------------

local function makeLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = 0
	cash.Parent = folder

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = 0
	rebirths.Parent = folder

	local multiplier = Instance.new("NumberValue")
	multiplier.Name = "Multiplier"
	multiplier.Value = 1
	multiplier.Parent = folder

	folder.Parent = player
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 58
		humanoid.MaxHealth = 100
		humanoid.Health = 100
		local speed = 16
		if deps.UpgradeService then
			speed = deps.UpgradeService.getSpeed(player)
		end
		humanoid.WalkSpeed = speed
	end

	-- BrainrotService watches Died and scatters anything being carried.
	pcall(function()
		deps.BrainrotService.watchCharacter(player, character)
	end)

	if not deps.BaseService.getPad(player) then
		pcall(function()
			deps.BaseService.assignPad(player)
		end)
	end
end

local function trackCharacter(player: Player, character: Model)
	local links = state.characterLinks[player]
	if links then
		for _, link in ipairs(links) do
			pcall(function()
				link:Disconnect()
			end)
		end
	end
	state.characterLinks[player] = {}
	setupCharacter(player, character)
end

local function onPlayerAdded(player: Player)
	if not alive(player) or state.joined[player] then
		return
	end
	state.joined[player] = true

	makeLeaderstats(player)
	state.balances[player] = 0
	player:SetAttribute("Cash", 0)
	player:SetAttribute("Carried", 0)
	player:SetAttribute("Placed", 0)
	player:SetAttribute("IncomePerSec", 0)
	player:SetAttribute("Rebirths", 0)
	player:SetAttribute("Multiplier", 1)
	player:SetAttribute("StealCooldown", 0)
	PlayerService.setPadsInfo(player)
	publish(player)

	-- Persistence first: every per-player service below reads from the profile.
	pcall(function()
		deps.DataService.load(player)
	end)

	if player.Character then
		trackCharacter(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		trackCharacter(player, character)
	end)

	pcall(function()
		deps.UpgradeService.onPlayerAdded(player)
	end)
	pcall(function()
		deps.QuestService.onPlayerAdded(player)
	end)
	pcall(function()
		deps.LeaderboardService.onPlayerAdded(player)
	end)
	pcall(function()
		deps.OnboardingService.onPlayerAdded(player)
	end)
	pcall(function()
		deps.BaseService.assignPad(player)
	end)

	-- The HUD may still be binding remotes; one delayed snapshot is cheaper
	-- than a polling loop on every join.
	task.delay(0.8, function()
		if alive(player) then
			pcall(function()
				deps.StateService.push(player)
			end)
			pcall(function()
				deps.LeaderboardService.pushTo(player)
			end)
		end
	end)

	local cap = deps.UpgradeService and deps.UpgradeService.getCarryCap(player) or Config.MAX_CARRIED
	local slots = deps.UpgradeService and deps.UpgradeService.getPadSlots(player) or Config.MAX_BASE
	Util.toast(
		deps.Remotes,
		player,
		string.format("Welcome! You have %d backpack slots and %d pad slots. Grab wild brainrots, bank them, press E for the Index.", cap, slots),
		"info",
		Config.TOAST.welcome
	)
end

local function onPlayerRemoving(player: Player)
	-- Order matters: creatures go home before the pad and the profile vanish.
	local cleanups = {
		"BrainrotService",
		"BaseService",
		"LeaderboardService",
		"CraftService",
		"QuestService",
		"OnboardingService",
		"UpgradeService",
	}
	for _, name in ipairs(cleanups) do
		local service = deps[name]
		if service and service.releasePlayer then
			pcall(service.releasePlayer, player)
		end
	end
	pcall(function()
		deps.DataService.save(player)
	end)

	local links = state.characterLinks[player]
	if links then
		for _, link in ipairs(links) do
			pcall(function()
				link:Disconnect()
			end)
		end
	end
	state.characterLinks[player] = nil
	state.balances[player] = nil
	state.joined[player] = nil
	state.lastRebirthAt[player] = nil
end

-- Lifecycle ----------------------------------------------------------------

function PlayerService.start(services: any)
	deps = services
	Config = services.Config
	Util = services.Util
	state.running = true
	state.balances = {}
	state.joined = {}
	state.lastRebirthAt = {}
	state.characterLinks = {}

	local rebirthRemote = deps.Remotes and deps.Remotes.Rebirth
	if rebirthRemote then
		rebirthRemote.OnServerEvent:Connect(function(player)
			PlayerService.tryRebirth(player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

function PlayerService.stop()
	state.running = false
	for player, links in pairs(state.characterLinks) do
		for _, link in ipairs(links) do
			pcall(function()
				link:Disconnect()
			end)
		end
		state.characterLinks[player] = nil
	end
end

return PlayerService
