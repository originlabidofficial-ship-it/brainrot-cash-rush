-- WaveService: the 90-second Brainrot Wave. A glowing neon wall of parts
-- sweeps across the arena from east to west. Five seconds before it launches,
-- the HUD screams. A carrying player caught in it drops everything back to the
-- wild, unless they are standing on their own base deck (the safe zone), which
-- is why players learn to run home.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local WaveService = {}

local Util
local Config
local deps: any = nil

local nextWaveAt = 0
local waveBusy = false
local warningSent = false
local safeNoticed: { [Player]: boolean } = {}
local waveCount = 0

local function setWaveAttributes(timeLeft: number, warning: boolean, active: boolean)
	pcall(function()
		Workspace:SetAttribute("WaveTimeLeft", timeLeft)
		Workspace:SetAttribute("WaveWarning", warning)
		Workspace:SetAttribute("WaveActive", active)
		Workspace:SetAttribute("WaveNumber", waveCount)
	end)
end

local function buildWall(): Model
	local folder = Workspace:FindFirstChild("Waves")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Waves"
		folder.Parent = Workspace
	end

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

	local segmentWidth = 13.8
	local count = 18
	for i = 1, count do
		local z = -117 + (i - 1) * segmentWidth
		local tint = i % 2 == 0 and Color3.fromRGB(255, 65, 120) or Color3.fromRGB(255, 140, 200)
		local solid = Util.part({
			Size = Vector3.new(7, 30, segmentWidth - 0.7),
			CFrame = CFrame.new(0, 17, z),
			Color = tint,
			Material = Enum.Material.Neon,
			Transparency = 0.42,
			CanCollide = false,
			CanQuery = false,
		}, model)
		solid.Name = "WaveSegment"

		local core = Util.part({
			Size = Vector3.new(1.4, 25, segmentWidth - 2.2),
			CFrame = CFrame.new(0, 16.5, z),
			Color = Color3.fromRGB(255, 245, 250),
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			CanCollide = false,
			CanQuery = false,
		}, model)
		core.Name = "WaveCore"

		if i % 4 == 1 then
			local light = Instance.new("PointLight")
			light.Color = tint
			light.Brightness = 3
			light.Range = 32
			light.Parent = solid
		end
	end

	model.WorldPivot = CFrame.new(0, 0, 0)
	model.Parent = folder
	return model
end

local function checkPlayers(wallX: number)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Parent then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local pos = root.Position
				if math.abs(pos.X - wallX) <= 7.5 and math.abs(pos.Z) <= 122 and pos.Y < 60 then
					if deps.BaseService.isPlayerOnOwnPad(player) then
						if not safeNoticed[player] then
							safeNoticed[player] = true
							Util.toast(deps.Remotes, player, "Safe on your base! The wave rolled past.", "good", 3)
						end
					else
						local carried = deps.BrainrotService.getCarriedCount(player)
						if carried > 0 then
							deps.BrainrotService.dropCarriedToWild(player, "wave")
							Util.toast(deps.Remotes, player, "THE WAVE GOT YOU! Your brainrots scattered back to the wild.", "bad", 5)
							Util.fireClient(deps.Remotes.FX, player, {
								kind = "shake",
								strength = 1.4,
								duration = 0.7,
							})
							Util.fireClient(deps.Remotes.FX, player, {
								kind = "waveHit",
								duration = 1.2,
							})
						end
					end
				end
			end
		end
	end
end

function WaveService.runWave()
	if waveBusy then
		return
	end
	waveBusy = true
	waveCount += 1
	safeNoticed = {}
	setWaveAttributes(0, false, true)

	Util.fireAll(deps.Remotes.FX, {
		kind = "waveStart",
		number = waveCount,
	})
	Util.broadcastToast(deps.Remotes, "THE BRAINROT WAVE IS HERE! Bank your brainrots!", "bad", 4)

	local wall = buildWall()
	local startX = Config.MAP.arenaHalf + 14
	local endX = -Config.MAP.arenaHalf - 14
	wall:PivotTo(CFrame.new(startX, 0, 0))

	local duration = Config.WAVE_DURATION
	local started = os.clock()
	while true do
		local alpha = math.min(1, (os.clock() - started) / duration)
		local x = startX + (endX - startX) * alpha
		pcall(function()
			wall:PivotTo(CFrame.new(x, 0, 0))
		end)
		checkPlayers(x)
		if alpha >= 1 then
			break
		end
		task.wait(0.05)
	end

	if wall and wall.Parent then
		wall:Destroy()
	end
	waveBusy = false
	nextWaveAt = os.clock() + Config.WAVE_INTERVAL
	warningSent = false
	setWaveAttributes(Config.WAVE_INTERVAL, false, false)
	Util.broadcastToast(deps.Remotes, "Wave over. The wild is restocked — go grab!", "info", 3)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Parent then
			pcall(function()
				deps.QuestService.recordEvent(player, "wave", 1)
			end)
		end
	end
end

-- Public helper so a reviewer (or a future admin) can summon a wave on demand.
function WaveService.summon()
	if not waveBusy then
		warningSent = true
		task.spawn(function()
			local ok, err = pcall(WaveService.runWave)
			if not ok then
				warn("[WaveService] wave failed: " .. tostring(err))
				-- Never leave the wave stuck on: reset so the next 90s round
				-- still fires even if a decorative part failed.
				waveBusy = false
				warningSent = false
				nextWaveAt = os.clock() + Config.WAVE_INTERVAL
				setWaveAttributes(Config.WAVE_INTERVAL, false, false)
				local waves = Workspace:FindFirstChild("Waves")
				if waves then
					waves:ClearAllChildren()
				end
			end
		end)
	end
end

local function countdownLoop()
	task.spawn(function()
		while true do
			local now = os.clock()
			local left = math.max(0, nextWaveAt - now)
			if not waveBusy then
				local warning = left <= Config.WAVE_WARN and left > 0
				setWaveAttributes(left, warning, false)
				if warning and not warningSent then
					warningSent = true
					Util.fireAll(deps.Remotes.FX, {
						kind = "waveWarning",
						seconds = Config.WAVE_WARN,
					})
					Util.broadcastToast(deps.Remotes, "WAVE IN 5 SECONDS — GET HOME!", "bad", 5)
				end
				if left <= 0 then
					WaveService.summon()
				end
			end
			task.wait(0.25)
		end
	end)
end

function WaveService.init(services: any)
	deps = services
	Util = services.Util
	Config = services.Config
	waveBusy = false
	warningSent = false
	waveCount = 0
	nextWaveAt = os.clock() + Config.WAVE_INTERVAL
	setWaveAttributes(Config.WAVE_INTERVAL, false, false)
	countdownLoop()
end

return WaveService
