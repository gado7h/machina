-- HDD module

local HDD = {}
HDD.__index = HDD

local SECTOR_SIZE = 512
local DATA_WINDOW_OFF = 0x200 -- keeps compatibility with previous layout
local DATA_WINDOW_END = DATA_WINDOW_OFF + SECTOR_SIZE - 1

local STATUS_ERR = 0x01
local STATUS_DRQ = 0x08
local STATUS_DSC = 0x10
local STATUS_DRDY = 0x40
local STATUS_BSY = 0x80

local CMD_READ = 0x20
local CMD_WRITE = 0x30
local CMD_IDENTIFY = 0xEC

local MBR_SIGNATURE_LO = 0x55
local MBR_SIGNATURE_HI = 0xAA

local function blankSector()
	local s = {}
	for i = 1, SECTOR_SIZE do
		s[i] = 0
	end
	return s
end

function HDD.new(config)
	local self = setmetatable({}, HDD)
	self.config = config
	self.sectorSize = SECTOR_SIZE
	self.totalSectors = config.DISK_BLOCKS
	self._sectors = {}
	self._activity = false
	self._headPos = 0
	self._bus = nil

	self._status = bit32.bor(STATUS_DRDY, STATUS_DSC)
	self._error = 0
	self._cmd = 0
	self._irqEnabled = 1
	self._sectorCount = 1
	self._lba0 = 0
	self._lba1 = 0
	self._lba2 = 0
	self._lba3 = 0
	self._ioBuffer = blankSector()
	self._pending = nil

	self.stats = {
		reads = 0,
		writes = 0,
		seeks = 0,
		errors = 0,
		commands = 0,
		irqRaised = 0,
	}

	self:_initMBR()
	return self
end

function HDD:attachBus(bus)
	self._bus = bus
end

function HDD:_setError(code)
	self._error = code or 1
	self._status = bit32.bor(bit32.band(self._status, bit32.bnot(STATUS_BSY)), STATUS_ERR)
	self.stats.errors = self.stats.errors + 1
end

function HDD:_clearError()
	self._error = 0
	self._status = bit32.band(self._status, bit32.bnot(STATUS_ERR))
end

function HDD:_lba()
	return self._lba0 + self._lba1 * 256 + self._lba2 * 65536 + self._lba3 * 16777216
end

function HDD:_setLBA(v)
	v = tonumber(v) or 0
	self._lba0 = v % 256
	self._lba1 = math.floor(v / 256) % 256
	self._lba2 = math.floor(v / 65536) % 256
	self._lba3 = math.floor(v / 16777216) % 256
end

function HDD:_estimateLatencySec(lba)
	local dist = math.abs(lba - self._headPos)
	return 0.001 + (dist / 250000)
end

function HDD:_raiseIRQ(kind, lba)
	if self._irqEnabled ~= 0 and self._bus then
		local irq = (self.config.IRQ and self.config.IRQ.ATA) or 14
		self._bus:raiseIRQ(irq, { source = "hdd", event = kind, lba = lba })
		self.stats.irqRaised = self.stats.irqRaised + 1
	end
end

function HDD:_issueCommand(cmd)
	self.stats.commands = self.stats.commands + 1
	self._cmd = cmd
	self:_clearError()
	self._status = bit32.bor(STATUS_BSY, STATUS_DRDY)

	local lba = self:_lba()
	local count = math.max(1, self._sectorCount)
	if lba < 0 or lba >= self.totalSectors then
		self:_setError(0x04)
		return
	end

	local normalized = cmd
	-- Legacy compatibility with previous MMIO model.
	if cmd == 1 then
		normalized = CMD_READ
	elseif cmd == 2 then
		normalized = CMD_WRITE
	end

	if normalized ~= CMD_READ and normalized ~= CMD_WRITE and normalized ~= CMD_IDENTIFY then
		self:_setError(0x01)
		return
	end

	self._pending = {
		cmd = normalized,
		lba = lba,
		count = count,
		remaining = self:_estimateLatencySec(lba),
	}
end

function HDD:_finishCommand(op)
	self._pending = nil
	self._status = bit32.bor(STATUS_DRDY, STATUS_DSC)
	self:_clearError()

	if op.cmd == CMD_READ then
		local s = self:readSector(op.lba)
		self._ioBuffer = s
		self._status = bit32.bor(self._status, STATUS_DRQ)
		self:_raiseIRQ("read-complete", op.lba)
	elseif op.cmd == CMD_WRITE then
		self:writeSector(op.lba, self._ioBuffer)
		self:_raiseIRQ("write-complete", op.lba)
	elseif op.cmd == CMD_IDENTIFY then
		local id = blankSector()
		id[1] = 0x40
		id[2] = 0x00
		local model = tostring(self.config.DISK_MODEL or "Nova Virtual ATA")
		for i = 1, math.min(#model, 40) do
			id[55 + i] = string.byte(model, i)
		end
		self._ioBuffer = id
		self._status = bit32.bor(self._status, STATUS_DRQ)
		self:_raiseIRQ("identify-complete", op.lba)
	end
end

function HDD:tick(dt)
	if not self._pending then
		return
	end
	dt = tonumber(dt) or 0
	if dt <= 0 then
		return
	end
	self._pending.remaining = self._pending.remaining - dt
	if self._pending.remaining <= 0 then
		self:_finishCommand(self._pending)
	end
end

-- Low-level sector I/O

function HDD:readSector(lba)
	self.stats.reads = self.stats.reads + 1
	self._activity = true
	if lba < 0 or lba >= self.totalSectors then
		self.stats.errors = self.stats.errors + 1
		return blankSector()
	end
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
	local s = {}
	for i = 1, SECTOR_SIZE do
		s[i] = (data[i] or 0) % 256
	end
	self._sectors[lba] = s
	self._headPos = lba
	return true
end

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

-- MMIO registers (ATA-like)
-- 0x00: command (write) / status (read mirror)
-- 0x01: status
-- 0x02: error
-- 0x03: irq enable
-- 0x04..0x07: LBA0..LBA3
-- 0x08: sector count
-- 0x200..0x3FF: data buffer

function HDD:memRead(offset)
	offset = tonumber(offset) or -1
	if offset == 0x00 or offset == 0x01 then
		return self._status
	elseif offset == 0x02 then
		return self._error
	elseif offset == 0x03 then
		return self._irqEnabled
	elseif offset == 0x04 then
		return self._lba0
	elseif offset == 0x05 then
		return self._lba1
	elseif offset == 0x06 then
		return self._lba2
	elseif offset == 0x07 then
		return self._lba3
	elseif offset == 0x08 then
		return self._sectorCount
	elseif offset >= DATA_WINDOW_OFF and offset <= DATA_WINDOW_END then
		return self._ioBuffer[offset - DATA_WINDOW_OFF + 1] or 0
	end
	self:_setError(0x10)
	return 0xFF
end

function HDD:memWrite(offset, value)
	offset = tonumber(offset) or -1
	value = (tonumber(value) or 0) % 256
	if offset == 0x00 then
		self:_issueCommand(value)
		return
	elseif offset == 0x03 then
		self._irqEnabled = value
		return
	elseif offset == 0x04 then
		self._lba0 = value
		return
	elseif offset == 0x05 then
		self._lba1 = value
		return
	elseif offset == 0x06 then
		self._lba2 = value
		return
	elseif offset == 0x07 then
		self._lba3 = value
		return
	elseif offset == 0x08 then
		self._sectorCount = value == 0 and 1 or value
		return
	elseif offset >= DATA_WINDOW_OFF and offset <= DATA_WINDOW_END then
		self._ioBuffer[offset - DATA_WINDOW_OFF + 1] = value
		return
	end
	self:_setError(0x10)
end

function HDD:_initMBR()
	local mbr = blankSector()
	mbr[1] = 0xEB
	mbr[2] = 0x58
	mbr[3] = 0x90

	mbr[441] = 0x4E
	mbr[442] = 0x56
	mbr[443] = 0x4D
	mbr[444] = 0x41

	local pe = 447
	mbr[pe + 0] = 0x80
	mbr[pe + 1] = 0x00
	mbr[pe + 2] = 0x02
	mbr[pe + 3] = 0x03
	mbr[pe + 4] = 0x83
	mbr[pe + 5] = 0xFF
	mbr[pe + 6] = 0xFF
	mbr[pe + 7] = 0xFF
	mbr[pe + 8] = 63
	mbr[pe + 9] = 0
	mbr[pe + 10] = 0
	mbr[pe + 11] = 0
	local sz = self.totalSectors - 63
	mbr[pe + 12] = sz % 256
	mbr[pe + 13] = math.floor(sz / 256) % 256
	mbr[pe + 14] = math.floor(sz / 65536) % 256
	mbr[pe + 15] = math.floor(sz / 16777216) % 256

	mbr[511] = MBR_SIGNATURE_LO
	mbr[512] = MBR_SIGNATURE_HI
	self._sectors[0] = mbr
end

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
