-- Classifies guest executable files for the shell/runtime boundary.

local ExecutableLoader = {}
ExecutableLoader.__index = ExecutableLoader

local NativeAssembler = require(script.Parent.NativeAssembler)
local NativeExecutable = require(script.Parent.NativeExecutable)

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

local function getNativeConfig(config)
	local native = config and config.NATIVE or {}
	return {
		extension = native.EXTENSION or ".nxe",
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
	local bytes, err = self.vfs:readFile(path)
	if not bytes then
		return nil, err
	end

	if NativeExecutable.isImage(bytes, self.config) then
		local spec, parseErr = NativeExecutable.parse(bytes, self.config)
		if not spec then
			return nil, parseErr
		end
		spec.path = path
		spec.exists = true
		return spec
	end

	local vm = getVmConfig(self.config)
	local native = getNativeConfig(self.config)
	if path:sub(-#native.extension) == native.extension then
		return nil, "native-image-invalid"
	end

	local content, textErr = self.vfs:readFileStr(path)
	if not content then
		return nil, textErr
	end
	local pragma = firstMeaningfulLine(content)
	local spec = {
		path = path,
		content = content,
		pragma = pragma,
		exists = true,
	}

	if pragma == vm.nativePragma then
		local ok, imageOrErr = pcall(function()
			return NativeAssembler.compile(content, self.config, {
				sourcePath = path,
			})
		end)
		if not ok then
			return nil, imageOrErr
		end

		local assembled, parseErr = NativeExecutable.parse(imageOrErr, self.config)
		if not assembled then
			return nil, parseErr
		end

		assembled.path = path
		assembled.exists = true
		assembled.source = content
		assembled.sourceFormat = "native-source"
		assembled.pragma = pragma
		assembled.assembled = true
		return assembled
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
