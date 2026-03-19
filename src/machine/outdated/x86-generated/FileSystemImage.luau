local FileSystemImage = {}

FileSystemImage.MAGIC = "NXFS"
FileSystemImage.VERSION = 1
FileSystemImage.ENTRY_SIZE = 32
FileSystemImage.NAME_SIZE = 11
FileSystemImage.TYPE_FILE = 0x01
FileSystemImage.TYPE_EXEC = 0x81

local function toSector(bytes, blockSize, offset)
	local sector = {}
	for i = 1, blockSize do
		sector[i] = bytes[(offset or 0) + i] or 0
	end
	return sector
end

local function writeWord(bytes, index, value)
	local v = (tonumber(value) or 0) % 0x10000
	bytes[index] = v % 256
	bytes[index + 1] = math.floor(v / 256) % 256
end

local function sectorCountForBytes(bytes, blockSize)
	return math.max(1, math.ceil(#bytes / blockSize))
end

local function writeChunk(sectors, startLba, bytes, blockSize)
	local count = sectorCountForBytes(bytes, blockSize)
	for sectorIndex = 0, count - 1 do
		sectors[startLba + sectorIndex] = toSector(bytes, blockSize, sectorIndex * blockSize)
	end
	return count
end

local function normalizeName(name)
	local text = string.lower(tostring(name or "")):gsub("[/\\]+", "_")
	if text == "" then
		text = "file"
	end
	return text:sub(1, FileSystemImage.NAME_SIZE)
end

local function encodeName(name)
	local bytes = {}
	for i = 1, FileSystemImage.NAME_SIZE do
		bytes[i] = 32
	end
	for i = 1, math.min(#name, FileSystemImage.NAME_SIZE) do
		bytes[i] = string.byte(name, i)
	end
	return bytes
end

local function buildRootDirectory(entries, blockSize)
	local bytes = {}
	for index, entry in ipairs(entries) do
		local base = ((index - 1) * FileSystemImage.ENTRY_SIZE) + 1
		for i = 1, FileSystemImage.NAME_SIZE do
			bytes[base + i - 1] = entry.nameBytes[i]
		end
		bytes[base + 11] = entry.typeFlag % 256
		writeWord(bytes, base + 12, entry.sectorNumber)
		writeWord(bytes, base + 14, entry.sectorCount)
		writeWord(bytes, base + 16, entry.byteSize)
	end

	local sectors = {}
	local sectorCount = math.max(1, math.ceil((#entries * FileSystemImage.ENTRY_SIZE) / blockSize))
	for sectorIndex = 0, sectorCount - 1 do
		sectors[#sectors + 1] = toSector(bytes, blockSize, sectorIndex * blockSize)
	end
	return sectors, sectorCount
end

local function buildSuperblock(layout, blockSize)
	local bytes = {}
	bytes[1] = string.byte("N")
	bytes[2] = string.byte("X")
	bytes[3] = string.byte("F")
	bytes[4] = string.byte("S")
	bytes[5] = FileSystemImage.VERSION
	bytes[6] = 0
	writeWord(bytes, 7, blockSize)
	writeWord(bytes, 9, layout.rootDirSector)
	writeWord(bytes, 11, layout.rootDirSectorCount)
	writeWord(bytes, 13, layout.dataStartSector)
	writeWord(bytes, 15, layout.fileCount)
	writeWord(bytes, 17, FileSystemImage.ENTRY_SIZE)
	writeWord(bytes, 19, FileSystemImage.NAME_SIZE)
	return toSector(bytes, blockSize, 0)
end

function FileSystemImage.build(config, layout, files)
	local blockSize = config.DISK_BLOCK_SIZE or 512
	local rootDirSectorCount = math.max(1, math.ceil((#files * FileSystemImage.ENTRY_SIZE) / blockSize))
	local fsLayout = {
		fsSuperSector = layout.fsSuperSector,
		rootDirSector = layout.fsSuperSector + 1,
		rootDirSectorCount = rootDirSectorCount,
		dataStartSector = layout.fsSuperSector + 1 + rootDirSectorCount,
	}

	local sectors = {}
	local entries = {}
	local nextSector = fsLayout.dataStartSector

	for _, file in ipairs(files or {}) do
		local name = normalizeName(file.name)
		local count = sectorCountForBytes(file.bytes, blockSize)
		local entry = {
			name = name,
			nameBytes = encodeName(name),
			typeFlag = file.typeFlag or FileSystemImage.TYPE_FILE,
			sectorNumber = nextSector,
			sectorCount = count,
			byteSize = #file.bytes,
		}
		entries[#entries + 1] = entry
		writeChunk(sectors, nextSector - 1, file.bytes, blockSize)
		nextSector = nextSector + count
	end

	fsLayout.fileCount = #entries
	sectors[fsLayout.fsSuperSector - 1] = buildSuperblock(fsLayout, blockSize)
	local rootDirSectors = buildRootDirectory(entries, blockSize)
	for index, sector in ipairs(rootDirSectors) do
		sectors[(fsLayout.rootDirSector - 1) + (index - 1)] = sector
	end

	return {
		layout = fsLayout,
		entries = entries,
		sectors = sectors,
	}
end

return FileSystemImage
