--!strict
-- QuestService: owns the three rotating quests in every player's log. It
-- assigns distinct quests on join, advances progress only from real server
-- events (capture, bank, wave, steal, rebirth), validates claim requests by
-- quest id, pays the reward through PlayerService and immediately rotates a
-- fresh quest into the freed slot.

local Players = game:GetService("Players")

local QuestService = {}

local deps: any = nil
local quests: { [Player]: { any } } = {}
local lastClaimAt: { [Player]: number } = {}
local completeToastAt: { [Player]: number } = {}
local claimedCount: { [Player]: number } = {}

local function pool(): { any }
	return deps.Config.QUESTS
end

local function activeIds(player: Player): { [string]: boolean }
	local out = {}
	for _, quest in ipairs(quests[player] or {}) do
		out[quest.id] = true
	end
	return out
end

local function pickQuest(player: Player): any
	local active = activeIds(player)
	local candidates = {}
	for _, entry in ipairs(pool()) do
		if not active[entry.id] then
			table.insert(candidates, entry)
		end
	end
	if #candidates == 0 then
		candidates = pool()
	end
	return candidates[math.random(#candidates)]
end

local function makeQuest(player: Player, slot: number): any
	local entry = pickQuest(player)
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
	for slot = 1, 3 do
		list[slot] = makeQuest(player, slot)
	end
	quests[player] = list
	lastClaimAt[player] = 0
	completeToastAt[player] = 0
	claimedCount[player] = 0
end

function QuestService.getQuests(player: Player): { any }
	return quests[player] or {}
end

function QuestService.getClaimedCount(player: Player): number
	return claimedCount[player] or 0
end

function QuestService.recordEvent(player: Player, event: string, amount: number?)
	if not player or not player.Parent then
		return
	end
	if type(event) ~= "string" then
		return
	end
	local add = math.max(0, math.floor(tonumber(amount) or 1))
	if add <= 0 then
		return
	end
	local list = quests[player]
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
				if now - (completeToastAt[player] or 0) > 2 then
					completeToastAt[player] = now
					deps.Util.toast(deps.Remotes, player, "Quest complete: " .. quest.name .. " — claim $" .. tostring(quest.reward) .. "!", "good", 5)
					deps.Util.fireClient(deps.Remotes.FX, player, {
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
	if not player or not player.Parent then
		return
	end
	if type(questId) ~= "string" or #questId > 32 then
		return
	end
	local now = os.clock()
	if now - (lastClaimAt[player] or 0) < 0.8 then
		return
	end
	lastClaimAt[player] = now

	local list = quests[player]
	if not list then
		return
	end
	for index, quest in ipairs(list) do
		if quest.id == questId then
			if not quest.complete then
				deps.Util.toast(deps.Remotes, player, "That quest is not complete yet.", "info", 2.5)
				return
			end
			claimedCount[player] = (claimedCount[player] or 0) + 1
			deps.PlayerService.addCash(player, quest.reward)
			deps.Util.toast(deps.Remotes, player, string.format("Quest claimed: +$%s!", deps.Util.commaNumber(quest.reward)), "good", 4)
			deps.Util.fireClient(deps.Remotes.FX, player, {
				kind = "quest",
				text = "+$" .. deps.Util.commaNumber(quest.reward),
				position = deps.BaseService.getPadCenter(player) + Vector3.new(0, 7, 0),
			})
			list[index] = makeQuest(player, quest.slot or index)
			pcall(function()
				deps.StateService.push(player)
			end)
			return
		end
	end
end

function QuestService.releasePlayer(player: Player)
	quests[player] = nil
	lastClaimAt[player] = nil
	completeToastAt[player] = nil
	claimedCount[player] = nil
end

function QuestService.init(services: any)
	deps = services
	quests = {}
	lastClaimAt = {}
	completeToastAt = {}
	claimedCount = {}

	local remote = deps.Remotes and deps.Remotes.QuestClaim
	if remote then
		remote.OnServerEvent:Connect(function(player, questId)
			QuestService.tryClaim(player, questId)
		end)
	end

	-- Defensive cleanup: PlayerService calls releasePlayer explicitly too.
	Players.PlayerRemoving:Connect(function(player)
		QuestService.releasePlayer(player)
	end)
end

return QuestService
