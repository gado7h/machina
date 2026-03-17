-- Shell module

local CommandDispatcher = require(script.Parent.CommandDispatcher)
local ExecutableLoader = require(script.Parent.ExecutableLoader)

local Shell = {}
Shell.__index = Shell

local function getVmConfig(config)
	local vm = config and config.VM or {}
	return {
		enabled = vm.ENABLED == true,
		pragma = vm.PRAGMA or "--!vm",
		extension = vm.EXTENSION or ".luau",
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

function Shell.new(kernel, username)
	local self = setmetatable({}, Shell)
	self.kernel = kernel
	self.gpu = kernel.gpu
	self.vfs = kernel.vfs
	self.pm = kernel.pm
	self.mm = kernel.mm
	self.sc = kernel.syscall
	self.keyboard = kernel.keyboard
	self.config = kernel.config
	self.luauvm = kernel.machine and kernel.machine.luauvm

	self._foreground = nil
	self._foregroundInput = nil
	self._foregroundCleanup = nil
	self._suppressPrompt = false

	self.username = username or "user"
	self.hostname = kernel._hostname or kernel.config.HOSTNAME
	self.cwd = (username == "root") and "/root" or ("/home/" .. username)
	self.env = {
		HOME = (username == "root") and "/root" or ("/home/" .. username),
		USER = username,
		SHELL = "/bin/sh",
		PATH = "/bin:/usr/bin:/usr/local/bin:/pkg/bin",
		TERM = "nova-vt100",
		LANG = "en_US.UTF-8",
		OLDPWD = "/",
		HISTSIZE = "100",
		PS1 = "",
	}
	self.exitCode = 0
	self._history = {}
	self._histIdx = 0
	self._lineBuf = {}
	self._running = false
	self._jobs = {}
	self._aliases = {
		["ll"] = "ls -la",
		["la"] = "ls -a",
		[".."] = "cd ..",
		["..."] = "cd ../..",
	}
	self._builtins = self:_buildBuiltins()
	self._loader = ExecutableLoader.new(self.vfs, self.config)
	self._dispatcher = CommandDispatcher.new({
		resolveExternal = function(cmd)
			return self:_resolveExecutablePath(cmd)
		end,
	})
	self._dispatcher:setBuiltins(self._builtins)
	return self
end

function Shell:_getVmConfig()
	return getVmConfig(self.config)
end

function Shell:_pathDirs()
	local dirs = {}
	local rawPath = tostring((self.env and self.env.PATH) or "")
	for dir in rawPath:gmatch("([^:]+)") do
		if dir ~= "" then
			table.insert(dirs, dir)
		end
	end
	if #dirs == 0 then
		return { "/bin", "/usr/bin", "/usr/local/bin", "/pkg/bin" }
	end
	return dirs
end

function Shell:_isVMFile(path, content)
	local vm = self:_getVmConfig()
	if not path or path:sub(-#vm.extension) ~= vm.extension then
		return false
	end
	return firstMeaningfulLine(content or "") == vm.pragma
end

function Shell:_resolveExecutablePath(cmd)
	local vm = self:_getVmConfig()
	local function isExecutableFile(path)
		if not self.vfs:exists(path) then
			return false
		end
		local st = self.vfs:stat(path)
		return st ~= nil and not st.isDir
	end

	local candidates = {}
	if cmd:sub(1, 1) == "/" then
		table.insert(candidates, cmd)
		table.insert(candidates, cmd .. vm.extension)
	else
		for _, dir in ipairs(self:_pathDirs()) do
			table.insert(candidates, dir .. "/" .. cmd)
			table.insert(candidates, dir .. "/" .. cmd .. vm.extension)
		end
	end

	for _, candidate in ipairs(candidates) do
		if isExecutableFile(candidate) then
			return candidate
		end
	end
	return nil
end

function Shell:_classifyCommand(cmd)
	return self._dispatcher:classify(cmd)
end

function Shell:_dispatchParsedCommand(parsed)
	local spec = self:_classifyCommand(parsed.cmd)
	if spec.kind == "builtin" then
		return spec.handler(parsed.args, parsed) or 0
	end
	if spec.kind == "external" then
		return self:_runExternal(spec.path, parsed.args, parsed) or 127
	end
	self.gpu:println("nsh: " .. tostring(parsed.cmd) .. ": command not found", 0x0C)
	return 127
end

--  Start
function Shell:start()
	self._running = true
	if not self.vfs:exists(self.cwd) then
		self.vfs:mkdir(self.cwd)
	end
	self:_prompt()
	self:_pollLoop()
end

function Shell:_prompt()
	local sym = (self.username == "root") and "#" or "$"
	local cwd = self.cwd
	local home = self.env.HOME or "/"
	if cwd:sub(1, #home) == home then
		cwd = "~" .. cwd:sub(#home + 1)
	end
	if cwd == "" then
		cwd = "/"
	end
	self.gpu:print(
		string.format("\n[\27[32m%s@%s\27[0m \27[36m%s\27[0m]%s ", self.username, self.hostname, cwd, sym),
		0x0A
	)
	-- ANSI not rendered in text mode; use plain version:
	local col, row = self.gpu:getCursor()
	-- reprint plainly since GPU text mode ignores ANSI
	self.gpu:moveCursor(0, row)
	for c = 0, self.config.TEXT_COLS - 1 do
		self.gpu:putChar(c, row, 32, 0x07)
	end
	self.gpu:print(string.format("[%s@%s %s]%s ", self.username, self.hostname, cwd, sym), 0x0A)
end

--  Input loop
function Shell:_pollLoop()
	if not self._running then
		return
	end
	local function poll()
		if not self._running then
			return
		end
		if self.keyboard then
			while true do
				local ch = self.keyboard:readChar()
				if not ch then
					break
				end
				self:_handleChar(ch)
			end
		end
		task.delay(0.04, poll)
	end
	task.delay(0.04, poll)
end

function Shell:_handleChar(ch)
	local g = self.gpu

	-- Foreground app owns input first
	if self._foreground then
		if ch == "\3" then -- Ctrl+C
			self:interruptForeground()
			return
		end

		if self:sendForegroundInput(ch) then
			return
		end
	end

	if ch == "\n" or ch == "\r" then
		local line = table.concat(self._lineBuf)
		self._lineBuf = {}
		g:println("")

		if line:match("%S") then
			if self._history[1] ~= line then
				table.insert(self._history, 1, line)
				if #self._history > 100 then
					table.remove(self._history)
				end
			end
		end

		self._histIdx = 0

		if line:match("%S") then
			self:_executeLine(line)
		end

		if self._running and not self._suppressPrompt and not self._foreground then
			self:_prompt()
		end
	elseif ch == "\b" then
		if #self._lineBuf > 0 then
			table.remove(self._lineBuf)
			g:print("\b")
		end
	elseif ch == "\3" then -- Ctrl+C
		g:println("^C", 0x0C)
		self._lineBuf = {}
		if self._running and not self._foreground then
			self:_prompt()
		end
	elseif ch == "\4" then -- Ctrl+D
		g:println("exit", 0x07)
		self._running = false
	elseif ch == "[UP]" then
		self._histIdx = math.min(self._histIdx + 1, #self._history)
		self:_replaceInput(self._history[self._histIdx] or "")
	elseif ch == "[DOWN]" then
		self._histIdx = math.max(self._histIdx - 1, 0)
		self:_replaceInput(self._histIdx > 0 and self._history[self._histIdx] or "")
	elseif ch == "\t" then
		self:_tabComplete()
	else
		table.insert(self._lineBuf, ch)
		g:print(ch)
	end
end

function Shell:_replaceInput(new)
	for _ = 1, #self._lineBuf do
		self.gpu:print("\b")
	end
	self._lineBuf = {}
	for i = 1, #new do
		table.insert(self._lineBuf, new:sub(i, i))
	end
	self.gpu:print(new)
end

function Shell:_tabComplete()
	local partial = table.concat(self._lineBuf)
	local lastWord = partial:match("%S+$") or ""
	if lastWord == "" then
		return
	end
	local completions = {}
	local seen = {}
	local function addCompletion(name)
		if name == "" or seen[name] then
			return
		end
		seen[name] = true
		table.insert(completions, name)
	end
	if lastWord:find("/") or lastWord:sub(1, 1) == "." or lastWord:sub(1, 1) == "~" then
		local expanded = lastWord:gsub("^~", self.env.HOME or "/home/" .. self.username)
		local dir, prefix
		if expanded:sub(-1) == "/" then
			dir = expanded
			prefix = ""
		else
			dir = expanded:match("^(.*/)") or self.cwd .. "/"
			prefix = expanded:match("[^/]+$") or ""
		end
		local entries = self.vfs:listDir(dir)
		if entries then
			for _, e in ipairs(entries) do
				if e.name:sub(1, #prefix) == prefix then
					addCompletion(e.name .. (e.isDir and "/" or ""))
				end
			end
		end
	else
		local vmCfg = self:_getVmConfig()
		for name in pairs(self._builtins) do
			if name:sub(1, #lastWord) == lastWord then
				addCompletion(name)
			end
		end
		for _, dir in ipairs(self:_pathDirs()) do
			local entries = self.vfs:listDir(dir)
			if entries then
				for _, e in ipairs(entries) do
					if e.isDir then
						continue
					end
					local name = e.name
					if name:sub(1, #lastWord) == lastWord then
						addCompletion(name)
					end
					if vmCfg.extension ~= "" and name:sub(-#vmCfg.extension) == vmCfg.extension then
						local base = name:sub(1, #name - #vmCfg.extension)
						if base ~= "" and base:sub(1, #lastWord) == lastWord then
							addCompletion(base)
						end
					end
				end
			end
		end
	end
	table.sort(completions)
	if #completions == 1 then
		local suffix = completions[1]:sub(#lastWord + 1)
		for i = 1, #suffix do
			table.insert(self._lineBuf, suffix:sub(i, i))
		end
		self.gpu:print(suffix)
	elseif #completions > 1 then
		self.gpu:println("")
		-- print in columns
		local line = {}
		for _, c in ipairs(completions) do
			table.insert(line, string.format("%-16s", c))
			if #line >= 4 then
				self.gpu:println(table.concat(line), 0x07)
				line = {}
			end
		end
		if #line > 0 then
			self.gpu:println(table.concat(line), 0x07)
		end
		self:_prompt()
		self.gpu:print(table.concat(self._lineBuf))
	end
end

--  Line execution
function Shell:_executeLine(line)
	-- Expand aliases
	local firstWord = line:match("^%s*(%S+)")
	if firstWord and self._aliases[firstWord] then
		line = self._aliases[firstWord] .. line:sub(#firstWord + 1)
	end
	-- Strip comments
	line = line:match("^([^#]*)") or line
	line = line:match("^%s*(.-)%s*$")
	if line == "" then
		return
	end

	-- Background job
	local background = false
	if line:sub(-1) == "&" then
		background = true
		line = line:sub(1, -2):match("^%s*(.-)%s*$")
	end

	-- Semicolon-separated commands
	if line:find(";") then
		for part in line:gmatch("([^;]+)") do
			local p = part:match("^%s*(.-)%s*$")
			if p ~= "" then
				self:_executeLine(p)
			end
		end
		return
	end

	-- Logical operators
	if line:find("&&") then
		local a, b = line:match("^(.-)&&(.+)$")
		if a and b then
			self:_executeLine(a:match("^%s*(.-)%s*$"))
			if self.exitCode == 0 then
				self:_executeLine(b:match("^%s*(.-)%s*$"))
			end
			return
		end
	end
	if line:find("||") then
		local a, b = line:match("^(.-)%|%|(.+)$")
		if a and b then
			self:_executeLine(a:match("^%s*(.-)%s*$"))
			if self.exitCode ~= 0 then
				self:_executeLine(b:match("^%s*(.-)%s*$"))
			end
			return
		end
	end

	-- Pipeline
	local stages = {}
	for seg in (line .. "|"):gmatch("(.-)|") do
		local s = seg:match("^%s*(.-)%s*$")
		if s ~= "" then
			table.insert(stages, s)
		end
	end
	if #stages > 1 then
		self:_executePipeline(stages)
	else
		self:_executeCommand(line)
	end
end

--  Parsing
function Shell:_parseCommand(cmdStr)
	local s = cmdStr
	local redirectIn, redirectOut, redirectAppend

	-- Extract >> before >
	local ra = s:match(">>%s*(%S+)")
	if ra then
		redirectAppend = ra
		s = s:gsub(">>%s*" .. ra:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1"), "")
	end
	local ro = s:match("[^>]>%s*(%S+)") or s:match("^>%s*(%S+)")
	if ro then
		redirectOut = ro
		s = s:gsub(">%s*" .. ro:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1"), "")
	end
	local ri = s:match("<%s*(%S+)")
	if ri then
		redirectIn = ri
		s = s:gsub("<%s*" .. ri:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1"), "")
	end

	-- Expand variables
	s = s:gsub("%$(%w+)", function(v)
		return self.env[v] or ""
	end)
	s = s:gsub("%$%?", tostring(self.exitCode))
	s = s:gsub("~", self.env.HOME or "/home/" .. self.username)

	-- Tokenise respecting quotes
	local tokens = {}
	local i = 1
	while i <= #s do
		while i <= #s and s:sub(i, i):match("%s") do
			i = i + 1
		end
		if i > #s then
			break
		end
		local ch = s:sub(i, i)
		local tok = ""
		if ch == '"' then
			i = i + 1
			while i <= #s and s:sub(i, i) ~= '"' do
				if s:sub(i, i) == "\\" then
					i = i + 1
				end
				tok = tok .. (s:sub(i, i) or "")
				i = i + 1
			end
			i = i + 1
		elseif ch == "'" then
			i = i + 1
			while i <= #s and s:sub(i, i) ~= "'" do
				tok = tok .. s:sub(i, i)
				i = i + 1
			end
			i = i + 1
		else
			while i <= #s and not s:sub(i, i):match("%s") do
				tok = tok .. s:sub(i, i)
				i = i + 1
			end
		end
		if tok ~= "" then
			table.insert(tokens, tok)
		end
	end
	if #tokens == 0 then
		return nil
	end
	return {
		cmd = tokens[1],
		args = tokens,
		redirectIn = redirectIn,
		redirectOut = redirectOut,
		redirectAppend = redirectAppend,
	}
end

--  Execute
function Shell:_executeCommand(cmdStr)
	local parsed = self:_parseCommand(cmdStr)
	if not parsed then
		return 0
	end

	local savedPrint, outLines
	if parsed.redirectOut or parsed.redirectAppend then
		outLines = {}
		savedPrint = { print = self.gpu.print, println = self.gpu.println }

		local function capture(_, s)
			table.insert(outLines, s or "")
		end

		self.gpu.print = capture
		self.gpu.println = function(_, s)
			table.insert(outLines, (s or "") .. "\n")
		end
	end

	self.exitCode = self:_dispatchParsedCommand(parsed)

	if savedPrint then
		self.gpu.print = savedPrint.print
		self.gpu.println = savedPrint.println

		local content = table.concat(outLines)
		local path = parsed.redirectOut or parsed.redirectAppend

		if parsed.redirectAppend then
			self.vfs:appendFile(path, self:_strBytes(content))
		else
			self.vfs:writeFileStr(path, content)
		end
	end

	return self.exitCode
end

function Shell:_executePipeline(stages)
	local output = nil
	for _, stage in ipairs(stages) do
		local parsed = self:_parseCommand(stage)
		if not parsed then
			break
		end
		local outBuf = {}
		local savedP = self.gpu.print
		local savedPL = self.gpu.println
		self.gpu.print = function(_, s, a)
			table.insert(outBuf, s or "")
		end
		self.gpu.println = function(_, s, a)
			table.insert(outBuf, (s or "") .. "\n")
		end
		-- inject stdin if we have pipe input
		if output then
			self._pipeInput = output
		end
		self.exitCode = self:_dispatchParsedCommand(parsed)
		self._pipeInput = nil
		self.gpu.print = savedP
		self.gpu.println = savedPL
		output = table.concat(outBuf)
	end
	if output and output ~= "" then
		self.gpu:print(output)
	end
end

function Shell:_execFromPath(cmd, args, parsed)
	local path = self:_resolveExecutablePath(cmd)
	if path then
		return self:_runScript(path, args, parsed)
	end
	self.gpu:println("nsh: " .. cmd .. ": command not found", 0x0C)
	return 127
end

function Shell:_runExternal(path, args, parsed)
	local spec, err = self._loader:load(path)
	if not spec then
		self.gpu:println("nsh: cannot read " .. path .. ": " .. tostring(err), 0x0C)
		return 126
	end

	local vmCfg = self:_getVmConfig()
	if spec.kind == "plain" then
		self.gpu:println("nsh: " .. path .. ": not an executable guest file", 0x0C)
		return 126
	end

	if spec.kind == "native" then
		self.gpu:println("nsh: " .. path .. ": native guest binaries are not implemented yet", 0x0C)
		return 126
	end

	if not vmCfg.enabled then
		self.gpu:println("nsh: guest VM execution is disabled in config", 0x0C)
		return 1
	end

	local cpu = self.kernel.machine and self.kernel.machine.cpu
	if not cpu or type(cpu.executeGuestExecutable) ~= "function" then
		self.gpu:println("nsh: CPU guest execution backend unavailable", 0x0C)
		return 1
	end

	local execContext = cpu:createExecutionContext({
		pid = self.kernel.pm and self.kernel.pm._currentPid or 0,
		argv = args or {},
		env = self.env,
		executable = {
			path = spec.path,
			kind = spec.kind,
			format = spec.format,
			runtime = spec.runtime,
			cpuBackend = spec.cpuBackend,
		},
		backend = spec.backend or "auto",
	})
	local runtimeEnv = self:_makeRuntimeEnv(args, parsed, execContext)

	local ok, func, loadErr = pcall(function()
		return cpu:executeGuestExecutable(spec, runtimeEnv, execContext)
	end)

	if not ok or not func then
		self.gpu:println("nsh: failed to load " .. path, 0x0C)
		self.gpu:println(tostring(loadErr or func), 0x0C)
		return 1
	end

	local runOk, result = pcall(func)
	if not runOk then
		if type(result) == "table" and result.__exit then
			return tonumber(result.code) or 0
		end

		self.gpu:println(path .. ": " .. tostring(result), 0x0C)
		if self._foreground then
			self:endForeground()
		end
		return 1
	end

	return type(result) == "number" and result or 0
end

Shell._runScript = Shell._runExternal

--  Process runtime environment (given to every script)
function Shell:_makeRuntimeEnv(args, parsed, execContext)
	local vfs = self.vfs
	local gpu = self.gpu
	local kernel = self.kernel
	local shell = self
	local env = self.env

	local stdinData = self._pipeInput

	local function resolvePath(path)
		path = tostring(path or "")
		if path == "" then
			return shell.cwd
		end
		if path:sub(1, 1) == "~" then
			path = (shell.env.HOME or "/home/" .. shell.username) .. path:sub(2)
		end
		if path:sub(1, 1) ~= "/" then
			path = shell.cwd .. "/" .. path
		end
		local parts = {}
		for seg in path:gmatch("[^/]+") do
			if seg == ".." then
				table.remove(parts)
			elseif seg ~= "." and seg ~= "" then
				table.insert(parts, seg)
			end
		end
		return "/" .. table.concat(parts, "/")
	end

	local sandbox = {}
	sandbox.__nova_exec_ctx = execContext

	-- Standard I/O
	sandbox.print = function(...)
		gpu:println(table.concat({ ... }, "\t"))
	end
	sandbox.io = {
		write = function(_, s)
			gpu:print(tostring(s))
		end,
		read = function(_, fmt)
			if stdinData then
				-- consume from pipe
				local line = stdinData:match("^([^\n]*)\n?")
				stdinData = stdinData:sub(#(line or "") + 2)
				return line
			end
			if shell.keyboard then
				return shell.keyboard:readChar()
			end
			return nil
		end,
		lines = function(_, src)
			local data = src and vfs:readFileStr(src) or stdinData or ""
			local lines = {}
			for l in (data .. "\n"):gmatch("([^\n]*)\n") do
				table.insert(lines, l)
			end
			local i = 0
			return function()
				i = i + 1
				return lines[i]
			end
		end,
		open = function(_, path, mode)
			mode = mode or "r"
			local abspath = path:sub(1, 1) == "/" and path or (shell.cwd .. "/" .. path)
			if mode:find("w") then
				return {
					write = function(self2, s)
						vfs:appendFile(abspath, shell:_strBytes(tostring(s)))
					end,
					close = function() end,
					lines = function()
						return function()
							return nil
						end
					end,
				}
			else
				local content = vfs:readFileStr(abspath) or ""
				local lines = {}
				for l in (content .. "\n"):gmatch("([^\n]*)\n") do
					table.insert(lines, l)
				end
				local pos = 0
				return {
					read = function(self2, fmt)
						if fmt == "*l" or fmt == "l" then
							pos = pos + 1
							return lines[pos]
						elseif fmt == "*a" or fmt == "a" then
							return content
						end
						return nil
					end,
					lines = function(self2)
						local j = 0
						return function()
							j = j + 1
							return lines[j]
						end
					end,
					close = function() end,
				}
			end
		end,
	}

	-- Args (like a main() receives them)
	sandbox.arg = args or {}
	sandbox.args = args or {}

	-- OS functions
	sandbox.os = {
		time = os.time,
		date = os.date,
		clock = os.clock,
		exit = function(code)
			error({ __exit = true, code = code or 0 })
		end,
		getenv = function(v)
			return env[v] or nil
		end,
		execute = function(cmd)
			cmd = tostring(cmd)

			-- normal shell command
			shell:_executeLine(cmd)
			return shell.exitCode == 0
		end,
	}

	-- String / math / table
	sandbox.string = string
	sandbox.math = math
	sandbox.table = table
	sandbox.pairs = pairs
	sandbox.ipairs = ipairs
	sandbox.tostring = tostring
	sandbox.tonumber = tonumber
	sandbox.type = type
	sandbox.pcall = pcall
	sandbox.xpcall = xpcall
	sandbox.error = error
	sandbox.select = select
	sandbox.unpack = table.unpack or unpack
	sandbox.rawget = rawget
	sandbox.rawset = rawset
	sandbox.setmetatable = setmetatable
	sandbox.getmetatable = getmetatable
	sandbox.next = next
	sandbox.ipairs = ipairs
	sandbox.task = task
	sandbox.coroutine = coroutine

	-- Filesystem API (POSIX-like)
	sandbox.fs = {
		read = function(p)
			return vfs:readFileStr(resolvePath(p))
		end,
		write = function(p, s)
			vfs:writeFileStr(resolvePath(p), tostring(s))
			return true
		end,
		append = function(p, s)
			vfs:appendFile(resolvePath(p), shell:_strBytes(tostring(s)))
			return true
		end,
		exists = function(p)
			return vfs:exists(resolvePath(p))
		end,
		ls = function(p)
			return vfs:listDir(resolvePath(p or shell.cwd))
		end,
		mkdir = function(p)
			return vfs:mkdir(resolvePath(p))
		end,
		rm = function(p)
			return vfs:remove(resolvePath(p))
		end,
		stat = function(p)
			return vfs:stat(resolvePath(p))
		end,
		resolve = function(p)
			return resolvePath(p)
		end,
		copy = function(src, dst)
			local sourcePath = resolvePath(src)
			local destPath = resolvePath(dst)
			local data, err = vfs:readFile(sourcePath)
			if not data then
				return false, err
			end
			local st = vfs:stat(destPath)
			if st and st.isDir then
				destPath = destPath .. "/" .. (sourcePath:match("[^/]+$") or sourcePath)
			end
			vfs:writeFile(destPath, data)
			return true, destPath
		end,
		move = function(src, dst)
			local ok, result = sandbox.fs.copy(src, dst)
			if not ok then
				return false, result
			end
			vfs:remove(resolvePath(src))
			return true, result
		end,
		touch = function(p)
			local full = resolvePath(p)
			if not vfs:exists(full) then
				vfs:writeFile(full, {})
			end
			return true, full
		end,
	}

	-- Process API
	sandbox.process = {
		pid = self.kernel.pm and self.kernel.pm._currentPid or 0,
		_pipeInput = self._pipeInput,
		execContext = execContext,

		exit = function(code)
			if shell:isForegroundBusy() then
				shell:endForeground()
			end
			error({ __exit = true, code = code or 0 })
		end,

		env = env,

		cwd = function()
			return shell.cwd
		end,

		list = function()
			return (shell.pm and shell.pm:getProcessList()) or {}
		end,

		user = function()
			return shell.username
		end,

		exec = function(cmd)
			shell:_executeLine(tostring(cmd))
			return shell.exitCode
		end,

		beginForeground = function(name, onInput, onCleanup)
			return shell:beginForeground(name, onInput, onCleanup)
		end,

		endForeground = function()
			shell:endForeground()
		end,

		isForeground = function()
			return shell:isForegroundBusy()
		end,
	}

	sandbox.system = {
		hostname = function(nextName)
			if nextName ~= nil and nextName ~= "" then
				shell.hostname = tostring(nextName)
				kernel._hostname = shell.hostname
				vfs:writeFileStr("/etc/hostname", shell.hostname .. "\n")
			end
			return shell.hostname
		end,
		uptime = function()
			return kernel:getUptime()
		end,
		meminfo = function()
			return (shell.mm and shell.mm:getMemInfo()) or {}
		end,
		diskstats = function()
			return vfs:getDiskStats()
		end,
		pci = function()
			return shell.config.PCI or {}
		end,
		dmesg = function()
			return kernel:getLog()
		end,
		info = function()
			local mi = (shell.mm and shell.mm:getMemInfo()) or {}
			local ds = vfs:getDiskStats()
			return {
				os = shell.config.OS_NAME,
				kernel = shell.config.KERNEL_VERSION,
				hostname = shell.hostname,
				arch = shell.config.ARCH,
				screenW = shell.config.SCREEN_W,
				screenH = shell.config.SCREEN_H,
				ramTotal = mi.total or 0,
				ramFree = mi.free or 0,
				diskTotalBlocks = ds.totalBlocks or 0,
				diskFreeBlocks = ds.freeBlocks or 0,
				uptime = kernel:getUptime(),
			}
		end,
		mounts = function()
			return {
				"/dev/hda1 on / type novafs (rw,relatime)",
				"tmpfs on /tmp type tmpfs (rw)",
				"proc on /proc type proc (rw)",
				"sysfs on /sys type sysfs (rw)",
			}
		end,
	}

	-- Kernel syscall bridge
	sandbox.syscall = function(num, ...)
		if not kernel.syscall then
			return -38
		end
		local pid = kernel.pm and kernel.pm._currentPid or 1
		return kernel.syscall:call(pid, num, ...)
	end

	-- GPU/display
	sandbox.tty = {
		write = function(s, attr)
			gpu:print(tostring(s), attr)
		end,
		writeln = function(s, attr)
			gpu:println(tostring(s), attr)
		end,
		clear = function()
			gpu:clearScreen()
		end,
		cursor = function(col, row)
			gpu:moveCursor(col, row)
		end,
		size = function()
			return shell.config.TEXT_COLS, shell.config.TEXT_ROWS
		end,
		color = function(fg, bg)
			return (bg or 0) * 16 + (fg or 7)
		end,
	}

	-- Pixel GPU API (for graphical apps)
	sandbox.gpu = {
		size = function()
			return gpu.W, gpu.H
		end,
		mode = function(mode)
			gpu:setMode(mode)
		end,
		clear = function(argb)
			gpu:fillRect(0, 0, gpu.W, gpu.H, argb or 0xFF000000)
		end,
		pixel = function(x, y, argb)
			gpu:setPixel(math.floor(x), math.floor(y), argb)
		end,
		line = function(x0, y0, x1, y1, argb)
			gpu:drawLine(math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1), argb)
		end,
		rect = function(x, y, w, h, argb, filled)
			gpu:drawRect(math.floor(x), math.floor(y), math.floor(w), math.floor(h), argb, filled and true or false)
		end,
		text = function(x, y, text, fg, bg)
			gpu:drawText(math.floor(x), math.floor(y), tostring(text), fg or 0xFFFFFFFF, bg or 0x00000000)
		end,
	}

	-- Package manager bridge
	sandbox.pkgmgr = kernel.pkgmgr
			and {
				install = function(name)
					return kernel.pkgmgr:install(name)
				end,
				remove = function(name)
					return kernel.pkgmgr:remove(name)
				end,
				list = function()
					return kernel.pkgmgr:list()
				end,
				search = function(q)
					return kernel.pkgmgr:search(q)
				end,
			}
		or nil

	-- LuauVM re-exposed so scripts can compile/run sub-scripts
	if self.luauvm and self:_getVmConfig().enabled then
		sandbox.luauvm = {
			compile = function(src)
				return self.luauvm.compile(src)
			end,
			load = function(src, isPureBytecode)
				local f, c = self.luauvm(src, isPureBytecode, sandbox, execContext)
				return f, c
			end,
		}
	end

	setmetatable(sandbox, { __index = getfenv(1) })

	return sandbox
end

function Shell:_strBytes(s)
	local b = {}
	for i = 1, #s do
		b[i] = string.byte(s, i)
	end
	return b
end

--  Built-in commands
function Shell:_buildBuiltins()
	local B = {}
	local vfs = function()
		return self.vfs
	end
	local gpu = function()
		return self.gpu
	end
	local out = function(s, a)
		self.gpu:print(tostring(s), a)
	end
	local outln = function(s, a)
		self.gpu:println(tostring(s), a)
	end
	local vmCfg = self:_getVmConfig()

	local function absPath(p)
		if not p or p == "" then
			return self.cwd
		end
		if p:sub(1, 1) == "~" then
			p = (self.env.HOME or "/home/" .. self.username) .. p:sub(2)
		end
		if p:sub(1, 1) ~= "/" then
			p = self.cwd .. "/" .. p
		end
		-- Resolve . and ..
		local parts = {}
		for seg in p:gmatch("[^/]+") do
			if seg == ".." then
				table.remove(parts)
			elseif seg ~= "." then
				table.insert(parts, seg)
			end
		end
		return "/" .. table.concat(parts, "/")
	end

	-- cd
	B["cd"] = function(args)
		local path = absPath(args[2] or self.env.HOME or "/")
		if args[2] == "-" then
			path = self.env.OLDPWD or "/"
		end
		if not vfs():exists(path) then
			outln("cd: no such directory: " .. path, 0x0C)
			return 1
		end
		local st = vfs():stat(path)
		if not st or not st.isDir then
			outln("cd: not a directory: " .. path, 0x0C)
			return 1
		end
		self.env.OLDPWD = self.cwd
		self.cwd = path
		return 0
	end

	-- pwd
	B["pwd"] = function()
		outln(self.cwd)
		return 0
	end

	-- ls
	B["ls"] = function(args)
		local flags = {}
		local paths = {}
		for i = 2, #args do
			if args[i]:sub(1, 1) == "-" then
				for j = 2, #args[i] do
					flags[args[i]:sub(j, j)] = true
				end
			else
				table.insert(paths, args[i])
			end
		end
		if #paths == 0 then
			paths = { self.cwd }
		end
		for _, p in ipairs(paths) do
			local dir = absPath(p)
			local entries = vfs():listDir(dir)
			if not entries then
				outln("ls: cannot access '" .. p .. "': No such file or directory", 0x0C)
				return 1
			end
			if #paths > 1 then
				outln(dir .. ":")
			end
			-- Sort
			table.sort(entries, function(a, b)
				return a.name < b.name
			end)
			if flags["a"] then
				-- include . and ..
				local stat = vfs():stat(dir)
				local pdir = dir:match("^(.*)/") or "/"
				table.insert(entries, 1, { name = "..", isDir = true, size = 0, mtime = 0, mode = 0x41ED })
				table.insert(entries, 1, { name = ".", isDir = true, size = 0, mtime = 0, mode = 0x41ED })
			end
			if flags["l"] then
				-- long listing
				outln(string.format("total %d", #entries))
				for _, e in ipairs(entries) do
					if not flags["a"] and e.name:sub(1, 1) == "." then
						continue
					end
					local perm = e.isDir and "drwxr-xr-x" or "-rw-r--r--"
					local sz = string.format("%8d", e.size)
					local date = os.date("%b %d %H:%M", e.mtime > 0 and e.mtime or os.time())
					local col = e.isDir and 0x0B or 0x07
					outln(string.format("%s  1 root root %s %s %s", perm, sz, date, e.name), col)
				end
			else
				-- short listing in columns
				local names = {}
				for _, e in ipairs(entries) do
					if not flags["a"] and e.name:sub(1, 1) == "." then
						-- skip hidden unless -a
					else
						local col = e.isDir and 0x0B or 0x07
						table.insert(names, { name = e.name, col = col, isDir = e.isDir })
					end
				end
				local colWidth = 18
				local cols = math.floor(self.config.TEXT_COLS / colWidth)
				local row = {}
				for i, n in ipairs(names) do
					local display = n.name .. (n.isDir and "/" or "")
					local padded = string.format("%-" .. colWidth .. "s", display:sub(1, colWidth - 1))
					table.insert(row, { text = padded, col = n.col })
					if #row >= cols then
						for _, r in ipairs(row) do
							out(r.text, r.col)
						end
						outln("")
						row = {}
					end
				end
				if #row > 0 then
					for _, r in ipairs(row) do
						out(r.text, r.col)
					end
					outln("")
				end
			end
		end
		return 0
	end

	-- cat
	B["cat"] = function(args)
		if #args < 2 then
			-- read from pipe/stdin
			if self._pipeInput then
				out(self._pipeInput)
			end
			return 0
		end
		for i = 2, #args do
			local p = absPath(args[i])
			local s, err = vfs():readFileStr(p)
			if not s then
				outln("cat: " .. args[i] .. ": " .. tostring(err), 0x0C)
				return 1
			end
			out(s)
		end
		return 0
	end

	-- echo
	B["echo"] = function(args)
		local parts = {}
		local newline = true
		for i = 2, #args do
			if args[i] == "-n" then
				newline = false
			else
				table.insert(parts, args[i])
			end
		end
		local s = table.concat(parts, " ")
		-- Interpret escape sequences
		s = s:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\033%[(%d+)m", "")
		if newline then
			outln(s)
		else
			out(s)
		end
		return 0
	end

	-- mkdir
	B["mkdir"] = function(args)
		for i = 2, #args do
			local p = absPath(args[i])
			local ok, err = vfs():mkdir(p)
			if not ok then
				outln("mkdir: cannot create directory '" .. args[i] .. "': " .. tostring(err), 0x0C)
				return 1
			end
		end
		return 0
	end

	-- rm
	B["rm"] = function(args)
		local flags = {}
		local paths = {}
		for i = 2, #args do
			if args[i]:sub(1, 1) == "-" then
				for j = 2, #args[i] do
					flags[args[i]:sub(j, j)] = true
				end
			else
				table.insert(paths, args[i])
			end
		end
		for _, p in ipairs(paths) do
			local full = absPath(p)
			local st = vfs():stat(full)
			if not st then
				outln("rm: cannot remove '" .. p .. "': No such file or directory", 0x0C)
				return 1
			end
			if st.isDir and not flags["r"] then
				outln("rm: cannot remove '" .. p .. "': Is a directory", 0x0C)
				return 1
			end
			vfs():remove(full)
		end
		return 0
	end

	-- cp
	B["cp"] = function(args)
		if #args < 3 then
			outln("usage: cp <src> <dst>", 0x0C)
			return 1
		end
		local src = absPath(args[2])
		local dst = absPath(args[3])
		local data, err = vfs():readFile(src)
		if not data then
			outln("cp: cannot read " .. args[2] .. ": " .. tostring(err), 0x0C)
			return 1
		end
		-- If dst is a directory, copy into it
		local st = vfs():stat(dst)
		if st and st.isDir then
			dst = dst .. "/" .. (src:match("[^/]+$") or src)
		end
		vfs():writeFile(dst, data)
		return 0
	end

	-- mv
	B["mv"] = function(args)
		if #args < 3 then
			outln("usage: mv <src> <dst>", 0x0C)
			return 1
		end
		local src = absPath(args[2])
		local dst = absPath(args[3])
		local st = vfs():stat(dst)
		if st and st.isDir then
			dst = dst .. "/" .. (src:match("[^/]+$") or src)
		end
		local data, err = vfs():readFile(src)
		if not data then
			outln("mv: cannot read " .. args[2] .. ": " .. tostring(err), 0x0C)
			return 1
		end
		vfs():writeFile(dst, data)
		vfs():remove(src)
		return 0
	end

	-- touch
	B["touch"] = function(args)
		for i = 2, #args do
			local p = absPath(args[i])
			if not vfs():exists(p) then
				vfs():writeFile(p, {})
			end
		end
		return 0
	end

	-- head
	B["head"] = function(args)
		local n = 10
		local paths = {}
		for i = 2, #args do
			if args[i] == "-n" and args[i + 1] then
				n = tonumber(args[i + 1]) or 10
			elseif not args[i]:match("^%d+$") or args[i - 1] ~= "-n" then
				table.insert(paths, args[i])
			end
		end
		local function doHead(content)
			local count = 0
			for line in (content .. "\n"):gmatch("([^\n]*)\n") do
				if count >= n then
					break
				end
				outln(line)
				count = count + 1
			end
		end
		if #paths == 0 then
			if self._pipeInput then
				doHead(self._pipeInput)
			end
		else
			for _, p in ipairs(paths) do
				local s, err = vfs():readFileStr(absPath(p))
				if s then
					doHead(s)
				else
					outln("head: " .. p .. ": " .. tostring(err), 0x0C)
					return 1
				end
			end
		end
		return 0
	end

	-- tail
	B["tail"] = function(args)
		local n = 10
		local paths = {}
		for i = 2, #args do
			if args[i] == "-n" and args[i + 1] then
				n = tonumber(args[i + 1]) or 10
			elseif args[i - 1] ~= "-n" then
				table.insert(paths, args[i])
			end
		end
		local function doTail(content)
			local lines = {}
			for l in (content .. "\n"):gmatch("([^\n]*)\n") do
				table.insert(lines, l)
			end
			local start = math.max(1, #lines - n + 1)
			for i = start, #lines do
				outln(lines[i])
			end
		end
		if #paths == 0 then
			if self._pipeInput then
				doTail(self._pipeInput)
			end
		else
			for _, p in ipairs(paths) do
				local s, err = vfs():readFileStr(absPath(p))
				if s then
					doTail(s)
				else
					outln("tail: " .. p .. ": " .. tostring(err), 0x0C)
					return 1
				end
			end
		end
		return 0
	end

	-- grep
	B["grep"] = function(args)
		local flags = {}
		local pattern, paths = nil, {}
		for i = 2, #args do
			if args[i]:sub(1, 1) == "-" then
				for j = 2, #args[i] do
					flags[args[i]:sub(j, j)] = true
				end
			elseif not pattern then
				pattern = args[i]
			else
				table.insert(paths, args[i])
			end
		end
		if not pattern then
			outln("usage: grep <pattern> [file...]", 0x0C)
			return 1
		end
		local function doGrep(content, label)
			local lineNum = 0
			for line in (content .. "\n"):gmatch("([^\n]*)\n") do
				lineNum = lineNum + 1
				local match = flags["i"] and line:lower():find(pattern:lower()) or line:find(pattern)
				if match then
					local prefix = flags["n"] and (lineNum .. ":") or ""
					if label then
						prefix = label .. ":" .. prefix
					end
					outln(prefix .. line, 0x0A)
				end
			end
		end
		if #paths == 0 then
			if self._pipeInput then
				doGrep(self._pipeInput)
			end
		else
			for _, p in ipairs(paths) do
				local s = vfs():readFileStr(absPath(p))
				if s then
					doGrep(s, #paths > 1 and p or nil)
				end
			end
		end
		return 0
	end

	-- wc
	B["wc"] = function(args)
		local function doWC(content, name)
			local lines = 0
			local words = 0
			local bytes = #content
			for l in (content .. "\n"):gmatch("([^\n]*)\n") do
				lines = lines + 1
				for _ in l:gmatch("%S+") do
					words = words + 1
				end
			end
			outln(string.format("%7d %7d %7d%s", lines, words, bytes, name and (" " .. name) or ""))
		end
		if #args < 2 then
			if self._pipeInput then
				doWC(self._pipeInput)
			end
		else
			for i = 2, #args do
				local s = vfs():readFileStr(absPath(args[i]))
				if s then
					doWC(s, args[i])
				else
					outln("wc: " .. args[i] .. ": not found", 0x0C)
				end
			end
		end
		return 0
	end

	-- sort
	B["sort"] = function(args)
		local content = self._pipeInput or ""
		if args[2] then
			content = vfs():readFileStr(absPath(args[2])) or ""
		end
		local lines = {}
		for l in (content .. "\n"):gmatch("([^\n]*)\n") do
			table.insert(lines, l)
		end
		table.sort(lines)
		for _, l in ipairs(lines) do
			outln(l)
		end
		return 0
	end

	-- uniq
	B["uniq"] = function(args)
		local content = self._pipeInput or ""
		if args[2] then
			content = vfs():readFileStr(absPath(args[2])) or ""
		end
		local prev = nil
		for l in (content .. "\n"):gmatch("([^\n]*)\n") do
			if l ~= prev then
				outln(l)
				prev = l
			end
		end
		return 0
	end

	-- cut
	B["cut"] = function(args)
		local delim = "\t"
		local fields = nil
		for i = 2, #args do
			if args[i] == "-d" then
				delim = args[i + 1] or "\t"
			elseif args[i] == "-f" then
				fields = {}
				for f in (args[i + 1] or "1"):gmatch("%d+") do
					table.insert(fields, tonumber(f))
				end
			end
		end
		local content = self._pipeInput or ""
		for line in (content .. "\n"):gmatch("([^\n]*)\n") do
			if fields then
				local parts = {}
				local j = 0
				for seg in (line .. delim):gmatch("(.-)" .. delim:gsub("([%.%+%-%*%?%[%]%(%)%^%$%%])", "%%%1")) do
					j = j + 1
					for _, f in ipairs(fields) do
						if f == j then
							table.insert(parts, seg)
						end
					end
				end
				outln(table.concat(parts, delim))
			else
				outln(line)
			end
		end
		return 0
	end

	-- ps
	-- kill
	B["kill"] = function(args)
		local sig = 15
		local pids = {}
		for i = 2, #args do
			if args[i]:sub(1, 1) == "-" then
				local n = tonumber(args[i]:sub(2))
				if n then
					sig = n
				else
					local smap = { KILL = 9, TERM = 15, HUP = 1, INT = 2, QUIT = 3, STOP = 19, CONT = 18 }
					sig = smap[args[i]:sub(2)] or sig
				end
			else
				table.insert(pids, tonumber(args[i]))
			end
		end
		for _, pid in ipairs(pids) do
			if self.pm then
				self.pm:sendSignal(pid, sig)
			end
		end
		return 0
	end

	-- top (one-shot snapshot)
	B["top"] = function(args)
		local mi = self.mm and self.mm:getMemInfo() or {}
		local procs = self.pm and self.pm:getProcessList() or {}
		outln(
			string.format("top - %s  up %.0fs  %d processes", os.date("%H:%M:%S"), self.kernel:getUptime(), #procs),
			0x0B
		)
		outln(
			string.format(
				"Mem: %dkB total  %dkB free  %dkB used",
				math.floor((mi.total or 0) / 1024),
				math.floor((mi.free or 0) / 1024),
				math.floor((mi.used or 0) / 1024)
			),
			0x07
		)
		outln("")
		local psPath = self:_resolveExecutablePath("ps")
		local vmCfg = self:_getVmConfig()
		if vmCfg.enabled and psPath then
			local ok, rc = pcall(function()
				return self:_runExternal(psPath, { "ps" }, { cmd = "ps", args = { "ps" } })
			end)
			if ok and rc == 0 then
				return 0
			end
		end

		local fallbackProcs = self.pm and self.pm:getProcessList() or {}
		outln(
			string.format(
				"  %-6s %-6s %-4s %-10s %-5s %-6s %s",
				"PID",
				"PPID",
				"PRI",
				"STATE",
				"CPU%",
				"MEM",
				"COMMAND"
			),
			0x0B
		)
		for _, p in ipairs(fallbackProcs) do
			local stateCol = p.state == "R" and 0x0A or p.state == "Z" and 0x0C or 0x07
			outln(
				string.format(
					"  %-6d %-6d %-4d %-10s %-5.1f %-6dK %s",
					p.pid,
					p.ppid,
					p.pri,
					p.state,
					p.cpu,
					p.mem,
					p.name
				),
				stateCol
			)
		end
		return 0
	end

	-- uname
	B["uname"] = function(args)
		local flags = {}
		for i = 2, #args do
			if args[i]:sub(1, 1) == "-" then
				for j = 2, #args[i] do
					flags[args[i]:sub(j, j)] = true
				end
			end
		end
		if flags["a"] then
			outln(
				string.format(
					"%s %s %s #1 SMP %s %s",
					self.config.OS_NAME,
					self.config.HOSTNAME,
					self.config.KERNEL_VERSION,
					os.date("%Y-%m-%d"),
					self.config.ARCH
				)
			)
		elseif flags["r"] then
			outln(self.config.KERNEL_VERSION)
		elseif flags["m"] then
			outln(self.config.ARCH)
		elseif flags["n"] then
			outln(self.config.HOSTNAME)
		else
			outln(self.config.OS_NAME)
		end
		return 0
	end

	-- whoami / id
	B["whoami"] = function()
		outln(self.username)
		return 0
	end
	B["id"] = function()
		local uid = self.username == "root" and 0 or 1000
		outln(
			string.format(
				"uid=%d(%s) gid=%d(%s) groups=%d(%s)",
				uid,
				self.username,
				uid,
				self.username,
				uid,
				self.username
			)
		)
		return 0
	end

	-- hostname
	B["hostname"] = function(args)
		if args[2] then
			self.hostname = args[2]
			self.kernel._hostname = args[2]
			vfs():writeFileStr("/etc/hostname", args[2] .. "\n")
		else
			outln(self.hostname)
		end
		return 0
	end

	-- date
	B["date"] = function(args)
		local fmt = args[2] and args[2]:gsub("^%+", "") or "%a %b %d %H:%M:%S %Z %Y"
		outln(os.date(fmt))
		return 0
	end

	-- uptime
	B["uptime"] = function()
		local u = self.kernel:getUptime()
		local h = math.floor(u / 3600)
		local m = math.floor((u % 3600) / 60)
		local s = math.floor(u % 60)
		local procs = self.pm and #self.pm:getProcessList() or 0
		outln(
			string.format(
				" %s  up %02d:%02d:%02d,  1 user,  load average: 0.00, 0.00, 0.00 (%d procs)",
				os.date("%H:%M:%S"),
				h,
				m,
				s,
				procs
			)
		)
		return 0
	end

	-- free
	B["free"] = function(args)
		local mi = self.mm and self.mm:getMemInfo() or {}
		local function kb(n)
			return math.floor((n or 0) / 1024)
		end
		outln(string.format("%-16s%8s%8s%8s", "              ", "total", "used", "free"), 0x0B)
		outln(string.format("%-16s%8d%8d%8d", "Mem:", kb(mi.total), kb(mi.used), kb(mi.free)))
		outln(string.format("%-16s%8d%8d%8d", "Swap:", 0, 0, 0))
		return 0
	end

	-- df
	B["df"] = function()
		local ds = vfs():getDiskStats()
		outln(
			string.format(
				"%-20s%10s%10s%10s%6s %s",
				"Filesystem",
				"1K-blocks",
				"Used",
				"Available",
				"Use%",
				"Mounted on"
			),
			0x0B
		)
		local total = (ds.totalBlocks or 0) * 512 / 1024
		local used = (ds.usedBlocks or 0) * 512 / 1024
		local free = (ds.freeBlocks or 0) * 512 / 1024
		local pct = total > 0 and math.floor(used / total * 100) or 0
		outln(
			string.format(
				"%-20s%10d%10d%10d%5d%% %s",
				"/dev/hda1",
				math.floor(total),
				math.floor(used),
				math.floor(free),
				pct,
				"/"
			)
		)
		return 0
	end

	-- env / export / unset
	B["env"] = function()
		local keys = {}
		for k in pairs(self.env) do
			table.insert(keys, k)
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			outln(k .. "=" .. tostring(self.env[k]))
		end
		return 0
	end
	B["export"] = function(args)
		for i = 2, #args do
			local k, v = args[i]:match("^([%w_]+)=(.*)$")
			if k then
				self.env[k] = v
			else
				self.env[args[i]] = self.env[args[i]] or ""
			end
		end
		return 0
	end
	B["unset"] = function(args)
		for i = 2, #args do
			self.env[args[i]] = nil
		end
		return 0
	end

	-- alias / unalias
	B["alias"] = function(args)
		if #args < 2 then
			for k, v in pairs(self._aliases) do
				outln(string.format("alias %s='%s'", k, v))
			end
		else
			for i = 2, #args do
				local k, v = args[i]:match("^([%w_%.%-]+)=(.*)$")
				if k then
					self._aliases[k] = v:gsub("^'(.-)'$", "%1")
				end
			end
		end
		return 0
	end
	B["unalias"] = function(args)
		for i = 2, #args do
			self._aliases[args[i]] = nil
		end
		return 0
	end

	-- history
	B["history"] = function(args)
		local n = tonumber(args[2]) or #self._history
		for i = math.max(1, #self._history - n + 1), #self._history do
			outln(string.format("  %4d  %s", i, self._history[i]))
		end
		return 0
	end

	-- which
	B["which"] = function(args)
		if not args[2] then
			return 1
		end
		local spec = self:_classifyCommand(args[2])
		if spec.kind == "builtin" then
			outln(args[2] .. ": shell built-in")
			return 0
		end
		if spec.kind == "external" then
			outln(spec.path)
			return 0
		end
		outln(args[2] .. " not found", 0x0C)
		return 1
	end

	-- type
	B["type"] = function(args)
		if #args < 2 then
			outln("usage: type <command> [...]", 0x07)
			return 1
		end
		local rc = 0
		for i = 2, #args do
			local name = args[i]
			local spec = self:_classifyCommand(name)
			if spec.kind == "builtin" then
				outln(name .. " is a shell built-in")
			elseif spec.kind == "external" then
				outln(name .. " is " .. spec.path)
			else
				outln(name .. ": not found", 0x0C)
				rc = 1
			end
		end
		return rc
	end

	-- find
	B["find"] = function(args)
		local root = absPath(args[2] or ".")
		local name = nil
		local type_ = nil
		for i = 2, #args do
			if args[i] == "-name" then
				name = args[i + 1]
			elseif args[i] == "-type" then
				type_ = args[i + 1]
			end
		end
		local function walk(dir)
			local entries = vfs():listDir(dir)
			if not entries then
				return
			end
			for _, e in ipairs(entries) do
				local full = dir == "/" and ("/" .. e.name) or (dir .. "/" .. e.name)
				local match = true
				if name and not e.name:match(name:gsub("%*", ".*"):gsub("%?", ".")) then
					match = false
				end
				if type_ == "f" and e.isDir then
					match = false
				end
				if type_ == "d" and not e.isDir then
					match = false
				end
				if match then
					outln(full)
				end
				if e.isDir then
					walk(full)
				end
			end
		end
		walk(root)
		return 0
	end

	-- printf
	B["printf"] = function(args)
		if not args[2] then
			return 0
		end
		local fmt = args[2]:gsub("\\n", "\n"):gsub("\\t", "\t")
		local fmtArgs = {}
		for i = 3, #args do
			table.insert(fmtArgs, tonumber(args[i]) or args[i])
		end
		local ok, result = pcall(string.format, fmt, table.unpack(fmtArgs))
		if ok then
			out(result)
		end
		return 0
	end

	-- true / false
	B["true"] = function()
		return 0
	end
	B["false"] = function()
		return 1
	end

	-- test / [
	B["test"] = function(args)
		if #args < 2 then
			return 1
		end
		local a, op, b = args[2], args[3], args[4]
		if op == "=" or op == "==" then
			return a == b and 0 or 1
		elseif op == "!=" then
			return a ~= b and 0 or 1
		elseif op == "-eq" then
			return tonumber(a) == tonumber(b) and 0 or 1
		elseif op == "-ne" then
			return tonumber(a) ~= tonumber(b) and 0 or 1
		elseif op == "-lt" then
			return (tonumber(a) or 0) < (tonumber(b) or 0) and 0 or 1
		elseif op == "-gt" then
			return (tonumber(a) or 0) > (tonumber(b) or 0) and 0 or 1
		elseif op == "-le" then
			return (tonumber(a) or 0) <= (tonumber(b) or 0) and 0 or 1
		elseif op == "-ge" then
			return (tonumber(a) or 0) >= (tonumber(b) or 0) and 0 or 1
		elseif a == "-f" then
			return vfs():exists(b or a) and not (vfs():stat(b or a) or {}).isDir and 0 or 1
		elseif a == "-d" then
			local st = vfs():stat(b or a)
			return (st and st.isDir) and 0 or 1
		elseif a == "-e" then
			return vfs():exists(b or a) and 0 or 1
		elseif a == "-z" then
			return (b == nil or b == "") and 0 or 1
		elseif a == "-n" then
			return (b and b ~= "") and 0 or 1
		else
			return 1
		end
	end
	B["["] = B["test"]

	-- xargs (simple)
	B["xargs"] = function(args)
		if not self._pipeInput then
			return 0
		end
		local cmd = args[2] or "echo"
		for line in (self._pipeInput .. "\n"):gmatch("([^\n]+)") do
			self:_executeLine(cmd .. " " .. line)
		end
		return 0
	end

	-- tee
	B["tee"] = function(args)
		local content = self._pipeInput or ""
		if args[2] then
			vfs():writeFileStr(absPath(args[2]), content)
		end
		out(content)
		return 0
	end

	-- write / read (shell scripting)
	B["read"] = function(args)
		local varname = args[2] or "REPLY"
		-- Non-blocking: return empty string if no input
		local ch = self.keyboard and self.keyboard:readChar()
		self.env[varname] = ch or ""
		return 0
	end

	-- exec (replace shell with command - just runs it here)
	B["exec"] = function(args)
		if #args < 2 then
			return 0
		end
		local newArgs = {}
		for i = 2, #args do
			table.insert(newArgs, args[i])
		end
		return self:_execFromPath(newArgs[1], newArgs, {}) or 1
	end

	-- source / .
	B["source"] = function(args)
		local path = absPath(args[2] or "")
		if not vfs():exists(path) then
			outln("source: " .. (args[2] or "") .. ": not found", 0x0C)
			return 1
		end
		local content = vfs():readFileStr(path) or ""
		for line in (content .. "\n"):gmatch("([^\n]+)") do
			local l = line:match("^%s*(.-)%s*$")
			if l ~= "" and l:sub(1, 1) ~= "#" then
				self:_executeLine(l)
			end
		end
		return self.exitCode
	end
	B["."] = B["source"]

	-- sh (start a subshell or run a script)
	B["sh"] = function(args)
		if args[2] then
			return self:_runScript(absPath(args[2]), args, {}) or 0
		end
		outln("nsh: interactive subshell not supported in this context", 0x0E)
		return 0
	end

	-- eval
	B["eval"] = function(args)
		local parts = {}
		for i = 2, #args do
			table.insert(parts, args[i])
		end
		self:_executeLine(table.concat(parts, " "))
		return self.exitCode
	end

	-- clear
	B["clear"] = function()
		self.gpu:clearScreen()
		return 0
	end

	-- sleep
	B["sleep"] = function(args)
		local secs = tonumber(args[2]) or 1
		local deadline = os.clock() + secs
		-- Busy-wait (acceptable for small durations in Roblox)
		while os.clock() < deadline do
		end
		return 0
	end

	-- yes
	B["yes"] = function(args)
		local s = args[2] or "y"
		-- Print 20 lines then stop (prevent hang)
		for i = 1, 20 do
			outln(s)
		end
		return 0
	end

	-- nano / vi (full-screen text editor)
	B["nano"] = function(args)
		if not args[2] then
			outln("usage: nano <file>", 0x0C)
			return 1
		end

		local path = absPath(args[2])
		local fileName = args[2]
		local ext = fileName:match("%.([%w_%-]+)$") or ""
		local isLuau = (ext == "luau") or (ext == "lua")
		local content = vfs():readFileStr(path) or ""
		local lines = {}
		for l in (content .. "\n"):gmatch("([^\n]*)\n") do
			table.insert(lines, l)
		end
		if #lines == 0 then
			lines = { "" }
		end

		local cursorRow, cursorCol = 1, 0
		local scrollRow = 1
		local scrollCol = 0
		local modified = false
		local status = "^G Help  ^O WriteOut  ^W Where Is  ^K Cut Text  ^X Exit"
		local statusAttr = 0x08
		local cols = self.config.TEXT_COLS
		local rows = self.config.TEXT_ROWS
		local topRow = 1
		local bodyRows = rows - 4
		local gutter = 6
		local textStart = gutter
		local textWidth = math.max(8, cols - textStart)
		local clipboardLine = nil
		local promptMode = nil
		local promptBuffer = ""

		local luauKeywords = {
			["and"] = true,
			["break"] = true,
			["do"] = true,
			["else"] = true,
			["elseif"] = true,
			["end"] = true,
			["false"] = true,
			["for"] = true,
			["function"] = true,
			["if"] = true,
			["in"] = true,
			["local"] = true,
			["nil"] = true,
			["not"] = true,
			["or"] = true,
			["repeat"] = true,
			["return"] = true,
			["then"] = true,
			["true"] = true,
			["until"] = true,
			["while"] = true,
			["continue"] = true,
			["type"] = true,
			["typeof"] = true,
			["export"] = true,
		}

		local function ensureLine()
			if cursorRow < 1 then
				cursorRow = 1
			end
			if cursorRow > #lines then
				cursorRow = #lines
			end
			local line = lines[cursorRow] or ""
			if cursorCol < 0 then
				cursorCol = 0
			end
			if cursorCol > #line then
				cursorCol = #line
			end
		end

		local function setStatus(msg, attr)
			status = msg
			statusAttr = attr or 0x08
		end

		local function tokenizeLuau(line)
			local tokens = {}
			local i = 1
			while i <= #line do
				local c = line:sub(i, i)
				local n = line:sub(i + 1, i + 1)
				if c == "-" and n == "-" then
					table.insert(tokens, { text = line:sub(i), attr = 0x02 })
					break
				elseif c == '"' or c == "'" then
					local q = c
					local j = i + 1
					while j <= #line do
						if line:sub(j, j) == "\\" then
							j = j + 2
						elseif line:sub(j, j) == q then
							j = j + 1
							break
						else
							j = j + 1
						end
					end
					table.insert(tokens, { text = line:sub(i, j - 1), attr = 0x0E }) -- strings
					i = j
				elseif c == "[" and n == "[" then
					local closePos = line:find("]%]", i + 2, false)
					local j = closePos and (closePos + 2) or (#line + 1)
					table.insert(tokens, { text = line:sub(i, j - 1), attr = 0x0E })
					i = j
				elseif c:match("[%a_]") then
					local j = i + 1
					while j <= #line and line:sub(j, j):match("[%w_]") do
						j = j + 1
					end
					local word = line:sub(i, j - 1)
					if luauKeywords[word] then
						table.insert(tokens, { text = word, attr = 0x0B })
					elseif word == "self" then
						table.insert(tokens, { text = word, attr = 0x0A })
					else
						table.insert(tokens, { text = word, attr = 0x07 })
					end
					i = j
				elseif c:match("%d") then
					local j = i + 1
					while j <= #line and line:sub(j, j):match("[%d%.xXa-fA-F]") do
						j = j + 1
					end
					table.insert(tokens, { text = line:sub(i, j - 1), attr = 0x0D })
					i = j
				elseif c:match("[%+%-%*%/%=<>~%%%^#:,%.%(%)%[%]{}]") then
					table.insert(tokens, { text = c, attr = 0x0C })
					i = i + 1
				else
					table.insert(tokens, { text = c, attr = 0x07 })
					i = i + 1
				end
			end
			return tokens
		end

		local function writeAt(col, row, str, attr)
			for i = 1, #str do
				self.gpu:putChar(col + i - 1, row, string.byte(str, i), attr)
			end
		end

		local function clearRow(row, attr)
			for col = 0, cols - 1 do
				self.gpu:putChar(col, row, 32, attr)
			end
		end

		local function render()
			ensureLine()
			if cursorRow < scrollRow then
				scrollRow = cursorRow
			elseif cursorRow >= scrollRow + bodyRows then
				scrollRow = cursorRow - bodyRows + 1
			end
			if cursorCol < scrollCol then
				scrollCol = cursorCol
			elseif cursorCol >= scrollCol + textWidth then
				scrollCol = cursorCol - textWidth + 1
			end
			if scrollRow < 1 then
				scrollRow = 1
			end
			if scrollCol < 0 then
				scrollCol = 0
			end

			clearRow(0, 0x71)
			local title = string.format(" GNU nano - Nova IDE | %s%s", fileName, modified and " [Modified]" or "")
			writeAt(0, 0, title:sub(1, cols), 0x71)

			for r = 0, bodyRows - 1 do
				local row = topRow + r
				local lineIndex = scrollRow + r
				clearRow(row, 0x00)
				if lineIndex <= #lines then
					local ln = string.format("%4d ", lineIndex)
					writeAt(0, row, ln, 0x08)
					local contentLine = lines[lineIndex] or ""
					local visibleLine = contentLine:sub(scrollCol + 1)
					if isLuau then
						local col = textStart
						for _, token in ipairs(tokenizeLuau(visibleLine)) do
							if col >= cols then
								break
							end
							local text = token.text
							if col + #text > cols then
								text = text:sub(1, cols - col)
							end
							if #text > 0 then
								writeAt(col, row, text, token.attr)
								col = col + #text
							end
						end
					else
						writeAt(textStart, row, visibleLine:sub(1, textWidth), 0x07)
					end
				end
			end

			clearRow(rows - 3, 0x01)
			local location = string.format(" Ln %d, Col %d ", cursorRow, cursorCol + 1)
			writeAt(0, rows - 3, location:sub(1, cols), 0x01)
			if status and status ~= "" then
				clearRow(rows - 2, 0x30)
				writeAt(0, rows - 2, status:sub(1, cols), statusAttr)
			end

			clearRow(rows - 1, 0x30)
			local shortcuts = "^X Exit  ^O WriteOut  ^W Search  ^K Cut  ^U Paste  ^G Goto"
			writeAt(0, rows - 1, shortcuts:sub(1, cols), 0x30)

			if promptMode then
				local promptText = (promptMode == "search" and "Search: " or "Goto line: ") .. promptBuffer
				clearRow(rows - 2, 0x00)
				writeAt(0, rows - 2, promptText:sub(1, cols), 0x0B)
			end

			local cursorScreenRow = topRow + (cursorRow - scrollRow)
			local cursorScreenCol = textStart + (cursorCol - scrollCol)
			if cursorScreenRow < topRow then
				cursorScreenRow = topRow
			end
			if cursorScreenRow > topRow + bodyRows - 1 then
				cursorScreenRow = topRow + bodyRows - 1
			end
			if cursorScreenCol >= cols then
				cursorScreenCol = cols - 1
			end
			self.gpu:moveCursor(cursorScreenCol, cursorScreenRow)
		end

		local function saveFile()
			local text = table.concat(lines, "\n")
			vfs():writeFileStr(path, text)
			modified = false
			setStatus(string.format("Wrote %d lines to %s", #lines, fileName), 0x0A)
		end

		local CTRL_X = string.char(24)
		local CTRL_O = string.char(15)
		local CTRL_S = string.char(19)
		local CTRL_K = string.char(11)
		local CTRL_U = string.char(21)
		local CTRL_W = string.char(23)
		local CTRL_G = string.char(7)
		local CTRL_Q = string.char(17)

		local function findNext(term)
			if term == "" then
				return false
			end
			for r = cursorRow, #lines do
				local line = lines[r] or ""
				local startCol = (r == cursorRow and (cursorCol + 2) or 1)
				local at = line:find(term, startCol, true)
				if at then
					cursorRow = r
					cursorCol = at - 1
					return true
				end
			end
			for r = 1, cursorRow do
				local line = lines[r] or ""
				local at = line:find(term, 1, true)
				if at then
					cursorRow = r
					cursorCol = at - 1
					return true
				end
			end
			return false
		end

		local function handleInput(ch)
			if promptMode then
				if ch == "\n" or ch == "\r" then
					if promptMode == "search" then
						if findNext(promptBuffer) then
							setStatus("Found: " .. promptBuffer, 0x0A)
						else
							setStatus("Not found: " .. promptBuffer, 0x0C)
						end
					else
						local ln = tonumber(promptBuffer)
						if ln then
							cursorRow = math.clamp(math.floor(ln), 1, #lines)
							cursorCol = math.min(cursorCol, #(lines[cursorRow] or ""))
							setStatus(string.format("Moved to line %d", cursorRow), 0x0A)
						else
							setStatus("Invalid line number", 0x0C)
						end
					end
					promptMode = nil
					promptBuffer = ""
					render()
					return
				elseif ch == "\27" or ch == CTRL_X then
					promptMode = nil
					promptBuffer = ""
					setStatus("Canceled", 0x08)
					render()
					return
				elseif ch == "\b" then
					promptBuffer = promptBuffer:sub(1, -2)
					render()
					return
				elseif #ch == 1 and string.byte(ch) >= 32 and string.byte(ch) <= 126 then
					promptBuffer = promptBuffer .. ch
					render()
					return
				end
			end

			if ch == CTRL_X then
				if modified then
					setStatus("Unsaved changes. Use Ctrl+O to save or Ctrl+Q to force quit.", 0x0C)
					render()
					return
				end
				self.gpu:clearScreen()
				self:endForeground()
				return
			elseif ch == CTRL_Q then
				self.gpu:clearScreen()
				self:endForeground()
				return
			elseif ch == CTRL_O or ch == CTRL_S then
				saveFile()
				render()
				return
			elseif ch == CTRL_K then
				clipboardLine = lines[cursorRow] or ""
				table.remove(lines, cursorRow)
				if #lines == 0 then
					lines = { "" }
					cursorRow = 1
					cursorCol = 0
				else
					if cursorRow > #lines then
						cursorRow = #lines
					end
					cursorCol = math.min(cursorCol, #(lines[cursorRow] or ""))
				end
				modified = true
				setStatus("Cut current line", 0x08)
				render()
				return
			elseif ch == CTRL_U then
				if clipboardLine then
					table.insert(lines, cursorRow + 1, clipboardLine)
					cursorRow = cursorRow + 1
					cursorCol = 0
					modified = true
					setStatus("Pasted line", 0x0A)
				else
					setStatus("Clipboard empty", 0x08)
				end
				render()
				return
			elseif ch == CTRL_W then
				promptMode = "search"
				promptBuffer = ""
				render()
				return
			elseif ch == CTRL_G then
				promptMode = "goto"
				promptBuffer = tostring(cursorRow)
				render()
				return
			end

			if ch == "[UP]" then
				cursorRow = cursorRow - 1
			elseif ch == "[DOWN]" then
				cursorRow = cursorRow + 1
			elseif ch == "[LEFT]" then
				if cursorCol > 0 then
					cursorCol = cursorCol - 1
				elseif cursorRow > 1 then
					cursorRow = cursorRow - 1
					cursorCol = #(lines[cursorRow] or "")
				end
			elseif ch == "[RIGHT]" then
				local line = lines[cursorRow] or ""
				if cursorCol < #line then
					cursorCol = cursorCol + 1
				elseif cursorRow < #lines then
					cursorRow = cursorRow + 1
					cursorCol = 0
				end
			elseif ch == "[HOME]" then
				cursorCol = 0
			elseif ch == "[END]" then
				cursorCol = #(lines[cursorRow] or "")
			elseif ch == "\n" or ch == "\r" then
				local line = lines[cursorRow] or ""
				local left = line:sub(1, cursorCol)
				local right = line:sub(cursorCol + 1)
				lines[cursorRow] = left
				table.insert(lines, cursorRow + 1, right)
				cursorRow = cursorRow + 1
				cursorCol = 0
				modified = true
				setStatus("Inserted newline", 0x08)
			elseif ch == "\b" then
				if cursorCol > 0 then
					local line = lines[cursorRow] or ""
					lines[cursorRow] = line:sub(1, cursorCol - 1) .. line:sub(cursorCol + 1)
					cursorCol = cursorCol - 1
					modified = true
				elseif cursorRow > 1 then
					local prev = lines[cursorRow - 1] or ""
					local cur = lines[cursorRow] or ""
					cursorCol = #prev
					lines[cursorRow - 1] = prev .. cur
					table.remove(lines, cursorRow)
					cursorRow = cursorRow - 1
					modified = true
				end
			elseif ch == "[DEL]" then
				local line = lines[cursorRow] or ""
				if cursorCol < #line then
					lines[cursorRow] = line:sub(1, cursorCol) .. line:sub(cursorCol + 2)
					modified = true
				elseif cursorRow < #lines then
					lines[cursorRow] = line .. (lines[cursorRow + 1] or "")
					table.remove(lines, cursorRow + 1)
					modified = true
				end
			elseif ch == "\t" then
				local line = lines[cursorRow] or ""
				lines[cursorRow] = line:sub(1, cursorCol) .. "  " .. line:sub(cursorCol + 1)
				cursorCol = cursorCol + 2
				modified = true
			elseif #ch == 1 and string.byte(ch) >= 32 and string.byte(ch) <= 126 then
				local line = lines[cursorRow] or ""
				lines[cursorRow] = line:sub(1, cursorCol) .. ch .. line:sub(cursorCol + 1)
				cursorCol = cursorCol + 1
				modified = true
			end

			ensureLine()
			render()
		end

		self.gpu:clearScreen()
		render()
		local ok, err = self:beginForeground("nano", handleInput)
		if not ok then
			outln("nano: " .. tostring(err), 0x0C)
			return 1
		end

		return 0
	end
	B["vi"] = B["nano"]

	-- cat but write stdin to file (heredoc-like)
	B["write"] = function(args)
		if not args[2] then
			return 1
		end
		local path = absPath(args[2])
		local parts = {}
		for i = 3, #args do
			table.insert(parts, args[i])
		end
		vfs():writeFileStr(path, table.concat(parts, " ") .. "\n")
		return 0
	end

	-- pkgmgr
	B["pkgmgr"] = function(args)
		local pm = self.kernel.pkgmgr
		if not pm then
			outln("pkgmgr: package manager not loaded", 0x0C)
			return 1
		end
		local sub = args[2]
		if sub == "install" then
			for i = 3, #args do
				local ok, msg = pm:install(args[i])
				outln(ok and ("Installed: " .. args[i]) or ("Error: " .. tostring(msg)), ok and 0x0A or 0x0C)
			end
		elseif sub == "remove" then
			for i = 3, #args do
				local ok, msg = pm:remove(args[i])
				outln(ok and ("Removed: " .. args[i]) or ("Error: " .. tostring(msg)), ok and 0x0A or 0x0C)
			end
		elseif sub == "update" then
			local ok, msg = pm:update()
			outln(ok and "Package list updated." or ("Error: " .. tostring(msg)), ok and 0x0A or 0x0C)
		elseif sub == "list" then
			local pkgs = pm:list()
			for _, p in ipairs(pkgs) do
				outln(string.format("  %-20s %-10s %s", p.name, p.version, p.desc), p.installed and 0x0A or 0x07)
			end
		elseif sub == "search" then
			local results = pm:search(args[3] or "")
			for _, p in ipairs(results) do
				outln(string.format("  %-20s %-10s %s", p.name, p.version, p.desc))
			end
		elseif sub == "info" then
			local info = pm:info(args[3] or "")
			if info then
				for k, v in pairs(info) do
					outln(string.format("  %-16s: %s", k, tostring(v)))
				end
			else
				outln("pkgmgr: package not found", 0x0C)
			end
		else
			outln("usage: pkgmgr <install|remove|update|list|search|info> [package]")
		end
		return 0
	end

	-- sysinfo (hardware overview)
	B["sysinfo"] = function()
		outln("=== NovaMachine System Information ===", 0x0B)
		outln(string.format("  OS       : %s %s", self.config.OS_NAME, self.config.KERNEL_VERSION))
		outln(string.format("  Hostname : %s", self.hostname))
		outln(string.format("  Arch     : %s", self.config.ARCH))
		outln(string.format("  CPU      : NovaCPU-X1 @ 3.2GHz, 4 cores"))
		local mi = self.mm and self.mm:getMemInfo() or {}
		outln(
			string.format(
				"  RAM      : %dMB total / %dMB free",
				math.floor((mi.total or 0) / 1048576),
				math.floor((mi.free or 0) / 1048576)
			)
		)
		local ds = vfs():getDiskStats()
		outln(
			string.format(
				"  Disk     : %dMB total / %dMB free",
				math.floor(((ds.totalBlocks or 0) * 512) / 1048576),
				math.floor(((ds.freeBlocks or 0) * 512) / 1048576)
			)
		)
		outln(string.format("  GPU      : NovaGFX-400, 1GB VRAM, %dx%d", self.config.SCREEN_W, self.config.SCREEN_H))
		outln(string.format("  Uptime   : %.0f seconds", self.kernel:getUptime()))
		return 0
	end

	-- dmesg
	B["dmesg"] = function(args)
		local log = self.kernel:getLog()
		local n = tonumber(args[2]) or #log
		for i = math.max(1, #log - n + 1), #log do
			outln(log[i], 0x08)
		end
		return 0
	end

	-- lspci
	B["lspci"] = function()
		for _, dev in ipairs(self.config.PCI) do
			outln(
				string.format(
					"%02x:%02x.%d %s: %s [%04x:%04x]",
					dev.bus,
					dev.dev,
					dev.fn,
					dev.class,
					dev.subclass,
					dev.vendor,
					dev.device
				)
			)
		end
		return 0
	end

	-- lsblk
	B["lsblk"] = function()
		outln(string.format("%-10s %-6s %-6s %-6s %-10s %s", "NAME", "MAJ:MIN", "RM", "SIZE", "RO", "TYPE"), 0x0B)
		local total = self.kernel.machine
				and self.kernel.machine.hdd
				and math.floor(self.kernel.machine.hdd:getTotalSectors() * 512 / 1048576)
			or 0
		outln(string.format("%-10s %-6s %-6s %-6s %-10s %s", "hda", "8:0", "0", total .. "M", "0", "disk"))
		outln(string.format("%-10s %-6s %-6s %-6s %-10s %s", "hda1", "8:1", "0", total .. "M", "0", "part"))
		return 0
	end

	-- mount
	B["mount"] = function(args)
		if #args < 2 then
			outln("/dev/hda1 on / type novafs (rw,relatime)")
			outln("tmpfs on /tmp type tmpfs (rw)")
			outln("proc on /proc type proc (rw)")
			outln("sysfs on /sys type sysfs (rw)")
		end
		return 0
	end

	-- reboot / shutdown
	B["reboot"] = function()
		outln("Rebooting system...", 0x0E)
		self._running = false
		task.delay(0.5, function()
			self.kernel:reboot()
		end)
		return 0
	end
	B["shutdown"] = function(args)
		local mode = args[2] or "-h"
		outln("System " .. (mode == "-r" and "rebooting" or "halting") .. " now.", 0x0E)
		self._running = false
		task.delay(0.5, function()
			self.kernel:reboot()
		end)
		return 0
	end
	B["poweroff"] = B["shutdown"]
	B["halt"] = B["shutdown"]

	-- exit
	B["exit"] = function(args)
		self._running = false
		outln("logout", 0x07)
		return tonumber(args[2]) or 0
	end
	B["logout"] = B["exit"]

	-- help
	B["help"] = function()
		outln("NovaShell (nsh) built-in commands:", 0x0B)
		local names = {}
		for k in pairs(B) do
			table.insert(names, k)
		end
		table.sort(names)
		local row = {}
		for _, n in ipairs(names) do
			table.insert(row, string.format("%-12s", n))
			if #row >= 5 then
				outln("  " .. table.concat(row), 0x07)
				row = {}
			end
		end
		if #row > 0 then
			outln("  " .. table.concat(row), 0x07)
		end
		outln("")
		outln("Execution model:", 0x0B)
		outln("  built-in commands: handled internally by nsh", 0x07)
		outln("  external commands: executable files from PATH", 0x07)
		outln("Use 'type <cmd>' or 'which <cmd>' to inspect command kind.", 0x07)
		outln("")
		outln("Type 'pkgmgr install <pkg>' to install packages.", 0x07)
		outln("Type 'pkgmgr list'          to list available packages.", 0x07)
		return 0
	end

	-- lua (interactive Lua REPL via LuauVM)
	B["lua"] = function(args)
		if not vmCfg.enabled then
			outln("lua: VM execution is disabled in config", 0x0C)
			return 1
		end
		if args[2] then
			local target = absPath(args[2])
			if target:sub(-#vmCfg.extension) ~= vmCfg.extension and self.vfs:exists(target .. vmCfg.extension) then
				target = target .. vmCfg.extension
			end
			return self:_runScript(target, args, {}) or 0
		end

		outln("NovaLua REPL (LuauVM powered). Type 'exit' to quit.", 0x0B)

		local replBuf = {}

		local function renderPrompt()
			self.gpu:print("> ")
		end

		local function handleInput(ch)
			if ch == "\n" or ch == "\r" then
				local line = table.concat(replBuf)
				replBuf = {}
				self.gpu:println("")

				if line == "exit" or line == "quit" then
					self:endForeground()
					return
				end

				if line ~= "" then
					local cpu = self.kernel.machine and self.kernel.machine.cpu
					if cpu and type(cpu.executeGuestExecutable) == "function" then
						local execContext = cpu:createExecutionContext({
							pid = self.kernel.pm and self.kernel.pm._currentPid or 0,
							argv = { "lua" },
							env = self.env,
							executable = {
								path = "(lua-repl)",
								kind = "vm",
								format = "luau",
								runtime = "luauvm",
								cpuBackend = self.config.VM and self.config.VM.CPU_BACKEND or nil,
							},
							backend = self.config.VM and self.config.VM.DEFAULT_BACKEND or "auto",
						})
						local sandbox = self:_makeRuntimeEnv({ "lua" }, {}, execContext)

						local function loadSource(source)
							return cpu:executeGuestExecutable({
								path = "(lua-repl)",
								kind = "vm",
								format = "luau",
								runtime = "luauvm",
								backend = self.config.VM and self.config.VM.DEFAULT_BACKEND or "auto",
								cpuBackend = self.config.VM and self.config.VM.CPU_BACKEND or nil,
								content = source,
							}, sandbox, execContext)
						end

						local ok, f = pcall(function()
							return loadSource("return " .. line)
						end)

						if not ok then
							ok, f = pcall(function()
								return loadSource(line)
							end)
						end

						if ok and f then
							local rok, result = pcall(f)
							if rok and result ~= nil then
								outln(tostring(result), 0x0A)
							elseif not rok then
								outln("error: " .. tostring(result), 0x0C)
							end
						else
							outln("compile error: " .. tostring(f), 0x0C)
						end
					else
						outln("lua: CPU guest execution backend unavailable", 0x0C)
					end
				end

				renderPrompt()
			elseif ch == "\b" then
				if #replBuf > 0 then
					table.remove(replBuf)
					self.gpu:print("\b")
				end
			else
				table.insert(replBuf, ch)
				self.gpu:print(ch)
			end
		end

		local ok, err = self:beginForeground("lua-repl", handleInput)
		if not ok then
			outln("lua: " .. tostring(err), 0x0C)
			return 1
		end

		renderPrompt()
		return 0
	end

	-- Prefer guest executable files for common userland tools.
	for _, name in ipairs({
		"mkdir",
		"rm",
		"cp",
		"mv",
		"touch",
		"ls",
		"cat",
		"echo",
		"pwd",
		"date",
		"clear",
		"true",
		"false",
		"sleep",
		"uname",
		"whoami",
		"id",
		"hostname",
		"uptime",
		"free",
		"df",
		"wc",
		"grep",
		"sort",
		"which",
		"find",
		"head",
		"tail",
		"ps",
		"sysinfo",
		"dmesg",
		"lspci",
		"lsblk",
		"mount",
		"lua",
		"pkgmgr",
	}) do
		B[name] = nil
	end

	return B
end

function Shell:isForegroundBusy()
	return self._foreground ~= nil
end

function Shell:beginForeground(name, onInput, onCleanup)
	if self._foreground then
		return false, "foreground already active"
	end

	self._foreground = {
		name = name or "app",
		startedAt = os.clock(),
	}

	self._foregroundInput = onInput
	self._foregroundCleanup = onCleanup
	self._suppressPrompt = true
	return true
end

function Shell:endForeground()
	local cleanup = self._foregroundCleanup

	self._foreground = nil
	self._foregroundInput = nil
	self._foregroundCleanup = nil
	self._suppressPrompt = false

	if cleanup then
		pcall(cleanup)
	end

	if self._running then
		self:_prompt()
	end
end

function Shell:sendForegroundInput(ch)
	if self._foregroundInput then
		local ok, err = pcall(self._foregroundInput, ch)
		if not ok then
			self.gpu:println("[foreground crash] " .. tostring(err), 0x0C)
			self:endForeground()
		end
		return true
	end
	return false
end

function Shell:interruptForeground()
	if not self._foreground then
		return false
	end

	self.gpu:println("^C", 0x0C)
	self:endForeground()
	return true
end

return Shell
