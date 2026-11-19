--!strict
-- UpgradeService — the six permanent shop tracks.
--
-- The server owns levels, prices and effects. A client may only send a track
-- key; the price is looked up here, cash is debited atomically, and only then
-- is the level written. The getters below are the single source of truth other
-- services use for caps, radius, speed and income multipliers.

local Players = game:GetService("Players")

local UpgradeService = {}

local Config: any = nil
local Util: any = nil
local deps: any = nil

local state = {
	running = false,
	levels = {} :: { [Player]: { [string]: number } },
	lastBuyAt = {} :: { [Player]: number },
}

local function alive(player: Player?): boolean
	return player ~= nil and player.Parent ~= nil
end

local function trackFor(key: string): any
	for _, entry in ipairs(Config.UPGRADES) do
		if entry.key == key then
			return entry
		end
	end
	return nil
end

local function levelOf(player: Player, key: string): number
	local map = state.levels[player]
	local raw = map and map[key] or 0
	return math.clamp(math.floor(tonumber(raw) or 0), 0, Config.MAX_UPGRADE_LEVEL)
end

local function effectOf(player: Player, key: string): number
	local track = trackFor(key)
	if not track then
		return 0
	end
	return track.base + track.perLevel * levelOf(player, key)
end

-- Public effect getters ----------------------------------------------------

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

-- Next price, or nil when the track is maxed. This is what the HUD displays
-- and what tryBuy actually charges — one lookup, no client-side price.
function UpgradeService.getPrice(player: Player, key: string): number?
	local track = trackFor(key)
	if not track then
		return nil
	end
	return track.prices[levelOf(player, key) + 1]
end

function UpgradeService.getAllLevels(player: Player): { [string]: number }
	local out = {}
	for _, track in ipairs(Config.UPGRADES) do
		out[track.key] = levelOf(player, track.key)
	end
	return out
end

-- Application --------------------------------------------------------------

local function applySpeed(player: Player)
	if not alive(player) then
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

local function connectCharacter(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(0.1)
		applySpeed(player)
	end)
end

function UpgradeService.onPlayerAdded(player: Player)
	local stored = deps.DataService.getUpgrades(player)
	local map = {}
	for _, track in ipairs(Config.UPGRADES) do
		map[track.key] = math.clamp(math.floor(tonumber(stored[track.key]) or 0), 0, Config.MAX_UPGRADE_LEVEL)
	end
	state.levels[player] = map
	applySpeed(player)
end

local function describeEffect(key: string, value: number): string
	local track = trackFor(key)
	local unit = track and track.unit or ""
	if key == "Income" then
		return string.format("x%.2f", value)
	end
	return string.format("%.1f%s", value, unit)
end

function UpgradeService.tryBuy(player: Player, key: any)
	if not alive(player) or type(key) ~= "string" then
		return
	end
	local track = trackFor(key)
	if not track then
		Util.toast(deps.Remotes, player, "Unknown upgrade.", "bad", Config.TOAST.short)
		return
	end

	local now = os.clock()
	if now - (state.lastBuyAt[player] or 0) < Config.LIMITS.shopBuy then
		return
	end
	state.lastBuyAt[player] = now

	local current = levelOf(player, key)
	if current >= #track.prices then
		Util.toast(deps.Remotes, player, track.name .. " is already max level.", "info", Config.TOAST.short)
		return
	end

	local price = track.prices[current + 1]
	local cash = deps.PlayerService.getCash(player)
	if cash < price then
		Util.toast(deps.Remotes, player, string.format("%s costs $%s — you have $%s.", track.name, Util.commaNumber(price), Util.commaNumber(cash)), "bad", Config.TOAST.normal)
		return
	end
	if not deps.PlayerService.spendCash(player, price) then
		return
	end

	local map = state.levels[player]
	if not map then
		map = {}
		state.levels[player] = map
	end
	map[key] = current + 1

	-- Keep the persisted profile in step with the live map.
	local profile = deps.DataService.getProfile(player)
	if profile then
		profile.upgrades[key] = current + 1
	end
	applyAll(player)

	local effect = describeEffect(key, effectOf(player, key))
	Util.toast(deps.Remotes, player, string.format("%s → Lv %d/%d! %s %s.", track.name, current + 1, #track.prices, track.effectLabel, effect), "good", Config.TOAST.normal)
	Util.fireClient(deps.Remotes.FX, player, {
		kind = "upgrade",
		position = deps.BaseService.getPadCenter(player) + Vector3.new(0, 5, 0),
		text = track.name .. " LV " .. tostring(current + 1),
	})

	pcall(function()
		deps.StateService.push(player)
	end)
	pcall(function()
		deps.DataService.save(player)
	end)
end

function UpgradeService.releasePlayer(player: Player)
	state.levels[player] = nil
	state.lastBuyAt[player] = nil
end

-- Lifecycle ----------------------------------------------------------------

function UpgradeService.start(services: any)
	deps = services
	Config = services.Config
	Util = services.Util

	state.running = true
	state.levels = {}
	state.lastBuyAt = {}

	local remote = deps.Remotes and deps.Remotes.ShopBuy
	if remote then
		remote.OnServerEvent:Connect(function(player, key)
			if type(key) == "string" then
				UpgradeService.tryBuy(player, key)
			end
		end)
	end

	Players.PlayerAdded:Connect(connectCharacter)
	for _, player in ipairs(Players:GetPlayers()) do
		connectCharacter(player)
	end
end

function UpgradeService.stop()
	state.running = false
	state.levels = {}
	state.lastBuyAt = {}
end

return UpgradeService
