local BootImageCatalog = require(script.Parent.BootImageCatalog)
local BiosRom = require(script.Parent.BiosRom)
local RawImageCatalog = require(script.Parent.RawImageCatalog)
local ImportedImageCatalog = require(script.Parent.ImportedImageCatalog)

local BootImageLoader = {}

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

local function normalizeImage(image, meta)
	assert(type(image) == "table", "x86 image loader expected an image table")
	assert(image.sectors ~= nil or image.diskBytes ~= nil, "x86 image is missing sectors/diskBytes")

	local romBytes = image.romBytes
	if romBytes == nil then
		local artifact = BiosRom.buildArtifact(meta.config)
		romBytes = BiosRom.buildROMBytes(meta.config, artifact)
	end
	local normalizedRom = BootImageLoader._normalizeByteArray(romBytes)
	local normalizedSectors = image.sectors and BootImageLoader._normalizeSectors(image.sectors)
		or BootImageLoader._diskBytesToSectors(image.diskBytes, image.diskStartLba or 0)

	local normalized = {
		name = image.name,
		romBytes = normalizedRom,
		sectors = normalizedSectors,
		layout = deepCopy(image.layout or {}),
		files = image.files or {},
		symbols = image.symbols or {},
	}
	normalized.meta = {
		source = meta.source,
		provider = meta.provider,
		name = meta.name or meta.provider,
	}

	normalized.layout.kernelSectorStart = normalized.layout.kernelSectorStart or 2
	normalized.layout.kernelSectorCount = normalized.layout.kernelSectorCount or 1
	normalized.layout.fsSuperSector = normalized.layout.fsSuperSector or 0
	normalized.layout.rootDirSector = normalized.layout.rootDirSector or 0
	normalized.layout.rootDirSectorCount = normalized.layout.rootDirSectorCount or 0
	normalized.layout.dataStartSector = normalized.layout.dataStartSector or 0
	normalized.layout.fileCount = normalized.layout.fileCount or #(normalized.files or {})

	return normalized
end

function BootImageLoader._normalizeByteArray(value)
	if type(value) == "table" then
		local out = {}
		for index, byte in ipairs(value) do
			out[index] = (tonumber(byte) or 0) % 256
		end
		return out
	end
	if type(value) == "string" then
		local out = {}
		for index = 1, #value do
			out[index] = string.byte(value, index)
		end
		return out
	end
	error("x86 image byte payload must be a table or string")
end

function BootImageLoader._normalizeSectorPayload(sector)
	local normalized = BootImageLoader._normalizeByteArray(sector)
	local out = {}
	for index = 1, 512 do
		out[index] = normalized[index] or 0
	end
	return out
end

function BootImageLoader._normalizeSectors(sectors)
	assert(type(sectors) == "table", "x86 sectors payload must be a table")
	local out = {}
	for lba, sector in pairs(sectors) do
		out[tonumber(lba) or 0] = BootImageLoader._normalizeSectorPayload(sector)
	end
	return out
end

function BootImageLoader._diskBytesToSectors(diskBytes, startLba)
	local bytes = BootImageLoader._normalizeByteArray(diskBytes)
	local sectors = {}
	local sectorCount = math.max(1, math.ceil(#bytes / 512))
	for sectorIndex = 0, sectorCount - 1 do
		local sector = {}
		for byteIndex = 1, 512 do
			sector[byteIndex] = bytes[sectorIndex * 512 + byteIndex] or 0
		end
		sectors[(tonumber(startLba) or 0) + sectorIndex] = sector
	end
	return sectors
end

local function providerImage(provider, config)
	if type(provider) == "function" then
		return provider(config)
	end
	if type(provider) == "table" and type(provider.build) == "function" then
		return provider.build(config)
	end
	if type(provider) == "table" then
		return provider
	end
	error("invalid external x86 image provider")
end

local function rawImage(rawEntry, _config)
	if type(rawEntry) == "function" then
		return rawEntry()
	end
	if type(rawEntry) == "table" then
		return rawEntry
	end
	error("invalid raw x86 image entry")
end

function BootImageLoader.load(config)
	local x86 = config.X86 or {}
	local imageConfig = x86.IMAGE or {}
	local source = tostring(
		imageConfig.SOURCE
			or (imageConfig.IMPORT_IMAGE and "imported")
			or (imageConfig.RAW_IMAGE and "raw")
			or "provider"
	)
	if source == "imported" then
		local importName = tostring(imageConfig.IMPORT_IMAGE or imageConfig.NAME or "ProtectedModeBringUp")
		local importedEntry = ImportedImageCatalog[importName]
		assert(importedEntry, "unknown x86 imported image entry: " .. importName)
		local image = rawImage(importedEntry, config)
		return normalizeImage(image, {
			config = config,
			source = "imported",
			provider = importName,
			name = image and image.name or importName,
		})
	end
	if source == "raw" then
		local rawName = tostring(imageConfig.RAW_IMAGE or imageConfig.NAME or "ProtectedModeBringUp")
		local rawEntry = RawImageCatalog[rawName]
		assert(rawEntry, "unknown x86 raw image entry: " .. rawName)
		local image = rawImage(rawEntry, config)
		return normalizeImage(image, {
			config = config,
			source = "raw",
			provider = rawName,
			name = image and image.name or rawName,
		})
	end

	local providerName = tostring(imageConfig.PROVIDER or imageConfig.NAME or "ProtectedModeBringUp")
	local provider = BootImageCatalog[providerName]
	assert(provider, "unknown x86 external image provider: " .. providerName)
	local image = providerImage(provider, config)
	return normalizeImage(image, {
		config = config,
		source = "provider",
		provider = providerName,
		name = image and image.name or providerName,
	})
end

return BootImageLoader
