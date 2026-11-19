--!strict
-- BaseService — the six home decks and every rule that protects them.
--
-- A pad is both a piece of scenery and a small state machine:
--   vacant -> claimed by a player -> decorated with rebirth marks -> vacant.
-- BrainrotService owns the creatures; this module owns where they can be put
-- down, when a base counts as guarded, and whether a steal is legal. Every
-- steal decision is made here on the server, never on the client.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BaseService = {}

local Config: any = nil
local Util: any = nil
local deps: any = nil

local state = {
	running = false,
	pads = {} :: { any },
	byPlayer = {} :: { [Player]: any },
	touchCooldown = {} :: { [Player]: number },
	hintCooldown = {} :: { [Player]: number },
	stealReadyAt = {} :: { [Player]: number },
	stealNoticeAt = {} :: { [Player]: number },
}

local function alive(player: Player?): boolean
	return player ~= nil and player.Parent ~= nil
end

local function upgradeService(): any
	return deps and deps.UpgradeService
end

-- Geometry helpers ---------------------------------------------------------

local function part(props: { [string]: any }, parent: Instance): Part
	return Util.part(props, parent)
end

local function labelProps(props: { [string]: any }, parent: Instance): TextLabel
	return Util.label(props, parent)
end

-- A disc lying flat on the ground: cylinder rotated onto its side.
local function plate(position: Vector3, diameter: number, thickness: number, color: Color3, material: Enum.Material, parent: Instance, alpha: number?): Part
	return Util.flatDisc(position, diameter, thickness, color, material, parent, alpha)
end

-- Pad signage --------------------------------------------------------------

-- Two SurfaceGuis (front and back) on a real board. Unlike a BillboardGui the
-- board is geometry, so "YOUR BASE" reads in any screenshot.
local function mountBoard(pad: any, board: Part, accent: Color3)
	pad.markerTitles = {}
	pad.markerSubs = {}
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "BaseSignGui"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 46
		gui.LightInfluence = 0
		gui.MaxDistance = 520
		gui.Parent = board

		local card = Util.frame({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(14, 12, 26),
			BackgroundTransparency = 0.1,
		}, gui)
		Util.corner(card, 16)
		Util.stroke(card, accent, 3, 0.08)

		local heading = labelProps({
			Size = UDim2.new(1, -14, 0.55, 0),
			Position = UDim2.fromOffset(7, 3),
			Text = "YOUR BASE",
			Font = Enum.Font.GothamBlack,
			TextColor3 = accent,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, card)
		local sub = labelProps({
			Size = UDim2.new(1, -14, 0.3, 0),
			Position = UDim2.new(0, 7, 0.58, 0),
			Text = "JOIN TO CLAIM",
			Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(230, 226, 245),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, card)
		table.insert(pad.markerTitles, heading)
		table.insert(pad.markerSubs, sub)
	end
end

local function buildSignage(pad: any)
	-- Floating card above the deck, readable from the plaza.
	local anchor = part({
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(pad.center + Vector3.new(0, 16, 0)),
		Transparency = 1,
	}, pad.folder)
	anchor.Name = "SignAnchor"

	local billboard = Util.billboard(anchor, Vector2.new(330, 92), Vector3.new(0, 0, 0), 230)
	local card = Util.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(16, 14, 28),
		BackgroundTransparency = 0.2,
	}, billboard)
	Util.corner(card, 14)
	pad.stroke = Util.stroke(card, pad.baseColor, 2.5, 0.1)
	pad.titleLabel = labelProps({
		Size = UDim2.new(1, -18, 0.52, 0),
		Position = UDim2.fromOffset(9, 4),
		Text = "YOUR BASE",
		Font = Enum.Font.GothamBlack,
		TextColor3 = pad.baseColor,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, card)
	pad.infoLabel = labelProps({
		Size = UDim2.new(1, -18, 0.34, 0),
		Position = UDim2.new(0, 9, 0.56, 0),
		Text = "Stand here to claim",
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(225, 220, 240),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, card)

	-- Physical board between the pylons.
	local boardPos = pad.center - pad.towardCenter * 12 + Vector3.new(0, 11.4, 0)
	local boardCF = CFrame.lookAt(boardPos, boardPos + pad.towardCenter)
	local board = part({
		Size = Vector3.new(21, 4.4, 0.5),
		CFrame = boardCF,
		Color = Color3.fromRGB(14, 12, 26),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	}, pad.folder)
	board.Name = "BaseBoard"

	local trim = {
		{ Vector3.new(0, 2.55, 0), Vector3.new(22.2, 0.4, 0.8) },
		{ Vector3.new(0, -2.55, 0), Vector3.new(22.2, 0.4, 0.8) },
		{ Vector3.new(-10.9, 0, 0), Vector3.new(0.4, 5.3, 0.8) },
		{ Vector3.new(10.9, 0, 0), Vector3.new(0.4, 5.3, 0.8) },
	}
	for _, piece in ipairs(trim) do
		part({
			Size = piece[2],
			CFrame = boardCF * CFrame.new(piece[1]),
			Color = pad.baseColor,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		}, pad.folder).Name = "BaseTrim"
	end
	mountBoard(pad, board, pad.baseColor)
end

-- Slot ring ----------------------------------------------------------------
-- Sixteen slots: the eight inner ones are the starting capacity, the outer
-- eight unlock with the Pad Slots upgrade. Locked slots are still built so the
-- deck visibly grows instead of changing shape mid-session.

local INNER_SLOTS = 8

local function buildSlots(pad: any)
	local slots = {}
	local markers = {}
	local beams = {}
	local faceYaw = math.atan2(pad.towardCenter.X, pad.towardCenter.Z)

	for slotIndex = 1, Config.MAX_BASE_SLOTS do
		local ring = slotIndex <= INNER_SLOTS and 0 or 1
		local slotInRing = (slotIndex - 1) % INNER_SLOTS
		local angle = slotInRing / INNER_SLOTS * math.pi * 2
		if ring == 1 then
			angle += math.rad(22.5)
		end
		local radius = ring == 0 and 8.6 or 12.6
		local offset = pad.right * (math.cos(angle) * radius) + pad.towardCenter * (math.sin(angle) * radius)
		local markerPos = pad.center + offset + Vector3.new(0, 0.95, 0)

		local marker = plate(markerPos, 3.8, 0.18, pad.baseColor, Enum.Material.Neon, pad.folder, 0.55)
		marker.Name = "Slot_" .. slotIndex
		markers[slotIndex] = marker

		slots[slotIndex] = CFrame.new(markerPos + Vector3.new(0, 2.65, 0)) * CFrame.Angles(0, faceYaw, 0)

		local beam = part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3.2, 0.38, 0.38),
			CFrame = CFrame.new(markerPos + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = pad.baseColor,
			Material = Enum.Material.Neon,
			Transparency = 0.9,
			CanCollide = false,
			CanQuery = false,
		}, pad.folder)
		beam.Name = "SlotBeam_" .. slotIndex
		beams[slotIndex] = beam
	end

	pad.slots = slots
	pad.slotParts = markers
	pad.slotBeams = beams
end

local function createPad(index: number, position: Vector3): any
	local folder = Instance.new("Folder")
	folder.Name = "Base_" .. index
	folder.Parent = Workspace:FindFirstChild("Bases") or Workspace

	local padColor = Config.MAP.palette[((index - 1) % #Config.MAP.palette) + 1]
	local towardCenter = (Vector3.new(0, 0, 0) - position).Unit
	if towardCenter.Magnitude < 0.01 then
		towardCenter = Vector3.new(0, 0, -1)
	end
	local right = Vector3.new(towardCenter.Z, 0, -towardCenter.X)

	local glow = plate(position + Vector3.new(0, 0.3, 0), Config.MAP.padRadius * 2 + 3, 0.35, padColor, Enum.Material.Neon, folder, 0.32)
	glow.Name = "PadGlow"

	local deck = plate(position + Vector3.new(0, 0.35, 0), Config.MAP.padRadius * 2, 0.9, Color3.fromRGB(230, 224, 212), Enum.Material.Concrete, folder)
	deck.Name = "PadDeck"
	deck.CanCollide = true
	deck.CanTouch = true

	local inner = plate(position + Vector3.new(0, 0.82, 0), Config.MAP.padRadius * 2 - 4, 0.2, padColor:Lerp(Color3.fromRGB(255, 255, 255), 0.3), Enum.Material.SmoothPlastic, folder, 0.1)
	inner.Name = "PadInner"

	local pad = {
		index = index,
		center = position,
		folder = folder,
		deck = deck,
		glow = glow,
		inner = inner,
		baseColor = padColor,
		towardCenter = towardCenter,
		right = right,
		owner = nil,
		rebirths = 0,
		income = 0,
		count = 0,
		occupied = {},
	}

	buildSlots(pad)

	-- Two pylons at the rear edge so a deck is identifiable from far away.
	for _, side in ipairs({ -13, 13 }) do
		local polePos = position + right * side - towardCenter * 12
		part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(9, 0.7, 0.7),
			CFrame = CFrame.new(polePos + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(44, 40, 62),
			Material = Enum.Material.Metal,
			CanCollide = true,
		}, folder).Name = "Pylon"
		local bulb = part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.6, 1.6, 1.6),
			CFrame = CFrame.new(polePos + Vector3.new(0, 9.3, 0)),
			Color = padColor,
			Material = Enum.Material.Neon,
		}, folder)
		bulb.Name = "PylonBulb"
		local light = Instance.new("PointLight")
		light.Color = padColor
		light.Brightness = 1.4
		light.Range = 20
		light.Parent = bulb
	end

	buildSignage(pad)

	deck.Touched:Connect(function(hit)
		BaseService.handleDeckTouch(pad, hit)
	end)

	return pad
end

-- Pads and ownership -------------------------------------------------------

function BaseService.getPad(player: Player): any
	return state.byPlayer[player]
end

function BaseService.getPadCenter(player: Player): Vector3
	local pad = state.byPlayer[player]
	return pad and pad.center or Vector3.new(0, 0, 0)
end

function BaseService.getSlotCFrame(player: Player, slot: number): CFrame?
	local pad = state.byPlayer[player]
	if pad and pad.slots and pad.slots[slot] then
		return pad.slots[slot]
	end
	return nil
end

local function markedOccupied(pad: any, slot: number): boolean
	return pad.occupied ~= nil and pad.occupied[slot] == true
end

function BaseService.setSlotOccupied(playerOrPad: any, slot: number, occupied: boolean)
	local pad = playerOrPad
	if typeof(playerOrPad) == "Instance" then
		pad = state.byPlayer[playerOrPad]
	end
	if not pad or not slot then
		return
	end
	pad.occupied[slot] = occupied == true

	local marker = pad.slotParts[slot]
	if marker then
		marker.Transparency = occupied and 0.05 or 0.55
		marker.Color = occupied and Color3.fromRGB(255, 244, 210) or pad.baseColor
	end
	local beam = pad.slotBeams[slot]
	if beam then
		beam.Transparency = occupied and 0.32 or 0.9
		beam.Color = pad.baseColor
	end
end

function BaseService.refreshPad(playerOrPad: any)
	local pad = playerOrPad
	if typeof(playerOrPad) == "Instance" then
		pad = state.byPlayer[playerOrPad]
	end
	if not pad then
		return
	end

	local owner = pad.owner
	local capacity = Config.MAX_BASE
	if owner and upgradeService() then
		capacity = upgradeService().getPadSlots(owner)
	end

	if alive(owner) then
		local count = deps.BrainrotService.getPlacedCount(owner)
		local multiplier = deps.PlayerService.getMultiplier(owner)
		if upgradeService() then
			multiplier *= upgradeService().getIncomeMultiplier(owner)
		end
		local income = deps.BrainrotService.getBaseIncome(owner) * multiplier
		pad.count = count
		pad.income = income

		local golden = pad.rebirths > 0
		pad.titleLabel.Text = "YOUR BASE"
		pad.infoLabel.Text = string.format("%s  •  $%s/sec  •  %d/%d", string.sub(owner.DisplayName, 1, 16), Util.formatCash(income), count, capacity)
		pad.titleLabel.TextColor3 = golden and Color3.fromRGB(255, 222, 110) or pad.baseColor
		pad.stroke.Color = golden and Color3.fromRGB(255, 212, 80) or pad.baseColor
		for _, item in ipairs(pad.markerTitles or {}) do
			item.TextColor3 = golden and Color3.fromRGB(255, 222, 110) or pad.baseColor
		end
		for _, item in ipairs(pad.markerSubs or {}) do
			item.Text = string.upper(string.sub(owner.DisplayName, 1, 18))
		end
		owner:SetAttribute("Placed", count)
		owner:SetAttribute("IncomePerSec", income)
	else
		pad.count = 0
		pad.income = 0
		pad.titleLabel.Text = "YOUR BASE"
		pad.infoLabel.Text = "Stand here to claim it"
		pad.titleLabel.TextColor3 = Color3.fromRGB(205, 200, 222)
		pad.stroke.Color = Color3.fromRGB(150, 144, 170)
		for _, item in ipairs(pad.markerTitles or {}) do
			item.TextColor3 = Color3.fromRGB(205, 200, 222)
		end
		for _, item in ipairs(pad.markerSubs or {}) do
			item.Text = "JOIN TO CLAIM"
		end
	end

	-- Lock beyond the owner's capacity, and repaint every slot that is legal.
	local visibleCap = alive(owner) and capacity or Config.MAX_BASE
	for slot = 1, #pad.slotParts do
		local marker = pad.slotParts[slot]
		local beam = pad.slotBeams[slot]
		if slot > visibleCap then
			marker.Transparency = 0.93
			marker.Color = Color3.fromRGB(66, 62, 84)
			if beam then
				beam.Transparency = 1
			end
		else
			local occupied = markedOccupied(pad, slot)
			marker.Transparency = occupied and 0.05 or 0.55
			marker.Color = occupied and Color3.fromRGB(255, 244, 210) or pad.baseColor
			if beam then
				beam.Transparency = occupied and 0.32 or 0.9
				beam.Color = pad.baseColor
			end
		end
	end

	if pad.rebirths > 0 then
		pad.glow.Color = Color3.fromRGB(255, 206, 70)
		pad.glow.Transparency = 0.05
	else
		pad.glow.Color = pad.baseColor
		pad.glow.Transparency = 0.32
	end
end

function BaseService.assignPad(player: Player): any
	if not alive(player) then
		return nil
	end
	if state.byPlayer[player] then
		BaseService.refreshPad(state.byPlayer[player])
		return state.byPlayer[player]
	end

	local chosen = nil
	for _, pad in ipairs(state.pads) do
		if pad.owner == nil then
			chosen = pad
			break
		end
	end

	if not chosen then
		-- Overflow: build a seventh (or later) deck instead of leaving a player
		-- without any way to bank.
		local index = #state.pads + 1
		local angle = math.rad(15 + index * 47)
		local radius = Config.MAP.baseRadius + 26
		chosen = createPad(index, Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius))
		table.insert(state.pads, chosen)
	end

	chosen.owner = player
	chosen.rebirths = tonumber(player:GetAttribute("Rebirths")) or 0
	state.byPlayer[player] = chosen
	player:SetAttribute("BaseIndex", chosen.index)
	player:SetAttribute("BaseColor", chosen.baseColor)
	BaseService.refreshPad(chosen)
	BaseService.updateRebirthMarks(chosen)
	Util.toast(deps.Remotes, player, "This glowing deck is your base. Bank brainrots here!", "good", Config.TOAST.normal)
	return chosen
end

function BaseService.releasePlayer(player: Player)
	local pad = state.byPlayer[player]
	if pad then
		pad.owner = nil
		pad.rebirths = 0
		pad.occupied = {}
		local marks = pad.folder:FindFirstChild("RebirthMarks")
		if marks then
			marks:Destroy()
		end
		for slot = 1, Config.MAX_BASE_SLOTS do
			local marker = pad.slotParts[slot]
			if marker then
				marker.Transparency = 0.55
				marker.Color = pad.baseColor
			end
			local beam = pad.slotBeams[slot]
			if beam then
				beam.Transparency = 0.9
			end
		end
		BaseService.refreshPad(pad)
	end
	state.byPlayer[player] = nil
	state.touchCooldown[player] = nil
	state.hintCooldown[player] = nil
	state.stealReadyAt[player] = nil
	state.stealNoticeAt[player] = nil
end

function BaseService.isPlayerOnOwnPad(player: Player): boolean
	local pad = state.byPlayer[player]
	if not pad or not alive(player) then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local radius = Config.GUARD_RADIUS
	if upgradeService() then
		radius = upgradeService().getGuardRadius(player)
	end
	return Util.flatDistance(root.Position, pad.center) <= radius
end

function BaseService.updateRebirthMarks(pad: any)
	local old = pad.folder:FindFirstChild("RebirthMarks")
	if old then
		old:Destroy()
	end
	if pad.rebirths <= 0 then
		return
	end

	local group = Instance.new("Folder")
	group.Name = "RebirthMarks"
	group.Parent = pad.folder

	-- Up to eight golden stars, one per rebirth, plus a tall beacon.
	local stars = math.min(pad.rebirths, 8)
	for i = 1, stars do
		local angle = i / stars * math.pi * 2
		part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.8, 1.8, 1.8),
			CFrame = CFrame.new(pad.center + Vector3.new(math.cos(angle) * 14.5, 3.2, math.sin(angle) * 14.5)),
			Color = Color3.fromRGB(255, 214, 76),
			Material = Enum.Material.Neon,
		}, group).Name = "RebirthStar"
	end
	part({
		Size = Vector3.new(1.4, 34, 1.4),
		CFrame = CFrame.new(pad.center + Vector3.new(0, 18, 0)),
		Color = Color3.fromRGB(255, 214, 76),
		Material = Enum.Material.Neon,
		Transparency = 0.55,
	}, group).Name = "RebirthBeacon"
end

function BaseService.onRebirth(player: Player, rebirths: number)
	local pad = state.byPlayer[player]
	if not pad then
		return
	end
	pad.rebirths = rebirths
	BaseService.refreshPad(pad)
	BaseService.updateRebirthMarks(pad)
end

-- Banking ------------------------------------------------------------------

function BaseService.handleDeckTouch(pad: any, hit: BasePart?)
	local owner = pad.owner
	if not owner then
		return
	end
	local player = Util.playerFromHit(hit)
	if not player or player ~= owner or not alive(player) then
		return
	end

	local now = os.clock()
	if (state.touchCooldown[player] or 0) > now then
		return
	end
	state.touchCooldown[player] = now + 0.4

	if deps.BrainrotService.getCarriedCount(player) > 0 then
		local placed = deps.BrainrotService.placeCarried(player)
		if placed > 0 then
			BaseService.refreshPad(player)
			local income = tonumber(player:GetAttribute("IncomePerSec")) or 0
			Util.toast(deps.Remotes, player, string.format("Banked %d brainrot%s! +$%s/sec.", placed, placed == 1 and "" or "s", Util.formatCash(income)), "good", Config.TOAST.normal)
			Util.fireClient(deps.Remotes.FX, player, {
				kind = "bank",
				position = pad.center + Vector3.new(0, 5, 0),
				text = "+$" .. Util.formatCash(income) .. "/s",
			})
		end
	elseif (state.hintCooldown[player] or 0) < now then
		state.hintCooldown[player] = now + 5
		Util.toast(deps.Remotes, player, "This is your base. Bring wild brainrots here to bank them.", "info", Config.TOAST.short)
	end
end

-- Stealing ----------------------------------------------------------------

local function noticeOnce(thief: Player, text: string, tone: string)
	local now = os.clock()
	if now < (state.stealNoticeAt[thief] or 0) then
		return
	end
	state.stealNoticeAt[thief] = now + 1.4
	Util.toast(deps.Remotes, thief, text, tone, Config.TOAST.short)
end

local function carryLimitOf(player: Player): number
	if upgradeService() then
		return upgradeService().getCarryCap(player)
	end
	return Config.MAX_CARRIED
end

-- Shared gate for both steal flavours. Returns true when the thief is allowed
-- to take something, and has already explained every refusal to the client.
local function thiefMaySteal(thief: Player, owner: Player, record: any): boolean
	local now = os.clock()
	if (state.stealReadyAt[thief] or 0) > now then
		noticeOnce(thief, string.format("Steal cooldown: %.1fs", (state.stealReadyAt[thief] or now) - now), "info")
		return false
	end

	local carrying = deps.BrainrotService.getCarriedCount(thief)
	local limit = carryLimitOf(thief)
	if carrying >= limit then
		noticeOnce(thief, string.format("Hands full (%d/%d)! Bank first.", carrying, limit), "bad")
		return false
	end

	if BaseService.isPlayerOnOwnPad(owner) then
		noticeOnce(thief, string.format("%s is guarding their base. Come back when they leave!", owner.DisplayName), "bad")
		return false
	end

	if record.state == "carried" and now - (record.carriedAt or 0) < Config.STEAL_GRACE then
		return false
	end
	return true
end

local function afterSteal(thief: Player, owner: Player, record: any, verb: string)
	state.stealReadyAt[thief] = os.clock() + Config.STEAL_COOLDOWN
	BaseService.refreshPad(owner)
	BaseService.refreshPad(thief)

	Util.toast(deps.Remotes, owner, string.format("%s %s your %s!", thief.DisplayName, verb, record.kind.name), "bad", Config.TOAST.long)
	Util.toast(deps.Remotes, thief, string.format("%s %s (+$%d/sec)!", verb == "stole" and "Stole" or "Snatched", record.kind.name, record.rarity.value), "good", Config.TOAST.normal)
	Util.fireClient(deps.Remotes.FX, owner, {
		kind = "steal",
		position = record.model:GetPivot().Position,
		text = "-" .. record.kind.name,
		tone = "bad",
	})
	Util.fireClient(deps.Remotes.FX, thief, { kind = "stealHighlight", duration = 2.2, text = "STEALING" })

	pcall(function()
		deps.QuestService.recordEvent(thief, "steal", 1)
	end)
	pcall(function()
		deps.StateService.push(thief)
	end)
	pcall(function()
		deps.StateService.push(owner)
	end)
end

function BaseService.trySteal(thief: Player, record: any): boolean
	if not alive(thief) or not record or record.state ~= "placed" then
		return false
	end
	local owner = record.owner
	if not owner or owner == thief or not alive(owner) then
		return false
	end
	if not thiefMaySteal(thief, owner, record) then
		return false
	end
	if not deps.BrainrotService.transferToCarried(record, thief) then
		return false
	end
	afterSteal(thief, owner, record, "stole")
	return true
end

function BaseService.tryStealCarried(thief: Player, record: any): boolean
	if not alive(thief) or not record or record.state ~= "carried" then
		return false
	end
	local owner = record.owner
	if not owner or owner == thief or not alive(owner) then
		return false
	end
	if not thiefMaySteal(thief, owner, record) then
		return false
	end
	if not deps.BrainrotService.transferToCarried(record, thief) then
		return false
	end
	afterSteal(thief, owner, record, "snatched")
	return true
end

-- Lifecycle ----------------------------------------------------------------

function BaseService.start(services: any)
	deps = services
	Config = services.Config
	Util = services.Util

	local previous = Workspace:FindFirstChild("Bases")
	if previous then
		previous:Destroy()
	end
	local bases = Instance.new("Folder")
	bases.Name = "Bases"
	bases.Parent = Workspace

	state.pads = {}
	state.byPlayer = {}
	state.touchCooldown = {}
	state.hintCooldown = {}
	state.stealReadyAt = {}
	state.stealNoticeAt = {}
	state.running = true

	for index = 1, Config.PAD_COUNT do
		local angle = math.rad(30 + (index - 1) * (360 / Config.PAD_COUNT))
		local position = Vector3.new(math.sin(angle) * Config.MAP.baseRadius, 0, math.cos(angle) * Config.MAP.baseRadius)
		local pad = createPad(index, position)
		pad.folder.Parent = bases
		table.insert(state.pads, pad)
		BaseService.refreshPad(pad)
	end

	-- Keep the income line on every claimed deck fresh between bank events.
	task.spawn(function()
		while state.running do
			task.wait(2)
			for _, pad in ipairs(state.pads) do
				if alive(pad.owner) then
					BaseService.refreshPad(pad)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		BaseService.releasePlayer(player)
	end)
end

function BaseService.stop()
	state.running = false
	for _, pad in ipairs(state.pads) do
		if pad.folder and pad.folder.Parent then
			pad.folder:Destroy()
		end
	end
	state.pads = {}
	state.byPlayer = {}
end

return BaseService
