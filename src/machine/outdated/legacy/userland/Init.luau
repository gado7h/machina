-- Init module

local Init = {}
Init.__index = Init

local GuestPrograms = require(script.Parent.GuestPrograms)
local NativePrograms = require(script.Parent.NativePrograms)
local NativeSourcePrograms = require(script.Parent.NativeSourcePrograms)

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

function Init.new(kernel)
	local self = setmetatable({}, Init)
	self.kernel = kernel
	self.gpu = kernel.gpu
	self.vfs = kernel.vfs
	self.config = kernel.config
	self.luauvm = kernel.machine and kernel.machine.luauvm
	self.vmConfig = getVmConfig(self.config)
	return self
end

function Init:run()
	if self.kernel.pm then
		self.kernel.pm:spawn("init", function(p)
			while true do
				coroutine.yield()
			end
		end, 0, 0, 0)
	end
	self.gpu:println("NovaOS init  PID 1", 0x07)
	self.gpu:println("", 0x07)
	self:_rcSysinit()
end

function Init:_rcSysinit()
	local steps = {
		{
			msg = "Mounting filesystems",
			fn = function()
				self:_mountFS()
			end,
		},
		{
			msg = "Populating /bin",
			fn = function()
				self:_populateBin()
			end,
		},
		{
			msg = "Validating VM scripts",
			fn = function()
				self:_precompileBin()
			end,
		},
		{
			msg = "Setting hostname",
			fn = function()
				self:_setHostname()
			end,
		},
		{
			msg = "Initialising /dev",
			fn = function()
				self:_initDev()
			end,
		},
		{
			msg = "Loading kernel modules",
			fn = function()
				self:_loadModules()
			end,
		},
		{
			msg = "Bringing up loopback",
			fn = function()
				self:_netLoopback()
			end,
		},
		{
			msg = "Starting syslog",
			fn = function()
				self:_startSyslog()
			end,
		},
		{
			msg = "Running /etc/rc.local",
			fn = function()
				self:_rcLocal()
			end,
		},
	}
	local function run(i)
		if i > #steps then
			self:_getty()
			return
		end
		local s = steps[i]
		self.gpu:print(string.format("  %-44s", "[ " .. s.msg .. " ]"), 0x07)
		local ok, err = pcall(s.fn)
		self.gpu:println(ok and " OK" or ("FAIL:" .. tostring(err):sub(1, 28)), ok and 0x0A or 0x0C)
		task.delay(0.025, function()
			run(i + 1)
		end)
	end
	run(1)
end

function Init:_mountFS()
	for _, d in ipairs({
		"/",
		"/bin",
		"/usr",
		"/usr/bin",
		"/usr/lib",
		"/etc",
		"/home",
		"/home/user",
		"/var",
		"/var/log",
		"/tmp",
		"/boot",
		"/dev",
		"/proc",
		"/sys",
		"/pkg",
		"/pkg/db",
		"/root",
	}) do
		if not self.vfs:exists(d) then
			self.vfs:mkdir(d)
		end
	end
end

function Init:_populateBin()
	local scripts = GuestPrograms.materialize(self.vmConfig.pragma)
	for path, src in pairs(scripts) do
		self.vfs:writeFileStr(path, src)
	end

	local nativePrograms = NativePrograms.materialize(self.config)
	for path, imageBytes in pairs(nativePrograms) do
		self.vfs:writeFile(path, imageBytes)
	end

	local nativeSources = NativeSourcePrograms.materialize()
	for path, source in pairs(nativeSources) do
		self.vfs:writeFileStr(path, source)
	end
end

function Init:_precompileBin()
	if not self.luauvm or not self.vmConfig.enabled then
		return
	end
	for _, dir in ipairs({ "/bin", "/usr/bin" }) do
		local entries = self.vfs:listDir(dir) or {}
		for _, e in ipairs(entries) do
			if not e.isDir and e.name:sub(-#self.vmConfig.extension) == self.vmConfig.extension then
				local src = self.vfs:readFileStr(dir .. "/" .. e.name)
				if src and firstMeaningfulLine(src) == self.vmConfig.pragma then
					pcall(function()
						self.luauvm.compile(src)
					end)
				end
			end
		end
	end
end

function Init:_setHostname()
	local hn = "novamachine"
	if self.vfs:exists("/etc/hostname") then
		local s = self.vfs:readFileStr("/etc/hostname")
		if s then
			hn = s:gsub("%s+$", "")
		end
	end
	self.kernel._hostname = hn
end

function Init:_initDev()
	for _, d in ipairs({ "null", "zero", "random", "urandom", "tty", "tty0", "hda", "hda1", "fb0", "kbd" }) do
		local p = "/dev/" .. d
		if not self.vfs:exists(p) then
			self.vfs:writeFileStr(p, "device:" .. d .. "\n")
		end
	end
end

function Init:_loadModules()
	for _, m in ipairs({ "novafs", "novagpu", "novanet", "novainput", "novaacpi" }) do
		self.kernel:log("modprobe: loaded " .. m)
	end
end

function Init:_netLoopback()
	if self.kernel.machine and self.kernel.machine.nic then
		self.kernel.machine.nic.ip = "127.0.0.1"
		self.kernel.machine.nic.link = "UP"
	end
end

function Init:_startSyslog()
	if not self.vfs:exists("/var/log") then
		self.vfs:mkdir("/var/log")
	end
	self.vfs:writeFileStr("/var/log/syslog", os.date("[%Y-%m-%d %H:%M:%S]") .. " syslogd started\n")
	self.vfs:writeFileStr("/var/log/dmesg", table.concat(self.kernel:getLog(), "\n") .. "\n")
end

function Init:_rcLocal()
	local path = "/etc/rc.local"
	if not self.vfs:exists(path) then
		self.vfs:writeFileStr(path, "-- /etc/rc.local\nreturn 0\n")
		return
	end
	local src = self.vfs:readFileStr(path)
	if not src or not self.luauvm or not self.vmConfig.enabled then
		return
	end
	if firstMeaningfulLine(src) ~= self.vmConfig.pragma then
		return
	end
	local sandbox = {
		tty = {
			writeln = function(s, a)
				self.gpu:println(tostring(s), a or 0x07)
			end,
			write = function(s, a)
				self.gpu:print(tostring(s), a or 0x07)
			end,
			color = function(f, b)
				return (b or 0) * 16 + (f or 7)
			end,
		},
		fs = {
			read = function(p)
				return self.vfs:readFileStr(p)
			end,
			write = function(p, s)
				self.vfs:writeFileStr(p, tostring(s))
			end,
			exists = function(p)
				return self.vfs:exists(p)
			end,
			mkdir = function(p)
				self.vfs:mkdir(p)
			end,
		},
		os = { time = os.time, date = os.date, clock = os.clock },
		print = function(...)
			self.gpu:println(table.concat({ ... }, "\t"))
		end,
		string = string,
		math = math,
		table = table,
		pairs = pairs,
		ipairs = ipairs,
		tostring = tostring,
		tonumber = tonumber,
		type = type,
		pcall = pcall,
		error = error,
		task = { delay = task and task.delay or function(_, f)
			f()
		end },
	}
	local ok, f = pcall(function()
		return self.luauvm(src, false, sandbox)
	end)
	if ok and f then
		pcall(f)
	end
end

function Init:_getty()
	self.gpu:println("", 0x07)
	if self.vfs:exists("/etc/motd") then
		local m = self.vfs:readFileStr("/etc/motd")
		if m then
			self.gpu:print(m, 0x07)
		end
	end
	self.gpu:println(string.format("%s login: user (auto)", self.kernel._hostname or "novamachine"), 0x0F)
	self.gpu:println("", 0x07)
	task.delay(0.4, function()
		self:_loginUser("user")
	end)
end

function Init:_startGPUTest(username)
	local DemoMod = require(script.Parent.GPUTest)
	self.gpuTest = DemoMod.new(self.kernel, username, function()
		self:_startShell(username)
	end)
	self.gpuTest:start()
end

function Init:_startShell(username)
	local ShellMod = require(script.Parent.Shell)
	self.shell = ShellMod.new(self.kernel, username)
	self.shell:start()
end

function Init:_loginUser(username)
	self.gpu:println(string.format("Last login: %s on tty0", os.date()), 0x07)
	self.gpu:println("", 0x07)
	self:_startGPUTest(username)
end

return Init
