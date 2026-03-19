-- Kernel driver facade layer.
-- This isolates kernel logic from direct hardware object usage.

local Drivers = {}
Drivers.__index = Drivers

local function makeConsoleDriver(gpu, config)
	local driver = {}

	function driver:isAvailable()
		return gpu ~= nil
	end

	function driver:print(text, attr)
		if gpu then
			gpu:print(tostring(text or ""), attr)
		end
	end

	function driver:println(text, attr)
		if gpu then
			gpu:println(tostring(text or ""), attr)
		end
	end

	function driver:clear(attr)
		if not gpu then
			return
		end
		if attr ~= nil then
			gpu:clearScreen(attr)
		else
			gpu:clearScreen()
		end
	end

	function driver:flush()
		if gpu then
			gpu:flush()
		end
	end

	function driver:size()
		return (config and config.TEXT_COLS) or 80, (config and config.TEXT_ROWS) or 25
	end

	return driver
end

local function makeKeyboardDriver(keyboard)
	local driver = {}

	function driver:isAvailable()
		return keyboard ~= nil
	end

	function driver:readChar()
		if keyboard and keyboard.readChar then
			return keyboard:readChar()
		end
		return nil
	end

	return driver
end

local function makeTimerDriver(bus, config)
	local driver = {}
	local irqTimer = (config and config.IRQ and config.IRQ.TIMER) or 0

	function driver:registerTickIRQ(handler)
		if bus and bus.registerIRQ then
			bus:registerIRQ(irqTimer, "kernel.timer", function(_irq, data)
				handler(data)
			end)
		end
	end

	return driver
end

local function makeDiskDriver(bus, config, hdd)
	local driver = {}
	local irqAta = (config and config.IRQ and config.IRQ.ATA) or 14

	function driver:registerIRQ(handler)
		if bus and bus.registerIRQ then
			bus:registerIRQ(irqAta, "kernel.disk", function(_irq, data)
				handler(data)
			end)
		end
	end

	-- Transitional compatibility path for call sites that still need raw sectors.
	-- Kernel code should prefer controller/MMIO paths in later phases.
	function driver:readSector(lba)
		if hdd and hdd.readSector then
			return hdd:readSector(lba)
		end
		return nil
	end

	function driver:writeSector(lba, bytes)
		if hdd and hdd.writeSector then
			return hdd:writeSector(lba, bytes)
		end
		return false
	end

	return driver
end

function Drivers.new(machine, config)
	local self = setmetatable({}, Drivers)
	self.machine = machine
	self.config = config or machine.config
	self.bus = machine.bus

	self.console = makeConsoleDriver(machine.gpu, self.config)
	self.keyboard = makeKeyboardDriver(machine.keyboard)
	self.timer = makeTimerDriver(machine.bus, self.config)
	self.disk = makeDiskDriver(machine.bus, self.config, machine.hdd)

	return self
end

return Drivers
