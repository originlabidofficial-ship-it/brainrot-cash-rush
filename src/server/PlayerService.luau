-- PlayerService: owns the player's persistent round state (cash, rebirths,
-- multiplier), the leaderstats the HUD reads, character setup, pad assignment
-- on join and the rebirth RemoteEvent. Every number is decided here or in a
-- service it calls; the client only asks for a rebirth.

local Players = game:GetService("Players")

local PlayerService = {}

local deps: any = nil
local balances: { [Player]: number } = {}
local initialized: { [Player]: boolean } = {}

local function leaderstat(player: Player, name: string, className: string): any
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		return nil
	end
	return folder:FindFirstChild(name)
end

local function publish(player: Player)
	if not player.Parent then
		return
	end
	local cash = leaderstat(player, "Cash", "IntValue")
	local rebirths = leaderstat(player, "Rebirths", "IntValue")
	local multiplier = leaderstat(player, "Multiplier", "NumberValue")
	if cash then
		cash.Value = math.floor(balances[player] or 0)
	end
	if rebirths then
		rebirths.Value = player:GetAttribute("Rebirths") or 0
	end
	if multiplier then
		multiplier.Value = player:GetAttribute("Multiplier") or 1
	end
	player:SetAttribute("Cash", math.floor(balances[player] or 0))
end

function PlayerService.getCash(player: Player): number
	return math.floor(balances[player] or 0)
end

function PlayerService.getMultiplier(player: Player): number
	return tonumber(player:GetAttribute("Multiplier")) or 1
end

function PlayerService.getRebirths(player: Player): number
	return tonumber(player:GetAttribute("Rebirths")) or 0
end

function PlayerService.setCash(player: Player, amount: number)
	if not player.Parent then
		return
	end
	balances[player] = math.max(0, tonumber(amount) or 0)
	publish(player)
end

function PlayerService.addCash(player: Player, amount: number)
	if not player.Parent then
		return
	end
	if amount == 0 then
		return
	end
	balances[player] = math.max(0, (balances[player] or 0) + amount)
	publish(player)
	if amount > 0 and deps.LeaderboardService then
		pcall(function()
			deps.LeaderboardService.recordEarn(player, amount)
		end)
	end
end

-- Atomic server-side debit used by the shop. Returns false and touches nothing
-- when the player cannot afford it, so a stale client price can never overdraw.
function PlayerService.spendCash(player: Player, amount: number): boolean
	if not player or not player.Parent then
		return false
	end
	local price = tonumber(amount) or 0
	if price <= 0 then
		return false
	end
	local cash = balances[player] or 0
	if cash < price then
		return false
	end
	balances[player] = cash - price
	publish(player)
	return true
end

function PlayerService.setPadsInfo(player: Player)
	local carried = tonumber(player:GetAttribute("Carried")) or 0
	local placed = tonumber(player:GetAttribute("Placed")) or 0
	local income = tonumber(player:GetAttribute("IncomePerSec")) or 0
	player:SetAttribute("Carried", carried)
	player:SetAttribute("Placed", placed)
	player:SetAttribute("IncomePerSec", income)
end

function PlayerService.tryRebirth(player: Player)
	if not player or not player.Parent then
		return
	end
	local cash = PlayerService.getCash(player)
	if cash < deps.Config.REBIRTH_COST then
		deps.Util.toast(deps.Remotes, player, string.format("Need $%d to rebirth (you have $%s).", deps.Config.REBIRTH_COST, deps.Util.formatCash(cash)), "bad", 3.5)
		return
	end

	local rebirths = PlayerService.getRebirths(player) + 1
	local multiplier = 1 + deps.Config.REBIRTH_BONUS * rebirths

	-- Put every placed brainrot back in the wild before the base is wiped.
	pcall(function()
		deps.BrainrotService.clearBaseForRebirth(player)
	end)

	balances[player] = 0
	player:SetAttribute("Rebirths", rebirths)
	player:SetAttribute("Multiplier", multiplier)
	player:SetAttribute("IncomePerSec", 0)
	player:SetAttribute("Placed", 0)
	publish(player)

	pcall(function()
		deps.BaseService.onRebirth(player, rebirths)
	end)

	deps.Util.toast(deps.Remotes, player, string.format("REBIRTH %d! Permanent x%.2f cash multiplier.", rebirths, multiplier), "rebirth", 6)
	deps.Util.broadcastToast(deps.Remotes, string.format("%s rebirthed to level %d!", player.DisplayName, rebirths), "rebirth", 5)
	deps.Util.fireAll(deps.Remotes.FX, {
		kind = "rebirth",
		level = rebirths,
		position = deps.BaseService.getPadCenter(player),
	})
	pcall(function()
		deps.QuestService.recordEvent(player, "rebirth", 1)
	end)
	pcall(function()
		deps.OnboardingService.progress(player, "rebirth")
	end)
	pcall(function()
		deps.DataService.updateBest(player, deps.LeaderboardService.getTotalEarned(player), rebirths)
	end)
	pcall(function()
		deps.StateService.push(player)
	end)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 58
		humanoid.WalkSpeed = deps.UpgradeService and deps.UpgradeService.getSpeed(player) or 16
		humanoid.MaxHealth = 100
		humanoid.Health = 100
	end

	-- The character can die while carrying; BrainrotService watches Died and
	-- scatters the carried creatures, so nothing is ever orphaned in the air.
	pcall(function()
		deps.BrainrotService.watchCharacter(player, character)
	end)

	if not deps.BaseService.getPad(player) then
		pcall(function()
			deps.BaseService.assignPad(player)
		end)
	end
end

local function onPlayerAdded(player: Player)
	if not player.Parent then
		return
	end
	if initialized[player] then
		return
	end
	initialized[player] = true
	if not player:FindFirstChild("leaderstats") then
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

	balances[player] = 0
	player:SetAttribute("Cash", 0)
	player:SetAttribute("Carried", 0)
	player:SetAttribute("Placed", 0)
	player:SetAttribute("IncomePerSec", 0)
	player:SetAttribute("Rebirths", 0)
	player:SetAttribute("Multiplier", 1)
	player:SetAttribute("StealCooldown", 0)
	PlayerService.setPadsInfo(player)
	publish(player)

	-- Load persistence before the per-player services read upgrades or index.
	pcall(function()
		deps.DataService.load(player)
	end)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end

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

	-- The HUD may still be binding its remotes; a short delayed snapshot is
	-- cheaper than a client polling loop on every join.
	task.delay(0.8, function()
		if player.Parent then
			pcall(function()
				deps.StateService.push(player)
			end)
			pcall(function()
				deps.LeaderboardService.pushTo(player)
			end)
		end
	end)

	deps.Util.toast(
		deps.Remotes,
		player,
		string.format("Welcome! You have %d backpack slots and %d pad slots. Grab wild brainrots, bank them, press E for the Index.", deps.UpgradeService.getCarryCap(player), deps.UpgradeService.getPadSlots(player)),
		"info",
		7
	)
end

local function onPlayerRemoving(player: Player)
	-- Return this player's creatures to the wild before their pad disappears.
	pcall(function()
		deps.BrainrotService.releasePlayer(player)
	end)
	pcall(function()
		deps.BaseService.releasePlayer(player)
	end)
	pcall(function()
		deps.LeaderboardService.releasePlayer(player)
	end)
	pcall(function()
		deps.QuestService.releasePlayer(player)
	end)
	pcall(function()
		deps.OnboardingService.releasePlayer(player)
	end)
	pcall(function()
		deps.UpgradeService.releasePlayer(player)
	end)
	pcall(function()
		deps.DataService.save(player)
	end)
	balances[player] = nil
	initialized[player] = nil
end

function PlayerService.init(services: any)
	deps = services

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

return PlayerService
