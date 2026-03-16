-- Bootloader module

local Bootloader = {}
Bootloader.__index = Bootloader

-- BootInfo offsets in RAM (at 0x600)
local BOOTINFO_BASE = 0x600
local BI_MAGIC = 0 -- 4B: 0x4E4F5641 "NOVA"
local BI_KERNEL_ENTRY = 4 -- 4B: virtual entry point
local BI_KERNEL_SIZE = 8 -- 4B: bytes
local BI_MEM_MAP_PTR = 12 -- 4B: pointer to E820 table in RAM
local BI_MEM_MAP_COUNT = 16 -- 4B: number of E820 entries
local BI_BOOT_DRIVE = 20 -- 1B: drive index
local BI_CMDLINE_PTR = 24 -- 4B: pointer to null-terminated command line

local BOOTINFO_MAGIC = 0x4E4F5641 -- "NOVA"

function Bootloader.new(machine)
	local self = setmetatable({}, Bootloader)
	self.machine = machine
	self.gpu = machine.gpu
	self.ram = machine.ram
	self.hdd = machine.hdd
	self.bus = machine.bus
	self.config = machine.config
	self.vfs = nil -- set once filesystem is mounted
	self._log = {}
	return self
end

--  Entry point

function Bootloader:run(memMap, onKernelLoaded)
	self._onKernelLoaded = onKernelLoaded
	self._memMap = memMap

	self.gpu:println("NovaLoader Stage1 — checking MBR partition table...", 0x07)

	-- Parse partition table from MBR
	local part = self:_parsePartitionTable()
	if not part then
		self.gpu:println("ERROR: No bootable partition found!", 0x0C)
		return
	end

	self.gpu:println(
		string.format("  Partition 0: type=0x%02X  LBA=%d  size=%d sectors", part.type, part.lbaStart, part.lbaSize),
		0x07
	)

	task.delay(0.1, function()
		self:_stage2(part)
	end)
end

--  Stage 1: Parse MBR partition table

function Bootloader:_parsePartitionTable()
	local mbr = self.hdd:readSector(0)
	-- Partition entries at bytes 446–509 (1-based: 447–510)
	local pe = 447
	-- Entry 1
	local status = mbr[pe + 0]
	local ptype = mbr[pe + 4]
	local lbaStart = mbr[pe + 8] + mbr[pe + 9] * 256 + mbr[pe + 10] * 65536 + mbr[pe + 11] * 16777216
	local lbaSize = mbr[pe + 12] + mbr[pe + 13] * 256 + mbr[pe + 14] * 65536 + mbr[pe + 15] * 16777216

	if ptype == 0 or lbaStart == 0 then
		return nil
	end

	return {
		status = status,
		type = ptype,
		lbaStart = lbaStart,
		lbaSize = lbaSize,
		bootable = (status == 0x80),
	}
end

--  Stage 2: Mount FS, find kernel, load it

function Bootloader:_stage2(partition)
	self.gpu:println("NovaLoader Stage2 — mounting NovaFS...", 0x07)

	-- Mount filesystem
	local NovaFS = require(script.Parent.Parent.kernel.VFS)
	local fs = NovaFS.new(self.hdd, partition.lbaStart, self.config)

	local ok, err = fs:mount()
	if not ok then
		self.gpu:println("ERROR mounting filesystem: " .. tostring(err), 0x0C)
		-- Attempt to format and install a minimal filesystem
		self.gpu:println("  Attempting fresh install...", 0x0E)
		fs:format()
		fs:mount()
		self:_installBaseSystem(fs)
	else
		self.gpu:println(
			"  NovaFS mounted  " .. string.format("(magic=%s, inodes=%d)", fs:getMagic(), fs:getInodeCount()),
			0x07
		)
	end

	self.vfs = fs

	-- Locate kernel binary
	self.gpu:println("  Searching /boot/kernel.bin ...", 0x07)
	local kdata, kerr = fs:readFile("/boot/kernel.bin")
	if not kdata then
		self.gpu:println("ERROR: kernel not found: " .. tostring(kerr), 0x0C)
		self.gpu:println("  Loading emergency mini-kernel...", 0x0E)
		kdata = self:_emergencyKernelBlob()
	end

	-- Load kernel into RAM
	local loadAddr = self.config.KERNEL_LOAD_ADDR
	self.gpu:println(string.format("  Loading kernel: %d bytes → 0x%08X", #kdata, loadAddr), 0x07)

	local ramBase = self.config.RAM_BASE
	for i, byte in ipairs(kdata) do
		self.ram:memWrite(loadAddr - ramBase + i - 1, byte)
	end

	-- Write BootInfo struct to RAM
	self:_writeBootInfo(loadAddr, #kdata)

	self.gpu:println("  Kernel loaded.  Transferring control...", 0x0A)
	self.gpu:println("", 0x07)

	task.delay(0.2, function()
		if self._onKernelLoaded then
			self._onKernelLoaded(fs, loadAddr, kdata)
		end
	end)
end

--  Write BootInfo struct to RAM

function Bootloader:_writeBootInfo(kernelEntry, kernelSize)
	local ramBase = self.config.RAM_BASE
	local base = BOOTINFO_BASE -- offset within RAM

	self.bus:memWrite32(ramBase + base + BI_MAGIC, BOOTINFO_MAGIC)
	self.bus:memWrite32(ramBase + base + BI_KERNEL_ENTRY, kernelEntry)
	self.bus:memWrite32(ramBase + base + BI_KERNEL_SIZE, kernelSize)
	self.bus:memWrite32(ramBase + base + BI_MEM_MAP_PTR, ramBase + 0x500)
	self.bus:memWrite32(ramBase + base + BI_MEM_MAP_COUNT, self._memMap and #self._memMap or 0)
	self.ram:memWrite(base + BI_BOOT_DRIVE, 0x80)

	-- Write default cmdline "nova ro quiet" at RAM 0x700
	local cmdline = "nova ro quiet"
	self.bus:memWrite32(ramBase + base + BI_CMDLINE_PTR, ramBase + 0x700)
	for i = 1, #cmdline do
		self.ram:memWrite(0x700 + i - 1, string.byte(cmdline, i))
	end
	self.ram:memWrite(0x700 + #cmdline, 0) -- null terminator
end

--  Fresh filesystem install (first boot)

function Bootloader:_installBaseSystem(fs)
	self.gpu:println("  Installing base filesystem...", 0x0E)

	-- Create directory tree
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

	-- /etc/hostname
	fs:writeFile("/etc/hostname", self:_strBytes("novamachine\n"))

	-- /etc/os-release
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

	-- /etc/fstab
	fs:writeFile(
		"/etc/fstab",
		self:_strBytes(
			"# <device>  <mountpoint>  <type>  <options>  <dump>  <pass>\n"
				.. "/dev/hda1   /             novafs  defaults   0       1\n"
				.. "tmpfs       /tmp          tmpfs   defaults   0       0\n"
		)
	)

	-- /etc/passwd (minimal)
	fs:writeFile(
		"/etc/passwd",
		self:_strBytes("root:x:0:0:root:/root:/bin/sh\n" .. "user:x:1000:1000:User:/home/user:/bin/sh\n")
	)

	-- /etc/motd
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

	-- /boot/kernel.bin — placeholder (real kernel is the Lua Kernel module)
	local stub = { 0x4E, 0x4B, 0x52, 0x4E } -- "NKRN" magic
	fs:writeFile("/boot/kernel.bin", stub)

	-- /var/log/boot.log
	fs:writeFile("/var/log/boot.log", self:_strBytes("-- boot log --\n"))

	-- /home/user/readme.txt
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
	-- Minimal "kernel": just the magic bytes; kernel module handles the rest
	return { 0x4E, 0x4B, 0x52, 0x4E, 0x00 }
end

function Bootloader:getLog()
	return self._log
end

return Bootloader
