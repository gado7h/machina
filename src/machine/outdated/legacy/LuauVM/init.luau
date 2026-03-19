--!nolint DeprecatedApi
local FiU = require("@self/Fiu")
local Compiler = require("@self/Compiler")
local Base64 = require("@self/Base64")

local LuauVM = {}
local RUNTIME_NAME = "luauvm"

function LuauVM.compile(source: string): string
	local bytecode = Compiler.luau_compile(source)
	return Base64.Encode(bytecode)
end

local function makeManagedRuntime()
	return {
		compileSource = function(source: string): string
			return Compiler.luau_compile(source)
		end,
		loadBytecode = function(bytecode: string, env: { [string]: any }?, _context)
			env = env or getfenv(1)
			return FiU.luau_load(bytecode, env)
		end,
	}
end

local function makeCPUBackend(runtimeName: string)
	return {
		kind = "managed-runtime-adapter",
		runtime = runtimeName,
		execute = function(cpu, session)
			local runtime = cpu:getManagedRuntime(session.runtimeName or runtimeName)
			if not runtime or type(runtime.loadBytecode) ~= "function" then
				return nil, "managed-runtime-unavailable:" .. tostring(session.runtimeName or runtimeName)
			end
			return runtime.loadBytecode(session.bytecode, session.env, session.context)
		end,
	}
end

function LuauVM.registerCPU(cpu)
	if not cpu then
		return false
	end

	local vmConfig = cpu.config and cpu.config.VM or {}
	local backendName = vmConfig.CPU_BACKEND or "luauvm-cpu"
	local attached = false

	if type(cpu.attachManagedRuntime) == "function" then
		attached = cpu:attachManagedRuntime(RUNTIME_NAME, makeManagedRuntime()) or attached
	end
	if type(cpu.registerGuestExecutionBackend) == "function" then
		attached = cpu:registerGuestExecutionBackend(backendName, makeCPUBackend(RUNTIME_NAME)) or attached
	elseif type(cpu.ensureManagedGuestBackend) == "function" then
		cpu:ensureManagedGuestBackend(RUNTIME_NAME, backendName)
		attached = true
	end

	return attached
end

local function loadWithRuntime(bytecode: string, env: { [string]: any }?, context)
	env = env or getfenv(1)
	context = context or rawget(env, "__nova_exec_ctx")

	if context and type(context.executeBytecode) == "function" then
		local fn, err = context:executeBytecode(bytecode, env)
		if fn then
			return fn, nil
		end
		return nil, err
	end

	return FiU.luau_load(bytecode, env)
end

local load = function(_, source: string, isPureBytecode: boolean?, env: { [string]: any }?, context)
	if isPureBytecode then
		local bytecode = Base64.Decode(source)
		return loadWithRuntime(bytecode, env, context)
	end

	local bytecode = Compiler.luau_compile(source)
	return loadWithRuntime(bytecode, env, context)
end

local ReturnTable = setmetatable({}, {
	__index = function(_, index)
		return LuauVM[index]
	end,
	__call = load,
})

return ReturnTable
