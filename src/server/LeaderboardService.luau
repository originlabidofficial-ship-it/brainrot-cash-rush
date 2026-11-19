--!strict
-- LeaderboardService: owns the cash leaderboard. It accumulates each player's
-- total earned cash, folds in persisted all-time bests from DataService, builds
-- the physical TOP 10 board near spawn out of primitive parts, refreshes it on a
-- timer, and pushes the same table plus the viewer's own rank to every HUD.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LeaderboardService = {}

local deps: any = nil
local totalEarned: { [Player]: number } = {}
local board: Part? = nil
local rowLabels: { TextLabel } = {}
local rowColors: { TextLabel } = {}
local statusLabel: TextLabel? = nil
local lastRefresh = 0

local RANK_COLORS = {
	Color3.fromRGB(255, 212, 80),
	Color3.fromRGB(220, 228, 245),
	Color3.fromRGB(255, 164, 110),
}

local function formatRow(index: number, entry: any): (string, Color3)
	local rank = tostring(index)
	local name = string.sub(tostring(entry.name or "?"), 1, 14)
	local cash = deps.Util.formatCash(entry.cash or 0)
	local rebirths = tostring(entry.rebirths or 0)
	return string.format("%2s  %-14s  $%-8s  R%s", rank, name, cash, rebirths), RANK_COLORS[index] or Color3.fromRGB(225, 228, 245)
end

function LeaderboardService.recordEarn(player: Player, amount: number)
	if not player or not player.Parent then
		return
	end
	local gain = math.max(0, tonumber(amount) or 0)
	if gain <= 0 then
		return
	end
	local total = (totalEarned[player] or 0) + gain
	totalEarned[player] = total
	pcall(function()
		deps.DataService.updateBest(player, total, deps.PlayerService.getRebirths(player))
	end)
end

function LeaderboardService.getTotalEarned(player: Player): number
	return totalEarned[player] or 0
end

-- Merge all-time records with live players. Current players always win on name
-- and rebirths; their cash is the larger of session earnings and best total.
local function gather(): { any }
	local map: { [number]: any } = {}
	for userId, entry in pairs(deps.DataService.getAllTime()) do
		map[userId] = {
			userId = userId,
			name = entry.name or ("PLAYER " .. tostring(userId)),
			cash = entry.cash or 0,
			rebirths = entry.rebirths or 0,
		}
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local best = deps.DataService.getBestTotal(player)
		local session = totalEarned[player] or 0
		map[player.UserId] = {
			userId = player.UserId,
			name = player.DisplayName,
			cash = math.max(best, session),
			rebirths = deps.PlayerService.getRebirths(player),
		}
	end
	local list = {}
	for _, entry in pairs(map) do
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

local function updateBoard(list: { any })
	for index = 1, 10 do
		local label = rowLabels[index]
		if label then
			local entry = list[index]
			if entry then
				local text, color = formatRow(index, entry)
				label.Text = text
				label.TextColor3 = color
				label.TextTransparency = 0
			else
				label.Text = string.format("%2d  ---", index)
				label.TextColor3 = Color3.fromRGB(110, 108, 130)
				label.TextTransparency = 0.35
			end
		end
	end
	if statusLabel then
		statusLabel.Text = string.format("SERVER + ALL-TIME BESTS  •  LIVE  •  %s", os.date("%H:%M:%S"))
	end
end

function LeaderboardService.pushTo(player: Player)
	local list = gather()
	local rank = nil
	for index, entry in ipairs(list) do
		if entry.userId == player.UserId then
			rank = index
			break
		end
	end
	local top = {}
	for index = 1, math.min(10, #list) do
		local entry = list[index]
		table.insert(top, {
			rank = index,
			name = entry.name,
			cash = entry.cash,
			rebirths = entry.rebirths,
		})
	end
	deps.Util.fireClient(deps.Remotes.Leaderboard, player, {
		kind = "leaderboard",
		entries = top,
		viewerRank = rank,
		viewerCash = totalEarned[player] or deps.DataService.getBestTotal(player),
		totalPlayers = #list,
	})
end

local function refresh()
	local now = os.clock()
	if now - lastRefresh < 1 then
		return
	end
	lastRefresh = now
	local list = gather()
	updateBoard(list)
	for _, player in ipairs(Players:GetPlayers()) do
		LeaderboardService.pushTo(player)
	end
end

-- A physical board: two metal posts, a dark 24x16 stud screen, neon edge bars
-- and a SurfaceGui with ten fixed rows. Rebuilt as primitives, no asset ids.
local function buildBoard()
	local world = Workspace:FindFirstChild("World")
	if not world then
		return
	end
	local old = world:FindFirstChild("LeaderboardBoard")
	if old then
		old:Destroy()
	end
	local position = deps.Config.MAP.boardPos
	local facing = (Vector3.new(0, 0, 94) - position).Unit
	local cf = CFrame.lookAt(position + Vector3.new(0, 13, 0), position + Vector3.new(0, 13, 0) + facing)

	local frame = Instance.new("Folder")
	frame.Name = "LeaderboardBoard"
	frame.Parent = world

	for _, sx in ipairs({ -10.5, 10.5 }) do
		deps.Util.part({
			Size = Vector3.new(1.4, 9, 1.4),
			CFrame = CFrame.new(cf * CFrame.new(sx, -8.5, 0)),
			Color = Color3.fromRGB(44, 40, 66),
			Material = Enum.Material.Metal,
			CanCollide = true,
		}, frame).Name = "BoardPost"
	end

	local screen = deps.Util.part({
		Size = Vector3.new(24, 16, 0.7),
		CFrame = cf,
		Color = Color3.fromRGB(13, 11, 24),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	}, frame)
	screen.Name = "LeaderboardScreen"
	board = screen

	for _, bar in ipairs({
		{ Vector3.new(0, 8.25, 0), Vector3.new(25.2, 0.5, 1.1), Color3.fromRGB(90, 230, 255) },
		{ Vector3.new(0, -8.25, 0), Vector3.new(25.2, 0.5, 1.1), Color3.fromRGB(255, 95, 205) },
		{ Vector3.new(-12.25, 0, 0), Vector3.new(0.5, 16.8, 1.1), Color3.fromRGB(255, 95, 205) },
		{ Vector3.new(12.25, 0, 0), Vector3.new(0.5, 16.8, 1.1), Color3.fromRGB(90, 230, 255) },
	}) do
		deps.Util.part({
			Size = bar[2],
			CFrame = cf * CFrame.new(bar[1]),
			Color = bar[3],
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		}, frame).Name = "BoardNeon"
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 44
	gui.LightInfluence = 0
	gui.MaxDistance = 700
	gui.Parent = screen

	local panel = deps.Util.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(12, 10, 22),
		BackgroundTransparency = 0.05,
	}, gui)
	deps.Util.corner(panel, 18)
	deps.Util.stroke(panel, Color3.fromRGB(255, 208, 76), 3, 0.1)

	deps.Util.label({
		Size = UDim2.new(1, -24, 0.12, 0),
		Position = UDim2.fromOffset(12, 6),
		Text = "TOP 10  •  CASH EARNED",
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 220, 90),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, panel)
	statusLabel = deps.Util.label({
		Size = UDim2.new(1, -24, 0.055, 0),
		Position = UDim2.new(0, 12, 0.115, 0),
		Text = "SERVER + ALL-TIME BESTS  •  LIVE",
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(90, 230, 255),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, panel)

	rowLabels = {}
	for index = 1, 10 do
		local row = deps.Util.frame({
			Size = UDim2.new(1, -24, 0.068, 0),
			Position = UDim2.new(0, 12, 0.185 + (index - 1) * 0.077, 0),
			BackgroundColor3 = index % 2 == 0 and Color3.fromRGB(27, 23, 45) or Color3.fromRGB(20, 17, 34),
			BackgroundTransparency = 0.1,
		}, panel)
		deps.Util.corner(row, 7)
		local label = deps.Util.label({
			Size = UDim2.new(1, -14, 1, 0),
			Position = UDim2.fromOffset(7, 0),
			Text = string.format("%2d  ---", index),
			Font = Enum.Font.Code,
			TextColor3 = Color3.fromRGB(210, 214, 235),
			TextScaled = true,
		}, row)
		rowLabels[index] = label
		rowColors[index] = label
	end
end

function LeaderboardService.onPlayerAdded(player: Player)
	totalEarned[player] = deps.DataService.getBestTotal(player)
	task.delay(1.2, function()
		if player.Parent then
			LeaderboardService.pushTo(player)
		end
	end)
end

function LeaderboardService.releasePlayer(player: Player)
	pcall(function()
		deps.DataService.save(player)
	end)
	totalEarned[player] = nil
end

function LeaderboardService.init(services: any)
	deps = services
	totalEarned = {}
	lastRefresh = 0
	pcall(buildBoard)
	refresh()

	task.spawn(function()
		while true do
			task.wait(6)
			pcall(refresh)
		end
	end)
end

return LeaderboardService
