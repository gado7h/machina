--!nolint DeprecatedApi
local FiU = require("@self/Fiu")
local Compiler = require("@self/Compiler")
local Base64 = require("@self/Base64")

local LuauVM = {}

function LuauVM.compile(source: string): string
	local bytecode = Compiler.luau_compile(source)
	return Base64.Encode(bytecode)
end

local load = function(_, source: string, isPureBytecode: boolean?, env: { [string]: any }?): () -> ()
	env = env or getfenv(1)

	local func, closure
	if isPureBytecode then
		local bytecode = Base64.Decode(source)
		func, closure = FiU.luau_load(bytecode, env)
	else
		local bytecode = Compiler.luau_compile(source)
		func, closure = FiU.luau_load(bytecode, env)
	end
	return func, closure
end

local ReturnTable = setmetatable({}, {
	__index = function(_, index)
		return LuauVM[index]
	end,
	__call = load,
})

return ReturnTable
