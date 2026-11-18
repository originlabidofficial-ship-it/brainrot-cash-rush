-- BaseService: the six player base decks, placement, guarding, stealing and
-- the permanent rebirth glow. It owns the pads and decides whether a steal is
-- legal; BrainrotService owns the creatures being moved.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local BaseService = {}

local Util
local Config
local deps: any = nil

local pads: { any } = {}
local playerPads: { [Player]: any } = {}
local padTouchAt: { [Player]: number } = {}
local padHintAt: { [Player]: number } = {}
local stealReadyAt: { [Player]: number } = {}
local stealNoticeAt: { [Player]: number } = {}

local function makePart(props: { [string]: any }, parent: Instance): Part
	return Util.part(props, parent)
end

local function makeLabel(parent: Instance, props: { [string]: any }): TextLabel
	return Util.label(props, parent)
end

-- A flat disc lying on the ground (Roblox cylinders are X-aligned).
local function flatDisc(position: Vector3, diameter: number, thickness: number, color: Color3, material: Enum.Material, parent: Instance, transparency: number?): Part
	return makePart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, diameter, diameter),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
		Transparency = transparency or 0,
	}, parent)
end

local function makeSign(pad: any)
	local anchor = makePart({
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(pad.center + Vector3.new(0, 13, 0)),
		Transparency = 1,
		CanCollide = false,
	}, pad.folder)
	anchor.Name = "SignAnchor"

	local bb = Util.billboard(anchor, Vector2.new(390, 104), Vector3.new(0, 0, 0), 190)
	local frame = Util.frame({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(16, 14, 28),
		BackgroundTransparency = 0.2,
	}, bb)
	Util.corner(frame, 14)
	pad.stroke = Util.stroke(frame, pad.baseColor, 2.5, 0.1)

	pad.titleLabel = makeLabel(frame, {
		Size = UDim2.new(1, -18, 0.52, 0),
		Position = UDim2.fromOffset(9, 4),
		Text = "OPEN BASE",
		Font = Enum.Font.GothamBlack,
		TextColor3 = pad.baseColor,
		TextScaled = true,
	})
	pad.infoLabel = makeLabel(frame, {
		Size = UDim2.new(1, -18, 0.34, 0),
		Position = UDim2.new(0, 9, 0.56, 0),
		Text = "Stand here to claim",
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(225, 220, 240),
		TextScaled = true,
	})
end

local function createPad(index: number, position: Vector3): any
	local folder = Instance.new("Folder")
	folder.Name = "Base_" .. index
	folder.Parent = Workspace:FindFirstChild("Bases") or Workspace

	local baseColor = Config.MAP.palette[((index - 1) % #Config.MAP.palette) + 1]
	local towardCenter = (Vector3.new(0, 0, 0) - position).Unit
	if towardCenter.Magnitude < 0.01 then
		towardCenter = Vector3.new(0, 0, -1)
	end
	local right = Vector3.new(towardCenter.Z, 0, -towardCenter.X)

	local glow = flatDisc(position + Vector3.new(0, 0.3, 0), Config.MAP.padRadius * 2 + 3, 0.35, baseColor, Enum.Material.Neon, folder, 0.32)
	glow.Name = "PadGlow"
	glow.CanCollide = false

	local deck = flatDisc(position + Vector3.new(0, 0.35, 0), Config.MAP.padRadius * 2, 0.9, Color3.fromRGB(52, 46, 74), Enum.Material.Metal, folder)
	deck.Name = "PadDeck"
	deck.CanCollide = true
	deck.CanTouch = true

	local inner = flatDisc(position + Vector3.new(0, 0.82, 0), Config.MAP.padRadius * 2 - 4, 0.2, baseColor:Lerp(Color3.fromRGB(255, 255, 255), 0.25), Enum.Material.SmoothPlastic, folder, 0.1)
	inner.Name = "PadInner"
	inner.CanCollide = false

	local slots = {}
	local slotParts = {}
	for row = 0, 1 do
		for col = 0, 3 do
			local slotIndex = row * 4 + col + 1
			local across = right * ((col - 1.5) * 6.2)
			local depth = towardCenter * (row == 0 and 4.5 or -3.5)
			local slotPosition = position + across + depth + Vector3.new(0, 1.15, 0)
			local marker = flatDisc(slotPosition, 4.6, 0.18, baseColor, Enum.Material.Neon, folder, 0.55)
			marker.Name = "Slot_" .. slotIndex
			marker.CanCollide = false
			slots[slotIndex] = CFrame.new(slotPosition + Vector3.new(0, 3.0, 0)) * CFrame.Angles(0, math.atan2(towardCenter.X, towardCenter.Z), 0)
			table.insert(slotParts, marker)
		end
	end

	-- Two neon pylons at the back corners make each deck visible across the map.
	for _, side in ipairs({ -13, 13 }) do
		local polePos = position + right * side - towardCenter * 12
		makePart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(9, 0.7, 0.7),
			CFrame = CFrame.new(polePos + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(42, 38, 60),
			Material = Enum.Material.Metal,
			CanCollide = true,
		}, folder)
		local bulb = makePart({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.6, 1.6, 1.6),
			CFrame = CFrame.new(polePos + Vector3.new(0, 9.3, 0)),
			Color = baseColor,
			Material = Enum.Material.Neon,
		}, folder)
		local light = Instance.new("PointLight")
		light.Color = baseColor
		light.Brightness = 1.4
		light.Range = 20
		light.Parent = bulb
	end

	local pad = {
		index = index,
		center = position,
		folder = folder,
		deck = deck,
		glow = glow,
		inner = inner,
		slots = slots,
		slotParts = slotParts,
		baseColor = baseColor,
		towardCenter = towardCenter,
		right = right,
		owner = nil,
		rebirths = 0,
		income = 0,
		count = 0,
	}

	makeSign(pad)

	deck.Touched:Connect(function(hit)
		if not pad.owner then
			return
		end
		local player = Util.playerFromHit(hit)
		if not player or player ~= pad.owner then
			return
		end
		local now = os.clock()
		if (padTouchAt[player] or 0) > now then
			return
		end
		padTouchAt[player] = now + 0.4

		local carried = deps.BrainrotService.getCarriedCount(player)
		if carried > 0 then
			local placed = deps.BrainrotService.placeCarried(player)
			if placed > 0 then
				BaseService.refreshPad(player)
				local income = tonumber(player:GetAttribute("IncomePerSec")) or 0
				Util.toast(deps.Remotes, player, string.format("Banked %d brainrot%s! +$%s/sec.", placed, placed == 1 and "" or "s", Util.formatCash(income)), "good", 4)
				Util.fireClient(deps.Remotes.FX, player, {
					kind = "bank",
					position = pad.center + Vector3.new(0, 5, 0),
					text = "+$" .. Util.formatCash(income) .. "/s",
				})
			end
		elseif (padHintAt[player] or 0) < now then
			padHintAt[player] = now + 5
			Util.toast(deps.Remotes, player, "This is your base. Bring wild brainrots here to bank them.", "info", 3)
		end
	end)

	return pad
end

function BaseService.getPad(player: Player): any
	return playerPads[player]
end

function BaseService.getPadCenter(player: Player): Vector3
	local pad = playerPads[player]
	if pad then
		return pad.center
	end
	return Vector3.new(0, 0, 0)
end

function BaseService.getSlotCFrame(player: Player, slot: number): CFrame?
	local pad = playerPads[player]
	if pad and pad.slots[slot] then
		return pad.slots[slot]
	end
	return nil
end

function BaseService.refreshPad(playerOrPad: any)
	local pad = playerOrPad
	if typeof(playerOrPad) == "Instance" then
		pad = playerPads[playerOrPad]
	end
	if not pad then
		return
	end

	local owner = pad.owner
	if owner and owner.Parent then
		local count = deps.BrainrotService.getPlacedCount(owner)
		local income = deps.BrainrotService.getBaseIncome(owner) * deps.PlayerService.getMultiplier(owner)
		pad.count = count
		pad.income = income
		pad.titleLabel.Text = string.upper(string.sub(owner.DisplayName, 1, 18)) .. "'S BASE"
		pad.infoLabel.Text = string.format("$%s/sec  •  %d/%d", Util.formatCash(income), count, Config.MAX_BASE)
		pad.stroke.Color = pad.rebirths > 0 and Color3.fromRGB(255, 212, 80) or pad.baseColor
		pad.titleLabel.TextColor3 = pad.rebirths > 0 and Color3.fromRGB(255, 222, 110) or pad.baseColor
		pad.inner.Color = pad.baseColor:Lerp(Color3.fromRGB(255, 255, 255), 0.25)
		owner:SetAttribute("Placed", count)
		owner:SetAttribute("IncomePerSec", income)
	else
		pad.count = 0
		pad.income = 0
		pad.titleLabel.Text = "OPEN BASE"
		pad.infoLabel.Text = "Join and claim it"
		pad.stroke.Color = Color3.fromRGB(150, 144, 170)
		pad.titleLabel.TextColor3 = Color3.fromRGB(200, 195, 215)
		pad.inner.Color = Color3.fromRGB(96, 90, 118)
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
	if not player or not player.Parent then
		return nil
	end
	if playerPads[player] then
		BaseService.refreshPad(playerPads[player])
		return playerPads[player]
	end

	local chosen = nil
	for _, pad in ipairs(pads) do
		if pad.owner == nil then
			chosen = pad
			break
		end
	end

	if not chosen then
		-- More players than the six home decks: add an overflow deck rather
		-- than leaving a player without a way to bank.
		local index = #pads + 1
		local a = math.rad(15 + index * 47)
		local radius = Config.MAP.baseRadius + 26
		chosen = createPad(index, Vector3.new(math.sin(a) * radius, 0, math.cos(a) * radius))
		table.insert(pads, chosen)
	end

	chosen.owner = player
	chosen.rebirths = tonumber(player:GetAttribute("Rebirths")) or 0
	playerPads[player] = chosen
	player:SetAttribute("BaseIndex", chosen.index)
	player:SetAttribute("BaseColor", chosen.baseColor)
	BaseService.refreshPad(chosen)
	BaseService.updateRebirthMarks(chosen)
	Util.toast(deps.Remotes, player, "This glowing deck is your base. Bank brainrots here!", "good", 4)
	return chosen
end

function BaseService.releasePlayer(player: Player)
	local pad = playerPads[player]
	if pad then
		pad.owner = nil
		pad.rebirths = 0
		local marks = pad.folder:FindFirstChild("RebirthMarks")
		if marks then
			marks:Destroy()
		end
		BaseService.refreshPad(pad)
	end
	playerPads[player] = nil
	padTouchAt[player] = nil
	padHintAt[player] = nil
	stealReadyAt[player] = nil
	stealNoticeAt[player] = nil
end

function BaseService.isPlayerOnOwnPad(player: Player): boolean
	local pad = playerPads[player]
	if not pad or not player.Parent then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return Util.flatDistance(root.Position, pad.center) <= Config.GUARD_RADIUS
end

function BaseService.updateRebirthMarks(pad: any)
	local old = pad.folder:FindFirstChild("RebirthMarks")
	if old then
		old:Destroy()
	end
	if pad.rebirths <= 0 then
		return
	end
	local marks = Instance.new("Folder")
	marks.Name = "RebirthMarks"
	marks.Parent = pad.folder
	local count = math.min(pad.rebirths, 8)
	for i = 1, count do
		local a = i / count * math.pi * 2
		local p = makePart({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.8, 1.8, 1.8),
			CFrame = CFrame.new(pad.center + Vector3.new(math.cos(a) * 14.5, 3.2, math.sin(a) * 14.5)),
			Color = Color3.fromRGB(255, 214, 76),
			Material = Enum.Material.Neon,
		}, marks)
		p.Name = "RebirthStar"
	end
	local beacon = makePart({
		Size = Vector3.new(1.4, 34, 1.4),
		CFrame = CFrame.new(pad.center + Vector3.new(0, 18, 0)),
		Color = Color3.fromRGB(255, 214, 76),
		Material = Enum.Material.Neon,
		Transparency = 0.55,
	}, marks)
	beacon.Name = "RebirthBeacon"
	beacon.CanCollide = false
end

function BaseService.onRebirth(player: Player, rebirths: number)
	local pad = playerPads[player]
	if not pad then
		return
	end
	pad.rebirths = rebirths
	BaseService.refreshPad(pad)
	BaseService.updateRebirthMarks(pad)
end

-- A legal steal: target on a base, thief has hands free, owner not guarding,
-- and the thief's three-second cooldown is over. The transfer itself is
-- BrainrotService's job.
function BaseService.trySteal(thief: Player, record: any): boolean
	if not thief or not thief.Parent or not record then
		return false
	end
	if record.state ~= "placed" then
		return false
	end
	local owner = record.owner
	if not owner or owner == thief or not owner.Parent then
		return false
	end

	local now = os.clock()
	if (stealReadyAt[thief] or 0) > now then
		if now >= (stealNoticeAt[thief] or 0) then
			stealNoticeAt[thief] = now + 1.2
			Util.toast(deps.Remotes, thief, string.format("Steal cooldown: %.1fs", (stealReadyAt[thief] or now) - now), "info", 2)
		end
		return false
	end

	if deps.BrainrotService.getCarriedCount(thief) >= Config.MAX_CARRIED then
		if now >= (stealNoticeAt[thief] or 0) then
			stealNoticeAt[thief] = now + 2
			Util.toast(deps.Remotes, thief, "Hands full! Bank one of your three first.", "bad", 3)
		end
		return false
	end

	if BaseService.isPlayerOnOwnPad(owner) then
		if now >= (stealNoticeAt[thief] or 0) then
			stealNoticeAt[thief] = now + 2
			Util.toast(deps.Remotes, thief, string.format("%s is guarding their base. Come back when they leave!", owner.DisplayName), "bad", 3.5)
		end
		return false
	end

	local stolen = deps.BrainrotService.transferToCarried(record, thief)
	if not stolen then
		return false
	end

	stealReadyAt[thief] = now + Config.STEAL_COOLDOWN
	BaseService.refreshPad(owner)
	BaseService.refreshPad(thief)

	Util.toast(deps.Remotes, owner, string.format("%s STOLE your %s! Guard your base!", thief.DisplayName, record.kind.name), "bad", 5)
	Util.toast(deps.Remotes, thief, string.format("Stole %s (+$%d/sec)! Bank it fast.", record.kind.name, record.rarity.value), "good", 4)
	Util.fireClient(deps.Remotes.FX, owner, {
		kind = "steal",
		position = record.model:GetPivot().Position,
		text = "-" .. record.kind.name,
		tone = "bad",
	})
	Util.fireClient(deps.Remotes.FX, thief, {
		kind = "stealHighlight",
		duration = 2.2,
		text = "STEALING",
	})
	return true
end

-- A brainrot lifted above a running player is vulnerable too: an enemy who
-- jumps into its hitbox can snatch it, with the same cooldown, carry cap and
-- base-guard rules. A short grace period stops a steal the instant it is grabbed.
function BaseService.tryStealCarried(thief: Player, record: any): boolean
	if not thief or not thief.Parent or not record or record.state ~= "carried" then
		return false
	end
	local owner = record.owner
	if not owner or owner == thief or not owner.Parent then
		return false
	end
	local now = os.clock()
	if now - (record.carriedAt or 0) < 1.6 then
		return false
	end
	if (stealReadyAt[thief] or 0) > now then
		return false
	end
	if deps.BrainrotService.getCarriedCount(thief) >= Config.MAX_CARRIED then
		if now >= (stealNoticeAt[thief] or 0) then
			stealNoticeAt[thief] = now + 2
			Util.toast(deps.Remotes, thief, "Hands full! Bank one of your three first.", "bad", 3)
		end
		return false
	end
	if BaseService.isPlayerOnOwnPad(owner) then
		if now >= (stealNoticeAt[thief] or 0) then
			stealNoticeAt[thief] = now + 2
			Util.toast(deps.Remotes, thief, string.format("%s is guarding their base!", owner.DisplayName), "bad", 3)
		end
		return false
	end

	local stolen = deps.BrainrotService.transferToCarried(record, thief)
	if not stolen then
		return false
	end
	stealReadyAt[thief] = now + Config.STEAL_COOLDOWN
	Util.toast(deps.Remotes, owner, string.format("%s snatched your carried %s!", thief.DisplayName, record.kind.name), "bad", 4)
	Util.toast(deps.Remotes, thief, string.format("Snatched %s (+$%d/sec) mid-run!", record.kind.name, record.rarity.value), "good", 4)
	Util.fireClient(deps.Remotes.FX, thief, { kind = "stealHighlight", duration = 2.2, text = "STEALING" })
	Util.fireClient(deps.Remotes.FX, owner, {
		kind = "steal",
		position = record.model:GetPivot().Position,
		text = "-" .. record.kind.name,
		tone = "bad",
	})
	return true
end

function BaseService.init(services: any)
	deps = services
	Util = services.Util
	Config = services.Config

	local basesFolder = Workspace:FindFirstChild("Bases")
	if basesFolder then
		basesFolder:Destroy()
	end
	basesFolder = Instance.new("Folder")
	basesFolder.Name = "Bases"
	basesFolder.Parent = Workspace

	pads = {}
	playerPads = {}

	for i = 1, 6 do
		local a = math.rad(30 + (i - 1) * 60)
		local position = Vector3.new(math.sin(a) * Config.MAP.baseRadius, 0, math.cos(a) * Config.MAP.baseRadius)
		local pad = createPad(i, position)
		pad.folder.Parent = basesFolder
		table.insert(pads, pad)
		BaseService.refreshPad(pad)
	end

	-- Keep the on-pad income labels fresh even while nobody banks.
	task.spawn(function()
		while true do
			task.wait(2)
			for _, pad in ipairs(pads) do
				if pad.owner and pad.owner.Parent then
					BaseService.refreshPad(pad)
				end
			end
		end
	end)
end

return BaseService
