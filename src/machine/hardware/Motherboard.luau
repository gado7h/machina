-- Motherboard module

local Motherboard = {}
Motherboard.__index = Motherboard

function Motherboard.new(config, editableImage, luauvm)
	local self = setmetatable({}, Motherboard)
	self.config = config
	self.editableImage = editableImage
	self.luauvm = luauvm -- LuauVM module reference
	self.runtime = nil
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
	self._bootStage = "OFF"

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

	local Runtime_M = require(script.Parent.Parent.software.RuntimeController)
	self.runtime = Runtime_M.new(self, self.luauvm)
	self.runtime:startBoot()
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
	self.runtime = nil
	self.kernel = nil

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


function Motherboard:_setBootStage(stage)
	self._bootStage = stage
end

--  Stats
function Motherboard:getStats()
	local cpuStats = self.cpu and self.cpu:getStats() or {}
	local ramStats = self.ram and self.ram:getStats() or {}
	local hddStats = self.hdd and self.hdd:getStats() or {}
	local gpuStats = self.gpu and self.gpu:getStats() or {}
	local busStats = self.bus and self.bus:getStats() or {}

	return {
		powered = self._powered,
		bootStage = self._bootStage,
		uptime = os.clock() - self._uptimeStart,
		-- Backward-compatible flat stats
		cpuStats = cpuStats,
		ramStats = ramStats,
		hddStats = hddStats,
		gpuStats = gpuStats,
		busStats = busStats,
		-- Explicit hardware vs software breakdown
		hardware = {
			cpu = cpuStats,
			ram = ramStats,
			hdd = hddStats,
			gpu = gpuStats,
			bus = busStats,
		},
		software = {
			bootStage = self._bootStage,
			kernelRunning = self.kernel ~= nil,
			runtimeInitialized = self.runtime ~= nil,
		},
	}
end

function Motherboard:isPowered()
	return self._powered
end
function Motherboard:getBootStage()
	return self._bootStage
end

return Motherboard
