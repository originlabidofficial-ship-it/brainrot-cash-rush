-- MapService: builds the whole 3D arena from Roblox primitive parts at run
-- time. No asset ids, no models: floor, plaza fountain, six base decks,
-- raised wild zone, spawn portal, pillars, trees, arches and neon trim.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapService = {}

local Util
local Config

local function paint(props: { [string]: any }, parent: Instance): Part
	return Util.part(props, parent)
end

local function disc(position: Vector3, diameter: number, thickness: number, color: Color3, material: Enum.Material, parent: Instance, transparency: number?): Part
	return paint({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, diameter, diameter),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
		Transparency = transparency or 0,
		CanCollide = true,
	}, parent)
end

local function cylinderBetween(a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material, parent: Instance): Part
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	local p = paint({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		Color = color,
		Material = material,
	}, parent)
	p.CFrame = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0)
	return p
end

local function neonBar(size: Vector3, cf: CFrame, color: Color3, parent: Instance, transparency: number?): Part
	return paint({
		Size = size,
		CFrame = cf,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = transparency or 0,
	}, parent)
end

local function buildTree(parent: Instance, position: Vector3, leafColor: Color3, scale: number)
	local trunk = paint({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(10 * scale, 1.8 * scale, 1.8 * scale),
		CFrame = CFrame.new(position + Vector3.new(0, 5 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(116, 78, 52),
		Material = Enum.Material.Wood,
		CanCollide = true,
	}, parent)
	trunk.Name = "TreeTrunk"
	local offsets = {
		Vector3.new(0, 11, 0),
		Vector3.new(1.8, 9.4, 0.4),
		Vector3.new(-1.7, 9.6, -0.6),
		Vector3.new(0.4, 9.2, 1.7),
	}
	for i, offset in ipairs(offsets) do
		local s = (4.4 - i * 0.35) * scale
		local jitter = Vector3.new(math.random(-60, 60) / 100, 0, math.random(-60, 60) / 100)
		paint({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(s * 2, s * 2, s * 2),
			CFrame = CFrame.new(position + offset * scale + jitter),
			Color = leafColor:Lerp(Color3.fromRGB(255, 255, 255), i * 0.04),
			Material = Enum.Material.Grass,
			CanCollide = false,
		}, parent)
	end
	-- A small neon fruit so the trees read at a glance.
	paint({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.9, 0.9, 0.9),
		CFrame = CFrame.new(position + Vector3.new(1.4, 10.5, 1.4) * scale),
		Color = Color3.fromRGB(255, 210, 80),
		Material = Enum.Material.Neon,
	}, parent)
end

local function buildPillar(parent: Instance, position: Vector3, height: number, accent: Color3)
	paint({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 3.4, 3.4),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(238, 234, 242),
		Material = Enum.Material.Marble,
		CanCollide = true,
	}, parent)
	disc(position + Vector3.new(0, 0.25, 0), 5.2, 0.5, Color3.fromRGB(210, 202, 226), Enum.Material.Concrete, parent)
	local cap = disc(position + Vector3.new(0, height + 0.4, 0), 4.2, 1.2, accent, Enum.Material.Neon, parent)
	local light = Instance.new("PointLight")
	light.Color = accent
	light.Brightness = 1.1
	light.Range = 18
	light.Parent = cap
end

local function buildArch(parent: Instance, position: Vector3, width: number, height: number, color: Color3)
	local left = position + Vector3.new(-width / 2, 0, 0)
	local right = position + Vector3.new(width / 2, 0, 0)
	for _, side in ipairs({ left, right }) do
		paint({
			Size = Vector3.new(1.6, height, 1.6),
			CFrame = CFrame.new(side + Vector3.new(0, height / 2, 0)),
			Color = Color3.fromRGB(46, 40, 66),
			Material = Enum.Material.Metal,
			CanCollide = true,
		}, parent)
		neonBar(Vector3.new(0.35, height * 0.75, 0.35), CFrame.new(side + Vector3.new(0.9, height * 0.5, 0)), color, parent)
	end
	neonBar(Vector3.new(width + 2, 1.2, 1.2), CFrame.new(position + Vector3.new(0, height, 0)), color, parent)
	neonBar(Vector3.new(width + 2.8, 0.35, 0.35), CFrame.new(position + Vector3.new(0, height - 1.1, 0)), Color3.fromRGB(255, 255, 255), parent, 0.2)
end

local function buildFountain(parent: Instance, origin: Vector3)
	local fountain = Instance.new("Folder")
	fountain.Name = "Fountain"
	fountain.Parent = parent

	disc(origin + Vector3.new(0, 0.5, 0), 22, 1.4, Color3.fromRGB(224, 214, 226), Enum.Material.Marble, fountain)
	disc(origin + Vector3.new(0, 1.25, 0), 18.6, 0.5, Color3.fromRGB(130, 70, 140), Enum.Material.Concrete, fountain)
	local water = disc(origin + Vector3.new(0, 1.55, 0), 17.4, 0.35, Color3.fromRGB(60, 230, 255), Enum.Material.Neon, fountain, 0.18)
	water.Name = "Water"
	water.CanCollide = false

	paint({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6.2, 2.1, 2.1),
		CFrame = CFrame.new(origin + Vector3.new(0, 4.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(235, 220, 245),
		Material = Enum.Material.Marble,
	}, fountain)
	local bowl = paint({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(7.4, 7.4, 7.4),
		CFrame = CFrame.new(origin + Vector3.new(0, 7.4, 0)),
		Color = Color3.fromRGB(245, 235, 255),
		Material = Enum.Material.Marble,
		Transparency = 0.05,
		CanCollide = true,
	}, fountain)
	bowl.Name = "FountainBowl"

	local jetColors = {
		Color3.fromRGB(80, 240, 255),
		Color3.fromRGB(255, 110, 220),
		Color3.fromRGB(255, 215, 90),
		Color3.fromRGB(130, 255, 150),
	}
	for i = 1, 4 do
		local a = (i - 1) * math.pi / 2 + math.pi / 4
		local base = origin + Vector3.new(math.cos(a) * 7.6, 2.2, math.sin(a) * 7.6)
		cylinderBetween(base, base + Vector3.new(math.cos(a) * 3.2, 6.6, math.sin(a) * 3.2), 0.65, jetColors[i], Enum.Material.Neon, fountain)
		local glow = Instance.new("PointLight")
		glow.Color = jetColors[i]
		glow.Brightness = 1.6
		glow.Range = 14
		glow.Parent = water
	end

	local beam = neonBar(Vector3.new(2.2, 22, 2.2), CFrame.new(origin + Vector3.new(0, 13.5, 0)), Color3.fromRGB(160, 100, 255), fountain, 0.62)
	beam.Name = "FountainBeam"
	beam.CanCollide = false

	local coin = paint({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 3.4, 3.4),
		CFrame = CFrame.new(origin + Vector3.new(0, 11, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 208, 62),
		Material = Enum.Material.Neon,
	}, fountain)
	coin.Name = "FountainCoin"
end

-- Two side-readable SurfaceGui labels: the front faces the plaza/spawn and the
-- back face covers the reverse approach, so the sign always reads in a frame.
local function surfaceSign(board: Part, title: string, sub: string, color: Color3)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignGui"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 46
		gui.LightInfluence = 0
		gui.MaxDistance = 900
		gui.Parent = board

		local frame = Util.frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(14, 11, 26),
			BackgroundTransparency = 0.08,
		}, gui)
		Util.corner(frame, 24)
		Util.stroke(frame, color, 4, 0.06)
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 26, 78)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(20, 16, 36)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(64, 22, 54)),
		})
		gradient.Rotation = 16
		gradient.Parent = frame

		Util.label({
			Size = UDim2.new(1, -30, 0.52, 0),
			Position = UDim2.fromOffset(15, 8),
			Text = title,
			Font = Enum.Font.GothamBlack,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, frame)
		Util.label({
			Size = UDim2.new(1, -30, 0.24, 0),
			Position = UDim2.new(0, 15, 0.56, 0),
			Text = sub,
			Font = Enum.Font.GothamBold,
			TextColor3 = color,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, frame)
	end
end

-- A real 3D sign: dark board, neon trim on all four edges, SurfaceGui text on
-- both faces. Primitive parts only, no asset ids.
local function buildSignBoard(parent: Instance, position: Vector3, facing: Vector3, width: number, height: number, color: Color3, title: string, sub: string): Part
	local safeFacing = facing
	if safeFacing.Magnitude < 0.01 then
		safeFacing = Vector3.new(0, 0, 1)
	end
	local cf = CFrame.lookAt(position, position + safeFacing.Unit)
	local board = paint({
		Size = Vector3.new(width, height, 0.55),
		CFrame = cf,
		Color = Color3.fromRGB(14, 11, 26),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	}, parent)
	board.Name = "SignBoard"
	for _, barInfo in ipairs({
		{ Vector3.new(0, height / 2 + 0.28, 0), Vector3.new(width + 1.4, 0.5, 0.9) },
		{ Vector3.new(0, -height / 2 - 0.28, 0), Vector3.new(width + 1.4, 0.5, 0.9) },
		{ Vector3.new(-width / 2 - 0.28, 0, 0), Vector3.new(0.5, height + 0.7, 0.9) },
		{ Vector3.new(width / 2 + 0.28, 0, 0), Vector3.new(0.5, height + 0.7, 0.9) },
	}) do
		local bar = paint({
			Size = barInfo[2],
			CFrame = cf * CFrame.new(barInfo[1]),
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		}, parent)
		bar.Name = "SignFrame"
	end
	surfaceSign(board, title, sub, color)
	return board
end

local function buildTitleSign(parent: Instance, position: Vector3)
	local gold = Color3.fromRGB(255, 208, 76)
	-- Neon lift beams make the board feel mounted above the fountain instead of
	-- pasted onto the sky.
	for _, x in ipairs({ -27, 27 }) do
		neonBar(Vector3.new(1.2, 20, 1.2), CFrame.new(x, position.Y - 13.5, 0), Color3.fromRGB(150, 100, 255), parent, 0.45).Name = "TitleSupport"
	end
	neonBar(Vector3.new(46, 0.5, 0.5), CFrame.new(0, position.Y - 7.2, 0), Color3.fromRGB(90, 230, 255), parent, 0.2).Name = "TitleGlow"
	buildSignBoard(parent, position, Vector3.new(0, 0, 1), 50, 13, gold, "BRAINROT CASH RUSH", "GRAB  •  BANK  •  STEAL  •  REBIRTH")
end

-- WILD ZONE arch at the far end of the spawn deck: two chunky posts, a neon
-- top beam and a lit sign board facing the plaza.
local function buildWildSign(parent: Instance, origin: Vector3)
	local deckY = origin.Y + 1.4
	local archZ = origin.Z - 20
	local pink = Color3.fromRGB(255, 95, 205)
	for _, x in ipairs({ -21, 21 }) do
		local post = paint({
			Size = Vector3.new(2.4, 20, 2.4),
			CFrame = CFrame.new(origin.X + x, deckY + 10, archZ),
			Color = Color3.fromRGB(48, 40, 72),
			Material = Enum.Material.Metal,
			CanCollide = false,
		}, parent)
		post.Name = "WildArchPost"
		local edge = neonBar(Vector3.new(0.5, 15, 0.5), CFrame.new(origin.X + x, deckY + 10, archZ + 1.4), pink, parent)
		edge.Name = "WildArchNeon"
	end
	local topBeam = neonBar(Vector3.new(45, 2.2, 2.2), CFrame.new(origin.X, deckY + 20.4, archZ), Color3.fromRGB(90, 230, 255), parent)
	topBeam.Name = "WildArchBeam"
	buildSignBoard(parent, Vector3.new(origin.X, deckY + 15.4, archZ), Vector3.new(0, 0, 1), 32, 8.5, pink, "WILD ZONE", "CREATURES SPAWN HERE")
	-- Two pink floor chevrons point into the spawn deck.
	for i = 0, 1 do
		local chevron = neonBar(Vector3.new(10 - i * 3, 0.3, 1.2), CFrame.new(origin.X, deckY + 0.25, archZ + 4 + i * 4), pink, parent, 0.25)
		chevron.Name = "WildChevron"
	end
end

local function buildWildZone(parent: Instance, origin: Vector3)
	local wild = Instance.new("Folder")
	wild.Name = "WildZone"
	wild.Parent = parent

	paint({
		Size = Vector3.new(100, 3.2, 46),
		CFrame = CFrame.new(origin + Vector3.new(0, -0.2, 0)),
		Color = Color3.fromRGB(62, 44, 98),
		Material = Enum.Material.Slate,
		CanCollide = true,
	}, wild)
	neonBar(Vector3.new(100, 0.35, 0.65), CFrame.new(origin + Vector3.new(0, 1.5, -23)), Color3.fromRGB(255, 90, 200), wild)
	neonBar(Vector3.new(100, 0.35, 0.65), CFrame.new(origin + Vector3.new(0, 1.5, 23)), Color3.fromRGB(255, 90, 200), wild)
	neonBar(Vector3.new(0.65, 0.35, 46), CFrame.new(origin + Vector3.new(-50, 1.5, 0)), Color3.fromRGB(120, 220, 255), wild)
	neonBar(Vector3.new(0.65, 0.35, 46), CFrame.new(origin + Vector3.new(50, 1.5, 0)), Color3.fromRGB(120, 220, 255), wild)

	-- Seven low steps from the grass up to the wild deck. The tops climb from
	-- 0.8 to 5.0 studs, which is walkable without jumping and meets the deck's
	-- front edge instead of walling players out.
	for i = 0, 6 do
		local top = 0.8 + i * 0.7
		local z = origin.Z + 34.5 - i * 2.0
		paint({
			Size = Vector3.new(30, 0.8, 2.4),
			CFrame = CFrame.new(origin.X, top - 0.4, z),
			Color = Color3.fromRGB(118, 98, 168),
			Material = Enum.Material.Concrete,
			CanCollide = true,
		}, wild)
	end

	for _, x in ipairs({ -46, 46 }) do
		for _, z in ipairs({ -20, 20 }) do
			buildPillar(wild, origin + Vector3.new(x, 1.6, z), 12, Color3.fromRGB(255, 100, 210))
		end
	end

	-- Two neon trees frame the wild deck.
	buildTree(wild, origin + Vector3.new(-33, 1.6, -15), Color3.fromRGB(255, 120, 200), 1.0)
	buildTree(wild, origin + Vector3.new(34, 1.6, 14), Color3.fromRGB(110, 235, 190), 0.9)

	buildWildSign(wild, origin)
end

local function buildPortal(parent: Instance, origin: Vector3)
	local portal = Instance.new("Folder")
	portal.Name = "Portal"
	portal.Parent = parent

	disc(origin + Vector3.new(0, 0.1, 0), 34, 1.2, Color3.fromRGB(36, 30, 58), Enum.Material.Metal, portal)
	local pad = paint({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 24, 24),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(30, 220, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = true,
	}, portal)
	pad.Name = "PortalFloor"

	for i = 1, 18 do
		local a = (i - 1) / 18 * math.pi * 2
		local color = i % 2 == 0 and Color3.fromRGB(255, 90, 215) or Color3.fromRGB(60, 225, 255)
		local p = neonBar(
			Vector3.new(1.8, 2.8, 1.8),
			CFrame.new(origin + Vector3.new(math.cos(a) * 13, 6 + math.sin(a) * 13, 0)) * CFrame.Angles(0, 0, a + math.pi / 2),
			color,
			portal
		)
		p.Name = "PortalRing"
		p.CanCollide = false
	end
	for i = 1, 4 do
		local a = (i - 1) / 4 * math.pi * 2
		local light = Instance.new("PointLight")
		light.Color = i % 2 == 0 and Color3.fromRGB(255, 90, 215) or Color3.fromRGB(60, 225, 255)
		light.Brightness = 2
		light.Range = 26
		light.Parent = pad
		paint({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.2, 1.2, 1.2),
			CFrame = CFrame.new(origin + Vector3.new(math.cos(a) * 12, 1.6, math.sin(a) * 12)),
			Color = light.Color,
			Material = Enum.Material.Neon,
		}, portal)
	end

	local signPart = paint({
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(origin + Vector3.new(0, 24, 0)),
		Transparency = 1,
	}, portal)
	local bb = Util.billboard(signPart, Vector2.new(680, 170), Vector3.new(0, 0, 0), 300)
	local frame = Util.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(16, 12, 28),
		BackgroundTransparency = 0.18,
	}, bb)
	Util.corner(frame, 22)
	Util.stroke(frame, Color3.fromRGB(90, 230, 255), 4, 0.05)
	Util.label({
		Size = UDim2.new(1, -30, 0.58, 0),
		Position = UDim2.fromOffset(18, 6),
		Text = "BRAINROT CASH RUSH",
		Font = Enum.Font.GothamBlack,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
	}, frame)
	Util.label({
		Size = UDim2.new(1, -30, 0.28, 0),
		Position = UDim2.new(0, 18, 0.62, 0),
		Text = "GRAB  •  BANK  •  REBIRTH",
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(90, 230, 255),
		TextScaled = true,
	}, frame)

	-- Arch over the spawn deck.
	for _, x in ipairs({ -19, 19 }) do
		paint({
			Size = Vector3.new(2.2, 21, 2.2),
			CFrame = CFrame.new(origin + Vector3.new(x, 10.5, 0)),
			Color = Color3.fromRGB(48, 40, 72),
			Material = Enum.Material.Metal,
			CanCollide = true,
		}, portal)
		neonBar(Vector3.new(0.5, 15, 0.5), CFrame.new(origin + Vector3.new(x, 10.5, 1.25)), Color3.fromRGB(255, 90, 215), portal)
	end
	neonBar(Vector3.new(40, 2.4, 2.4), CFrame.new(origin + Vector3.new(0, 22, 0)), Color3.fromRGB(70, 225, 255), portal)
end

function MapService.build(deps: any)
	Util = deps.Util
	Config = deps.Config

	local existing = Workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end
	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = Workspace

	local map = Config.MAP

	-- Ground and plaza ------------------------------------------------------
	local ground = paint({
		Size = Vector3.new(map.arenaSize, 3, map.arenaSize),
		CFrame = CFrame.new(0, -1.5, 0),
		Color = Color3.fromRGB(87, 176, 112),
		Material = Enum.Material.Grass,
		CanCollide = true,
	}, world)
	ground.Name = "ArenaFloor"

	disc(Vector3.new(0, 0.15, 0), map.plazaRadius * 2, 0.8, Color3.fromRGB(238, 228, 216), Enum.Material.Concrete, world)
	disc(Vector3.new(0, 0.55, 0), map.plazaRadius * 2 - 3, 0.4, Color3.fromRGB(248, 241, 230), Enum.Material.Marble, world)
	local rim = disc(Vector3.new(0, 0.75, 0), map.plazaRadius * 2 + 1.4, 0.5, Color3.fromRGB(255, 200, 80), Enum.Material.Neon, world, 0.15)
	rim.Name = "PlazaRim"
	rim.CanCollide = false

	-- Soft coloured rings in the plaza.
	for i = 1, 3 do
		local ring = disc(Vector3.new(0, 0.52, 0), 12 + i * 6, 0.12, i % 2 == 0 and Color3.fromRGB(255, 120, 210) or Color3.fromRGB(90, 220, 255), Enum.Material.Neon, world, 0.55)
		ring.CanCollide = false
	end

	buildFountain(world, Vector3.new(0, 0, 0))
	buildTitleSign(world, Vector3.new(0, 33, 0))

	-- Paths from every base toward the plaza --------------------------------
	for i = 0, 5 do
		local a = math.rad(30 + i * 60)
		local dir = Vector3.new(math.sin(a), 0, math.cos(a))
		local mid = dir * ((map.baseRadius + map.plazaRadius) / 2)
		local path = paint({
			Size = Vector3.new(10, 0.35, map.baseRadius - map.plazaRadius + 4),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.35, 0), Vector3.new(0, 0.35, 0)),
			Color = Color3.fromRGB(226, 216, 200),
			Material = Enum.Material.Concrete,
			CanCollide = false,
		}, world)
		path.Name = "Path"
	end

	-- Boundary: invisible walls plus a visible neon curb ---------------------
	local half = map.arenaHalf - 1
	for _, info in ipairs({
		{ Vector3.new(0, 18, -half), Vector3.new(6, 36, 2) },
		{ Vector3.new(0, 18, half), Vector3.new(6, 36, 2) },
		{ Vector3.new(-half, 18, 0), Vector3.new(2, 36, 6) },
		{ Vector3.new(half, 18, 0), Vector3.new(2, 36, 6) },
	}) do
		local wall = paint({
			Size = info[2],
			CFrame = CFrame.new(info[1]),
			Transparency = 1,
			CanCollide = true,
		}, world)
		wall.Name = "Boundary"
	end
	for i = 0, 3 do
		local a = i * math.pi / 2
		local bar = neonBar(
			Vector3.new(i % 2 == 0 and map.arenaSize or 0.6, 0.55, i % 2 == 0 and 0.6 or map.arenaSize),
			CFrame.new(Vector3.new(math.sin(a) * half, 0.35, math.cos(a) * half)),
			Color3.fromRGB(255, 110, 210),
			world,
			0.1
		)
		bar.Name = "BoundaryNeon"
	end

	buildWildZone(world, Vector3.new(0, map.wildTop, -94))
	buildPortal(world, Vector3.new(0, 0, 94))

	-- Pillars ring the plaza ------------------------------------------------
	for i = 0, 7 do
		local a = math.rad(22.5 + i * 45)
		local p = Vector3.new(math.sin(a) * 37, 0, math.cos(a) * 37)
		buildPillar(world, p, 13, i % 2 == 0 and Color3.fromRGB(255, 200, 80) or Color3.fromRGB(90, 225, 255))
	end

	-- Neon arches over the north and south approach.
	buildArch(world, Vector3.new(0, 0, 70), 34, 18, Color3.fromRGB(255, 105, 215))
	buildArch(world, Vector3.new(0, 0, -66), 34, 16, Color3.fromRGB(90, 220, 255))

	-- Trees on the outskirts (fixed spots, away from pads and the wild deck).
	local treeSpots = {
		{ Vector3.new(-102, 0, -18), Color3.fromRGB(64, 182, 118), 1.0 },
		{ Vector3.new(104, 0, -26), Color3.fromRGB(74, 196, 132), 0.9 },
		{ Vector3.new(-96, 0, 72), Color3.fromRGB(255, 150, 200), 0.85 },
		{ Vector3.new(98, 0, 66), Color3.fromRGB(120, 220, 150), 1.0 },
		{ Vector3.new(-58, 0, 108), Color3.fromRGB(96, 206, 128), 0.8 },
		{ Vector3.new(56, 0, 110), Color3.fromRGB(255, 170, 100), 0.9 },
		{ Vector3.new(-112, 0, 108), Color3.fromRGB(110, 220, 160), 0.75 },
		{ Vector3.new(114, 0, 112), Color3.fromRGB(255, 145, 205), 0.8 },
		{ Vector3.new(-112, 0, -102), Color3.fromRGB(130, 230, 160), 0.9 },
		{ Vector3.new(112, 0, -104), Color3.fromRGB(255, 160, 210), 0.8 },
	}
	for _, spot in ipairs(treeSpots) do
		buildTree(world, spot[1], spot[2], spot[3])
	end

	-- Lamp posts between the bases.
	for i = 0, 5 do
		local a = math.rad(60 + i * 60)
		local base = Vector3.new(math.sin(a) * 46, 0, math.cos(a) * 46)
		paint({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(9, 0.6, 0.6),
			CFrame = CFrame.new(base + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(52, 46, 72),
			Material = Enum.Material.Metal,
			CanCollide = true,
		}, world)
		local bulb = paint({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.8, 1.8, 1.8),
			CFrame = CFrame.new(base + Vector3.new(0, 9.4, 0)),
			Color = i % 2 == 0 and Color3.fromRGB(255, 215, 90) or Color3.fromRGB(90, 230, 255),
			Material = Enum.Material.Neon,
		}, world)
		local light = Instance.new("PointLight")
		light.Color = bulb.Color
		light.Brightness = 1.4
		light.Range = 22
		light.Parent = bulb
	end

	-- Floating neon orbits high above the arena; Effects.client.luau spins
	-- these locally so no server work is spent on decoration.
	local orbits = Instance.new("Folder")
	orbits.Name = "Orbits"
	orbits.Parent = world
	for ringIndex = 1, 3 do
		local ringModel = Instance.new("Model")
		ringModel.Name = "Orbit" .. ringIndex
		ringModel.Parent = orbits
		local radius = 34 + ringIndex * 14
		local height = 34 + ringIndex * 7
		local color = ({ Color3.fromRGB(90, 225, 255), Color3.fromRGB(255, 110, 215), Color3.fromRGB(255, 215, 90) })[ringIndex]
		for i = 1, 14 do
			local a = i / 14 * math.pi * 2
			local p = paint({
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.4, 1.4, 1.4),
				CFrame = CFrame.new(Vector3.new(math.cos(a) * radius, height, math.sin(a) * radius)),
				Color = color,
				Material = Enum.Material.Neon,
				Transparency = 0.15,
			}, ringModel)
			p.Name = "OrbitDot"
		end
	end

	-- Spawn point ------------------------------------------------------------
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CashRushSpawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(0, 2.5, 94)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Transparency = 0.2
	spawn.Color = Color3.fromRGB(60, 230, 255)
	spawn.Material = Enum.Material.Neon
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = Workspace

	-- Lighting / mood --------------------------------------------------------
	pcall(function()
		Lighting.ClockTime = 14.3
		Lighting.Brightness = 2.6
		Lighting.Ambient = Color3.fromRGB(88, 94, 128)
		Lighting.OutdoorAmbient = Color3.fromRGB(150, 164, 200)
		Lighting.EnvironmentDiffuseScale = 0.6
		Lighting.EnvironmentSpecularScale = 0.65
		Lighting.FogStart = 240
		Lighting.FogEnd = 1100
		Lighting.FogColor = Color3.fromRGB(186, 214, 244)
	end)

	local oldAtmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if oldAtmosphere then
		oldAtmosphere:Destroy()
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(228, 224, 255)
	atmosphere.Decay = Color3.fromRGB(116, 156, 220)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting

	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.85
	bloom.Size = 26
	bloom.Threshold = 0.92

	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Parent = Lighting
	end
	cc.Brightness = 0.02
	cc.Contrast = 0.06
	cc.Saturation = 0.2
	cc.TintColor = Color3.fromRGB(255, 250, 245)

	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if not sunRays then
		sunRays = Instance.new("SunRaysEffect")
		sunRays.Parent = Lighting
	end
	sunRays.Intensity = 0.14
	sunRays.Spread = 0.5

	MapService.world = world
end

return MapService
