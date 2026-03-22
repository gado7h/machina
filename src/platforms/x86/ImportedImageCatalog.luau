local BootImageCatalog = require(script.Parent.BootImageCatalog)

local ImportedImageCatalog = {}

local FROZEN_IMPORT_CONFIG = {
	X86 = {
		BOOT_DRIVE = 0x80,
		BIOS_ENTRY_OFFSET = 0x0100,
		RESET_VECTOR_SEG = 0xF000,
		RESET_VECTOR_OFF = 0xFFF0,
		KERNEL_LOAD_SEG = 0x1000,
		KERNEL_LOAD_OFF = 0x0000,
		VIDEO_BASE = 0x000A0000,
		VIDEO_SIZE = 0x20000,
		TEXT_BUFFER_BASE = 0x000B8000,
		TEXT_BUFFER_SIZE = 0x8000,
		SECTORS_PER_TRACK = 18,
		HEADS = 1,
	},
}

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

local function buildImportedImage(entryName)
	local entry = BootImageCatalog[entryName]
	assert(entry, "unknown x86 imported image entry: " .. tostring(entryName))

	local image = entry
	if type(entry) == "table" and type(entry.build) == "function" then
		image = entry.build(deepCopy(FROZEN_IMPORT_CONFIG))
	end

	assert(type(image) == "table", "x86 imported image builder returned an invalid image")
	assert(type(image.sectors) == "table", "x86 imported image is missing sectors")

	return {
		name = image.name,
		diskBytes = sectorsToDiskBytes(image.sectors),
		layout = deepCopy(image.layout or {}),
		files = deepCopy(image.files or {}),
		symbols = deepCopy(image.symbols or {}),
	}
end

ImportedImageCatalog.ProtectedModeBringUp = buildImportedImage("ProtectedModeBringUp")

function ImportedImageCatalog.get(name)
	return ImportedImageCatalog[name]
end

return ImportedImageCatalog
