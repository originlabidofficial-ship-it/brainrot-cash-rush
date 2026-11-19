--!strict
-- QuestService — three rotating jobs per player.
--
-- Quests are assigned on join from Config.QUESTS, advanced only by real server
-- events (capture, bank, wave, steal, rebirth), and claimed by id. A claim is
-- validated here: known id, complete, rate-limited, then paid through
-- PlayerService and replaced with a fresh quest so the slot never goes empty.

local QuestService = {}

local Config: any = nil
local Util: any = nil
local deps: any = nil

local state = {
	running = false,
	quests = {} :: { [Player]: { any } },
	lastClaimAt = {} :: { [Player]: number },
	noticeAt = {} :: { [Player]: number },
	claimed = {} :: { [Player]: number },
}

local function alive(player: Player?): boolean
	return player ~= nil and player.Parent ~= nil
end

local function activeIds(player: Player): { [string]: boolean }
	local taken = {}
	for _, quest in ipairs(state.quests[player] or {}) do
		taken[quest.id] = true
	end
	return taken
end

local function chooseEntry(player: Player): any
	local taken = activeIds(player)
	local options = {}
	for _, entry in ipairs(Config.QUESTS) do
		if not taken[entry.id] then
			table.insert(options, entry)
		end
	end
	if #options == 0 then
		options = Config.QUESTS
	end
	return options[math.random(#options)]
end

local function buildQuest(player: Player, slot: number): any
	local entry = chooseEntry(player)
	return {
		slot = slot,
		id = entry.id,
		event = entry.event,
		name = entry.name,
		goal = entry.goal,
		reward = entry.reward,
		progress = 0,
		complete = false,
	}
end

function QuestService.onPlayerAdded(player: Player)
	local list = {}
	for slot = 1, Config.QUEST_SLOTS do
		list[slot] = buildQuest(player, slot)
	end
	state.quests[player] = list
	state.lastClaimAt[player] = 0
	state.noticeAt[player] = 0
	state.claimed[player] = 0
end

function QuestService.getQuests(player: Player): { any }
	return state.quests[player] or {}
end

function QuestService.getClaimedCount(player: Player): number
	return state.claimed[player] or 0
end

function QuestService.recordEvent(player: Player, event: string, amount: number?)
	if not alive(player) or type(event) ~= "string" then
		return
	end
	local add = math.max(0, math.floor(tonumber(amount) or 1))
	if add <= 0 then
		return
	end
	local list = state.quests[player]
	if not list then
		return
	end

	local changed = false
	for _, quest in ipairs(list) do
		if quest.event == event and not quest.complete then
			quest.progress = math.min(quest.goal, quest.progress + add)
			changed = true
			if quest.progress >= quest.goal then
				quest.complete = true
				local now = os.clock()
				if now - (state.noticeAt[player] or 0) > 2 then
					state.noticeAt[player] = now
					Util.toast(deps.Remotes, player, "Quest complete: " .. quest.name .. " — claim $" .. tostring(quest.reward) .. "!", "good", Config.TOAST.long)
					Util.fireClient(deps.Remotes.FX, player, {
						kind = "quest",
						text = "QUEST COMPLETE",
						position = deps.BaseService.getPadCenter(player) + Vector3.new(0, 7, 0),
					})
				end
			end
		end
	end

	if changed then
		pcall(function()
			deps.StateService.push(player)
		end)
	end
end

function QuestService.tryClaim(player: Player, questId: any)
	if not alive(player) then
		return
	end
	if type(questId) ~= "string" or #questId == 0 or #questId > 32 then
		return
	end

	local now = os.clock()
	if now - (state.lastClaimAt[player] or 0) < Config.LIMITS.questClaim then
		return
	end
	state.lastClaimAt[player] = now

	local list = state.quests[player]
	if not list then
		return
	end

	for index, quest in ipairs(list) do
		if quest.id == questId then
			if not quest.complete then
				Util.toast(deps.Remotes, player, "That quest is not complete yet.", "info", Config.TOAST.short)
				return
			end
			state.claimed[player] = (state.claimed[player] or 0) + 1
			deps.PlayerService.addCash(player, quest.reward)
			Util.toast(deps.Remotes, player, string.format("Quest claimed: +$%s!", Util.commaNumber(quest.reward)), "good", Config.TOAST.normal)
			Util.fireClient(deps.Remotes.FX, player, {
				kind = "quest",
				text = "+$" .. Util.commaNumber(quest.reward),
				position = deps.BaseService.getPadCenter(player) + Vector3.new(0, 7, 0),
			})
			list[index] = buildQuest(player, quest.slot or index)
			pcall(function()
				deps.StateService.push(player)
			end)
			return
		end
	end
end

function QuestService.releasePlayer(player: Player)
	state.quests[player] = nil
	state.lastClaimAt[player] = nil
	state.noticeAt[player] = nil
	state.claimed[player] = nil
end

function QuestService.start(services: any)
	deps = services
	Config = services.Config
	Util = services.Util

	state.running = true
	state.quests = {}
	state.lastClaimAt = {}
	state.noticeAt = {}
	state.claimed = {}

	local remote = deps.Remotes and deps.Remotes.QuestClaim
	if remote then
		remote.OnServerEvent:Connect(function(player, questId)
			-- Never trust the shape of a remote argument: validate before work.
			if type(questId) == "string" then
				QuestService.tryClaim(player, questId)
			end
		end)
	end
end

function QuestService.stop()
	state.running = false
	state.quests = {}
	state.lastClaimAt = {}
	state.noticeAt = {}
	state.claimed = {}
end

return QuestService
