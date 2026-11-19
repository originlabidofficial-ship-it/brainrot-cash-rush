--!strict
-- HUD: owns one coherent ScreenGui layer: currency/status bar, wave warning,
-- quest tracker, Index panel, Shop panel, Leaderboard panel, onboarding
-- overlay and touch-sized buttons. It displays only server-pushed state and
-- attributes; the only messages it sends are Rebirth, ShopBuy, QuestClaim and
-- TutorialAction. No cash, price or quest progress is ever computed client-side.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
local stateRemote = RemotesFolder and RemotesFolder:FindFirstChild("State") :: RemoteEvent?
local fxRemote = RemotesFolder and RemotesFolder:FindFirstChild("FX") :: RemoteEvent?
local rebirthRemote = RemotesFolder and RemotesFolder:FindFirstChild("Rebirth") :: RemoteEvent?
local shopRemote = RemotesFolder and RemotesFolder:FindFirstChild("ShopBuy") :: RemoteEvent?
local claimRemote = RemotesFolder and RemotesFolder:FindFirstChild("QuestClaim") :: RemoteEvent?
local tutorialRemote = RemotesFolder and RemotesFolder:FindFirstChild("TutorialAction") :: RemoteEvent?
local boardRemote = RemotesFolder and RemotesFolder:FindFirstChild("Leaderboard") :: RemoteEvent?

local BG = Color3.fromRGB(16, 13, 28)
local PANEL = Color3.fromRGB(26, 21, 44)
local PANEL_2 = Color3.fromRGB(35, 29, 58)
local CYAN = Color3.fromRGB(90, 230, 255)
local PINK = Color3.fromRGB(255, 95, 205)
local GOLD = Color3.fromRGB(255, 210, 90)
local GREEN = Color3.fromRGB(110, 235, 150)
local RED = Color3.fromRGB(255, 95, 115)
local WHITE = Color3.fromRGB(245, 245, 255)
local DIM = Color3.fromRGB(165, 160, 190)

local state: any = nil
local latestBoard: any = nil
local carryCap = Config.MAX_CARRIED
local padSlots = Config.MAX_BASE
local lastCash = -1
local lastWaveWarning = false
local lastWaveActive = false
local flashTween: Tween? = nil

-- Screen --------------------------------------------------------------------
local old = playerGui:FindFirstChild("BrainrotHUD")
if old then
	old:Destroy()
end
local gui = Instance.new("ScreenGui")
gui.Name = "BrainrotHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Scale = 1
uiScale.Parent = gui

local root = Util.frame({
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 1,
}, gui)

local function updateScale()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local scale = math.clamp(viewport.Y / 720, 0.72, 1.05)
	uiScale.Scale = scale
end
updateScale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

local function corner(instance: Instance, radius: number)
	Util.corner(instance, radius)
end

local function panelFrame(width: number, height: number, z: number): Frame
	local frame = Util.frame({
		Size = UDim2.fromOffset(width, height),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = BG,
		BackgroundTransparency = 0,
		Visible = false,
		ZIndex = z,
	}, root)
	corner(frame, 20)
	Util.stroke(frame, Color3.fromRGB(92, 220, 255), 2, 0.35)
	return frame
end

local function makeButton(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(20, 16, 30)
	button.TextSize = 15
	button.TextWrapped = true
	button.ZIndex = 3
	button.Parent = parent
	corner(button, 10)
	Util.stroke(button, Color3.fromRGB(255, 255, 255), 1, 0.6)
	return button
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3, textSize: number, z: number?): TextLabel
	return Util.label({
		Size = size,
		Position = position,
		Text = text,
		TextColor3 = color,
		TextSize = textSize,
		Font = Enum.Font.GothamBold,
		ZIndex = z or 2,
	}, parent)
end

-- Top bar -------------------------------------------------------------------
-- Every key metric lives on a fully opaque dark panel: cash, income/s,
-- rebirths, carry, multiplier and the wave timer stay readable even when the
-- camera points at the bright sky or the marble plaza.
local cashBox = Util.frame({
	Size = UDim2.fromOffset(320, 96),
	Position = UDim2.fromOffset(16, 14),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0,
	ZIndex = 4,
}, root)
corner(cashBox, 16)
Util.stroke(cashBox, GOLD, 2, 0.15)
local cashTitle = label(cashBox, "CASH", UDim2.fromOffset(130, 20), UDim2.fromOffset(14, 7), GOLD, 18)
cashTitle.Font = Enum.Font.GothamBlack
local rebirthLabel = label(cashBox, "REBIRTHS 0", UDim2.fromOffset(150, 20), UDim2.new(1, -164, 0, 7), PINK, 18)
rebirthLabel.TextXAlignment = Enum.TextXAlignment.Right
local cashLabel = label(cashBox, "$0", UDim2.fromOffset(300, 42), UDim2.fromOffset(14, 25), WHITE, 36, 5)
cashLabel.Font = Enum.Font.GothamBlack
local incomeLabel = label(cashBox, "$0/sec  •  best $0", UDim2.fromOffset(300, 22), UDim2.fromOffset(14, 70), GREEN, 18)

local statusBox = Util.frame({
	Size = UDim2.fromOffset(540, 96),
	Position = UDim2.new(0.5, 0, 0, 14),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0,
	ZIndex = 4,
}, root)
corner(statusBox, 16)
Util.stroke(statusBox, CYAN, 2, 0.2)
local statusLabels: { [string]: TextLabel } = {}
local statusChips = {
	{ key = "wave", title = "WAVE" },
	{ key = "carry", title = "CARRY" },
	{ key = "pad", title = "PAD" },
	{ key = "mult", title = "MULTIPLIER" },
}
for index, chip in ipairs(statusChips) do
	local x = 8 + (index - 1) * 131
	local card = Util.frame({
		Size = UDim2.fromOffset(125, 78),
		Position = UDim2.fromOffset(x, 9),
		BackgroundColor3 = PANEL_2,
		BackgroundTransparency = 0,
		ZIndex = 5,
	}, statusBox)
	corner(card, 10)
	label(card, chip.title, UDim2.new(1, -8, 0, 22), UDim2.fromOffset(4, 4), DIM, 18)
	local value = label(card, "—", UDim2.new(1, -8, 0, 42), UDim2.fromOffset(4, 28), WHITE, 24, 6)
	value.Font = Enum.Font.GothamBlack
	statusLabels[chip.key] = value
end

local actionBox = Util.frame({
	Size = UDim2.fromOffset(320, 96),
	Position = UDim2.new(1, -16, 0, 14),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0,
	ZIndex = 4,
}, root)
corner(actionBox, 16)
Util.stroke(actionBox, PINK, 2, 0.2)
local actionButtons: { [string]: TextButton } = {}
local actions = {
	{ key = "index", text = "INDEX\nE", color = CYAN },
	{ key = "shop", text = "SHOP\nB", color = GOLD },
	{ key = "board", text = "BOARD\nL", color = PINK },
	{ key = "rebirth", text = "REBIRTH\nR", color = GREEN },
}
for index, action in ipairs(actions) do
	local button = makeButton(actionBox, action.text, UDim2.fromOffset(74, 64), UDim2.fromOffset(4 + (index - 1) * 78, 16), action.color)
	button.TextSize = 14
	actionButtons[action.key] = button
end

-- Quest tracker -------------------------------------------------------------
local questPanel = Util.frame({
	Size = UDim2.fromOffset(340, 258),
	Position = UDim2.new(0, 16, 1, -16),
	AnchorPoint = Vector2.new(0, 1),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0,
	ZIndex = 4,
}, root)
corner(questPanel, 16)
Util.stroke(questPanel, GOLD, 2, 0.25)
label(questPanel, "QUESTS", UDim2.fromOffset(170, 24), UDim2.fromOffset(14, 10), GOLD, 16).Font = Enum.Font.GothamBlack
label(questPanel, "3 ROTATING • CLAIM CASH", UDim2.new(1, -150, 0, 16), UDim2.fromOffset(186, 15), DIM, 10)

type QuestRow = { name: TextLabel, progress: TextLabel, fill: Frame, button: TextButton, questId: string?, complete: boolean }
local questRows: { QuestRow } = {}
for index = 1, 3 do
	local row = Util.frame({
		Size = UDim2.new(1, -20, 0, 64),
		Position = UDim2.fromOffset(10, 40 + (index - 1) * 70),
		BackgroundColor3 = PANEL_2,
		BackgroundTransparency = 0,
		ZIndex = 5,
	}, questPanel)
	corner(row, 10)
	local nameLabel = label(row, "Loading quest…", UDim2.new(1, -110, 0, 18), UDim2.fromOffset(10, 5), WHITE, 12)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local progressLabel = label(row, "0/0", UDim2.fromOffset(84, 18), UDim2.new(1, -94, 0, 5), DIM, 11)
	progressLabel.TextXAlignment = Enum.TextXAlignment.Right
	local track = Util.frame({
		Size = UDim2.fromOffset(202, 7),
		Position = UDim2.fromOffset(10, 30),
		BackgroundColor3 = Color3.fromRGB(58, 52, 82),
		ZIndex = 6,
	}, row)
	corner(track, 4)
	local fill = Util.frame({
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = GREEN,
		ZIndex = 7,
	}, track)
	corner(fill, 4)
	local button = makeButton(row, "CLAIM", UDim2.fromOffset(88, 38), UDim2.new(1, -98, 0, 13), Color3.fromRGB(80, 74, 108))
	button.TextSize = 12
	button.Active = false
	table.insert(questRows, {
		name = nameLabel,
		progress = progressLabel,
		fill = fill,
		button = button,
		questId = nil,
		complete = false,
	})
	button.Activated:Connect(function()
		if claimRemote and questRows[index].questId and questRows[index].complete then
			claimRemote:FireServer(questRows[index].questId)
			button.Active = false
			button.Text = "CLAIMED"
		end
	end)
end

-- Controls / first-minute hint ----------------------------------------------
local hintPanel = Util.frame({
	Size = UDim2.fromOffset(320, 120),
	Position = UDim2.new(1, -16, 1, -16),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0,
	ZIndex = 4,
}, root)
corner(hintPanel, 14)
Util.stroke(hintPanel, CYAN, 1.5, 0.45)
label(hintPanel, "FIRST MINUTE", UDim2.fromOffset(180, 18), UDim2.fromOffset(12, 8), CYAN, 12).Font = Enum.Font.GothamBlack
local hintLabel = Util.label({
	Size = UDim2.new(1, -24, 0, 54),
	Position = UDim2.fromOffset(12, 28),
	Text = "Grab a wild brainrot → run to your pad → bank it → open the Index (E) → buy an upgrade (B) → rebirth at $500 (R).",
	TextColor3 = Color3.fromRGB(220, 218, 238),
	TextSize = 11,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 5,
}, hintPanel)
hintLabel.Font = Enum.Font.GothamBold
label(hintPanel, "WASD move  •  SPACE jump  •  E index  •  B shop  •  L board  •  R rebirth", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(12, 88), DIM, 10)

-- Toasts --------------------------------------------------------------------
local toastBox = Util.frame({
	Size = UDim2.fromOffset(500, 220),
	Position = UDim2.new(0.5, 0, 0, 174),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	ZIndex = 12,
}, root)
local toastLayout = Instance.new("UIListLayout")
toastLayout.Padding = UDim.new(0, 6)
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Parent = toastBox
local liveToasts: { Frame } = {}
local toastOrder = 0

local function pushToast(text: string, tone: string?, duration: number?)
	if type(text) ~= "string" or text == "" then
		return
	end
	local color = CYAN
	if tone == "bad" then
		color = RED
	elseif tone == "good" then
		color = GREEN
	elseif tone == "rebirth" or tone == "legendary" then
		color = GOLD
	end
	toastOrder += 1
	local frame = Util.frame({
		Size = UDim2.fromOffset(480, 44),
		BackgroundColor3 = BG,
		BackgroundTransparency = 0,
		LayoutOrder = toastOrder,
		ZIndex = 13,
	}, toastBox)
	corner(frame, 10)
	Util.stroke(frame, color, 2, 0.15)
	local textLabel = Util.label({
		Size = UDim2.new(1, -20, 1, -6),
		Position = UDim2.fromOffset(10, 3),
		Text = text,
		TextColor3 = WHITE,
		TextSize = 12,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 14,
	}, frame)
	textLabel.Font = Enum.Font.GothamBold
	table.insert(liveToasts, frame)
	while #liveToasts > 4 do
		local oldest = table.remove(liveToasts, 1)
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end
	local life = duration or 4
	task.delay(life, function()
		if frame and frame.Parent then
			TweenService:Create(frame, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(textLabel, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
			task.wait(0.28)
			if frame and frame.Parent then
				frame:Destroy()
			end
		end
	end)
end

-- Index panel ---------------------------------------------------------------
local indexPanel = panelFrame(960, 600, 20)
label(indexPanel, "BRAINROT INDEX", UDim2.fromOffset(300, 32), UDim2.fromOffset(26, 16), CYAN, 24).Font = Enum.Font.GothamBlack
local indexProgress = label(indexPanel, "0 / 0 (0%)", UDim2.fromOffset(330, 26), UDim2.fromOffset(330, 20), WHITE, 18)
local indexSub = label(indexPanel, "Discover all 22 creatures. Counts persist with DataStore.", UDim2.new(1, -300, 0, 18), UDim2.fromOffset(26, 50), DIM, 11)
local indexBarTrack = Util.frame({
	Size = UDim2.fromOffset(300, 8),
	Position = UDim2.fromOffset(650, 24),
	BackgroundColor3 = Color3.fromRGB(58, 52, 82),
	ZIndex = 22,
}, indexPanel)
corner(indexBarTrack, 4)
local indexBarFill = Util.frame({
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = CYAN,
	ZIndex = 23,
}, indexBarTrack)
corner(indexBarFill, 4)
local indexClose = makeButton(indexPanel, "✕", UDim2.fromOffset(48, 44), UDim2.new(1, -64, 0, 14), PINK)
indexClose.TextSize = 20

type IndexCell = { frame: Frame, title: TextLabel, rarity: TextLabel, count: TextLabel, quip: TextLabel, dot: Frame }
local indexCells: { [string]: IndexCell } = {}
for index, kind in ipairs(Config.BRAINROTS) do
	local col = (index - 1) % 5
	local row = math.floor((index - 1) / 5)
	local cell = Util.frame({
		Size = UDim2.fromOffset(174, 88),
		Position = UDim2.fromOffset(20 + col * 182, 82 + row * 96),
		BackgroundColor3 = Color3.fromRGB(20, 17, 34),
		ZIndex = 21,
	}, indexPanel)
	corner(cell, 10)
	Util.stroke(cell, Color3.fromRGB(70, 65, 95), 1, 0.4)
	local dot = Util.frame({
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromOffset(10, 10),
		BackgroundColor3 = Color3.fromRGB(50, 46, 70),
		ZIndex = 22,
	}, cell)
	corner(dot, 7)
	local title = label(cell, "???", UDim2.new(1, -34, 0, 18), UDim2.fromOffset(30, 8), Color3.fromRGB(90, 86, 112), 12)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	local rarityLabel = label(cell, "UNDISCOVERED", UDim2.new(1, -20, 0, 14), UDim2.fromOffset(10, 28), Color3.fromRGB(80, 76, 104), 9)
	local countLabel = label(cell, "", UDim2.new(1, -20, 0, 14), UDim2.fromOffset(10, 44), DIM, 9)
	local quip = label(cell, "Capture it to reveal the quip.", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 58), Color3.fromRGB(85, 80, 108), 9)
	quip.TextWrapped = true
	indexCells[kind.id] = { frame = cell, title = title, rarity = rarityLabel, count = countLabel, quip = quip, dot = dot }
end
indexClose.Activated:Connect(function()
	indexPanel.Visible = false
end)

-- Shop panel ----------------------------------------------------------------
local shopPanel = panelFrame(960, 600, 20)
label(shopPanel, "UPGRADE SHOP", UDim2.fromOffset(300, 32), UDim2.fromOffset(26, 16), GOLD, 24).Font = Enum.Font.GothamBlack
label(shopPanel, "Six tracks • five levels each • bought server-side, permanent across rebirths.", UDim2.new(1, -200, 0, 18), UDim2.fromOffset(26, 50), DIM, 11)
local shopClose = makeButton(shopPanel, "✕", UDim2.fromOffset(48, 44), UDim2.new(1, -64, 0, 14), PINK)
shopClose.TextSize = 20
shopClose.Activated:Connect(function()
	shopPanel.Visible = false
end)

type ShopCard = { level: TextLabel, effect: TextLabel, price: TextLabel, button: TextButton, key: string }
local shopCards: { [string]: ShopCard } = {}
for index, track in ipairs(Config.UPGRADES) do
	local col = (index - 1) % 2
	local row = math.floor((index - 1) / 2)
	local card = Util.frame({
		Size = UDim2.fromOffset(456, 128),
		Position = UDim2.fromOffset(18 + col * 468, 84 + row * 138),
		BackgroundColor3 = PANEL,
		ZIndex = 21,
	}, shopPanel)
	corner(card, 12)
	Util.stroke(card, Color3.fromRGB(92, 80, 130), 1.5, 0.25)
	local icon = label(card, track.icon, UDim2.fromOffset(48, 48), UDim2.fromOffset(14, 14), GOLD, 30, 22)
	icon.TextXAlignment = Enum.TextXAlignment.Center
	local name = label(card, track.name, UDim2.fromOffset(280, 24), UDim2.fromOffset(70, 10), WHITE, 17, 22)
	name.Font = Enum.Font.GothamBlack
	local blurb = label(card, track.blurb, UDim2.fromOffset(370, 18), UDim2.fromOffset(70, 34), DIM, 10, 22)
	blurb.TextTruncate = Enum.TextTruncate.AtEnd
	local level = label(card, "LV 0/5", UDim2.fromOffset(74, 20), UDim2.new(1, -88, 0, 12), CYAN, 12, 22)
	level.TextXAlignment = Enum.TextXAlignment.Right
	local effect = label(card, "NOW —", UDim2.fromOffset(300, 18), UDim2.fromOffset(14, 66), GREEN, 11, 22)
	local price = label(card, "NEXT $0", UDim2.fromOffset(300, 22), UDim2.fromOffset(14, 88), GOLD, 14, 22)
	local button = makeButton(card, "BUY", UDim2.fromOffset(112, 46), UDim2.new(1, -126, 0, 66), GOLD)
	button.TextSize = 13
	button.Activated:Connect(function()
		if shopRemote then
			shopRemote:FireServer(track.key)
		end
	end)
	shopCards[track.key] = { level = level, effect = effect, price = price, button = button, key = track.key }
end

-- Leaderboard panel ---------------------------------------------------------
local boardPanel = panelFrame(760, 600, 20)
label(boardPanel, "TOP 10 • TOTAL EARNED", UDim2.fromOffset(500, 30), UDim2.fromOffset(26, 16), PINK, 22).Font = Enum.Font.GothamBlack
label(boardPanel, "Server session + persisted all-time bests. Refreshes every 6 seconds.", UDim2.new(1, -100, 0, 18), UDim2.fromOffset(26, 50), DIM, 11)
local boardClose = makeButton(boardPanel, "✕", UDim2.fromOffset(48, 44), UDim2.new(1, -64, 0, 14), PINK)
boardClose.TextSize = 20
boardClose.Activated:Connect(function()
	boardPanel.Visible = false
end)
local boardHeader = label(boardPanel, "#    PLAYER                 CASH          REBIRTHS", UDim2.new(1, -40, 0, 18), UDim2.fromOffset(22, 80), CYAN, 11)
boardHeader.Font = Enum.Font.Code
type BoardRow = { rank: TextLabel, name: TextLabel, cash: TextLabel, rebirths: TextLabel }
local boardRows: { BoardRow } = {}
for index = 1, 10 do
	local row = Util.frame({
		Size = UDim2.new(1, -40, 0, 40),
		Position = UDim2.fromOffset(20, 104 + (index - 1) * 43),
		BackgroundColor3 = index % 2 == 0 and PANEL_2 or PANEL,
		BackgroundTransparency = 0.1,
		ZIndex = 21,
	}, boardPanel)
	corner(row, 8)
	local rank = label(row, tostring(index), UDim2.fromOffset(44, 22), UDim2.fromOffset(10, 9), index <= 3 and GOLD or DIM, 14, 22)
	local name = label(row, "---", UDim2.fromOffset(280, 22), UDim2.fromOffset(62, 9), WHITE, 13, 22)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local cash = label(row, "$0", UDim2.fromOffset(150, 22), UDim2.new(1, -210, 0, 9), GREEN, 13, 22)
	cash.TextXAlignment = Enum.TextXAlignment.Right
	local rebirths = label(row, "R0", UDim2.fromOffset(70, 22), UDim2.new(1, -80, 0, 9), GOLD, 12, 22)
	rebirths.TextXAlignment = Enum.TextXAlignment.Right
	table.insert(boardRows, { rank = rank, name = name, cash = cash, rebirths = rebirths })
end
local boardFooter = label(boardPanel, "Your rank: —", UDim2.new(1, -40, 0, 30), UDim2.new(0, 26, 1, -44), WHITE, 14)
boardFooter.Font = Enum.Font.GothamBlack

-- Onboarding overlay --------------------------------------------------------
local tutorialLayer = Util.frame({
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(6, 4, 14),
	BackgroundTransparency = 0.42,
	Visible = false,
	ZIndex = 30,
}, root)
local tutorialCard = Util.frame({
	Size = UDim2.fromOffset(640, 430),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = BG,
	ZIndex = 31,
}, tutorialLayer)
corner(tutorialCard, 20)
Util.stroke(tutorialCard, CYAN, 3, 0.1)
label(tutorialCard, "WELCOME TO BRAINROT CASH RUSH", UDim2.new(1, -40, 0, 32), UDim2.fromOffset(20, 18), CYAN, 21).Font = Enum.Font.GothamBlack
label(tutorialCard, "Five quick objectives. They tick off live — skip whenever you like.", UDim2.new(1, -40, 0, 18), UDim2.fromOffset(20, 54), DIM, 12)
type TutorialRow = { label: TextLabel, tick: TextLabel }
local tutorialRows: { [string]: TutorialRow } = {}
local tutorialKeys = { "move", "grab", "bank", "index", "rebirth" }
for index, key in ipairs(tutorialKeys) do
	local row = Util.frame({
		Size = UDim2.new(1, -40, 0, 46),
		Position = UDim2.fromOffset(20, 88 + (index - 1) * 52),
		BackgroundColor3 = PANEL,
		ZIndex = 32,
	}, tutorialCard)
	corner(row, 10)
	local tick = label(row, "○", UDim2.fromOffset(34, 30), UDim2.fromOffset(12, 8), DIM, 22, 33)
	tick.TextXAlignment = Enum.TextXAlignment.Center
	local textLabel = label(row, "Objective", UDim2.new(1, -70, 1, 0), UDim2.fromOffset(56, 0), WHITE, 13, 33)
	tutorialRows[key] = { label = textLabel, tick = tick }
end
local skipButton = makeButton(tutorialCard, "SKIP TUTORIAL", UDim2.fromOffset(190, 48), UDim2.fromOffset(20, 364), PINK)
skipButton.TextSize = 14
skipButton.Activated:Connect(function()
	tutorialLayer.Visible = false
	if tutorialRemote then
		tutorialRemote:FireServer("skip")
	end
	pushToast("Tutorial skipped — press E for the Index, B for the Shop.", "info", 4)
end)
label(tutorialCard, "Objectives tick live from the server. Press E, B, L or R any time.", UDim2.new(1, -255, 0, 36), UDim2.fromOffset(225, 370), DIM, 10).TextWrapped = true

-- Panel switching -----------------------------------------------------------
local panels = { index = indexPanel, shop = shopPanel, board = boardPanel }
local function closeAllPanels()
	for _, panel in pairs(panels) do
		panel.Visible = false
	end
end
local function togglePanel(key: string)
	local panel = panels[key]
	if not panel then
		return
	end
	local wasOpen = panel.Visible
	closeAllPanels()
	panel.Visible = not wasOpen
	if key == "index" and not wasOpen then
		if tutorialRemote then
			tutorialRemote:FireServer("index")
		end
	end
end
actionButtons.index.Activated:Connect(function()
	togglePanel("index")
end)
actionButtons.shop.Activated:Connect(function()
	togglePanel("shop")
end)
actionButtons.board.Activated:Connect(function()
	togglePanel("board")
end)
actionButtons.rebirth.Activated:Connect(function()
	if rebirthRemote then
		rebirthRemote:FireServer()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.E then
		togglePanel("index")
	elseif input.KeyCode == Enum.KeyCode.B then
		togglePanel("shop")
	elseif input.KeyCode == Enum.KeyCode.L then
		togglePanel("board")
	elseif input.KeyCode == Enum.KeyCode.R then
		if rebirthRemote then
			rebirthRemote:FireServer()
		end
	elseif input.KeyCode == Enum.KeyCode.Escape then
		closeAllPanels()
		indexPanel.Visible = false
		shopPanel.Visible = false
		boardPanel.Visible = false
	end
end)

-- State application ---------------------------------------------------------
local function updateIndex(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local discovered = tonumber(payload.discovered) or 0
	local total = tonumber(payload.total) or #Config.BRAINROTS
	local percent = total > 0 and discovered / total or 0
	indexProgress.Text = string.format("%d / %d (%d%%)", discovered, total, math.floor(percent * 100 + 0.5))
	indexBarFill.Size = UDim2.fromScale(math.clamp(percent, 0, 1), 1)
	indexSub.Text = string.format("%d creatures still hiding in the wild. Counts persist with DataStore.", total - discovered)
	for _, entry in ipairs(payload.entries or {}) do
		local cell = indexCells[entry.id]
		local rarity = Config.RARITIES[entry.rarity]
		if cell and rarity then
			if entry.discovered then
				cell.frame.BackgroundColor3 = Color3.fromRGB(28, 24, 46)
				cell.dot.BackgroundColor3 = rarity.color
				cell.title.Text = entry.name
				cell.title.TextColor3 = rarity.color
				cell.rarity.Text = string.upper(entry.rarity) .. " • $" .. tostring(entry.income) .. "/SEC"
				cell.rarity.TextColor3 = rarity.color
				cell.count.Text = "CAPTURED ×" .. tostring(entry.count)
				cell.count.TextColor3 = GOLD
				cell.quip.Text = entry.quip
				cell.quip.TextColor3 = Color3.fromRGB(195, 192, 216)
			else
				cell.frame.BackgroundColor3 = Color3.fromRGB(19, 16, 30)
				cell.dot.BackgroundColor3 = Color3.fromRGB(48, 44, 62)
				cell.title.Text = "???"
				cell.title.TextColor3 = Color3.fromRGB(80, 76, 104)
				cell.rarity.Text = "UNDISCOVERED"
				cell.rarity.TextColor3 = Color3.fromRGB(78, 74, 98)
				cell.count.Text = ""
				cell.quip.Text = "Find it in the wild to reveal its quip."
				cell.quip.TextColor3 = Color3.fromRGB(70, 66, 88)
			end
		end
	end
end

local function updateShop(upgrades: any)
	if type(upgrades) ~= "table" then
		return
	end
	for _, info in ipairs(upgrades) do
		local card = shopCards[info.key]
		if card then
			local maxed = info.level >= info.maxLevel
			card.level.Text = string.format("LV %d/%d", info.level, info.maxLevel)
			card.effect.Text = "NOW: " .. tostring(info.effect)
			if maxed then
				card.price.Text = "MAX LEVEL"
				card.price.TextColor3 = GREEN
				card.button.Text = "MAX"
				card.button.Active = false
				card.button.BackgroundColor3 = Color3.fromRGB(70, 84, 92)
			else
				card.price.Text = "NEXT: $" .. Util.commaNumber(info.price or 0)
				card.price.TextColor3 = GOLD
				card.button.Text = "BUY"
				card.button.Active = true
				card.button.BackgroundColor3 = GOLD
			end
		end
	end
end

local function updateQuests(quests: any)
	if type(quests) ~= "table" then
		return
	end
	for index = 1, 3 do
		local row = questRows[index]
		local quest = quests[index]
		if quest then
			row.name.Text = quest.name
			row.progress.Text = string.format("%d/%d", quest.progress or 0, quest.goal or 0)
			local percent = (quest.goal or 0) > 0 and (quest.progress or 0) / quest.goal or 0
			row.fill.Size = UDim2.fromScale(math.clamp(percent, 0, 1), 1)
			row.fill.BackgroundColor3 = quest.complete and GREEN or CYAN
			row.questId = quest.id
			row.complete = quest.complete == true
			if row.complete then
				row.button.Text = "CLAIM $" .. Util.formatCash(quest.reward or 0)
				row.button.BackgroundColor3 = GREEN
				row.button.Active = true
				row.button.TextColor3 = Color3.fromRGB(20, 50, 30)
			else
				row.button.Text = "LOCKED"
				row.button.BackgroundColor3 = Color3.fromRGB(68, 62, 92)
				row.button.Active = false
				row.button.TextColor3 = Color3.fromRGB(190, 186, 212)
			end
		else
			row.name.Text = "Rotating…"
			row.progress.Text = "0/0"
			row.fill.Size = UDim2.fromScale(0, 1)
			row.button.Text = "LOCKED"
			row.button.Active = false
			row.questId = nil
			row.complete = false
		end
	end
end

local function updateTutorial(tutorial: any)
	if type(tutorial) ~= "table" then
		return
	end
	if tutorial.done then
		tutorialLayer.Visible = false
		return
	end
	tutorialLayer.Visible = true
	local allDone = true
	for _, objective in ipairs(tutorial.objectives or {}) do
		local row = tutorialRows[objective.key]
		if row then
			row.label.Text = objective.label
			if objective.done then
				row.tick.Text = "✓"
				row.tick.TextColor3 = GREEN
				row.label.TextColor3 = GREEN
			else
				row.tick.Text = "○"
				row.tick.TextColor3 = DIM
				row.label.TextColor3 = WHITE
				allDone = false
			end
		end
	end
	if allDone then
		tutorialLayer.Visible = false
	end
end

local function applyState(payload: any)
	if type(payload) ~= "table" or payload.kind ~= "state" then
		return
	end
	state = payload
	carryCap = tonumber(payload.carryCap) or carryCap
	padSlots = tonumber(payload.padSlots) or padSlots
	updateIndex(payload.index)
	updateShop(payload.upgrades)
	updateQuests(payload.quests)
	updateTutorial(payload.tutorial)
	incomeLabel.Text = string.format("$%s/sec  •  best $%s", Util.formatCash(payload.income or 0), Util.formatCash(payload.bestTotal or 0))
end

if stateRemote then
	stateRemote.OnClientEvent:Connect(applyState)
end
if boardRemote then
	boardRemote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.entries) ~= "table" then
			return
		end
		latestBoard = payload
		for index = 1, 10 do
			local row = boardRows[index]
			local entry = payload.entries[index]
			if row then
				if entry then
					row.rank.Text = tostring(entry.rank or index)
					row.rank.TextColor3 = index <= 3 and GOLD or DIM
					row.name.Text = tostring(entry.name or "—")
					row.cash.Text = "$" .. Util.formatCash(entry.cash or 0)
					row.rebirths.Text = "R" .. tostring(entry.rebirths or 0)
					row.name.TextColor3 = WHITE
					row.cash.TextColor3 = GREEN
				else
					row.rank.Text = tostring(index)
					row.rank.TextColor3 = DIM
					row.name.Text = "—"
					row.cash.Text = "$0"
					row.rebirths.Text = "R0"
					row.name.TextColor3 = Color3.fromRGB(100, 96, 120)
					row.cash.TextColor3 = Color3.fromRGB(100, 96, 120)
				end
			end
		end
		local rankText = "Your rank: unranked"
		if tonumber(payload.viewerRank) then
			rankText = string.format("Your rank: #%d  •  $%s total earned  •  %d players ranked", payload.viewerRank, Util.formatCash(payload.viewerCash or 0), payload.totalPlayers or 0)
		end
		boardFooter.Text = rankText
	end)
end
if fxRemote then
	fxRemote.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.kind == "toast" then
			pushToast(payload.text, payload.tone, payload.duration)
		end
	end)
end

-- Live attribute polling ----------------------------------------------------
local function readCash(): number
	local cash = tonumber(player:GetAttribute("Cash"))
	if cash then
		return math.max(0, cash)
	end
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Cash")
	if value and value:IsA("IntValue") then
		return math.max(0, value.Value)
	end
	return 0
end

local function updateLive()
	local cash = readCash()
	if cash ~= lastCash then
		lastCash = cash
		cashLabel.Text = "$" .. Util.formatCash(cash)
	end
	local income = tonumber(player:GetAttribute("IncomePerSec")) or 0
	local best = state and tonumber(state.bestTotal) or 0
	if latestBoard and tonumber(latestBoard.viewerCash) then
		best = math.max(best or 0, tonumber(latestBoard.viewerCash) or 0)
	end
	incomeLabel.Text = string.format("$%s/sec  •  best $%s", Util.formatCash(income), Util.formatCash(best or 0))
	local carried = tonumber(player:GetAttribute("Carried")) or 0
	local placed = tonumber(player:GetAttribute("Placed")) or 0
	local multiplier = tonumber(player:GetAttribute("Multiplier")) or 1
	local rebirths = tonumber(player:GetAttribute("Rebirths")) or 0
	rebirthLabel.Text = "REBIRTHS " .. tostring(rebirths)
	statusLabels.carry.Text = string.format("%d/%d", carried, carryCap)
	statusLabels.pad.Text = string.format("%d/%d", placed, padSlots)
	statusLabels.mult.Text = string.format("x%.2f", multiplier)
	local left = tonumber(Workspace:GetAttribute("WaveTimeLeft")) or Config.WAVE_INTERVAL
	local warning = Workspace:GetAttribute("WaveWarning") == true
	local active = Workspace:GetAttribute("WaveActive") == true
	if active then
		statusLabels.wave.Text = "NOW"
		statusLabels.wave.TextColor3 = RED
	elseif warning then
		statusLabels.wave.Text = string.format("%ds", math.max(0, math.ceil(left)))
		statusLabels.wave.TextColor3 = RED
	else
		statusLabels.wave.Text = string.format("%ds", math.max(0, math.ceil(left)))
		statusLabels.wave.TextColor3 = WHITE
	end
	if warning ~= lastWaveWarning or active ~= lastWaveActive then
		lastWaveWarning = warning
		lastWaveActive = active
		if warning or active then
			statusChips[1].title = "BRAINROT WAVE"
			if flashTween then
				flashTween:Cancel()
			end
			flashTween = TweenService:Create(statusBox, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true, 0), { BackgroundColor3 = Color3.fromRGB(90, 22, 34) })
			flashTween:Play()
		else
			statusBox.BackgroundColor3 = BG
		end
	end
end

task.spawn(function()
	while true do
		pcall(updateLive)
		task.wait(0.15)
	end
end)

-- On join, ask the server for a fresh snapshot even if the delayed push raced
-- the HUD's remote binding.
task.delay(2, function()
	pcall(function()
		if tutorialRemote then
			tutorialRemote:FireServer("hello")
		end
	end)
end)

pushToast("Welcome! Grab wild brainrots, bank them on your pad, and press E to open the Index.", "info", 7)
