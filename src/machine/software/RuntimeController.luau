-- RuntimeController module

local RuntimeController = {}
RuntimeController.__index = RuntimeController

function RuntimeController.new(machine, luauvm)
	local self = setmetatable({}, RuntimeController)
	self.machine = machine
	self.luauvm = luauvm
	self._kernelReady = false
	return self
end

function RuntimeController:startBoot()
	self.machine:_setBootStage("BIOS")

	local BIOS_M = require(script.Parent.Parent.firmware.BIOS)
	self.bios = BIOS_M.new(self.machine)
	self.bios:run(function(memMap)
		self:_onBIOSComplete(memMap)
	end)
end

function RuntimeController:_onBIOSComplete(memMap)
	self.machine:_setBootStage("BOOT")
	local BL_M = require(script.Parent.Parent.bootloader.Bootloader)
	self.bootloader = BL_M.new(self.machine)
	self.bootloader:run(memMap, function(fs, loadAddr, kdata)
		self:_onKernelLoaded(fs, loadAddr, kdata)
	end)
end

function RuntimeController:_onKernelLoaded(fs, loadAddr, kdata)
	self.machine:_setBootStage("KERNEL")

	self.machine.cpu:setReg("PC", loadAddr)

	local K_M = require(script.Parent.Parent.kernel.Kernel)
	self.kernel = K_M.new(self.machine)
	self.machine.kernel = self.kernel

	self.kernel:kmain(fs, loadAddr, kdata)

	local PKG_M = require(script.Parent.Parent.pkgmgr.PackageManager)
	self.kernel.pkgmgr = PKG_M.new(self.kernel)

	self.machine:_setBootStage("RUNNING")
	self._kernelReady = true
end

return RuntimeController
