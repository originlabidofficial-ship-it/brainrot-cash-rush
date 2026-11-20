--!strict
-- StateService — composes the HUD's single snapshot.
--
-- Any service that changes something the player can see (cash, Index, shop,
-- quests, tutorial) calls push(player). The payload below is the whole contract
-- with HUD.client.luau: server-authoritative numbers, no client-side guesses.
-- Building is pcall-guarded because a snapshot must never break gameplay.

local StateService = {}

local Config: any = nil
local deps: any = nil

local function effectValue(player: Player, key: string): number
	local upgrades = deps.UpgradeService
	if not upgrades then
		return 0
	end
	if key == "CarryCap" then
		return upgrades.getCarryCap(player)
	elseif key == "PadSlots" then
		return upgrades.getPadSlots(player)
	elseif key == "Income" then
		return upgrades.getIncomeMultiplier(player)
	elseif key == "GuardRange" then
		return upgrades.getGuardRadius(player)
	elseif key == "Speed" then
		return upgrades.getSpeed(player)
	elseif key == "Magnet" then
		return upgrades.getMagnetRadius(player)
	end
	return 0
end

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

local function indexSection(player: Player): any
	local stored = deps.DataService.getIndex(player)
	local entries = {}
	local discovered = 0
	for _, kind in ipairs(Config.BRAINROTS) do
		local count = math.floor(tonumber(stored[kind.id]) or 0)
		if count > 0 then
			discovered += 1
		end
		table.insert(entries, {
			id = kind.id,
			name = kind.name,
			rarity = kind.rarity,
			shape = kind.shape,
			quip = kind.quip,
			income = Config.RARITIES[kind.rarity].value,
			discovered = count > 0,
			count = count,
		})
	end
	local total = #entries
	local mutations = {}
	for _, mutation in ipairs(Config.MUTATIONS) do
		table.insert(mutations, {
			key = mutation.key,
			name = mutation.name,
			multiplier = mutation.multiplier,
			weight = mutation.weight,
			blurb = mutation.blurb,
		})
	end
	return {
		discovered = discovered,
		total = total,
		percent = total > 0 and discovered / total or 0,
		entries = entries,
		mutationChance = Config.MUTATION_CHANCE,
		mutations = mutations,
	}
end

local function shopSection(player: Player): { any }
	local entries = {}
	local upgrades = deps.UpgradeService
	for _, track in ipairs(Config.UPGRADES) do
		local level = upgrades.getLevel(player, track.key)
		local value = effectValue(player, track.key)
		table.insert(entries, {
			key = track.key,
			name = track.name,
			icon = track.icon,
			blurb = track.blurb,
			level = level,
			maxLevel = #track.prices,
			price = upgrades.getPrice(player, track.key),
			effect = effectText(track.key, value),
			value = value,
		})
	end
	return entries
end

local function questSection(player: Player): { any }
	local entries = {}
	for _, quest in ipairs(deps.QuestService.getQuests(player)) do
		table.insert(entries, {
			id = quest.id,
			name = quest.name,
			goal = quest.goal,
			progress = quest.progress,
			reward = quest.reward,
			complete = quest.complete,
		})
	end
	return entries
end

local function craftSection(player: Player): any
	if not deps.CraftService then
		return nil
	end
	return deps.CraftService.preview(player)
end

function StateService.build(player: Player): any
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
		index = indexSection(player),
		upgrades = shopSection(player),
		quests = questSection(player),
		craft = craftSection(player),
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

function StateService.start(services: any)
	deps = services
	Config = services.Config
end

function StateService.stop()
	-- Snapshots hold no state of their own; nothing to release.
end

return StateService
