--!strict
-- Util — the small shared toolbox used by both the server services and the
-- client HUD. Everything in here is deliberately defensive: a missing remote,
-- a destroyed character or a nil player must never be able to throw out of a
-- helper and take a live round down with it.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Util = {}

-- Numbers ------------------------------------------------------------------

local CASH_STEPS = {
	{ limit = 1e12, suffix = "T", digits = 2 },
	{ limit = 1e9, suffix = "B", digits = 2 },
	{ limit = 1e6, suffix = "M", digits = 2 },
	{ limit = 1e5, suffix = "K", digits = 0 },
	{ limit = 1e4, suffix = "K", digits = 1 },
}

-- "$1.2K"-style short cash text for the HUD and for world billboards.
function Util.formatCash(amount: number): string
	local n = tonumber(amount) or 0
	if n < 0 then
		n = 0
	end
	for _, step in ipairs(CASH_STEPS) do
		if n >= step.limit then
			return string.format("%." .. step.digits .. "f%s", n / step.limit, step.suffix)
		end
	end
	return tostring(math.floor(n))
end

-- "12,340" with thousand separators, for exact prices in toasts.
function Util.commaNumber(amount: number): string
	local text = tostring(math.floor(tonumber(amount) or 0))
	local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if grouped:sub(1, 1) == "," then
		grouped = grouped:sub(2)
	end
	return grouped
end

function Util.round(n: number, places: number?): number
	local scale = 10 ^ (places or 0)
	return math.floor(n * scale + 0.5) / scale
end

function Util.clamp(n: number, lo: number, hi: number): number
	if n < lo then
		return lo
	elseif n > hi then
		return hi
	end
	return n
end

-- Horizontal distance only: creature heights bob, so Y must not skew it.
function Util.flatDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Lists --------------------------------------------------------------------

function Util.pickWeighted(list: { any }, weightOf: (any) -> number): any
	if #list == 0 then
		return nil
	end
	local total = 0
	for _, item in ipairs(list) do
		total += math.max(0, weightOf(item))
	end
	if total <= 0 then
		return list[1]
	end
	local roll = math.random() * total
	for _, item in ipairs(list) do
		roll -= math.max(0, weightOf(item))
		if roll <= 0 then
			return item
		end
	end
	return list[#list]
end

function Util.shuffle(list: { any }): { any }
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- Removes every occurrence of item in place and returns how many were removed.
function Util.removeAll(list: { any }, item: any): number
	local removed = 0
	for i = #list, 1, -1 do
		if list[i] == item then
			table.remove(list, i)
			removed += 1
		end
	end
	return removed
end

-- Worlds -------------------------------------------------------------------

-- Walk a few parents up from a touched part so hats, tools and accessories
-- still resolve to the player who owns them.
function Util.playerFromHit(hit: BasePart?): Player?
	local node: Instance? = hit
	for _ = 1, 5 do
		if not node then
			return nil
		end
		local owner = Players:GetPlayerFromCharacter(node)
		if owner then
			return owner
		end
		node = node.Parent
	end
	return nil
end

function Util.cframeAt(position: Vector3, yaw: number?): CFrame
	return CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0)
end

-- A flat disc lying on the ground. Roblox cylinders are X-aligned, so a disc
-- is a cylinder rotated 90 degrees about Z.
function Util.flatDisc(position: Vector3, diameter: number, thickness: number, color: Color3, material: Enum.Material, parent: Instance?, transparency: number?): Part
	return Util.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, diameter, diameter),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
		Transparency = transparency or 0,
	}, parent)
end

-- Instances ----------------------------------------------------------------

local function applyProps(instance: any, props: { [string]: any }?)
	if not props then
		return
	end
	for key, value in pairs(props) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
end

-- A part with the world's default tuning: anchored, non-colliding, no touch
-- events unless a caller asks for them.
function Util.part(props: { [string]: any }, parent: Instance?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	applyProps(part, props)
	if parent then
		part.Parent = parent
	end
	return part
end

function Util.corner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

function Util.stroke(parent: Instance, color: Color3, thickness: number?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Util.label(props: { [string]: any }, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = false
	label.RichText = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	applyProps(label, props)
	label.Parent = parent
	return label
end

function Util.frame(props: { [string]: any }, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.fromRGB(20, 18, 34)
	applyProps(frame, props)
	frame.Parent = parent
	return frame
end

-- A rounded BillboardGui for nameplates and base signs.
function Util.billboard(adornee: BasePart, size: Vector2, studsOffset: Vector3, maxDistance: number?): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Nameplate"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = maxDistance or 150
	billboard.Size = UDim2.fromOffset(size.X, size.Y)
	billboard.StudsOffset = studsOffset
	billboard.ResetOnSpawn = false
	billboard.Parent = adornee
	return billboard
end

function Util.setTransparency(model: Instance, alpha: number)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = alpha
		elseif descendant:IsA("Decal") then
			descendant.Transparency = alpha
		end
	end
end

function Util.destroyAfter(instance: Instance, seconds: number)
	task.delay(seconds, function()
		if instance and instance.Parent then
			instance:Destroy()
		end
	end)
end

function Util.tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

function Util.safeWaitFor(parent: Instance, name: string, timeout: number?): Instance?
	local found = parent:FindFirstChild(name)
	if found then
		return found
	end
	local ok, result = pcall(function()
		return parent:WaitForChild(name, timeout or 10)
	end)
	if ok then
		return result
	end
	return nil
end

-- Remotes ------------------------------------------------------------------

-- All three of these swallow transport errors: a remote that cannot be
-- delivered is never a reason to break gameplay logic.
function Util.fireClient(remote: RemoteEvent?, player: Player?, payload: any)
	if not remote or not player then
		return
	end
	pcall(function()
		remote:FireClient(player, payload)
	end)
end

function Util.fireAll(remote: RemoteEvent?, payload: any)
	if not remote then
		return
	end
	pcall(function()
		remote:FireAllClients(payload)
	end)
end

function Util.toast(remotes: any, player: Player?, text: string, tone: string?, duration: number?)
	if not player then
		return
	end
	Util.fireClient(remotes and remotes.FX, player, {
		kind = "toast",
		text = text,
		tone = tone or "info",
		duration = duration or 4,
	})
end

function Util.broadcastToast(remotes: any, text: string, tone: string?, duration: number?)
	Util.fireAll(remotes and remotes.FX, {
		kind = "toast",
		text = text,
		tone = tone or "info",
		duration = duration or 4,
	})
end

-- Tone name to colour, shared by the HUD and by world float text.
function Util.toneColor(tone: string?, ui: any): Color3
	local palette = ui or {
		gold = Color3.fromRGB(255, 211, 74),
		green = Color3.fromRGB(92, 242, 168),
		red = Color3.fromRGB(255, 70, 100),
		cyan = Color3.fromRGB(86, 231, 255),
		text = Color3.fromRGB(246, 246, 255),
	}
	if tone == "good" then
		return palette.green
	elseif tone == "bad" then
		return palette.red
	elseif tone == "legendary" or tone == "gold" or tone == "rebirth" then
		return palette.gold
	elseif tone == "info" then
		return palette.cyan
	end
	return palette.text
end

return Util
