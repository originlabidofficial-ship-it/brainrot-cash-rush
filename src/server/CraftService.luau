--!strict
-- CraftService -- three same-rarity banked brainrots become one of the next
-- rarity. All work is server-side: the player must be standing on their own
-- deck, must own at least Config.CRAFT_COUNT banked creatures of the requested
-- rarity, and every request passes type, range and 2-second cooldown checks.
-- The winner is deterministic from the player's craft sequence (never a client
-- choice), the three sources are consumed, and the result is seated in the
-- first freed slot. Mythic is the cap.

local CraftService = {}

local Config: any = nil
local Util: any = nil
local deps: any = nil

local state = {
	running = false,
	lastCraftAt = {} :: { [Player]: number },
	craftSerial = {} :: { [Player]: number },
	connection = nil :: RBXScriptConnection?,
}

local function alive(player: Player?): boolean
	return player ~= nil and player.Parent ~= nil
end

local function onOwnPad(player: Player): boolean
	local pad = deps.BaseService.getPad(player)
	if not pad then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return Util.flatDistance(root.Position, pad.center) <= Config.MAP.padRadius
end

local function candidatesFor(rarityName: string): { any }
	local pool = {}
	for _, kind in ipairs(Config.BRAINROTS) do
		if kind.rarity == rarityName then
			table.insert(pool, kind)
		end
	end
	return pool
end

-- Deterministic, not random: the same player at the same craft count always
-- gets the same next species, so the HUD preview cannot lie.
local function nextKind(player: Player, sourceRarity: string): any
	local sourceIndex = table.find(Config.RARITY_ORDER, sourceRarity)
	local targetRarity = sourceIndex and Config.RARITY_ORDER[sourceIndex + 1]
	if not targetRarity then
		return nil
	end
	local pool = candidatesFor(targetRarity)
	if #pool == 0 then
		return nil
	end
	local serial = (state.craftSerial[player] or 0) + 1
	local seed = (math.floor(player.UserId / 7) + serial * 13) % #pool
	return pool[seed + 1]
end

function CraftService.preview(player: Player): any
	local entries = {}
	local maxSource = math.min(Config.CRAFT_ENABLED_RARITIES, #Config.RARITY_ORDER - 1)
	for index = 1, maxSource do
		local source = Config.RARITY_ORDER[index]
		local target = Config.RARITY_ORDER[index + 1]
		local count = deps.BrainrotService.countBankedRarity(player, source)
		local result = nextKind(player, source)
		table.insert(entries, {
			source = source,
			target = target,
			count = count,
			required = Config.CRAFT_COUNT,
			ready = count >= Config.CRAFT_COUNT,
			resultName = result and result.name or nil,
			resultRarity = target,
		})
	end
	return {
		onPad = onOwnPad(player),
		required = Config.CRAFT_COUNT,
		cooldown = Config.LIMITS.craft,
		entries = entries,
	}
end

function CraftService.tryCraft(player: Player, rarityName: any)
	if not alive(player) or not state.running then
		return
	end
	-- Type and length first: this is the only client-provided value.
	if type(rarityName) ~= "string" or #rarityName == 0 or #rarityName > 16 then
		return
	end
	local sourceIndex = table.find(Config.RARITY_ORDER, rarityName)
	if not sourceIndex or sourceIndex >= #Config.RARITY_ORDER then
		if sourceIndex == #Config.RARITY_ORDER then
			Util.toast(deps.Remotes, player, "Mythic is the crafting cap.", "info", Config.TOAST.short)
		end
		return
	end

	local now = os.clock()
	if now - (state.lastCraftAt[player] or 0) < Config.LIMITS.craft then
		return
	end
	state.lastCraftAt[player] = now

	if not onOwnPad(player) then
		Util.toast(deps.Remotes, player, "Stand on your own pad to craft.", "bad", Config.TOAST.short)
		return
	end
	local count = deps.BrainrotService.countBankedRarity(player, rarityName)
	if count < Config.CRAFT_COUNT then
		Util.toast(deps.Remotes, player, string.format("Crafting needs %d banked %s brainrots (%d/%d).", Config.CRAFT_COUNT, rarityName, count, Config.CRAFT_COUNT), "info", Config.TOAST.normal)
		return
	end

	local resultKind = nextKind(player, rarityName)
	if not resultKind then
		Util.toast(deps.Remotes, player, "No creature is available for that recipe.", "bad", Config.TOAST.short)
		return
	end
	local ok, record = pcall(deps.BrainrotService.craftBanked, player, rarityName, resultKind)
	if not ok then
		warn("[CraftService] craft failed: " .. tostring(record))
		return
	end
	if not record then
		Util.toast(deps.Remotes, player, "That craft could not be completed.", "bad", Config.TOAST.short)
		return
	end

	state.craftSerial[player] = (state.craftSerial[player] or 0) + 1
	Util.broadcastToast(
		deps.Remotes,
		string.format("%s crafted a %s %s from three %s brainrots!", player.DisplayName, resultKind.rarity, resultKind.name, rarityName),
		"legendary",
		Config.TOAST.long
	)
	pcall(function()
		deps.StateService.push(player)
	end)
end

function CraftService.releasePlayer(player: Player)
	state.lastCraftAt[player] = nil
	state.craftSerial[player] = nil
end

function CraftService.start(services: any)
	deps = services
	Config = services.Config
	Util = services.Util
	state.running = true
	state.lastCraftAt = {}
	state.craftSerial = {}

	local remote = deps.Remotes and deps.Remotes.CraftRequest
	if remote then
		state.connection = remote.OnServerEvent:Connect(function(player, rarityName)
			CraftService.tryCraft(player, rarityName)
		end)
	end
end

function CraftService.stop()
	state.running = false
	if state.connection then
		pcall(function()
			state.connection:Disconnect()
		end)
		state.connection = nil
	end
	state.lastCraftAt = {}
	state.craftSerial = {}
end

return CraftService
