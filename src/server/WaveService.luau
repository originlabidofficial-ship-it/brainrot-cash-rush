--!strict
-- WaveService — the Brainrot Wave, every 90 seconds.
--
-- A neon wall sweeps east to west across the arena. Five seconds before it
-- launches the HUD is warned. Any player carrying creatures who is caught
-- outside their own guarded base drops everything back into the wild, which is
-- the whole reason bases exist.
--
-- The wave is fail-safe: the wall is always destroyed and the timer is always
-- re-armed, even if a decorative part fails halfway through a sweep.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local WaveService = {}

local Config: any = nil
local Util: any = nil
local deps: any = nil

local state = {
	running = false,
	busy = false,
	warningSent = false,
	count = 0,
	nextAt = 0,
	safeNoticed = {} :: { [Player]: boolean },
}

local function publish(timeLeft: number, warning: boolean, active: boolean)
	pcall(function()
		Workspace:SetAttribute("WaveTimeLeft", timeLeft)
		Workspace:SetAttribute("WaveWarning", warning)
		Workspace:SetAttribute("WaveActive", active)
		Workspace:SetAttribute("WaveNumber", state.count)
	end)
end

local function wallFolder(): Folder
	local folder = Workspace:FindFirstChild("Waves")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Waves"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

-- Build the moving wall. It is a model with a transparent root so PivotTo can
-- move the whole thing with one call per frame.
local function assembleWall(): Model
	local folder = wallFolder()
	local model = Instance.new("Model")
	model.Name = "BrainrotWave"

	local root = Instance.new("Part")
	root.Name = "WaveRoot"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CFrame = CFrame.new(0, 0, 0)
	root.Parent = model
	model.PrimaryPart = root

	local count = Config.WAVE_SEGMENTS
	local span = Config.MAP.arenaSize - 16
	local segmentWidth = span / count
	for i = 1, count do
		local z = -span / 2 + (i - 0.5) * segmentWidth
		local color = i % 2 == 0 and Color3.fromRGB(255, 65, 120) or Color3.fromRGB(255, 148, 205)

		local solid = Util.part({
			Name = "WaveSegment",
			Size = Vector3.new(7, 30, segmentWidth - 0.7),
			CFrame = CFrame.new(0, 17, z),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.42,
			CanCollide = false,
			CanQuery = false,
		}, model)

		Util.part({
			Name = "WaveCore",
			Size = Vector3.new(1.4, 25, segmentWidth - 2.2),
			CFrame = CFrame.new(0, 16.5, z),
			Color = Color3.fromRGB(255, 246, 250),
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			CanCollide = false,
			CanQuery = false,
		}, model)

		if i % 4 == 1 then
			local light = Instance.new("PointLight")
			light.Color = color
			light.Brightness = 3
			light.Range = 32
			light.Parent = solid
		end
	end

	model.WorldPivot = CFrame.new(0, 0, 0)
	model.Parent = folder
	return model
end

-- One player caught by the wall at world X.
local function hitPlayer(player: Player, wallX: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local position = root.Position
	if math.abs(position.X - wallX) > 7.5 or math.abs(position.Z) > Config.MAP.arenaHalf or position.Y > 60 then
		return
	end

	if deps.BaseService.isPlayerOnOwnPad(player) then
		if not state.safeNoticed[player] then
			state.safeNoticed[player] = true
			Util.toast(deps.Remotes, player, "Safe on your base! The wave rolled past.", "good", Config.TOAST.short)
		end
		return
	end

	if deps.BrainrotService.getCarriedCount(player) <= 0 then
		return
	end
	deps.BrainrotService.dropCarriedToWild(player, "wave")
	Util.toast(deps.Remotes, player, "THE WAVE GOT YOU! Your brainrots scattered back to the wild.", "bad", Config.TOAST.long)
	Util.fireClient(deps.Remotes.FX, player, { kind = "shake", strength = 1.4, duration = 0.7 })
	Util.fireClient(deps.Remotes.FX, player, { kind = "waveHit", duration = 1.2 })
end

local function sweep(wall: Model)
	local startX = Config.MAP.arenaHalf + 14
	local endX = -Config.MAP.arenaHalf - 14
	wall:PivotTo(CFrame.new(startX, 0, 0))

	local started = os.clock()
	while state.running do
		local alpha = math.min(1, (os.clock() - started) / Config.WAVE_DURATION)
		local x = startX + (endX - startX) * alpha
		pcall(function()
			wall:PivotTo(CFrame.new(x, 0, 0))
		end)
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Parent then
				local ok = pcall(hitPlayer, player, x)
				if not ok then
					warn("[WaveService] wave check skipped a player")
				end
			end
		end
		if alpha >= 1 then
			break
		end
		task.wait(Config.WAVE_SPEED_STEP)
	end
end

local function resetAfterWave()
	state.busy = false
	state.warningSent = false
	state.nextAt = os.clock() + Config.WAVE_INTERVAL
	publish(Config.WAVE_INTERVAL, false, false)
end

function WaveService.runWave()
	if state.busy or not state.running then
		return
	end
	state.busy = true
	state.count += 1
	state.safeNoticed = {}
	publish(0, false, true)

	Util.fireAll(deps.Remotes.FX, { kind = "waveStart", number = state.count })
	Util.broadcastToast(deps.Remotes, "THE BRAINROT WAVE IS HERE! Bank your brainrots!", "bad", Config.TOAST.normal)

	local wall = assembleWall()
	local ok, err = pcall(sweep, wall)
	if not ok then
		warn("[WaveService] sweep failed: " .. tostring(err))
	end
	if wall and wall.Parent then
		wall:Destroy()
	end
	resetAfterWave()

	Util.broadcastToast(deps.Remotes, "Wave over. The wild is restocked — go grab!", "info", Config.TOAST.short)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Parent then
			pcall(function()
				deps.QuestService.recordEvent(player, "wave", 1)
			end)
		end
	end
end

-- Public helper: an admin/reviewer can trigger a wave out of schedule.
function WaveService.summon()
	if state.busy or not state.running then
		return
	end
	state.nextAt = 0
	task.spawn(function()
		local ok, err = pcall(WaveService.runWave)
		if not ok then
			warn("[WaveService] summon failed: " .. tostring(err))
			state.busy = false
			local folder = Workspace:FindFirstChild("Waves")
			if folder then
				folder:ClearAllChildren()
			end
			resetAfterWave()
		end
	end)
end

local function tick()
	local now = os.clock()
	if state.busy then
		return
	end
	local left = math.max(0, state.nextAt - now)
	local warning = left <= Config.WAVE_WARN and left > 0
	publish(left, warning, false)
	if warning and not state.warningSent then
		state.warningSent = true
		Util.fireAll(deps.Remotes.FX, { kind = "waveWarning", seconds = Config.WAVE_WARN })
		Util.broadcastToast(deps.Remotes, string.format("WAVE IN %d SECONDS — GET HOME!", Config.WAVE_WARN), "bad", Config.TOAST.long)
	end
	if left <= 0 then
		WaveService.summon()
	end
end

function WaveService.start(services: any)
	deps = services
	Config = services.Config
	Util = services.Util

	state.running = true
	state.busy = false
	state.warningSent = false
	state.count = 0
	state.safeNoticed = {}
	state.nextAt = os.clock() + Config.WAVE_INTERVAL
	publish(Config.WAVE_INTERVAL, false, false)

	task.spawn(function()
		while state.running do
			local ok, err = pcall(tick)
			if not ok then
				warn("[WaveService] timer tick failed: " .. tostring(err))
			end
			task.wait(0.25)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		state.safeNoticed[player] = nil
	end)
end

function WaveService.stop()
	state.running = false
	state.busy = false
	local folder = Workspace:FindFirstChild("Waves")
	if folder then
		folder:ClearAllChildren()
	end
end

return WaveService
