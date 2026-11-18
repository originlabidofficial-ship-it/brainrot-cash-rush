--!strict
-- Util: small helpers shared by server and client. Everything here is
-- defensive: a missing RemoteEvent, player or character must never take a
-- service down mid-round.

local Util = {}

-- "$1.2K" style numbers, used by the HUD and by world Billboards.
function Util.formatCash(amount: number): string
	local n = tonumber(amount) or 0
	if n < 0 then
		n = 0
	end
	if n >= 1e12 then
		return string.format("%.2fT", n / 1e12)
	elseif n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 100000 then
		return string.format("%.0fK", n / 1000)
	elseif n >= 10000 then
		return string.format("%.1fK", n / 1000)
	end
	return tostring(math.floor(n))
end

function Util.commaNumber(amount: number): string
	local s = tostring(math.floor(tonumber(amount) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

function Util.round(n: number, places: number?): number
	local p = places or 0
	local m = 10 ^ p
	return math.floor(n * m + 0.5) / m
end

function Util.flatDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function Util.clamp(n: number, lo: number, hi: number): number
	if n < lo then
		return lo
	elseif n > hi then
		return hi
	end
	return n
end

function Util.pickWeighted(list: { any }, weightOf: (any) -> number): any
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

-- Find the player a touching part belongs to, walking up the model tree so
-- hats and tools count too.
function Util.playerFromHit(hit: BasePart?): Player?
	if not hit then
		return nil
	end
	local node: Instance? = hit
	for _ = 1, 5 do
		if not node then
			return nil
		end
		local player = game:GetService("Players"):GetPlayerFromCharacter(node)
		if player then
			return player
		end
		node = node.Parent
	end
	return nil
end

function Util.cframeAt(position: Vector3, yaw: number?): CFrame
	return CFrame.new(position) * CFrame.Angles(0, yaw or 0, 0)
end

-- A part with sane defaults, all anchored; the world is static except for the
-- models the services explicitly move.
function Util.part(props: { [string]: any }, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	local target = p :: any
	for key, value in pairs(props) do
		if key ~= "Parent" and key ~= "Class" then
			target[key] = value
		end
	end
	if parent then
		p.Parent = parent
	end
	return p
end

function Util.corner(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function Util.stroke(parent: Instance, color: Color3, thickness: number?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Util.label(props: { [string]: any }, parent: Instance): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Font = Enum.Font.GothamBold
	t.TextColor3 = Color3.fromRGB(255, 255, 255)
	t.TextScaled = false
	t.RichText = false
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	local target = t :: any
	for key, value in pairs(props) do
		if key ~= "Parent" then
			target[key] = value
		end
	end
	t.Parent = parent
	return t
end

function Util.frame(props: { [string]: any }, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(20, 18, 34)
	local target = f :: any
	for key, value in pairs(props) do
		if key ~= "Parent" then
			target[key] = value
		end
	end
	f.Parent = parent
	return f
end

-- Remote helpers never throw into gameplay code.
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

-- A rounded BillboardGui used for brainrot nameplates and base signs.
function Util.billboard(adornee: BasePart, size: Vector2, studsOffset: Vector3, maxDistance: number?): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "Nameplate"
	bb.Adornee = adornee
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = maxDistance or 150
	bb.Size = UDim2.fromOffset(size.X, size.Y)
	bb.StudsOffset = studsOffset
	bb.ResetOnSpawn = false
	bb.Parent = adornee
	return bb
end

function Util.setTransparency(model: Model, alpha: number)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = alpha
		elseif d:IsA("Decal") then
			d.Transparency = alpha
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
	local tween = game:GetService("TweenService"):Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
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

return Util
