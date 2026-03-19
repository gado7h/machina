-- BIOS module

local BootProtocol = require(script.Parent.Parent.bootloader.BootProtocol)

local BIOS = {}
BIOS.__index = BIOS

function BIOS.new(machine)
	local self = setmetatable({}, BIOS)
	self.machine = machine
	self.gpu = machine.gpu
	self.ram = machine.ram
	self.rom = machine.rom
	self.hdd = machine.hdd
	self.bus = machine.bus
	self.config = machine.config
	self._logs = {}
	self._memMap = {}
	self._bootDrive = 0x80
	self._bootSector = nil
	self._bootSectorAddr = 0
	return self
end

-- Main POST entry point
function BIOS:run(onComplete)
	self._onComplete = onComplete
	self:_resetCpuForFirmware()
	BootProtocol.writeHandoff(self.machine, {
		stage = BootProtocol.STAGE.RESET,
		flags = 0,
		memMapPtr = self.config.RAM_BASE + BootProtocol.MEMMAP_BASE,
		memMapCount = 0,
		bootDrive = self._bootDrive,
	})
	self:_post()
end

function BIOS:_resetCpuForFirmware()
	local cpu = self.machine.cpu
	if not cpu then
		return
	end
	cpu:reset()
	cpu:setReg("PC", self.config.ROM_BASE)
end

function BIOS:_post()
	local g = self.gpu
	g:clearScreen(0x07)
	g:println("NovaFW v2.1  (C) NovaMachine Project", 0x0F)
	g:println("BIOS POST - Power-On Self-Test", 0x07)
	g:println("", 0x07)

	local steps = {
		{
			name = "CPU Register Test",
			fn = function()
				return self:_testCPU()
			end,
		},
		{
			name = "ROM Integrity Check",
			fn = function()
				return self:_testROM()
			end,
		},
		{
			name = "RAM Sizing and Test",
			fn = function()
				return self:_testRAM()
			end,
		},
		{
			name = "PIC - 8259 Init",
			fn = function()
				return self:_initPIC()
			end,
		},
		{
			name = "PIT - Timer Init (18.2Hz)",
			fn = function()
				return self:_initPIT()
			end,
		},
		{
			name = "VGA - Video Init (80x25)",
			fn = function()
				return self:_initVGA()
			end,
		},
		{
			name = "PCI Bus Enumeration",
			fn = function()
				return self:_enumPCI()
			end,
		},
		{
			name = "CMOS / RTC Read",
			fn = function()
				return self:_readCMOS()
			end,
		},
		{
			name = "HDD - ATA Device Detect",
			fn = function()
				return self:_detectHDD()
			end,
		},
		{
			name = "Build E820 Memory Map",
			fn = function()
				return self:_buildMemMap()
			end,
		},
		{
			name = "Boot Device Select",
			fn = function()
				return self:_selectBootDevice()
			end,
		},
		{
			name = "Read Boot Sector",
			fn = function()
				return self:_loadBootSector()
			end,
		},
	}

	local function runSteps(i)
		if i > #steps then
			self:_postDone()
			return
		end

		local step = steps[i]
		g:print(string.format("  %-36s", step.name), 0x07)
		local ok, msg = step.fn()

		if ok then
			g:println("[ OK ]", 0x0A)
		else
			g:println("[FAIL] " .. (msg or ""), 0x0C)
			if msg and msg:find("FATAL") then
				g:println("", 0x07)
				g:println("FATAL: System cannot continue. Halted.", 0x0C)
				return
			end
		end

		self:_log(step.name .. ": " .. (ok and "OK" or ("FAIL " .. (msg or ""))))
		if task and task.delay then
			task.delay(0.04, function()
				runSteps(i + 1)
			end)
		else
			runSteps(i + 1)
		end
	end

	runSteps(1)
end

-- POST steps
function BIOS:_testCPU()
	local cpu = self.machine.cpu
	if not cpu then
		return false, "No CPU found - FATAL"
	end
	cpu:setReg("R1", 0xDEADBEEF)
	local v = cpu:getReg("R1")
	cpu:setReg("R1", 0)
	if v ~= 0xDEADBEEF then
		return false, "Register R/W mismatch"
	end
	return true
end

function BIOS:_testROM()
	local b0 = self.rom:memRead(0)
	local b1 = self.rom:memRead(1)
	if b0 == 0xFF and b1 == 0xFF then
		return false, "ROM appears unprogrammed"
	end
	return true
end

function BIOS:_testRAM()
	local errors = 0
	local patterns = { 0xAA, 0x55, 0xFF, 0x00 }
	for _, pat in ipairs(patterns) do
		for i = 0, 255 do
			self.ram:memWrite(i, pat)
		end
		for i = 0, 255 do
			if self.ram:memRead(i) ~= pat then
				errors = errors + 1
			end
		end
	end
	self.ram:clear(0, 256)
	if errors > 0 then
		return false, errors .. " parity errors"
	end

	local mbytes = math.floor(self.config.RAM_SIZE / 1048576)
	self.gpu:println(string.format("        RAM: %d MB detected", mbytes), 0x07)
	return true
end

function BIOS:_initPIC()
	self.bus:portWrite(self.config.PORT.PIC_MASTER_CMD, 0x11)
	self.bus:portWrite(self.config.PORT.PIC_MASTER_DATA, 0x20)
	self.bus:portWrite(self.config.PORT.PIC_MASTER_DATA, 0x04)
	self.bus:portWrite(self.config.PORT.PIC_MASTER_DATA, 0x01)
	self.bus:portWrite(self.config.PORT.PIC_MASTER_DATA, 0xF8)

	self.bus:portWrite(self.config.PORT.PIC_SLAVE_CMD, 0x11)
	self.bus:portWrite(self.config.PORT.PIC_SLAVE_DATA, 0x28)
	self.bus:portWrite(self.config.PORT.PIC_SLAVE_DATA, 0x02)
	self.bus:portWrite(self.config.PORT.PIC_SLAVE_DATA, 0x01)
	self.bus:portWrite(self.config.PORT.PIC_SLAVE_DATA, 0xFF)
	return true
end

function BIOS:_initPIT()
	self.bus:portWrite(self.config.PORT.PIT_CMD, 0x36)
	self.bus:portWrite(self.config.PORT.PIT_CHAN0, 0x00)
	self.bus:portWrite(self.config.PORT.PIT_CHAN0, 0x00)
	return true
end

function BIOS:_initVGA()
	self.bus:portWrite(self.config.PORT.VGA_MISC_WRITE, 0x67)
	self.gpu:setMode("TEXT")
	return true
end

function BIOS:_enumPCI()
	local found = 0
	for _, dev in ipairs(self.config.PCI) do
		self:_log(
			string.format(
				"PCI %02X:%02X.%d  %04X:%04X  %s",
				dev.bus,
				dev.dev,
				dev.fn,
				dev.vendor,
				dev.device,
				dev.class
			)
		)
		found = found + 1
	end
	self.gpu:println(string.format("        PCI: %d devices found", found), 0x07)
	return true
end

function BIOS:_readCMOS()
	self.bus:portWrite(self.config.PORT.RTC_INDEX, 0x00)
	local ts = os.time and os.time() or 0
	self._rtcTime = ts
	return true
end

function BIOS:_detectHDD()
	if not self.hdd then
		return false, "No HDD device"
	end
	local total = self.hdd:getTotalSectors()
	local mb = math.floor(total * 512 / 1048576)
	self.gpu:println(string.format("        ATA0: NovaDisk %d MB  LBA%d sectors", mb, total), 0x07)
	return true
end

function BIOS:_buildMemMap()
	self._memMap = {
		{ base = 0x00000000, size = 0x0009FC00, type = "Usable", desc = "Conventional RAM" },
		{ base = 0x0009FC00, size = 0x00000400, type = "Reserved", desc = "EBDA" },
		{ base = 0x000A0000, size = 0x00060000, type = "Reserved", desc = "Video ROM/RAM" },
		{ base = 0x000F0000, size = 0x00010000, type = "Reserved", desc = "BIOS ROM" },
		{ base = 0x00100000, size = self.config.RAM_SIZE - 0x100000, type = "Usable", desc = "Extended RAM" },
		{ base = 0xFFFE0000, size = 0x00020000, type = "Reserved", desc = "BIOS Chip" },
	}
	self:_writeMemMapToRAM()
	return true
end

function BIOS:_writeMemMapToRAM()
	local addr = BootProtocol.MEMMAP_BASE
	self.bus:memWrite32(self.config.RAM_BASE + addr, #self._memMap)
	addr = addr + 4
	for _, entry in ipairs(self._memMap) do
		self.bus:memWrite32(self.config.RAM_BASE + addr, entry.base)
		self.bus:memWrite32(self.config.RAM_BASE + addr + 4, 0)
		self.bus:memWrite32(self.config.RAM_BASE + addr + 8, entry.size)
		self.bus:memWrite32(self.config.RAM_BASE + addr + 12, 0)
		local typeN = (entry.type == "Usable") and 1 or 2
		self.bus:memWrite32(self.config.RAM_BASE + addr + 16, typeN)
		addr = addr + 20
	end
end

function BIOS:_selectBootDevice()
	if not self.hdd then
		return false, "No bootable disk - FATAL"
	end
	self._bootDrive = 0x80
	self:_writeBDA()
	return true
end

function BIOS:_writeBDA()
	local bda = 0x400
	local convKb = math.floor(self.config.RAM_SIZE / 1024)
	self.ram:memWrite(bda + 0x75, self._bootDrive % 256)
	self.ram:memWrite(bda + 0x13, convKb % 256)
	self.ram:memWrite(bda + 0x14, math.floor(convKb / 256) % 256)
end

function BIOS:_loadBootSector()
	local sec = self.hdd:readSector(0)
	if sec[511] ~= 0x55 or sec[512] ~= 0xAA then
		return false, "No boot signature (0x55AA) - FATAL"
	end

	local loadOff = BootProtocol.BOOT_SECTOR_ADDR
	for i = 1, 512 do
		self.ram:memWrite(loadOff + i - 1, sec[i] or 0)
	end

	self._bootSector = sec
	self._bootSectorAddr = self.config.RAM_BASE + loadOff
	local cpu = self.machine.cpu
	if cpu then
		cpu:setReg("PC", self._bootSectorAddr)
		cpu:setReg("R1", self.config.RAM_BASE + BootProtocol.HANDOFF_BASE)
		cpu:setReg("R2", self._bootDrive)
		cpu:setReg("R3", self._bootSectorAddr)
	end
	self.gpu:println(string.format("        Boot sector loaded at 0x%08X", self._bootSectorAddr), 0x07)
	return true
end

-- POST complete -> bootloader handoff
function BIOS:_postDone()
	local g = self.gpu
	g:println("", 0x07)
	g:println("POST complete.  Handing off boot context...", 0x07)
	g:println("", 0x07)
	local handoffFlags = BootProtocol.FLAG.BOOT_SECTOR_VALID
	self._firmwareHandoffAddr = BootProtocol.writeHandoff(self.machine, {
		stage = BootProtocol.STAGE.FIRMWARE_READY,
		flags = handoffFlags,
		memMapPtr = self.config.RAM_BASE + BootProtocol.MEMMAP_BASE,
		memMapCount = #self._memMap,
		bootDrive = self._bootDrive,
		bootSectorAddr = self._bootSectorAddr,
		bootPartLba = 0,
		bootPartSize = self.hdd and self.hdd:getTotalSectors() or 0,
		cmdlinePtr = self.config.RAM_BASE + BootProtocol.CMDLINE_BASE,
	})
	task.delay(0.3, function()
		if self._onComplete then
			self._onComplete({
				handoffAddr = self._firmwareHandoffAddr,
				bootDrive = self._bootDrive,
				bootSectorAddr = self._bootSectorAddr,
			})
		end
	end)
end

function BIOS:_log(msg)
	table.insert(self._logs, msg)
end

function BIOS:getLog()
	return self._logs
end

function BIOS:getMemMap()
	return self._memMap
end

function BIOS:getRTCTime()
	return self._rtcTime
end

return BIOS
