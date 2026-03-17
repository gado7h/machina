-- Motherboard module

local Motherboard = {}
Motherboard.__index = Motherboard

function Motherboard.new(config, editableImage, luauvm)
	local self = setmetatable({}, Motherboard)
	self.config = config
	self.editableImage = editableImage
	self.luauvm = luauvm
	self.runtime = nil
	self._powered = false
	self._bootStage = "OFF"
	self._heartbeat = nil
	self._heartbeatGeneration = 0
	self._uptimeStart = 0
	self._cursorTimer = 0
	self._bootRecord = nil
	return self
end

-- Power On
function Motherboard:powerOn()
	if self._powered then
		return
	end
	self._powered = true
	self._uptimeStart = os.clock()
	self._bootStage = "OFF"
	self._bootRecord = {
		startedAt = self._uptimeStart,
		stages = {},
	}

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

	self.nic = { link = "DOWN", ip = "unassigned", mac = "00:1A:2B:3C:4D:5E" }

	self.bus:registerDevice("cpu", self.cpu)
	self.bus:registerDevice("ram", self.ram)
	self.bus:registerDevice("rom", self.rom)
	self.bus:registerDevice("gpu", self.gpu)
	self.bus:registerDevice("hdd", self.hdd)
	self.bus:registerDevice("keyboard", self.keyboard)

	self.bus:mapMemory(self.config.ROM_BASE, self.config.ROM_SIZE, self.rom, "ROM", { readOnly = true })
	self.bus:mapMemory(self.config.RAM_BASE, self.config.RAM_SIZE, self.ram, "RAM")
	self.bus:mapMemory(self.config.VRAM_BASE, self.config.VRAM_SIZE, self.gpu, "VRAM")

	local mmio = self.config.MMIO or {}
	self.bus:mapMemory(mmio.HDD_BASE or self.config.MMIO_BASE, mmio.HDD_SIZE or 0x1000, self.hdd, "HDD-MMIO")
	if self.bus.timer then
		self.bus:mapMemory(
			mmio.TIMER_BASE or (self.config.MMIO_BASE + 0x0800),
			mmio.TIMER_SIZE or 0x40,
			self.bus.timer,
			"TIMER-MMIO"
		)
	end
	if self.bus.pic then
		self.bus:mapMemory(
			mmio.PIC_BASE or (self.config.MMIO_BASE + 0x0840),
			mmio.PIC_SIZE or 0x40,
			self.bus.pic,
			"PIC-MMIO"
		)
	end

	local romStub = {}
	local header = "NOVAFIRMWARE2.2"
	for i = 1, #header do
		romStub[i] = string.byte(header, i)
	end
	for i = #header + 1, self.config.ROM_SIZE do
		romStub[i] = 0xFF
	end
	self.rom:flash(romStub)

	self:_startHeartbeat()

	local Runtime_M = require(script.Parent.Parent.software.RuntimeController)
	self.runtime = Runtime_M.new(self, self.luauvm)
	self.runtime:startBoot()
end

-- Heartbeat
function Motherboard:_startHeartbeat()
	self._heartbeatGeneration = self._heartbeatGeneration + 1
	local generation = self._heartbeatGeneration

	local function tick()
		if not self._powered then
			return
		end
		if generation ~= self._heartbeatGeneration then
			return
		end
		local tickHz = math.max(self.config.CPU_CLOCK_HZ or 1, self.config.DISPLAY_REFRESH_HZ or 60)
		local dt = 1 / tickHz

		self.bus:processDMA(dt)

		if self._bootStage == "RUNNING" and self.kernel then
			local cpuCycles = 4
			for _ = 1, cpuCycles do
				local op = self.cpu:step()
				if op == "HLT" then
					break
				end
			end
			self.kernel:tick(dt)
		end

		self._cursorTimer = self._cursorTimer + dt
		if self._cursorTimer >= 0.5 then
			self._cursorTimer = 0
			if self.gpu then
				self.gpu:toggleCursor()
			end
		end

		if self.gpu then
			self.gpu:flush()
		end

		task.delay(dt, tick)
	end

	local startHz = math.max(self.config.CPU_CLOCK_HZ or 1, self.config.DISPLAY_REFRESH_HZ or 60)
	task.delay(1 / startHz, tick)
end

-- Input binding
function Motherboard:bindInput(UIS)
	self._inputService = UIS
	if self.keyboard then
		self.keyboard:bindRobloxInput(UIS)
	end
end

-- Reboot
function Motherboard:reboot()
	if self.keyboard then
		self.keyboard:unbind()
	end

	self._powered = false
	self._heartbeatGeneration = self._heartbeatGeneration + 1
	self._bootStage = "OFF"
	self.runtime = nil
	self.kernel = nil
	self._bootRecord = nil

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

function Motherboard:_setBootStage(stage, detail)
	self._bootStage = stage
	if self._bootRecord then
		table.insert(self._bootRecord.stages, {
			stage = stage,
			uptime = os.clock() - self._uptimeStart,
			detail = detail,
		})
	end
end

function Motherboard:setBootRecord(record)
	self._bootRecord = self._bootRecord or { startedAt = self._uptimeStart, stages = {} }
	for k, v in pairs(record or {}) do
		self._bootRecord[k] = v
	end
end

function Motherboard:getBootRecord()
	return self._bootRecord
end

-- Stats
function Motherboard:getStats()
	local cpuStats = self.cpu and self.cpu:getStats() or {}
	local ramStats = self.ram and self.ram:getStats() or {}
	local hddStats = self.hdd and self.hdd:getStats() or {}
	local gpuStats = self.gpu and self.gpu:getStats() or {}
	local busStats = self.bus and self.bus:getStats() or {}
	local picStats = (self.bus and self.bus.pic and self.bus.pic.getStats and self.bus.pic:getStats()) or {}
	local timerStats = (self.bus and self.bus.timer and self.bus.timer.getStats and self.bus.timer:getStats()) or {}

	return {
		powered = self._powered,
		bootStage = self._bootStage,
		uptime = os.clock() - self._uptimeStart,
		bootRecord = self._bootRecord,
		cpuStats = cpuStats,
		ramStats = ramStats,
		hddStats = hddStats,
		gpuStats = gpuStats,
		busStats = busStats,
		hardware = {
			cpu = cpuStats,
			ram = ramStats,
			hdd = hddStats,
			gpu = gpuStats,
			bus = busStats,
			pic = picStats,
			timer = timerStats,
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
