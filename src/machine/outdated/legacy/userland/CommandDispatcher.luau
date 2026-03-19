-- Command dispatch model for nsh.
-- Separates internal built-ins from external executable files.

local CommandDispatcher = {}
CommandDispatcher.__index = CommandDispatcher

function CommandDispatcher.new(opts)
	local self = setmetatable({}, CommandDispatcher)
	self._builtins = {}
	self._resolveExternal = opts and opts.resolveExternal or nil
	return self
end

function CommandDispatcher:setBuiltins(builtins)
	self._builtins = builtins or {}
end

function CommandDispatcher:classify(cmd)
	if not cmd or cmd == "" then
		return { kind = "missing", name = tostring(cmd) }
	end

	local builtin = self._builtins[cmd]
	if builtin then
		return {
			kind = "builtin",
			name = cmd,
			handler = builtin,
		}
	end

	local path = self._resolveExternal and self._resolveExternal(cmd) or nil
	if path then
		return {
			kind = "external",
			name = cmd,
			path = path,
		}
	end

	return { kind = "missing", name = cmd }
end

return CommandDispatcher
