-- BrainrotService: the whole brainrot life cycle. It builds every creature out
-- of primitive parts, spawns and wanders them in the wild zone, locks one to a
-- player who touches it, banks carried creatures on the owner's pad and pays
-- their cash/sec every second. Stealing is validated by BaseService and lands
-- here as transferToCarried.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BrainrotService = {}

local Util
local Config
local deps: any = nil

local records: { any } = {}
local wild: { any } = {}
local carried: { [Player]: { any } } = {}
local placed: { [Player]: { any } } = {}
local rootToRecord: { [BasePart]: any } = {}
local incomeShown: { [Player]: number } = {}
local lastIncomeShownAt: { [Player]: number } = {}
local fullToastAt: { [Player]: number } = {}
local deathConnections: { [Player]: any } = {}
local brainrotFolder: Folder? = nil

-- Primitive-part helpers ----------------------------------------------------
local function at(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
end

local function v(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = transparency or 0
	p.Parent = model
	return p
end

local function eyes(model: Model, y: number, z: number, spread: number, size: number, pupilColor: Color3?)
	local white = Color3.fromRGB(255, 255, 255)
	local pupil = pupilColor or Color3.fromRGB(20, 18, 28)
	for _, sx in ipairs({ -1, 1 }) do
		v(model, "Eye", Vector3.new(size, size, size * 0.7), at(sx * spread, y, z), white, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		v(model, "Pupil", Vector3.new(size * 0.42, size * 0.48, size * 0.35), at(sx * spread, y, z + size * 0.42), pupil, Enum.Material.Neon, Enum.PartType.Ball)
	end
end

local function brows(model: Model, y: number, z: number, spread: number, tilt: number)
	for _, sx in ipairs({ -1, 1 }) do
		v(model, "Brow", Vector3.new(0.85, 0.16, 0.2), at(sx * spread, y, z, 0, 0, sx * tilt), Color3.fromRGB(35, 30, 46), Enum.Material.SmoothPlastic)
	end
end

local function teeth(model: Model, y: number, z: number, count: number, width: number, color: Color3?)
	local c = color or Color3.fromRGB(255, 255, 255)
	for i = 1, count do
		local x = (i - (count + 1) / 2) * width
		v(model, "Tooth", Vector3.new(width * 0.55, 0.35, 0.18), at(x, y, z), c)
	end
end

local function nameplate(model: Model, root: BasePart, kind: any, rarity: any)
	local bb = Util.billboard(root, Vector2.new(300, 78), Vector3.new(0, 3.7, 0), 145)
	local frame = Util.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(15, 13, 26),
		BackgroundTransparency = 0.18,
	}, bb)
	Util.corner(frame, 13)
	Util.stroke(frame, rarity.color, 2.2, 0.05)

	Util.label({
		Size = UDim2.new(1, -16, 0.5, 0),
		Position = UDim2.fromOffset(8, 3),
		Text = kind.name,
		Font = Enum.Font.GothamBlack,
		TextColor3 = rarity.color,
		TextScaled = true,
	}, frame)
	Util.label({
		Size = UDim2.new(1, -16, 0.36, 0),
		Position = UDim2.new(0, 8, 0.55, 0),
		Text = string.upper(rarity.name) .. "   •   $" .. tostring(rarity.value) .. "/SEC",
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(255, 240, 205),
		TextScaled = true,
	}, frame)

	-- A rarity bead on the left edge, readable even when the nameplate is small.
	local bead = Util.frame({
		Size = UDim2.fromOffset(6, 44),
		Position = UDim2.new(0, 2, 0.5, -22),
		BackgroundColor3 = rarity.color,
	}, frame)
	Util.corner(bead, 3)
end

-- Shape builders ------------------------------------------------------------
local function buildToilet(model: Model, kind: any, rarity: any)
	local body = kind.body
	local accent = kind.accent
	v(model, "Bowl", Vector3.new(2.8, 3.2, 3.2), at(0, -1.1, 0, 0, 0, 90), body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	v(model, "Rim", Vector3.new(0.5, 3.6, 3.6), at(0, 0.25, 0), body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	v(model, "Water", Vector3.new(0.16, 2.6, 2.6), at(0, 0.48, 0, 0, 0, 0), Color3.fromRGB(60, 230, 255), Enum.Material.Neon, Enum.PartType.Cylinder, 0.25)
	v(model, "Tank", Vector3.new(2.4, 2.4, 1.2), at(0, 0.95, 1.45), body)
	v(model, "Lid", Vector3.new(2.7, 0.25, 1.5), at(0, 2.25, 1.45), body:Lerp(Color3.fromRGB(255, 255, 255), 0.4))
	v(model, "Flush", Vector3.new(1.2, 0.2, 0.5), at(0, 2.42, 1.45), accent, Enum.Material.Neon)
	eyes(model, 1.1, 2.12, 0.68, 0.62)
	brows(model, 1.55, 2.16, 0.68, 12)
	v(model, "Mouth", Vector3.new(0.9, 0.16, 0.2), at(0, 0.55, 2.12), Color3.fromRGB(60, 30, 60))
	v(model, "PlungerStick", Vector3.new(2.8, 0.28, 0.28), at(2.3, 0.9, 0, 0, 0, -38), Color3.fromRGB(130, 80, 42), Enum.Material.Wood, Enum.PartType.Cylinder)
	v(model, "PlungerCup", Vector3.new(1.1, 1.1, 1.1), at(3.55, 0.05, 0), Color3.fromRGB(240, 70, 85), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	v(model, "Spin", Vector3.new(0.18, 4.6, 4.6), at(0, -2.45, 0), accent, Enum.Material.Neon, Enum.PartType.Cylinder, 0.4)
	for i = 0, 2 do
		v(model, "Prop", Vector3.new(0.22, 0.22, 2.5), at(0, 3.55, 0, 0, i * 60, 0), accent, Enum.Material.Neon)
	end
	v(model, "PropHub", Vector3.new(0.7, 0.7, 0.7), at(0, 3.55, 0), body, Enum.Material.Metal, Enum.PartType.Ball)
end

local function buildTaco(model: Model, kind: any, rarity: any)
	local shell = kind.body
	v(model, "ShellL", Vector3.new(0.45, 3.5, 3.4), at(-1.15, 0, 0, 0, 0, 16), shell)
	v(model, "ShellR", Vector3.new(0.45, 3.5, 3.4), at(1.15, 0, 0, 0, 0, -16), shell)
	v(model, "ShellBottom", Vector3.new(2.4, 0.6, 3.2), at(0, -1.55, 0), shell:Lerp(Color3.fromRGB(160, 100, 20), 0.2))
	v(model, "Lettuce1", Vector3.new(1.0, 1.0, 1.0), at(-0.7, 1.0, 0.4), Color3.fromRGB(80, 205, 90), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	v(model, "Lettuce2", Vector3.new(1.1, 1.1, 1.1), at(0.1, 1.2, 0.1), Color3.fromRGB(55, 180, 75), Enum.Material.Grass, Enum.PartType.Ball)
	v(model, "Lettuce3", Vector3.new(0.9, 0.9, 0.9), at(0.8, 1.0, 0.5), Color3.fromRGB(105, 220, 105), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	v(model, "Tomato1", Vector3.new(0.55, 0.55, 0.55), at(-0.2, 1.55, 0.9), Color3.fromRGB(235, 70, 60))
	v(model, "Tomato2", Vector3.new(0.5, 0.5, 0.5), at(0.6, 1.45, 0.8), Color3.fromRGB(235, 70, 60))
	for i = -1, 1 do
		v(model, "Cheese", Vector3.new(1.5, 0.16, 0.35), at(i * 0.8, 1.65, -0.3, 0, 18, 0), Color3.fromRGB(255, 220, 90))
	end
	v(model, "Head", Vector3.new(1.6, 1.4, 1.5), at(0, 2.55, 0.7), kind.accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	v(model, "Snout", Vector3.new(1.0, 0.7, 1.0), at(0, 2.35, 1.6), kind.accent:Lerp(Color3.fromRGB(255, 255, 255), 0.1))
	eyes(model, 2.75, 1.42, 0.38, 0.42)
	brows(model, 3.0, 1.45, 0.38, -10)
	v(model, "Nostril1", Vector3.new(0.16, 0.16, 0.16), at(0.2, 2.45, 2.1), Color3.fromRGB(40, 90, 40))
	v(model, "Nostril2", Vector3.new(0.16, 0.16, 0.16), at(-0.2, 2.45, 2.1), Color3.fromRGB(40, 90, 40))
	for i = 1, 4 do
		v(model, "Tooth", Vector3.new(0.18, 0.34, 0.16), at(-0.45 + i * 0.22, 2.18, 2.12), Color3.fromRGB(255, 255, 255))
	end
	for i = 1, 3 do
		v(model, "Spike", Vector3.new(0.45, 0.55, 0.45), at(-0.6 + i * 0.5, 3.15, 0.4, 0, 45, 0), Color3.fromRGB(255, 150, 60), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	v(model, "ArmL", Vector3.new(0.18, 0.8, 0.18), at(-1.35, 1.7, 0.4, 0, 0, -35), kind.accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	v(model, "ArmR", Vector3.new(0.18, 0.8, 0.18), at(1.35, 1.7, 0.4, 0, 0, 35), kind.accent, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
end

local function buildFridge(model: Model, kind: any, rarity: any)
	v(model, "FridgeBody", Vector3.new(2.9, 4.0, 1.8), at(0, 0, 0), kind.body, Enum.Material.Metal)
	v(model, "DoorSplit", Vector3.new(2.9, 0.1, 0.08), at(0, 0.45, 0.93), Color3.fromRGB(80, 90, 105), Enum.Material.Metal)
	for _, sx in ipairs({ -1.25, 1.25 }) do
		v(model, "Handle", Vector3.new(2.2, 0.2, 0.2), at(sx, 0.1, 1.05, 0, 0, 0), Color3.fromRGB(140, 160, 180), Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	v(model, "Magnet1", Vector3.new(0.35, 0.35, 0.12), at(-0.7, 1.2, 0.95), Color3.fromRGB(255, 110, 150))
	v(model, "Magnet2", Vector3.new(0.35, 0.35, 0.12), at(-0.2, 1.45, 0.95), Color3.fromRGB(90, 200, 255))
	v(model, "Magnet3", Vector3.new(0.35, 0.35, 0.12), at(0.3, 1.1, 0.95), Color3.fromRGB(255, 215, 90))
	v(model, "RhinoHead", Vector3.new(1.9, 1.5, 1.7), at(0, 2.65, 0.3), Color3.fromRGB(150, 156, 170), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	v(model, "Horn", Vector3.new(1.2, 0.42, 0.42), at(0, 2.95, 1.25, 0, 0, 90), Color3.fromRGB(240, 226, 190), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	eyes(model, 2.78, 1.15, 0.48, 0.45)
	brows(model, 3.02, 1.2, 0.48, 8)
	v(model, "EarL", Vector3.new(0.55, 0.4, 0.25), at(-0.65, 3.4, 0.2, 0, 0, 18), Color3.fromRGB(135, 140, 155))
	v(model, "EarR", Vector3.new(0.55, 0.4, 0.25), at(0.65, 3.4, 0.2, 0, 0, -18), Color3.fromRGB(135, 140, 155))
	v(model, "Nostril1", Vector3.new(0.14, 0.14, 0.14), at(0.2, 2.55, 1.35), Color3.fromRGB(70, 70, 85))
	v(model, "Nostril2", Vector3.new(0.14, 0.14, 0.14), at(-0.2, 2.55, 1.35), Color3.fromRGB(70, 70, 85))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			v(model, "Leg", Vector3.new(0.55, 0.7, 0.55), at(sx * 0.95, -2.35, sz * 0.55), Color3.fromRGB(130, 136, 150), Enum.Material.Metal)
		end
	end
	v(model, "Milk", Vector3.new(0.8, 1.1, 0.8), at(1.0, 2.75, -0.2), Color3.fromRGB(250, 250, 250))
	v(model, "MilkTop", Vector3.new(0.85, 0.25, 0.85), at(1.0, 3.35, -0.2), kind.accent, Enum.Material.Neon)
end

local function buildShake(model: Model, kind: any, rarity: any)
	v(model, "Cup", Vector3.new(3.2, 3.4, 3.4), at(0, -0.5, 0, 0, 0, 90), kind.body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	v(model, "Lid", Vector3.new(0.45, 3.7, 3.7), at(0, 1.25, 0, 0, 0, 90), kind.body:Lerp(Color3.fromRGB(230, 160, 255), 0.35), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	v(model, "Dome", Vector3.new(3.2, 1.8, 3.2), at(0, 1.7, 0), kind.accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball, 0.25)
	v(model, "Straw", Vector3.new(2.6, 0.32, 0.32), at(0.65, 3.15, 0, 0, 0, -18), Color3.fromRGB(255, 110, 220), Enum.Material.Neon, Enum.PartType.Cylinder)
	v(model, "StrawTop", Vector3.new(0.42, 0.42, 0.42), at(1.05, 4.35, 0), Color3.fromRGB(255, 110, 220), Enum.Material.Neon, Enum.PartType.Ball)
	eyes(model, 0.35, 1.65, 0.62, 0.58)
	brows(model, 0.85, 1.7, 0.62, -18)
	v(model, "Mouth", Vector3.new(1.3, 0.22, 0.2), at(0, -0.15, 1.72), Color3.fromRGB(45, 20, 60))
	teeth(model, -0.02, 1.78, 4, 0.3)
	v(model, "ArmL", Vector3.new(0.22, 1.1, 0.22), at(-1.85, -0.5, 0.2, 0, 0, -55), kind.body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	v(model, "ArmR", Vector3.new(0.22, 1.1, 0.22), at(1.85, -0.4, 0.2, 0, 0, 55), kind.body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	v(model, "HandL", Vector3.new(0.65, 0.65, 0.65), at(-2.35, 0.2, 0.2), Color3.fromRGB(255, 240, 250), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	v(model, "HandR", Vector3.new(0.65, 0.65, 0.65), at(2.35, 0.3, 0.2), Color3.fromRGB(255, 240, 250), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	for i = -1, 1 do
		v(model, "Drip", Vector3.new(0.35, 0.55, 0.35), at(i * 0.75, -2.25, 1.1), kind.accent, Enum.Material.Neon, Enum.PartType.Ball)
	end
	v(model, "Cherry", Vector3.new(0.7, 0.7, 0.7), at(-0.6, 2.45, 0), Color3.fromRGB(255, 60, 90), Enum.Material.Neon, Enum.PartType.Ball)
end

local function buildShark(model: Model, kind: any, rarity: any)
	v(model, "Body", Vector3.new(3.6, 2.7, 2.7), at(0, 0, 0), kind.body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	v(model, "Belly", Vector3.new(2.8, 1.6, 1.6), at(0.1, -0.45, 0.55), Color3.fromRGB(245, 250, 255), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	v(model, "Snout", Vector3.new(1.7, 1.1, 1.1), at(2.0, 0.05, 0.15, 0, 0, 90), kind.body:Lerp(Color3.fromRGB(255, 255, 255), 0.15), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	v(model, "Nose", Vector3.new(0.85, 0.85, 0.85), at(2.9, 0.05, 0.15), kind.body:Lerp(Color3.fromRGB(255, 255, 255), 0.2), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	v(model, "TailA", Vector3.new(0.25, 1.8, 1.0), at(-2.0, 0.5, 0, 0, 0, -22), kind.body)
	v(model, "TailB", Vector3.new(0.25, 1.8, 1.0), at(-2.0, -0.5, 0, 0, 0, 22), kind.body)
	v(model, "Dorsal", Vector3.new(0.3, 1.9, 1.2), at(0, 1.85, 0, 0, 0, -8), kind.body)
	v(model, "FinL", Vector3.new(1.3, 0.25, 0.9), at(-0.2, -0.2, 1.8, 0, 22, -25), kind.body)
	v(model, "FinR", Vector3.new(1.3, 0.25, 0.9), at(-0.2, -0.2, -1.8, 0, -22, -25), kind.body)
	-- Side eyes with sunglasses.
	for _, sz in ipairs({ -1, 1 }) do
		v(model, "Eye", Vector3.new(0.7, 0.7, 0.7), at(0.95, 0.55, sz * 1.2), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		v(model, "Pupil", Vector3.new(0.32, 0.4, 0.3), at(0.95, 0.55, sz * 1.52), Color3.fromRGB(20, 18, 28), Enum.Material.Neon, Enum.PartType.Ball)
		v(model, "Shade", Vector3.new(1.15, 0.55, 0.14), at(1.05, 0.62, sz * 1.55, 0, 0, 0), Color3.fromRGB(15, 15, 22), Enum.Material.SmoothPlastic)
	end
	v(model, "ShadeBridge", Vector3.new(0.35, 0.16, 0.16), at(1.05, 0.62, 0), Color3.fromRGB(15, 15, 22))
	v(model, "Necklace", Vector3.new(0.5, 0.5, 0.5), at(0.2, 0.7, 1.35), Color3.fromRGB(255, 205, 60), Enum.Material.Neon, Enum.PartType.Ball)
	for i = 1, 5 do
		v(model, "Chain", Vector3.new(0.34, 0.34, 0.34), at(-0.3 + i * 0.16, 0.55 - i * 0.05, 1.48), Color3.fromRGB(255, 205, 60), Enum.Material.Neon, Enum.PartType.Ball)
	end
	-- Three sneakers, zero feet.
	local sneakers = {
		{ 1.1, -1.5, 0.8 },
		{ 0.3, -1.6, -0.85 },
		{ -1.5, -1.45, 0.9 },
	}
	for i, s in ipairs(sneakers) do
		v(model, "Sneaker" .. i, Vector3.new(1.3, 0.55, 0.75), at(s[1], s[2], s[3], 0, i * 25, 0), Color3.fromRGB(245, 245, 255))
		v(model, "Sole" .. i, Vector3.new(1.35, 0.16, 0.8), at(s[1], s[2] - 0.32, s[3], 0, i * 25, 0), kind.accent, Enum.Material.Neon)
		for j = 1, 3 do
			v(model, "Lace" .. i .. j, Vector3.new(0.7, 0.08, 0.06), at(s[1], s[2] + 0.25, s[3] + 0.12 + j * 0.06, 0, i * 25, 0), Color3.fromRGB(130, 130, 150))
		end
	end
end

local function buildBomb(model: Model, kind: any, rarity: any)
	v(model, "Bomb", Vector3.new(2.9, 2.9, 2.9), at(0, 0, 0), kind.body, Enum.Material.Metal, Enum.PartType.Ball)
	v(model, "Band", Vector3.new(0.4, 3.0, 3.0), at(0, -0.55, 0, 0, 0, 90), kind.accent, Enum.Material.Neon, Enum.PartType.Cylinder)
	v(model, "Fuse", Vector3.new(1.5, 0.26, 0.26), at(0.1, 2.05, 0, 0, 0, 26), Color3.fromRGB(150, 100, 55), Enum.Material.Wood, Enum.PartType.Cylinder)
	v(model, "Spark", Vector3.new(0.65, 0.65, 0.65), at(-0.3, 2.65, 0), Color3.fromRGB(255, 190, 50), Enum.Material.Neon, Enum.PartType.Ball)
	for _, sx in ipairs({ -1, 1 }) do
		v(model, "Wing", Vector3.new(2.9, 0.3, 1.9), at(sx * 2.65, 0.5, 0, 0, 0, sx * -16), Color3.fromRGB(235, 175, 70), Enum.Material.SmoothPlastic)
		v(model, "WaffleBar1", Vector3.new(2.9, 0.08, 0.16), at(sx * 2.65, 0.68, 0.45, 0, 0, sx * -16), Color3.fromRGB(150, 95, 30))
		v(model, "WaffleBar2", Vector3.new(2.9, 0.08, 0.16), at(sx * 2.65, 0.68, -0.4, 0, 0, sx * -16), Color3.fromRGB(150, 95, 30))
		v(model, "WaffleBar3", Vector3.new(0.16, 0.08, 1.9), at(sx * 2.1, 0.68, 0, 0, 0, sx * -16), Color3.fromRGB(150, 95, 30))
	end
	v(model, "CrocSnout", Vector3.new(2.0, 0.9, 1.8), at(0, 0.05, 1.7), kind.accent:Lerp(Color3.fromRGB(40, 170, 80), 0.55))
	v(model, "CrocUpper", Vector3.new(1.9, 0.4, 1.5), at(0, 0.45, 1.55), Color3.fromRGB(70, 185, 90))
	for i = 1, 5 do
		v(model, "Tooth", Vector3.new(0.25, 0.35, 0.2), at(-0.8 + i * 0.32, 0.15, 2.6), Color3.fromRGB(255, 255, 255))
	end
	for _, sx in ipairs({ -1, 1 }) do
		v(model, "Eye", Vector3.new(0.55, 0.55, 0.55), at(sx * 0.65, 0.85, 1.0), Color3.fromRGB(255, 240, 120), Enum.Material.Neon, Enum.PartType.Ball)
		v(model, "Pupil", Vector3.new(0.22, 0.35, 0.22), at(sx * 0.65, 0.85, 1.25), Color3.fromRGB(20, 18, 28), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	for i = 0, 2 do
		v(model, "Prop", Vector3.new(0.2, 0.2, 2.1), at(-1.65, 0.25, 0, 0, i * 60, 0), Color3.fromRGB(120, 220, 255), Enum.Material.Neon)
	end
	v(model, "PropHub", Vector3.new(0.5, 0.5, 0.5), at(-1.65, 0.25, 0), Color3.fromRGB(120, 220, 255), Enum.Material.Neon, Enum.PartType.Ball)
end

local function buildCactus(model: Model, kind: any, rarity: any)
	v(model, "Saucer", Vector3.new(0.28, 4.6, 4.6), at(0, -2.5, 0, 0, 0, 90), Color3.fromRGB(240, 236, 245), Enum.Material.Marble, Enum.PartType.Cylinder)
	v(model, "Cup", Vector3.new(2.6, 3.2, 3.2), at(0, -1.0, 0, 0, 0, 90), Color3.fromRGB(250, 246, 240), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	v(model, "HandleTop", Vector3.new(0.75, 0.22, 0.22), at(1.95, 0.1, 0, 0, 0, 0), Color3.fromRGB(250, 246, 240), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	v(model, "HandleSide", Vector3.new(0.75, 0.22, 0.22), at(2.3, -0.35, 0, 0, 0, 90), Color3.fromRGB(250, 246, 240), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	v(model, "HandleBottom", Vector3.new(0.75, 0.22, 0.22), at(1.95, -0.8, 0, 0, 0, 0), Color3.fromRGB(250, 246, 240), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	v(model, "Coffee", Vector3.new(0.2, 3.0, 3.0), at(0, 0.4, 0, 0, 0, 90), Color3.fromRGB(110, 70, 45), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	for i, pos in ipairs({
		Vector3.new(-0.9, 0.62, 0.4),
		Vector3.new(0.0, 0.7, -0.3),
		Vector3.new(0.9, 0.6, 0.3),
		Vector3.new(0.4, 0.72, 0.8),
	}) do
		v(model, "Foam" .. i, Vector3.new(1.1, 0.55, 1.1), at(pos.X, pos.Y, pos.Z), Color3.fromRGB(250, 240, 225), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	v(model, "CactusBody", Vector3.new(3.0, 1.15, 1.15), at(0, 1.65, 0, 0, 0, 90), kind.body, Enum.Material.Grass, Enum.PartType.Cylinder)
	v(model, "ArmL", Vector3.new(1.3, 0.65, 0.65), at(-1.35, 1.95, 0), kind.body, Enum.Material.Grass, Enum.PartType.Cylinder)
	v(model, "ArmLTip", Vector3.new(1.0, 0.65, 0.65), at(-1.9, 2.35, 0, 0, 0, 90), kind.body, Enum.Material.Grass, Enum.PartType.Cylinder)
	v(model, "ArmR", Vector3.new(1.1, 0.65, 0.65), at(1.3, 1.5, 0), kind.body, Enum.Material.Grass, Enum.PartType.Cylinder)
	v(model, "ArmRTip", Vector3.new(0.9, 0.65, 0.65), at(1.75, 1.9, 0, 0, 0, 90), kind.body, Enum.Material.Grass, Enum.PartType.Cylinder)
	v(model, "Flower", Vector3.new(1.05, 1.05, 1.05), at(-0.2, 3.05, 0), kind.accent, Enum.Material.Neon, Enum.PartType.Ball)
	v(model, "FlowerCore", Vector3.new(0.45, 0.45, 0.45), at(-0.2, 3.35, 0), Color3.fromRGB(255, 230, 100), Enum.Material.Neon, Enum.PartType.Ball)
	eyes(model, 1.85, 0.65, 0.32, 0.34)
	v(model, "Smile", Vector3.new(0.55, 0.12, 0.16), at(0, 1.5, 0.75), Color3.fromRGB(35, 70, 45))
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		v(model, "Spike", Vector3.new(0.16, 0.16, 0.16), at(math.cos(a) * 0.6, 1.65 + math.sin(a) * 0.55, 0.5), Color3.fromRGB(240, 240, 200), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
end

local function buildBanana(model: Model, kind: any, rarity: any)
	v(model, "Body", Vector3.new(2.5, 1.8, 1.8), at(0, 0, 0), kind.body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	v(model, "BodyFront", Vector3.new(1.9, 1.4, 1.4), at(1.45, 0.45, 0, 0, 0, 20), kind.body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	v(model, "BodyBack", Vector3.new(1.7, 1.3, 1.3), at(-1.4, -0.35, 0), kind.body:Lerp(Color3.fromRGB(210, 180, 40), 0.2), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	v(model, "Snout", Vector3.new(1.3, 0.7, 0.7), at(2.55, 0.55, 0, 0, 0, 90), kind.body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	v(model, "Nose", Vector3.new(0.6, 0.6, 0.6), at(3.2, 0.55, 0), kind.accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	v(model, "Dorsal", Vector3.new(0.25, 1.4, 0.9), at(0.4, 1.45, 0, 0, 0, -24), kind.accent)
	v(model, "TailTop", Vector3.new(0.25, 1.1, 0.85), at(-2.2, 0.45, 0, 0, 0, 28), kind.accent)
	v(model, "TailBottom", Vector3.new(0.25, 1.1, 0.85), at(-2.2, -0.3, 0, 0, 0, -28), kind.accent)
	for i = 0, 2 do
		v(model, "Peel", Vector3.new(0.25, 1.3, 0.8), at(-0.8 + i * 0.8, -1.45, 0.7, 0, i * 35, -12), kind.body:Lerp(Color3.fromRGB(255, 240, 140), 0.4))
	end
	v(model, "FinL", Vector3.new(1.0, 0.22, 0.8), at(0.2, -0.4, 1.55, 0, 22, -22), kind.accent)
	v(model, "FinR", Vector3.new(1.0, 0.22, 0.8), at(0.2, -0.4, -1.55, 0, -22, -22), kind.accent)
	for _, sz in ipairs({ -1, 1 }) do
		v(model, "Eye", Vector3.new(0.6, 0.6, 0.6), at(1.1, 0.6, sz * 0.9), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		v(model, "Pupil", Vector3.new(0.28, 0.32, 0.26), at(1.1, 0.6, sz * 1.16), Color3.fromRGB(20, 18, 28), Enum.Material.Neon, Enum.PartType.Ball)
		v(model, "Shade", Vector3.new(1.0, 0.5, 0.14), at(1.2, 0.66, sz * 1.2), Color3.fromRGB(15, 15, 22))
	end
	v(model, "ShadeBridge", Vector3.new(0.35, 0.16, 0.16), at(1.2, 0.66, 0), Color3.fromRGB(255, 205, 60), Enum.Material.Neon)
	for i = 1, 6 do
		v(model, "Chain", Vector3.new(0.34, 0.34, 0.34), at(0.2 + i * 0.12, 0.75 - i * 0.04, 1.2), Color3.fromRGB(255, 205, 60), Enum.Material.Neon, Enum.PartType.Ball)
	end
	-- A tiny gold crown for the one that rules the wild.
	for i = 0, 2 do
		v(model, "Crown", Vector3.new(0.35, 0.7, 0.35), at(-0.3 + i * 0.3, 2.1, 0, 0, 0, i % 2 == 0 and 18 or -18), Color3.fromRGB(255, 215, 70), Enum.Material.Neon)
	end
	v(model, "CrownBand", Vector3.new(1.3, 0.2, 0.3), at(0, 1.85, 0), Color3.fromRGB(255, 215, 70), Enum.Material.Neon)
end

local builders = {
	toilet = buildToilet,
	taco = buildTaco,
	fridge = buildFridge,
	shake = buildShake,
	shark = buildShark,
	bomb = buildBomb,
	cactus = buildCactus,
	banana = buildBanana,
}

local function buildModel(kind: any, rarity: any): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Brainrot_" .. kind.id
	model:SetAttribute("BrainrotKind", kind.name)
	model:SetAttribute("Rarity", kind.rarity)
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

	local builder = builders[kind.shape]
	if builder then
		builder(model, kind, rarity)
	else
		v(model, "FallbackBody", Vector3.new(2.5, 2.5, 2.5), at(0, 0, 0), kind.body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		eyes(model, 0.4, 1.2, 0.5, 0.5)
	end

	if rarity.value >= Config.RARITIES.Legendary.value then
		v(model, "Aura", Vector3.new(0.16, 4.8, 4.8), at(0, -2.5, 0, 0, 0, 90), rarity.color, Enum.Material.Neon, Enum.PartType.Cylinder, 0.42)
		local light = Instance.new("PointLight")
		light.Color = rarity.color
		light.Brightness = rarity.value >= Config.RARITIES.Mythic.value and 2.4 or 1.6
		light.Range = 16
		light.Parent = root
	end

	nameplate(model, root, kind, rarity)
	model.WorldPivot = root.CFrame
	return model, root
end

-- Spawning and state --------------------------------------------------------
local function randomWildPosition(): Vector3
	local center = Config.MAP.wildCenter
	return Vector3.new(
		center.X + (math.random() * 2 - 1) * (Config.MAP.wildHalfX - 7),
		center.Y,
		center.Z + (math.random() * 2 - 1) * (Config.MAP.wildHalfZ - 6)
	)
end

local function randomKind(): any
	local rarityName = Util.pickWeighted(Config.RARITY_ORDER, function(name)
		return Config.RARITIES[name].weight
	end)
	local options = {}
	for _, kind in ipairs(Config.BRAINROTS) do
		if kind.rarity == rarityName then
			table.insert(options, kind)
		end
	end
	if #options == 0 then
		return Config.BRAINROTS[1]
	end
	return options[math.random(#options)]
end

local function removeFromList(list: { any }, item: any)
	for i = #list, 1, -1 do
		if list[i] == item then
			table.remove(list, i)
		end
	end
end

local function updatePlayerAttributes(player: Player)
	if not player or not player.Parent then
		return
	end
	local carryCount = carried[player] and #carried[player] or 0
	local baseCount = placed[player] and #placed[player] or 0
	local income = 0
	if placed[player] then
		for _, rec in ipairs(placed[player]) do
			income += rec.rarity.value
		end
	end
	player:SetAttribute("Carried", carryCount)
	player:SetAttribute("Placed", baseCount)
	player:SetAttribute("IncomePerSec", income * deps.PlayerService.getMultiplier(player))
end

local function onTouched(record: any, hit: BasePart?)
	local player = Util.playerFromHit(hit)
	if not player then
		return
	end
	if record.state == "wild" then
		BrainrotService.attemptGrab(player, record)
	elseif record.state == "placed" and record.owner ~= player then
		deps.BaseService.trySteal(player, record)
	elseif record.state == "carried" and record.owner ~= player then
		deps.BaseService.tryStealCarried(player, record)
	end
end

function BrainrotService.spawnOne(kindOverride: any?, positionOverride: Vector3?): any
	local kind = kindOverride or randomKind()
	local rarity = Config.RARITIES[kind.rarity]
	local model, root = buildModel(kind, rarity)
	local position = positionOverride or randomWildPosition()
	local yaw = math.random() * math.pi * 2
	local cf = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	model:PivotTo(cf)
	model.Parent = brainrotFolder

	local record = {
		id = kind.id .. "_" .. tostring(math.random(100000, 999999)),
		kind = kind,
		rarity = rarity,
		model = model,
		root = root,
		state = "wild",
		owner = nil,
		basePos = position,
		target = randomWildPosition(),
		nextTarget = os.clock() + math.random(3, 7),
		yaw = yaw,
		phase = math.random() * math.pi * 2,
		slot = nil,
		baseCF = nil,
		carriedAt = 0,
	}
	table.insert(records, record)
	table.insert(wild, record)
	rootToRecord[root] = record
	root.Touched:Connect(function(hit)
		onTouched(record, hit)
	end)

	Util.fireAll(deps.Remotes.FX, {
		kind = "spawn",
		position = position,
		color = rarity.color,
	})
	return record
end

function BrainrotService.attemptGrab(player: Player, record: any)
	if not player or not player.Parent or not record then
		return false
	end
	if record.state ~= "wild" then
		return false
	end
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false
	end
	local list = carried[player]
	if not list then
		list = {}
		carried[player] = list
	end
	if #list >= Config.MAX_CARRIED then
		local now = os.clock()
		if (fullToastAt[player] or 0) < now then
			fullToastAt[player] = now + 2
			Util.toast(deps.Remotes, player, "Hands full (3/3). Run to your pad and bank them!", "bad", 3)
		end
		return false
	end

	removeFromList(wild, record)
	record.state = "carried"
	record.owner = player
	record.carriedAt = os.clock()
	record.basePos = nil
	table.insert(list, record)
	updatePlayerAttributes(player)
	deps.BaseService.refreshPad(player)

	Util.fireClient(deps.Remotes.FX, player, {
		kind = "grab",
		position = record.model:GetPivot().Position,
		color = record.rarity.color,
	})
	Util.toast(deps.Remotes, player, string.format("Grabbed %s (%s) • $%d/sec. Bank it at your pad!", record.kind.name, record.rarity.name, record.rarity.value), "good", 4)
	if record.rarity.value >= Config.RARITIES.Legendary.value then
		Util.broadcastToast(deps.Remotes, string.format("%s grabbed a %s %s!", player.DisplayName, record.rarity.name, record.kind.name), "legendary", 5)
	end
	return true
end

function BrainrotService.transferToCarried(record: any, thief: Player): boolean
	if not record or not thief or not thief.Parent then
		return false
	end
	if record.state == "placed" then
		local oldOwner = record.owner
		if oldOwner and placed[oldOwner] then
			removeFromList(placed[oldOwner], record)
			record.slot = nil
			record.baseCF = nil
			updatePlayerAttributes(oldOwner)
			deps.BaseService.refreshPad(oldOwner)
		end
	elseif record.state == "carried" then
		local oldOwner = record.owner
		if oldOwner and carried[oldOwner] then
			removeFromList(carried[oldOwner], record)
			updatePlayerAttributes(oldOwner)
		end
	elseif record.state == "wild" then
		removeFromList(wild, record)
	end

	local list = carried[thief]
	if not list then
		list = {}
		carried[thief] = list
	end
	record.state = "carried"
	record.owner = thief
	record.carriedAt = os.clock()
	record.basePos = nil
	record.slot = nil
	record.baseCF = nil
	table.insert(list, record)
	updatePlayerAttributes(thief)
	deps.BaseService.refreshPad(thief)
	return true
end

local function recordPlace(rec: any, player: Player, slot: number, slotCF: CFrame)
	rec.state = "placed"
	rec.owner = player
	rec.slot = slot
	rec.baseCF = slotCF
	rec.basePos = slotCF.Position
	rec.yaw = math.atan2(-slotCF.Position.X, -slotCF.Position.Z)
end

function BrainrotService.placeCarried(player: Player): number
	local list = carried[player]
	if not list or #list == 0 then
		return 0
	end
	local pad = deps.BaseService.getPad(player)
	if not pad then
		return 0
	end
	local occupied = {}
	local baseList = placed[player]
	if not baseList then
		baseList = {}
		placed[player] = baseList
	end
	for _, rec in ipairs(baseList) do
		if rec.slot then
			occupied[rec.slot] = true
		end
	end

	-- Iterate a copy: the carried list shrinks as each creature is banked.
	local moved = 0
	local copy = table.clone(list)
	for _, rec in ipairs(copy) do
		local slot = nil
		for i = 1, Config.MAX_BASE do
			if not occupied[i] then
				slot = i
				break
			end
		end
		if not slot then
			break
		end
		local slotCF = deps.BaseService.getSlotCFrame(player, slot)
		if slotCF then
			occupied[slot] = true
			removeFromList(list, rec)
			recordPlace(rec, player, slot, slotCF)
			table.insert(baseList, rec)
			moved += 1
		end
	end

	if #list > 0 then
		Util.toast(deps.Remotes, player, "Your base is full (8/8). Rebirth clears it for more!", "bad", 4)
	end
	updatePlayerAttributes(player)
	deps.BaseService.refreshPad(player)
	if moved > 0 then
		Util.fireClient(deps.Remotes.FX, player, {
			kind = "place",
			position = pad.center + Vector3.new(0, 4, 0),
			count = moved,
		})
	end
	return moved
end

function BrainrotService.getCarriedCount(player: Player): number
	local list = carried[player]
	return list and #list or 0
end

function BrainrotService.getPlacedCount(player: Player): number
	local list = placed[player]
	return list and #list or 0
end

function BrainrotService.getBaseIncome(player: Player): number
	local list = placed[player]
	if not list then
		return 0
	end
	local total = 0
	for _, rec in ipairs(list) do
		total += rec.rarity.value
	end
	return total
end

local function sendHome(record: any)
	record.state = "wild"
	record.owner = nil
	record.slot = nil
	record.baseCF = nil
	local pos = randomWildPosition()
	record.basePos = pos
	record.target = randomWildPosition()
	record.nextTarget = os.clock() + math.random(3, 7)
	record.yaw = math.random() * math.pi * 2
	if not table.find(wild, record) then
		table.insert(wild, record)
	end
	Util.fireAll(deps.Remotes.FX, {
		kind = "spawn",
		position = pos,
		color = record.rarity.color,
	})
end

function BrainrotService.dropCarriedToWild(player: Player, reason: string?): number
	local list = carried[player]
	if not list or #list == 0 then
		return 0
	end
	local dropped = 0
	local copy = table.clone(list)
	for _, rec in ipairs(copy) do
		removeFromList(list, rec)
		sendHome(rec)
		dropped += 1
	end
	updatePlayerAttributes(player)
	deps.BaseService.refreshPad(player)
	if dropped > 0 and player.Parent then
		if reason == "wave" then
			-- WaveService owns the dramatic message and the big shake.
			Util.fireClient(deps.Remotes.FX, player, { kind = "shake", strength = 1.1, duration = 0.55 })
		elseif reason == "death" then
			Util.toast(deps.Remotes, player, "You dropped your brainrots when you went down!", "bad", 4)
			Util.fireClient(deps.Remotes.FX, player, { kind = "shake", strength = 0.8, duration = 0.45 })
		else
			Util.toast(deps.Remotes, player, string.format("%d brainrot%s scattered back to the wild!", dropped, dropped == 1 and "" or "s"), "bad", 4)
			Util.fireClient(deps.Remotes.FX, player, { kind = "shake", strength = 0.8, duration = 0.45 })
		end
	end
	return dropped
end

function BrainrotService.clearBaseForRebirth(player: Player)
	local list = placed[player]
	if list then
		local copy = table.clone(list)
		for _, rec in ipairs(copy) do
			removeFromList(list, rec)
			sendHome(rec)
		end
	end
	if carried[player] then
		local copy = table.clone(carried[player])
		for _, rec in ipairs(copy) do
			removeFromList(carried[player], rec)
			sendHome(rec)
		end
	end
	updatePlayerAttributes(player)
	deps.BaseService.refreshPad(player)
end

function BrainrotService.releasePlayer(player: Player)
	if carried[player] then
		local copy = table.clone(carried[player])
		for _, rec in ipairs(copy) do
			removeFromList(carried[player], rec)
			sendHome(rec)
		end
	end
	if placed[player] then
		local copy = table.clone(placed[player])
		for _, rec in ipairs(copy) do
			removeFromList(placed[player], rec)
			sendHome(rec)
		end
	end
	carried[player] = nil
	placed[player] = nil
	incomeShown[player] = nil
	lastIncomeShownAt[player] = nil
	fullToastAt[player] = nil
	local conn = deathConnections[player]
	if conn then
		pcall(function()
			conn:Disconnect()
		end)
		deathConnections[player] = nil
	end
end

function BrainrotService.watchCharacter(player: Player, character: Model)
	local old = deathConnections[player]
	if old then
		pcall(function()
			old:Disconnect()
		end)
		deathConnections[player] = nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	deathConnections[player] = humanoid.Died:Connect(function()
		task.delay(0.25, function()
			if player.Parent then
				BrainrotService.dropCarriedToWild(player, "death")
			end
		end)
	end)
end

-- Movement loop -------------------------------------------------------------
local function pivotRecord(record: any, position: Vector3, yaw: number)
	if record.model.Parent then
		record.model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
	end
end

local function movementLoop()
	task.spawn(function()
		while true do
			local now = os.clock()
			for _, record in ipairs(records) do
				if record.model.Parent then
					if record.state == "wild" then
						if now >= record.nextTarget then
							record.target = randomWildPosition()
							record.nextTarget = now + math.random(4, 8)
						end
						local basePos = record.basePos or record.model:GetPivot().Position
						local flat = Vector3.new(record.target.X - basePos.X, 0, record.target.Z - basePos.Z)
						if flat.Magnitude > 0.35 then
							local step = math.min(3.6 * 0.09, flat.Magnitude)
							basePos = basePos + flat.Unit * step
							record.yaw = math.atan2(flat.X, flat.Z)
						end
						record.basePos = basePos
						local bob = math.sin(now * 2.3 + record.phase) * 0.32
						pivotRecord(record, basePos + Vector3.new(0, bob, 0), record.yaw)
					elseif record.state == "placed" then
						local cf = record.baseCF
						if cf then
							local bob = math.sin(now * 1.8 + record.phase) * 0.16
							pivotRecord(record, cf.Position + Vector3.new(0, bob, 0), record.yaw)
						end
					elseif record.state == "carried" then
						local owner = record.owner
						local character = owner and owner.Character
						local hrp = character and character:FindFirstChild("HumanoidRootPart")
						if owner and hrp and hrp:IsA("BasePart") then
							local list = carried[owner]
							local index = list and table.find(list, record) or 1
							local offsets = { -1.55, 0, 1.55 }
							local x = offsets[math.clamp(index, 1, 3)] or 0
							local bob = math.sin(now * 3 + record.phase) * 0.22
							local pos = hrp.Position + Vector3.new(x, 4.2 + index * 0.2, 0) + Vector3.new(0, bob, 0)
							local look = hrp.CFrame.LookVector
							local yaw = math.atan2(look.X, look.Z)
							pivotRecord(record, pos, yaw)
						else
							-- The carrier vanished: drop the brainrot rather than
							-- leaving it floating forever.
							if carried[owner] then
								removeFromList(carried[owner], record)
							end
							sendHome(record)
							if owner then
								updatePlayerAttributes(owner)
								deps.BaseService.refreshPad(owner)
							end
						end
					end
				end
			end
			task.wait(0.09)
		end
	end)
end

local function incomeLoop()
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for player, list in pairs(placed) do
				if player.Parent and #list > 0 then
					local perSecond = 0
					for _, rec in ipairs(list) do
						perSecond += rec.rarity.value
					end
					local multiplier = deps.PlayerService.getMultiplier(player)
					local amount = perSecond * multiplier
					if amount > 0 then
						deps.PlayerService.addCash(player, amount)
						incomeShown[player] = (incomeShown[player] or 0) + amount
						if now - (lastIncomeShownAt[player] or 0) >= 5 then
							lastIncomeShownAt[player] = now
							Util.fireClient(deps.Remotes.FX, player, {
								kind = "float",
								position = deps.BaseService.getPadCenter(player) + Vector3.new(0, 8, 0),
								text = "+$" .. Util.formatCash(incomeShown[player]),
								tone = "gold",
							})
							incomeShown[player] = 0
						end
					end
					player:SetAttribute("IncomePerSec", perSecond * multiplier)
				end
			end
		end
	end)
end

local function spawnLoop()
	task.spawn(function()
		while true do
			task.wait(Config.SPAWN_INTERVAL)
			if #wild < Config.MAX_WILD and #records < 40 then
				local ok = pcall(function()
					BrainrotService.spawnOne()
				end)
				if not ok then
					warn("BrainrotService: a wild spawn failed")
				end
			end
		end
	end)
end

function BrainrotService.init(services: any)
	deps = services
	Util = services.Util
	Config = services.Config

	local old = Workspace:FindFirstChild("Brainrots")
	if old then
		old:Destroy()
	end
	brainrotFolder = Instance.new("Folder")
	brainrotFolder.Name = "Brainrots"
	brainrotFolder.Parent = Workspace

	records = {}
	wild = {}
	carried = {}
	placed = {}
	rootToRecord = {}

	-- Seed the wild with the first six cast members so the world reads alive
	-- immediately; rarer ones join on the weighted spawn timer.
	for i = 1, math.min(6, #Config.BRAINROTS) do
		pcall(function()
			BrainrotService.spawnOne(Config.BRAINROTS[i])
		end)
	end

	incomeLoop()
	spawnLoop()
	movementLoop()
end

return BrainrotService
