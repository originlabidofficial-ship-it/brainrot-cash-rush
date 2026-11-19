--!strict
-- Config: one place for every number the whole game shares. Server and client
-- both read it through ReplicatedStorage.Shared.Config, so the HUD's copy of
-- the rules (carry cap, upgrade prices, quest rewards) can never drift from
-- the server's authoritative copy.

local Config = {}

Config.GAME_NAME = "BRAINROT CASH RUSH"
Config.TAGLINE = "Grab them. Bank them. Upgrade. Rebirth before the wave."

-- Core loop tuning ---------------------------------------------------------
Config.MAX_WILD = 10
Config.SPAWN_INTERVAL = 5
Config.MAX_CARRIED = 3 -- base carry cap before the Carry Cap upgrade
Config.MAX_BASE = 8 -- base pad slots before the Pad Slots upgrade
Config.MAX_BASE_SLOTS = 16 -- physical slots built on every deck
Config.WAVE_INTERVAL = 90
Config.WAVE_WARN = 5
Config.WAVE_DURATION = 13
Config.STEAL_COOLDOWN = 3
Config.GUARD_RADIUS = 19 -- base guard radius before the Guard Range upgrade
Config.REBIRTH_COST = 500
Config.REBIRTH_BONUS = 0.25
Config.INCOME_INTERVAL = 1
Config.SAVE_INTERVAL = 60

-- Rarities -----------------------------------------------------------------
-- value is cash per second for one placed brainrot of that rarity.
Config.RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

Config.RARITIES = {
	Common = {
		name = "Common",
		value = 1,
		color = Color3.fromRGB(205, 220, 238),
		glow = Color3.fromRGB(130, 180, 230),
		weight = 44,
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
		weight = 3,
	},
}

-- The cast: 22 absurd creatures, each built from primitive parts by its own
-- builder in BrainrotService. body/accent are the paint colours; quip is the
-- one-line joke the nameplate, index and capture toast show.
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
		id = "phone",
		name = "Phonealicious Rex",
		rarity = "Common",
		shape = "phone",
		body = Color3.fromRGB(36, 40, 58),
		accent = Color3.fromRGB(110, 255, 180),
		quip = "Three bars, zero signal, infinite lore.",
	},
	{
		id = "duck",
		name = "Duck Norris",
		rarity = "Common",
		shape = "duck",
		body = Color3.fromRGB(255, 220, 70),
		accent = Color3.fromRGB(255, 140, 40),
		quip = "Quacks first. Asks questions never.",
	},
	{
		id = "cheese",
		name = "Cheddar Cheeseus",
		rarity = "Common",
		shape = "cheese",
		body = Color3.fromRGB(255, 215, 70),
		accent = Color3.fromRGB(255, 160, 35),
		quip = "Aged four years, mostly in the sun.",
	},
	{
		id = "sock",
		name = "Sockrates",
		rarity = "Common",
		shape = "sock",
		body = Color3.fromRGB(245, 130, 190),
		accent = Color3.fromRGB(90, 230, 255),
		quip = "Knows exactly where your other sock went.",
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
		id = "pizza",
		name = "Pizza the Hut",
		rarity = "Rare",
		shape = "pizza",
		body = Color3.fromRGB(245, 190, 95),
		accent = Color3.fromRGB(230, 65, 55),
		quip = "Delivers in thirty minutes or less, emotionally.",
	},
	{
		id = "worm",
		name = "Wyrmothy",
		rarity = "Rare",
		shape = "worm",
		body = Color3.fromRGB(250, 165, 195),
		accent = Color3.fromRGB(120, 240, 170),
		quip = "Six segments, one brain cell, all vibes.",
	},
	{
		id = "donut",
		name = "Donutello",
		rarity = "Rare",
		shape = "donut",
		body = Color3.fromRGB(255, 175, 210),
		accent = Color3.fromRGB(255, 245, 180),
		quip = "The hole is where the rent money went.",
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
		id = "crab",
		name = "Crabby McCrabface",
		rarity = "Epic",
		shape = "crab",
		body = Color3.fromRGB(242, 92, 82),
		accent = Color3.fromRGB(255, 205, 80),
		quip = "Pinches pockets, not claws.",
	},
	{
		id = "balloon",
		name = "Balloonicus",
		rarity = "Epic",
		shape = "balloon",
		body = Color3.fromRGB(255, 105, 165),
		accent = Color3.fromRGB(255, 240, 250),
		quip = "One sharp idea away from retirement.",
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
		id = "ghost",
		name = "Ghosteato",
		rarity = "Legendary",
		shape = "ghost",
		body = Color3.fromRGB(225, 240, 255),
		accent = Color3.fromRGB(130, 100, 255),
		quip = "Boo-ries its savings in your base.",
	},
	{
		id = "skull",
		name = "Skullius Maximus",
		rarity = "Legendary",
		shape = "skull",
		body = Color3.fromRGB(238, 234, 225),
		accent = Color3.fromRGB(255, 90, 120),
		quip = "All bone, no body, full confidence.",
	},
	{
		id = "robot",
		name = "Robo Brainrot 9000",
		rarity = "Legendary",
		shape = "robot",
		body = Color3.fromRGB(160, 178, 198),
		accent = Color3.fromRGB(80, 255, 200),
		quip = "Beep boop, your cash is now mine.",
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
	{
		id = "dragon",
		name = "Dragonfruitius",
		rarity = "Mythic",
		shape = "dragon",
		body = Color3.fromRGB(255, 80, 150),
		accent = Color3.fromRGB(110, 240, 170),
		quip = "Breathes glitter. Hoards tip jars.",
	},
	{
		id = "cat",
		name = "Cattus Supreme",
		rarity = "Mythic",
		shape = "cat",
		body = Color3.fromRGB(80, 90, 130),
		accent = Color3.fromRGB(255, 220, 90),
		quip = "Knocks your whole base off the shelf.",
	},
}

-- Six permanent upgrade tracks, five levels each. Prices are paid in cash and
-- rise every level. base + perLevel * level is the server-side effect.
Config.UPGRADES = {
	{
		key = "CarryCap",
		name = "Carry Cap",
		icon = "🎒",
		blurb = "+1 brainrot carried per level",
		base = Config.MAX_CARRIED,
		perLevel = 1,
		prices = { 150, 400, 900, 1800, 3200 },
		effectLabel = "CARRIED",
	},
	{
		key = "PadSlots",
		name = "Pad Slots",
		icon = "🏠",
		blurb = "Grow the pad from 8 to 16 display slots",
		base = Config.MAX_BASE,
		perLevel = 1.6,
		prices = { 250, 650, 1400, 2600, 4500 },
		effectLabel = "SLOTS",
	},
	{
		key = "Income",
		name = "Income",
		icon = "💸",
		blurb = "+10% on all banked income per level",
		base = 1,
		perLevel = 0.10,
		prices = { 300, 750, 1600, 3000, 5200 },
		effectLabel = "MULTIPLIER",
	},
	{
		key = "GuardRange",
		name = "Guard Range",
		icon = "🛡️",
		blurb = "+3.5 studs of safe base radius per level",
		base = 19,
		perLevel = 3.5,
		prices = { 200, 500, 1100, 2200, 4000 },
		effectLabel = "STUDS",
	},
	{
		key = "Speed",
		name = "Speed",
		icon = "⚡",
		blurb = "+2 walkspeed per level",
		base = 16,
		perLevel = 2,
		prices = { 180, 450, 1000, 2000, 3600 },
		effectLabel = "WALKSPEED",
	},
	{
		key = "Magnet",
		name = "Magnet",
		icon = "🧲",
		blurb = "Auto-collect wild brainrots in radius",
		base = 0,
		perLevel = 6,
		prices = { 350, 850, 1700, 3200, 5500 },
		effectLabel = "STUDS",
	},
}

-- Three of these rotate into every player's quest log. Progress is driven by
-- real server events only; rewards are paid by QuestService on a valid claim.
Config.QUESTS = {
	{ id = "capture_5", event = "capture", goal = 5, name = "Catch 5 brainrots", reward = 120 },
	{ id = "capture_15", event = "capture", goal = 15, name = "Catch 15 brainrots", reward = 380 },
	{ id = "bank_10", event = "bank", goal = 10, name = "Bank 10 brainrots", reward = 200 },
	{ id = "bank_30", event = "bank", goal = 30, name = "Bank 30 brainrots", reward = 600 },
	{ id = "wave_3", event = "wave", goal = 3, name = "Survive 3 waves", reward = 500 },
	{ id = "steal_5", event = "steal", goal = 5, name = "Steal 5 brainrots", reward = 450 },
	{ id = "rebirth_2", event = "rebirth", goal = 2, name = "Rebirth twice", reward = 800 },
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
	dockCenter = Vector3.new(101, 0, -8),
	shopPos = Vector3.new(-42, 0, 78),
	boardPos = Vector3.new(42, 0, 78),
	vaultPos = Vector3.new(72, 0, -38),
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

-- Remote names, created once by Main.server.luau. The client only sends
-- ShopBuy, QuestClaim, TutorialAction and Rebirth; the other two are pushed
-- from the server (FX one-way effects, State and Leaderboard snapshots).
Config.REMOTES = {
	Rebirth = "Rebirth",
	FX = "FX",
	ShopBuy = "ShopBuy",
	QuestClaim = "QuestClaim",
	TutorialAction = "TutorialAction",
	State = "State",
	Leaderboard = "Leaderboard",
}

return Config
