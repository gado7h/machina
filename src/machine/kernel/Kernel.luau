-- Kernel module

local Kernel = {}
Kernel.__index = Kernel

function Kernel.new(machine)
	local self = setmetatable({}, Kernel)
	self.machine = machine
	self.config = machine.config
	self.bus = machine.bus
	self.gpu = machine.gpu
	self.ram = machine.ram
	self.hdd = machine.hdd
	self.keyboard = machine.keyboard
	self._running = false
	self._log = {}
	self._uptime = 0 -- seconds
	return self
end

--  kmain — kernel entry point

function Kernel:kmain(fs, kernelLoadAddr, kernelData)
	local g = self.gpu
	g:println("", 0x07)
	g:println(string.format("[    0.000] NovaKernel %s — %s", self.config.KERNEL_VERSION, self.config.ARCH), 0x0A)
	g:println(string.format("[    0.000] Command line: nova ro quiet"), 0x07)
	g:println("", 0x07)

	self:_klog("0.000", "NovaKernel starting")

	self:_klog("0.001", "initializing memory manager")
	local MM = require(script.Parent.MemoryManager)
	self.mm = MM.new(self.config, self.ram)
	local mi = self.mm:getMemInfo()
	g:println(
		string.format(
			"[    0.001] Memory: %dMB total, %dMB free",
			math.floor(mi.total / 1048576),
			math.floor(mi.free / 1048576)
		),
		0x07
	)

	self:_klog("0.002", "initializing process manager")
	local PMod = require(script.Parent.ProcessManager)
	self.pm = PMod.new(self.config, self.mm)
	self.pm:spawnIdle()
	g:println("[    0.002] Process manager: OK  (max PIDs: 65535)", 0x07)

	self:_klog("0.003", "mounting root filesystem")
	self.vfs = fs
	g:println("[    0.003] NovaFS mounted on /", 0x07)

	self:_klog("0.004", "registering syscall table")
	local SC = require(script.Parent.Syscall)
	self.syscall = SC.new(self)
	g:println("[    0.004] Syscall table: 64 entries registered", 0x07)

	self:_klog("0.005", "initializing device manager")
	self:_initDeviceManager()
	g:println("[    0.005] devtmpfs mounted on /dev", 0x07)

	self:_klog("0.006", "registering IRQ handlers")
	self:_registerIRQs()

	self:_initProcFS()
	g:println("[    0.007] procfs mounted on /proc", 0x07)
	g:println("[    0.008] sysfs mounted on /sys", 0x07)

	self.vfs:mkdir("/tmp")

	self:_klog("0.010", "kernel init complete")
	g:println("", 0x07)
	g:println("[    0.010] Kernel init complete.  Starting init...", 0x0A)
	g:println("", 0x07)

	self._running = true

	task.delay(0.3, function()
		self:_spawnInit()
	end)
end

--  Device Manager

function Kernel:_initDeviceManager()
	-- Create /dev entries
	local devs = {
		"null",
		"zero",
		"random",
		"urandom",
		"tty",
		"tty0",
		"tty1",
		"hda",
		"hda1",
		"mem",
		"kmem",
		"stdin",
		"stdout",
		"stderr",
		"fb0", -- framebuffer
		"kbd", -- keyboard
		"rtc0", -- real-time clock
	}
	self.vfs:mkdir("/dev")
	for _, name in ipairs(devs) do
		-- Write a small device descriptor file
		local desc = string.format("device:%s\n", name)
		local bytes = {}
		for i = 1, #desc do
			bytes[i] = string.byte(desc, i)
		end
		self.vfs:writeFile("/dev/" .. name, bytes)
	end

	-- /dev/null reads return 0 bytes; writes discard
	-- /dev/zero reads return 0x00 bytes
	-- These are handled specially in Syscall:_sysRead
end

--  IRQ registration

function Kernel:_registerIRQs()
	-- IRQ 0: Timer
	self.bus:registerIRQ(self.config.IRQ.TIMER, "kernel", function(irq, data)
		self._uptime = self._uptime + (1 / 18.2)
	end)

	-- IRQ 1: Keyboard (handled by Keyboard hardware)
	-- IRQ 14: ATA disk
	self.bus:registerIRQ(self.config.IRQ.ATA, "kernel", function(irq, data)
		-- Disk interrupt: wake any sleeping process waiting on disk I/O
	end)
end

--  /proc pseudo-filesystem

function Kernel:_initProcFS()
	self.vfs:mkdir("/proc")
	self.vfs:mkdir("/sys")
	self.vfs:mkdir("/sys/class")
	self.vfs:mkdir("/sys/block")
	self.vfs:mkdir("/proc/net")

	-- Static /proc files
	self:_updateProcFS()
end

function Kernel:_updateProcFS()
	if not self.vfs or not self.vfs:isMounted() then
		return
	end

	-- /proc/version
	self.vfs:writeFileStr(
		"/proc/version",
		string.format(
			"%s version %s (nova@novamachine) (gcc %s) #1 SMP\n",
			self.config.OS_NAME,
			self.config.KERNEL_VERSION,
			"11.3.0"
		)
	)

	-- /proc/uptime
	self.vfs:writeFileStr("/proc/uptime", string.format("%.2f %.2f\n", self._uptime, self._uptime * 0.9))

	-- /proc/cpuinfo
	self.vfs:writeFileStr(
		"/proc/cpuinfo",
		table.concat({
			"processor	: 0",
			"vendor_id	: NovaCPU",
			"model name	: " .. tostring(self.config.CPU_MODEL or "NovaCPU-X1") .. " @ 3200.000 MHz",
			"architecture	: " .. tostring(self.config.CPU_ARCH or "nova32"),
			"cache size	: 8192 KB",
			"cpu cores	: " .. tostring(self.config.CPU_CORES or 1),
			"siblings	: " .. tostring(self.config.CPU_THREADS or self.config.CPU_CORES or 1),
			"flags		: fpu pse pse36 mtrr pge mca cmov pat clflush mmx sse sse2 syscall",
			"bogomips	: 6400.00",
			"",
		}, "\n")
	)

	-- /proc/meminfo
	local mi = self.mm and self.mm:getMemInfo() or {}
	self.vfs:writeFileStr(
		"/proc/meminfo",
		table.concat({
			string.format("MemTotal:   %8d kB", math.floor((mi.total or 0) / 1024)),
			string.format("MemFree:    %8d kB", math.floor((mi.free or 0) / 1024)),
			string.format("MemUsed:    %8d kB", math.floor((mi.used or 0) / 1024)),
			string.format("Buffers:    %8d kB", 0),
			string.format("Cached:     %8d kB", 0),
			string.format("PageSize:   %8d kB", math.floor((mi.pageSize or 4096) / 1024)),
			"",
		}, "\n")
	)

	-- /proc/mounts
	self.vfs:writeFileStr(
		"/proc/mounts",
		"/dev/hda1 / novafs rw,relatime 0 0\n"
			.. "tmpfs /tmp tmpfs rw 0 0\n"
			.. "proc /proc proc rw 0 0\n"
			.. "sysfs /sys sysfs rw 0 0\n"
	)

	-- /proc/filesystems
	self.vfs:writeFileStr("/proc/filesystems", "nodev\tproc\nnodev\tsysfs\nnodev\ttmpfs\n\tnovafs\n")
end

--  init process (PID 1)

function Kernel:_spawnInit()
	local InitMod = require(script.Parent.Parent.userland.Init)
	self.initModule = InitMod.new(self)
	self.initModule:run()
end

--  Timer tick (called by Motherboard heartbeat)

function Kernel:tick(dt)
	if not self._running then
		return
	end

	-- Raise timer IRQ
	self.bus:raiseIRQ(self.config.IRQ.TIMER, nil)

	-- Scheduler tick
	if self.pm then
		self.pm:tick(dt)
	end

	-- Update /proc periodically
	self._tickCounter = (self._tickCounter or 0) + 1
	if self._tickCounter % 20 == 0 then
		self:_updateProcFS()
	end

	-- Flush GPU
	if self.gpu then
		self.gpu:flush()
	end
end

--  Kernel panic

function Kernel:panic(msg)
	self._running = false
	if self.gpu then
		self.gpu:clearScreen(0x4F) -- red background
		self.gpu:println("", 0x4F)
		self.gpu:println("  *** KERNEL PANIC — NOT SYNCING ***", 0x4F)
		self.gpu:println("", 0x4F)
		self.gpu:println("  " .. tostring(msg), 0x4F)
		self.gpu:println("", 0x4F)
		self.gpu:println("  CPU: 0  PID: " .. tostring(self.pm and self.pm._currentPid or "?"), 0x4F)
		self.gpu:println("  Kernel: nova-" .. self.config.KERNEL_VERSION, 0x4F)
		self.gpu:println("", 0x4F)
		self.gpu:println("  System halted.", 0x4F)
		self.gpu:flush()
	end
	error("KERNEL PANIC: " .. tostring(msg))
end

--  Reboot

function Kernel:reboot()
	self._running = false
	if self.gpu then
		self.gpu:clearScreen(0x07)
		self.gpu:println("System is rebooting...", 0x0E)
		self.gpu:println("", 0x07)
		self.gpu:flush()
	end
	task.delay(1.0, function()
		self.machine:reboot()
	end)
end

--  Logging

function Kernel:_klog(time, msg)
	local entry = string.format("[%9s] %s", time, msg)
	table.insert(self._log, entry)
	if #self._log > 1000 then
		table.remove(self._log, 1)
	end
end

function Kernel:log(msg)
	local t = string.format("%.3f", self._uptime)
	self:_klog(t, msg)
end

function Kernel:getLog()
	return self._log
end
function Kernel:getUptime()
	return self._uptime
end
function Kernel:isRunning()
	return self._running
end

-- Shortcut for processes to call syscalls
function Kernel:syscall(pid, num, ...)
	if not self.syscall then
		return -38
	end
	return self.syscall:call(pid, num, ...)
end

return Kernel
