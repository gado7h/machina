-- HDD module

local HDD = {}
HDD.__index = HDD

local SECTOR_SIZE = 512

local MBR_SIGNATURE_LO = 0x55
local MBR_SIGNATURE_HI = 0xAA

function HDD.new(config)
	local self = setmetatable({}, HDD)
	self.config = config
	self.sectorSize = SECTOR_SIZE
	self.totalSectors = config.DISK_BLOCKS
	self._sectors = {} -- lba → {512 bytes as table}
	self._activity = false -- for LED blinking
	self._headPos = 0 -- simulated head position (for seek time)

	self.stats = { reads = 0, writes = 0, seeks = 0, errors = 0 }

	-- Pre-format with blank sectors
	self:_initMBR()
	return self
end

--  Low-level sector I/O

local function blankSector()
	local s = {}
	for i = 1, SECTOR_SIZE do
		s[i] = 0
	end
	return s
end

function HDD:readSector(lba)
	self.stats.reads = self.stats.reads + 1
	self._activity = true
	if lba < 0 or lba >= self.totalSectors then
		self.stats.errors = self.stats.errors + 1
		return blankSector()
	end
	-- Simulate seek
	local dist = math.abs(lba - self._headPos)
	self._headPos = lba
	if dist > 1000 then
		self.stats.seeks = self.stats.seeks + 1
	end
	return self._sectors[lba] or blankSector()
end

function HDD:writeSector(lba, data)
	self.stats.writes = self.stats.writes + 1
	self._activity = true
	if lba < 0 or lba >= self.totalSectors then
		self.stats.errors = self.stats.errors + 1
		return false
	end
	-- Ensure sector is exactly 512 bytes
	local s = {}
	for i = 1, SECTOR_SIZE do
		s[i] = (data[i] or 0) % 256
	end
	self._sectors[lba] = s
	self._headPos = lba
	return true
end

--- Read multiple consecutive sectors
function HDD:readSectors(startLba, count)
	local out = {}
	for i = 0, count - 1 do
		local s = self:readSector(startLba + i)
		for _, b in ipairs(s) do
			table.insert(out, b)
		end
	end
	return out
end

function HDD:writeSectors(startLba, bytes)
	local scount = math.ceil(#bytes / SECTOR_SIZE)
	for i = 0, scount - 1 do
		local s = {}
		for j = 1, SECTOR_SIZE do
			s[j] = bytes[i * SECTOR_SIZE + j] or 0
		end
		self:writeSector(startLba + i, s)
	end
end

--  Memory-mapped bus interface
-- Maps as MMIO: command register at offset 0, data buffer at offset 512

function HDD:memRead(offset)
	if offset < SECTOR_SIZE then
		return self._ioBuffer and self._ioBuffer[offset + 1] or 0
	end
	return 0
end

function HDD:memWrite(offset, value)
	if offset == 0 then
		-- command byte: 0=NOP, 1=READ, 2=WRITE
		if value == 1 and self._ioLBA then
			local s = self:readSector(self._ioLBA)
			self._ioBuffer = s
		elseif value == 2 and self._ioLBA and self._ioBuffer then
			self:writeSector(self._ioLBA, self._ioBuffer)
		end
	elseif offset == 4 then
		self._ioLBA = (self._ioLBA or 0)
		self._ioLBA = value -- simplified: single-byte LBA (enough for sim)
	elseif offset >= 512 and offset < 1024 then
		if not self._ioBuffer then
			self._ioBuffer = blankSector()
		end
		self._ioBuffer[offset - 511] = value % 256
	end
end

--  MBR initialization

function HDD:_initMBR()
	local mbr = blankSector()
	-- Boot code placeholder (JMP to 0x7C00 style)
	mbr[1] = 0xEB
	mbr[2] = 0x58
	mbr[3] = 0x90 -- JMP short + NOP

	-- Disk signature at offset 440
	mbr[441] = 0x4E
	mbr[442] = 0x56
	mbr[443] = 0x4D
	mbr[444] = 0x41 -- "NVMA"

	-- Partition entry 1 at offset 446 (1-indexed = 447)
	-- Status=0x80 (bootable), type=0x83 (Linux), LBA start=63, size=204737
	local pe = 447
	mbr[pe + 0] = 0x80 -- bootable
	mbr[pe + 1] = 0x00
	mbr[pe + 2] = 0x02
	mbr[pe + 3] = 0x03 -- CHS start
	mbr[pe + 4] = 0x83 -- type: Linux filesystem
	mbr[pe + 5] = 0xFF
	mbr[pe + 6] = 0xFF
	mbr[pe + 7] = 0xFF -- CHS end
	-- LBA start = 63 (little-endian 32-bit)
	mbr[pe + 8] = 63
	mbr[pe + 9] = 0
	mbr[pe + 10] = 0
	mbr[pe + 11] = 0
	-- LBA size = totalSectors - 63
	local sz = self.totalSectors - 63
	mbr[pe + 12] = sz % 256
	mbr[pe + 13] = math.floor(sz / 256) % 256
	mbr[pe + 14] = math.floor(sz / 65536) % 256
	mbr[pe + 15] = math.floor(sz / 16777216) % 256

	-- MBR signature
	mbr[511] = MBR_SIGNATURE_LO
	mbr[512] = MBR_SIGNATURE_HI

	self._sectors[0] = mbr
end

--  Helpers: byte packing / unpacking

function HDD:readUInt32(sector, offset)
	local s = self:readSector(sector)
	local b0 = s[offset + 1] or 0
	local b1 = s[offset + 2] or 0
	local b2 = s[offset + 3] or 0
	local b3 = s[offset + 4] or 0
	return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

function HDD:writeUInt32(sector, offset, value)
	local s = self._sectors[sector] or blankSector()
	s[offset + 1] = value % 256
	s[offset + 2] = math.floor(value / 256) % 256
	s[offset + 3] = math.floor(value / 65536) % 256
	s[offset + 4] = math.floor(value / 16777216) % 256
	self._sectors[sector] = s
end

function HDD:readString(sector, offset, length)
	local s = self:readSector(sector)
	local chars = {}
	for i = 1, length do
		local b = s[offset + i] or 0
		if b == 0 then
			break
		end
		table.insert(chars, string.char(b))
	end
	return table.concat(chars)
end

function HDD:writeString(sector, offset, str, fieldLen)
	local s = self._sectors[sector] or blankSector()
	for i = 1, fieldLen or #str do
		s[offset + i] = (i <= #str) and string.byte(str, i) or 0
	end
	self._sectors[sector] = s
end

function HDD:isActive()
	local a = self._activity
	self._activity = false
	return a
end

function HDD:getStats()
	return self.stats
end
function HDD:getSectorSize()
	return self.sectorSize
end
function HDD:getTotalSectors()
	return self.totalSectors
end

return HDD
