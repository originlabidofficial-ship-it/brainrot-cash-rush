--!strict
-- Config: one place for every number the whole game shares. Server and client
-- both read it through ReplicatedStorage.Shared.Config, so the HUD's copy of
-- the rules (carry cap, rebirth price) can never drift from the server's.

local Config = {}

Config.GAME_NAME = "BRAINROT CASH RUSH"
Config.TAGLINE = "Grab them. Bank them. Rebirth before the wave."

-- Core loop tuning ---------------------------------------------------------
Config.MAX_WILD = 9
Config.SPAWN_INTERVAL = 6
Config.MAX_CARRIED = 3
Config.MAX_BASE = 8
Config.WAVE_INTERVAL = 90
Config.WAVE_WARN = 5
Config.WAVE_DURATION = 13
Config.STEAL_COOLDOWN = 3
Config.GUARD_RADIUS = 19
Config.REBIRTH_COST = 500
Config.REBIRTH_BONUS = 0.25
Config.INCOME_INTERVAL = 1

-- Rarities -----------------------------------------------------------------
-- value is cash per second for one placed brainrot of that rarity.
Config.RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

Config.RARITIES = {
	Common = {
		name = "Common",
		value = 1,
		color = Color3.fromRGB(205, 220, 238),
		glow = Color3.fromRGB(130, 180, 230),
		weight = 45,
	},
	Rare = {
		name = "Rare",
		value = 3,
		color = Color3.fromRGB(90, 205, 255),
		glow = Color3.fromRGB(60, 160, 255),
		weight = 28,
	},
	Epic = {
		name = "Epic",
		value = 8,
		color = Color3.fromRGB(195, 115, 255),
		glow = Color3.fromRGB(150, 60, 255),
		weight = 17,
	},
	Legendary = {
		name = "Legendary",
		value = 25,
		color = Color3.fromRGB(255, 195, 65),
		glow = Color3.fromRGB(255, 150, 20),
		weight = 8,
	},
	Mythic = {
		name = "Mythic",
		value = 90,
		color = Color3.fromRGB(255, 85, 175),
		glow = Color3.fromRGB(255, 20, 140),
		weight = 2,
	},
}

-- The cast: eight absurd little creatures, each built from primitive parts by
-- BrainrotService. body/accent are the paint colours; quip is the nameplate
-- joke line the HUD and Billboards show.
Config.BRAINROTS = {
	{
		id = "toiletto",
		name = "Toiletto Tornado",
		rarity = "Common",
		shape = "toilet",
		body = Color3.fromRGB(245, 248, 255),
		accent = Color3.fromRGB(70, 200, 255),
		quip = "Flushes at 300 RPM.",
	},
	{
		id = "taco",
		name = "Taco Tuesday Rex",
		rarity = "Common",
		shape = "taco",
		body = Color3.fromRGB(246, 191, 72),
		accent = Color3.fromRGB(90, 205, 95),
		quip = "It is always Tuesday somewhere.",
	},
	{
		id = "fridge",
		name = "Refrigerator Rhino",
		rarity = "Rare",
		shape = "fridge",
		body = Color3.fromRGB(226, 236, 244),
		accent = Color3.fromRGB(120, 195, 255),
		quip = "Keeps the milk cold. Keeps grudges colder.",
	},
	{
		id = "shake",
		name = "Grimble Shake",
		rarity = "Rare",
		shape = "shake",
		body = Color3.fromRGB(152, 66, 224),
		accent = Color3.fromRGB(255, 120, 222),
		quip = "Brain freeze, but make it evil.",
	},
	{
		id = "shark",
		name = "Sharkuza Sneakerino",
		rarity = "Epic",
		shape = "shark",
		body = Color3.fromRGB(64, 139, 232),
		accent = Color3.fromRGB(250, 250, 255),
		quip = "Three sneakers, zero feet.",
	},
	{
		id = "bomb",
		name = "Bombardino Wafflini",
		rarity = "Epic",
		shape = "bomb",
		body = Color3.fromRGB(60, 62, 82),
		accent = Color3.fromRGB(255, 172, 45),
		quip = "Explodes into breakfast.",
	},
	{
		id = "cactus",
		name = "Cactus Cappuccino",
		rarity = "Legendary",
		shape = "cactus",
		body = Color3.fromRGB(92, 196, 122),
		accent = Color3.fromRGB(255, 128, 194),
		quip = "Prickly on the outside, foamy inside.",
	},
	{
		id = "banana",
		name = "Bananita Dolphinita",
		rarity = "Mythic",
		shape = "banana",
		body = Color3.fromRGB(252, 220, 74),
		accent = Color3.fromRGB(255, 199, 32),
		quip = "Delphine with a peel. Legally a fruit.",
	},
}

-- Map layout (studs) -------------------------------------------------------
Config.MAP = {
	arenaSize = 250,
	arenaHalf = 125,
	plazaRadius = 30,
	baseRadius = 58,
	wildCenter = Vector3.new(0, 7.5, -94),
	wildHalfX = 46,
	wildHalfZ = 19,
	wildTop = 3.6,
	spawnPos = Vector3.new(0, 3, 94),
	padRadius = 17,
	palette = {
		Color3.fromRGB(66, 222, 190),
		Color3.fromRGB(255, 148, 72),
		Color3.fromRGB(188, 120, 255),
		Color3.fromRGB(255, 108, 170),
		Color3.fromRGB(152, 230, 82),
		Color3.fromRGB(88, 170, 255),
		Color3.fromRGB(255, 220, 80),
		Color3.fromRGB(90, 235, 140),
	},
}

-- Remote names, created once by Main.server.luau.
Config.REMOTES = {
	Rebirth = "Rebirth",
	FX = "FX",
}

return Config
