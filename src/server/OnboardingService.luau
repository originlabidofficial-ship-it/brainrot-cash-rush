--!strict
-- OnboardingService: owns the five-step first-join tutorial. It listens to real
-- server progress (movement polled from the character, grab/bank/rebirth calls
-- from the services, and a validated Index-open remote), ticks objectives live,
-- and remembers completion per player through DataService. The skip button is
-- also server-validated and persisted.

local Players = game:GetService("Players")

local OnboardingService = {}

local deps: any = nil
local states: { [Player]: any } = {}
local lastActionAt: { [Player]: number } = {}

local OBJECTIVES = {
	{ key = "move", label = "Move around the plaza" },
	{ key = "grab", label = "Grab a wild brainrot" },
	{ key = "bank", label = "Bank it on your base pad" },
	{ key = "index", label = "Open the Brainrot Index (E)" },
	{ key = "rebirth", label = "Rebirth once ($500)" },
}

local function buildState(done: boolean): any
	return {
		done = done,
		objectives = {},
	}
end

local function findObjective(key: string): any
	for _, objective in ipairs(OBJECTIVES) do
		if objective.key == key then
			return objective
		end
	end
	return nil
end

local function complete(player: Player, state: any)
	state.done = true
	deps.DataService.setTutorialDone(player, true)
	pcall(function()
		deps.DataService.save(player)
	end)
	deps.Util.toast(deps.Remotes, player, "Tutorial complete! The whole map is yours — press E for the Index, B for the Shop.", "good", 6)
	deps.Util.fireClient(deps.Remotes.FX, player, {
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
	local state = buildState(done)
	for _, objective in ipairs(OBJECTIVES) do
		table.insert(state.objectives, {
			key = objective.key,
			label = objective.label,
			done = done,
		})
	end
	states[player] = state
	lastActionAt[player] = 0
end

function OnboardingService.getState(player: Player): any
	if not states[player] then
		OnboardingService.onPlayerAdded(player)
	end
	return states[player]
end

function OnboardingService.progress(player: Player, key: string)
	local state = states[player]
	if not state or state.done or type(key) ~= "string" then
		return
	end
	local changed = false
	for _, objective in ipairs(state.objectives) do
		if objective.key == key and not objective.done then
			objective.done = true
			changed = true
			deps.Util.toast(deps.Remotes, player, "Tutorial: " .. objective.label .. " ✓", "good", 3)
			break
		end
	end
	if not changed then
		return
	end
	local allDone = true
	for _, objective in ipairs(state.objectives) do
		if not objective.done then
			allDone = false
			break
		end
	end
	if allDone then
		complete(player, state)
	else
		pcall(function()
			deps.StateService.push(player)
		end)
	end
end

function OnboardingService.skip(player: Player)
	local state = states[player]
	if not state or state.done then
		return
	end
	state.done = true
	deps.DataService.setTutorialDone(player, true)
	pcall(function()
		deps.DataService.save(player)
	end)
	deps.Util.toast(deps.Remotes, player, "Tutorial skipped. Press E for the Index and B for the Shop.", "info", 4)
	pcall(function()
		deps.StateService.push(player)
	end)
end

function OnboardingService.handleAction(player: Player, action: any)
	if type(action) ~= "string" or #action > 8 then
		return
	end
	local now = os.clock()
	if now - (lastActionAt[player] or 0) < 0.5 then
		return
	end
	lastActionAt[player] = now
	if action == "skip" then
		OnboardingService.skip(player)
	elseif action == "index" then
		OnboardingService.progress(player, "index")
	elseif action == "hello" then
		-- A late-binding HUD asks for a snapshot after its remotes are ready.
		pcall(function()
			deps.StateService.push(player)
		end)
	end
end

function OnboardingService.releasePlayer(player: Player)
	states[player] = nil
	lastActionAt[player] = nil
end

function OnboardingService.init(services: any)
	deps = services
	states = {}
	lastActionAt = {}

	local remote = deps.Remotes and deps.Remotes.TutorialAction
	if remote then
		remote.OnServerEvent:Connect(function(player, action)
			OnboardingService.handleAction(player, action)
		end)
	end

	-- Server-side movement detection: distance from spawn, not a client claim.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in ipairs(Players:GetPlayers()) do
				local state = states[player]
				if state and not state.done then
					local character = player.Character
					local hrp = character and character:FindFirstChild("HumanoidRootPart")
					if hrp and hrp:IsA("BasePart") then
						if deps.Util.flatDistance(hrp.Position, deps.Config.MAP.spawnPos) > 14 then
							OnboardingService.progress(player, "move")
						end
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		OnboardingService.releasePlayer(player)
	end)
end

return OnboardingService
