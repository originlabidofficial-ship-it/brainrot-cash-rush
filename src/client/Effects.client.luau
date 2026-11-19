--!strict
-- Effects.client.luau — all client-side juice.
--
-- The server sends one FX RemoteEvent with a tagged table; this script maps the
-- tag to a local visual. Nothing here has gameplay authority, and nothing here
-- talks back to the server. Keeping the effects local also means the server
-- never replicates a part change just to make something sparkle.
--
-- It installs once: a duplicate copy removes the previous ScreenGui folder and
-- world folder first, so there is exactly one flash layer and one shake driver.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 20)
if not playerGui then
	return
end
local Shared = ReplicatedStorage:WaitForChild("Shared", 20)
if not Shared then
	return
end
local Config = require(Shared:WaitForChild("Config", 10))

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
if not Remotes then
	return
end
local FX = Remotes:WaitForChild("FX", 10)

-- Colours ------------------------------------------------------------------
local GOLD = Color3.fromRGB(255, 211, 74)
local CYAN = Color3.fromRGB(86, 231, 255)
local PINK = Color3.fromRGB(255, 92, 202)
local RED = Color3.fromRGB(255, 70, 100)
local GREEN = Color3.fromRGB(92, 242, 168)
local WHITE = Color3.fromRGB(255, 255, 255)

-- One instance of everything ----------------------------------------------
local previousGui = playerGui:FindFirstChild("BrainrotEffects")
if previousGui then
	previousGui:Destroy()
end
local previousWorld = Workspace:FindFirstChild("ClientEffects")
if previousWorld then
	previousWorld:Destroy()
end

local overlay = Instance.new("ScreenGui")
overlay.Name = "BrainrotEffects"
overlay.ResetOnSpawn = false
overlay.IgnoreGuiInset = true
overlay.DisplayOrder = 15
overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
overlay.Parent = playerGui

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = RED
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 40
flash.Parent = overlay

local stray = Instance.new("Folder")
stray.Name = "ClientEffects"
stray.Parent = Workspace

-- Camera shake -------------------------------------------------------------
local shake = {
	strength = 0,
	left = 0,
	total = 0,
}

local function addShake(strength: number?, duration: number?)
	shake.strength = math.max(shake.strength, tonumber(strength) or 0.5)
	shake.left = math.max(shake.left, tonumber(duration) or 0.4)
	shake.total = math.max(shake.total, shake.left)
end

RunService.RenderStepped:Connect(function(delta)
	if shake.left <= 0 then
		return
	end
	shake.left = math.max(0, shake.left - delta)
	local falloff = shake.total > 0 and shake.left / shake.total or 0
	local amount = shake.strength * falloff
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CFrame = camera.CFrame + Vector3.new(
			(math.random() * 2 - 1) * amount,
			(math.random() * 2 - 1) * amount,
			(math.random() * 2 - 1) * amount * 0.5
		)
	end
	if shake.left <= 0 then
		shake.strength = 0
	end
end)

-- Screen flash -------------------------------------------------------------
local flashTween: Tween? = nil

local function flashScreen(color: Color3, peak: number, duration: number)
	if flashTween then
		flashTween:Cancel()
	end
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1
	flashTween = TweenService:Create(flash, TweenInfo.new(duration * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = peak,
	})
	flashTween:Play()
	task.delay(duration * 0.2, function()
		TweenService:Create(flash, TweenInfo.new(duration * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
	end)
end

-- World primitives ---------------------------------------------------------

local function spark(position: Vector3, color: Color3, size: number): Part
	local part = Instance.new("Part")
	part.Size = Vector3.new(size, size, size)
	part.CFrame = CFrame.new(position)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Shape = Enum.PartType.Ball
	part.Parent = stray
	return part
end

local function ringPulse(position: Vector3, color: Color3, from: number, to: number, duration: number)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.16, from, from)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.15
	ring.Parent = stray
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.16, to, to),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, duration + 0.1)
end

local function confetti(position: Vector3, color: Color3, count: number, speed: number)
	for _ = 1, count do
		local bit = spark(position, color, math.random(35, 75) / 100)
		local direction = Vector3.new(math.random() * 2 - 1, math.random() * 1.2 + 0.2, math.random() * 2 - 1)
		if direction.Magnitude < 0.1 then
			direction = Vector3.new(0, 1, 0)
		end
		direction = direction.Unit * (speed * (0.5 + math.random()))
		TweenService:Create(bit, TweenInfo.new(0.55 + math.random() * 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(position + direction),
			Transparency = 1,
			Size = Vector3.new(0.05, 0.05, 0.05),
		}):Play()
		Debris:AddItem(bit, 1)
	end
end

local function popText(position: Vector3, message: string, color: Color3, scale: number?)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Parent = stray

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FloatText"
	billboard.Adornee = anchor
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 120
	billboard.Size = UDim2.fromOffset(260 * (scale or 1), 70 * (scale or 1))
	billboard.Parent = anchor

	local caption = Instance.new("TextLabel")
	caption.BackgroundTransparency = 1
	caption.Size = UDim2.fromScale(1, 1)
	caption.Font = Enum.Font.GothamBlack
	caption.Text = message
	caption.TextColor3 = color
	caption.TextScaled = true
	caption.TextStrokeColor3 = Color3.fromRGB(20, 12, 30)
	caption.TextStrokeTransparency = 0.15
	caption.Parent = billboard

	TweenService:Create(anchor, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(position + Vector3.new(0, 6, 0)),
	}):Play()
	TweenService:Create(caption, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(anchor, 1.35)
end

-- Character highlight ------------------------------------------------------
local activeHighlight: Highlight? = nil

local function highlightCharacter(color: Color3, duration: number, caption: string?)
	if activeHighlight then
		activeHighlight:Destroy()
		activeHighlight = nil
	end
	local character = player.Character
	if not character then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "StealHighlight"
	highlight.FillColor = color
	highlight.FillTransparency = 0.55
	highlight.OutlineColor = WHITE
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character
	activeHighlight = highlight

	if caption then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			popText(root.Position + Vector3.new(0, 4, 0), caption, color, 0.8)
		end
	end
	task.delay(duration, function()
		if highlight and highlight.Parent then
			highlight:Destroy()
		end
		if activeHighlight == highlight then
			activeHighlight = nil
		end
	end)
end

local function localPosition(): Vector3
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return Config.MAP.spawnPos
end

-- Payload handlers ---------------------------------------------------------
-- A table keeps the dispatch flat: adding an effect is one key, not another
-- branch in a growing if-chain.

local function validPosition(value: any): Vector3?
	if typeof(value) == "Vector3" then
		return value
	end
	return nil
end

local function colorOr(value: any, fallback: Color3): Color3
	if typeof(value) == "Color3" then
		return value
	end
	return fallback
end

local HANDLERS: { [string]: (any, Vector3?) -> () } = {}

HANDLERS.spawn = function(payload, position)
	if not position then
		return
	end
	local color = colorOr(payload.color, PINK)
	ringPulse(position, color, 1, 8, 0.55)
	confetti(position, color, 4, 3)
end

HANDLERS.grab = function(payload, position)
	if not position then
		return
	end
	local color = colorOr(payload.color, CYAN)
	ringPulse(position, color, 1, 10, 0.45)
	confetti(position, color, 10, 4)
	popText(position + Vector3.new(0, 2, 0), "GRABBED!", color)
end

HANDLERS.bank = function(payload, position)
	if not position then
		return
	end
	ringPulse(position, GOLD, 2, 16, 0.7)
	confetti(position, GOLD, 16, 6)
	popText(position, payload.text or "+CASH!", GOLD, 1)
end

HANDLERS.place = HANDLERS.bank

HANDLERS.padPulse = function(_, position)
	if not position then
		return
	end
	ringPulse(position, GOLD, 4, 22, 0.9)
	confetti(position, GOLD, 12, 5)
end

HANDLERS.float = function(payload, position)
	if not position then
		return
	end
	local color = payload.tone == "gold" and GOLD or GREEN
	popText(position, payload.text or "+$", color, 1.15)
end

HANDLERS.steal = function(payload, position)
	if position then
		ringPulse(position, RED, 2, 14, 0.6)
		confetti(position, RED, 12, 5)
		popText(position + Vector3.new(0, 2, 0), payload.text or "STOLEN!", RED, 0.9)
	end
	flashScreen(RED, 0.82, 0.5)
	addShake(0.5, 0.3)
end

HANDLERS.stealHighlight = function(payload)
	highlightCharacter(GOLD, tonumber(payload.duration) or 2, payload.text or "STEALING")
	flashScreen(GOLD, 0.9, 0.3)
end

HANDLERS.waveWarning = function()
	flashScreen(RED, 0.72, 0.8)
	addShake(0.55, 0.6)
	popText(localPosition() + Vector3.new(0, 5, 0), "RUN HOME!", RED, 1.2)
end

HANDLERS.waveStart = function()
	flashScreen(RED, 0.55, 1.1)
	addShake(1.1, 0.9)
end

HANDLERS.waveHit = function()
	flashScreen(RED, 0.6, 1.2)
	addShake(1.3, 0.8)
end

HANDLERS.rebirth = function(payload, position)
	if position then
		ringPulse(position, GOLD, 3, 34, 1.1)
		ringPulse(position, WHITE, 1, 24, 0.8)
		confetti(position, GOLD, 30, 10)
		confetti(position, PINK, 18, 7)
		popText(position + Vector3.new(0, 8, 0), "REBIRTH x" .. tostring(payload.level or 1), GOLD, 1.35)
	end
	flashScreen(GOLD, 0.55, 1.2)
	addShake(0.6, 0.6)
end

HANDLERS.shake = function(payload)
	addShake(payload.strength or 0.6, payload.duration or 0.4)
end

HANDLERS.upgrade = function(payload, position)
	if position then
		ringPulse(position, GOLD, 2, 18, 0.65)
		confetti(position, GOLD, 18, 6)
		confetti(position, CYAN, 10, 4)
		popText(position + Vector3.new(0, 2.5, 0), payload.text or "UPGRADE!", GOLD, 1.15)
	end
	flashScreen(GOLD, 0.4, 0.4)
end

HANDLERS.levelUp = HANDLERS.upgrade

HANDLERS.quest = function(payload, position)
	if not position then
		return
	end
	ringPulse(position, GREEN, 2, 16, 0.7)
	confetti(position, GREEN, 20, 6)
	popText(position + Vector3.new(0, 2, 0), payload.text or "QUEST!", GREEN, 1.1)
end

HANDLERS.discover = function(payload, position)
	if not position then
		return
	end
	local color = colorOr(payload.color, PINK)
	ringPulse(position, color, 1, 14, 0.6)
	confetti(position, color, 24, 7)
	popText(position + Vector3.new(0, 2, 0), "NEW SPECIES!", color, 1.1)
end

HANDLERS.magnet = function(_, position)
	if position then
		ringPulse(position, CYAN, 1, 8, 0.4)
	end
end

local function onEffect(payload: any)
	if type(payload) ~= "table" or type(payload.kind) ~= "string" then
		return
	end
	local handler = HANDLERS[payload.kind]
	if not handler then
		return
	end
	local ok, err = pcall(handler, payload, validPosition(payload.position))
	if not ok then
		warn("[Effects] dropped a " .. payload.kind .. " effect: " .. tostring(err))
	end
end

FX.OnClientEvent:Connect(onEffect)

-- Ambient animation --------------------------------------------------------
-- The server never animates decoration; these loops only touch parts under
-- World and stop quietly when the map is not there yet.

task.spawn(function()
	local world = Workspace:WaitForChild("World", 20)
	if not world then
		return
	end
	local fountain = world:FindFirstChild("Fountain")
	local water = fountain and fountain:FindFirstChild("Water")
	local coin = fountain and fountain:FindFirstChild("FountainCoin")
	local orbits = world:FindFirstChild("Orbits")

	local spinners = {}
	if orbits then
		for _, child in ipairs(orbits:GetChildren()) do
			if child:IsA("Model") then
				local pivot = child:GetPivot()
				child.WorldPivot = CFrame.new(0, pivot.Position.Y, 0)
				table.insert(spinners, child)
			end
		end
	end

	local clock = 0
	while true do
		local delta = RunService.RenderStepped:Wait()
		clock += delta

		if water and water:IsA("BasePart") then
			water.Transparency = 0.16 + math.sin(clock * 2.2) * 0.07
		end
		if coin and coin:IsA("BasePart") then
			coin.CFrame = CFrame.new(coin.Position) * CFrame.Angles(0, clock * 1.4, 0)
		end
		for _, model in ipairs(spinners) do
			if model.Parent then
				local y = model:GetPivot().Position.Y
				model:PivotTo(CFrame.new(0, y, 0) * CFrame.Angles(0, clock * 0.16, 0))
			end
		end
	end
end)

-- Lazy sparkles drifting over the three landmark spots.
task.spawn(function()
	local anchors = {
		Vector3.new(0, 3, 0),
		Config.MAP.wildCenter,
		Vector3.new(0, 7, 94),
	}
	while true do
		task.wait(0.8)
		local base = anchors[math.random(#anchors)]
		local sparkle = spark(
			base + Vector3.new(math.random(-16, 16), math.random(0, 8), math.random(-16, 16)),
			math.random() < 0.5 and CYAN or PINK,
			math.random(18, 32) / 100
		)
		sparkle.Transparency = 0.25
		TweenService:Create(sparkle, TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(sparkle.Position + Vector3.new(math.random(-2, 2), 7, math.random(-2, 2))),
			Transparency = 1,
		}):Play()
		Debris:AddItem(sparkle, 2.6)
	end
end)

-- A slow pulse on the plaza rim keeps the hub feeling alive.
task.spawn(function()
	local world = Workspace:WaitForChild("World", 20)
	local rim = world and world:FindFirstChild("PlazaRim")
	if not (rim and rim:IsA("BasePart")) then
		return
	end
	while true do
		rim.Transparency = 0.15 + math.sin(os.clock() * 1.8) * 0.1
		task.wait(0.1)
	end
end)
