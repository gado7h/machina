-- NovaMachine/userland/Init.lua
-- PID 1 — init process. Runs rc scripts, populates /bin, launches shell.
-- All user-executable scripts are compiled through LuauVM.

local Init = {}
Init.__index = Init

function Init.new(kernel)
	local self = setmetatable({}, Init)
	self.kernel = kernel
	self.gpu = kernel.gpu
	self.vfs = kernel.vfs
	self.config = kernel.config
	self.luauvm = kernel.machine and kernel.machine.luauvm
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
			msg = "Validating scripts (LuauVM)",
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
	local scripts = {
		["/bin/echo"] = 'local p={};local nl=true;for i=2,#args do if args[i]=="-n" then nl=false else table.insert(p,args[i])end end;local s=table.concat(p," "):gsub("\\\\n","\\n"):gsub("\\\\t","\\t");if nl then tty.writeln(s)else tty.write(s)end;return 0',
		["/bin/cat"] = 'if #args<2 then if process._pipeInput then tty.write(process._pipeInput)end;return 0 end;for i=2,#args do local c=fs.read(args[i]);if c then tty.write(c)else tty.writeln("cat: "..args[i]..": not found",tty.color(12,0));return 1 end end;return 0',
		["/bin/pwd"] = "tty.writeln(process.cwd());return 0",
		["/bin/date"] = 'tty.writeln(os.date((args[2] and args[2]:gsub("^%+","")) or "%c"));return 0',
		["/bin/clear"] = "tty.clear();return 0",
		["/bin/true"] = "return 0",
		["/bin/false"] = "return 1",
		["/bin/sleep"] = "local d=os.clock()+(tonumber(args[2])or 1);while os.clock()<d do end;return 0",
		["/bin/uname"] = 'local f={};for i=2,#args do for j=2,#args[i] do f[args[i]:sub(j,j)]=true end end;if f["a"] then tty.writeln("NovaOS novamachine nova-1.0.0 #1 SMP nova32")elseif f["r"] then tty.writeln("nova-1.0.0")elseif f["m"] then tty.writeln("nova32")else tty.writeln("NovaOS")end;return 0',
		["/bin/wc"] = 'local c=args[2] and(fs.read(args[2])or"")or(process._pipeInput or"");local l,w,b=0,0,#c;for ln in(c.."\\n"):gmatch("([^\\n]*)\\n") do l=l+1;for _ in ln:gmatch("%S+") do w=w+1 end end;tty.writeln(string.format("%7d %7d %7d",l,w,b));return 0',
		["/bin/grep"] = 'local p=args[2];local c=args[3] and(fs.read(args[3])or"")or(process._pipeInput or"");if not p then tty.writeln("usage: grep <pat> [file]");return 1 end;for l in(c.."\\n"):gmatch("([^\\n]*)\\n") do if l:find(p) then tty.writeln(l,tty.color(10,0))end end;return 0',
		["/bin/sort"] = 'local c=args[2] and(fs.read(args[2])or"")or(process._pipeInput or"");local t={};for l in(c.."\\n"):gmatch("([^\\n]*)\\n") do if l~="" then table.insert(t,l)end end;table.sort(t);for _,l in ipairs(t) do tty.writeln(l)end;return 0',
		["/bin/which"] = 'if not args[2] then return 1 end;for _,d in ipairs({"/bin","/usr/bin","/pkg/bin"}) do if fs.exists(d.."/"..args[2]) then tty.writeln(d.."/"..args[2]);return 0 end end;tty.writeln(args[2]..": not found",tty.color(12,0));return 1',
		["/bin/find"] = 'local function w(d)local e=fs.ls(d);if not e then return end;for _,f in ipairs(e) do local p=(d=="/"and"/"..f.name or d.."/"..f.name);if not args[2] or args[2]:find("-")==nil or d:find(args[2]:gsub("^./","")) then tty.writeln(p)end;if f.isDir then w(p)end end end;w(args[2]or".");return 0',
		["/bin/head"] = 'local n=10;local p;for i=2,#args do if args[i]=="-n" then n=tonumber(args[i+1])or 10 elseif not p then p=args[i]end end;local c=p and(fs.read(p)or"")or(process._pipeInput or"");local i=0;for l in(c.."\\n"):gmatch("([^\\n]*)\\n") do if i>=n then break end;tty.writeln(l);i=i+1 end;return 0',
		["/bin/tail"] = 'local n=10;local p;for i=2,#args do if args[i]=="-n" then n=tonumber(args[i+1])or 10 elseif not p then p=args[i]end end;local c=p and(fs.read(p)or"")or(process._pipeInput or"");local t={};for l in(c.."\\n"):gmatch("([^\\n]*)\\n") do table.insert(t,l)end;for i=math.max(1,#t-n+1),#t do tty.writeln(t[i])end;return 0',
		["/sbin/init"] = "return 0",
		["/sbin/shutdown"] = 'tty.writeln("Shutting down...",tty.color(14,0));os.exit(0)',
		["/usr/bin/lua"] = [[
		tty.writeln("LuauVM Lua REPL. Use lua <file> to run scripts.",tty.color(11,0));if args[2] then local c=fs.read(args[2]);if c and luauvm then local ok,f,cl=pcall(function()return luauvm.load(c,false)end);if ok and f then local rk,e=pcall(f);if not rk then tty.writeln(tostring(e),tty.color(12,0))end end end end;return 0
		]],
	}
	for path, src in pairs(scripts) do
		if not self.vfs:exists(path) then
			self.vfs:writeFileStr(path, src)
		end
	end
end

function Init:_precompileBin()
	if not self.luauvm then
		return
	end
	for _, dir in ipairs({ "/bin", "/usr/bin" }) do
		local entries = self.vfs:listDir(dir) or {}
		for _, e in ipairs(entries) do
			if not e.isDir then
				local src = self.vfs:readFileStr(dir .. "/" .. e.name)
				if src then
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
	if not src or not self.luauvm then
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

function Init:_loginUser(username)
	self.gpu:println(string.format("Last login: %s on tty0", os.date()), 0x07)
	self.gpu:println("", 0x07)
	local ShellMod = require(script.Parent.Shell)
	self.shell = ShellMod.new(self.kernel, username)
	self.shell:start()
end

return Init
