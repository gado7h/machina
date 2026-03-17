-- Bootloader module

local BootProtocol = require(script.Parent.BootProtocol)

local Bootloader = {}
Bootloader.__index = Bootloader

function Bootloader.new(machine)
	local self = setmetatable({}, Bootloader)
	self.machine = machine
	self.gpu = machine.gpu
	self.ram = machine.ram
	self.hdd = machine.hdd
	self.bus = machine.bus
	self.config = machine.config
	self.vfs = nil
	self._log = {}
	self._memMapCount = 0
	self._bootDrive = 0x80
	self._bootSector = nil
	self._bootSectorAddr = 0
	self._handoffAddr = self.config.RAM_BASE + BootProtocol.HANDOFF_BASE
	self._handoff = nil
	return self
end

-- Entry point
function Bootloader:run(firmwareState, onKernelLoaded)
	self._onKernelLoaded = onKernelLoaded
	self:_adoptFirmwareState(firmwareState)
	self._handoffAddr = BootProtocol.writeHandoff(self.machine, {
		stage = BootProtocol.STAGE.BOOTLOADER_READY,
		bootDrive = self._bootDrive,
		bootSectorAddr = self._bootSectorAddr,
		memMapPtr = self.config.RAM_BASE + BootProtocol.MEMMAP_BASE,
		memMapCount = self._memMapCount,
	})

	self.gpu:println("NovaLoader Stage1 - scanning partition table...", 0x07)
	self.gpu:println(string.format("  Boot drive: 0x%02X", self._bootDrive), 0x07)

	local part, err = self:_parsePartitionTable()
	if not part then
		self.gpu:println("ERROR: " .. tostring(err or "No bootable partition found"), 0x0C)
		return
	end

	self.gpu:println(
		string.format("  Selected partition: type=0x%02X  LBA=%d  size=%d", part.type, part.lbaStart, part.lbaSize),
		0x07
	)

	task.delay(0.1, function()
		self:_stage2(part)
	end)
end

function Bootloader:_adoptFirmwareState(firmwareState)
	local handoff, _ = BootProtocol.readHandoff(self.machine)
	if handoff and handoff.stage >= BootProtocol.STAGE.FIRMWARE_READY then
		self._handoff = handoff
		self._bootDrive = handoff.bootDrive or self._bootDrive
		self._bootSectorAddr = handoff.bootSectorAddr or self._bootSectorAddr
		self._memMapCount = handoff.memMapCount or self._memMapCount
		self._handoffAddr = handoff.addr or self._handoffAddr
	end

	local cpuRegs = BootProtocol.readCpuRegs(self.machine)
	if cpuRegs then
		if cpuRegs.r2 ~= 0 then
			self._bootDrive = cpuRegs.r2
		end
		if self._bootSectorAddr == 0 and cpuRegs.r3 ~= 0 then
			self._bootSectorAddr = cpuRegs.r3
		end
	end

	if type(firmwareState) == "table" then
		self._handoffAddr = firmwareState.handoffAddr or self._handoffAddr
		if self._bootSectorAddr == 0 then
			self._bootSectorAddr = firmwareState.bootSectorAddr or self._bootSectorAddr
		end
		if self._memMapCount == 0 and type(firmwareState.memMap) == "table" then
			self._memMapCount = #firmwareState.memMap
		end
		if self._bootSector == nil and type(firmwareState.bootSector) == "table" then
			self._bootSector = firmwareState.bootSector
		end
	end

	if self._bootSectorAddr == 0 then
		self._bootSectorAddr = self.config.RAM_BASE + BootProtocol.BOOT_SECTOR_ADDR
	end
	self._bootSector = self:_readBootSectorFromRam(self._bootSectorAddr) or self._bootSector
end

-- Stage 1: parse MBR partition table
function Bootloader:_parsePartitionTable()
	local mbr = self._bootSector or self.hdd:readSector(0)
	if mbr[511] ~= 0x55 or mbr[512] ~= 0xAA then
		return nil, "Invalid MBR signature"
	end

	local entries = {}
	for idx = 0, 3 do
		local pe = 447 + idx * 16
		local status = mbr[pe + 0] or 0
		local ptype = mbr[pe + 4] or 0
		local lbaStart = (mbr[pe + 8] or 0)
			+ (mbr[pe + 9] or 0) * 256
			+ (mbr[pe + 10] or 0) * 65536
			+ (mbr[pe + 11] or 0) * 16777216
		local lbaSize = (mbr[pe + 12] or 0)
			+ (mbr[pe + 13] or 0) * 256
			+ (mbr[pe + 14] or 0) * 65536
			+ (mbr[pe + 15] or 0) * 16777216

		if ptype ~= 0 and lbaStart > 0 and lbaSize > 0 then
			table.insert(entries, {
				index = idx,
				status = status,
				type = ptype,
				lbaStart = lbaStart,
				lbaSize = lbaSize,
				bootable = status == 0x80,
			})
		end
	end

	if #entries == 0 then
		return nil, "No valid partition entries"
	end

	local selected = nil
	for _, e in ipairs(entries) do
		if e.bootable then
			selected = e
			break
		end
	end
	if not selected then
		selected = entries[1]
	end

	return selected
end

-- Stage 2: mount FS, find kernel, load it
function Bootloader:_stage2(partition)
	self.gpu:println("NovaLoader Stage2 - mounting NovaFS...", 0x07)

	local NovaFS = require(script.Parent.Parent.kernel.VFS)
	local fs = NovaFS.new(self.hdd, partition.lbaStart, self.config)

	local ok, err = fs:mount()
	if not ok then
		self.gpu:println("ERROR mounting filesystem: " .. tostring(err), 0x0C)
		self.gpu:println("  Attempting fresh install...", 0x0E)
		fs:format()
		fs:mount()
		self:_installBaseSystem(fs)
	else
		self.gpu:println(
			"  NovaFS mounted " .. string.format("(magic=%s, inodes=%d)", fs:getMagic(), fs:getInodeCount()),
			0x07
		)
	end

	self.vfs = fs

	self.gpu:println("  Searching /boot/kernel.bin ...", 0x07)
	local kdata, kerr = fs:readFile("/boot/kernel.bin")
	if not kdata then
		self.gpu:println("ERROR: kernel not found: " .. tostring(kerr), 0x0C)
		self.gpu:println("  Loading emergency mini-kernel...", 0x0E)
		kdata = self:_emergencyKernelBlob()
	end

	local loadAddr = self.config.KERNEL_LOAD_ADDR
	self.gpu:println(string.format("  Loading kernel: %d bytes -> 0x%08X", #kdata, loadAddr), 0x07)
	self:_loadKernelToRam(loadAddr, kdata)

	local existingFlags = (self._handoff and self._handoff.flags) or 0
	local flags = bit32.bor(existingFlags, BootProtocol.FLAG.BOOTINFO_VALID, BootProtocol.FLAG.KERNEL_LOADED)

	local bootInfoAddr = BootProtocol.writeBootInfo(self.machine, {
		kernelEntry = loadAddr,
		kernelSize = #kdata,
		memMapCount = self._memMapCount,
		bootDrive = self._bootDrive,
		flags = flags,
		cmdline = "nova ro quiet",
		partition = partition,
		bootSectorAddr = self._bootSectorAddr,
	})

	self._handoffAddr = BootProtocol.writeHandoff(self.machine, {
		stage = BootProtocol.STAGE.KERNEL_READY,
		flags = flags,
		bootInfoAddr = bootInfoAddr,
		kernelEntry = loadAddr,
		kernelSize = #kdata,
		memMapPtr = self.config.RAM_BASE + BootProtocol.MEMMAP_BASE,
		memMapCount = self._memMapCount,
		bootDrive = self._bootDrive,
		bootSectorAddr = self._bootSectorAddr,
		bootPartLba = partition.lbaStart,
		bootPartSize = partition.lbaSize,
		cmdlinePtr = self.config.RAM_BASE + BootProtocol.CMDLINE_BASE,
	})
	self._handoff, _ = BootProtocol.readHandoff(self.machine)
	local seeded, seedErr = BootProtocol.seedCpuForKernel(self.machine, self._handoff)
	if not seeded then
		self.gpu:println("ERROR seeding CPU handoff: " .. tostring(seedErr), 0x0C)
		return
	end

	self.gpu:println("  Kernel loaded.  Transferring control...", 0x0A)
	self.gpu:println("", 0x07)

	task.delay(0.2, function()
		if self._onKernelLoaded then
			self._onKernelLoaded({
				fs = fs,
			})
		end
	end)
end

function Bootloader:_readBootSectorFromRam(addr)
	if type(addr) ~= "number" or addr == 0 then
		return nil
	end
	local off = addr - self.config.RAM_BASE
	if off < 0 then
		return nil
	end

	local sec = {}
	for i = 1, 512 do
		sec[i] = self.ram:memRead(off + i - 1) or 0
	end
	if sec[511] ~= 0x55 or sec[512] ~= 0xAA then
		return nil
	end
	return sec
end

function Bootloader:_loadKernelToRam(loadAddr, kdata)
	local ramBase = self.config.RAM_BASE
	for i, byte in ipairs(kdata) do
		self.ram:memWrite(loadAddr - ramBase + i - 1, byte)
	end
end

-- Fresh filesystem install (first boot)
function Bootloader:_installBaseSystem(fs)
	self.gpu:println("  Installing base filesystem...", 0x0E)

	local dirs = {
		"/",
		"/bin",
		"/usr",
		"/usr/bin",
		"/usr/lib",
		"/etc",
		"/home",
		"/home/user",
		"/var",
		"/var/log",
		"/tmp",
		"/boot",
		"/dev",
		"/proc",
		"/sys",
		"/pkg",
		"/pkg/db",
		"/pkg/cache",
		"/pkg/installed",
	}
	for _, d in ipairs(dirs) do
		fs:mkdir(d)
	end

	fs:writeFile("/etc/hostname", self:_strBytes("novamachine\n"))

	fs:writeFile(
		"/etc/os-release",
		self:_strBytes(table.concat({
			'NAME="NovaOS"',
			'VERSION="1.0.0"',
			"ID=novaos",
			"ID_LIKE=linux",
			'PRETTY_NAME="NovaOS 1.0.0 (Nova)"',
			'VERSION_ID="1.0"',
			'HOME_URL="https://novamachine.local"',
			'KERNEL="nova-1.0.0"',
			"",
		}, "\n"))
	)

	fs:writeFile(
		"/etc/fstab",
		self:_strBytes(
			"# <device>  <mountpoint>  <type>  <options>  <dump>  <pass>\n"
				.. "/dev/hda1   /             novafs  defaults   0       1\n"
				.. "tmpfs       /tmp          tmpfs   defaults   0       0\n"
		)
	)

	fs:writeFile(
		"/etc/passwd",
		self:_strBytes("root:x:0:0:root:/root:/bin/sh\n" .. "user:x:1000:1000:User:/home/user:/bin/sh\n")
	)

	fs:writeFile(
		"/etc/motd",
		self:_strBytes(
			"\n"
				.. "  Welcome to NovaOS 1.0.0\n"
				.. "  NovaKernel nova-1.0.0  NovaMachine Educational Platform\n"
				.. "\n"
				.. "  Type 'help' for available commands.\n"
				.. "\n"
		)
	)

	local stub = { 0x4E, 0x4B, 0x52, 0x4E } -- "NKRN"
	fs:writeFile("/boot/kernel.bin", stub)
	fs:writeFile("/var/log/boot.log", self:_strBytes("-- boot log --\n"))

	fs:writeFile(
		"/home/user/readme.txt",
		self:_strBytes(
			"Welcome to your NovaMachine home directory!\n" .. "NovaOS is a virtual Unix-like operating system.\n"
		)
	)

	self.gpu:println("  Base system installed.", 0x0A)
end

function Bootloader:_strBytes(s)
	local b = {}
	for i = 1, #s do
		b[i] = string.byte(s, i)
	end
	return b
end

function Bootloader:_emergencyKernelBlob()
	return { 0x4E, 0x4B, 0x52, 0x4E, 0x00 }
end

function Bootloader:getLog()
	return self._log
end

return Bootloader
