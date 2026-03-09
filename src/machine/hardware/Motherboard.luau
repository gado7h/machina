-- Motherboard module

local Motherboard = {}
Motherboard.__index = Motherboard

function Motherboard.new(config, editableImage, luauvm)
	local self = setmetatable({}, Motherboard)
	self.config = config
	self.editableImage = editableImage
	self.luauvm = luauvm -- LuauVM module reference
	self._powered = false
	self._bootStage = "OFF" -- OFF → BIOS → BOOT → KERNEL → RUNNING
	self._heartbeat = nil
	self._uptimeStart = 0
	self._cursorTimer = 0
	return self
end

--  Power On
function Motherboard:powerOn()
	if self._powered then
		return
	end
	self._powered = true
	self._uptimeStart = os.clock()
	self._bootStage = "BIOS"

	local Bus_M = require(script.Parent.Bus)
	local CPU_M = require(script.Parent.CPU)
	local RAM_M = require(script.Parent.RAM)
	local ROM_M = require(script.Parent.ROM)
	local GPU_M = require(script.Parent.GPU)
	local HDD_M = require(script.Parent.HDD)
	local KBD_M = require(script.Parent.Keyboard)

	self.bus = Bus_M.new(self.config)
	self.ram = RAM_M.new(self.config)
	self.rom = ROM_M.new(self.config)
	self.gpu = GPU_M.new(self.config, self.editableImage)
	self.hdd = HDD_M.new(self.config)
	self.cpu = CPU_M.new(self.bus, self.config)
	self.keyboard = KBD_M.new(self.config, self.bus)

	if self._inputService then
		self.keyboard:bindRobloxInput(self._inputService)
	end

	-- Simulated NIC state
	self.nic = { link = "DOWN", ip = "unassigned", mac = "00:1A:2B:3C:4D:5E" }

	self.bus:registerDevice("cpu", self.cpu)
	self.bus:registerDevice("ram", self.ram)
	self.bus:registerDevice("rom", self.rom)
	self.bus:registerDevice("gpu", self.gpu)
	self.bus:registerDevice("hdd", self.hdd)
	self.bus:registerDevice("keyboard", self.keyboard)

	self.bus:mapMemory(self.config.ROM_BASE, self.config.ROM_SIZE, self.rom, "ROM")
	self.bus:mapMemory(self.config.RAM_BASE, self.config.RAM_SIZE, self.ram, "RAM")
	self.bus:mapMemory(self.config.VRAM_BASE, self.config.VRAM_SIZE, self.gpu, "VRAM")
	self.bus:mapMemory(self.config.MMIO_BASE, 0x1000, self.hdd, "HDD-MMIO")

	-- Real firmware logic is in BIOS.lua; ROM just needs a non-0xFF first byte.
	local romStub = {}
	local header = "NOVAFIRMWARE2.1"
	for i = 1, #header do
		romStub[i] = string.byte(header, i)
	end
	for i = #header + 1, self.config.ROM_SIZE do
		romStub[i] = 0xFF
	end
	self.rom:flash(romStub)

	-- The keyboard module auto-connects to UserInputService from Roblox
	-- caller must pass UIS: Motherboard:bindInput(UIS)

	self:_startHeartbeat()

	local BIOS_M = require(script.Parent.Parent.firmware.BIOS)
	self.bios = BIOS_M.new(self)
	self.bios:run(function(memMap)
		self:_onBIOSComplete(memMap)
	end)
end

--  Heartbeat
function Motherboard:_startHeartbeat()
	local function tick()
		if not self._powered then
			return
		end
		local dt = 1 / self.config.CPU_CLOCK_HZ

		-- Process bus DMA
		self.bus:processDMA()

		-- CPU ticks (only during RUNNING stage)
		if self._bootStage == "RUNNING" and self.kernel then
			-- Run several CPU instruction cycles per heartbeat
			local cpuCycles = 4
			for _ = 1, cpuCycles do
				local op = self.cpu:step()
				if op == "HLT" then
					break
				end
			end
			-- Kernel tick
			self.kernel:tick(dt)
		end

		-- Cursor blink
		self._cursorTimer = self._cursorTimer + dt
		if self._cursorTimer >= 0.5 then
			self._cursorTimer = 0
			if self.gpu then
				self.gpu:toggleCursor()
			end
		end

		-- GPU flush
		if self.gpu then
			self.gpu:flush()
		end

		-- Reschedule
		task.delay(dt, tick)
	end

	task.delay(1 / self.config.CPU_CLOCK_HZ, tick)
end

--  Boot chain callbacks
function Motherboard:_onBIOSComplete(memMap)
	self._bootStage = "BOOT"
	local BL_M = require(script.Parent.Parent.bootloader.Bootloader)
	self.bootloader = BL_M.new(self)
	self.bootloader:run(memMap, function(fs, loadAddr, kdata)
		self:_onKernelLoaded(fs, loadAddr, kdata)
	end)
end

function Motherboard:_onKernelLoaded(fs, loadAddr, kdata)
	self._bootStage = "KERNEL"

	-- Set CPU program counter to kernel load address
	self.cpu:setReg("PC", loadAddr)

	-- Instantiate kernel
	local K_M = require(script.Parent.Parent.kernel.Kernel)
	self.kernel = K_M.new(self)

	-- Run kernel main first so kernel.vfs is set
	self.kernel:kmain(fs, loadAddr, kdata)

	-- Attach package manager after VFS is ready
	local PKG_M = require(script.Parent.Parent.pkgmgr.PackageManager)
	self.kernel.pkgmgr = PKG_M.new(self.kernel)

	self._bootStage = "RUNNING"
end

--  Input binding
function Motherboard:bindInput(UIS)
	self._inputService = UIS
	if self.keyboard then
		self.keyboard:bindRobloxInput(UIS)
	end
end

--  Reboot
function Motherboard:reboot()
	if self.keyboard then
		self.keyboard:unbind()
	end

	self._powered = false
	self._bootStage = "OFF"

	if self.ram then
		self.ram._mem = {}
	end

	if self.gpu then
		self.gpu:clearScreen()
	end

	task.delay(0.5, function()
		self:powerOn()
	end)
end

--  Desktop activation (called by pkgmgr postinst)
function Motherboard:activateDesktop()
	if not self.kernel then
		return false, "kernel not running"
	end

	local source = self.kernel.vfs:readFileStr("/usr/lib/novade/init.lua")
	if not source then
		return false, "desktop not installed"
	end

	local vm = self.luauvm
	if not vm then
		return false, "LuauVM not available"
	end

	local sandbox = {
		kernel = self.kernel,

		string = string,
		math = math,
		table = table,
		pairs = pairs,
		ipairs = ipairs,
		next = next,

		tostring = tostring,
		tonumber = tonumber,
		type = type,

		os = os,

		setmetatable = setmetatable,
		getmetatable = getmetatable,

		error = error,
		pcall = pcall,
		xpcall = xpcall,
	}

	local ok, DE = pcall(function()
		local chunk = vm(source, false, sandbox)
		return chunk()
	end)

	if not ok then
		return false, tostring(DE)
	end

	if type(DE) ~= "table" or type(DE.new) ~= "function" then
		return false, "desktop module invalid"
	end

	local de = DE.new(self.kernel)
	if not de or type(de.start) ~= "function" then
		return false, "desktop instance invalid"
	end

	local started, err = de:start()
	if started == false then
		return false, tostring(err)
	end

	self.kernel._desktop = de
	return true
end

--  Stats
function Motherboard:getStats()
	return {
		powered = self._powered,
		bootStage = self._bootStage,
		uptime = os.clock() - self._uptimeStart,
		cpuStats = self.cpu and self.cpu:getStats() or {},
		ramStats = self.ram and self.ram:getStats() or {},
		hddStats = self.hdd and self.hdd:getStats() or {},
		gpuStats = self.gpu and self.gpu:getStats() or {},
		busStats = self.bus and self.bus:getStats() or {},
	}
end

function Motherboard:isPowered()
	return self._powered
end
function Motherboard:getBootStage()
	return self._bootStage
end

return Motherboard
