-- HUD: the ScreenGui layer over the 3D world. Top bar (cash, multiplier,
-- carry, wave countdown), rebirth button, rotating hint bar, warning banner and
-- event toasts. All values come from leaderstats or replicated attributes; the
-- only thing this script asks the server to do is fire the Rebirth remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
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
local RebirthRemote = Remotes and Remotes:WaitForChild("Rebirth", 10)
local FXRemote = Remotes and Remotes:WaitForChild("FX", 10)

local GOLD = Color3.fromRGB(255, 211, 74)
local CYAN = Color3.fromRGB(86, 231, 255)
local PINK = Color3.fromRGB(255, 92, 202)
local GREEN = Color3.fromRGB(92, 242, 168)
local RED = Color3.fromRGB(255, 76, 104)
local PURPLE = Color3.fromRGB(185, 118, 255)
local DARK = Color3.fromRGB(18, 16, 33)
local WHITE = Color3.fromRGB(255, 255, 255)

local function safeCashFolder(): Folder?
	return player:FindFirstChild("leaderstats") :: Folder?
end

local gui = Instance.new("ScreenGui")
gui.Name = "BrainrotHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 20
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local function roundFrame(parent: Instance, radius: number): Frame
	local f = Util.frame({
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.08,
	}, parent)
	Util.corner(f, radius)
	return f
end

-- Top bar -------------------------------------------------------------------
local topBar = Util.frame({
	Size = UDim2.fromOffset(760, 92),
	Position = UDim2.new(0.5, 0, 0, 14),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.fromRGB(22, 18, 40),
	BackgroundTransparency = 0.06,
}, gui)
topBar.Name = "TopBar"
Util.corner(topBar, 20)
local topStroke = Util.stroke(topBar, Color3.fromRGB(255, 255, 255), 1.5, 0.82)
local topGradient = Instance.new("UIGradient")
topGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(48, 33, 82)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(24, 20, 44)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 24, 56)),
})
topGradient.Rotation = 18
topGradient.Parent = topBar
local topShade = Util.frame({
	Size = UDim2.new(1, 0, 0, 30),
	Position = UDim2.new(0, 0, 0, 0),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.94,
}, topBar)
Util.corner(topShade, 20)
topShade.ZIndex = 0

-- Logo block.
local logo = Util.frame({
	Size = UDim2.fromOffset(180, 76),
	Position = UDim2.fromOffset(14, 8),
	BackgroundTransparency = 1,
}, topBar)
logo.ZIndex = 2
Util.label({
	Size = UDim2.new(1, 0, 0, 26),
	Text = "BRAINROT",
	Font = Enum.Font.GothamBlack,
	TextColor3 = WHITE,
	TextSize = 24,
	TextXAlignment = Enum.TextXAlignment.Left,
}, logo).ZIndex = 2
Util.label({
	Size = UDim2.new(1, 0, 0, 26),
	Position = UDim2.fromOffset(0, 25),
	Text = "CASH RUSH",
	Font = Enum.Font.GothamBlack,
	TextColor3 = GOLD,
	TextSize = 24,
	TextXAlignment = Enum.TextXAlignment.Left,
}, logo).ZIndex = 2
Util.label({
	Size = UDim2.new(1, 0, 0, 15),
	Position = UDim2.fromOffset(0, 53),
	Text = "GRAB  •  BANK  •  REBIRTH",
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(168, 158, 205),
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
}, logo).ZIndex = 2

-- Cash block.
local cashBox = Util.frame({
	Size = UDim2.fromOffset(220, 78),
	Position = UDim2.fromOffset(198, 7),
	BackgroundColor3 = Color3.fromRGB(12, 10, 22),
	BackgroundTransparency = 0.35,
}, topBar)
Util.corner(cashBox, 14)
local cashStroke = Util.stroke(cashBox, GOLD, 1.5, 0.55)
cashBox.ZIndex = 2
Util.label({
	Size = UDim2.new(1, -18, 0, 16),
	Position = UDim2.fromOffset(10, 6),
	Text = "CASH",
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(184, 172, 220),
	TextSize = 11,
}, cashBox).ZIndex = 3
local cashLabel = Util.label({
	Size = UDim2.new(1, -18, 0, 38),
	Position = UDim2.fromOffset(10, 19),
	Text = "$0",
	Font = Enum.Font.GothamBlack,
	TextColor3 = GOLD,
	TextSize = 32,
}, cashBox)
cashLabel.ZIndex = 3
local incomeLabel = Util.label({
	Size = UDim2.new(1, -18, 0, 15),
	Position = UDim2.fromOffset(10, 57),
	Text = "+$0/sec",
	Font = Enum.Font.GothamBold,
	TextColor3 = GREEN,
	TextSize = 12,
}, cashBox)
incomeLabel.ZIndex = 3

-- Stat chips.
local function chip(x: number, width: number, title: string, color: Color3): (Frame, TextLabel)
	local frame = Util.frame({
		Size = UDim2.fromOffset(width, 66),
		Position = UDim2.fromOffset(x, 13),
		BackgroundColor3 = Color3.fromRGB(12, 10, 22),
		BackgroundTransparency = 0.4,
	}, topBar)
	frame.ZIndex = 2
	Util.corner(frame, 13)
	Util.stroke(frame, color, 1.2, 0.62)
	Util.label({
		Size = UDim2.new(1, -12, 0, 15),
		Position = UDim2.fromOffset(8, 5),
		Text = title,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(174, 162, 210),
		TextSize = 10,
	}, frame).ZIndex = 3
	local value = Util.label({
		Size = UDim2.new(1, -12, 0, 32),
		Position = UDim2.fromOffset(8, 21),
		Text = "--",
		Font = Enum.Font.GothamBlack,
		TextColor3 = color,
		TextSize = 22,
	}, frame)
	value.ZIndex = 3
	return frame, value
end

local multChip, multLabel = chip(430, 100, "MULTIPLIER", PURPLE)
local carryChip, carryLabel = chip(540, 100, "CARRYING", CYAN)
local waveChip, waveLabel = chip(650, 96, "WAVE", PINK)

-- Three carry pips under the carry number.
local pips = {}
for i = 1, 3 do
	local pip = Util.frame({
		Size = UDim2.fromOffset(20, 7),
		Position = UDim2.fromOffset(10 + (i - 1) * 26, 52),
		BackgroundColor3 = Color3.fromRGB(58, 52, 84),
	}, carryChip)
	Util.corner(pip, 4)
	pip.ZIndex = 3
	pips[i] = pip
end

-- Rebirth button: a compact bottom-right card that never sits on the pad view.
local rebirthButton = Instance.new("TextButton")
rebirthButton.Name = "RebirthButton"
rebirthButton.Size = UDim2.fromOffset(250, 56)
rebirthButton.Position = UDim2.new(1, -22, 1, -84)
rebirthButton.AnchorPoint = Vector2.new(1, 1)
rebirthButton.BackgroundColor3 = Color3.fromRGB(60, 48, 26)
rebirthButton.BackgroundTransparency = 0.05
rebirthButton.Text = ""
rebirthButton.AutoButtonColor = true
rebirthButton.ZIndex = 5
rebirthButton.Parent = gui
Util.corner(rebirthButton, 14)
local rebirthStroke = Util.stroke(rebirthButton, GOLD, 2, 0.25)
local rebirthGradient = Instance.new("UIGradient")
rebirthGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 68, 24)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(54, 42, 26)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(92, 56, 22)),
})
rebirthGradient.Rotation = 12
rebirthGradient.Parent = rebirthButton

local rebirthTitle = Util.label({
	Size = UDim2.new(1, -78, 0, 26),
	Position = UDim2.fromOffset(12, 4),
	Text = "REBIRTH",
	Font = Enum.Font.GothamBlack,
	TextColor3 = GOLD,
	TextSize = 19,
	TextXAlignment = Enum.TextXAlignment.Left,
}, rebirthButton)
rebirthTitle.ZIndex = 6
local rebirthLevel = Util.label({
	Size = UDim2.fromOffset(60, 20),
	Position = UDim2.new(1, -70, 0, 7),
	Text = "LV 0",
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(255, 236, 180),
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Right,
}, rebirthButton)
rebirthLevel.ZIndex = 6
local rebirthSub = Util.label({
	Size = UDim2.new(1, -24, 0, 16),
	Position = UDim2.fromOffset(12, 32),
	Text = "NEED $500 MORE",
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(236, 224, 196),
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
}, rebirthButton)
rebirthSub.ZIndex = 6

-- Hint bar ------------------------------------------------------------------
local hintBar = Util.frame({
	Size = UDim2.fromOffset(620, 44),
	Position = UDim2.new(0.5, 0, 1, -18),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = Color3.fromRGB(16, 14, 28),
	BackgroundTransparency = 0.12,
}, gui)
Util.corner(hintBar, 22)
Util.stroke(hintBar, Color3.fromRGB(120, 108, 168), 1.2, 0.55)
local hintLabel = Util.label({
	Size = UDim2.new(1, -30, 1, 0),
	Position = UDim2.fromOffset(15, 0),
	Text = "Walk into a wild brainrot to grab it",
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(238, 233, 255),
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Center,
}, hintBar)
hintLabel.ZIndex = 3
local hintIndex = 1
local hints = {
	"Walk into a wild brainrot to grab it (max 3)",
	"Run home to YOUR glowing pad to bank it",
	"Guard your pad — rivals can steal while you are away",
	"Wave every 90s: bank your brainrots before it hits",
	"At $500 press R or REBIRTH for permanent +25%",
	"Touch an enemy's brainrot on their base to steal it",
}

-- Warning banner ------------------------------------------------------------
local warning = Util.frame({
	Size = UDim2.fromOffset(640, 72),
	Position = UDim2.new(0.5, 0, 0, 112),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.fromRGB(74, 12, 30),
	BackgroundTransparency = 0.06,
	Visible = false,
}, gui)
warning.Name = "WaveWarning"
Util.corner(warning, 18)
local warningStroke = Util.stroke(warning, RED, 3, 0.1)
local warningGradient = Instance.new("UIGradient")
warningGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 16, 36)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(130, 22, 48)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 12, 30)),
})
warningGradient.Parent = warning
Util.label({
	Size = UDim2.new(1, -24, 0, 34),
	Position = UDim2.fromOffset(12, 8),
	Text = "!  BRAINROT WAVE INCOMING  !",
	Font = Enum.Font.GothamBlack,
	TextColor3 = Color3.fromRGB(255, 245, 248),
	TextSize = 25,
	TextXAlignment = Enum.TextXAlignment.Center,
}, warning).ZIndex = 3
local warningSub = Util.label({
	Size = UDim2.new(1, -24, 0, 24),
	Position = UDim2.fromOffset(12, 44),
	Text = "RUN TO YOUR BASE — 5 SECONDS",
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(255, 190, 200),
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Center,
}, warning)
warningSub.ZIndex = 3

-- Toasts: bottom-left stack that grows upward, deliberately far away from the
-- centred wave banner (the old mid-left stack could clip it on short screens).
local toastHolder = Util.frame({
	Size = UDim2.fromOffset(336, 210),
	Position = UDim2.new(0, 20, 1, -76),
	AnchorPoint = Vector2.new(0, 1),
	BackgroundTransparency = 1,
}, gui)
toastHolder.Name = "Toasts"
local toastLayout = Instance.new("UIListLayout")
toastLayout.Padding = UDim.new(0, 7)
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
toastLayout.Parent = toastHolder
local toastCount = 0
local liveToasts: { Frame } = {}

local toneColors = {
	info = CYAN,
	good = GREEN,
	bad = RED,
	gold = GOLD,
	rebirth = GOLD,
	legendary = Color3.fromRGB(255, 146, 60),
}

local function pushToast(text: string, tone: string?, duration: number?)
	if not text or text == "" then
		return
	end
	local color = toneColors[tone or "info"] or CYAN
	toastCount += 1
	local frame = Util.frame({
		Size = UDim2.fromOffset(332, 52),
		BackgroundColor3 = Color3.fromRGB(14, 12, 26),
		BackgroundTransparency = 0.12,
		LayoutOrder = toastCount,
	}, toastHolder)
	Util.corner(frame, 10)
	local accent = Util.frame({
		Size = UDim2.fromOffset(5, 38),
		Position = UDim2.fromOffset(3, 7),
		BackgroundColor3 = color,
	}, frame)
	Util.corner(accent, 3)
	Util.stroke(frame, color, 1.2, 0.7)
	local label = Util.label({
		Size = UDim2.new(1, -22, 1, -6),
		Position = UDim2.fromOffset(14, 3),
		Text = text,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(248, 245, 255),
		TextSize = 13,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, frame)
	label.ZIndex = 3

	frame.BackgroundTransparency = 1
	label.TextTransparency = 1
	TweenService:Create(frame, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.12 }):Play()
	TweenService:Create(label, TweenInfo.new(0.22), { TextTransparency = 0 }):Play()

	table.insert(liveToasts, frame)
	while #liveToasts > 3 do
		local old = table.remove(liveToasts, 1)
		if old and old.Parent then
			old:Destroy()
		end
	end

	local life = duration or 4
	task.delay(life, function()
		if frame and frame.Parent then
			local tween = TweenService:Create(frame, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
			tween:Play()
			TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			task.delay(0.32, function()
				if frame and frame.Parent then
					frame:Destroy()
				end
			end)
		end
	end)
end

-- Live values ---------------------------------------------------------------
local cashValue = 0
local lastCash = 0
local lastRebirths = -1
local lastMultiplier = -1
local carrying = 0
local hintedCarry = -1
local warnedActive = false

local function setCashText(value: number)
	cashLabel.Text = "$" .. Util.formatCash(value)
end

local function updateCash()
	local cash = safeCashFolder()
	local value = 0
	if cash then
		local cashInt = cash:FindFirstChild("Cash")
		if cashInt and cashInt:IsA("IntValue") then
			value = cashInt.Value
		end
	end
	if value < 0 then
		value = 0
	end
	cashValue = value
	if value ~= lastCash then
		if value > lastCash and lastCash > 0 then
			local delta = value - lastCash
			local pulse = TweenService:Create(cashLabel, TweenInfo.new(0.12), { TextSize = 35 })
			pulse:Play()
			task.delay(0.13, function()
				TweenService:Create(cashLabel, TweenInfo.new(0.2), { TextSize = 32 }):Play()
			end)
			if delta >= 1 then
				-- Small floating delta next to the cash amount.
				local d = Util.label({
					Size = UDim2.fromOffset(90, 20),
					Position = UDim2.fromOffset(120, 26),
					Text = "+$" .. Util.formatCash(delta),
					Font = Enum.Font.GothamBold,
					TextColor3 = GREEN,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Right,
				}, cashBox)
				d.ZIndex = 4
				TweenService:Create(d, TweenInfo.new(0.9), { Position = UDim2.fromOffset(120, 6), TextTransparency = 1 }):Play()
				task.delay(1, function()
					if d and d.Parent then
						d:Destroy()
					end
				end)
			end
		end
		lastCash = value
		setCashText(value)
	end
end

local function updateStats()
	local folder = safeCashFolder()
	if not folder then
		return
	end
	local cashInt = folder:FindFirstChild("Cash")
	if cashInt and cashInt:IsA("IntValue") then
		cashValue = math.max(0, cashInt.Value)
		setCashText(cashValue)
	end
	local rebirthInt = folder:FindFirstChild("Rebirths")
	local multNum = folder:FindFirstChild("Multiplier")
	local rebirths = rebirthInt and rebirthInt:IsA("IntValue") and rebirthInt.Value or 0
	local multiplier = multNum and multNum:IsA("NumberValue") and multNum.Value or 1
	if rebirths ~= lastRebirths then
		lastRebirths = rebirths
	end
	if multiplier ~= lastMultiplier then
		lastMultiplier = multiplier
	end
	multLabel.Text = string.format("x%.2f", multiplier)
	rebirthLevel.Text = "LV " .. tostring(rebirths)

	local canRebirth = cashValue >= Config.REBIRTH_COST
	if canRebirth then
		rebirthStroke.Color = GOLD
		rebirthStroke.Transparency = 0.1
		rebirthTitle.TextColor3 = Color3.fromRGB(255, 238, 160)
		rebirthSub.Text = "READY! +25% CASH"
		rebirthSub.TextColor3 = Color3.fromRGB(255, 240, 175)
	else
		rebirthStroke.Color = Color3.fromRGB(160, 132, 82)
		rebirthStroke.Transparency = 0.5
		rebirthTitle.TextColor3 = Color3.fromRGB(205, 185, 140)
		rebirthSub.Text = string.format("NEED $%s MORE", Util.formatCash(Config.REBIRTH_COST - cashValue))
		rebirthSub.TextColor3 = Color3.fromRGB(236, 224, 196)
	end
end

local function updateCarry()
	local carry = tonumber(player:GetAttribute("Carried")) or 0
	carrying = carry
	carryLabel.Text = string.format("%d/%d", carry, Config.MAX_CARRIED)
	for i = 1, 3 do
		if pips[i] then
			pips[i].BackgroundColor3 = i <= carry and GOLD or Color3.fromRGB(58, 52, 84)
		end
	end
	if carry >= Config.MAX_CARRIED then
		carryLabel.TextColor3 = RED
	elseif carry > 0 then
		carryLabel.TextColor3 = GOLD
	else
		carryLabel.TextColor3 = CYAN
	end
	if carry > 0 and carry > hintedCarry then
		hintedCarry = carry
		hintLabel.Text = "Carrying " .. carry .. "! Run to your glowing pad and step on it"
	end
end

local function updateIncome()
	local income = tonumber(player:GetAttribute("IncomePerSec")) or 0
	incomeLabel.Text = "+$" .. Util.formatCash(income) .. "/sec"
end

local function updateWave()
	local left = tonumber(Workspace:GetAttribute("WaveTimeLeft")) or Config.WAVE_INTERVAL
	local warningOn = Workspace:GetAttribute("WaveWarning") == true
	local active = Workspace:GetAttribute("WaveActive") == true
	if active then
		waveLabel.Text = "NOW"
		waveLabel.TextColor3 = RED
		waveChip.BackgroundColor3 = Color3.fromRGB(70, 12, 28)
		warning.Visible = true
		warningSub.Text = "THE WAVE IS SWEEPING — GET ON YOUR PAD!"
	elseif warningOn or (left <= Config.WAVE_WARN and left > 0) then
		waveLabel.Text = string.format("%.1fs", math.max(0, left))
		waveLabel.TextColor3 = RED
		waveChip.BackgroundColor3 = Color3.fromRGB(64, 12, 26)
		warning.Visible = true
		warningSub.Text = string.format("RUN TO YOUR BASE — %.0f SECONDS", math.max(0, left))
	else
		local seconds = math.floor(left)
		waveLabel.Text = string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
		waveLabel.TextColor3 = left <= 20 and Color3.fromRGB(255, 170, 90) or PINK
		waveChip.BackgroundColor3 = Color3.fromRGB(12, 10, 22)
		warning.Visible = false
	end
	warnedActive = active
end

-- Rebirth -------------------------------------------------------------------
local rebirthLock = 0
local function requestRebirth()
	if os.clock() < rebirthLock then
		return
	end
	rebirthLock = os.clock() + 1.2
	if RebirthRemote then
		RebirthRemote:FireServer()
	end
	local tween = TweenService:Create(rebirthButton, TweenInfo.new(0.09), { Size = UDim2.fromOffset(238, 52) })
	tween:Play()
	task.delay(0.1, function()
		TweenService:Create(rebirthButton, TweenInfo.new(0.16), { Size = UDim2.fromOffset(250, 56) }):Play()
	end)
end

rebirthButton.Activated:Connect(requestRebirth)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		requestRebirth()
	end
end)

-- Toast subscription --------------------------------------------------------
if FXRemote then
	FXRemote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "toast" then
			pushToast(payload.text, payload.tone, payload.duration)
		end
	end)
end

if safeCashFolder() then
	local cash = safeCashFolder():FindFirstChild("Cash")
	if cash then
		cash:GetPropertyChangedSignal("Value"):Connect(updateCash)
	end
end
player.ChildAdded:Connect(function(child)
	if child.Name == "leaderstats" then
		local cash = child:FindFirstChild("Cash")
		if cash then
			cash:GetPropertyChangedSignal("Value"):Connect(updateCash)
		end
	end
end)

-- Hint rotation -------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(6.5)
		if carrying > 0 then
			hintLabel.Text = "Run to YOUR glowing pad and step on it to bank " .. carrying .. " brainrot" .. (carrying == 1 and "" or "s")
		else
			hintIndex += 1
			if hintIndex > #hints then
				hintIndex = 1
			end
			hintLabel.Text = hints[hintIndex]
		end
		hintLabel.TextTransparency = 1
		TweenService:Create(hintLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	end
end)

-- Main HUD loop -------------------------------------------------------------
task.spawn(function()
	while true do
		updateStats()
		updateCarry()
		updateIncome()
		updateWave()
		local pulse = 0.25 + 0.2 * math.sin(os.clock() * 6)
		if warning.Visible then
			warningStroke.Transparency = pulse
		end
		task.wait(0.1)
	end
end)

updateStats()
updateCarry()
updateIncome()
task.delay(1, function()
	pushToast("Welcome to Brainrot Cash Rush! Grab a creature in the wild.", "info", 6)
end)
