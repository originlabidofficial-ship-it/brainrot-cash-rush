--!strict
-- DataService: owns per-player persistence. It loads and saves the profile
-- (captured index, permanent upgrades, best total earned, tutorial completion)
-- through DataStoreService, and mirrors the best total into an OrderedDataStore
-- so the leaderboard can show all-time records when DataStores are available.
-- Every DataStore call is pcall-guarded: in Studio with API access off the game
-- still runs and simply keeps profiles in memory for the session.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local DataService = {}

local deps: any = nil
local profiles: { [Player]: any } = {}
local loaded: { [Player]: boolean } = {}
local allTime: { [number]: any } = {}
local profileStore: any = nil
local cashStore: any = nil
local storeReady = false
local allTimeFetched = false
local lastSavedAt: { [Player]: number } = {}

local function defaultProfile(): any
	return {
		index = {},
		bestTotal = 0,
		tutorialDone = false,
		upgrades = {},
		rebirths = 0,
		savedAt = 0,
	}
end

local function validUpgrade(key: string): boolean
	for _, track in ipairs(deps.Config.UPGRADES) do
		if track.key == key then
			return true
		end
	end
	return false
end

local function sanitize(raw: any): any
	local profile = defaultProfile()
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
			if type(key) == "string" and type(level) == "number" and validUpgrade(key) then
				profile.upgrades[key] = math.clamp(math.floor(level), 0, 5)
			end
		end
	end
	profile.bestTotal = math.max(0, tonumber(raw.bestTotal) or 0)
	profile.rebirths = math.max(0, math.floor(tonumber(raw.rebirths) or 0))
	profile.tutorialDone = raw.tutorialDone == true
	profile.savedAt = tonumber(raw.savedAt) or 0
	return profile
end

local function noteAllTime(player: Player, fresh: boolean)
	local profile = profiles[player]
	if not profile then
		return
	end
	local userId = player.UserId
	local existing = allTime[userId]
	if not existing or fresh or profile.bestTotal >= (existing.cash or 0) then
		allTime[userId] = {
			name = player.DisplayName,
			cash = math.max(profile.bestTotal or 0, existing and existing.cash or 0),
			rebirths = math.max(profile.rebirths or 0, existing and existing.rebirths or 0),
		}
	end
end

local function fetchAllTime()
	if allTimeFetched or not storeReady or not cashStore then
		return
	end
	allTimeFetched = true
	local ok, pages = pcall(function()
		return cashStore:GetSortedAsync(false, 10)
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
		if type(entry) == "table" and entry.key and entry.value then
			local userId = tonumber(entry.key)
			if userId then
				local existing = allTime[userId]
				if not existing or (tonumber(entry.value) or 0) > (existing.cash or 0) then
					allTime[userId] = {
						name = existing and existing.name or ("PLAYER " .. tostring(userId)),
						cash = tonumber(entry.value) or 0,
						rebirths = existing and existing.rebirths or 0,
					}
				end
			end
		end
	end
end

function DataService.getProfile(player: Player): any
	return profiles[player]
end

function DataService.load(player: Player): any
	if profiles[player] then
		return profiles[player]
	end
	local profile = defaultProfile()
	if storeReady and profileStore then
		local ok, raw = pcall(function()
			return profileStore:GetAsync("profile_" .. tostring(player.UserId))
		end)
		if ok and raw ~= nil then
			profile = sanitize(raw)
		elseif not ok then
			warn("[DataService] profile load failed; using a fresh profile for " .. player.Name)
		end
	end
	profiles[player] = profile
	loaded[player] = true
	lastSavedAt[player] = nil
	noteAllTime(player, true)
	fetchAllTime()
	return profile
end

function DataService.recordCapture(player: Player, id: string): number
	local profile = profiles[player]
	if not profile or type(id) ~= "string" then
		return 0
	end
	local count = (profile.index[id] or 0) + 1
	profile.index[id] = count
	return count
end

function DataService.getIndex(player: Player): { [string]: number }
	local profile = profiles[player]
	return profile and profile.index or {}
end

function DataService.setTutorialDone(player: Player, done: boolean)
	local profile = profiles[player]
	if profile then
		profile.tutorialDone = done == true
	end
end

function DataService.isTutorialDone(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.tutorialDone == true
end

function DataService.getUpgrades(player: Player): { [string]: number }
	local profile = profiles[player]
	return profile and profile.upgrades or {}
end

function DataService.getBestTotal(player: Player): number
	local profile = profiles[player]
	return profile and profile.bestTotal or 0
end

function DataService.updateBest(player: Player, total: number, rebirths: number)
	local profile = profiles[player]
	if not profile or not player.Parent then
		return
	end
	profile.bestTotal = math.max(profile.bestTotal or 0, math.floor(tonumber(total) or 0))
	profile.rebirths = math.max(profile.rebirths or 0, math.floor(tonumber(rebirths) or 0))
	local entry = allTime[player.UserId]
	allTime[player.UserId] = {
		name = player.DisplayName,
		cash = math.max(profile.bestTotal, entry and entry.cash or 0),
		rebirths = math.max(profile.rebirths, entry and entry.rebirths or 0),
	}
end

function DataService.getAllTime(): { [number]: any }
	return allTime
end

function DataService.save(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	noteAllTime(player, true)
	if not storeReady then
		return
	end
	local now = os.clock()
	if now - (lastSavedAt[player] or -1000) < 2 then
		return
	end
	lastSavedAt[player] = now
	local snapshot = {
		index = profile.index,
		bestTotal = profile.bestTotal,
		rebirths = profile.rebirths,
		tutorialDone = profile.tutorialDone,
		upgrades = profile.upgrades,
		savedAt = os.time(),
	}
	if profileStore then
		local ok, err = pcall(function()
			profileStore:SetAsync("profile_" .. tostring(player.UserId), snapshot)
		end)
		if not ok then
			warn("[DataService] profile save failed: " .. tostring(err))
		end
	end
	if cashStore then
		pcall(function()
			cashStore:SetAsync(tostring(player.UserId), math.max(0, math.floor(profile.bestTotal)))
		end)
	end
end

function DataService.init(services: any)
	deps = services
	pcall(function()
		profileStore = DataStoreService:GetDataStore("BrainrotCashRush_Profiles_v2")
		cashStore = DataStoreService:GetOrderedDataStore("BrainrotCashRush_BestTotal_v2")
		storeReady = profileStore ~= nil and cashStore ~= nil
	end)
	if storeReady then
		print("[DataService] DataStores online")
	else
		print("[DataService] DataStores unavailable; using in-memory profiles this session")
	end
	fetchAllTime()

	pcall(function()
		game:BindToClose(function()
			for _, player in ipairs(Players:GetPlayers()) do
				pcall(function()
					DataService.save(player)
				end)
			end
			task.wait(1.5)
		end)
	end)

	-- Periodic autosave so a server crash loses at most a minute of Index and
	-- best-total progress, not the whole session.
	task.spawn(function()
		while true do
			task.wait(deps.Config.SAVE_INTERVAL or 60)
			for _, player in ipairs(Players:GetPlayers()) do
				pcall(function()
					DataService.save(player)
				end)
			end
		end
	end)
end

return DataService
