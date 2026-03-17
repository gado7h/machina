-- RuntimeController module

local BootProtocol = require(script.Parent.Parent.bootloader.BootProtocol)

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
	self.bios:run(function(firmwareState)
		self:_onBIOSComplete(firmwareState)
	end)
end

function RuntimeController:_onBIOSComplete(firmwareState)
	self.machine:_setBootStage("BOOT")
	local BL_M = require(script.Parent.Parent.bootloader.Bootloader)
	self.bootloader = BL_M.new(self.machine)
	self.bootloader:run(firmwareState, function(bootResult)
		self:_onKernelLoaded(bootResult)
	end)
end

local function normalizeBootResult(result)
	if type(result) == "table" and result.fs then
		return result
	end
	return {
		fs = result,
		kdata = nil,
	}
end

function RuntimeController:_resolveBootContext(boot)
	local kctx, kctxErr = BootProtocol.readKernelContext(self.machine)
	if not kctx then
		return nil, kctxErr
	end
	local fs = boot.fs
	if not fs then
		return nil, "missing filesystem handle in boot result"
	end

	return {
		fs = fs,
		handoff = kctx.handoff,
		bootInfo = kctx.bootInfo,
		kernelEntry = kctx.kernelEntry,
		kernelData = boot.kdata,
	}
end

function RuntimeController:_onKernelLoaded(result)
	local boot = normalizeBootResult(result)
	local ctx, ctxErr = self:_resolveBootContext(boot)
	if not ctx then
		self.machine:_setBootStage("BOOT", "handoff error: " .. tostring(ctxErr))
		return
	end

	self.machine:_setBootStage("KERNEL")

	local K_M = require(script.Parent.Parent.kernel.Kernel)
	self.kernel = K_M.new(self.machine)
	self.machine.kernel = self.kernel

	self.kernel:kmain(ctx.fs, ctx.kernelEntry, ctx.kernelData)

	local PKG_M = require(script.Parent.Parent.pkgmgr.PackageManager)
	self.kernel.pkgmgr = PKG_M.new(self.kernel)

	BootProtocol.writeHandoff(self.machine, {
		stage = BootProtocol.STAGE.KERNEL_ENTERED,
	})

	if self.machine.setBootRecord then
		self.machine:setBootRecord({
			handoffAddr = ctx.handoff.addr,
			bootInfoAddr = ctx.bootInfo.addr,
			bootDrive = ctx.bootInfo.bootDrive,
			loadAddr = ctx.kernelEntry,
			kernelSize = ctx.bootInfo.kernelSize,
		})
	end

	self.machine:_setBootStage("RUNNING")
	self._kernelReady = true
end

return RuntimeController
