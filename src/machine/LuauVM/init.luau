--!nolint DeprecatedApi
local FiU = require("@self/Fiu")
local Compiler = require("@self/Compiler")
local Base64 = require("@self/Base64")

local LuauVM = {}

function LuauVM.compile(source: string): string
	local bytecode = Compiler.luau_compile(source)
	return Base64.Encode(bytecode)
end

local function loadWithRuntime(bytecode: string, env: { [string]: any }?)
	env = env or getfenv(1)

	-- Optional CPU hook for future CPU-native execution paths.
	local cpu = env.__nova_cpu
	if cpu and type(cpu.executeLuauBytecode) == "function" then
		local fn = cpu:executeLuauBytecode(bytecode, env)
		if fn then
			return fn, nil
		end
	end

	return FiU.luau_load(bytecode, env)
end

local load = function(_, source: string, isPureBytecode: boolean?, env: { [string]: any }?): () -> ()
	if isPureBytecode then
		local bytecode = Base64.Decode(source)
		return loadWithRuntime(bytecode, env)
	end

	local bytecode = Compiler.luau_compile(source)
	return loadWithRuntime(bytecode, env)
end

local ReturnTable = setmetatable({}, {
	__index = function(_, index)
		return LuauVM[index]
	end,
	__call = load,
})

return ReturnTable
