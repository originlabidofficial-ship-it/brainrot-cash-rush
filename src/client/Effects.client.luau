-- Effects: the client-side juice layer. Server remote events become floating
-- cash text, capture sparkles, steal highlights, screen shakes, red wave
-- flashes and rebirth fireworks. It also animates the world's neon decorations
-- locally, so none of that decoration costs the server a replicated part change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui", 15)
if not playerGui then
	return
end

local Shared = ReplicatedStorage:WaitForChild("Shared", 15)
if not Shared then
	return
end
local Config = require(Shared:WaitForChild("Config", 10))
local Util = require(Shared:WaitForChild("Util", 10))

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local FXRemote = Remotes and Remotes:WaitForChild("FX", 10)

local GOLD = Color3.fromRGB(255, 211, 74)
local CYAN = Color3.fromRGB(86, 231, 255)
local PINK = Color3.fromRGB(255, 92, 202)
local RED = Color3.fromRGB(255, 70, 100)
local GREEN = Color3.fromRGB(92, 242, 168)
local WHITE = Color3.fromRGB(255, 255, 255)

local fxGui = Instance.new("ScreenGui")
fxGui.Name = "BrainrotEffects"
fxGui.ResetOnSpawn = false
fxGui.IgnoreGuiInset = true
fxGui.DisplayOrder = 15
fxGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
fxGui.Parent = playerGui

local flashFrame = Instance.new("Frame")
flashFrame.Name = "Flash"
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BackgroundColor3 = RED
flashFrame.BackgroundTransparency = 1
flashFrame.BorderSizePixel = 0
flashFrame.ZIndex = 50
flashFrame.Parent = fxGui

-- Camera shake --------------------------------------------------------------
local shakeStrength = 0
local shakeTime = 0
local shakeDuration = 0

local function shake(strength: number, duration: number)
	shakeStrength = math.max(shakeStrength, strength)
	shakeTime = math.max(shakeTime, duration)
	shakeDuration = math.max(shakeDuration, duration)
end

RunService.RenderStepped:Connect(function(dt)
	if shakeTime <= 0 then
		return
	end
	shakeTime = math.max(0, shakeTime - dt)
	local falloff = shakeDuration > 0 and (shakeTime / shakeDuration) or 0
	local s = shakeStrength * falloff
	local offset = Vector3.new(
		(math.random() * 2 - 1) * s,
		(math.random() * 2 - 1) * s,
		(math.random() * 2 - 1) * s * 0.5
	)
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CFrame = cam.CFrame + offset
	end
	if shakeTime <= 0 then
		shakeStrength = 0
	end
end)

-- Screen flash --------------------------------------------------------------
local flashTween = nil
local function flash(color: Color3, peak: number, duration: number)
	if flashTween then
		flashTween:Cancel()
	end
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = 1
	flashTween = TweenService:Create(flashFrame, TweenInfo.new(duration * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = peak,
	})
	flashTween:Play()
	task.delay(duration * 0.2, function()
		TweenService:Create(flashFrame, TweenInfo.new(duration * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
	end)
end

-- World helpers -------------------------------------------------------------
local effectFolder = Instance.new("Folder")
effectFolder.Name = "ClientEffects"
effectFolder.Parent = Workspace

local function effectPart(position: Vector3, color: Color3, size: number): Part
	local p = Instance.new("Part")
	p.Size = Vector3.new(size, size, size)
	p.CFrame = CFrame.new(position)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Shape = Enum.PartType.Ball
	p.Parent = effectFolder
	return p
end

local function ring(position: Vector3, color: Color3, startSize: number, endSize: number, duration: number)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.16, startSize, startSize)
	p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.15
	p.Parent = effectFolder
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.16, endSize, endSize),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, duration + 0.1)
end

local function burst(position: Vector3, color: Color3, count: number, speed: number)
	for i = 1, count do
		local p = effectPart(position, color, math.random(35, 75) / 100)
		local dir = Vector3.new(math.random() * 2 - 1, math.random() * 1.2 + 0.2, math.random() * 2 - 1)
		if dir.Magnitude < 0.1 then
			dir = Vector3.new(0, 1, 0)
		end
		dir = dir.Unit * (speed * (0.5 + math.random()))
		TweenService:Create(p, TweenInfo.new(0.55 + math.random() * 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(position + dir),
			Transparency = 1,
			Size = Vector3.new(0.05, 0.05, 0.05),
		}):Play()
		Debris:AddItem(p, 1)
	end
end

local function floatText(position: Vector3, text: string, color: Color3, scale: number?)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Parent = effectFolder

	local bb = Instance.new("BillboardGui")
	bb.Name = "FloatText"
	bb.Adornee = anchor
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 120
	bb.Size = UDim2.fromOffset(260 * (scale or 1), 70 * (scale or 1))
	bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.fromRGB(20, 12, 30)
	label.TextStrokeTransparency = 0.15
	label.Parent = bb

	TweenService:Create(anchor, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(position + Vector3.new(0, 6, 0)),
	}):Play()
	TweenService:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(anchor, 1.35)
end

-- Highlight the local character while stealing (and when hit by a steal).
local highlight: Highlight? = nil
local function characterHighlight(color: Color3, duration: number, labelText: string?)
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
	local character = player.Character
	if not character then
		return
	end
	local h = Instance.new("Highlight")
	h.Name = "StealHighlight"
	h.FillColor = color
	h.FillTransparency = 0.55
	h.OutlineColor = WHITE
	h.OutlineTransparency = 0.1
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = character
	highlight = h
	if labelText then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			floatText(hrp.Position + Vector3.new(0, 4, 0), labelText, color, 0.8)
		end
	end
	task.delay(duration, function()
		if h and h.Parent then
			h:Destroy()
		end
		if highlight == h then
			highlight = nil
		end
	end)
end

-- Remote effects ------------------------------------------------------------
local function onEffect(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	local position = payload.position
	if typeof(position) ~= "Vector3" then
		position = nil
	end

	if kind == "spawn" then
		local color = payload.color
		if typeof(color) ~= "Color3" then
			color = PINK
		end
		if position then
			ring(position, color, 1, 8, 0.55)
			burst(position, color, 4, 3)
		end
	elseif kind == "grab" then
		if position then
			local color = typeof(payload.color) == "Color3" and payload.color or CYAN
			ring(position, color, 1, 10, 0.45)
			burst(position, color, 10, 4)
			floatText(position + Vector3.new(0, 2, 0), "GRABBED!", color)
		end
	elseif kind == "bank" or kind == "place" then
		if position then
			ring(position, GOLD, 2, 16, 0.7)
			burst(position, GOLD, 16, 6)
			floatText(position, payload.text or "+CASH!", GOLD, 1)
		end
	elseif kind == "float" then
		if position then
			local tone = payload.tone
			local color = tone == "gold" and GOLD or GREEN
			floatText(position, payload.text or "+$", color, 1.15)
		end
	elseif kind == "steal" then
		if position then
			ring(position, RED, 2, 14, 0.6)
			burst(position, RED, 12, 5)
			floatText(position + Vector3.new(0, 2, 0), payload.text or "STOLEN!", RED, 0.9)
		end
		flash(RED, 0.82, 0.5)
		shake(0.5, 0.3)
	elseif kind == "stealHighlight" then
		characterHighlight(GOLD, payload.duration or 2, "STEALING")
		flash(GOLD, 0.9, 0.3)
	elseif kind == "waveWarning" then
		flash(RED, 0.72, 0.8)
		shake(0.55, 0.6)
		floatText((player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or Vector3.new(0, 8, 0)) + Vector3.new(0, 5, 0), "RUN HOME!", RED, 1.2)
	elseif kind == "waveStart" then
		flash(RED, 0.55, 1.1)
		shake(1.1, 0.9)
	elseif kind == "waveHit" then
		flash(RED, 0.6, 1.2)
		shake(1.3, 0.8)
	elseif kind == "rebirth" then
		if position then
			ring(position, GOLD, 3, 34, 1.1)
			ring(position, WHITE, 1, 24, 0.8)
			burst(position, GOLD, 30, 10)
			burst(position, PINK, 18, 7)
			floatText(position + Vector3.new(0, 8, 0), "REBIRTH x" .. tostring(payload.level or 1), GOLD, 1.35)
		end
		flash(GOLD, 0.55, 1.2)
		shake(0.6, 0.6)
	elseif kind == "shake" then
		shake(payload.strength or 0.6, payload.duration or 0.4)
	elseif kind == "levelUp" then
		if position then
			burst(position, CYAN, 14, 5)
		end
	end
end

if FXRemote then
	FXRemote.OnClientEvent:Connect(onEffect)
end

-- Ambient decoration animation ----------------------------------------------
task.spawn(function()
	local world = Workspace:WaitForChild("World", 15)
	if not world then
		return
	end
	local fountain = world:FindFirstChild("Fountain")
	local water = fountain and fountain:FindFirstChild("Water")
	local coin = fountain and fountain:FindFirstChild("FountainCoin")
	local orbits = world:FindFirstChild("Orbits")

	local orbitModels = {}
	if orbits then
		for _, child in ipairs(orbits:GetChildren()) do
			if child:IsA("Model") then
				local pivot = child:GetPivot()
				child.WorldPivot = CFrame.new(0, pivot.Position.Y, 0)
				table.insert(orbitModels, child)
			end
		end
	end

	local tick = 0
	while true do
		local dt = RunService.RenderStepped:Wait()
		tick += dt
		if water and water:IsA("BasePart") then
			water.Transparency = 0.16 + math.sin(tick * 2.2) * 0.07
		end
		if coin and coin:IsA("BasePart") then
			coin.CFrame = CFrame.new(coin.Position) * CFrame.Angles(0, tick * 1.4, 0)
		end
		for _, model in ipairs(orbitModels) do
			if model.Parent then
				local y = model:GetPivot().Position.Y
				model:PivotTo(CFrame.new(0, y, 0) * CFrame.Angles(0, tick * 0.16, 0))
			end
		end
	end
end)

-- Lazy sparkles drifting around the fountain, wild zone and portal.
task.spawn(function()
	local spots = {
		Vector3.new(0, 3, 0),
		Config.MAP.wildCenter,
		Vector3.new(0, 7, 94),
	}
	while true do
		task.wait(0.8)
		local base = spots[math.random(#spots)]
		local p = effectPart(
			base + Vector3.new(math.random(-16, 16), math.random(0, 8), math.random(-16, 16)),
			math.random() < 0.5 and CYAN or PINK,
			math.random(18, 32) / 100
		)
		p.Transparency = 0.25
		TweenService:Create(p, TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(p.Position + Vector3.new(math.random(-2, 2), 7, math.random(-2, 2))),
			Transparency = 1,
		}):Play()
		Debris:AddItem(p, 2.6)
	end
end)

-- A soft pulse on the plaza rim for a living world feel.
task.spawn(function()
	local world = Workspace:WaitForChild("World", 15)
	local rim = world and world:FindFirstChild("PlazaRim")
	if rim and rim:IsA("BasePart") then
		while true do
			rim.Transparency = 0.15 + math.sin(os.clock() * 1.8) * 0.1
			task.wait(0.1)
		end
	end
end)
