--!strict
-- Config — the single source of truth for tuning.
--
-- Every number a player can feel (carry cap, spawn rate, wave timing, steal
-- cooldown, prices, rewards, map coordinates) lives here exactly once. The
-- server requires this module through ReplicatedStorage.Shared.Config and the
-- client does the same, so the HUD can never quote a price the server will
-- refuse. Services are not allowed to hard-code gameplay numbers: if a value
-- matters to the player it belongs in this file.

local Config = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Identity ------------------------------------------------------------------
Config.GAME_NAME = "BRAINROT CASH RUSH"
Config.TAGLINE = "Grab them. Bank them. Upgrade. Rebirth before the wave."
Config.VERSION = "2.0"

-- Core loop ---------------------------------------------------------------
-- MAX_WILD        how many wild creatures may roam at once
-- SPAWN_INTERVAL  seconds between wild spawn attempts
-- MAX_RECORDS     hard ceiling on live creature models (memory guard)
-- WILD_SEED       creatures placed immediately when the server boots
Config.MAX_WILD = 10
Config.SPAWN_INTERVAL = 5
Config.MAX_RECORDS = 40
Config.WILD_SEED = 8

Config.MAX_CARRIED = 3          -- backpack size before the Carry Cap upgrade
Config.MAX_BASE = 8             -- usable pad slots before the Pad Slots upgrade
Config.MAX_BASE_SLOTS = 16      -- slots physically built on every deck
Config.MAX_UPGRADE_LEVEL = 5    -- levels per shop track
Config.PAD_COUNT = 6            -- home decks placed around the plaza

Config.INCOME_INTERVAL = 1      -- seconds between income payments
Config.INCOME_FLOAT_EVERY = 5   -- seconds between "+$" popups over a base
Config.SAVE_INTERVAL = 60       -- autosave cadence

Config.STEAL_COOLDOWN = 3       -- seconds between successful steals per thief
Config.STEAL_GRACE = 1.6        -- a freshly grabbed creature cannot be stolen
Config.GUARD_RADIUS = 19        -- safe radius before the Guard Range upgrade
Config.REBIRTH_COST = 500
Config.REBIRTH_BONUS = 0.25     -- +25% cash per rebirth, permanent

-- Waves --------------------------------------------------------------------
Config.WAVE_INTERVAL = 90       -- seconds between waves
Config.WAVE_WARN = 5            -- warning lead time
Config.WAVE_DURATION = 13       -- seconds the wall takes to cross the arena
Config.WAVE_SEGMENTS = 18       -- wall segments (each ~13.8 studs wide)
Config.WAVE_SPEED_STEP = 0.05   -- seconds between wall position updates

-- Motion -------------------------------------------------------------------
Config.MOVEMENT_TICK = 0.09     -- creature animation step
Config.WILD_SPEED = 3.6         -- studs per second while wandering
Config.WILD_BOB = 0.32
Config.PLACED_BOB = 0.16
Config.CARRY_BOB = 0.22
Config.CARRY_HEIGHT = 4.2       -- how high carried creatures float
Config.CARRY_STACK = 0.2        -- extra height per carried creature
Config.MAGNET_TICK = 0.4        -- magnet scan cadence
Config.SNAP_DISTANCE = 3        -- drift before a banked model is re-seated

-- Anti-spam limits (seconds) ----------------------------------------------
-- Applied server-side on every remote a client may fire.
Config.LIMITS = {
	shopBuy = 0.4,
	questClaim = 0.8,
	rebirth = 2.0,
	tutorial = 0.5,
}

-- Toast durations ----------------------------------------------------------
Config.TOAST = {
	short = 3,
	normal = 4,
	long = 5,
	welcome = 7,
	rebirth = 6,
	full = 2, -- cooldown between repeated "hands full" toasts
}

-- Rarities -----------------------------------------------------------------
-- value is cash per second for one banked creature of that rarity; weight is
-- the relative spawn chance used by Util.pickWeighted.
Config.RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

Config.RARITIES = {
	Common = { name = "Common", value = 1, color = rgb(205, 220, 238), glow = rgb(130, 180, 230), weight = 44 },
	Rare = { name = "Rare", value = 3, color = rgb(90, 205, 255), glow = rgb(60, 160, 255), weight = 28 },
	Epic = { name = "Epic", value = 8, color = rgb(195, 115, 255), glow = rgb(150, 60, 255), weight = 17 },
	Legendary = { name = "Legendary", value = 25, color = rgb(255, 195, 65), glow = rgb(255, 150, 20), weight = 8 },
	Mythic = { name = "Mythic", value = 90, color = rgb(255, 85, 175), glow = rgb(255, 20, 140), weight = 3 },
}

-- The cast. Written compactly as {id, name, rarity, shape, body, accent, quip}
-- and expanded below into the table every service reads, so adding a creature
-- is a single row here plus one shape recipe in BrainrotService.
local CAST = {
	{ "toiletto", "Toiletto Tornado", "Common", "toilet", { 245, 248, 255 }, { 70, 200, 255 }, "Flushes at 300 RPM." },
	{ "taco", "Taco Tuesday Rex", "Common", "taco", { 246, 191, 72 }, { 90, 205, 95 }, "It is always Tuesday somewhere." },
	{ "phone", "Phonealicious Rex", "Common", "phone", { 36, 40, 58 }, { 110, 255, 180 }, "Three bars, zero signal, infinite lore." },
	{ "duck", "Duck Norris", "Common", "duck", { 255, 220, 70 }, { 255, 140, 40 }, "Quacks first. Asks questions never." },
	{ "cheese", "Cheddar Cheeseus", "Common", "cheese", { 255, 215, 70 }, { 255, 160, 35 }, "Aged four years, mostly in the sun." },
	{ "sock", "Sockrates", "Common", "sock", { 245, 130, 190 }, { 90, 230, 255 }, "Knows exactly where your other sock went." },
	{ "fridge", "Refrigerator Rhino", "Rare", "fridge", { 226, 236, 244 }, { 120, 195, 255 }, "Keeps the milk cold. Keeps grudges colder." },
	{ "shake", "Grimble Shake", "Rare", "shake", { 152, 66, 224 }, { 255, 120, 222 }, "Brain freeze, but make it evil." },
	{ "pizza", "Pizza the Hut", "Rare", "pizza", { 245, 190, 95 }, { 230, 65, 55 }, "Delivers in thirty minutes or less, emotionally." },
	{ "worm", "Wyrmothy", "Rare", "worm", { 250, 165, 195 }, { 120, 240, 170 }, "Six segments, one brain cell, all vibes." },
	{ "donut", "Donutello", "Rare", "donut", { 255, 175, 210 }, { 255, 245, 180 }, "The hole is where the rent money went." },
	{ "shark", "Sharkuza Sneakerino", "Epic", "shark", { 64, 139, 232 }, { 250, 250, 255 }, "Three sneakers, zero feet." },
	{ "bomb", "Bombardino Wafflini", "Epic", "bomb", { 60, 62, 82 }, { 255, 172, 45 }, "Explodes into breakfast." },
	{ "crab", "Crabby McCrabface", "Epic", "crab", { 242, 92, 82 }, { 255, 205, 80 }, "Pinches pockets, not claws." },
	{ "balloon", "Balloonicus", "Epic", "balloon", { 255, 105, 165 }, { 255, 240, 250 }, "One sharp idea away from retirement." },
	{ "cactus", "Cactus Cappuccino", "Legendary", "cactus", { 92, 196, 122 }, { 255, 128, 194 }, "Prickly on the outside, foamy inside." },
	{ "ghost", "Ghosteato", "Legendary", "ghost", { 225, 240, 255 }, { 130, 100, 255 }, "Boo-ries its savings in your base." },
	{ "skull", "Skullius Maximus", "Legendary", "skull", { 238, 234, 225 }, { 255, 90, 120 }, "All bone, no body, full confidence." },
	{ "robot", "Robo Brainrot 9000", "Legendary", "robot", { 160, 178, 198 }, { 80, 255, 200 }, "Beep boop, your cash is now mine." },
	{ "banana", "Bananita Dolphinita", "Mythic", "banana", { 252, 220, 74 }, { 255, 199, 32 }, "Delphine with a peel. Legally a fruit." },
	{ "dragon", "Dragonfruitius", "Mythic", "dragon", { 255, 80, 150 }, { 110, 240, 170 }, "Breathes glitter. Hoards tip jars." },
	{ "cat", "Cattus Supreme", "Mythic", "cat", { 80, 90, 130 }, { 255, 220, 90 }, "Knocks your whole base off the shelf." },
}

Config.BRAINROTS = {}
for _, row in ipairs(CAST) do
	table.insert(Config.BRAINROTS, {
		id = row[1],
		name = row[2],
		rarity = row[3],
		shape = row[4],
		body = rgb(row[5][1], row[5][2], row[5][3]),
		accent = rgb(row[6][1], row[6][2], row[6][3]),
		quip = row[7],
	})
end
Config.CAST_SIZE = #Config.BRAINROTS

-- Shop tracks --------------------------------------------------------------
-- Effect at level L is base + perLevel * L. prices[L] is the cost of level L.
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
		unit = "",
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
		unit = "",
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
		unit = "x",
	},
	{
		key = "GuardRange",
		name = "Guard Range",
		icon = "🛡️",
		blurb = "+3.5 studs of safe base radius per level",
		base = Config.GUARD_RADIUS,
		perLevel = 3.5,
		prices = { 200, 500, 1100, 2200, 4000 },
		effectLabel = "STUDS",
		unit = " studs",
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
		unit = "",
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
		unit = " studs",
	},
}

-- Quests -------------------------------------------------------------------
Config.QUEST_SLOTS = 3

Config.QUESTS = {
	{ id = "capture_5", event = "capture", goal = 5, name = "Catch 5 brainrots", reward = 120 },
	{ id = "capture_15", event = "capture", goal = 15, name = "Catch 15 brainrots", reward = 380 },
	{ id = "bank_10", event = "bank", goal = 10, name = "Bank 10 brainrots", reward = 200 },
	{ id = "bank_30", event = "bank", goal = 30, name = "Bank 30 brainrots", reward = 600 },
	{ id = "wave_3", event = "wave", goal = 3, name = "Survive 3 waves", reward = 500 },
	{ id = "steal_5", event = "steal", goal = 5, name = "Steal 5 brainrots", reward = 450 },
	{ id = "rebirth_2", event = "rebirth", goal = 2, name = "Rebirth twice", reward = 800 },
}

-- Tutorial -----------------------------------------------------------------
-- Order matters: the HUD shows these as a checklist and the server ticks them
-- from real events only. `event` is what OnboardingService.progress() accepts.
Config.TUTORIAL = {
	{ key = "move", label = "Move around the plaza", event = "move" },
	{ key = "grab", label = "Grab a wild brainrot", event = "grab" },
	{ key = "bank", label = "Bank it on your base pad", event = "bank" },
	{ key = "index", label = "Open the Brainrot Index (E)", event = "index" },
	{ key = "rebirth", label = "Rebirth once ($500)", event = "rebirth" },
}
Config.TUTORIAL_MOVE_STUDS = 14 -- distance from spawn that counts as "moved"

-- Leaderboard --------------------------------------------------------------
Config.LEADERBOARD_ROWS = 10
Config.LEADERBOARD_REFRESH = 6   -- seconds between board/HUD refreshes
Config.LEADERBOARD_MIN_GAP = 1   -- minimum seconds between two pushes

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
		rgb(66, 222, 190),
		rgb(255, 148, 72),
		rgb(188, 120, 255),
		rgb(255, 108, 170),
		rgb(152, 230, 82),
		rgb(88, 170, 255),
		rgb(255, 220, 80),
		rgb(90, 235, 140),
	},
}

-- Remotes ------------------------------------------------------------------
-- Main.server.luau creates exactly these names once. The client may fire
-- Rebirth, ShopBuy, QuestClaim and TutorialAction; FX, State and Leaderboard
-- are server-to-client pushes only.
Config.REMOTES = {
	Rebirth = "Rebirth",
	FX = "FX",
	ShopBuy = "ShopBuy",
	QuestClaim = "QuestClaim",
	TutorialAction = "TutorialAction",
	State = "State",
	Leaderboard = "Leaderboard",
}

-- UI palette shared by the HUD so text stays readable on a bright map ------
Config.UI = {
	panel = rgb(18, 16, 30),
	panelLight = rgb(32, 29, 48),
	text = rgb(246, 246, 255),
	textDim = rgb(186, 190, 210),
	gold = rgb(255, 211, 74),
	cyan = rgb(86, 231, 255),
	pink = rgb(255, 92, 202),
	green = rgb(92, 242, 168),
	red = rgb(255, 70, 100),
	white = rgb(255, 255, 255),
}

return Config
