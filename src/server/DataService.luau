--!strict
-- DataService — persistence for everything that must survive a server.
--
-- Stores one profile per player (captured Index, permanent upgrade levels, best
-- total earned, rebirths, tutorial flag) in a DataStore, and mirrors the best
-- total into an OrderedDataStore for the all-time board. Every call is wrapped
-- in pcall: when DataStores are unavailable (Studio without API access, an
-- outage) the game still runs and simply keeps profiles in memory.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local DataService = {}

local Config: any = nil
local deps: any = nil

local state = {
	running = false,
	profiles = {} :: { [Player]: any },
	allTime = {} :: { [number]: any },
	profileStore = nil :: any,
	totalStore = nil :: any,
	storesOnline = false,
	allTimePulled = false,
	lastSaveAt = {} :: { [Player]: number },
}

local PROFILE_PREFIX = "profile_"
local MAX_UPGRADE_LEVEL = 5

local function blankProfile(): any
	return {
		index = {},
		bestTotal = 0,
		tutorialDone = false,
		upgrades = {},
		rebirths = 0,
		savedAt = 0,
	}
end

local function isKnownUpgrade(key: string): boolean
	for _, track in ipairs(Config.UPGRADES) do
		if track.key == key then
			return true
		end
	end
	return false
end

-- Anything from a DataStore is untrusted: rebuild it field by field.
local function sanitize(raw: any): any
	local profile = blankProfile()
	if type(raw) ~= "table" then
		return profile
	end

	if type(raw.index) == "table" then
		for id, count in pairs(raw.index) do
			if type(id) == "string" and type(count) == "number" then
				local safe = math.floor(math.clamp(count, 0, 999999))
				if safe > 0 then
					profile.index[id] = safe
				end
			end
		end
	end

	if type(raw.upgrades) == "table" then
		for key, level in pairs(raw.upgrades) do
			if type(key) == "string" and type(level) == "number" and isKnownUpgrade(key) then
				profile.upgrades[key] = math.clamp(math.floor(level), 0, MAX_UPGRADE_LEVEL)
			end
		end
	end

	profile.bestTotal = math.max(0, tonumber(raw.bestTotal) or 0)
	profile.rebirths = math.max(0, math.floor(tonumber(raw.rebirths) or 0))
	profile.tutorialDone = raw.tutorialDone == true
	profile.savedAt = tonumber(raw.savedAt) or 0
	return profile
end

local function rememberAllTime(player: Player, fresh: boolean)
	local profile = state.profiles[player]
	if not profile then
		return
	end
	local userId = player.UserId
	local previous = state.allTime[userId]
	if previous and not fresh and profile.bestTotal < (previous.cash or 0) then
		profile.bestTotal = previous.cash
	end
	state.allTime[userId] = {
		name = player.DisplayName,
		cash = math.max(profile.bestTotal or 0, previous and previous.cash or 0),
		rebirths = math.max(profile.rebirths or 0, previous and previous.rebirths or 0),
	}
end

local function pullAllTime()
	if state.allTimePulled or not state.storesOnline or not state.totalStore then
		return
	end
	state.allTimePulled = true

	local ok, pages = pcall(function()
		return state.totalStore:GetSortedAsync(false, Config.LEADERBOARD_ROWS * 3)
	end)
	if not ok or not pages then
		return
	end
	local pageOk, entries = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not pageOk or type(entries) ~= "table" then
		return
	end
	for _, entry in ipairs(entries) do
		if type(entry) == "table" and entry.key then
			local userId = tonumber(entry.key)
			local cash = tonumber(entry.value) or 0
			if userId and cash > 0 then
				local known = state.allTime[userId]
				if not known or cash > (known.cash or 0) then
					state.allTime[userId] = {
						name = known and known.name or ("PLAYER " .. tostring(userId)),
						cash = cash,
						rebirths = known and known.rebirths or 0,
					}
				end
			end
		end
	end
end

-- Public API ---------------------------------------------------------------

function DataService.getProfile(player: Player): any
	return state.profiles[player]
end

function DataService.load(player: Player): any
	if state.profiles[player] then
		return state.profiles[player]
	end

	local profile = blankProfile()
	if state.storesOnline and state.profileStore then
		local ok, raw = pcall(function()
			return state.profileStore:GetAsync(PROFILE_PREFIX .. tostring(player.UserId))
		end)
		if ok and raw ~= nil then
			profile = sanitize(raw)
		elseif not ok then
			warn("[DataService] profile load failed; starting fresh for " .. player.Name)
		end
	end

	state.profiles[player] = profile
	state.lastSaveAt[player] = nil
	rememberAllTime(player, true)
	pullAllTime()
	return profile
end

function DataService.recordCapture(player: Player, id: string): number
	local profile = state.profiles[player]
	if not profile or type(id) ~= "string" then
		return 0
	end
	local count = (profile.index[id] or 0) + 1
	profile.index[id] = count
	return count
end

function DataService.getIndex(player: Player): { [string]: number }
	local profile = state.profiles[player]
	return profile and profile.index or {}
end

function DataService.setTutorialDone(player: Player, done: boolean)
	local profile = state.profiles[player]
	if profile then
		profile.tutorialDone = done == true
	end
end

function DataService.isTutorialDone(player: Player): boolean
	local profile = state.profiles[player]
	return profile ~= nil and profile.tutorialDone == true
end

function DataService.getUpgrades(player: Player): { [string]: number }
	local profile = state.profiles[player]
	return profile and profile.upgrades or {}
end

function DataService.getBestTotal(player: Player): number
	local profile = state.profiles[player]
	return profile and profile.bestTotal or 0
end

function DataService.updateBest(player: Player, total: number, rebirths: number)
	local profile = state.profiles[player]
	if not profile or not player.Parent then
		return
	end
	profile.bestTotal = math.max(profile.bestTotal or 0, math.floor(tonumber(total) or 0))
	profile.rebirths = math.max(profile.rebirths or 0, math.floor(tonumber(rebirths) or 0))
	local known = state.allTime[player.UserId]
	state.allTime[player.UserId] = {
		name = player.DisplayName,
		cash = math.max(profile.bestTotal, known and known.cash or 0),
		rebirths = math.max(profile.rebirths, known and known.rebirths or 0),
	}
end

function DataService.getAllTime(): { [number]: any }
	return state.allTime
end

function DataService.save(player: Player)
	local profile = state.profiles[player]
	if not profile then
		return
	end
	rememberAllTime(player, true)
	if not state.storesOnline then
		return
	end

	local now = os.clock()
	if now - (state.lastSaveAt[player] or -1000) < 2 then
		return
	end
	state.lastSaveAt[player] = now

	local snapshot = {
		index = profile.index,
		bestTotal = profile.bestTotal,
		rebirths = profile.rebirths,
		tutorialDone = profile.tutorialDone,
		upgrades = profile.upgrades,
		savedAt = os.time(),
	}

	if state.profileStore then
		local ok, err = pcall(function()
			state.profileStore:SetAsync(PROFILE_PREFIX .. tostring(player.UserId), snapshot)
		end)
		if not ok then
			warn("[DataService] profile save failed: " .. tostring(err))
		end
	end
	if state.totalStore then
		pcall(function()
			state.totalStore:SetAsync(tostring(player.UserId), math.max(0, math.floor(profile.bestTotal)))
		end)
	end
end

-- Lifecycle ----------------------------------------------------------------

function DataService.start(services: any)
	deps = services
	Config = services.Config

	state.running = true
	state.profiles = {}
	state.allTime = {}
	state.lastSaveAt = {}
	state.allTimePulled = false
	state.storesOnline = false

	pcall(function()
		state.profileStore = DataStoreService:GetDataStore("BrainrotCashRush_Profiles_v2")
		state.totalStore = DataStoreService:GetOrderedDataStore("BrainrotCashRush_BestTotal_v2")
		state.storesOnline = state.profileStore ~= nil and state.totalStore ~= nil
	end)
	print(state.storesOnline and "[DataService] DataStores online" or "[DataService] DataStores unavailable; in-memory profiles this session")

	pullAllTime()

	pcall(function()
		game:BindToClose(function()
			if not state.running then
				return
			end
			for _, player in ipairs(Players:GetPlayers()) do
				pcall(function()
					DataService.save(player)
				end)
			end
			task.wait(1.5)
		end)
	end)

	-- Autosave: a crash can cost at most one interval of Index/best progress.
	task.spawn(function()
		while state.running do
			task.wait(Config.SAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				pcall(function()
					DataService.save(player)
				end)
			end
		end
	end)
end

function DataService.stop()
	state.running = false
	for _, player in ipairs(Players:GetPlayers()) do
		pcall(function()
			DataService.save(player)
		end)
	end
	state.profiles = {}
end

return DataService
