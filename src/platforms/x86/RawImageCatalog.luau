local BootImageCatalog = require("@src/platforms/x86/BootImageCatalog")
local Config = require("@src/Config")
local ImageCatalogUtils = require("@src/platforms/x86/ImageCatalogUtils")

local RawImageCatalog = {}

local function buildCatalogImage(entryName)
	local entry = BootImageCatalog[entryName]
	assert(entry, "unknown x86 raw image entry: " .. tostring(entryName))

	if type(entry) == "table" and type(entry.build) == "function" then
		return entry.build(Config)
	end
	return entry
end

local function snapshotImage(image)
	assert(type(image) == "table", "x86 raw image builder returned an invalid image")
	assert(type(image.romBytes) == "table", "x86 raw image is missing romBytes")
	assert(type(image.sectors) == "table", "x86 raw image is missing sectors")

	return {
		name = image.name,
		romBytes = ImageCatalogUtils.deepCopy(image.romBytes),
		diskBytes = ImageCatalogUtils.sectorsToDiskBytes(image.sectors),
		layout = ImageCatalogUtils.deepCopy(image.layout or {}),
		files = ImageCatalogUtils.deepCopy(image.files or {}),
		symbols = ImageCatalogUtils.deepCopy(image.symbols or {}),
	}
end

local function buildRawImage(entryName)
	return snapshotImage(buildCatalogImage(entryName))
end

RawImageCatalog.ProtectedModeBringUp = buildRawImage("ProtectedModeBringUp")

function RawImageCatalog.get(name)
	return RawImageCatalog[name]
end

return RawImageCatalog
