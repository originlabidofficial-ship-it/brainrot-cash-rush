--!strict
-- HUD.client.luau — the whole player-facing interface.
--
-- Design rules:
--   * the map is bright, so every panel is a dark card with near-white text;
--   * all numbers come from the server's State payload (never recomputed from
--     guesses), except the wave countdown which is replicated as Workspace
--     attributes by WaveService;
--   * the client only ever asks: Rebirth, ShopBuy(key), QuestClaim(id),
--     TutorialAction(action). The server validates each request again.
--
-- The script installs itself once: if a HUD already exists (Studio hot reload,
-- a duplicate LocalScript) the old one is removed before building, so there is
-- never a double set of panels or double remote listeners.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
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
local Util = require(Shared:WaitForChild("Util", 10))

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes", 20)
if not RemotesFolder then
	return
end
local Remotes = {
	State = RemotesFolder:WaitForChild("State", 10),
	Leaderboard = RemotesFolder:WaitForChild("Leaderboard", 10),
	FX = RemotesFolder:WaitForChild("FX", 10),
	Rebirth = RemotesFolder:WaitForChild("Rebirth", 10),
	ShopBuy = RemotesFolder:WaitForChild("ShopBuy", 10),
	QuestClaim = RemotesFolder:WaitForChild("QuestClaim", 10),
	TutorialAction = RemotesFolder:WaitForChild("TutorialAction", 10),
}

-- Single instance ---------------------------------------------------------
local existing = playerGui:FindFirstChild("BrainrotHUD")
if existing then
	existing:Destroy()
end

local UI = Config.UI
local screen = Instance.new("ScreenGui")
screen.Name = "BrainrotHUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 20
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

-- Small widget toolkit ----------------------------------------------------

local function surface(parent: Instance, props: { [string]: any }): Frame
	return Util.frame(props, parent)
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	return Util.label(props, parent)
end

local function button(parent: Instance, caption: string, size: UDim2, position: UDim2, fill: Color3): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = size
	btn.Position = position
	btn.BackgroundColor3 = fill
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Text = caption
	btn.Font = Enum.Font.GothamBlack
	btn.TextColor3 = UI.white
	btn.TextScaled = true
	btn.TextSize = 16
	btn.ZIndex = 5
	btn.Parent = parent
	Util.corner(btn, 10)
	Util.stroke(btn, UI.white, 1.2, 0.75)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = btn
	return btn
end

local function chip(parent: Instance, caption: string, color: Color3, width: number): TextLabel
	local holder = surface({
		Size = UDim2.fromOffset(width, 26),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.78,
	}, parent)
	Util.corner(holder, 13)
	Util.stroke(holder, color, 1.5, 0.35)
	local label = text({
		Size = UDim2.fromScale(1, 1),
		Text = caption,
		Font = Enum.Font.GothamBold,
		TextColor3 = color:Lerp(UI.white, 0.35),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, holder)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = holder
	return label
end

local function titleBar(parent: Instance, caption: string, accent: Color3, subtitle: string?)
	text({
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(12, 8),
		Text = caption,
		Font = Enum.Font.GothamBlack,
		TextColor3 = accent,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	if subtitle then
		text({
			Size = UDim2.new(1, -20, 0, 18),
			Position = UDim2.fromOffset(12, 36),
			Text = subtitle,
			Font = Enum.Font.Gotham,
			TextColor3 = UI.textDim,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, parent)
	end
	local line = surface({
		Size = UDim2.new(1, -24, 0, 2),
		Position = UDim2.new(0, 12, 0, subtitle and 56 or 40),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.3,
	}, parent)
	line.Name = "Divider"
end

-- Root layout --------------------------------------------------------------

-- Top-left: wallet card.
local wallet = surface({
	Size = UDim2.fromOffset(300, 118),
	Position = UDim2.fromOffset(16, 16),
	BackgroundColor3 = UI.panel,
	BackgroundTransparency = 0.08,
}, screen)
Util.corner(wallet, 14)
Util.stroke(wallet, UI.gold, 2, 0.25)

local gameTitle = text({
	Size = UDim2.new(1, -20, 0, 18),
	Position = UDim2.fromOffset(10, 7),
	Text = Config.GAME_NAME,
	Font = Enum.Font.GothamBlack,
	TextColor3 = UI.gold,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
}, wallet)

local cashLabel = text({
	Size = UDim2.new(1, -20, 0, 38),
	Position = UDim2.fromOffset(10, 24),
	Text = "$0",
	Font = Enum.Font.GothamBlack,
	TextColor3 = UI.white,
	TextSize = 34,
	TextXAlignment = Enum.TextXAlignment.Left,
}, wallet)

local incomeLabel = text({
	Size = UDim2.new(0.55, 0, 0, 18),
	Position = UDim2.fromOffset(10, 64),
	Text = "$0/sec",
	Font = Enum.Font.GothamBold,
	TextColor3 = UI.green,
	TextSize = 16,
	TextXAlignment = Enum.TextXAlignment.Left,
}, wallet)

local multiplierLabel = text({
	Size = UDim2.new(0.4, 0, 0, 18),
	Position = UDim2.new(0.58, 0, 0, 64),
	Text = "x1.00",
	Font = Enum.Font.GothamBold,
	TextColor3 = UI.cyan,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Right,
}, wallet)

local carryLabel = text({
	Size = UDim2.new(0.48, 0, 0, 18),
	Position = UDim2.fromOffset(10, 88),
	Text = "Carrying 0/3",
	Font = Enum.Font.Gotham,
	TextColor3 = UI.textDim,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
}, wallet)

local slotLabel = text({
	Size = UDim2.new(0.48, 0, 0, 18),
	Position = UDim2.new(0.5, 0, 0, 88),
	Text = "Base 0/8",
	Font = Enum.Font.Gotham,
	TextColor3 = UI.textDim,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
}, wallet)

-- Top-right: wave clock plus menu buttons.
local waveCard = surface({
	Size = UDim2.fromOffset(210, 52),
	Position = UDim2.new(1, -226, 0, 16),
	BackgroundColor3 = UI.panel,
	BackgroundTransparency = 0.08,
}, screen)
Util.corner(waveCard, 12)
Util.stroke(waveCard, UI.pink, 1.6, 0.35)

local waveLabel = text({
	Size = UDim2.fromScale(1, 1),
	Text = "WAVE IN 90s",
	Font = Enum.Font.GothamBlack,
	TextColor3 = UI.pink,
	TextSize = 20,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Center,
}, waveCard)

local menuBar = surface({
	Size = UDim2.fromOffset(330, 40),
	Position = UDim2.new(1, -346, 0, 76),
	BackgroundTransparency = 1,
}, screen)
local menuLayout = Instance.new("UIListLayout")
menuLayout.FillDirection = Enum.FillDirection.Horizontal
menuLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
menuLayout.Padding = UDim.new(0, 6)
menuLayout.Parent = menuBar

local function menuButton(caption: string, accent: Color3, order: number): TextButton
	local btn = button(menuBar, caption, UDim2.fromOffset(78, 34), UDim2.fromOffset(0, 0), accent)
	btn.LayoutOrder = order
	btn.TextSize = 15
	btn.BackgroundTransparency = 0.05
	return btn
end

local indexButton = menuButton("INDEX (E)", UI.cyan, 1)
local shopButton = menuButton("SHOP (B)", UI.gold, 2)
local questButton = menuButton("QUESTS (Q)", UI.green, 3)
local boardButton = menuButton("TOP (L)", UI.pink, 4)

-- Toast feed, bottom-left, newest at the bottom.
local feed = surface({
	Size = UDim2.fromOffset(400, 210),
	Position = UDim2.new(0, 16, 1, -226),
	BackgroundTransparency = 1,
}, screen)
local feedLayout = Instance.new("UIListLayout")
feedLayout.FillDirection = Enum.FillDirection.Vertical
feedLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.Padding = UDim.new(0, 5)
feedLayout.Parent = feed

local toastSerial = 0

local function toast(message: string, tone: string?, duration: number?)
	if type(message) ~= "string" or message == "" then
		return
	end
	local seconds = tonumber(duration) or Config.TOAST.normal
	local accent = Util.toneColor(tone, UI)
	local card = surface({
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = UI.panel,
		BackgroundTransparency = 0.12,
	}, feed)
	Util.corner(card, 9)
	Util.stroke(card, accent, 1.6, 0.2)
	card.LayoutOrder = 1000 - toastSerial
	toastSerial += 1

	local stripe = surface({
		Size = UDim2.fromOffset(5, 26),
		Position = UDim2.fromOffset(3, 4),
		BackgroundColor3 = accent,
	}, card)
	stripe.Name = "Accent"

	text({
		Size = UDim2.new(1, -18, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		Text = message,
		Font = Enum.Font.GothamBold,
		TextColor3 = UI.text,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)

	-- Keep the feed to a reasonable length during busy waves.
	local live = {}
	for _, child in ipairs(feed:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(live, child)
		end
	end
	while #live > 6 do
		local oldest = table.remove(live, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	TweenService:Create(card, TweenInfo.new(seconds * 0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(seconds, function()
		if card and card.Parent then
			card:Destroy()
		end
	end)
end

-- Tutorial card, bottom-right.
local tutorialCard = surface({
	Size = UDim2.fromOffset(290, 210),
	Position = UDim2.new(1, -306, 1, -226),
	BackgroundColor3 = UI.panel,
	BackgroundTransparency = 0.08,
}, screen)
Util.corner(tutorialCard, 14)
Util.stroke(tutorialCard, UI.green, 1.8, 0.3)
titleBar(tutorialCard, "FIRST STEPS", UI.green, "Learn the loop in five moves")

local objectiveRows: { any } = {}
for i = 1, #Config.TUTORIAL do
	local row = surface({
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 64 + (i - 1) * 24),
		BackgroundTransparency = 1,
	}, tutorialCard)
	local bullet = text({
		Size = UDim2.fromOffset(18, 22),
		Text = "○",
		Font = Enum.Font.GothamBlack,
		TextColor3 = UI.textDim,
		TextSize = 16,
	}, row)
	local caption = text({
		Size = UDim2.new(1, -22, 1, 0),
		Position = UDim2.fromOffset(20, 0),
		Text = Config.TUTORIAL[i].label,
		Font = Enum.Font.Gotham,
		TextColor3 = UI.textDim,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	objectiveRows[i] = { bullet = bullet, caption = caption }
end

local skipTutorial = button(tutorialCard, "SKIP TUTORIAL", UDim2.new(1, -24, 0, 26), UDim2.new(0, 12, 1, -34), UI.panelLight)
skipTutorial.TextColor3 = UI.textDim

-- Panel shell --------------------------------------------------------------

local activePanel = ""

local panels: { [string]: Frame } = {}

local function makePanel(key: string, caption: string, subtitle: string, accent: Color3): Frame
	local frame = surface({
		Size = UDim2.fromOffset(720, 470),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = UI.panel,
		BackgroundTransparency = 0.03,
		Visible = false,
	}, screen)
	Util.corner(frame, 18)
	Util.stroke(frame, accent, 2.4, 0.15)
	titleBar(frame, caption, accent, subtitle)

	local close = button(frame, "✕", UDim2.fromOffset(34, 30), UDim2.new(1, -44, 0, 8), UI.panelLight)
	close.TextColor3 = UI.text
	close.MouseButton1Click:Connect(function()
		frame.Visible = false
		activePanel = ""
	end)

	panels[key] = frame
	return frame
end

local function showPanel(key: string)
	for name, frame in pairs(panels) do
		frame.Visible = name == key
	end
	activePanel = key
end

local function togglePanel(key: string)
	if activePanel == key then
		panels[key].Visible = false
		activePanel = ""
	else
		showPanel(key)
	end
end

-- Outbound requests -------------------------------------------------------
-- Every client->server request passes through this gate, so holding a key or
-- spamming a button cannot flood the server; the server rate-limits again.

local sendTimes: { [string]: number } = {}

local function sendRateLimited(key: string, cooldown: number, action: () -> ())
	local now = os.clock()
	if now - (sendTimes[key] or 0) < cooldown then
		return
	end
	sendTimes[key] = now
	task.spawn(action)
end

-- Index panel --------------------------------------------------------------

local indexPanel = makePanel("index", "BRAINROT INDEX", "Every species you have ever grabbed", UI.cyan)
local indexProgress = text({
	Size = UDim2.new(1, -24, 0, 20),
	Position = UDim2.fromOffset(12, 62),
	Text = "0 / 30 discovered",
	Font = Enum.Font.GothamBold,
	TextColor3 = UI.cyan,
	TextSize = 15,
}, indexPanel)

local indexMutations = text({
	Size = UDim2.new(1, -24, 0, 38),
	Position = UDim2.fromOffset(12, 83),
	Text = "MUTATIONS: 8% capture roll",
	Font = Enum.Font.Gotham,
	TextColor3 = UI.gold,
	TextSize = 11,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
}, indexPanel)

local indexScroll = Instance.new("ScrollingFrame")
indexScroll.Size = UDim2.new(1, -24, 1, -140)
indexScroll.Position = UDim2.fromOffset(12, 126)
indexScroll.BackgroundTransparency = 1
indexScroll.BorderSizePixel = 0
indexScroll.ScrollBarThickness = 6
indexScroll.ScrollBarImageColor3 = UI.cyan
indexScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
indexScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
indexScroll.Parent = indexPanel

local indexGrid = Instance.new("UIGridLayout")
indexGrid.CellSize = UDim2.fromOffset(220, 64)
indexGrid.CellPadding = UDim2.fromOffset(8, 8)
indexGrid.SortOrder = Enum.SortOrder.LayoutOrder
indexGrid.Parent = indexScroll

local indexCards: { any } = {}

local function ensureIndexCards(entries: { any })
	if #indexCards == #entries then
		return
	end
	for _, card in ipairs(indexCards) do
		card.root:Destroy()
	end
	indexCards = {}
	for _, entry in ipairs(entries) do
		local card = surface({
			Size = UDim2.fromOffset(220, 64),
			BackgroundColor3 = UI.panelLight,
			BackgroundTransparency = 0.1,
		}, indexScroll)
		Util.corner(card, 10)
		local stroke = Util.stroke(card, UI.textDim, 1.4, 0.4)
		local name = text({
			Size = UDim2.new(1, -12, 0, 20),
			Position = UDim2.fromOffset(7, 5),
			Text = entry.name,
			Font = Enum.Font.GothamBold,
			TextColor3 = UI.text,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		local meta = text({
			Size = UDim2.new(1, -12, 0, 15),
			Position = UDim2.fromOffset(7, 25),
			Text = string.upper(entry.rarity) .. " • $" .. tostring(entry.income) .. "/s",
			Font = Enum.Font.Gotham,
			TextColor3 = UI.textDim,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		local quip = text({
			Size = UDim2.new(1, -12, 0, 14),
			Position = UDim2.fromOffset(7, 42),
			Text = entry.quip,
			Font = Enum.Font.Gotham,
			TextColor3 = UI.textDim,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, card)
		table.insert(indexCards, { root = card, stroke = stroke, name = name, meta = meta, quip = quip, id = entry.id })
	end
end

local function refreshIndex(entries: { any }, discovered: number, total: number, index: any)
	ensureIndexCards(entries)
	for position, entry in ipairs(entries) do
		local card = indexCards[position]
		if card then
			local rarity = Config.RARITIES[entry.rarity]
			local color = rarity and rarity.color or UI.text
			card.name.Text = entry.discovered and entry.name or "???"
			card.name.TextColor3 = entry.discovered and color or UI.textDim
			card.meta.Text = entry.discovered
					and string.format("%s • $%d/s • x%d", string.upper(entry.rarity), entry.income, entry.count)
				or "UNDISCOVERED"
			card.stroke.Color = entry.discovered and color or UI.textDim
			card.root.BackgroundTransparency = entry.discovered and 0.08 or 0.35
		end
	end
	indexProgress.Text = string.format("%d / %d discovered  •  %d%%", discovered, total, math.floor((total > 0 and discovered / total or 0) * 100))

	if index and type(index.mutations) == "table" then
		local totalWeight = 0
		for _, mutation in ipairs(index.mutations) do
			totalWeight += tonumber(mutation.weight) or 0
		end
		local parts = {}
		for _, mutation in ipairs(index.mutations) do
			local share = totalWeight > 0 and (tonumber(mutation.weight) or 0) / totalWeight or 0
			local overall = (tonumber(index.mutationChance) or 0) * share * 100
			table.insert(parts, string.format("%s x%.2f (%.1f%%)", mutation.key, mutation.multiplier, overall))
		end
		indexMutations.Text = string.format("%.0f%% capture roll  •  %s", (tonumber(index.mutationChance) or 0) * 100, table.concat(parts, "   •   "))
	end
end

-- Shop panel ---------------------------------------------------------------

local shopPanel = makePanel("shop", "UPGRADE SHOP", "Six permanent tracks, five levels each", UI.gold)
local shopRows: { any } = {}

local function buildShopRows(upgrades: { any })
	for _, row in ipairs(shopRows) do
		row.root:Destroy()
	end
	shopRows = {}
	for index, upgrade in ipairs(upgrades) do
		local row = surface({
			Size = UDim2.new(1, -24, 0, 62),
			Position = UDim2.fromOffset(12, 66 + (index - 1) * 68),
			BackgroundColor3 = UI.panelLight,
			BackgroundTransparency = 0.08,
		}, shopPanel)
		Util.corner(row, 10)
		Util.stroke(row, UI.gold, 1.2, 0.55)

		text({
			Size = UDim2.fromOffset(32, 32),
			Position = UDim2.fromOffset(8, 6),
			Text = upgrade.icon,
			Font = Enum.Font.GothamBold,
			TextColor3 = UI.white,
			TextSize = 20,
		}, row)
		text({
			Size = UDim2.new(0.4, -40, 0, 20),
			Position = UDim2.fromOffset(44, 5),
			Text = string.format("%s  Lv %d/%d", upgrade.name, upgrade.level, upgrade.maxLevel),
			Font = Enum.Font.GothamBold,
			TextColor3 = UI.text,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		local blurb = text({
			Size = UDim2.new(0.62, -52, 0, 16),
			Position = UDim2.fromOffset(44, 26),
			Text = upgrade.blurb,
			Font = Enum.Font.Gotham,
			TextColor3 = UI.textDim,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)
		local effect = text({
			Size = UDim2.new(0.62, -52, 0, 16),
			Position = UDim2.fromOffset(44, 42),
			Text = "NOW: " .. string.upper(upgrade.effect),
			Font = Enum.Font.GothamBold,
			TextColor3 = UI.cyan,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)

		local buy = button(row, upgrade.price and ("BUY  $" .. Util.commaNumber(upgrade.price)) or "MAXED", UDim2.fromOffset(150, 38), UDim2.new(1, -162, 0.5, -19), UI.gold)
		buy.TextColor3 = Color3.fromRGB(40, 30, 10)
		if not upgrade.price then
			buy.BackgroundColor3 = UI.panelLight
			buy.TextColor3 = UI.textDim
			buy.AutoButtonColor = false
		end
		local key = upgrade.key
		buy.MouseButton1Click:Connect(function()
			sendRateLimited("shop", Config.LIMITS.shopBuy, function()
				Remotes.ShopBuy:FireServer(key)
			end)
		end)
		table.insert(shopRows, { root = row, buy = buy, blurb = blurb, effect = effect })
	end
end

-- Quest panel --------------------------------------------------------------

local questPanel = makePanel("quests", "QUEST LOG", "Three jobs at a time, paid in cash", UI.green)
local questCards: { any } = {}

local function buildQuestCards(quests: { any })
	for _, card in ipairs(questCards) do
		card.root:Destroy()
	end
	questCards = {}
	for index, quest in ipairs(quests) do
		local card = surface({
			Size = UDim2.new(1, -24, 0, 84),
			Position = UDim2.fromOffset(12, 66 + (index - 1) * 92),
			BackgroundColor3 = UI.panelLight,
			BackgroundTransparency = 0.08,
		}, questPanel)
		Util.corner(card, 10)
		Util.stroke(card, quest.complete and UI.green or UI.textDim, 1.4, 0.4)

		local name = text({
			Size = UDim2.new(0.6, 0, 0, 22),
			Position = UDim2.fromOffset(10, 6),
			Text = quest.name,
			Font = Enum.Font.GothamBold,
			TextColor3 = quest.complete and UI.green or UI.text,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)
		local reward = text({
			Size = UDim2.new(0.36, 0, 0, 22),
			Position = UDim2.new(0.62, 0, 0, 6),
			Text = "REWARD  $" .. Util.commaNumber(quest.reward),
			Font = Enum.Font.GothamBold,
			TextColor3 = UI.gold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, card)

		local track = surface({
			Size = UDim2.new(0.62, 0, 0, 12),
			Position = UDim2.fromOffset(10, 36),
			BackgroundColor3 = Color3.fromRGB(50, 46, 68),
		}, card)
		Util.corner(track, 6)
		local fill = surface({
			Size = UDim2.fromScale(math.clamp(quest.goal > 0 and quest.progress / quest.goal or 0, 0, 1), 1),
			BackgroundColor3 = quest.complete and UI.green or UI.cyan,
		}, track)
		Util.corner(fill, 6)

		local progress = text({
			Size = UDim2.new(0.62, 0, 0, 18),
			Position = UDim2.fromOffset(10, 52),
			Text = string.format("%d / %d", quest.progress, quest.goal),
			Font = Enum.Font.Gotham,
			TextColor3 = UI.textDim,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, card)

		local claim = button(card, quest.complete and "CLAIM" or "IN PROGRESS", UDim2.fromOffset(150, 36), UDim2.new(1, -162, 0.5, -18), UI.green)
		claim.TextColor3 = Color3.fromRGB(10, 40, 22)
		if not quest.complete then
			claim.BackgroundColor3 = UI.panelLight
			claim.TextColor3 = UI.textDim
		end
		local questId = quest.id
		claim.MouseButton1Click:Connect(function()
			sendRateLimited("quest", Config.LIMITS.questClaim, function()
				Remotes.QuestClaim:FireServer(questId)
			end)
		end)
		table.insert(questCards, { root = card, name = name, reward = reward, claim = claim, progress = progress, fill = fill })
	end
end

-- Leaderboard panel --------------------------------------------------------

local boardPanel = makePanel("board", "TOP 10 EARNERS", "This server plus persisted all-time bests", UI.pink)
local boardRows: { any } = {}
local boardFooter = text({
	Size = UDim2.new(1, -24, 0, 20),
	Position = UDim2.new(0, 12, 1, -30),
	Text = "Waiting for the board…",
	Font = Enum.Font.Gotham,
	TextColor3 = UI.textDim,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Center,
}, boardPanel)

for i = 1, Config.LEADERBOARD_ROWS do
	local row = surface({
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.fromOffset(12, 66 + (i - 1) * 34),
		BackgroundColor3 = i % 2 == 0 and UI.panelLight or Color3.fromRGB(24, 21, 38),
		BackgroundTransparency = 0.1,
	}, boardPanel)
	Util.corner(row, 7)
	local rank = text({
		Size = UDim2.fromOffset(38, 30),
		Position = UDim2.fromOffset(6, 0),
		Text = "#" .. tostring(i),
		Font = Enum.Font.GothamBlack,
		TextColor3 = i <= 3 and UI.gold or UI.textDim,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, row)
	local name = text({
		Size = UDim2.new(0.42, 0, 1, 0),
		Position = UDim2.fromOffset(48, 0),
		Text = "---",
		Font = Enum.Font.GothamBold,
		TextColor3 = UI.text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local cash = text({
		Size = UDim2.new(0.36, 0, 1, 0),
		Position = UDim2.new(0.48, 0, 0, 0),
		Text = "",
		Font = Enum.Font.Code,
		TextColor3 = UI.green,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, row)
	local rebounds = text({
		Size = UDim2.fromOffset(60, 30),
		Position = UDim2.new(1, -66, 0, 0),
		Text = "",
		Font = Enum.Font.Gotham,
		TextColor3 = UI.cyan,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, row)
	boardRows[i] = { rank = rank, name = name, cash = cash, rebirths = rebounds }
end

-- Network ------------------------------------------------------------------

-- Network helpers are declared before the panels because the buy/claim buttons
-- capture them when they are built.
local lastState: any = nil

local function applyState(payload: any)
	if type(payload) ~= "table" or payload.kind ~= "state" then
		return
	end
	lastState = payload

	cashLabel.Text = "$" .. Util.commaNumber(payload.cash or 0)
	incomeLabel.Text = "+$" .. Util.formatCash(payload.income or 0) .. "/sec"
	multiplierLabel.Text = string.format("x%.2f  •  R%s", payload.multiplier or 1, tostring(payload.rebirths or 0))
	carryLabel.Text = string.format("Carrying %d/%d", payload.carried or 0, payload.carryCap or Config.MAX_CARRIED)
	slotLabel.Text = string.format("Base %d/%d", payload.placed or 0, payload.padSlots or Config.MAX_BASE)

	if payload.index then
		refreshIndex(payload.index.entries or {}, payload.index.discovered or 0, payload.index.total or 0, payload.index)
	end
	if payload.upgrades then
		buildShopRows(payload.upgrades)
	end
	if payload.quests then
		buildQuestCards(payload.quests)
	end
	if payload.tutorial then
		local done = payload.tutorial.done == true
		tutorialCard.Visible = not done
		for index, objective in ipairs(payload.tutorial.objectives or {}) do
			local row = objectiveRows[index]
			if row then
				row.bullet.Text = objective.done and "●" or "○"
				row.bullet.TextColor3 = objective.done and UI.green or UI.textDim
				row.caption.TextColor3 = objective.done and UI.text or UI.textDim
				row.caption.Text = objective.done and (objective.label .. "  ✓") or objective.label
			end
		end
	end
end

local function applyLeaderboard(payload: any)
	if type(payload) ~= "table" or payload.kind ~= "leaderboard" then
		return
	end
	local entries = payload.entries or {}
	for i, row in ipairs(boardRows) do
		local entry = entries[i]
		if entry then
			row.rank.Text = "#" .. tostring(entry.rank or i)
			row.name.Text = string.sub(tostring(entry.name or "?"), 1, 18)
			row.cash.Text = "$" .. Util.formatCash(entry.cash or 0)
			row.rebirths.Text = "R" .. tostring(entry.rebirths or 0)
		else
			row.rank.Text = "#" .. tostring(i)
			row.name.Text = "---"
			row.cash.Text = ""
			row.rebirths.Text = ""
		end
	end
	if payload.viewerRank then
		boardFooter.Text = string.format("You are #%d of %d • $%s earned", payload.viewerRank, payload.totalPlayers or 0, Util.formatCash(payload.viewerCash or 0))
	else
		boardFooter.Text = string.format("%d players ranked • $%s earned", payload.totalPlayers or 0, Util.formatCash(payload.viewerCash or 0))
	end
end

local function onFx(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind == "toast" then
		toast(payload.text, payload.tone, payload.duration)
	elseif payload.kind == "waveWarning" then
		toast("WAVE INCOMING — GET TO YOUR BASE!", "bad", 4)
	elseif payload.kind == "waveStart" then
		toast("THE BRAINROT WAVE IS HERE!", "bad", 4)
	elseif payload.kind == "rebirth" then
		toast(string.format("REBIRTH x%s!", tostring(payload.level or 1)), "rebirth", 5)
	end
end

Remotes.State.OnClientEvent:Connect(applyState)
Remotes.Leaderboard.OnClientEvent:Connect(applyLeaderboard)
Remotes.FX.OnClientEvent:Connect(onFx)

-- Wave attributes ----------------------------------------------------------

local function refreshWave()
	local active = Workspace:GetAttribute("WaveActive") == true
	local warning = Workspace:GetAttribute("WaveWarning") == true
	local left = tonumber(Workspace:GetAttribute("WaveTimeLeft")) or 0
	local number = tonumber(Workspace:GetAttribute("WaveNumber")) or 0
	if active then
		waveLabel.Text = "WAVE " .. tostring(number) .. " • RUN!"
		waveLabel.TextColor3 = UI.red
		waveCard.BackgroundColor3 = Color3.fromRGB(70, 20, 34)
	elseif warning then
		waveLabel.Text = string.format("WAVE IN %.0fs", math.max(0, left))
		waveLabel.TextColor3 = UI.red
		waveCard.BackgroundColor3 = Color3.fromRGB(58, 22, 34)
	else
		waveLabel.Text = string.format("WAVE IN %.0fs", math.max(0, left))
		waveLabel.TextColor3 = UI.pink
		waveCard.BackgroundColor3 = UI.panel
	end
end

for _, attribute in ipairs({ "WaveTimeLeft", "WaveWarning", "WaveActive", "WaveNumber" }) do
	Workspace:GetAttributeChangedSignal(attribute):Connect(refreshWave)
end
refreshWave()

-- Buttons and keys ---------------------------------------------------------

indexButton.MouseButton1Click:Connect(function()
	togglePanel("index")
end)
shopButton.MouseButton1Click:Connect(function()
	togglePanel("shop")
end)
questButton.MouseButton1Click:Connect(function()
	togglePanel("quests")
end)
boardButton.MouseButton1Click:Connect(function()
	togglePanel("board")
end)

skipTutorial.MouseButton1Click:Connect(function()
	sendRateLimited("tutorial", Config.LIMITS.tutorial, function()
		Remotes.TutorialAction:FireServer("skip")
	end)
	tutorialCard.Visible = false
end)

local function closeEverything()
	for _, frame in pairs(panels) do
		frame.Visible = false
	end
	activePanel = ""
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local code = input.KeyCode
	if code == Enum.KeyCode.E then
		togglePanel("index")
		sendRateLimited("tutorialIndex", 1, function()
			Remotes.TutorialAction:FireServer("index")
		end)
	elseif code == Enum.KeyCode.B then
		togglePanel("shop")
	elseif code == Enum.KeyCode.Q then
		togglePanel("quests")
	elseif code == Enum.KeyCode.L then
		togglePanel("board")
	elseif code == Enum.KeyCode.R then
		sendRateLimited("rebirth", Config.LIMITS.rebirth, function()
			Remotes.Rebirth:FireServer()
		end)
	elseif code == Enum.KeyCode.Escape then
		closeEverything()
	end
end)

-- Live fallback: if the State remote is slow, the leaderstats replicas still
-- let the wallet card tick. The server remains the source of truth.
local function readCashFromLeaderstats(): number?
	local stats = player:FindFirstChild("leaderstats")
	local cash = stats and stats:FindFirstChild("Cash")
	if cash and cash:IsA("IntValue") then
		return cash.Value
	end
	return nil
end

task.spawn(function()
	while screen.Parent do
		if not lastState then
			local cash = readCashFromLeaderstats()
			if cash then
				cashLabel.Text = "$" .. Util.commaNumber(cash)
			end
		end
		task.wait(0.5)
	end
end)

-- Ask for a fresh snapshot once the HUD is ready. The server answers with the
-- same State payload every service pushes, so this is cheap and idempotent.
task.delay(0.5, function()
	if screen.Parent then
		pcall(function()
			Remotes.TutorialAction:FireServer("hello")
		end)
	end
end)

toast("Grab wild brainrots, bank them on your pad, press B to upgrade.", "info", 6)
