local BiosInterrupts = require("@src/platforms/x86/BiosInterrupts")
local HardwareDiagnostics = require("@src/platforms/x86/HardwareDiagnostics")
local BootImageLoader = require("@src/platforms/x86/BootImageLoader")

local BootController = {}
BootController.__index = BootController

function BootController.new(machine)
	local self = setmetatable({}, BootController)
	self.machine = machine
	self.config = machine.config
	self.x86 = machine.config.X86 or {}
	self.image = nil
	self.bios = nil
	self._kernelLinear = ((self.x86.KERNEL_LOAD_SEG or 0x1000) * 16) + (self.x86.KERNEL_LOAD_OFF or 0)
	self._bootLinear = ((self.x86.BOOT_SECTOR_LOAD_SEG or 0) * 16) + (self.x86.BOOT_SECTOR_LOAD_OFF or 0x7C00)
	self._readyFlagLinear = nil
	return self
end

function BootController:startBoot()
	self.machine:_setBootStage("BIOS")
	self.machine.gpu:clearHostOverlay()
	self.machine.gpu:biosSetVideoMode(0x03)

	if self.machine.bus and self.machine.bus.timer then
		self.machine.bus.timer._enabled = false
		self.machine.bus.timer._irqEnabled = false
	end

	local ok, imageOrErr = pcall(function()
		return BootImageLoader.load(self.config)
	end)
	if not ok then
		self.machine:_setBootStage("FAULT", tostring(imageOrErr))
		self.machine.gpu:hostClear(0x0C)
		self.machine.gpu:hostWriteLine("x86 image build failed", 0x0C)
		self.machine.gpu:hostWriteLine(tostring(imageOrErr), 0x0C)
		return
	end

	self.image = imageOrErr
	self.machine.hdd._sectors = {}
	for lba, sector in pairs(self.image.sectors) do
		self.machine.hdd:writeSector(lba, sector)
	end

	self.machine.rom:flash(self.image.romBytes)
	self.machine.cpu:reset()

	local diagnostics = nil
	local diagnosticsConfig = (self.x86 and self.x86.DIAGNOSTICS) or {}
	if diagnosticsConfig.ENABLED ~= false then
		self.machine:_setBootStage("DIAG")
		diagnostics = HardwareDiagnostics.run(self.machine, self.config)
		if diagnosticsConfig.PRINT_SUMMARY ~= false then
			local color = diagnostics.passed and 0x0A or 0x0E
			self.machine.gpu:hostClear(color)
			self.machine.gpu:hostWriteLine(
				string.format("Device diagnostics %d/%d", diagnostics.passedCount, diagnostics.totalCount),
				color
			)
		end
		self.machine.cpu:reset()
		self.machine.gpu:biosSetVideoMode(0x03)
	end

	self:_initializeIVT()
	self:_initializeBDA()

	if self.machine.bus and self.machine.bus.timer then
		self.machine.bus.timer._enabled = true
		self.machine.bus.timer._irqEnabled = true
	end

	self.bios = BiosInterrupts.new(self.machine, self, self.image)
	self.machine.cpu:attachBIOS(self.bios)
	local kernelSymbols = self.image.symbols and self.image.symbols.kernel or nil
	local readyFlagOffset = kernelSymbols and kernelSymbols.BOOT_READY_FLAG or nil
	self._readyFlagLinear = readyFlagOffset and (self._kernelLinear + readyFlagOffset) or nil

	self.machine:setBootRecord({
		profile = "x86-bios",
		imageSource = self.image.meta and self.image.meta.source or "external",
		imageProvider = self.image.meta and self.image.meta.provider or "ProtectedModeBringUp",
		imageName = self.image.meta and self.image.meta.name or "ProtectedModeBringUp",
		kernelSectorStart = self.image.layout.kernelSectorStart,
		kernelSectorCount = self.image.layout.kernelSectorCount,
		fsSuperSector = self.image.layout.fsSuperSector,
		rootDirSector = self.image.layout.rootDirSector,
		rootDirSectorCount = self.image.layout.rootDirSectorCount,
		dataStartSector = self.image.layout.dataStartSector,
		fileCount = self.image.layout.fileCount,
		readyFlagLinear = self._readyFlagLinear,
		diagnostics = diagnostics,
	})
	self.machine.gpu:clearHostOverlay()
	self.machine:_setBootStage("BIOS")
end

function BootController:onDiskRead(startLba, _count, bufferAddress)
	if startLba == 0 and bufferAddress == self._bootLinear then
		self.machine:_setBootStage("BOOT")
	elseif startLba == (self.image.layout.kernelSectorStart - 1) and bufferAddress == self._kernelLinear then
		self.machine:_setBootStage("KERNEL")
	end
end

function BootController:tick(_dt)
	if self.machine:getBootStage() ~= "KERNEL" then
		return
	end
	if self._readyFlagLinear and self.machine.cpu:readPhysical16(self._readyFlagLinear) == 1 then
		self.machine:_setBootStage("RUNNING")
		return
	end
	local pc = self.machine.cpu:getLinearPC()
	if not self._readyFlagLinear and pc >= self._kernelLinear then
		self.machine:_setBootStage("RUNNING")
	end
end

function BootController:_initializeIVT()
	local cpu = self.machine.cpu
	local romBase = self.x86.ROM_BASE or 0xF0000
	for vector = 0, 0xFF do
		local offset = vector * 4
		cpu:writePhysical8(offset, 0x00)
		cpu:writePhysical8(offset + 1, 0x00)
		cpu:writePhysical8(offset + 2, bit32.band(romBase, 0xFF))
		cpu:writePhysical8(offset + 3, bit32.rshift(romBase, 8) % 0x100)
	end
end

function BootController:_initializeBDA()
	local cpu = self.machine.cpu
	cpu:writePhysical8(0x0400, 0x50)
	cpu:writePhysical8(0x0401, 0x14)
	cpu:writePhysical8(0x0402, 0x00)
	cpu:writePhysical8(0x0403, 0x00)
	cpu:writePhysical8(0x0404, 0x00)
	cpu:writePhysical8(0x0405, 0x00)
	cpu:writePhysical8(0x0406, 0x00)
	cpu:writePhysical8(0x0407, 0x00)
	cpu:writePhysical8(0x0408, 0x00)
	cpu:writePhysical8(0x0409, 0x00)
	cpu:writePhysical8(0x040A, 0x00)
	cpu:writePhysical8(0x040B, 0x00)
	cpu:writePhysical8(0x040C, 0x00)
	cpu:writePhysical8(0x040D, 0x00)
	cpu:writePhysical8(0x040E, 0x00)
	cpu:writePhysical8(0x040F, 0x00)
	cpu:writePhysical8(0x0410, 0x00)
	cpu:writePhysical8(0x0411, 0x00)
	cpu:writePhysical8(0x0412, 0x80)
	cpu:writePhysical8(0x0413, 0x02)
	cpu:writePhysical8(0x0414, 0x00)
	cpu:writePhysical8(0x0415, 0x00)
	cpu:writePhysical8(0x0416, 0x00)
	cpu:writePhysical8(0x0417, 0x00)
	cpu:writePhysical8(0x0418, 0x00)
	cpu:writePhysical8(0x0419, 0x00)
	cpu:writePhysical8(0x041A, 0x00)
	cpu:writePhysical8(0x041B, 0x50)
	cpu:writePhysical8(0x041C, 0x14)
	cpu:writePhysical8(0x041D, 0x00)
	cpu:writePhysical8(0x041E, 0x00)
	cpu:writePhysical8(0x041F, 0x00)
	cpu:writePhysical8(0x0480, 0x00)
	cpu:writePhysical8(0x0481, 0x0C)
	cpu:writePhysical8(0x0482, 0x00)
	cpu:writePhysical8(0x0483, 0x00)
end

return BootController
