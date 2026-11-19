--!strict
-- OnboardingService — the five-step first-join tutorial.
--
-- Progress is driven by real server facts: movement is sampled from the
-- character, grab/bank/rebirth come from the services that perform them, and
-- the Index step only ticks from a validated TutorialAction("index"). Skipping
-- is also server-validated and persisted, so it never reappears on rejoin.

local Players = game:GetService("Players")

local OnboardingService = {}

local Config: any = nil
local Util: any = nil
local deps: any = nil

local state = {
	running = false,
	players = {} :: { [Player]: any },
	lastActionAt = {} :: { [Player]: number },
}

local function alive(player: Player?): boolean
	return player ~= nil and player.Parent ~= nil
end

local function blankStatus(done: boolean): any
	local objectives = {}
	for _, step in ipairs(Config.TUTORIAL) do
		table.insert(objectives, { key = step.key, label = step.label, done = done })
	end
	return { done = done, objectives = objectives }
end

local function allComplete(status: any): boolean
	for _, objective in ipairs(status.objectives) do
		if not objective.done then
			return false
		end
	end
	return true
end

local function finish(player: Player, status: any)
	status.done = true
	for _, objective in ipairs(status.objectives) do
		objective.done = true
	end
	deps.DataService.setTutorialDone(player, true)
	pcall(function()
		deps.DataService.save(player)
	end)
	Util.toast(deps.Remotes, player, "Tutorial complete! The whole map is yours — press E for the Index, B for the Shop.", "good", 6)
	Util.fireClient(deps.Remotes.FX, player, {
		kind = "quest",
		text = "TUTORIAL COMPLETE",
		position = deps.BaseService.getPadCenter(player) + Vector3.new(0, 7, 0),
	})
	pcall(function()
		deps.StateService.push(player)
	end)
end

function OnboardingService.onPlayerAdded(player: Player)
	local done = deps.DataService.isTutorialDone(player)
	state.players[player] = blankStatus(done)
	state.lastActionAt[player] = 0
end

function OnboardingService.getState(player: Player): any
	if not state.players[player] then
		OnboardingService.onPlayerAdded(player)
	end
	return state.players[player]
end

function OnboardingService.progress(player: Player, key: string)
	if not player or type(key) ~= "string" then
		return
	end
	local status = state.players[player]
	if not status or status.done then
		return
	end

	local changed = false
	for _, objective in ipairs(status.objectives) do
		if objective.key == key and not objective.done then
			objective.done = true
			changed = true
			Util.toast(deps.Remotes, player, "Tutorial: " .. objective.label .. " ✓", "good", Config.TOAST.short)
			break
		end
	end
	if not changed then
		return
	end

	if allComplete(status) then
		finish(player, status)
	else
		pcall(function()
			deps.StateService.push(player)
		end)
	end
end

function OnboardingService.skip(player: Player)
	local status = state.players[player]
	if not status or status.done then
		return
	end
	status.done = true
	deps.DataService.setTutorialDone(player, true)
	pcall(function()
		deps.DataService.save(player)
	end)
	Util.toast(deps.Remotes, player, "Tutorial skipped. Press E for the Index and B for the Shop.", "info", Config.TOAST.normal)
	pcall(function()
		deps.StateService.push(player)
	end)
end

-- Only these three actions are legal on the TutorialAction remote.
local ACTIONS = {
	skip = function(player: Player)
		OnboardingService.skip(player)
	end,
	index = function(player: Player)
		OnboardingService.progress(player, "index")
	end,
	hello = function(player: Player)
		-- The HUD asks for one snapshot after its remotes are bound.
		pcall(function()
			deps.StateService.push(player)
		end)
	end,
}

function OnboardingService.handleAction(player: Player, action: any)
	if not alive(player) or type(action) ~= "string" or #action > 8 then
		return
	end
	local now = os.clock()
	if now - (state.lastActionAt[player] or 0) < Config.LIMITS.tutorial then
		return
	end
	state.lastActionAt[player] = now
	local handler = ACTIONS[action]
	if handler then
		handler(player)
	end
end

function OnboardingService.releasePlayer(player: Player)
	state.players[player] = nil
	state.lastActionAt[player] = nil
end

local function movementLoop()
	task.spawn(function()
		while state.running do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				local status = state.players[player]
				if status and not status.done then
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart")
					if root and root:IsA("BasePart") then
						if Util.flatDistance(root.Position, Config.MAP.spawnPos) > Config.TUTORIAL_MOVE_STUDS then
							OnboardingService.progress(player, "move")
						end
					end
				end
			end
		end
	end)
end

function OnboardingService.start(services: any)
	deps = services
	Config = services.Config
	Util = services.Util

	state.running = true
	state.players = {}
	state.lastActionAt = {}

	local remote = deps.Remotes and deps.Remotes.TutorialAction
	if remote then
		remote.OnServerEvent:Connect(function(player, action)
			OnboardingService.handleAction(player, action)
		end)
	end

	movementLoop()

	Players.PlayerRemoving:Connect(function(player)
		OnboardingService.releasePlayer(player)
	end)
end

function OnboardingService.stop()
	state.running = false
	state.players = {}
	state.lastActionAt = {}
end

return OnboardingService
