local NativeSyscalls = require(script.Parent.NativeSyscalls)

local NativeCommandBridge = {}

local function buildRuntime(execution)
	local env = execution.env or {}
	local context = execution.context or {}
	local argv = context.argv or env.args or {}
	local tty = env.tty or {}
	local fs = env.fs or {}
	local process = env.process or {}
	local system = env.system or {}
	local oslib = env.os or os

	local function writeln(text, attr)
		if tty.writeln then
			tty.writeln(text, attr)
		elseif tty.write then
			tty.write((text or "") .. "\n", attr)
		end
	end

	local function write(text, attr)
		if tty.write then
			tty.write(text, attr)
		elseif tty.writeln then
			tty.writeln(text, attr)
		end
	end

	local function color(fg, bg)
		if tty.color then
			return tty.color(fg, bg)
		end
		return nil
	end

	return {
		env = env,
		context = context,
		argv = argv,
		tty = tty,
		fs = fs,
		process = process,
		system = system,
		os = oslib,
		write = write,
		writeln = writeln,
		color = color,
	}
end

local function dispatchEcho(rt)
	local parts = {}
	local newline = true
	for i = 2, #rt.argv do
		if rt.argv[i] == "-n" then
			newline = false
		else
			table.insert(parts, rt.argv[i])
		end
	end
	local text = table.concat(parts, " "):gsub("\\n", "\n"):gsub("\\t", "\t")
	if newline then
		rt.writeln(text)
	else
		rt.write(text)
	end
	return 0
end

local function dispatchCat(rt)
	if #rt.argv < 2 then
		if rt.process._pipeInput then
			rt.write(rt.process._pipeInput)
		end
		return 0
	end

	for i = 2, #rt.argv do
		local content = rt.fs.read and rt.fs.read(rt.argv[i]) or nil
		if content then
			rt.write(content)
		else
			rt.writeln("cat: " .. tostring(rt.argv[i]) .. ": not found", rt.color(12, 0))
			return 1
		end
	end
	return 0
end

local function dispatchPwd(rt)
	rt.writeln(rt.process.cwd and rt.process.cwd() or "/")
	return 0
end

local function dispatchMkdir(rt)
	if #rt.argv < 2 then
		rt.writeln("usage: mkdir <dir> [...]", rt.color(12, 0))
		return 1
	end
	for i = 2, #rt.argv do
		local ok, err = rt.fs.mkdir and rt.fs.mkdir(rt.argv[i])
		if not ok then
			rt.writeln(
				"mkdir: cannot create directory '" .. tostring(rt.argv[i]) .. "': " .. tostring(err),
				rt.color(12, 0)
			)
			return 1
		end
	end
	return 0
end

local function dispatchRm(rt)
	local recursive = false
	local paths = {}
	for i = 2, #rt.argv do
		if tostring(rt.argv[i]):sub(1, 1) == "-" then
			recursive = tostring(rt.argv[i]):find("r", 2, true) ~= nil or recursive
		else
			table.insert(paths, rt.argv[i])
		end
	end
	for _, path in ipairs(paths) do
		local st = rt.fs.stat and rt.fs.stat(path) or nil
		if not st then
			rt.writeln("rm: cannot remove '" .. tostring(path) .. "': No such file or directory", rt.color(12, 0))
			return 1
		end
		if st.isDir and not recursive then
			rt.writeln("rm: cannot remove '" .. tostring(path) .. "': Is a directory", rt.color(12, 0))
			return 1
		end
		if rt.fs.rm then
			rt.fs.rm(path)
		end
	end
	return 0
end

local function dispatchCp(rt)
	if #rt.argv < 3 then
		rt.writeln("usage: cp <src> <dst>", rt.color(12, 0))
		return 1
	end
	local ok, result
	if rt.fs.copy then
		ok, result = rt.fs.copy(rt.argv[2], rt.argv[3])
	else
		ok, result = false, "unsupported"
	end
	if not ok then
		rt.writeln("cp: " .. tostring(result), rt.color(12, 0))
		return 1
	end
	return 0
end

local function dispatchMv(rt)
	if #rt.argv < 3 then
		rt.writeln("usage: mv <src> <dst>", rt.color(12, 0))
		return 1
	end
	local ok, result
	if rt.fs.move then
		ok, result = rt.fs.move(rt.argv[2], rt.argv[3])
	else
		ok, result = false, "unsupported"
	end
	if not ok then
		rt.writeln("mv: " .. tostring(result), rt.color(12, 0))
		return 1
	end
	return 0
end

local function dispatchTouch(rt)
	if #rt.argv < 2 then
		rt.writeln("usage: touch <file> [...]", rt.color(12, 0))
		return 1
	end
	for i = 2, #rt.argv do
		if rt.fs.touch then
			rt.fs.touch(rt.argv[i])
		end
	end
	return 0
end

local function dispatchLs(rt)
	local target = rt.argv[2] or (rt.process.cwd and rt.process.cwd()) or "/"
	local entries = rt.fs.ls and rt.fs.ls(target) or nil
	if not entries then
		rt.writeln("ls: cannot access '" .. tostring(target) .. "'", rt.color(12, 0))
		return 1
	end
	table.sort(entries, function(a, b)
		return a.name < b.name
	end)
	local row = {}
	for _, item in ipairs(entries) do
		local name = item.name .. (item.isDir and "/" or "")
		table.insert(row, string.format("%-18s", name:sub(1, 17)))
		if #row >= 4 then
			rt.writeln(table.concat(row))
			row = {}
		end
	end
	if #row > 0 then
		rt.writeln(table.concat(row))
	end
	return 0
end

local function dispatchPs(rt)
	local procs = rt.process.list and rt.process.list() or {}
	rt.writeln(
		string.format("  %-6s %-6s %-4s %-10s %-5s %-6s %s", "PID", "PPID", "PRI", "STATE", "CPU%", "MEM", "COMMAND"),
		rt.color(11, 0)
	)
	for _, p in ipairs(procs) do
		local stateColor = p.state == "R" and rt.color(10, 0) or p.state == "Z" and rt.color(12, 0) or rt.color(7, 0)
		rt.writeln(
			string.format("  %-6d %-6d %-4d %-10s %-5.1f %-6dK %s", p.pid, p.ppid, p.pri, p.state, p.cpu, p.mem, p.name),
			stateColor
		)
	end
	return 0
end

local function dispatchDate(rt)
	rt.writeln(rt.os.date((rt.argv[2] and tostring(rt.argv[2]):gsub("^%+", "")) or "%c"))
	return 0
end

local function dispatchClear(rt)
	if rt.tty.clear then
		rt.tty.clear()
	end
	return 0
end

local function dispatchSleep(rt)
	local deadline = rt.os.clock() + (tonumber(rt.argv[2]) or 1)
	while rt.os.clock() < deadline do
	end
	return 0
end

local function dispatchUname(rt)
	local flags = {}
	for i = 2, #rt.argv do
		for j = 2, #tostring(rt.argv[i]) do
			flags[tostring(rt.argv[i]):sub(j, j)] = true
		end
	end
	local info = rt.system.info and rt.system.info() or {}
	if flags.a then
		rt.writeln(string.format("%s %s %s #1 SMP %s", info.os or "NovaOS", info.hostname or "novamachine", info.kernel or "nova-1.0.0", info.arch or "nova32"))
	elseif flags.r then
		rt.writeln(info.kernel or "nova-1.0.0")
	elseif flags.m then
		rt.writeln(info.arch or "nova32")
	else
		rt.writeln(info.os or "NovaOS")
	end
	return 0
end

local function dispatchWhoami(rt)
	rt.writeln(rt.process.user and rt.process.user() or "user")
	return 0
end

local function dispatchId(rt)
	local user = rt.process.user and rt.process.user() or "user"
	local uid = user == "root" and 0 or 1000
	rt.writeln(string.format("uid=%d(%s) gid=%d(%s) groups=%d(%s)", uid, user, uid, user, uid, user))
	return 0
end

local function dispatchHostname(rt)
	if rt.argv[2] and rt.system.hostname then
		rt.system.hostname(rt.argv[2])
	else
		rt.writeln(rt.system.hostname and rt.system.hostname() or "novamachine")
	end
	return 0
end

local function dispatchUptime(rt)
	local uptime = rt.system.uptime and rt.system.uptime() or 0
	local h = math.floor(uptime / 3600)
	local m = math.floor((uptime % 3600) / 60)
	local s = math.floor(uptime % 60)
	local procs = rt.process.list and #rt.process.list() or 0
	rt.writeln(
		string.format(
			" %s  up %02d:%02d:%02d,  1 user,  load average: 0.00, 0.00, 0.00 (%d procs)",
			rt.os.date("%H:%M:%S"),
			h,
			m,
			s,
			procs
		)
	)
	return 0
end

local function dispatchFree(rt)
	local mi = rt.system.meminfo and rt.system.meminfo() or {}
	local function kb(n)
		return math.floor((n or 0) / 1024)
	end
	rt.writeln(string.format("%-16s%8s%8s%8s", "              ", "total", "used", "free"), rt.color(11, 0))
	rt.writeln(string.format("%-16s%8d%8d%8d", "Mem:", kb(mi.total), kb(mi.used), kb(mi.free)))
	rt.writeln(string.format("%-16s%8d%8d%8d", "Swap:", 0, 0, 0))
	return 0
end

local function dispatchDf(rt)
	local ds = rt.system.diskstats and rt.system.diskstats() or {}
	rt.writeln(
		string.format("%-20s%10s%10s%10s%6s %s", "Filesystem", "1K-blocks", "Used", "Available", "Use%", "Mounted on"),
		rt.color(11, 0)
	)
	local total = (ds.totalBlocks or 0) * 512 / 1024
	local used = (ds.usedBlocks or 0) * 512 / 1024
	local free = (ds.freeBlocks or 0) * 512 / 1024
	local pct = total > 0 and math.floor(used / total * 100) or 0
	rt.writeln(string.format("%-20s%10d%10d%10d%5d%% %s", "/dev/hda1", total, used, free, pct, "/"))
	return 0
end

local function dispatchEnv(rt)
	local keys = {}
	for key in pairs(rt.process.env or {}) do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		rt.writeln(key .. "=" .. tostring(rt.process.env[key]))
	end
	return 0
end

local function dispatchWc(rt)
	local content = rt.argv[2] and (rt.fs.read and rt.fs.read(rt.argv[2]) or "") or (rt.process._pipeInput or "")
	local lines, words, bytes = 0, 0, #content
	for line in (content .. "\n"):gmatch("([^\n]*)\n") do
		lines = lines + 1
		for _ in line:gmatch("%S+") do
			words = words + 1
		end
	end
	rt.writeln(string.format("%7d %7d %7d", lines, words, bytes))
	return 0
end

local function dispatchGrep(rt)
	local pattern = rt.argv[2]
	local content = rt.argv[3] and (rt.fs.read and rt.fs.read(rt.argv[3]) or "") or (rt.process._pipeInput or "")
	if not pattern then
		rt.writeln("usage: grep <pat> [file]", rt.color(12, 0))
		return 1
	end
	for line in (content .. "\n"):gmatch("([^\n]*)\n") do
		if line:find(pattern) then
			rt.writeln(line, rt.color(10, 0))
		end
	end
	return 0
end

local function dispatchHead(rt)
	local count = 10
	local path = nil
	for i = 2, #rt.argv do
		if rt.argv[i] == "-n" then
			count = tonumber(rt.argv[i + 1]) or 10
		elseif not path then
			path = rt.argv[i]
		end
	end
	local content = path and (rt.fs.read and rt.fs.read(path) or "") or (rt.process._pipeInput or "")
	local index = 0
	for line in (content .. "\n"):gmatch("([^\n]*)\n") do
		if index >= count then
			break
		end
		rt.writeln(line)
		index = index + 1
	end
	return 0
end

local function dispatchTail(rt)
	local count = 10
	local path = nil
	for i = 2, #rt.argv do
		if rt.argv[i] == "-n" then
			count = tonumber(rt.argv[i + 1]) or 10
		elseif not path then
			path = rt.argv[i]
		end
	end
	local content = path and (rt.fs.read and rt.fs.read(path) or "") or (rt.process._pipeInput or "")
	local lines = {}
	for line in (content .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(lines, line)
	end
	for i = math.max(1, #lines - count + 1), #lines do
		rt.writeln(lines[i])
	end
	return 0
end

local function dispatchSysinfo(rt)
	local info = rt.system.info and rt.system.info() or {}
	rt.writeln("=== NovaMachine System Information ===", rt.color(11, 0))
	rt.writeln(string.format("  OS       : %s %s", info.os or "NovaOS", info.kernel or "nova-1.0.0"))
	rt.writeln(string.format("  Hostname : %s", info.hostname or "novamachine"))
	rt.writeln(string.format("  Arch     : %s", info.arch or "nova32"))
	rt.writeln("  CPU      : NovaCPU-X1 @ 3.2GHz, 4 cores")
	rt.writeln(
		string.format(
			"  RAM      : %dMB total / %dMB free",
			math.floor((info.ramTotal or 0) / 1048576),
			math.floor((info.ramFree or 0) / 1048576)
		)
	)
	rt.writeln(
		string.format(
			"  Disk     : %dMB total / %dMB free",
			math.floor(((info.diskTotalBlocks or 0) * 512) / 1048576),
			math.floor(((info.diskFreeBlocks or 0) * 512) / 1048576)
		)
	)
	rt.writeln(string.format("  GPU      : NovaGFX-400, 1GB VRAM, %dx%d", info.screenW or 320, info.screenH or 200))
	rt.writeln(string.format("  Uptime   : %.0f seconds", info.uptime or 0))
	return 0
end

local function dispatchDmesg(rt)
	local log = rt.system.dmesg and rt.system.dmesg() or {}
	local n = tonumber(rt.argv[2]) or #log
	for i = math.max(1, #log - n + 1), #log do
		rt.writeln(log[i], rt.color(8, 0))
	end
	return 0
end

local function dispatchLspci(rt)
	for _, dev in ipairs(rt.system.pci and rt.system.pci() or {}) do
		rt.writeln(
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

local function dispatchLsblk(rt)
	rt.writeln(string.format("%-10s %-6s %-6s %-6s %-10s %s", "NAME", "MAJ:MIN", "RM", "SIZE", "RO", "TYPE"), rt.color(11, 0))
	local ds = rt.system.diskstats and rt.system.diskstats() or {}
	local total = math.floor(((ds.totalBlocks or 0) * 512) / 1048576)
	rt.writeln(string.format("%-10s %-6s %-6s %-6s %-10s %s", "hda", "8:0", "0", total .. "M", "0", "disk"))
	rt.writeln(string.format("%-10s %-6s %-6s %-6s %-10s %s", "hda1", "8:1", "0", total .. "M", "0", "part"))
	return 0
end

local function dispatchMount(rt)
	rt.writeln("/dev/hda1 on / type novafs (rw,relatime)")
	rt.writeln("tmpfs on /tmp type tmpfs (rw)")
	rt.writeln("proc on /proc type proc (rw)")
	rt.writeln("sysfs on /sys type sysfs (rw)")
	return 0
end

local HANDLERS = {
	[NativeSyscalls.SYS.ECHO] = dispatchEcho,
	[NativeSyscalls.SYS.CAT] = dispatchCat,
	[NativeSyscalls.SYS.PWD] = dispatchPwd,
	[NativeSyscalls.SYS.MKDIR] = dispatchMkdir,
	[NativeSyscalls.SYS.RM] = dispatchRm,
	[NativeSyscalls.SYS.CP] = dispatchCp,
	[NativeSyscalls.SYS.MV] = dispatchMv,
	[NativeSyscalls.SYS.TOUCH] = dispatchTouch,
	[NativeSyscalls.SYS.LS] = dispatchLs,
	[NativeSyscalls.SYS.PS] = dispatchPs,
	[NativeSyscalls.SYS.DATE] = dispatchDate,
	[NativeSyscalls.SYS.CLEAR] = dispatchClear,
	[NativeSyscalls.SYS.TRUE] = function()
		return 0
	end,
	[NativeSyscalls.SYS.FALSE] = function()
		return 1
	end,
	[NativeSyscalls.SYS.SLEEP] = dispatchSleep,
	[NativeSyscalls.SYS.UNAME] = dispatchUname,
	[NativeSyscalls.SYS.WHOAMI] = dispatchWhoami,
	[NativeSyscalls.SYS.ID] = dispatchId,
	[NativeSyscalls.SYS.HOSTNAME] = dispatchHostname,
	[NativeSyscalls.SYS.UPTIME] = dispatchUptime,
	[NativeSyscalls.SYS.FREE] = dispatchFree,
	[NativeSyscalls.SYS.DF] = dispatchDf,
	[NativeSyscalls.SYS.ENV] = dispatchEnv,
	[NativeSyscalls.SYS.WC] = dispatchWc,
	[NativeSyscalls.SYS.GREP] = dispatchGrep,
	[NativeSyscalls.SYS.HEAD] = dispatchHead,
	[NativeSyscalls.SYS.TAIL] = dispatchTail,
	[NativeSyscalls.SYS.SYSINFO] = dispatchSysinfo,
	[NativeSyscalls.SYS.DMESG] = dispatchDmesg,
	[NativeSyscalls.SYS.LSPCI] = dispatchLspci,
	[NativeSyscalls.SYS.LSBLK] = dispatchLsblk,
	[NativeSyscalls.SYS.MOUNT] = dispatchMount,
}

function NativeCommandBridge.dispatch(execution, syscallNumber)
	local handler = HANDLERS[tonumber(syscallNumber) or -1]
	if not handler then
		return nil, "native-syscall-unsupported:" .. tostring(syscallNumber)
	end
	local runtime = buildRuntime(execution or {})
	return handler(runtime)
end

return NativeCommandBridge
