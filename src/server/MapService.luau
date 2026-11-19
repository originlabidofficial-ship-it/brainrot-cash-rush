--!strict
-- MapService — builds the static world once, at boot.
--
-- The map is deliberately bright and readable: grass, warm concrete and marble
-- carry the shape of the arena, and neon is used only for trim, rims and signs
-- so screenshots stay legible in daylight. Nothing here has gameplay authority:
-- BaseService owns the decks, BrainrotService owns the creatures, WaveService
-- owns its wall. This module only produces scenery under Workspace.World plus a
-- single SpawnLocation.
--
-- buildStatic() can also be called straight from the Studio command bar, where
-- no service container exists, so it resolves Config/Util itself in that case.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapService = {}

local Config: any = nil
local Util: any = nil

-- Shared palette. Every colour the map uses lives here, so the whole arena can
-- be retinted in one place.
local PALETTE = {
	grass = Color3.fromRGB(104, 194, 122),
	grassDark = Color3.fromRGB(86, 172, 104),
	concrete = Color3.fromRGB(238, 231, 220),
	marble = Color3.fromRGB(250, 245, 236),
	deck = Color3.fromRGB(226, 219, 206),
	wood = Color3.fromRGB(186, 138, 92),
	metal = Color3.fromRGB(70, 68, 88),
	stone = Color3.fromRGB(214, 208, 196),
	dark = Color3.fromRGB(28, 25, 42),
	water = Color3.fromRGB(96, 214, 255),
	neonGold = Color3.fromRGB(255, 208, 84),
	neonCyan = Color3.fromRGB(84, 226, 255),
	neonPink = Color3.fromRGB(255, 110, 208),
	neonGreen = Color3.fromRGB(140, 240, 150),
}

local function ensureDeps(): boolean
	if Config and Util then
		return true
	end
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local configModule = shared and shared:FindFirstChild("Config")
	local utilModule = shared and shared:FindFirstChild("Util")
	if not configModule or not utilModule then
		return false
	end
	Config = require(configModule)
	Util = require(utilModule)
	return true
end

-- Small construction helpers ----------------------------------------------

local function block(props: { [string]: any }, parent: Instance): Part
	return Util.part(props, parent)
end

local function disc(position: Vector3, diameter: number, thickness: number, color: Color3, material: Enum.Material, parent: Instance, alpha: number?): Part
	return Util.flatDisc(position, diameter, thickness, color, material, parent, alpha)
end

local function bar(size: Vector3, cframe: CFrame, color: Color3, parent: Instance, alpha: number?): Part
	return block({
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = alpha or 0,
		CanCollide = false,
		CanQuery = false,
	}, parent)
end

-- A cylinder spanning two points, used for branches, poles and cables.
local function beam(a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material, parent: Instance): Part
	local delta = b - a
	local length = delta.Magnitude
	local part = block({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = CFrame.lookAt(a + delta * 0.5, b) * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Material = material,
		CanCollide = false,
	}, parent)
	return part
end

-- A readable SurfaceGui panel: dark card, neon border, two lines of text.
local function signPanel(board: Part, title: string, sub: string, accent: Color3, faces: { Enum.NormalId }?)
	local faceList = faces or { Enum.NormalId.Front, Enum.NormalId.Back }
	for _, face in ipairs(faceList) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignGui"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 42
		gui.LightInfluence = 0
		gui.MaxDistance = 520
		gui.Parent = board

		local card = Util.frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = PALETTE.dark,
			BackgroundTransparency = 0.08,
		}, gui)
		Util.corner(card, 16)
		Util.stroke(card, accent, 3, 0.06)

		Util.label({
			Size = UDim2.new(1, -16, 0.56, 0),
			Position = UDim2.fromOffset(8, 4),
			Text = title,
			Font = Enum.Font.GothamBlack,
			TextColor3 = accent,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, card)
		Util.label({
			Size = UDim2.new(1, -16, 0.3, 0),
			Position = UDim2.new(0, 8, 0.6, 0),
			Text = sub,
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(236, 232, 248),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, card)
	end
end

-- A sign board facing a target position, with neon trim. Returns the board so
-- callers can add more gui layers.
local function signBoard(parent: Instance, position: Vector3, facing: Vector3, width: number, height: number, accent: Color3, title: string, sub: string): Part
	local look = facing.Magnitude > 0.01 and facing.Unit or Vector3.new(0, 0, 1)
	local cframe = CFrame.lookAt(position, position + look)
	local board = block({
		Size = Vector3.new(width, height, 0.6),
		CFrame = cframe,
		Color = PALETTE.dark,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	}, parent)
	board.Name = "SignBoard"

	local trim = {
		{ Vector3.new(0, height / 2 + 0.25, 0), Vector3.new(width + 1.2, 0.4, 0.9) },
		{ Vector3.new(0, -height / 2 - 0.25, 0), Vector3.new(width + 1.2, 0.4, 0.9) },
		{ Vector3.new(-width / 2 - 0.3, 0, 0), Vector3.new(0.4, height + 1.2, 0.9) },
		{ Vector3.new(width / 2 + 0.3, 0, 0), Vector3.new(0.4, height + 1.2, 0.9) },
	}
	for _, piece in ipairs(trim) do
		bar(piece[2], cframe * CFrame.new(piece[1]), accent, parent, 0.05).Name = "SignTrim"
	end
	signPanel(board, title, sub, accent)
	return board
end

-- Scenery builders --------------------------------------------------------

local function buildTree(parent: Instance, position: Vector3, leafColor: Color3, scale: number)
	local trunk = block({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(9 * scale, 2.1 * scale, 2.1 * scale),
		CFrame = CFrame.new(position + Vector3.new(0, 4.5 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.wood,
		Material = Enum.Material.Wood,
		CanCollide = true,
	}, parent)
	trunk.Name = "TreeTrunk"

	local crown = {
		{ Vector3.new(0, 9.4, 0), 6.4 },
		{ Vector3.new(1.9, 8.2, 1.2), 4.4 },
		{ Vector3.new(-1.8, 8.4, -1.0), 4.0 },
		{ Vector3.new(0.4, 11.2, -0.6), 3.6 },
	}
	for index, layer in ipairs(crown) do
		local leaf = block({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(layer[2], layer[2] * 0.9, layer[2]) * scale,
			CFrame = CFrame.new(position + layer[1] * scale),
			Color = index % 2 == 0 and leafColor:Lerp(Color3.fromRGB(255, 255, 255), 0.12) or leafColor,
			Material = Enum.Material.Grass,
			CanCollide = false,
		}, parent)
		leaf.Name = "TreeCrown"
	end
end

local function buildPillar(parent: Instance, position: Vector3, height: number, accent: Color3)
	local shaft = block({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 2.6, 2.6),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.marble,
		Material = Enum.Material.Marble,
		CanCollide = true,
	}, parent)
	shaft.Name = "Pillar"

	disc(position + Vector3.new(0, 0.4, 0), 4.4, 0.8, PALETTE.stone, Enum.Material.Concrete, parent).Name = "PillarBase"
	local cap = disc(position + Vector3.new(0, height + 0.4, 0), 4.0, 0.9, PALETTE.stone, Enum.Material.Concrete, parent)
	cap.Name = "PillarCap"
	local lamp = block({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.8, 1.8, 1.8),
		CFrame = CFrame.new(position + Vector3.new(0, height + 1.6, 0)),
		Color = accent,
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, parent)
	lamp.Name = "PillarLamp"
	local light = Instance.new("PointLight")
	light.Color = accent
	light.Brightness = 1.2
	light.Range = 26
	light.Parent = lamp
end

local function buildArch(parent: Instance, position: Vector3, width: number, height: number, accent: Color3)
	local legOffset = width / 2
	for _, side in ipairs({ -1, 1 }) do
		local leg = block({
			Size = Vector3.new(1.6, height, 1.6),
			CFrame = CFrame.new(position + Vector3.new(side * legOffset, height / 2, 0)),
			Color = PALETTE.marble,
			Material = Enum.Material.Marble,
			CanCollide = true,
		}, parent)
		leg.Name = "ArchLeg"
	end
	bar(Vector3.new(width + 2.4, 1.2, 1.6), CFrame.new(position + Vector3.new(0, height + 0.6, 0)), accent, parent, 0.05).Name = "ArchBeam"
	bar(Vector3.new(width + 2.4, 0.35, 2.2), CFrame.new(position + Vector3.new(0, height - 0.4, 0)), PALETTE.neonGold, parent, 0.35).Name = "ArchGlow"
end

local function buildFountain(parent: Instance, origin: Vector3)
	local model = Instance.new("Model")
	model.Name = "Fountain"
	model.Parent = parent

	disc(origin + Vector3.new(0, 0.5, 0), 20, 1.0, PALETTE.marble, Enum.Material.Marble, model).Name = "FountainBasin"
	disc(origin + Vector3.new(0, 1.05, 0), 18.2, 0.4, PALETTE.water, Enum.Material.SmoothPlastic, model, 0.15).Name = "Water"
	local lip = disc(origin + Vector3.new(0, 1.4, 0), 20.6, 0.5, PALETTE.neonCyan, Enum.Material.Neon, model, 0.25)
	lip.Name = "FountainLip"

	local column = block({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(7, 2.0, 2.0),
		CFrame = CFrame.new(origin + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.marble,
		Material = Enum.Material.Marble,
		CanCollide = true,
	}, model)
	column.Name = "FountainColumn"

	local coin = block({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 3.2, 3.2),
		CFrame = CFrame.new(origin + Vector3.new(0, 8.4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.neonGold,
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, model)
	coin.Name = "FountainCoin"

	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		local jet = block({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.1, 1.1, 1.1),
			CFrame = CFrame.new(origin + Vector3.new(math.cos(angle) * 6.4, 2.4 + (i % 2) * 0.6, math.sin(angle) * 6.4)),
			Color = PALETTE.water,
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			CanCollide = false,
		}, model)
		jet.Name = "FountainJet"
	end
end

local function buildTitleSign(parent: Instance, position: Vector3)
	local board = signBoard(parent, position, Vector3.new(0, 0, 1), 62, 12, PALETTE.neonGold, "BRAINROT CASH RUSH", "GRAB • BANK • UPGRADE • REBIRTH")
	board.Name = "TitleSign"
	for _, side in ipairs({ -1, 1 }) do
		block({
			Size = Vector3.new(1.2, position.Y, 1.2),
			CFrame = CFrame.new(Vector3.new(position.X + side * 26, position.Y / 2, position.Z)),
			Color = PALETTE.metal,
			Material = Enum.Material.Metal,
			CanCollide = false,
		}, parent).Name = "TitlePost"
	end
end

-- The wild deck: a raised pastel platform where creatures spawn and wander.
local function buildWildDeck(parent: Instance, origin: Vector3)
	local model = Instance.new("Model")
	model.Name = "WildZone"
	model.Parent = parent

	local deck = block({
		Size = Vector3.new(Config.MAP.wildHalfX * 2 + 10, 1.4, Config.MAP.wildHalfZ * 2 + 10),
		CFrame = CFrame.new(Vector3.new(origin.X, origin.Y - 0.7, origin.Z)),
		Color = Color3.fromRGB(250, 236, 196),
		Material = Enum.Material.Sand,
		CanCollide = true,
	}, model)
	deck.Name = "WildDeck"

	local trim = bar(
		Vector3.new(Config.MAP.wildHalfX * 2 + 12, 0.5, Config.MAP.wildHalfZ * 2 + 12),
		CFrame.new(Vector3.new(origin.X, origin.Y + 0.1, origin.Z)),
		PALETTE.neonPink,
		model,
		0.15
	)
	trim.Name = "WildTrim"

	for _, side in ipairs({ -1, 1 }) do
		bar(
			Vector3.new(Config.MAP.wildHalfX * 2 + 12, 0.45, 0.6),
			CFrame.new(Vector3.new(origin.X, origin.Y + 0.15, origin.Z + side * (Config.MAP.wildHalfZ + 6))),
			PALETTE.neonCyan,
			model,
			0.2
		).Name = "WildEdge"
	end

	-- Little hills so the deck does not read as one flat slab.
	for i = -2, 2 do
		local hill = block({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(14, 5, 10),
			CFrame = CFrame.new(Vector3.new(origin.X + i * 17, origin.Y - 1.6, origin.Z + (i % 2) * 12)),
			Color = Color3.fromRGB(214, 236, 168),
			Material = Enum.Material.Grass,
			CanCollide = false,
		}, model)
		hill.Name = "WildHill"
	end

	signBoard(model, Vector3.new(origin.X, origin.Y + 12, origin.Z + 30), Vector3.new(0, 0, 1), 40, 9, PALETTE.neonPink, "WILD DECK", "TOUCH A BRAINROT TO GRAB IT")
end

local function buildPortal(parent: Instance, origin: Vector3)
	local model = Instance.new("Model")
	model.Name = "Portal"
	model.Parent = parent

	for _, side in ipairs({ -1, 1 }) do
		local post = block({
			Size = Vector3.new(1.6, 16, 1.6),
			CFrame = CFrame.new(origin + Vector3.new(side * 7, 8, 0)),
			Color = PALETTE.marble,
			Material = Enum.Material.Marble,
			CanCollide = true,
		}, model)
		post.Name = "PortalPost"
	end
	local ring = bar(Vector3.new(17, 1.4, 1.8), CFrame.new(origin + Vector3.new(0, 16.2, 0)), PALETTE.neonCyan, model, 0.05)
	ring.Name = "PortalRing"
	local veil = block({
		Size = Vector3.new(12.6, 14.4, 0.4),
		CFrame = CFrame.new(origin + Vector3.new(0, 8.2, 0)),
		Color = PALETTE.neonCyan,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		CanCollide = false,
	}, model)
	veil.Name = "PortalVeil"

	local pad = disc(origin + Vector3.new(0, 0.4, 0), 22, 0.8, PALETTE.marble, Enum.Material.Marble, model)
	pad.Name = "PortalPad"
	local glow = disc(origin + Vector3.new(0, 0.9, 0), 20, 0.3, PALETTE.neonCyan, Enum.Material.Neon, model, 0.3)
	glow.Name = "PortalGlow"
end

local function buildShopKiosk(parent: Instance, origin: Vector3)
	local model = Instance.new("Model")
	model.Name = "ShopKiosk"
	model.Parent = parent

	local floor = disc(origin + Vector3.new(0, 0.45, 0), 26, 0.9, PALETTE.deck, Enum.Material.Concrete, model)
	floor.Name = "ShopFloor"
	disc(origin + Vector3.new(0, 0.95, 0), 24, 0.3, PALETTE.neonGold, Enum.Material.Neon, model, 0.35).Name = "ShopGlow"

	local counter = block({
		Size = Vector3.new(16, 3.4, 4.4),
		CFrame = CFrame.new(origin + Vector3.new(0, 2.1, -6)),
		Color = PALETTE.wood,
		Material = Enum.Material.Wood,
		CanCollide = true,
	}, model)
	counter.Name = "ShopCounter"
	bar(Vector3.new(17, 0.4, 5.2), CFrame.new(origin + Vector3.new(0, 3.9, -6)), PALETTE.neonGold, model, 0.1).Name = "ShopCounterTrim"

	for _, side in ipairs({ -1, 1 }) do
		local post = block({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(11, 1.1, 1.1),
			CFrame = CFrame.new(origin + Vector3.new(side * 9, 6.5, -6)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = PALETTE.metal,
			Material = Enum.Material.Metal,
			CanCollide = false,
		}, model)
		post.Name = "ShopPost"
	end

	local roof = block({
		Size = Vector3.new(22, 1.0, 12),
		CFrame = CFrame.new(origin + Vector3.new(0, 12.6, -4)),
		Color = PALETTE.neonPink,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
	}, model)
	roof.Name = "ShopAwning"

	local sign = signBoard(model, origin + Vector3.new(0, 17.5, -2), Vector3.new(0, 0, 1), 26, 7, PALETTE.neonGold, "UPGRADE SHOP", "PRESS B ANYWHERE")
	sign.Name = "ShopSign"

	-- Upgrade icons as floating neon cubes: readable from the plaza.
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		block({
			Size = Vector3.new(1.4, 1.4, 1.4),
			CFrame = CFrame.new(origin + Vector3.new(math.cos(angle) * 10, 4.6, math.sin(angle) * 6)),
			Color = index % 2 == 0 and PALETTE.neonCyan or PALETTE.neonGold,
			Material = Enum.Material.Neon,
			CanCollide = false,
		}, model).Name = "ShopIcon"
	end
end

local function buildVault(parent: Instance, origin: Vector3)
	local model = Instance.new("Model")
	model.Name = "Vault"
	model.Parent = parent

	local body = block({
		Size = Vector3.new(16, 12, 12),
		CFrame = CFrame.new(origin + Vector3.new(0, 6, 0)),
		Color = Color3.fromRGB(196, 200, 214),
		Material = Enum.Material.Metal,
		CanCollide = true,
	}, model)
	body.Name = "VaultBody"

	local door = block({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 9, 9),
		CFrame = CFrame.new(origin + Vector3.new(0, 6, 6.4)) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(160, 166, 186),
		Material = Enum.Material.Metal,
		CanCollide = false,
	}, model)
	door.Name = "VaultDoor"
	bar(Vector3.new(2.6, 0.6, 0.6), CFrame.new(origin + Vector3.new(0, 6, 7.2)), PALETTE.neonGold, model, 0.05).Name = "VaultHandle"

	local roof = block({
		Size = Vector3.new(17.4, 1.0, 13.4),
		CFrame = CFrame.new(origin + Vector3.new(0, 12.4, 0)),
		Color = PALETTE.neonGold,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CanCollide = false,
	}, model)
	roof.Name = "VaultRoof"

	signBoard(model, origin + Vector3.new(0, 16, 0), Vector3.new(-1, 0, 0), 20, 6, PALETTE.neonGold, "THE VAULT", "BANKED CASH IS SAFE")
end

local function buildDock(parent: Instance, origin: Vector3)
	local model = Instance.new("Model")
	model.Name = "Dock"
	model.Parent = parent

	local deck = block({
		Size = Vector3.new(46, 1.2, 34),
		CFrame = CFrame.new(origin + Vector3.new(0, 1.2, 0)),
		Color = PALETTE.wood,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	}, model)
	deck.Name = "DockDeck"

	for i = -2, 2 do
		local plank = bar(
			Vector3.new(46, 0.2, 0.4),
			CFrame.new(origin + Vector3.new(0, 1.9, i * 6.6)),
			i % 2 == 0 and PALETTE.neonCyan or PALETTE.neonPink,
			model,
			0.5
		)
		plank.Name = "DockStripe"
	end

	-- Water beside the dock, flat and bright so the edge reads clearly.
	local sea = block({
		Size = Vector3.new(120, 1.0, 90),
		CFrame = CFrame.new(origin + Vector3.new(48, 0.1, -10)),
		Color = Color3.fromRGB(120, 210, 240),
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		CanCollide = false,
	}, model)
	sea.Name = "HarbourWater"

	for i = 1, 4 do
		local post = block({
			Size = Vector3.new(1.4, 6, 1.4),
			CFrame = CFrame.new(origin + Vector3.new(-20 + i * 13, 4, 15)),
			Color = PALETTE.metal,
			Material = Enum.Material.Metal,
			CanCollide = true,
		}, model)
		post.Name = "DockBollard"
		bar(Vector3.new(1.8, 0.5, 1.8), CFrame.new(origin + Vector3.new(-20 + i * 13, 7.2, 15)), PALETTE.neonGold, model, 0.1).Name = "DockLight"
	end

	local boat = block({
		Size = Vector3.new(8, 3, 16),
		CFrame = CFrame.new(origin + Vector3.new(24, 1.6, -6)),
		Color = Color3.fromRGB(250, 246, 240),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
	}, model)
	boat.Name = "DockBoat"
	bar(Vector3.new(8.4, 0.4, 16.4), CFrame.new(origin + Vector3.new(24, 3.2, -6)), PALETTE.neonPink, model, 0.2).Name = "BoatStripe"

	signBoard(model, origin + Vector3.new(0, 12, 14), Vector3.new(0, 0, -1), 24, 7, PALETTE.neonCyan, "THE DOCK", "STEAL RUNS START HERE")
end

-- A pale stone path from the plaza out to the dock, plus scattered crates.
local function buildHarbourPath(parent: Instance, origin: Vector3)
	local model = Instance.new("Model")
	model.Name = "HarbourPath"
	model.Parent = parent

	local from = Vector3.new(origin.X + 26, 0.35, origin.Z)
	local to = Vector3.new(Config.MAP.dockCenter.X - 20, 0.35, Config.MAP.dockCenter.Z)
	local steps = 12
	for i = 0, steps do
		local t = i / steps
		local point = from:Lerp(to, t)
		local tile = block({
			Size = Vector3.new(12, 0.5, 8),
			CFrame = CFrame.lookAt(point, to),
			Color = PALETTE.concrete,
			Material = Enum.Material.Concrete,
			CanCollide = false,
		}, model)
		tile.Name = "PathTile"
		if i % 3 == 0 then
			bar(Vector3.new(12, 0.2, 0.5), CFrame.lookAt(point + Vector3.new(0, 0.3, 0), to), PALETTE.neonCyan, model, 0.4).Name = "PathGlow"
		end
	end

	for _, spot in ipairs({ Vector3.new(58, 1.6, -34), Vector3.new(66, 1.6, -18), Vector3.new(84, 1.6, -46) }) do
		local crate = block({
			Size = Vector3.new(4.4, 3.2, 4.4),
			CFrame = CFrame.new(spot) * CFrame.Angles(0, math.rad(spot.X), 0),
			Color = PALETTE.wood,
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
		}, model)
		crate.Name = "Crate"
	end
end

-- Lighting ----------------------------------------------------------------

local function applyLighting()
	pcall(function()
		Lighting.ClockTime = 14.2
		Lighting.Brightness = 3.1
		Lighting.ExposureCompensation = 0.25
		Lighting.Ambient = Color3.fromRGB(132, 136, 160)
		Lighting.OutdoorAmbient = Color3.fromRGB(178, 186, 212)
		Lighting.EnvironmentDiffuseScale = 0.75
		Lighting.EnvironmentSpecularScale = 0.55
		Lighting.FogStart = 320
		Lighting.FogEnd = 1500
		Lighting.FogColor = Color3.fromRGB(206, 226, 246)
		Lighting.GlobalShadows = true
	end)

	local oldAtmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if oldAtmosphere then
		oldAtmosphere:Destroy()
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Haze = 0.9
	atmosphere.Glare = 0.1
	atmosphere.Color = Color3.fromRGB(226, 238, 252)
	atmosphere.Decay = Color3.fromRGB(160, 176, 206)
	atmosphere.Parent = Lighting

	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.45
		bloom.Size = 22
		bloom.Threshold = 1.6
		bloom.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("ColorCorrectionEffect") then
		local correction = Instance.new("ColorCorrectionEffect")
		correction.Brightness = 0.04
		correction.Contrast = 0.08
		correction.Saturation = 0.12
		correction.TintColor = Color3.fromRGB(255, 250, 244)
		correction.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("SunRaysEffect") then
		local rays = Instance.new("SunRaysEffect")
		rays.Intensity = 0.06
		rays.Spread = 0.6
		rays.Parent = Lighting
	end
end

-- The build ---------------------------------------------------------------

function MapService.buildStatic(services: any?)
	if services then
		Config = services.Config
		Util = services.Util
	elseif not ensureDeps() then
		warn("[MapService] cannot build the map: Shared.Config/Util not found")
		return nil
	end

	local previous = Workspace:FindFirstChild("World")
	if previous then
		previous:Destroy()
	end
	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = Workspace

	local map = Config.MAP

	-- Ground: bright grass, then the plaza on top of it.
	local ground = block({
		Size = Vector3.new(map.arenaSize, 3, map.arenaSize),
		CFrame = CFrame.new(0, -1.5, 0),
		Color = PALETTE.grass,
		Material = Enum.Material.Grass,
		CanCollide = true,
	}, world)
	ground.Name = "ArenaFloor"

	local shore = block({
		Size = Vector3.new(map.arenaSize, 2.6, map.arenaSize),
		CFrame = CFrame.new(0, -2.9, 0),
		Color = PALETTE.grassDark,
		Material = Enum.Material.Grass,
		CanCollide = false,
	}, world)
	shore.Name = "ArenaUnderlay"

	disc(Vector3.new(0, 0.15, 0), map.plazaRadius * 2, 0.8, PALETTE.concrete, Enum.Material.Concrete, world).Name = "PlazaBase"
	disc(Vector3.new(0, 0.55, 0), map.plazaRadius * 2 - 3, 0.4, PALETTE.marble, Enum.Material.Marble, world).Name = "PlazaTop"
	local rim = disc(Vector3.new(0, 0.78, 0), map.plazaRadius * 2 + 1.4, 0.5, PALETTE.neonGold, Enum.Material.Neon, world, 0.15)
	rim.Name = "PlazaRim"

	-- Soft concentric rings, neon but thin, so the plaza centre reads as a hub.
	for i = 1, 3 do
		local ring = disc(
			Vector3.new(0, 0.6, 0),
			12 + i * 6,
			0.12,
			i % 2 == 0 and PALETTE.neonPink or PALETTE.neonCyan,
			Enum.Material.Neon,
			world,
			0.55
		)
		ring.Name = "PlazaRing"
	end

	buildFountain(world, Vector3.new(0, 0, 0))
	buildTitleSign(world, Vector3.new(0, 33, 0))

	-- Paths from each home deck to the plaza.
	for i = 0, Config.PAD_COUNT - 1 do
		local angle = math.rad(30 + i * 60)
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local midpoint = dir * ((map.baseRadius + map.plazaRadius) / 2)
		block({
			Size = Vector3.new(10, 0.35, map.baseRadius - map.plazaRadius + 4),
			CFrame = CFrame.lookAt(midpoint + Vector3.new(0, 0.35, 0), Vector3.new(0, 0.35, 0)),
			Color = PALETTE.deck,
			Material = Enum.Material.Concrete,
			CanCollide = false,
		}, world).Name = "Path"
	end

	-- Boundary: invisible colliders plus a visible neon curb.
	local half = map.arenaHalf - 1
	local walls = {
		{ Vector3.new(0, 18, -half), Vector3.new(6, 36, 2) },
		{ Vector3.new(0, 18, half), Vector3.new(6, 36, 2) },
		{ Vector3.new(-half, 18, 0), Vector3.new(2, 36, 6) },
		{ Vector3.new(half, 18, 0), Vector3.new(2, 36, 6) },
	}
	for _, wall in ipairs(walls) do
		block({
			Size = wall[2],
			CFrame = CFrame.new(wall[1]),
			Transparency = 1,
			CanCollide = true,
		}, world).Name = "Boundary"
	end
	for i = 0, 3 do
		local angle = i * math.pi / 2
		local lengthX = i % 2 == 0 and map.arenaSize or 0.6
		local lengthZ = i % 2 == 0 and 0.6 or map.arenaSize
		bar(
			Vector3.new(lengthX, 0.55, lengthZ),
			CFrame.new(Vector3.new(math.sin(angle) * half, 0.35, math.cos(angle) * half)),
			PALETTE.neonPink,
			world,
			0.1
		).Name = "BoundaryNeon"
	end

	buildWildDeck(world, Vector3.new(0, map.wildTop, -94))
	buildPortal(world, Vector3.new(0, 0, 94))
	buildShopKiosk(world, map.shopPos)
	buildVault(world, map.vaultPos)
	buildDock(world, map.dockCenter)
	buildHarbourPath(world, Vector3.new(0, 0, 0))

	-- Eight pillars ring the plaza, alternating accent colours.
	for i = 0, 7 do
		local angle = math.rad(22.5 + i * 45)
		local point = Vector3.new(math.sin(angle) * 37, 0, math.cos(angle) * 37)
		buildPillar(world, point, 13, i % 2 == 0 and PALETTE.neonGold or PALETTE.neonCyan)
	end

	buildArch(world, Vector3.new(0, 0, 70), 34, 18, PALETTE.neonPink)
	buildArch(world, Vector3.new(0, 0, -66), 34, 16, PALETTE.neonCyan)

	-- Trees on the outskirts, kept clear of the decks and the wild platform.
	local trees = {
		{ Vector3.new(-102, 0, -18), Color3.fromRGB(78, 190, 124), 1.0 },
		{ Vector3.new(104, 0, -26), Color3.fromRGB(88, 200, 138), 0.9 },
		{ Vector3.new(-96, 0, 72), Color3.fromRGB(255, 162, 206), 0.85 },
		{ Vector3.new(98, 0, 66), Color3.fromRGB(130, 224, 156), 1.0 },
		{ Vector3.new(-58, 0, 108), Color3.fromRGB(104, 210, 132), 0.8 },
		{ Vector3.new(56, 0, 110), Color3.fromRGB(255, 178, 108), 0.9 },
		{ Vector3.new(-112, 0, 108), Color3.fromRGB(120, 224, 164), 0.75 },
		{ Vector3.new(114, 0, 112), Color3.fromRGB(255, 152, 208), 0.8 },
		{ Vector3.new(-112, 0, -102), Color3.fromRGB(138, 232, 166), 0.9 },
		{ Vector3.new(112, 0, -104), Color3.fromRGB(255, 166, 212), 0.8 },
	}
	for _, tree in ipairs(trees) do
		buildTree(world, tree[1], tree[2], tree[3])
	end

	-- Lamp posts between the decks.
	for i = 0, Config.PAD_COUNT - 1 do
		local angle = math.rad(60 + i * 60)
		local base = Vector3.new(math.sin(angle) * 46, 0, math.cos(angle) * 46)
		block({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(9, 0.6, 0.6),
			CFrame = CFrame.new(base + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = PALETTE.metal,
			Material = Enum.Material.Metal,
			CanCollide = true,
		}, world).Name = "LampPost"
		local bulb = block({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.8, 1.8, 1.8),
			CFrame = CFrame.new(base + Vector3.new(0, 9.4, 0)),
			Color = i % 2 == 0 and PALETTE.neonGold or PALETTE.neonCyan,
			Material = Enum.Material.Neon,
			CanCollide = false,
		}, world)
		bulb.Name = "LampBulb"
		local light = Instance.new("PointLight")
		light.Color = bulb.Color
		light.Brightness = 1.3
		light.Range = 22
		light.Parent = bulb
	end

	-- Floating neon orbits. Effects.client.luau spins these locally, so the
	-- server never pays for the animation.
	local orbits = Instance.new("Folder")
	orbits.Name = "Orbits"
	orbits.Parent = world
	local orbitColors = { PALETTE.neonCyan, PALETTE.neonPink, PALETTE.neonGold }
	for ringIndex = 1, 3 do
		local ring = Instance.new("Model")
		ring.Name = "Orbit" .. ringIndex
		ring.Parent = orbits
		local radius = 34 + ringIndex * 14
		local height = 34 + ringIndex * 7
		for i = 1, 14 do
			local angle = i / 14 * math.pi * 2
			block({
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.4, 1.4, 1.4),
				CFrame = CFrame.new(Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)),
				Color = orbitColors[ringIndex],
				Material = Enum.Material.Neon,
				Transparency = 0.15,
				CanCollide = false,
			}, ring).Name = "OrbitDot"
		end
	end

	-- Spawn: the portal at the south end of the plaza.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CashRushSpawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(0, 2.5, 94)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Transparency = 0.2
	spawn.Color = PALETTE.neonCyan
	spawn.Material = Enum.Material.Neon
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = Workspace

	applyLighting()
	return world
end

-- The service entry point used by Main. Kept separate from buildStatic so the
-- command-bar path and the runtime path share one implementation without any
-- work happening when this module is merely required.
function MapService.build(services: any)
	return MapService.buildStatic(services)
end

function MapService.start(services: any)
	return MapService.buildStatic(services)
end

function MapService.stop()
	local world = Workspace:FindFirstChild("World")
	if world then
		world:Destroy()
	end
end

return MapService
