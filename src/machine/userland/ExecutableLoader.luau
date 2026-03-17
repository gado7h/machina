-- Classifies guest executable files for the shell/runtime boundary.

local ExecutableLoader = {}
ExecutableLoader.__index = ExecutableLoader

local function getVmConfig(config)
	local vm = config and config.VM or {}
	return {
		pragma = vm.PRAGMA or "--!vm",
		nativePragma = vm.NATIVE_PRAGMA or "--!native",
		extension = vm.EXTENSION or ".luau",
		runtime = vm.MANAGED_RUNTIME or "luauvm",
		backend = vm.DEFAULT_BACKEND or "cpu-managed",
		cpuBackend = vm.CPU_BACKEND or "luauvm-cpu",
	}
end

local function firstMeaningfulLine(text)
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		local trimmed = line:match("^%s*(.-)%s*$")
		if trimmed ~= "" then
			return trimmed
		end
	end
	return nil
end

function ExecutableLoader.new(vfs, config)
	local self = setmetatable({}, ExecutableLoader)
	self.vfs = vfs
	self.config = config
	return self
end

function ExecutableLoader:load(path)
	local content, err = self.vfs:readFileStr(path)
	if not content then
		return nil, err
	end

	local vm = getVmConfig(self.config)
	local pragma = firstMeaningfulLine(content)
	local spec = {
		path = path,
		content = content,
		pragma = pragma,
		exists = true,
	}

	if pragma == vm.nativePragma then
		spec.kind = "native"
		spec.format = "native"
		return spec
	end

	if path:sub(-#vm.extension) == vm.extension and pragma == vm.pragma then
		spec.kind = "vm"
		spec.format = "luau"
		spec.runtime = vm.runtime
		spec.backend = vm.backend
		spec.cpuBackend = vm.cpuBackend
		return spec
	end

	spec.kind = "plain"
	spec.format = "text"
	return spec
end

return ExecutableLoader
