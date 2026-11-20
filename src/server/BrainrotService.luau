--!strict
-- BrainrotService — the life of every creature in the game.
--
-- Responsibilities, in order of the loop:
--   1. build a creature model out of primitives (one recipe per shape below),
--   2. keep a wild population wandering the wild deck,
--   3. lock a creature to the player who touches it (carried),
--   4. bank carried creatures onto the owner's pad (placed) and pay cash/sec,
--   5. hand creatures between players when BaseService allows a steal,
--   6. put creatures back in the wild when a carrier dies, is hit by a wave,
--      leaves the game or rebirths.
--
-- Shape recipes are data, not code: each recipe is a function that paints parts
-- through a small brush object, so adding a creature means one Config row and
-- one recipe. All tuning numbers come from Config; nothing here is magic.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BrainrotService = {}

local Config: any = nil
local Util: any = nil
local deps: any = nil

local WHITE = Color3.fromRGB(255, 255, 255)
local INK = Color3.fromRGB(20, 18, 28)
local DARK = Color3.fromRGB(38, 34, 50)

-- Runtime state. One table so stop() can wipe it in a single pass.
local world = {
	running = false,
	folder = nil :: Folder?,
	records = {} :: { any },
	wild = {} :: { any },
	carried = {} :: { [Player]: { any } },
	placed = {} :: { [Player]: { any } },
	byRoot = {} :: { [BasePart]: any },
	deathLinks = {} :: { [Player]: RBXScriptConnection },
	fullNoticeAt = {} :: { [Player]: number },
	incomeBank = {} :: { [Player]: number },
	incomeFloatAt = {} :: { [Player]: number },
	animWarned = false,
}

-- Dependency accessors -----------------------------------------------------
-- Every one of these tolerates a service that has not started yet, so a bad
-- boot order degrades instead of erroring.

local function upgrades(): any
	return deps and deps.UpgradeService
end

local function carryCapOf(player: Player): number
	local service = upgrades()
	if service then
		return service.getCarryCap(player)
	end
	return Config.MAX_CARRIED
end

local function padSlotsOf(player: Player): number
	local service = upgrades()
	if service then
		return service.getPadSlots(player)
	end
	return Config.MAX_BASE
end

local function multiplierOf(player: Player): number
	local rebirth = 1
	if deps and deps.PlayerService then
		rebirth = deps.PlayerService.getMultiplier(player)
	end
	local upgrade = 1
	local service = upgrades()
	if service then
		upgrade = service.getIncomeMultiplier(player)
	end
	return rebirth * upgrade
end

local function alive(player: Player?): boolean
	return player ~= nil and player.Parent ~= nil
end

-- A single creature's income after its one-time mutation roll. The service is
-- authoritative, with a local fallback so a boot-order problem never zeroes a
-- banked creature.
local function recordIncome(record: any): number
	if deps and deps.MutationService then
		return deps.MutationService.incomeOf(record)
	end
	local multiplier = record.mutation and record.mutation.multiplier or 1
	return record.rarity.value * multiplier
end

-- Primitive brush ----------------------------------------------------------

-- pos = { x, y, z, rotX?, rotY?, rotZ? } in studs and degrees.
local function pose(pos: { number }): CFrame
	return CFrame.new(pos[1], pos[2], pos[3])
		* CFrame.Angles(math.rad(pos[4] or 0), math.rad(pos[5] or 0), math.rad(pos[6] or 0))
end

-- The brush hides Instance.new bookkeeping from the shape recipes.
local function brush(model: Model)
	local b: any = {}

	function b.part(name: string, size: { number }, pos: { number }, color: Color3, material: Enum.Material?, shape: Enum.PartType?, alpha: number?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(size[1], size[2], size[3])
		p.CFrame = pose(pos)
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Shape = shape or Enum.PartType.Block
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Transparency = alpha or 0
		p.Parent = model
		return p
	end

	-- Two eye whites with neon pupils, both looking along +Z.
	function b.eyes(y: number, z: number, spread: number, size: number, pupil: Color3?)
		for _, side in ipairs({ -1, 1 }) do
			b.part("Eye", { size, size, size * 0.7 }, { side * spread, y, z }, WHITE, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			b.part("Pupil", { size * 0.42, size * 0.48, size * 0.35 }, { side * spread, y, z + size * 0.42 }, pupil or INK, Enum.Material.Neon, Enum.PartType.Ball)
		end
	end

	-- Angry eyebrows. tilt is in degrees and mirrored per side.
	function b.brows(y: number, z: number, spread: number, tilt: number)
		for _, side in ipairs({ -1, 1 }) do
			b.part("Brow", { 0.85, 0.16, 0.2 }, { side * spread, y, z, 0, 0, side * tilt }, Color3.fromRGB(35, 30, 46))
		end
	end

	function b.teeth(y: number, z: number, count: number, width: number, color: Color3?)
		local paint = color or WHITE
		for i = 1, count do
			local x = (i - (count + 1) / 2) * width
			b.part("Tooth", { width * 0.55, 0.35, 0.18 }, { x, y, z }, paint)
		end
	end

	return b
end

-- Shape recipes ------------------------------------------------------------
-- Each recipe paints one silhouette. Sizes are in studs around the creature's
-- origin (0,0,0); the hitbox is added later by buildCreature.

local RECIPES: { [string]: (any, Color3, Color3) -> () } = {}

RECIPES.toilet = function(b, body, accent)
	b.part("Bowl", { 2.8, 3.2, 3.2 }, { 0, -1.1, 0, 0, 0, 90 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("Rim", { 0.5, 3.6, 3.6 }, { 0, 0.25, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("Water", { 0.16, 2.6, 2.6 }, { 0, 0.48, 0, 0, 0, 90 }, Color3.fromRGB(60, 230, 255), Enum.Material.Neon, Enum.PartType.Cylinder, 0.25)
	b.part("Tank", { 2.4, 2.4, 1.2 }, { 0, 0.95, 1.45 }, body)
	b.part("Lid", { 2.7, 0.25, 1.5 }, { 0, 2.25, 1.45 }, body:Lerp(WHITE, 0.4))
	b.part("Flush", { 1.2, 0.2, 0.5 }, { 0, 2.42, 1.45 }, accent, Enum.Material.Neon)
	b.eyes(1.1, 2.12, 0.68, 0.62)
	b.brows(1.55, 2.16, 0.68, 12)
	b.part("Mouth", { 0.9, 0.16, 0.2 }, { 0, 0.55, 2.12 }, Color3.fromRGB(60, 30, 60))
	b.part("PlungerStick", { 2.8, 0.28, 0.28 }, { 2.3, 0.9, 0, 0, 0, -38 }, Color3.fromRGB(130, 80, 42), Enum.Material.Wood, Enum.PartType.Cylinder)
	b.part("PlungerCup", { 1.1, 1.1, 1.1 }, { 3.55, 0.05, 0 }, Color3.fromRGB(240, 70, 85), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Spin", { 0.18, 4.6, 4.6 }, { 0, -2.45, 0, 0, 0, 90 }, accent, Enum.Material.Neon, Enum.PartType.Cylinder, 0.4)
	for i = 0, 2 do
		b.part("Prop", { 0.22, 0.22, 2.5 }, { 0, 3.55, 0, 0, i * 60, 0 }, accent, Enum.Material.Neon)
	end
	b.part("PropHub", { 0.7, 0.7, 0.7 }, { 0, 3.55, 0 }, body, Enum.Material.Metal, Enum.PartType.Ball)
end

RECIPES.taco = function(b, body, accent)
	b.part("ShellL", { 0.45, 3.5, 3.4 }, { -1.15, 0, 0, 0, 0, 16 }, body)
	b.part("ShellR", { 0.45, 3.5, 3.4 }, { 1.15, 0, 0, 0, 0, -16 }, body)
	b.part("ShellBottom", { 2.4, 0.6, 3.2 }, { 0, -1.55, 0 }, body:Lerp(Color3.fromRGB(160, 100, 20), 0.2))
	b.part("Lettuce1", { 1.0, 1.0, 1.0 }, { -0.7, 1.0, 0.4 }, Color3.fromRGB(80, 205, 90), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Lettuce2", { 1.1, 1.1, 1.1 }, { 0.1, 1.2, 0.1 }, Color3.fromRGB(55, 180, 75), Enum.Material.Grass, Enum.PartType.Ball)
	b.part("Lettuce3", { 0.9, 0.9, 0.9 }, { 0.8, 1.0, 0.5 }, Color3.fromRGB(105, 220, 105), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Tomato1", { 0.55, 0.55, 0.55 }, { -0.2, 1.55, 0.9 }, Color3.fromRGB(235, 70, 60))
	b.part("Tomato2", { 0.5, 0.5, 0.5 }, { 0.6, 1.45, 0.8 }, Color3.fromRGB(235, 70, 60))
	for i = -1, 1 do
		b.part("Cheese", { 1.5, 0.16, 0.35 }, { i * 0.8, 1.65, -0.3, 0, 18, 0 }, Color3.fromRGB(255, 220, 90))
	end
	b.part("Head", { 1.6, 1.4, 1.5 }, { 0, 2.55, 0.7 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Snout", { 1.0, 0.7, 1.0 }, { 0, 2.35, 1.6 }, accent:Lerp(WHITE, 0.1))
	b.eyes(2.75, 1.42, 0.38, 0.42)
	b.brows(3.0, 1.45, 0.38, -10)
	b.part("Nostril1", { 0.16, 0.16, 0.16 }, { 0.2, 2.45, 2.1 }, Color3.fromRGB(40, 90, 40))
	b.part("Nostril2", { 0.16, 0.16, 0.16 }, { -0.2, 2.45, 2.1 }, Color3.fromRGB(40, 90, 40))
	b.teeth(2.18, 2.12, 4, 0.22)
	for i = 1, 3 do
		b.part("Spike", { 0.45, 0.55, 0.45 }, { -0.6 + i * 0.5, 3.15, 0.4, 0, 45, 0 }, Color3.fromRGB(255, 150, 60), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	b.part("ArmL", { 0.18, 0.8, 0.18 }, { -1.35, 1.7, 0.4, 0, 0, -35 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("ArmR", { 0.18, 0.8, 0.18 }, { 1.35, 1.7, 0.4, 0, 0, 35 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
end

RECIPES.phone = function(b, body, accent)
	b.part("PhoneBody", { 2.2, 3.8, 0.75 }, { 0, 0, 0 }, body, Enum.Material.Metal)
	b.part("Screen", { 1.8, 3.0, 0.12 }, { 0, 0.2, 0.44 }, accent, Enum.Material.Neon, Enum.PartType.Block, 0.1)
	b.part("HomeButton", { 0.42, 0.42, 0.14 }, { 0, -1.55, 0.44 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
	b.part("Camera", { 0.28, 0.28, 0.28 }, { 0, 1.63, 0.4 }, DARK, Enum.Material.Neon, Enum.PartType.Ball)
	b.part("Antenna", { 1.4, 0.13, 0.13 }, { 0.7, 2.25, 0, 0, 0, -32 }, Color3.fromRGB(210, 215, 230), Enum.Material.Metal, Enum.PartType.Cylinder)
	b.eyes(0.65, 0.52, 0.48, 0.42, accent)
	for _, side in ipairs({ -1, 1 }) do
		b.part("Arm", { 0.2, 1.1, 0.2 }, { side * 1.45, -0.3, 0, 0, 0, side * 28 }, body, Enum.Material.Metal, Enum.PartType.Cylinder)
		b.part("Leg", { 0.22, 1.0, 0.22 }, { side * 0.65, -2.25, 0.05 }, body, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	b.part("Battery", { 0.7, 0.22, 0.2 }, { -0.55, 1.55, 0.1 }, accent, Enum.Material.Neon)
end

RECIPES.duck = function(b, body, accent)
	b.part("DuckBody", { 2.9, 2.5, 3.0 }, { 0, -0.6, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("DuckHead", { 2.1, 2.0, 2.0 }, { 0, 1.55, 0.55 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Beak", { 1.3, 0.55, 1.1 }, { 0, 1.05, 1.7 }, accent)
	b.part("BeakLip", { 1.25, 0.16, 1.0 }, { 0, 0.92, 1.75 }, accent:Lerp(Color3.fromRGB(180, 100, 20), 0.2))
	b.eyes(2.2, 1.25, 0.48, 0.42)
	b.brows(2.55, 1.3, 0.48, 9)
	for _, side in ipairs({ -1, 1 }) do
		b.part("Wing", { 0.55, 1.5, 2.0 }, { side * 1.5, -0.5, -0.1, 0, 0, side * 18 }, body:Lerp(WHITE, 0.15))
		b.part("Foot", { 1.1, 0.22, 1.4 }, { side * 0.75, -2.0, 0.55 }, accent)
	end
	b.part("Tail", { 0.9, 0.8, 0.7 }, { 0, 0.3, -1.5, -28, 0, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
end

RECIPES.cheese = function(b, body, accent)
	b.part("CheeseWedge", { 3.4, 2.8, 3.0 }, { 0, -0.3, 0 }, body)
	b.part("CheeseRind", { 3.5, 2.9, 0.35 }, { 0, -0.3, -1.45 }, accent)
	local holes = {
		{ -0.9, 0.3, 1.52, 0.72 },
		{ 0.9, -0.45, 1.52, 0.55 },
		{ 1.65, 0.7, 0.2, 0.48 },
		{ -1.65, -0.7, -0.3, 0.52 },
	}
	for _, hole in ipairs(holes) do
		b.part("Hole", { hole[4], hole[4], 0.3 }, { hole[1], hole[2], hole[3] }, Color3.fromRGB(205, 150, 35), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	b.eyes(0.65, 1.52, 0.62, 0.52)
	b.brows(1.1, 1.55, 0.62, -6)
	b.part("Mouth", { 1.0, 0.18, 0.18 }, { 0, -0.25, 1.52 }, Color3.fromRGB(120, 80, 20))
	for _, side in ipairs({ -1, 1 }) do
		b.part("CheeseArm", { 0.22, 1.0, 0.22 }, { side * 1.85, -0.5, 0.3, 0, 0, side * 35 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		b.part("CheeseLeg", { 0.35, 0.7, 0.35 }, { side * 0.9, -2.2, 0.2 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
end

RECIPES.sock = function(b, body, accent)
	b.part("SockLeg", { 1.9, 3.2, 1.6 }, { 0, 0.4, 0 }, body, Enum.Material.Fabric)
	b.part("SockFoot", { 1.9, 1.4, 3.0 }, { 0, -1.35, 0.9 }, body, Enum.Material.Fabric)
	b.part("SockToe", { 1.95, 1.3, 0.8 }, { 0, -1.35, 2.55 }, body:Lerp(WHITE, 0.25), Enum.Material.Fabric, Enum.PartType.Ball)
	b.part("Cuff", { 2.05, 0.55, 1.75 }, { 0, 2.1, 0 }, accent)
	for i = 0, 2 do
		b.part("Stripe", { 1.95, 0.2, 1.65 }, { 0, 1.5 - i * 0.35, 0 }, accent, Enum.Material.Neon)
	end
	b.eyes(0.8, 1.0, 0.5, 0.46)
	b.brows(1.2, 1.05, 0.5, 12)
	b.part("Mouth", { 0.9, 0.18, 0.16 }, { 0, 0.25, 1.02 }, Color3.fromRGB(80, 30, 70))
	b.part("Heel", { 1.7, 0.3, 0.9 }, { 0, -2.0, 0.05 }, accent)
end

RECIPES.fridge = function(b, body, accent)
	b.part("FridgeBody", { 2.9, 4.0, 1.8 }, { 0, 0, 0 }, body, Enum.Material.Metal)
	b.part("DoorSplit", { 2.9, 0.1, 0.08 }, { 0, 0.45, 0.93 }, Color3.fromRGB(80, 90, 105), Enum.Material.Metal)
	for _, side in ipairs({ -1.25, 1.25 }) do
		b.part("Handle", { 2.2, 0.2, 0.2 }, { side, 0.1, 1.05, 0, 0, 90 }, Color3.fromRGB(140, 160, 180), Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	b.part("Magnet1", { 0.35, 0.35, 0.12 }, { -0.7, 1.2, 0.95 }, Color3.fromRGB(255, 110, 150))
	b.part("Magnet2", { 0.35, 0.35, 0.12 }, { -0.2, 1.45, 0.95 }, Color3.fromRGB(90, 200, 255))
	b.part("Magnet3", { 0.35, 0.35, 0.12 }, { 0.3, 1.1, 0.95 }, Color3.fromRGB(255, 215, 90))
	b.part("RhinoHead", { 1.9, 1.5, 1.7 }, { 0, 2.65, 0.3 }, Color3.fromRGB(150, 156, 170), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Horn", { 1.2, 0.42, 0.42 }, { 0, 2.95, 1.25, 0, 0, 90 }, Color3.fromRGB(240, 226, 190), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.eyes(2.78, 1.15, 0.48, 0.45)
	b.brows(3.02, 1.2, 0.48, 8)
	b.part("EarL", { 0.55, 0.4, 0.25 }, { -0.65, 3.4, 0.2, 0, 0, 18 }, Color3.fromRGB(135, 140, 155))
	b.part("EarR", { 0.55, 0.4, 0.25 }, { 0.65, 3.4, 0.2, 0, 0, -18 }, Color3.fromRGB(135, 140, 155))
	b.part("Nostril1", { 0.14, 0.14, 0.14 }, { 0.2, 2.55, 1.35 }, Color3.fromRGB(70, 70, 85))
	b.part("Nostril2", { 0.14, 0.14, 0.14 }, { -0.2, 2.55, 1.35 }, Color3.fromRGB(70, 70, 85))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			b.part("Leg", { 0.55, 0.7, 0.55 }, { sx * 0.95, -2.35, sz * 0.55 }, Color3.fromRGB(130, 136, 150), Enum.Material.Metal)
		end
	end
	b.part("Milk", { 0.8, 1.1, 0.8 }, { 1.0, 2.75, -0.2 }, Color3.fromRGB(250, 250, 250))
	b.part("MilkTop", { 0.85, 0.25, 0.85 }, { 1.0, 3.35, -0.2 }, accent, Enum.Material.Neon)
end

RECIPES.shake = function(b, body, accent)
	b.part("Cup", { 3.2, 3.4, 3.4 }, { 0, -0.5, 0, 0, 0, 90 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("Lid", { 0.45, 3.7, 3.7 }, { 0, 1.25, 0, 0, 0, 90 }, body:Lerp(Color3.fromRGB(230, 160, 255), 0.35), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("Dome", { 3.2, 1.8, 3.2 }, { 0, 1.7, 0 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball, 0.25)
	b.part("Straw", { 2.6, 0.32, 0.32 }, { 0.65, 3.15, 0, 0, 0, -18 }, Color3.fromRGB(255, 110, 220), Enum.Material.Neon, Enum.PartType.Cylinder)
	b.part("StrawTop", { 0.42, 0.42, 0.42 }, { 1.05, 4.35, 0 }, Color3.fromRGB(255, 110, 220), Enum.Material.Neon, Enum.PartType.Ball)
	b.eyes(0.35, 1.65, 0.62, 0.58)
	b.brows(0.85, 1.7, 0.62, -18)
	b.part("Mouth", { 1.3, 0.22, 0.2 }, { 0, -0.15, 1.72 }, Color3.fromRGB(45, 20, 60))
	b.teeth(-0.02, 1.78, 4, 0.3)
	b.part("ArmL", { 0.22, 1.1, 0.22 }, { -1.85, -0.5, 0.2, 0, 0, -55 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("ArmR", { 0.22, 1.1, 0.22 }, { 1.85, -0.4, 0.2, 0, 0, 55 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("HandL", { 0.65, 0.65, 0.65 }, { -2.35, 0.2, 0.2 }, Color3.fromRGB(255, 240, 250), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("HandR", { 0.65, 0.65, 0.65 }, { 2.35, 0.3, 0.2 }, Color3.fromRGB(255, 240, 250), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for i = -1, 1 do
		b.part("Drip", { 0.35, 0.55, 0.35 }, { i * 0.75, -2.25, 1.1 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
	end
	b.part("Cherry", { 0.7, 0.7, 0.7 }, { -0.6, 2.45, 0 }, Color3.fromRGB(255, 60, 90), Enum.Material.Neon, Enum.PartType.Ball)
end

RECIPES.pizza = function(b, body, accent)
	b.part("PizzaBase", { 1.1, 4.6, 4.6 }, { 0, 0, 0, 0, 0, 90 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("Crust", { 1.25, 5.0, 5.0 }, { 0, -0.2, 0, 0, 0, 90 }, body:Lerp(Color3.fromRGB(190, 120, 30), 0.35), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("Sauce", { 0.2, 4.1, 4.1 }, { 0, 0.48, 0, 0, 0, 90 }, Color3.fromRGB(225, 80, 45), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2
		b.part("Pepperoni", { 0.25, 0.9, 0.9 }, { math.cos(angle) * 1.35, 0.68, math.sin(angle) * 1.35, 0, 0, 90 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
	b.part("CheeseSlice", { 0.18, 2.2, 2.2 }, { 0, 0.75, 0, 0, 0, 90 }, Color3.fromRGB(255, 220, 110), Enum.Material.Neon, Enum.PartType.Cylinder, 0.25)
	b.eyes(0.5, 1.75, 0.45, 0.44)
	b.brows(0.95, 1.8, 0.45, -8)
	b.part("PizzaArmL", { 0.22, 1.2, 0.22 }, { -1.95, 0.1, 0, 0, 0, -52 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("PizzaArmR", { 0.22, 1.2, 0.22 }, { 1.95, 0.1, 0, 0, 0, 52 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
end

RECIPES.worm = function(b, body, accent)
	for i = 1, 5 do
		local z = 1.4 - i * 0.8
		local size = 1.9 - i * 0.16
		local paint = i % 2 == 0 and body or body:Lerp(WHITE, 0.18)
		b.part("Segment", { size, size, size }, { math.sin(i * 0.9) * 0.35, -0.3 + math.sin(i) * 0.15, z }, paint, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	b.part("WormHead", { 2.1, 2.1, 2.1 }, { 0, 0.35, 2.2 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.eyes(0.85, 3.05, 0.52, 0.5)
	b.brows(1.35, 3.08, 0.52, 16)
	b.part("Mouth", { 1.1, 0.2, 0.2 }, { 0, 0.05, 3.12 }, Color3.fromRGB(80, 30, 70))
	b.part("TinyHat", { 1.3, 0.2, 1.3 }, { 0, 1.6, 2.2, 0, 0, 90 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("TinyHatTop", { 0.8, 0.6, 0.8 }, { 0, 1.95, 2.2, 0, 0, 90 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("WormTail", { 1.1, 1.1, 1.1 }, { 0.2, -0.2, -2.8 }, accent, Enum.Material.Neon, Enum.PartType.Ball, 0.15)
end

RECIPES.donut = function(b, body, accent)
	for i = 1, 12 do
		local angle = i / 12 * math.pi * 2
		b.part("DoughRing", { 1.5, 1.5, 1.5 }, { math.cos(angle) * 1.95, 0, math.sin(angle) * 1.95 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	b.part("FrostingTop", { 0.5, 4.4, 4.4 }, { 0, 0.32, 0, 0, 0, 90 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("FrostingHole", { 1.5, 0.55, 0.55 }, { 0, 0.35, 0, 0, 0, 90 }, Color3.fromRGB(55, 35, 45), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2
		local sprinkle = i % 2 == 0 and Color3.fromRGB(90, 230, 255) or WHITE
		b.part("Sprinkle", { 0.16, 0.16, 0.65 }, { math.cos(angle) * 2.5, 0.6, math.sin(angle) * 2.5, 0, i * 45, 0 }, sprinkle, Enum.Material.Neon)
	end
	b.eyes(0.6, 2.5, 0.52, 0.48)
	b.brows(1.05, 2.55, 0.52, 10)
	b.part("Mouth", { 0.9, 0.18, 0.18 }, { 0, 0.05, 2.62 }, Color3.fromRGB(90, 30, 60))
end

RECIPES.shark = function(b, body, accent)
	b.part("Body", { 3.6, 2.7, 2.7 }, { 0, 0, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Belly", { 2.8, 1.6, 1.6 }, { 0.1, -0.45, 0.55 }, Color3.fromRGB(245, 250, 255), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Snout", { 1.7, 1.1, 1.1 }, { 2.0, 0.05, 0.15, 0, 0, 90 }, body:Lerp(WHITE, 0.15), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("Nose", { 0.85, 0.85, 0.85 }, { 2.9, 0.05, 0.15 }, body:Lerp(WHITE, 0.2), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("TailA", { 0.25, 1.8, 1.0 }, { -2.0, 0.5, 0, 0, 0, -22 }, body)
	b.part("TailB", { 0.25, 1.8, 1.0 }, { -2.0, -0.5, 0, 0, 0, 22 }, body)
	b.part("Dorsal", { 0.3, 1.9, 1.2 }, { 0, 1.85, 0, 0, 0, -8 }, body)
	b.part("FinL", { 1.3, 0.25, 0.9 }, { -0.2, -0.2, 1.8, 0, 22, -25 }, body)
	b.part("FinR", { 1.3, 0.25, 0.9 }, { -0.2, -0.2, -1.8, 0, -22, -25 }, body)
	b.eyes(0.35, 1.15, 0.55, 0.4)
	b.brows(0.8, 1.2, 0.55, 14)
	b.part("Mouth", { 1.2, 0.16, 0.16 }, { 2.05, -0.55, 0.3, 0, 0, 6 }, Color3.fromRGB(90, 30, 60))
	b.teeth(-0.4, 1.85, 5, 0.22)
	-- Three sneakers, zero feet.
	for i = 0, 2 do
		b.part("Sneaker", { 0.75, 0.45, 1.35 }, { -0.9 + i * 0.95, -1.55, 0.75 }, accent, Enum.Material.SmoothPlastic)
		b.part("Sole", { 0.8, 0.16, 1.4 }, { -0.9 + i * 0.95, -1.8, 0.75 }, Color3.fromRGB(235, 235, 245), Enum.Material.SmoothPlastic)
	end
	b.part("ShoeLace", { 0.55, 0.1, 0.2 }, { 0, -1.35, 1.05 }, Color3.fromRGB(255, 90, 120), Enum.Material.Neon)
end

RECIPES.bomb = function(b, body, accent)
	b.part("BombShell", { 3.4, 3.4, 3.4 }, { 0, -0.2, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("BombCap", { 1.2, 0.6, 1.2 }, { 0, 1.75, 0, 0, 0, 90 }, Color3.fromRGB(70, 72, 92), Enum.Material.Metal, Enum.PartType.Cylinder)
	b.part("Fuse", { 1.5, 0.16, 0.16 }, { 0.35, 2.55, 0, 0, 0, 28 }, Color3.fromRGB(210, 190, 150), Enum.Material.Fabric, Enum.PartType.Cylinder)
	b.part("Spark", { 0.75, 0.75, 0.75 }, { 0.7, 3.2, 0 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
	b.part("SparkRing", { 0.2, 1.5, 1.5 }, { 0.7, 3.2, 0, 0, 0, 90 }, accent, Enum.Material.Neon, Enum.PartType.Cylinder, 0.4)
	b.eyes(0.2, 1.68, 0.6, 0.52)
	b.brows(0.72, 1.7, 0.6, -14)
	b.part("Mouth", { 1.1, 0.2, 0.2 }, { 0, -0.45, 1.72 }, Color3.fromRGB(30, 20, 40))
	b.teeth(-0.3, 1.76, 5, 0.26)
	for _, side in ipairs({ -1, 1 }) do
		b.part("BombArm", { 0.24, 1.2, 0.24 }, { side * 1.85, -0.2, 0, 0, 0, side * 42 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		b.part("BombLeg", { 0.5, 0.9, 0.5 }, { side * 0.85, -2.15, 0.1 }, Color3.fromRGB(70, 72, 92), Enum.Material.Metal)
	end
end

RECIPES.crab = function(b, body, accent)
	b.part("Shell", { 4.0, 1.9, 3.2 }, { 0, 0, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("ShellTop", { 3.2, 1.0, 2.4 }, { 0, 0.85, -0.2 }, body:Lerp(WHITE, 0.2), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for _, side in ipairs({ -1, 1 }) do
		-- Eye stalks.
		b.part("Stalk", { 0.9, 0.22, 0.22 }, { side * 0.75, 1.35, 0.9, 0, 0, 90 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		b.part("CrabEye", { 0.55, 0.55, 0.55 }, { side * 0.75, 1.85, 0.9 }, WHITE, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		b.part("CrabPupil", { 0.24, 0.26, 0.22 }, { side * 0.75, 1.85, 1.16 }, INK, Enum.Material.Neon, Enum.PartType.Ball)
		-- Claws.
		b.part("ClawArm", { 1.3, 0.3, 0.3 }, { side * 2.35, 0.5, 0.6, 0, 0, side * 22 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		b.part("Claw", { 1.0, 0.75, 0.7 }, { side * 3.1, 0.75, 0.9 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		b.part("ClawTip", { 0.45, 0.5, 0.45 }, { side * 3.45, 1.15, 1.0 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
		for leg = 1, 3 do
			b.part("Leg", { 1.2, 0.2, 0.2 }, { side * 1.9, -0.65, -0.9 + leg * 0.7, 0, 0, side * 62 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		end
	end
	b.brows(1.0, 1.25, 0.5, 18)
	b.part("CrabMouth", { 1.0, 0.2, 0.2 }, { 0, -0.15, 1.55 }, Color3.fromRGB(120, 40, 40))
	b.teeth(-0.05, 1.6, 4, 0.24, accent)
end

RECIPES.balloon = function(b, body, accent)
	b.part("Balloon", { 3.6, 4.0, 3.6 }, { 0, 0.9, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("BalloonKnot", { 0.5, 0.6, 0.5 }, { 0, -1.2, 0 }, body:Lerp(WHITE, 0.3), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("String", { 3.2, 0.08, 0.08 }, { 0, -3.0, 0, 0, 0, 90 }, Color3.fromRGB(235, 235, 245), Enum.Material.Fabric, Enum.PartType.Cylinder)
	b.part("Basket", { 1.5, 1.1, 1.5 }, { 0, -4.6, 0 }, Color3.fromRGB(196, 146, 84), Enum.Material.Wood)
	b.part("BasketRim", { 1.7, 0.2, 1.7 }, { 0, -4.05, 0 }, accent, Enum.Material.Neon)
	b.part("Highlight", { 1.2, 1.4, 0.35 }, { -0.9, 1.9, 1.35 }, WHITE, Enum.Material.SmoothPlastic, Enum.PartType.Ball, 0.45)
	b.eyes(1.1, 1.75, 0.62, 0.54)
	b.brows(1.65, 1.8, 0.62, -10)
	b.part("Mouth", { 1.1, 0.2, 0.2 }, { 0, 0.25, 1.82 }, Color3.fromRGB(140, 40, 90))
	for _, side in ipairs({ -1, 1 }) do
		b.part("BalloonArm", { 0.22, 1.3, 0.22 }, { side * 2.0, -0.1, 0, 0, 0, side * 48 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		b.part("BalloonHand", { 0.6, 0.6, 0.6 }, { side * 2.5, -0.85, 0 }, body:Lerp(WHITE, 0.4), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
end

RECIPES.cactus = function(b, body, accent)
	b.part("CactusBody", { 2.4, 4.2, 2.4 }, { 0, 0.4, 0 }, body, Enum.Material.Grass)
	b.part("CactusTop", { 2.0, 1.2, 2.0 }, { 0, 2.7, 0 }, body, Enum.Material.Grass, Enum.PartType.Ball)
	for _, side in ipairs({ -1, 1 }) do
		b.part("CactusArm", { 1.6, 0.9, 0.9 }, { side * 1.7, 0.9, 0, 0, 0, side * 18 }, body, Enum.Material.Grass)
		b.part("CactusArmTop", { 0.9, 1.3, 0.9 }, { side * 2.3, 1.6, 0 }, body, Enum.Material.Grass)
	end
	for row = 0, 3 do
		for _, side in ipairs({ -1, 1 }) do
			b.part("Spine", { 0.5, 0.1, 0.1 }, { side * 1.35, -1.0 + row * 0.9, 0.4 }, Color3.fromRGB(235, 250, 225), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		end
	end
	b.part("Flower", { 1.1, 1.1, 1.1 }, { 0, 3.5, 0 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
	b.part("FlowerCore", { 0.5, 0.5, 0.5 }, { 0, 3.5, 0.5 }, Color3.fromRGB(255, 245, 180), Enum.Material.Neon, Enum.PartType.Ball)
	b.eyes(1.3, 1.25, 0.5, 0.46)
	b.brows(1.75, 1.3, 0.5, 8)
	b.part("Mouth", { 0.8, 0.18, 0.18 }, { 0, 0.55, 1.27 }, Color3.fromRGB(70, 60, 30))
	b.part("Pot", { 2.6, 1.2, 2.6 }, { 0, -2.0, 0 }, Color3.fromRGB(206, 132, 88), Enum.Material.Concrete)
	b.part("PotRim", { 2.8, 0.25, 2.8 }, { 0, -1.45, 0 }, Color3.fromRGB(180, 110, 70), Enum.Material.Concrete)
end

RECIPES.ghost = function(b, body, accent)
	b.part("GhostBody", { 3.2, 3.4, 3.2 }, { 0, 0.4, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball, 0.15)
	b.part("GhostSkirt", { 3.0, 1.8, 3.0 }, { 0, -1.5, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball, 0.3)
	for i = 0, 3 do
		local angle = i / 4 * math.pi * 2
		b.part("Wisp", { 0.9, 1.4, 0.9 }, { math.cos(angle) * 1.1, -2.5, math.sin(angle) * 1.1 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball, 0.45)
	end
	b.eyes(0.9, 1.55, 0.6, 0.55, accent)
	b.brows(1.35, 1.6, 0.6, -12)
	b.part("GhostMouth", { 1.0, 0.55, 0.2 }, { 0, 0.05, 1.6 }, Color3.fromRGB(60, 40, 90), Enum.Material.Neon)
	for _, side in ipairs({ -1, 1 }) do
		b.part("GhostArm", { 0.7, 1.4, 0.7 }, { side * 1.85, 0.2, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball, 0.25)
	end
	b.part("GhostAura", { 0.14, 5.2, 5.2 }, { 0, -2.9, 0, 0, 0, 90 }, accent, Enum.Material.Neon, Enum.PartType.Cylinder, 0.7)
end

RECIPES.skull = function(b, body, accent)
	b.part("Cranium", { 3.0, 2.8, 2.8 }, { 0, 0.9, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Jaw", { 2.4, 1.2, 2.2 }, { 0, -1.05, 0.15 }, body:Lerp(Color3.fromRGB(210, 205, 195), 0.3), Enum.Material.SmoothPlastic)
	b.part("CheekL", { 0.5, 1.1, 0.5 }, { -1.2, -0.35, 1.0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("CheekR", { 0.5, 1.1, 0.5 }, { 1.2, -0.35, 1.0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for _, side in ipairs({ -1, 1 }) do
		b.part("Socket", { 1.0, 1.0, 0.35 }, { side * 0.68, 0.95, 1.3 }, Color3.fromRGB(28, 24, 34), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		b.part("SkullPupil", { 0.42, 0.42, 0.3 }, { side * 0.68, 0.95, 1.55 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
		b.part("Horn", { 1.3, 0.42, 0.42 }, { side * 1.35, 2.15, 0, 0, 0, side * 42 }, Color3.fromRGB(240, 235, 220), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
	b.brows(1.55, 1.4, 0.68, 16)
	b.part("NoseHole", { 0.35, 0.5, 0.25 }, { 0, 0.15, 1.42 }, Color3.fromRGB(40, 34, 46), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.teeth(-0.75, 1.18, 6, 0.34, Color3.fromRGB(250, 248, 240))
	for _, side in ipairs({ -1, 1 }) do
		b.part("SkullArm", { 0.22, 1.2, 0.22 }, { side * 1.75, -0.6, 0.2, 0, 0, side * 26 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
	b.part("SkullGem", { 0.6, 0.6, 0.6 }, { 0, 2.5, 0 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
end

RECIPES.robot = function(b, body, accent)
	b.part("RobotBody", { 2.8, 2.7, 2.2 }, { 0, -0.45, 0 }, body, Enum.Material.Metal)
	b.part("RobotHead", { 2.2, 1.9, 2.0 }, { 0, 1.45, 0 }, body:Lerp(WHITE, 0.2), Enum.Material.Metal)
	b.part("Visor", { 1.8, 0.6, 0.18 }, { 0, 1.55, 1.02 }, Color3.fromRGB(20, 25, 35), Enum.Material.Neon)
	for _, side in ipairs({ -1, 1 }) do
		b.part("RoboEye", { 0.38, 0.38, 0.2 }, { side * 0.5, 1.55, 1.13 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
		b.part("RoboArm", { 0.35, 1.6, 0.35 }, { side * 1.7, -0.35, 0, 0, 0, side * 12 }, body, Enum.Material.Metal, Enum.PartType.Cylinder)
		b.part("RoboClaw", { 0.8, 0.35, 0.5 }, { side * 1.9, -1.2, 0.25 }, accent, Enum.Material.Metal)
		b.part("RoboLeg", { 0.55, 1.1, 0.8 }, { side * 0.75, -2.4, 0 }, Color3.fromRGB(55, 60, 78), Enum.Material.Metal)
	end
	b.part("ChestCore", { 0.25, 0.8, 0.8 }, { 0, -0.4, 1.15, 0, 0, 90 }, accent, Enum.Material.Neon, Enum.PartType.Cylinder)
	b.part("Antenna", { 1.1, 0.15, 0.15 }, { 0, 2.9, 0, 0, 0, 90 }, body, Enum.Material.Metal, Enum.PartType.Cylinder)
	b.part("AntennaBall", { 0.5, 0.5, 0.5 }, { 0, 3.45, 0 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
	b.part("MouthGrill", { 1.1, 0.18, 0.12 }, { 0, 0.85, 1.05 }, Color3.fromRGB(55, 60, 78), Enum.Material.Metal)
end

RECIPES.banana = function(b, body, accent)
	b.part("Body", { 2.5, 1.8, 1.8 }, { 0, 0, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("BodyFront", { 1.9, 1.4, 1.4 }, { 1.45, 0.45, 0, 0, 0, 20 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("BodyBack", { 1.7, 1.3, 1.3 }, { -1.4, -0.35, 0 }, body:Lerp(Color3.fromRGB(210, 180, 40), 0.2), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Snout", { 1.3, 0.7, 0.7 }, { 2.55, 0.55, 0, 0, 0, 90 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("Nose", { 0.6, 0.6, 0.6 }, { 3.2, 0.55, 0 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Dorsal", { 0.25, 1.4, 0.9 }, { 0.4, 1.45, 0, 0, 0, -24 }, accent)
	b.part("TailTop", { 0.25, 1.1, 0.85 }, { -2.2, 0.45, 0, 0, 0, 28 }, accent)
	b.part("TailBottom", { 0.25, 1.1, 0.85 }, { -2.2, -0.3, 0, 0, 0, -28 }, accent)
	for i = 0, 2 do
		b.part("Peel", { 0.25, 1.3, 0.8 }, { -0.8 + i * 0.8, -1.45, 0.7, 0, i * 35, -12 }, body:Lerp(Color3.fromRGB(255, 240, 140), 0.4))
	end
	b.part("FinL", { 1.0, 0.22, 0.8 }, { 0.2, -0.4, 1.55, 0, 22, -22 }, accent)
	b.part("FinR", { 1.0, 0.22, 0.8 }, { 0.2, -0.4, -1.55, 0, -22, -22 }, accent)
	for _, side in ipairs({ -1, 1 }) do
		b.part("Eye", { 0.6, 0.6, 0.6 }, { 1.1, 0.6, side * 0.9 }, WHITE, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		b.part("Pupil", { 0.28, 0.32, 0.26 }, { 1.1, 0.6, side * 1.16 }, INK, Enum.Material.Neon, Enum.PartType.Ball)
		b.part("Shade", { 1.0, 0.5, 0.14 }, { 1.2, 0.66, side * 1.2 }, Color3.fromRGB(15, 15, 22))
	end
	b.part("ShadeBridge", { 0.35, 0.16, 0.16 }, { 1.2, 0.66, 0 }, Color3.fromRGB(255, 205, 60), Enum.Material.Neon)
	for i = 1, 6 do
		b.part("Chain", { 0.34, 0.34, 0.34 }, { 0.2 + i * 0.12, 0.75 - i * 0.04, 1.2 }, Color3.fromRGB(255, 205, 60), Enum.Material.Neon, Enum.PartType.Ball)
	end
	for i = 0, 2 do
		local tilt = i % 2 == 0 and 18 or -18
		b.part("Crown", { 0.35, 0.7, 0.35 }, { -0.3 + i * 0.3, 2.1, 0, 0, 0, tilt }, Color3.fromRGB(255, 215, 70), Enum.Material.Neon)
	end
	b.part("CrownBand", { 1.3, 0.2, 0.3 }, { 0, 1.85, 0 }, Color3.fromRGB(255, 215, 70), Enum.Material.Neon)
end

RECIPES.dragon = function(b, body, accent)
	b.part("DragonBody", { 2.9, 2.2, 3.8 }, { 0, -0.2, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("DragonHead", { 2.4, 2.0, 2.3 }, { 0, 1.55, 1.35 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("DragonSnout", { 1.5, 0.9, 1.2 }, { 0, 1.05, 2.55 }, body:Lerp(WHITE, 0.12), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for _, side in ipairs({ -1, 1 }) do
		b.part("DragonWing", { 0.35, 2.6, 3.4 }, { side * 2.0, 1.1, -0.8, 0, 0, side * 28 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Block, 0.15)
		b.part("DragonWingTip", { 0.3, 1.0, 2.0 }, { side * 3.0, 2.0, -1.0, 0, 0, side * 52 }, accent, Enum.Material.Neon, Enum.PartType.Block, 0.25)
		b.part("DragonHorn", { 1.0, 0.32, 0.32 }, { side * 0.85, 2.65, 1.1, 0, 0, side * 45 }, Color3.fromRGB(255, 240, 200), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		b.part("DragonLeg", { 0.6, 1.2, 0.7 }, { side * 1.05, -1.85, 0.8 }, body)
		b.part("DragonClaw", { 0.7, 0.3, 0.9 }, { side * 1.05, -2.5, 1.25 }, Color3.fromRGB(255, 240, 200))
	end
	b.eyes(1.8, 2.5, 0.48, 0.42, accent)
	b.part("DragonMouth", { 1.1, 0.2, 0.15 }, { 0, 0.9, 3.15 }, Color3.fromRGB(90, 25, 50))
	for i = 1, 4 do
		b.part("BackSpike", { 0.55 - i * 0.07, 0.7, 0.55 }, { 0, 0.9, -0.2 - i * 0.55 }, accent, Enum.Material.Neon)
	end
	b.part("DragonTail", { 0.8, 0.8, 2.2 }, { 0, -0.1, -2.4, 12, 0, 0 }, body)
	b.part("TailSpade", { 1.0, 0.2, 1.0 }, { 0, 0.3, -3.5 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
end

RECIPES.cat = function(b, body, accent)
	b.part("CatBody", { 2.6, 2.4, 3.2 }, { 0, -0.55, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("CatHead", { 2.3, 2.1, 2.1 }, { 0, 1.35, 0.75 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for _, side in ipairs({ -1, 1 }) do
		b.part("CatEar", { 0.8, 1.2, 0.4 }, { side * 0.8, 2.45, 0.6, 0, 0, side * -12 }, body)
		b.part("CatEarInner", { 0.45, 0.7, 0.2 }, { side * 0.8, 2.45, 0.82, 0, 0, side * -12 }, accent, Enum.Material.Neon)
		b.part("Whisker", { 1.1, 0.06, 0.06 }, { side * 1.15, 0.95, 1.65, 0, side * 14, side * 8 }, WHITE, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		b.part("CatPaw", { 0.75, 0.55, 1.0 }, { side * 0.8, -1.85, 0.85 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		b.part("CatPawBean", { 0.45, 0.18, 0.4 }, { side * 0.8, -2.05, 1.25 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	b.eyes(1.6, 1.85, 0.55, 0.46, accent)
	b.brows(2.05, 1.9, 0.55, -8)
	b.part("CatNose", { 0.3, 0.24, 0.2 }, { 0, 1.1, 1.8 }, Color3.fromRGB(255, 140, 170), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("CatMouth", { 0.5, 0.12, 0.12 }, { 0, 0.8, 1.82 }, Color3.fromRGB(60, 30, 50))
	b.part("CatTail", { 2.4, 0.35, 0.35 }, { 0.2, 0.4, -2.5, -22, 0, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("CatCollar", { 2.35, 0.35, 2.15 }, { 0, 0.45, 0.75 }, accent, Enum.Material.Neon, Enum.PartType.Block, 0.15)
end

RECIPES.noodlegoblin = function(b, body, accent)
	b.part("GoblinBody", { 2.8, 2.6, 2.6 }, { 0, -0.35, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("GoblinHead", { 2.2, 2.0, 2.0 }, { 0, 1.35, 0.35 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("GoblinNose", { 0.62, 0.5, 0.95 }, { 0, 0.95, 1.38 }, body:Lerp(WHITE, 0.25), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.eyes(1.55, 1.25, 0.48, 0.42, accent)
	b.brows(1.95, 1.28, 0.48, 14)
	b.part("Grin", { 1.0, 0.16, 0.2 }, { 0, 0.65, 1.35 }, DARK)
	b.part("EarL", { 1.15, 0.38, 0.38 }, { -1.2, 1.5, 0.25, 0, 0, -38 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("EarR", { 1.15, 0.38, 0.38 }, { 1.2, 1.5, 0.25, 0, 0, 38 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	for i = 1, 5 do
		local side = i % 2 == 0 and 1 or -1
		b.part("Noodle", { 0.3, 3.2, 0.3 }, { side * (0.9 + i * 0.18), -1.7, -0.35 + i * 0.18, 0, i * 12, side * 48 }, accent, Enum.Material.Neon, Enum.PartType.Cylinder)
		b.part("NoodleTip", { 0.46, 0.46, 0.46 }, { side * (1.9 + i * 0.18), -2.9, -0.35 + i * 0.18 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
	end
	b.part("ForkHandle", { 0.22, 2.7, 0.22 }, { 1.75, 0.35, -0.75, 0, 0, -28 }, Color3.fromRGB(210, 220, 230), Enum.Material.Metal, Enum.PartType.Cylinder)
	b.part("ForkHead", { 0.7, 0.2, 0.8 }, { 2.4, 1.55, -0.75 }, Color3.fromRGB(210, 220, 230), Enum.Material.Metal)
end

RECIPES.gnomemoth = function(b, body, accent)
	b.part("MothBody", { 2.4, 2.7, 2.2 }, { 0, -0.35, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("MothHead", { 1.8, 1.7, 1.7 }, { 0, 1.3, 0.45 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("HatBase", { 2.3, 0.3, 2.3 }, { 0, 2.05, 0.3 }, accent)
	b.part("HatMid", { 1.55, 0.6, 1.55 }, { 0, 2.45, 0.3 }, accent)
	b.part("HatTip", { 0.75, 0.75, 0.75 }, { 0, 2.95, 0.3 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
	b.part("Beard", { 1.2, 0.9, 0.5 }, { 0, 0.45, 1.2 }, WHITE, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.eyes(1.4, 1.2, 0.42, 0.38, accent)
	b.part("MothWingL", { 0.22, 2.9, 3.3 }, { -1.65, 0.35, -0.4, 0, 18, 28 }, accent, Enum.Material.Neon, Enum.PartType.Block, 0.18)
	b.part("MothWingR", { 0.22, 2.9, 3.3 }, { 1.65, 0.35, -0.4, 0, -18, -28 }, accent, Enum.Material.Neon, Enum.PartType.Block, 0.18)
	for _, side in ipairs({ -1, 1 }) do
		b.part("Antenna", { 0.12, 1.3, 0.12 }, { side * 0.45, 2.2, 0.55, 0, 0, side * 22 }, DARK, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		b.part("AntennaTip", { 0.28, 0.28, 0.28 }, { side * 0.68, 2.82, 0.55 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
		b.part("Shoe", { 0.85, 0.45, 1.2 }, { side * 0.6, -1.8, 0.35 }, DARK)
	end
	b.part("Lantern", { 0.65, 0.8, 0.65 }, { 0, -0.2, 1.35 }, Color3.fromRGB(255, 230, 140), Enum.Material.Neon, Enum.PartType.Ball, 0.15)
end

RECIPES.disco = function(b, body, accent)
	b.part("HamsterBody", { 2.7, 2.4, 2.8 }, { 0, -0.55, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("HamsterHead", { 2.1, 1.8, 1.9 }, { 0, 1.2, 0.55 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("CheekL", { 0.85, 0.7, 0.8 }, { -0.75, 0.75, 1.15 }, body:Lerp(WHITE, 0.25), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("CheekR", { 0.85, 0.7, 0.8 }, { 0.75, 0.75, 1.15 }, body:Lerp(WHITE, 0.25), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for _, side in ipairs({ -1, 1 }) do
		b.part("Ear", { 0.8, 0.8, 0.35 }, { side * 0.72, 2.05, 0.45 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		b.part("EarGlow", { 0.42, 0.42, 0.18 }, { side * 0.72, 2.05, 0.63 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
		b.part("Paw", { 0.55, 0.45, 0.8 }, { side * 1.05, -1.55, 0.9 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	b.eyes(1.45, 1.35, 0.48, 0.4, accent)
	b.part("Nose", { 0.28, 0.24, 0.2 }, { 0, 0.95, 1.55 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
	b.part("DiscoStem", { 1.5, 0.16, 0.16 }, { 0, 2.5, 0, 0, 0, -25 }, Color3.fromRGB(220, 225, 240), Enum.Material.Metal, Enum.PartType.Cylinder)
	b.part("DiscoBall", { 1.15, 1.15, 1.15 }, { -0.52, 3.15, 0 }, Color3.fromRGB(200, 220, 255), Enum.Material.Metal, Enum.PartType.Ball)
	for i = 0, 5 do
		local angle = i * 60
		b.part("DiscTile", { 0.18, 0.2, 0.5 }, { -0.52, 3.15, 0, angle, 0, 0 }, accent, Enum.Material.Neon)
	end
	b.part("DanceFloor", { 0.18, 3.8, 3.8 }, { 0, -2.0, 0.2, 0, 0, 90 }, accent, Enum.Material.Neon, Enum.PartType.Cylinder, 0.35)
end

RECIPES.boba = function(b, body, accent)
	b.part("YetiBody", { 3.0, 2.9, 2.6 }, { 0, -0.25, 0 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("YetiHead", { 2.3, 2.0, 2.0 }, { 0, 1.45, 0.4 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("FurL", { 1.25, 1.4, 1.25 }, { -1.15, 0.3, 0 }, body:Lerp(WHITE, 0.12), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("FurR", { 1.25, 1.4, 1.25 }, { 1.15, 0.3, 0 }, body:Lerp(WHITE, 0.12), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.eyes(1.7, 1.1, 0.46, 0.42, accent)
	b.brows(2.05, 1.15, 0.46, 6)
	b.part("Muzzle", { 1.1, 0.65, 0.7 }, { 0, 1.0, 1.28 }, body:Lerp(WHITE, 0.25), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Nose", { 0.36, 0.28, 0.24 }, { 0, 1.15, 1.65 }, DARK, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for _, side in ipairs({ -1, 1 }) do
		b.part("Horn", { 0.65, 0.28, 0.28 }, { side * 0.75, 2.45, 0.4, 0, 0, side * 52 }, Color3.fromRGB(130, 180, 220), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		b.part("Arm", { 0.45, 1.7, 0.45 }, { side * 1.55, 0.1, 0.25, 0, 0, side * 24 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
	b.part("TeaCup", { 2.0, 1.55, 1.75 }, { 0, -0.55, 1.25 }, Color3.fromRGB(250, 245, 235), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("Tea", { 0.22, 1.55, 1.55 }, { 0, -0.04, 1.55, 90, 0, 0 }, accent, Enum.Material.Neon, Enum.PartType.Cylinder, 0.1)
	b.part("Straw", { 1.75, 0.22, 0.22 }, { 0.42, 0.9, 1.35, 0, 0, -18 }, Color3.fromRGB(255, 115, 175), Enum.Material.Neon, Enum.PartType.Cylinder)
	for i = 1, 4 do
		b.part("Boba", { 0.34, 0.34, 0.34 }, { -0.45 + i * 0.28, -0.52, 2.08 }, DARK, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
end

RECIPES.ratking = function(b, body, accent)
	b.part("Pizza", { 0.75, 4.2, 4.2 }, { 0, -1.75, 0, 0, 0, 90 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("Crust", { 0.95, 4.5, 4.5 }, { 0, -1.95, 0, 0, 0, 90 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	for i = 1, 7 do
		local angle = i * (math.pi * 2 / 7)
		b.part("Pepperoni", { 0.42, 0.42, 0.42 }, { math.cos(angle) * 1.45, -1.28, math.sin(angle) * 1.45 }, Color3.fromRGB(220, 65, 55), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
	b.part("RatBody", { 2.2, 2.0, 2.4 }, { 0, 0.3, 0 }, body:Lerp(WHITE, 0.28), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("RatHead", { 1.7, 1.55, 1.6 }, { 0, 1.7, 0.65 }, body:Lerp(WHITE, 0.35), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("RatSnout", { 0.85, 0.55, 0.8 }, { 0, 1.45, 1.55 }, body:Lerp(WHITE, 0.5), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("RatNose", { 0.28, 0.22, 0.2 }, { 0, 1.55, 1.98 }, Color3.fromRGB(240, 140, 160), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for _, side in ipairs({ -1, 1 }) do
		b.part("RatEar", { 0.9, 0.9, 0.24 }, { side * 0.72, 2.5, 0.55 }, body:Lerp(WHITE, 0.3), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		b.part("RatEarInner", { 0.48, 0.48, 0.12 }, { side * 0.72, 2.5, 0.69 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
		b.part("Whisker", { 1.1, 0.06, 0.06 }, { side * 1.0, 1.35, 1.65, 0, side * 14, side * 8 }, WHITE, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
	b.eyes(1.85, 1.4, 0.38, 0.34, accent)
	b.part("RatTail", { 2.2, 0.25, 0.25 }, { 1.1, 0.1, -1.75, 0, 0, -42 }, Color3.fromRGB(230, 160, 170), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	b.part("CrownBase", { 1.65, 0.22, 0.45 }, { 0, 2.65, 0.55 }, Color3.fromRGB(255, 215, 70), Enum.Material.Neon)
	for i = -1, 1 do
		b.part("CrownSpike", { 0.32, 0.75, 0.32 }, { i * 0.45, 3.0, 0.55, 0, 0, i * 13 }, Color3.fromRGB(255, 215, 70), Enum.Material.Neon)
	end
end

RECIPES.puppet = function(b, body, accent)
	b.part("SockLeg", { 2.1, 3.6, 1.9 }, { 0, -0.1, 0, 0, 0, -7 }, body, Enum.Material.Fabric)
	b.part("SockHeel", { 1.55, 1.2, 1.5 }, { 0.65, -1.65, 0.1 }, body:Lerp(Color3.fromRGB(80, 40, 70), 0.18), Enum.Material.Fabric, Enum.PartType.Ball)
	b.part("SockToe", { 2.1, 1.7, 2.15 }, { 0, -1.6, 0.65 }, body:Lerp(WHITE, 0.1), Enum.Material.Fabric, Enum.PartType.Ball)
	b.part("Cuff", { 2.25, 0.45, 2.05 }, { 0, 1.75, 0 }, accent, Enum.Material.Neon)
	b.part("Mouth", { 1.35, 0.5, 0.2 }, { 0, -0.6, 1.25 }, Color3.fromRGB(55, 25, 55))
	b.part("Tongue", { 0.8, 0.18, 0.16 }, { 0, -0.78, 1.37 }, Color3.fromRGB(255, 120, 150), Enum.Material.Neon)
	b.eyes(-1.15, 1.12, 0.48, 0.44, accent)
	b.brows(-0.7, 1.18, 0.48, -12)
	for _, side in ipairs({ -1, 1 }) do
		b.part("Button", { 0.2, 0.2, 0.2 }, { side * 0.7, -0.3, 1.32 }, Color3.fromRGB(255, 215, 70), Enum.Material.Neon, Enum.PartType.Ball)
	end
	b.part("PuppetArm", { 0.45, 2.3, 0.45 }, { -1.35, -0.8, 0.1, 0, 0, 48 }, body, Enum.Material.Fabric, Enum.PartType.Cylinder)
	b.part("PuppetHand", { 0.7, 0.7, 0.7 }, { -2.15, -1.55, 0.1 }, accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Patch", { 0.55, 0.55, 0.12 }, { 0.65, -0.75, 1.23, 0, 0, 20 }, accent, Enum.Material.Neon)
end

RECIPES.cloudjelly = function(b, body, accent)
	local puffs = {
		{ -1.35, -0.15, 0.1, 1.65 },
		{ -0.55, 0.55, 0.0, 1.85 },
		{ 0.45, 0.4, -0.05, 1.75 },
		{ 1.3, -0.15, 0.1, 1.5 },
		{ 0, -0.55, 0.1, 2.1 },
	}
	for _, puff in ipairs(puffs) do
		b.part("CloudPuff", { puff[4], puff[4], puff[4] * 0.95 }, { puff[1], puff[2], puff[3] }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	b.part("JellyDome", { 2.3, 2.3, 2.3 }, { 0, 0.65, 0.7 }, accent, Enum.Material.Neon, Enum.PartType.Ball, 0.36)
	b.part("JellyCore", { 1.2, 1.2, 1.2 }, { 0, 0.55, 0.75 }, accent:Lerp(WHITE, 0.4), Enum.Material.Neon, Enum.PartType.Ball, 0.2)
	b.eyes(0.95, 1.75, 0.46, 0.38)
	b.part("Smile", { 0.85, 0.16, 0.15 }, { 0, 0.35, 1.72 }, DARK)
	for _, side in ipairs({ -1, 1 }) do
		b.part("Sparkle", { 0.35, 0.35, 0.35 }, { side * 2.1, 1.35, 0.2, 0, 0, 45 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
		b.part("RainDrop", { 0.28, 0.7, 0.28 }, { side * 0.95, -1.55, 0.35 }, Color3.fromRGB(110, 190, 255), Enum.Material.Neon, Enum.PartType.Ball, 0.25)
	end
	b.part("Halo", { 0.14, 2.6, 2.6 }, { 0, 1.65, 0.2, 0, 0, 90 }, accent, Enum.Material.Neon, Enum.PartType.Cylinder, 0.55)
end

RECIPES.radioskull = function(b, body, accent)
	b.part("Skull", { 2.2, 2.0, 1.9 }, { 0, 1.25, 0.25 }, body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.part("Jaw", { 1.5, 0.75, 1.4 }, { 0, 0.15, 0.55 }, body:Lerp(WHITE, 0.2))
	for _, side in ipairs({ -1, 1 }) do
		b.part("EyeSocket", { 0.7, 0.55, 0.35 }, { side * 0.47, 1.35, 1.12 }, DARK, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		b.part("EyeGlow", { 0.3, 0.24, 0.18 }, { side * 0.47, 1.35, 1.28 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
	end
	b.part("SkullNose", { 0.28, 0.24, 0.2 }, { 0, 0.8, 1.2 }, DARK, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	b.teeth(0.22, 1.26, 4, 0.25, WHITE)
	b.part("Radio", { 2.5, 1.7, 1.25 }, { 0, -1.15, 0.3 }, DARK, Enum.Material.Metal)
	b.part("Speaker", { 1.1, 1.0, 0.16 }, { -0.55, -1.15, 0.97 }, accent, Enum.Material.Neon, Enum.PartType.Cylinder)
	b.part("Dial", { 0.5, 0.5, 0.18 }, { 0.7, -0.95, 0.97 }, Color3.fromRGB(255, 220, 90), Enum.Material.Neon, Enum.PartType.Cylinder)
	for i = -1, 1 do
		b.part("Tuner", { 0.22, 0.22, 0.18 }, { 0.55 + i * 0.35, -1.55, 0.97 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
	end
	b.part("Antenna", { 2.4, 0.14, 0.14 }, { 0.9, 2.35, 0, 0, 0, -28 }, Color3.fromRGB(210, 220, 235), Enum.Material.Metal, Enum.PartType.Cylinder)
	b.part("AntennaTip", { 0.42, 0.42, 0.42 }, { 1.95, 3.35, 0 }, accent, Enum.Material.Neon, Enum.PartType.Ball)
	b.part("Handle", { 1.6, 0.22, 0.22 }, { 0, 0.05, -0.6, 0, 0, 90 }, Color3.fromRGB(210, 220, 235), Enum.Material.Metal, Enum.PartType.Cylinder)
end

-- Model assembly -----------------------------------------------------------

local function addNameplate(model: Model, root: BasePart, kind: any, rarity: any): any
	local billboard = Util.billboard(root, Vector2.new(300, 78), Vector3.new(0, 3.7, 0), 145)
	local card = Util.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(15, 13, 26),
		BackgroundTransparency = 0.18,
	}, billboard)
	Util.corner(card, 13)
	local stroke = Util.stroke(card, rarity.color, 2.2, 0.05)

	local nameLabel = Util.label({
		Size = UDim2.new(1, -16, 0.5, 0),
		Position = UDim2.fromOffset(8, 3),
		Text = kind.name,
		Font = Enum.Font.GothamBlack,
		TextColor3 = rarity.color,
		TextScaled = true,
	}, card)
	local subLabel = Util.label({
		Size = UDim2.new(1, -16, 0.36, 0),
		Position = UDim2.new(0, 8, 0.55, 0),
		Text = string.upper(rarity.name) .. "   •   $" .. tostring(rarity.value) .. "/SEC",
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(255, 240, 205),
		TextScaled = true,
	}, card)
	Util.corner(Util.frame({
		Size = UDim2.fromOffset(6, 44),
		Position = UDim2.new(0, 2, 0.5, -22),
		BackgroundColor3 = rarity.color,
	}, card), 3)

	-- A physical gem above the head: it still reads in a screenshot even when
	-- the billboard layer is not drawn.
	Util.part({
		Name = "RarityGem",
		Size = Vector3.new(0.55, 0.55, 0.55),
		CFrame = CFrame.new(0, 4.55, 0),
		Color = rarity.color,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Ball,
	}, model)
	Util.part({
		Name = "RarityGemRing",
		Size = Vector3.new(0.16, 0.95, 0.95),
		CFrame = CFrame.new(0, 4.55, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = rarity.color,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		Transparency = 0.35,
	}, model)
	return { name = nameLabel, sub = subLabel, card = card, stroke = stroke, billboard = billboard }
end

local function buildCreature(kind: any, rarity: any): (Model, BasePart, any)
	local model = Instance.new("Model")
	model.Name = "Brainrot_" .. kind.id
	model:SetAttribute("BrainrotKind", kind.name)
	model:SetAttribute("Rarity", kind.rarity)
	model:SetAttribute("Mutation", "None")
	model:SetAttribute("MutationMultiplier", 1)
	model:SetAttribute("CashPerSecond", rarity.value)
	model:SetAttribute("Quip", kind.quip)

	local root = Instance.new("Part")
	root.Name = "Hitbox"
	root.Size = Vector3.new(5.2, 5.6, 5.2)
	root.CFrame = CFrame.new(0, 0, 0)
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = true
	root.CanQuery = true
	root.Transparency = 1
	root.Massless = true
	root.Parent = model
	model.PrimaryPart = root

	local recipe = RECIPES[kind.shape]
	if recipe then
		recipe(brush(model), kind.body, kind.accent)
	else
		-- Unknown shape: still a valid, visible creature rather than an error.
		local b = brush(model)
		b.part("FallbackBody", { 2.5, 2.5, 2.5 }, { 0, 0, 0 }, kind.body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		b.eyes(0.4, 1.2, 0.5, 0.5)
	end

	if rarity.value >= Config.RARITIES.Legendary.value then
		Util.part({
			Name = "Aura",
			Size = Vector3.new(0.16, 4.8, 4.8),
			CFrame = CFrame.new(0, -2.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = rarity.color,
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Cylinder,
			Transparency = 0.42,
		}, model)
		local light = Instance.new("PointLight")
		light.Color = rarity.color
		light.Brightness = rarity.value >= Config.RARITIES.Mythic.value and 2.4 or 1.6
		light.Range = 16
		light.Parent = root
	end

	model.WorldPivot = root.CFrame
	local plate = addNameplate(model, root, kind, rarity)
	return model, root, plate
end

-- Spawning ----------------------------------------------------------------

local function wildSpot(): Vector3
	local center = Config.MAP.wildCenter
	return Vector3.new(
		center.X + (math.random() * 2 - 1) * (Config.MAP.wildHalfX - 7),
		center.Y,
		center.Z + (math.random() * 2 - 1) * (Config.MAP.wildHalfZ - 6)
	)
end

local function rollKind(): any
	local rarityName = Util.pickWeighted(Config.RARITY_ORDER, function(name: string)
		return Config.RARITIES[name].weight
	end)
	local candidates = {}
	for _, kind in ipairs(Config.BRAINROTS) do
		if kind.rarity == rarityName then
			table.insert(candidates, kind)
		end
	end
	if #candidates == 0 then
		return Config.BRAINROTS[1]
	end
	return candidates[math.random(#candidates)]
end

local function carriedList(player: Player): { any }
	local list = world.carried[player]
	if not list then
		list = {}
		world.carried[player] = list
	end
	return list
end

local function placedList(player: Player): { any }
	local list = world.placed[player]
	if not list then
		list = {}
		world.placed[player] = list
	end
	return list
end

local function refreshAttributes(player: Player)
	if not alive(player) then
		return
	end
	local carrying = world.carried[player] and #world.carried[player] or 0
	local banked = world.placed[player] and #world.placed[player] or 0
	local raw = 0
	if world.placed[player] then
		for _, record in ipairs(world.placed[player]) do
			raw += recordIncome(record)
		end
	end
	player:SetAttribute("Carried", carrying)
	player:SetAttribute("Placed", banked)
	player:SetAttribute("IncomePerSec", raw * multiplierOf(player))
end

local function dispatch(record: any, hit: BasePart?)
	local player = Util.playerFromHit(hit)
	if not player then
		return
	end
	if record.state == "wild" then
		BrainrotService.attemptGrab(player, record)
	elseif record.state == "placed" then
		if record.owner ~= player then
			deps.BaseService.trySteal(player, record)
		end
	elseif record.state == "carried" then
		if record.owner ~= player then
			deps.BaseService.tryStealCarried(player, record)
		end
	end
end

function BrainrotService.spawnOne(kindOverride: any?, positionOverride: Vector3?): any
	local kind = kindOverride or rollKind()
	if not kind then
		return nil
	end
	local rarity = Config.RARITIES[kind.rarity]
	if not rarity then
		return nil
	end
	local model, root, plate = buildCreature(kind, rarity)
	local position = positionOverride or wildSpot()
	local yaw = math.random() * math.pi * 2
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
	model.Parent = world.folder

	local record = {
		id = string.format("%s_%d", kind.id, math.random(100000, 999999)),
		kind = kind,
		rarity = rarity,
		model = model,
		root = root,
		nameplate = plate,
		mutation = nil,
		mutationRolled = false,
		state = "wild",
		owner = nil,
		basePos = position,
		target = wildSpot(),
		nextTarget = os.clock() + math.random(3, 7),
		yaw = yaw,
		phase = math.random() * math.pi * 2,
		slot = nil,
		baseCF = nil,
		carriedAt = 0,
	}

	table.insert(world.records, record)
	table.insert(world.wild, record)
	world.byRoot[root] = record
	root.Touched:Connect(function(hit)
		dispatch(record, hit)
	end)

	Util.fireAll(deps.Remotes.FX, { kind = "spawn", position = position, color = rarity.color })
	return record
end

-- Capture ----------------------------------------------------------------

local function noteCapture(player: Player, kind: any, position: Vector3?)
	local discoveries = 0
	pcall(function()
		discoveries = deps.DataService.recordCapture(player, kind.id)
	end)
	pcall(function()
		deps.QuestService.recordEvent(player, "capture", 1)
	end)
	pcall(function()
		deps.OnboardingService.progress(player, "grab")
	end)
	pcall(function()
		deps.StateService.push(player)
	end)
	if discoveries == 1 and position then
		pcall(function()
			Util.fireClient(deps.Remotes.FX, player, {
				kind = "discover",
				position = position,
				color = Config.RARITIES[kind.rarity].color,
			})
			Util.toast(deps.Remotes, player, string.format("NEW SPECIES: %s added to your Index!", kind.name), "legendary", Config.TOAST.normal)
		end)
	end
end

function BrainrotService.attemptGrab(player: Player, record: any): boolean
	if not alive(player) or not record then
		return false
	end
	if record.state ~= "wild" then
		return false
	end
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false
	end

	local list = carriedList(player)
	local cap = carryCapOf(player)
	if #list >= cap then
		local now = os.clock()
		if (world.fullNoticeAt[player] or 0) < now then
			world.fullNoticeAt[player] = now + Config.TOAST.full
			Util.toast(deps.Remotes, player, string.format("Hands full (%d/%d). Bank them or buy Carry Cap!", #list, cap), "bad", Config.TOAST.short)
		end
		return false
	end

	Util.removeAll(world.wild, record)
	record.state = "carried"
	record.owner = player
	record.carriedAt = os.clock()
	record.basePos = nil

	-- The one and only mutation roll. It happens before the toast so the player
	-- reads the name, colour and new income in the same message.
	if deps.MutationService then
		local ok, err = pcall(deps.MutationService.rollForCapture, record)
		if not ok then
			warn("[BrainrotService] mutation roll failed: " .. tostring(err))
		end
		if record.mutation then
			local painted, paintErr = pcall(deps.MutationService.apply, record)
			if not painted then
				warn("[BrainrotService] mutation paint failed: " .. tostring(paintErr))
			end
		end
	end

	table.insert(list, record)
	refreshAttributes(player)
	deps.BaseService.refreshPad(player)

	Util.fireClient(deps.Remotes.FX, player, {
		kind = "grab",
		position = record.model:GetPivot().Position,
		color = record.mutation and record.mutation.color or record.rarity.color,
	})
	local mutation = record.mutation
	local income = record.rarity.value
	if deps.MutationService then
		income = deps.MutationService.incomeOf(record)
	end
	local tag = mutation and string.format(" [%s x%.2f]", mutation.key, mutation.multiplier) or ""
	Util.toast(deps.Remotes, player, string.format("Grabbed %s%s (%s) • $%d/sec. %s", record.kind.name, tag, record.rarity.name, income, record.kind.quip), mutation and "legendary" or "good", Config.TOAST.normal)

	if mutation then
		Util.broadcastToast(deps.Remotes, string.format("%s caught a %s %s! %s income.", player.DisplayName, mutation.key, record.kind.name, string.format("x%.2f", mutation.multiplier)), "legendary", Config.TOAST.long)
	elseif record.rarity.value >= Config.RARITIES.Legendary.value then
		Util.broadcastToast(deps.Remotes, string.format("%s grabbed a %s %s!", player.DisplayName, record.rarity.name, record.kind.name), "legendary", Config.TOAST.long)
	end
	noteCapture(player, record.kind, record.model:GetPivot().Position)
	return true
end

-- Hands a creature to a thief. BaseService has already validated the steal;
-- this function only moves bookkeeping and models, and is safe to call with a
-- stale record (it returns false instead of erroring).
function BrainrotService.transferToCarried(record: any, thief: Player): boolean
	if not record or not alive(thief) then
		return false
	end

	local previous = record.owner
	if record.state == "placed" then
		if previous and world.placed[previous] then
			Util.removeAll(world.placed[previous], record)
			if record.slot then
				deps.BaseService.setSlotOccupied(previous, record.slot, false)
			end
			record.slot = nil
			record.baseCF = nil
			refreshAttributes(previous)
			deps.BaseService.refreshPad(previous)
		end
	elseif record.state == "carried" then
		if previous and world.carried[previous] then
			Util.removeAll(world.carried[previous], record)
			refreshAttributes(previous)
		end
	elseif record.state == "wild" then
		Util.removeAll(world.wild, record)
	end

	local list = carriedList(thief)
	record.state = "carried"
	record.owner = thief
	record.carriedAt = os.clock()
	record.basePos = nil
	record.slot = nil
	record.baseCF = nil
	table.insert(list, record)
	refreshAttributes(thief)
	deps.BaseService.refreshPad(thief)
	return true
end

-- Banking ----------------------------------------------------------------

local function seatOnPad(record: any, player: Player, slot: number, slotCFrame: CFrame)
	record.state = "placed"
	record.owner = player
	record.slot = slot
	record.baseCF = slotCFrame
	record.basePos = slotCFrame.Position

	-- Face the plaza: that is the shortest way from any deck.
	local pad = deps.BaseService.getPad(player)
	local look = pad and (pad.center - slotCFrame.Position) or Vector3.new(-slotCFrame.Position.X, 0, -slotCFrame.Position.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	record.yaw = math.atan2(look.X, look.Z)

	-- Move the model in the same frame as the data: banking has to be visible
	-- on the pad immediately, not one animation tick later.
	if record.model then
		record.model.Parent = world.folder
		record.model:PivotTo(CFrame.new(slotCFrame.Position) * CFrame.Angles(0, record.yaw, 0))
	end
	deps.BaseService.setSlotOccupied(player, slot, true)
end

function BrainrotService.placeCarried(player: Player): number
	if not alive(player) then
		return 0
	end
	local list = world.carried[player]
	if not list or #list == 0 then
		return 0
	end
	local pad = deps.BaseService.getPad(player)
	if not pad then
		return 0
	end

	local taken = {}
	local banked = placedList(player)
	for _, record in ipairs(banked) do
		if record.slot then
			taken[record.slot] = true
		end
	end

	local slotCap = padSlotsOf(player)
	local snapshot = table.clone(list)
	local moved = 0
	for _, record in ipairs(snapshot) do
		local slot = nil
		for candidate = 1, slotCap do
			if not taken[candidate] then
				slot = candidate
				break
			end
		end
		if not slot then
			break
		end
		local slotCFrame = deps.BaseService.getSlotCFrame(player, slot)
		if slotCFrame then
			taken[slot] = true
			Util.removeAll(list, record)
			seatOnPad(record, player, slot, slotCFrame)
			table.insert(banked, record)
			moved += 1
		end
	end

	if #list > 0 then
		Util.toast(deps.Remotes, player, string.format("Your base is full (%d/%d). Buy Pad Slots or rebirth!", #banked, slotCap), "bad", Config.TOAST.normal)
	end
	refreshAttributes(player)
	deps.BaseService.refreshPad(player)

	if moved > 0 then
		Util.fireClient(deps.Remotes.FX, player, { kind = "place", position = pad.center + Vector3.new(0, 4, 0), count = moved })
		Util.fireClient(deps.Remotes.FX, player, { kind = "padPulse", position = pad.center, count = moved })
		pcall(function()
			deps.QuestService.recordEvent(player, "bank", moved)
		end)
		pcall(function()
			deps.OnboardingService.progress(player, "bank")
		end)
		pcall(function()
			deps.StateService.push(player)
		end)
	end
	return moved
end

function BrainrotService.getCarriedCount(player: Player): number
	local list = world.carried[player]
	return list and #list or 0
end

function BrainrotService.getPlacedCount(player: Player): number
	local list = world.placed[player]
	return list and #list or 0
end

function BrainrotService.getBaseIncome(player: Player): number
	local list = world.placed[player]
	if not list then
		return 0
	end
	local total = 0
	for _, record in ipairs(list) do
		total += recordIncome(record)
	end
	return total
end

-- Crafting -----------------------------------------------------------------
-- The three source records are consumed, not returned to the wild. Their two
-- spare slots stay empty; the crafted creature takes the first freed slot so
-- the player always sees the result appear where the recipe began.

function BrainrotService.countBankedRarity(player: Player, rarityName: string): number
	local list = world.placed[player]
	if not list then
		return 0
	end
	local count = 0
	for _, record in ipairs(list) do
		if record.rarity.name == rarityName then
			count += 1
		end
	end
	return count
end

function BrainrotService.craftBanked(player: Player, sourceRarity: string, kind: any): any
	if not alive(player) or type(kind) ~= "table" then
		return nil
	end
	local sourceIndex = table.find(Config.RARITY_ORDER, sourceRarity)
	local targetRarity = sourceIndex and Config.RARITY_ORDER[sourceIndex + 1]
	if not targetRarity or kind.rarity ~= targetRarity then
		return nil
	end

	local list = world.placed[player]
	if not list then
		return nil
	end
	local picked = {}
	for _, record in ipairs(list) do
		if record.rarity.name == sourceRarity and record.slot then
			table.insert(picked, record)
			if #picked >= Config.CRAFT_COUNT then
				break
			end
		end
	end
	if #picked < Config.CRAFT_COUNT then
		return nil
	end

	local targetSlot = picked[1].slot
	local slotCFrame = targetSlot and deps.BaseService.getSlotCFrame(player, targetSlot)
	if not slotCFrame then
		return nil
	end

	-- Build the result before spending anything. A failed model build leaves
	-- the three originals exactly where they were.
	local ok, newRecord = pcall(BrainrotService.spawnOne, kind)
	if not ok or not newRecord then
		return nil
	end
	Util.removeAll(world.wild, newRecord)

	for _, record in ipairs(picked) do
		Util.removeAll(list, record)
		Util.removeAll(world.records, record)
		world.byRoot[record.root] = nil
		if record.slot then
			deps.BaseService.setSlotOccupied(player, record.slot, false)
		end
		if record.model then
			record.model:Destroy()
		end
	end

	table.insert(list, newRecord)
	seatOnPad(newRecord, player, targetSlot, slotCFrame)
	refreshAttributes(player)
	deps.BaseService.refreshPad(player)
	pcall(function()
		deps.StateService.push(player)
	end)
	return newRecord
end

-- Releasing creatures back to the wild ------------------------------------

local function releaseToWild(record: any)
	-- Free the pad slot before the record forgets which slot it held.
	if record.owner and record.slot then
		deps.BaseService.setSlotOccupied(record.owner, record.slot, false)
	end
	record.state = "wild"
	record.owner = nil
	record.slot = nil
	record.baseCF = nil
	local spot = wildSpot()
	record.basePos = spot
	record.target = wildSpot()
	record.nextTarget = os.clock() + math.random(3, 7)
	record.yaw = math.random() * math.pi * 2
	if not table.find(world.wild, record) then
		table.insert(world.wild, record)
	end
	if record.model and record.model.Parent ~= world.folder then
		record.model.Parent = world.folder
	end
	Util.fireAll(deps.Remotes.FX, { kind = "spawn", position = spot, color = record.rarity.color })
end

function BrainrotService.dropCarriedToWild(player: Player, reason: string?): number
	if not player then
		return 0
	end
	local list = world.carried[player]
	if not list or #list == 0 then
		return 0
	end
	local dropped = 0
	for _, record in ipairs(table.clone(list)) do
		Util.removeAll(list, record)
		releaseToWild(record)
		dropped += 1
	end
	refreshAttributes(player)
	deps.BaseService.refreshPad(player)
	if dropped > 0 and alive(player) then
		if reason == "wave" then
			-- WaveService owns the loud message; this is only the shove.
			Util.fireClient(deps.Remotes.FX, player, { kind = "shake", strength = 1.1, duration = 0.55 })
		elseif reason == "death" then
			Util.toast(deps.Remotes, player, "You dropped your brainrots when you went down!", "bad", Config.TOAST.normal)
			Util.fireClient(deps.Remotes.FX, player, { kind = "shake", strength = 0.8, duration = 0.45 })
		else
			Util.toast(deps.Remotes, player, string.format("%d brainrot%s scattered back to the wild!", dropped, dropped == 1 and "" or "s"), "bad", Config.TOAST.normal)
			Util.fireClient(deps.Remotes.FX, player, { kind = "shake", strength = 0.8, duration = 0.45 })
		end
	end
	return dropped
end

function BrainrotService.clearBaseForRebirth(player: Player)
	for _, bucket in ipairs({ world.placed[player], world.carried[player] }) do
		if bucket then
			for _, record in ipairs(table.clone(bucket)) do
				Util.removeAll(bucket, record)
				releaseToWild(record)
			end
		end
	end
	refreshAttributes(player)
	deps.BaseService.refreshPad(player)
end

function BrainrotService.releasePlayer(player: Player)
	for _, bucket in ipairs({ world.carried[player], world.placed[player] }) do
		if bucket then
			for _, record in ipairs(table.clone(bucket)) do
				Util.removeAll(bucket, record)
				releaseToWild(record)
			end
		end
	end
	world.carried[player] = nil
	world.placed[player] = nil
	world.incomeBank[player] = nil
	world.incomeFloatAt[player] = nil
	world.fullNoticeAt[player] = nil
	local link = world.deathLinks[player]
	if link then
		pcall(function()
			link:Disconnect()
		end)
		world.deathLinks[player] = nil
	end
end

function BrainrotService.watchCharacter(player: Player, character: Model)
	local previous = world.deathLinks[player]
	if previous then
		pcall(function()
			previous:Disconnect()
		end)
		world.deathLinks[player] = nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	world.deathLinks[player] = humanoid.Died:Connect(function()
		task.delay(0.25, function()
			if alive(player) then
				BrainrotService.dropCarriedToWild(player, "death")
			end
		end)
	end)
end

-- Animation and economy loops ---------------------------------------------

local function moveRecord(record: any, position: Vector3, yaw: number)
	if record.model and record.model.Parent then
		record.model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
	end
end

-- Re-seat a banked model on its slot. The income loop calls this as a cheap
-- self-heal so one bad frame cannot leave an invisible base.
local function reseat(record: any)
	if record.state ~= "placed" or not record.model or not record.baseCF then
		return
	end
	if record.model.Parent ~= world.folder then
		record.model.Parent = world.folder
	end
	record.model:PivotTo(CFrame.new(record.baseCF.Position) * CFrame.Angles(0, record.yaw or 0, 0))
end

local CARRY_OFFSETS = { -1.55, 0, 1.55, -0.8, 0.8, -2.2, 2.2, 0 }

local function animateWild(record: any, now: number)
	if not record.target then
		record.target = wildSpot()
	end
	if now >= (record.nextTarget or 0) then
		record.target = wildSpot()
		record.nextTarget = now + math.random(4, 8)
	end
	local basePos = record.basePos or record.model:GetPivot().Position
	local flat = Vector3.new(record.target.X - basePos.X, 0, record.target.Z - basePos.Z)
	if flat.Magnitude > 0.35 then
		local step = math.min(Config.WILD_SPEED * Config.MOVEMENT_TICK, flat.Magnitude)
		basePos = basePos + flat.Unit * step
		record.yaw = math.atan2(flat.X, flat.Z)
	end
	record.basePos = basePos
	local bob = math.sin(now * 2.3 + record.phase) * Config.WILD_BOB
	moveRecord(record, basePos + Vector3.new(0, bob, 0), record.yaw)
end

local function animatePlaced(record: any, now: number)
	local seat = record.baseCF
	if not seat then
		return
	end
	local bob = math.sin(now * 1.8 + record.phase) * Config.PLACED_BOB
	moveRecord(record, seat.Position + Vector3.new(0, 0.25 + bob, 0), record.yaw)
end

local function animateCarried(record: any, now: number)
	local owner = record.owner
	local character = owner and owner.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (owner and hrp and hrp:IsA("BasePart")) then
		-- The carrier is gone: drop the creature instead of leaving it floating.
		if owner and world.carried[owner] then
			Util.removeAll(world.carried[owner], record)
		end
		releaseToWild(record)
		if owner then
			refreshAttributes(owner)
			deps.BaseService.refreshPad(owner)
		end
		return
	end
	local list = world.carried[owner]
	local index = math.clamp(list and table.find(list, record) or 1, 1, #CARRY_OFFSETS)
	local row = math.floor((index - 1) / 3)
	local bob = math.sin(now * 3 + record.phase) * Config.CARRY_BOB
	local offset = Vector3.new(
		CARRY_OFFSETS[index],
		Config.CARRY_HEIGHT + index * Config.CARRY_STACK + row * 0.35 + bob,
		0
	)
	local look = hrp.CFrame.LookVector
	moveRecord(record, hrp.Position + offset, math.atan2(look.X, look.Z))
end

local function animationLoop()
	task.spawn(function()
		while world.running do
			local now = os.clock()
			for _, record in ipairs(world.records) do
				-- One malformed record must not freeze the other 39.
				local ok, err = pcall(function()
					if not record.model or not record.model.Parent then
						return
					end
					if record.state == "wild" then
						animateWild(record, now)
					elseif record.state == "placed" then
						animatePlaced(record, now)
					elseif record.state == "carried" then
						animateCarried(record, now)
					end
				end)
				if not ok and not world.animWarned then
					world.animWarned = true
					warn("[BrainrotService] animation tick skipped a creature: " .. tostring(err))
				end
			end
			task.wait(Config.MOVEMENT_TICK)
		end
	end)
end

local function incomeLoop()
	task.spawn(function()
		while world.running do
			task.wait(Config.INCOME_INTERVAL)
			local now = os.clock()
			for player, list in pairs(world.placed) do
				if alive(player) and #list > 0 then
					local perSecond = 0
					for _, record in ipairs(list) do
						perSecond += recordIncome(record)
						-- Self-heal a model that drifted off its slot.
						local drift = record.baseCF and (record.model:GetPivot().Position - record.baseCF.Position).Magnitude or 0
						if record.model and (record.model.Parent ~= world.folder or drift > Config.SNAP_DISTANCE) then
							pcall(reseat, record)
						end
					end
					local multiplier = multiplierOf(player)
					local amount = perSecond * multiplier
					if amount > 0 then
						deps.PlayerService.addCash(player, amount)
						world.incomeBank[player] = (world.incomeBank[player] or 0) + amount
						if now - (world.incomeFloatAt[player] or 0) >= Config.INCOME_FLOAT_EVERY then
							world.incomeFloatAt[player] = now
							Util.fireClient(deps.Remotes.FX, player, {
								kind = "float",
								position = deps.BaseService.getPadCenter(player) + Vector3.new(0, 8, 0),
								text = "+$" .. Util.formatCash(world.incomeBank[player]),
								tone = "gold",
							})
							world.incomeBank[player] = 0
						end
					end
					player:SetAttribute("IncomePerSec", perSecond * multiplier)
				end
			end
		end
	end)
end

-- The Magnet upgrade: sweep wild creatures near a player into their hands. It
-- goes through attemptGrab, so the carry cap still applies.
local function magnetLoop()
	task.spawn(function()
		while world.running do
			task.wait(Config.MAGNET_TICK)
			for _, player in ipairs(Players:GetPlayers()) do
				local radius = 0
				local service = upgrades()
				if service then
					radius = service.getMagnetRadius(player)
				end
				if radius > 0 and BrainrotService.getCarriedCount(player) < carryCapOf(player) then
					local character = player.Character
					local hrp = character and character:FindFirstChild("HumanoidRootPart")
					if hrp and hrp:IsA("BasePart") then
						for _, record in ipairs(table.clone(world.wild)) do
							if record.state == "wild" and record.model.Parent then
								if Util.flatDistance(hrp.Position, record.model:GetPivot().Position) <= radius then
									BrainrotService.attemptGrab(player, record)
									if BrainrotService.getCarriedCount(player) >= carryCapOf(player) then
										break
									end
								end
							end
						end
					end
				end
			end
		end
	end)
end

local function refillLoop()
	task.spawn(function()
		while world.running do
			task.wait(Config.SPAWN_INTERVAL)
			if #world.wild < Config.MAX_WILD and #world.records < Config.MAX_RECORDS then
				local ok = pcall(function()
					BrainrotService.spawnOne()
				end)
				if not ok then
					warn("[BrainrotService] a wild spawn failed")
				end
			end
		end
	end)
end

-- Lifecycle ---------------------------------------------------------------

function BrainrotService.start(services: any)
	deps = services
	Config = services.Config
	Util = services.Util

	local previous = Workspace:FindFirstChild("Brainrots")
	if previous then
		previous:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Brainrots"
	folder.Parent = Workspace
	world.folder = folder

	world.records = {}
	world.wild = {}
	world.carried = {}
	world.placed = {}
	world.byRoot = {}
	world.deathLinks = {}
	world.fullNoticeAt = {}
	world.incomeBank = {}
	world.incomeFloatAt = {}
	world.animWarned = false
	world.running = true

	-- Seed the wild deck with the first few cast members so the world reads
	-- alive on the first frame; the rest arrive on the weighted timer.
	for i = 1, math.min(Config.WILD_SEED, #Config.BRAINROTS) do
		pcall(function()
			BrainrotService.spawnOne(Config.BRAINROTS[i])
		end)
	end

	animationLoop()
	incomeLoop()
	magnetLoop()
	refillLoop()
end

function BrainrotService.stop()
	world.running = false
	for player, link in pairs(world.deathLinks) do
		pcall(function()
			link:Disconnect()
		end)
		world.deathLinks[player] = nil
	end
	for _, record in ipairs(world.records) do
		if record.model then
			record.model:Destroy()
		end
	end
	world.records = {}
	world.wild = {}
	world.carried = {}
	world.placed = {}
	world.byRoot = {}
	if world.folder then
		world.folder:Destroy()
		world.folder = nil
	end
end

return BrainrotService
