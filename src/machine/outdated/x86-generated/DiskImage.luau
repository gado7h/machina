local Assembler8086 = require(script.Parent.Assembler8086)
local ExecutableFormat = require(script.Parent.ExecutableFormat)
local FileSystemImage = require(script.Parent.FileSystemImage)
local GuestOS = require(script.Parent.GuestOS)
local SystemBIOS = require(script.Parent.SystemBIOS)

local DiskImage = {}

local function toSector(bytes)
	local sector = {}
	for i = 1, 512 do
		sector[i] = bytes[i] or 0
	end
	return sector
end

local function sectorCountForBytes(bytes)
	return math.max(1, math.ceil(#bytes / 512))
end

local function writeChunk(sectors, startLba, bytes)
	local count = sectorCountForBytes(bytes)
	for sectorIndex = 0, count - 1 do
		local sector = {}
		for i = 1, 512 do
			sector[i] = bytes[sectorIndex * 512 + i] or 0
		end
		sectors[startLba + sectorIndex] = sector
	end
	return count
end

local function stringToBytes(text)
	local bytes = {}
	for i = 1, #text do
		bytes[i] = string.byte(text, i)
	end
	return bytes
end

function DiskImage.build(config)
	local x86 = config.X86 or {}
	local layout = {
		kernelSectorStart = 2,
		kernelSectorCount = 1,
		fsSuperSector = 3,
	}

	local sources
	local kernelArtifact
	for _ = 1, 4 do
		sources = GuestOS.buildSources(config, layout)
		kernelArtifact = Assembler8086.compile(sources.kernel)
		local nextKernelCount = sectorCountForBytes(kernelArtifact.bytes)
		local nextFsSuperSector = layout.kernelSectorStart + nextKernelCount
		if nextKernelCount == layout.kernelSectorCount and nextFsSuperSector == layout.fsSuperSector then
			break
		end
		layout.kernelSectorCount = nextKernelCount
		layout.fsSuperSector = nextFsSuperSector
	end

	sources = GuestOS.buildSources(config, layout)
	local biosArtifact = SystemBIOS.buildArtifact(config)
	local bootArtifact = Assembler8086.compile(sources.bootSector)
	kernelArtifact = Assembler8086.compile(sources.kernel)

	assert(#bootArtifact.bytes <= 512, "boot sector exceeds 512 bytes")

	local files = {}
	for _, spec in ipairs(GuestOS.programs()) do
		local artifact = Assembler8086.compile(sources.programs[spec.command])
		local loadOffset = spec.loadKind == "shell" and (x86.SHELL_LOAD_OFFSET or 0x9000)
			or (x86.PROGRAM_LOAD_OFFSET or 0x8000)
		local executable = ExecutableFormat.wrap(artifact.bytes, {
			headerSize = x86.EXEC_HEADER_SIZE or 32,
			loadOffset = loadOffset,
			entryOffset = loadOffset,
			version = x86.EXEC_VERSION or 1,
		})
		files[#files + 1] = {
			name = spec.fileName,
			typeFlag = FileSystemImage.TYPE_EXEC,
			bytes = executable.bytes,
		}
	end
	for _, file in ipairs(GuestOS.files()) do
		files[#files + 1] = {
			name = file.name,
			typeFlag = FileSystemImage.TYPE_FILE,
			bytes = stringToBytes(file.content),
		}
	end

	local filesystem = FileSystemImage.build(config, layout, files)

	local sectors = {}
	sectors[0] = toSector(bootArtifact.bytes)
	writeChunk(sectors, layout.kernelSectorStart - 1, kernelArtifact.bytes)
	for lba, sector in pairs(filesystem.sectors) do
		sectors[lba] = sector
	end

	return {
		romBytes = SystemBIOS.buildROMBytes(config, biosArtifact),
		sectors = sectors,
		layout = {
			kernelSectorStart = layout.kernelSectorStart,
			kernelSectorCount = layout.kernelSectorCount,
			fsSuperSector = filesystem.layout.fsSuperSector,
			rootDirSector = filesystem.layout.rootDirSector,
			rootDirSectorCount = filesystem.layout.rootDirSectorCount,
			dataStartSector = filesystem.layout.dataStartSector,
			fileCount = filesystem.layout.fileCount,
		},
		files = filesystem.entries,
		symbols = {
			bios = biosArtifact.symbols,
			bootSector = bootArtifact.symbols,
			kernel = kernelArtifact.symbols,
		},
	}
end

return DiskImage
