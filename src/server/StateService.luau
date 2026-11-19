--!strict
-- StateService: owns the aggregated HUD snapshot. Every service that changes
-- cash, index, upgrades, quests or onboarding calls push(player); the client
-- receives one typed payload with server-authoritative numbers and never has
-- to guess a price, cap or progress value.

local StateService = {}

local deps: any = nil

local function effectText(key: string, value: number): string
	if key == "Income" then
		return string.format("x%.2f", value)
	elseif key == "GuardRange" or key == "Magnet" then
		return string.format("%.0f studs", value)
	elseif key == "Speed" then
		return string.format("%.0f walk", value)
	elseif key == "CarryCap" then
		return string.format("%.0f carried", value)
	elseif key == "PadSlots" then
		return string.format("%.0f slots", value)
	end
	return tostring(value)
end

local function effectValue(player: Player, key: string): number
	if key == "CarryCap" then
		return deps.UpgradeService.getCarryCap(player)
	elseif key == "PadSlots" then
		return deps.UpgradeService.getPadSlots(player)
	elseif key == "Income" then
		return deps.UpgradeService.getIncomeMultiplier(player)
	elseif key == "GuardRange" then
		return deps.UpgradeService.getGuardRadius(player)
	elseif key == "Speed" then
		return deps.UpgradeService.getSpeed(player)
	elseif key == "Magnet" then
		return deps.UpgradeService.getMagnetRadius(player)
	end
	return 0
end

function StateService.build(player: Player): any
	local index = deps.DataService.getIndex(player)
	local entries = {}
	local discovered = 0
	for _, kind in ipairs(deps.Config.BRAINROTS) do
		local count = math.floor(tonumber(index[kind.id]) or 0)
		if count > 0 then
			discovered += 1
		end
		table.insert(entries, {
			id = kind.id,
			name = kind.name,
			rarity = kind.rarity,
			shape = kind.shape,
			quip = kind.quip,
			income = deps.Config.RARITIES[kind.rarity].value,
			discovered = count > 0,
			count = count,
		})
	end

	local upgrades = {}
	for _, track in ipairs(deps.Config.UPGRADES) do
		local level = deps.UpgradeService.getLevel(player, track.key)
		local value = effectValue(player, track.key)
		local price = deps.UpgradeService.getPrice(player, track.key)
		table.insert(upgrades, {
			key = track.key,
			name = track.name,
			icon = track.icon,
			blurb = track.blurb,
			level = level,
			maxLevel = #track.prices,
			price = price,
			effect = effectText(track.key, value),
			value = value,
		})
	end

	local questList = {}
	for _, quest in ipairs(deps.QuestService.getQuests(player)) do
		table.insert(questList, {
			id = quest.id,
			name = quest.name,
			goal = quest.goal,
			progress = quest.progress,
			reward = quest.reward,
			complete = quest.complete,
		})
	end

	return {
		kind = "state",
		cash = deps.PlayerService.getCash(player),
		income = tonumber(player:GetAttribute("IncomePerSec")) or 0,
		rebirths = deps.PlayerService.getRebirths(player),
		multiplier = deps.PlayerService.getMultiplier(player),
		carried = tonumber(player:GetAttribute("Carried")) or 0,
		placed = tonumber(player:GetAttribute("Placed")) or 0,
		carryCap = deps.UpgradeService.getCarryCap(player),
		padSlots = deps.UpgradeService.getPadSlots(player),
		index = {
			discovered = discovered,
			total = #entries,
			percent = #entries > 0 and discovered / #entries or 0,
			entries = entries,
		},
		upgrades = upgrades,
		quests = questList,
		tutorial = deps.OnboardingService.getState(player),
		bestTotal = deps.DataService.getBestTotal(player),
		totalEarned = deps.LeaderboardService.getTotalEarned(player),
	}
end

function StateService.push(player: Player)
	if not player or not player.Parent then
		return
	end
	local ok, payload = pcall(StateService.build, player)
	if not ok then
		warn("[StateService] snapshot failed: " .. tostring(payload))
		return
	end
	deps.Util.fireClient(deps.Remotes.State, player, payload)
end

function StateService.init(services: any)
	deps = services
end

return StateService
