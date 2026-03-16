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

function RuntimeController:activateIDE(path)
	if not self.kernel then
		return false, "kernel not running"
	end

	local idePath = path or "/usr/lib/novaide/init.lua"
	local source = self.kernel.vfs:readFileStr(idePath)
	if not source then
		return false, "IDE runtime not installed"
	end

	local vm = self.luauvm
	if not vm then
		return false, "LuauVM not available"
	end

	local runtimeEnv = {
		kernel = self.kernel,
		machine = self.machine,
		require = require,
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

	local ok, mod = pcall(function()
		local chunk = vm(source, false, runtimeEnv)
		return chunk()
	end)
	if not ok then
		return false, tostring(mod)
	end

	if type(mod) ~= "table" or type(mod.new) ~= "function" then
		return false, "IDE module invalid"
	end

	local ide = mod.new(self.kernel)
	if not ide or type(ide.start) ~= "function" then
		return false, "IDE instance invalid"
	end

	local started, err = ide:start()
	if started == false then
		return false, tostring(err)
	end

	self.kernel._ide = ide
	return true
end

return RuntimeController
