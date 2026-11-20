--!strict
-- MutationService -- one server-side roll that turns a captured creature into
-- a story. Every wild brainrot gets exactly one chance at the moment of grab
-- (Config.MUTATION_CHANCE); the winning variant is weighted from
-- Config.MUTATIONS and stored on the live record. The mutation never changes
-- after capture, multiplies that creature's banked income, and repaints its
-- nameplate with a coloured prefix. Nothing here trusts the client: rolls
-- happen inside BrainrotService.attemptGrab, and the HUD only sees the result.

local MutationService = {}

local Config: any = nil
local Util: any = nil
local deps: any = nil

local state = {
	running = false,
}

local function hex(color: Color3): string
	return string.format("%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function shortMultiplier(value: number): string
	local text = string.format("%.2f", value)
	text = text:gsub("0+$", ""):gsub("%.$", "")
	return "x" .. text
end

-- Roll once per creature. The record flag also covers the no-mutation result,
-- so a creature that is dropped and grabbed again cannot re-roll its luck.
function MutationService.rollForCapture(record: any): any
	if not state.running or type(record) ~= "table" or record.mutationRolled then
		return record and record.mutation or nil
	end
	record.mutationRolled = true
	if math.random() >= Config.MUTATION_CHANCE then
		return nil
	end
	local mutation = Util.pickWeighted(Config.MUTATIONS, function(entry: any): number
		return entry.weight
	end)
	record.mutation = mutation
	return mutation
end

function MutationService.multiplier(record: any): number
	local mutation = record and record.mutation
	if mutation and type(mutation.multiplier) == "number" then
		return mutation.multiplier
	end
	return 1
end

function MutationService.incomeOf(record: any): number
	if not record or not record.rarity then
		return 0
	end
	return record.rarity.value * MutationService.multiplier(record)
end

-- Repaint the live model and its nameplate after a roll. Missing labels are
-- tolerated: a record may be mid-rebuild when this runs.
function MutationService.apply(record: any)
	if type(record) ~= "table" or not record.model then
		return
	end
	local mutation = record.mutation
	local multiplier = MutationService.multiplier(record)
	local income = MutationService.incomeOf(record)

	record.model:SetAttribute("Mutation", mutation and mutation.key or "None")
	record.model:SetAttribute("MutationMultiplier", multiplier)
	record.model:SetAttribute("CashPerSecond", income)

	local plate = record.nameplate
	if not plate then
		return
	end
	local prefix = plate.name
	local sub = plate.sub
	if prefix then
		if mutation then
			prefix.RichText = true
			prefix.Text = string.format('<font color="#%s">%s</font> %s', hex(mutation.color), mutation.prefix, record.kind.name)
			prefix.TextColor3 = mutation.color
		else
			prefix.RichText = false
			prefix.Text = record.kind.name
			prefix.TextColor3 = record.rarity.color
		end
	end
	if sub then
		local tag = mutation and ("   •   " .. mutation.key .. " " .. shortMultiplier(multiplier)) or ""
		sub.Text = string.upper(record.rarity.name) .. tag .. "   •   $" .. tostring(income) .. "/SEC"
	end
	if plate.stroke and mutation then
		plate.stroke.Color = mutation.color
		plate.stroke.Thickness = 3
	end
end

function MutationService.start(services: any)
	deps = services
	Config = services.Config
	Util = services.Util
	state.running = true
end

function MutationService.stop()
	state.running = false
	deps = nil
end

return MutationService
