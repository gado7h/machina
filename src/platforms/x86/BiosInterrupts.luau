local BiosInterrupts = {}
BiosInterrupts.__index = BiosInterrupts

local function scanCodeForChar(ch)
	if ch == "\n" or ch == "\r" then
		return 0x1C
	end
	if ch == "\b" then
		return 0x0E
	end
	return 0
end

local function biosCharValue(ch)
	if ch == "\n" or ch == "\r" then
		return 13
	end
	if ch == "\b" then
		return 8
	end
	return string.byte(ch)
end

function BiosInterrupts.new(machine, runtime, image)
	local self = setmetatable({}, BiosInterrupts)
	self.machine = machine
	self.runtime = runtime
	self.image = image or {}
	self.config = machine.config
	self.x86 = machine.config.X86 or {}
	self._keyboardLatch = nil
	return self
end

function BiosInterrupts:_setCarry(cpu, enabled)
	cpu:setFlag(0x0001, enabled)
end

function BiosInterrupts:_setDiskStatus(cpu, status)
	cpu:setReg8(4, status % 0x100)
end

function BiosInterrupts:_teletype(cpu)
	local ch = cpu:getReg8(0)
	self.machine.gpu:biosTeletype(ch == 0 and 32 or ch, 0x07)
	self:_setCarry(cpu, false)
end

function BiosInterrupts:_setVideoMode(cpu)
	local mode = cpu:getReg8(0)
	self.machine.gpu:biosSetVideoMode(mode)
	self:_setCarry(cpu, false)
end

function BiosInterrupts:_getCursorPosition(cpu)
	local page = bit32.band(cpu:getReg8(2), 0x0F)
	local row = 0
	local col = 0
	if self.machine.gpu.getCursorPos then
		row, col = self.machine.gpu:getCursorPos(page)
	end
	cpu:setReg8(3, row)
	cpu:setReg8(2, col)
	self:_setCarry(cpu, false)
end

function BiosInterrupts:_setCursorPosition(cpu)
	local page = bit32.band(cpu:getReg8(2), 0x0F)
	local row = cpu:getReg8(1)
	local col = cpu:getReg8(0)
	if self.machine.gpu.setCursorPos then
		self.machine.gpu:setCursorPos(page, row, col)
	end
	self:_setCarry(cpu, false)
end

function BiosInterrupts:_setCursorType(cpu)
	local start = cpu:getReg8(1)
	local endLine = cpu:getReg8(0)
	if self.machine.gpu.setCursorType then
		self.machine.gpu:setCursorType(start, endLine)
	end
	self:_setCarry(cpu, false)
end

function BiosInterrupts:_scrollWindow(cpu)
	local lines = cpu:getReg8(0)
	local attr = cpu:getReg8(1)
	local top = bit32.rshift(bit32.band(cpu:getReg8(2), 0xFF), 8)
	local left = cpu:getReg8(2)
	local bottom = bit32.rshift(bit32.band(cpu:getReg8(3), 0xFF), 8)
	local right = cpu:getReg8(3)
	local page = bit32.band(cpu:getReg8(4), 0x0F)
	if self.machine.gpu.scrollWindow then
		self.machine.gpu:scrollWindow(page, top, left, bottom, right, lines, attr)
	end
	self:_setCarry(cpu, false)
end

function BiosInterrupts:_readCharAttr(cpu)
	local page = bit32.band(cpu:getReg8(2), 0x0F)
	local char = 0
	local attr = 0
	if self.machine.gpu.readCharAttr then
		char, attr = self.machine.gpu:readCharAttr(page)
	end
	cpu:setReg8(0, char)
	cpu:setReg8(1, attr)
	self:_setCarry(cpu, false)
end

function BiosInterrupts:_writeCharAttr(cpu)
	local char = cpu:getReg8(0)
	local attr = cpu:getReg8(1)
	local count = cpu:getReg16(2)
	local page = bit32.band(cpu:getReg8(4), 0x0F)
	if self.machine.gpu.writeCharAttr then
		self.machine.gpu:writeCharAttr(page, char, attr, count)
	end
	self:_setCarry(cpu, false)
end

function BiosInterrupts:_getVideoMode(cpu)
	local mode = 0x03
	local cols = 80
	local page = 0
	if self.machine.gpu.getVideoMode then
		mode, cols, page = self.machine.gpu:getVideoMode()
	end
	cpu:setReg8(0, mode)
	cpu:setReg8(1, cols)
	cpu:setReg8(2, page)
	self:_setCarry(cpu, false)
end

function BiosInterrupts:_chsToLba(cylinder, head, sector)
	local spt = self.x86.SECTORS_PER_TRACK or 18
	local heads = self.x86.HEADS or 1
	if sector <= 0 or sector > spt or head < 0 or head >= heads or cylinder < 0 then
		return nil
	end
	return ((cylinder * heads + head) * spt) + (sector - 1)
end

function BiosInterrupts:_readSectors(cpu)
	local count = cpu:getReg8(0)
	local cl = cpu:getReg8(1)
	local cylinder = bit32.bor(cpu:getReg8(5), bit32.lshift(bit32.band(cl, 0xC0), 2))
	local sector = bit32.band(cl, 0x3F)
	local head = cpu:getReg8(6)
	local drive = cpu:getReg8(2)
	local bufferAddress = cpu:linearAddress(cpu.seg.ES, cpu:getReg16(3))

	if drive ~= (self.x86.BOOT_DRIVE or 0x80) then
		self:_setCarry(cpu, true)
		self:_setDiskStatus(cpu, 0x01)
		return true
	end

	local startLba = self:_chsToLba(cylinder, head, sector)
	if not startLba then
		self:_setCarry(cpu, true)
		self:_setDiskStatus(cpu, 0x04)
		return true
	end
	local totalSectors = self.machine.hdd.getTotalSectors and self.machine.hdd:getTotalSectors()
		or self.machine.hdd.totalSectors
	if (startLba + math.max(0, count - 1)) >= (tonumber(totalSectors) or 0) then
		self:_setCarry(cpu, true)
		self:_setDiskStatus(cpu, 0x04)
		return true
	end

	for sectorIndex = 0, math.max(0, count - 1) do
		local bytes = self.machine.hdd:readSector(startLba + sectorIndex)
		for i = 1, #bytes do
			cpu:writePhysical8(bufferAddress + sectorIndex * 512 + i - 1, bytes[i])
		end
	end

	if self.runtime and type(self.runtime.onDiskRead) == "function" then
		self.runtime:onDiskRead(startLba, count, bufferAddress)
	end

	self:_setCarry(cpu, false)
	self:_setDiskStatus(cpu, 0x00)
	cpu:setReg8(0, count)
	return true
end

function BiosInterrupts:_writeSectors(cpu)
	local count = cpu:getReg8(0)
	local cl = cpu:getReg8(1)
	local cylinder = bit32.bor(cpu:getReg8(5), bit32.lshift(bit32.band(cl, 0xC0), 2))
	local sector = bit32.band(cl, 0x3F)
	local head = cpu:getReg8(6)
	local drive = cpu:getReg8(2)
	local bufferAddress = cpu:linearAddress(cpu.seg.ES, cpu:getReg16(3))

	if drive ~= (self.x86.BOOT_DRIVE or 0x80) then
		self:_setCarry(cpu, true)
		self:_setDiskStatus(cpu, 0x01)
		return true
	end

	local startLba = self:_chsToLba(cylinder, head, sector)
	if not startLba then
		self:_setCarry(cpu, true)
		self:_setDiskStatus(cpu, 0x04)
		return true
	end

	local totalSectors = self.machine.hdd.getTotalSectors and self.machine.hdd:getTotalSectors()
		or self.machine.hdd.totalSectors
	if (startLba + math.max(0, count - 1)) >= (tonumber(totalSectors) or 0) then
		self:_setCarry(cpu, true)
		self:_setDiskStatus(cpu, 0x04)
		return true
	end

	for sectorIndex = 0, math.max(0, count - 1) do
		local bytes = {}
		for i = 1, 512 do
			bytes[i] = cpu:readPhysical8(bufferAddress + sectorIndex * 512 + i - 1)
		end
		self.machine.hdd:writeSector(startLba + sectorIndex, bytes)
	end

	self:_setCarry(cpu, false)
	self:_setDiskStatus(cpu, 0x00)
	cpu:setReg8(0, count)
	return true
end

function BiosInterrupts:_diskInterrupt(cpu)
	local service = cpu:getReg8(4)
	if service == 0x00 then
		self:_setCarry(cpu, false)
		self:_setDiskStatus(cpu, 0x00)
		return true
	end
	if service == 0x02 then
		return self:_readSectors(cpu)
	end
	if service == 0x03 then
		return self:_writeSectors(cpu)
	end
	self:_setCarry(cpu, true)
	self:_setDiskStatus(cpu, 0x01)
	return true
end

function BiosInterrupts:_keyboardInterrupt(cpu)
	local service = cpu:getReg8(4)
	if service == 0x00 then
		local ch = self._keyboardLatch
		if ch then
			local queued = self.machine.keyboard:peekChar()
			if queued == ch then
				self.machine.keyboard:readChar()
			end
			self._keyboardLatch = nil
		else
			ch = self.machine.keyboard:readChar()
		end
		if not ch then
			self:_setCarry(cpu, false)
			cpu:setFlag(0x0040, true)
			cpu:setReg8(0, 0)
			cpu:setReg8(4, 0)
			return true
		end
		cpu:setReg8(0, biosCharValue(ch))
		cpu:setReg8(4, scanCodeForChar(ch))
		cpu:setFlag(0x0040, false)
		self:_setCarry(cpu, false)
		return true
	end
	if service == 0x01 then
		local ch = self._keyboardLatch or self.machine.keyboard:peekChar()
		if ch then
			self._keyboardLatch = ch
			cpu:setReg8(0, biosCharValue(ch))
			cpu:setReg8(4, scanCodeForChar(ch))
			cpu:setFlag(0x0040, false)
		else
			self._keyboardLatch = nil
			cpu:setFlag(0x0040, true)
		end
		self:_setCarry(cpu, false)
		return true
	end
	return false
end

function BiosInterrupts:_clockInterrupt(cpu)
	local service = cpu:getReg8(4)
	if service == 0x00 then
		local rtc = self.machine.rtc
		local ticks = (rtc and rtc.getBIOSClockTicks and rtc:getBIOSClockTicks())
			or math.floor((os.clock() - (self.machine._uptimeStart or os.clock())) * 18.2)
		cpu:setReg16(1, math.floor(ticks / 0x10000))
		cpu:setReg16(2, ticks % 0x10000)
		self:_setCarry(cpu, false)
		return true
	end
	if service == 0x02 or service == 0x04 then
		local rtc = self.machine.rtc
		if not rtc or type(rtc.readRegister) ~= "function" then
			self:_setCarry(cpu, true)
			return true
		end
		local isDate = service == 0x04
		local regs = isDate and { 0x09, 0x08, 0x07 } or { 0x04, 0x02, 0x00 }
		cpu:setReg8(6, rtc:readRegister(regs[1]))
		cpu:setReg8(2, rtc:readRegister(regs[2]))
		cpu:setReg8(0, rtc:readRegister(regs[3]))
		self:_setCarry(cpu, false)
		return true
	end
	return false
end

function BiosInterrupts:_memorySizeInterrupt(cpu)
	local x86 = self.x86
	local baseMemK = x86.LOW_RAM_SIZE and math.floor(x86.LOW_RAM_SIZE / 1024) or 640
	cpu:setReg16(0, baseMemK)
	self:_setCarry(cpu, false)
	return true
end

function BiosInterrupts:_systemConfigInterrupt(cpu)
	local service = cpu:getReg8(4)
	if service == 0xC0 then
		cpu:setReg8(6, 0x00)
		cpu:setReg16(4, 0xE980)
		cpu:setReg8(0, 0x00)
		cpu:setReg8(1, 0x01)
		cpu:setReg8(2, 0xFC)
		cpu:setReg8(3, 0x00)
		cpu:setReg8(4, 0x00)
		cpu:setReg8(5, 0x70)
		cpu:setReg8(7, 0x00)
		self:_setCarry(cpu, false)
		return true
	end
	if service == 0xC2 then
		local sub = cpu:getReg8(5)
		if sub == 0x00 then
			cpu:setReg8(0, 0x05)
			self:_setCarry(cpu, false)
			return true
		end
	end
	if service == 0x87 then
		local src = cpu:getReg16(2) * 16 + cpu:getReg16(3)
		local dest = cpu:getReg16(6) * 16 + cpu:getReg16(7)
		local count = cpu:getReg16(3)
		for i = 0, count * 2 - 1 do
			local byte = cpu:readPhysical8(src + i)
			cpu:writePhysical8(dest + i, byte)
		end
		cpu:setReg8(0, 0x00)
		self:_setCarry(cpu, false)
		return true
	end
	if service == 0xC5 then
		cpu:setReg8(0, 0x00)
		cpu:setReg8(1, 0x00)
		cpu:setReg8(2, 0x00)
		cpu:setReg8(3, 0x00)
		self:_setCarry(cpu, false)
		return true
	end
	return false
end

function BiosInterrupts:_a20Interrupt(cpu)
	local service = cpu:getReg8(4)
	if service == 0x24 then
		local sub = cpu:getReg8(5)
		if sub == 0x00 then
			cpu:setReg8(0, 0x00)
			local a20Enabled = self.machine.bus and self.machine.bus.isA20Enabled()
			cpu:setReg8(1, a20Enabled and 0x02 or 0x00)
			self:_setCarry(cpu, false)
			return true
		end
		if sub == 0x01 then
			local a20Enabled = bit32.band(cpu:getReg8(6), 0x01) ~= 0
			if self.machine.bus and self.machine.bus.setA20Enabled then
				self.machine.bus:setA20Enabled(a20Enabled)
			end
			cpu:setReg8(0, 0x00)
			self:_setCarry(cpu, false)
			return true
		end
		if sub == 0x02 then
			cpu:setReg8(0, 0x00)
			cpu:setReg8(1, 0x00)
			self:_setCarry(cpu, false)
			return true
		end
	end
	return false
end

function BiosInterrupts:_bootInterrupt(cpu)
	cpu.halted = true
	local reboot = function()
		self.machine:reboot()
	end
	if task and task.delay then
		task.delay(0, reboot)
	else
		reboot()
	end
	return true
end

function BiosInterrupts:handleInterrupt(cpu, vector)
	if vector == 0x10 then
		local service = cpu:getReg8(4)
		if service == 0x0E then
			self:_teletype(cpu)
			return true
		end
		if service == 0x00 then
			self:_setVideoMode(cpu)
			return true
		end
		if service == 0x03 then
			self:_getCursorPosition(cpu)
			return true
		end
		if service == 0x02 then
			self:_setCursorPosition(cpu)
			return true
		end
		if service == 0x01 then
			self:_setCursorType(cpu)
			return true
		end
		if service == 0x06 then
			self:_scrollWindow(cpu)
			return true
		end
		if service == 0x08 then
			self:_readCharAttr(cpu)
			return true
		end
		if service == 0x09 then
			self:_writeCharAttr(cpu)
			return true
		end
		if service == 0x0F then
			self:_getVideoMode(cpu)
			return true
		end
		return true
	end
	if vector == 0x12 then
		return self:_memorySizeInterrupt(cpu)
	end
	if vector == 0x13 then
		return self:_diskInterrupt(cpu)
	end
	if vector == 0x15 then
		if self:_a20Interrupt(cpu) then
			return true
		end
		return self:_systemConfigInterrupt(cpu)
	end
	if vector == 0x16 then
		return self:_keyboardInterrupt(cpu)
	end
	if vector == 0x19 then
		return self:_bootInterrupt(cpu)
	end
	if vector == 0x1A then
		return self:_clockInterrupt(cpu)
	end
	return false
end

return BiosInterrupts
