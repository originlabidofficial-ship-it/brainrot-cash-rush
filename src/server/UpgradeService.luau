--!strict
-- UpgradeService: owns the six five-level shop tracks. It stores each player's
-- levels (persisted by DataService), validates every purchase request on the
-- server, deducts cash atomically and exposes the authoritative effect numbers
-- (carry cap, pad slots, income multiplier, guard radius, walkspeed, magnet
-- radius) that BrainrotService, BaseService and the HUD read. The client can
-- only ask to buy a track key; it never sends a price or a level.

local Players = game:GetService("Players")

local UpgradeService = {}

local deps: any = nil
local levels: { [Player]: { [string]: number } } = {}
local lastBuyAt: { [Player]: number } = {}

local function track(key: string): any
	for _, entry in ipairs(deps.Config.UPGRADES) do
		if entry.key == key then
			return entry
		end
	end
	return nil
end

local function levelOf(player: Player, key: string): number
	local map = levels[player]
	local level = map and map[key] or 0
	return math.clamp(math.floor(tonumber(level) or 0), 0, 5)
end

local function effectOf(player: Player, key: string): number
	local entry = track(key)
	if not entry then
		return 0
	end
	return entry.base + entry.perLevel * levelOf(player, key)
end

function UpgradeService.getLevel(player: Player, key: string): number
	return levelOf(player, key)
end

function UpgradeService.getCarryCap(player: Player): number
	return math.floor(effectOf(player, "CarryCap") + 0.5)
end

function UpgradeService.getPadSlots(player: Player): number
	return math.floor(effectOf(player, "PadSlots") + 0.5)
end

function UpgradeService.getIncomeMultiplier(player: Player): number
	return effectOf(player, "Income")
end

function UpgradeService.getGuardRadius(player: Player): number
	return effectOf(player, "GuardRange")
end

function UpgradeService.getSpeed(player: Player): number
	return math.floor(effectOf(player, "Speed") + 0.5)
end

function UpgradeService.getMagnetRadius(player: Player): number
	return effectOf(player, "Magnet")
end

-- Price for the next level, or nil when the track is maxed.
function UpgradeService.getPrice(player: Player, key: string): number?
	local entry = track(key)
	if not entry then
		return nil
	end
	local nextLevel = levelOf(player, key) + 1
	return entry.prices[nextLevel]
end

function UpgradeService.getAllLevels(player: Player): { [string]: number }
	local out = {}
	for _, entry in ipairs(deps.Config.UPGRADES) do
		out[entry.key] = levelOf(player, entry.key)
	end
	return out
end

local function applySpeed(player: Player)
	if not player or not player.Parent then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.UseJumpPower = true
		humanoid.WalkSpeed = UpgradeService.getSpeed(player)
	end
end

local function applyAll(player: Player)
	applySpeed(player)
	pcall(function()
		deps.BaseService.refreshPad(player)
	end)
end

function UpgradeService.onPlayerAdded(player: Player)
	local stored = deps.DataService.getUpgrades(player)
	local map = {}
	for _, entry in ipairs(deps.Config.UPGRADES) do
		map[entry.key] = math.clamp(math.floor(tonumber(stored[entry.key]) or 0), 0, 5)
	end
	levels[player] = map
	applySpeed(player)
end

function UpgradeService.tryBuy(player: Player, key: any)
	if not player or not player.Parent then
		return
	end
	if type(key) ~= "string" then
		return
	end
	local entry = track(key)
	if not entry then
		deps.Util.toast(deps.Remotes, player, "Unknown upgrade.", "bad", 2.5)
		return
	end
	local now = os.clock()
	if now - (lastBuyAt[player] or 0) < 0.4 then
		return
	end
	lastBuyAt[player] = now

	local current = levelOf(player, key)
	if current >= #entry.prices then
		deps.Util.toast(deps.Remotes, player, entry.name .. " is already max level.", "info", 3)
		return
	end
	local price = entry.prices[current + 1]
	local cash = deps.PlayerService.getCash(player)
	if cash < price then
		deps.Util.toast(deps.Remotes, player, string.format("%s costs $%s — you have $%s.", entry.name, deps.Util.commaNumber(price), deps.Util.commaNumber(cash)), "bad", 3.5)
		return
	end

	if not deps.PlayerService.spendCash(player, price) then
		return
	end
	local map = levels[player]
	if not map then
		map = {}
		levels[player] = map
	end
	map[key] = current + 1

	local profile = deps.DataService.getProfile(player)
	if profile then
		profile.upgrades[key] = current + 1
	end
	applyAll(player)

	local effect = effectOf(player, key)
	local effectText = tostring(effect)
	if key == "Income" then
		effectText = string.format("x%.2f", effect)
	elseif key == "GuardRange" or key == "Magnet" then
		effectText = string.format("%.1f studs", effect)
	end
	deps.Util.toast(deps.Remotes, player, string.format("%s → Lv %d/%d! %s %s.", entry.name, current + 1, #entry.prices, entry.effectLabel, effectText), "good", 4.5)
	deps.Util.fireClient(deps.Remotes.FX, player, {
		kind = "upgrade",
		position = deps.BaseService.getPadCenter(player) + Vector3.new(0, 5, 0),
		text = entry.name .. " LV " .. tostring(current + 1),
	})
	pcall(function()
		deps.StateService.push(player)
	end)
	pcall(function()
		deps.DataService.save(player)
	end)
end

function UpgradeService.releasePlayer(player: Player)
	levels[player] = nil
	lastBuyAt[player] = nil
end

function UpgradeService.init(services: any)
	deps = services
	levels = {}
	lastBuyAt = {}

	local remote = deps.Remotes and deps.Remotes.ShopBuy
	if remote then
		remote.OnServerEvent:Connect(function(player, key)
			UpgradeService.tryBuy(player, key)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.1)
			applySpeed(player)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			task.wait(0.1)
			applySpeed(player)
		end)
	end
end

return UpgradeService
