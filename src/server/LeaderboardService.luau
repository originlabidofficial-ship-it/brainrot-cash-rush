--!strict
-- LeaderboardService — the cash race, on screen and in the HUD.
--
-- Two data sources are merged: this session's earnings (live, per player) and
-- the persisted all-time bests held by DataService. Current players always win
-- on name and rebirth count; their cash is the larger of the two. The same
-- table feeds a physical TOP 10 board near spawn and a State-independent
-- snapshot pushed to every HUD.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LeaderboardService = {}

local Config: any = nil
local Util: any = nil
local deps: any = nil

local state = {
	running = false,
	sessionTotals = {} :: { [Player]: number },
	rowLabels = {} :: { TextLabel },
	statusLabel = nil :: TextLabel?,
	lastRefresh = 0,
}

local PODIUM_COLORS = {
	Color3.fromRGB(255, 212, 80),
	Color3.fromRGB(226, 232, 246),
	Color3.fromRGB(255, 166, 112),
}

local function alive(player: Player?): boolean
	return player ~= nil and player.Parent ~= nil
end

local function seasonLine(): string
	local season = Config.seasonInfo()
	return string.format("%s  •  %s UTC  •  %s", season.label, season.date, season.resetNote)
end

local function rowText(rank: number, entry: any): (string, Color3)
	local name = string.sub(tostring(entry.name or "?"), 1, 14)
	local cash = Util.formatCash(entry.cash or 0)
	local rebirths = tostring(entry.rebirths or 0)
	return string.format("%2d  %-14s  $%-8s  R%s", rank, name, cash, rebirths),
		PODIUM_COLORS[rank] or Color3.fromRGB(228, 230, 246)
end

-- Data ---------------------------------------------------------------------

function LeaderboardService.recordEarn(player: Player, amount: number)
	if not alive(player) then
		return
	end
	local gain = math.max(0, tonumber(amount) or 0)
	if gain <= 0 then
		return
	end
	state.sessionTotals[player] = (state.sessionTotals[player] or 0) + gain
	pcall(function()
		deps.DataService.updateBest(player, state.sessionTotals[player], deps.PlayerService.getRebirths(player))
	end)
end

function LeaderboardService.getTotalEarned(player: Player): number
	return state.sessionTotals[player] or 0
end

local function gather(): { any }
	local merged: { [number]: any } = {}

	for userId, stored in pairs(deps.DataService.getAllTime()) do
		merged[userId] = {
			userId = userId,
			name = stored.name or ("PLAYER " .. tostring(userId)),
			cash = tonumber(stored.cash) or 0,
			rebirths = tonumber(stored.rebirths) or 0,
		}
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if alive(player) then
			local best = deps.DataService.getBestTotal(player)
			local session = state.sessionTotals[player] or 0
			merged[player.UserId] = {
				userId = player.UserId,
				name = player.DisplayName,
				cash = math.max(best, session),
				rebirths = deps.PlayerService.getRebirths(player),
			}
		end
	end

	local list = {}
	for _, entry in pairs(merged) do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		if a.cash == b.cash then
			return tostring(a.name) < tostring(b.name)
		end
		return a.cash > b.cash
	end)
	return list
end

-- Physical board -----------------------------------------------------------

local function buildBoard()
	local world = Workspace:FindFirstChild("World")
	if not world then
		return
	end
	local old = world:FindFirstChild("LeaderboardBoard")
	if old then
		old:Destroy()
	end

	local anchor = deps.Config.MAP.boardPos
	local facing = (Config.MAP.spawnPos - anchor).Unit
	local cframe = CFrame.lookAt(anchor + Vector3.new(0, 13, 0), anchor + Vector3.new(0, 13, 0) + facing)

	local frame = Instance.new("Folder")
	frame.Name = "LeaderboardBoard"
	frame.Parent = world

	for _, offset in ipairs({ -10.5, 10.5 }) do
		Util.part({
			Name = "BoardPost",
			Size = Vector3.new(1.4, 9, 1.4),
			CFrame = cframe * CFrame.new(offset, -8.5, 0),
			Color = Color3.fromRGB(46, 42, 68),
			Material = Enum.Material.Metal,
			CanCollide = true,
		}, frame)
	end

	local screen = Util.part({
		Name = "LeaderboardScreen",
		Size = Vector3.new(24, 16, 0.7),
		CFrame = cframe,
		Color = Color3.fromRGB(13, 11, 24),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	}, frame)

	local edges = {
		{ Vector3.new(0, 8.25, 0), Vector3.new(25.2, 0.5, 1.1), Color3.fromRGB(90, 230, 255) },
		{ Vector3.new(0, -8.25, 0), Vector3.new(25.2, 0.5, 1.1), Color3.fromRGB(255, 95, 205) },
		{ Vector3.new(-12.25, 0, 0), Vector3.new(0.5, 16.8, 1.1), Color3.fromRGB(255, 95, 205) },
		{ Vector3.new(12.25, 0, 0), Vector3.new(0.5, 16.8, 1.1), Color3.fromRGB(90, 230, 255) },
	}
	for _, edge in ipairs(edges) do
		Util.part({
			Name = "BoardNeon",
			Size = edge[2],
			CFrame = cframe * CFrame.new(edge[1]),
			Color = edge[3],
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		}, frame)
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 44
	gui.LightInfluence = 0
	gui.MaxDistance = 700
	gui.Parent = screen

	local card = Util.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 10, 22),
		BackgroundTransparency = 0.05,
	}, gui)
	Util.corner(card, 18)
	Util.stroke(card, Color3.fromRGB(255, 208, 76), 3, 0.1)

	Util.label({
		Size = UDim2.new(1, -24, 0.12, 0),
		Position = UDim2.fromOffset(12, 6),
		Text = "TOP 10  •  CASH EARNED",
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 220, 90),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, card)

	state.statusLabel = Util.label({
		Size = UDim2.new(1, -24, 0.055, 0),
		Position = UDim2.new(0, 12, 0.115, 0),
		Text = seasonLine(),
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(90, 230, 255),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, card)

	state.rowLabels = {}
	for index = 1, Config.LEADERBOARD_ROWS do
		local row = Util.frame({
			Size = UDim2.new(1, -24, 0.068, 0),
			Position = UDim2.new(0, 12, 0.185 + (index - 1) * 0.077, 0),
			BackgroundColor3 = index % 2 == 0 and Color3.fromRGB(29, 25, 46) or Color3.fromRGB(20, 17, 34),
			BackgroundTransparency = 0.1,
		}, card)
		Util.corner(row, 7)
		state.rowLabels[index] = Util.label({
			Size = UDim2.new(1, -14, 1, 0),
			Position = UDim2.fromOffset(7, 0),
			Text = string.format("%2d  ---", index),
			Font = Enum.Font.Code,
			TextColor3 = Color3.fromRGB(212, 216, 236),
			TextScaled = true,
		}, row)
	end
end

local function paintBoard(list: { any })
	for index = 1, Config.LEADERBOARD_ROWS do
		local label = state.rowLabels[index]
		if label then
			local entry = list[index]
			if entry then
				local caption, color = rowText(index, entry)
				label.Text = caption
				label.TextColor3 = color
				label.TextTransparency = 0
			else
				label.Text = string.format("%2d  ---", index)
				label.TextColor3 = Color3.fromRGB(112, 110, 132)
				label.TextTransparency = 0.35
			end
		end
	end
	if state.statusLabel then
		state.statusLabel.Text = seasonLine()
	end
end

-- HUD snapshots ------------------------------------------------------------

function LeaderboardService.pushTo(player: Player)
	if not alive(player) then
		return
	end
	local list = gather()
	local viewerRank = nil
	for index, entry in ipairs(list) do
		if entry.userId == player.UserId then
			viewerRank = index
			break
		end
	end

	local top = {}
	for index = 1, math.min(Config.LEADERBOARD_ROWS, #list) do
		local entry = list[index]
		table.insert(top, {
			rank = index,
			name = entry.name,
			cash = entry.cash,
			rebirths = entry.rebirths,
		})
	end

	Util.fireClient(deps.Remotes.Leaderboard, player, {
		kind = "leaderboard",
		entries = top,
		viewerRank = viewerRank,
		viewerCash = state.sessionTotals[player] or deps.DataService.getBestTotal(player),
		totalPlayers = #list,
		season = Config.seasonInfo(),
	})
end

local function refresh()
	local now = os.clock()
	if now - state.lastRefresh < Config.LEADERBOARD_MIN_GAP then
		return
	end
	state.lastRefresh = now
	local list = gather()
	paintBoard(list)
	for _, player in ipairs(Players:GetPlayers()) do
		pcall(LeaderboardService.pushTo, player)
	end
end

function LeaderboardService.onPlayerAdded(player: Player)
	state.sessionTotals[player] = deps.DataService.getBestTotal(player)
	task.delay(1.2, function()
		if alive(player) then
			pcall(LeaderboardService.pushTo, player)
		end
	end)
end

function LeaderboardService.releasePlayer(player: Player)
	pcall(function()
		deps.DataService.save(player)
	end)
	state.sessionTotals[player] = nil
end

function LeaderboardService.start(services: any)
	deps = services
	Config = services.Config
	Util = services.Util

	state.running = true
	state.sessionTotals = {}
	state.lastRefresh = 0
	state.rowLabels = {}

	pcall(buildBoard)
	pcall(refresh)

	task.spawn(function()
		while state.running do
			task.wait(Config.LEADERBOARD_REFRESH)
			pcall(refresh)
		end
	end)
end

function LeaderboardService.stop()
	state.running = false
	local world = Workspace:FindFirstChild("World")
	local board = world and world:FindFirstChild("LeaderboardBoard")
	if board then
		board:Destroy()
	end
	state.rowLabels = {}
	state.sessionTotals = {}
end

return LeaderboardService
