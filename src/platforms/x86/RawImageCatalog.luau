local BootImageCatalog = require("src/platforms/x86/BootImageCatalog")
local Config = require("src/Config")

local RawImageCatalog = {}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in pairs(value) do
		out[key] = deepCopy(child)
	end
	return out
end

local function sectorsToDiskBytes(sectors)
	local maxLba = -1
	for lba in pairs(sectors or {}) do
		maxLba = math.max(maxLba, tonumber(lba) or -1)
	end

	local bytes = {}
	for lba = 0, maxLba do
		local sector = sectors[lba] or {}
		for byteIndex = 1, 512 do
			bytes[#bytes + 1] = (tonumber(sector[byteIndex]) or 0) % 256
		end
	end
	return bytes
end

local function snapshotImage(image)
	return {
		name = image.name,
		romBytes = deepCopy(image.romBytes),
		diskBytes = sectorsToDiskBytes(image.sectors),
		layout = deepCopy(image.layout or {}),
		files = deepCopy(image.files or {}),
		symbols = deepCopy(image.symbols or {}),
	}
end

local function buildRawImage(entryName)
	local entry = BootImageCatalog[entryName]
	assert(entry, "unknown x86 raw image entry: " .. tostring(entryName))

	local image = entry
	if type(entry) == "table" and type(entry.build) == "function" then
		image = entry.build(Config)
	end
	assert(type(image) == "table", "x86 raw image builder returned an invalid image")
	assert(type(image.romBytes) == "table", "x86 raw image is missing romBytes")
	assert(type(image.sectors) == "table", "x86 raw image is missing sectors")
	return snapshotImage(image)
end

RawImageCatalog.ProtectedModeBringUp = buildRawImage("ProtectedModeBringUp")

function RawImageCatalog.get(name)
	return RawImageCatalog[name]
end

return RawImageCatalog
