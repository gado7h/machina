-- Canonical guest program sources seeded into the virtual filesystem.
-- Keeping them here makes userland commands easier to modify than
-- embedding large inline strings inside Init.

local GuestPrograms = {}

local SOURCES = {
	["/bin/echo.luau"] = [[
local parts = {}
local newline = true
for i = 2, #args do
	if args[i] == "-n" then
		newline = false
	else
		table.insert(parts, args[i])
	end
end
local text = table.concat(parts, " "):gsub("\\n", "\n"):gsub("\\t", "\t")
if newline then
	tty.writeln(text)
else
	tty.write(text)
end
return 0
]],
	["/bin/cat.luau"] = [[
if #args < 2 then
	if process._pipeInput then
		tty.write(process._pipeInput)
	end
	return 0
end

for i = 2, #args do
	local content = fs.read(args[i])
	if content then
		tty.write(content)
	else
		tty.writeln("cat: " .. args[i] .. ": not found", tty.color(12, 0))
		return 1
	end
end

return 0
]],
	["/bin/pwd.luau"] = [[
tty.writeln(process.cwd())
return 0
]],
	["/bin/ls.luau"] = [[
local function listDirectory(path)
	local entries = fs.ls(path)
	if not entries then
		tty.writeln("ls: cannot access '" .. tostring(path) .. "'", tty.color(12, 0))
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
			tty.writeln(table.concat(row))
			row = {}
		end
	end
	if #row > 0 then
		tty.writeln(table.concat(row))
	end
	return 0
end

return listDirectory(args[2] or process.cwd())
]],
	["/bin/ps.luau"] = [[
local procs = process.list and process.list() or {}
tty.writeln(
	string.format("  %-6s %-6s %-4s %-10s %-5s %-6s %s", "PID", "PPID", "PRI", "STATE", "CPU%", "MEM", "COMMAND"),
	tty.color(11, 0)
)
for _, p in ipairs(procs) do
	local stateColor = p.state == "R" and tty.color(10, 0) or p.state == "Z" and tty.color(12, 0) or tty.color(7, 0)
	tty.writeln(
		string.format("  %-6d %-6d %-4d %-10s %-5.1f %-6dK %s", p.pid, p.ppid, p.pri, p.state, p.cpu, p.mem, p.name),
		stateColor
	)
end
return 0
]],
	["/bin/date.luau"] = [[
tty.writeln(os.date((args[2] and args[2]:gsub("^%+", "")) or "%c"))
return 0
]],
	["/bin/clear.luau"] = [[
tty.clear()
return 0
]],
	["/bin/true.luau"] = [[
return 0
]],
	["/bin/false.luau"] = [[
return 1
]],
	["/bin/sleep.luau"] = [[
local deadline = os.clock() + (tonumber(args[2]) or 1)
while os.clock() < deadline do
end
return 0
]],
	["/bin/uname.luau"] = [[
local flags = {}
for i = 2, #args do
	for j = 2, #args[i] do
		flags[args[i]:sub(j, j)] = true
	end
end
if flags.a then
	tty.writeln("NovaOS novamachine nova-1.0.0 #1 SMP nova32")
elseif flags.r then
	tty.writeln("nova-1.0.0")
elseif flags.m then
	tty.writeln("nova32")
else
	tty.writeln("NovaOS")
end
return 0
]],
	["/bin/wc.luau"] = [[
local content = args[2] and (fs.read(args[2]) or "") or (process._pipeInput or "")
local lines, words, bytes = 0, 0, #content
for line in (content .. "\n"):gmatch("([^\n]*)\n") do
	lines = lines + 1
	for _ in line:gmatch("%S+") do
		words = words + 1
	end
end
tty.writeln(string.format("%7d %7d %7d", lines, words, bytes))
return 0
]],
	["/bin/grep.luau"] = [[
local pattern = args[2]
local content = args[3] and (fs.read(args[3]) or "") or (process._pipeInput or "")
if not pattern then
	tty.writeln("usage: grep <pat> [file]")
	return 1
end
for line in (content .. "\n"):gmatch("([^\n]*)\n") do
	if line:find(pattern) then
		tty.writeln(line, tty.color(10, 0))
	end
end
return 0
]],
	["/bin/sort.luau"] = [[
local content = args[2] and (fs.read(args[2]) or "") or (process._pipeInput or "")
local lines = {}
for line in (content .. "\n"):gmatch("([^\n]*)\n") do
	if line ~= "" then
		table.insert(lines, line)
	end
end
table.sort(lines)
for _, line in ipairs(lines) do
	tty.writeln(line)
end
return 0
]],
	["/bin/which.luau"] = [[
if not args[2] then
	return 1
end
for _, dir in ipairs({ "/bin", "/usr/bin", "/pkg/bin" }) do
	if fs.exists(dir .. "/" .. args[2]) then
		tty.writeln(dir .. "/" .. args[2])
		return 0
	elseif fs.exists(dir .. "/" .. args[2] .. ".luau") then
		tty.writeln(dir .. "/" .. args[2] .. ".luau")
		return 0
	end
end
tty.writeln(args[2] .. ": not found", tty.color(12, 0))
return 1
]],
	["/bin/find.luau"] = [[
local function walk(dir)
	local entries = fs.ls(dir)
	if not entries then
		return
	end
	for _, entry in ipairs(entries) do
		local path = (dir == "/" and "/" .. entry.name) or (dir .. "/" .. entry.name)
		if not args[2] or args[2]:find("-") == nil or dir:find(args[2]:gsub("^./", "")) then
			tty.writeln(path)
		end
		if entry.isDir then
			walk(path)
		end
	end
end

walk(args[2] or ".")
return 0
]],
	["/bin/head.luau"] = [[
local count = 10
local path
for i = 2, #args do
	if args[i] == "-n" then
		count = tonumber(args[i + 1]) or 10
	elseif not path then
		path = args[i]
	end
end

local content = path and (fs.read(path) or "") or (process._pipeInput or "")
local index = 0
for line in (content .. "\n"):gmatch("([^\n]*)\n") do
	if index >= count then
		break
	end
	tty.writeln(line)
	index = index + 1
end
return 0
]],
	["/bin/tail.luau"] = [[
local count = 10
local path
for i = 2, #args do
	if args[i] == "-n" then
		count = tonumber(args[i + 1]) or 10
	elseif not path then
		path = args[i]
	end
end

local content = path and (fs.read(path) or "") or (process._pipeInput or "")
local lines = {}
for line in (content .. "\n"):gmatch("([^\n]*)\n") do
	table.insert(lines, line)
end
for i = math.max(1, #lines - count + 1), #lines do
	tty.writeln(lines[i])
end
return 0
]],
	["/sbin/init.luau"] = [[
return 0
]],
	["/sbin/shutdown.luau"] = [[
tty.writeln("Shutting down...", tty.color(14, 0))
os.exit(0)
]],
	["/usr/bin/lua.luau"] = [[
tty.writeln("LuauVM Lua REPL. Use lua <file> to run scripts.", tty.color(11, 0))
if args[2] then
	local content = fs.read(args[2])
	if content and luauvm then
		local ok, fn = pcall(function()
			return luauvm.load(content, false)
		end)
		if ok and fn then
			local ran, err = pcall(fn)
			if not ran then
				tty.writeln(tostring(err), tty.color(12, 0))
			end
		end
	end
end
return 0
]],
	["/usr/bin/pkgmgr.luau"] = [[
if not pkgmgr then
	tty.writeln("pkgmgr: package manager unavailable", tty.color(12, 0))
	return 1
end

local sub = args[2]
if sub == "install" then
	for i = 3, #args do
		local ok, msg = pkgmgr.install(args[i])
		tty.writeln(ok and ("Installed: " .. args[i]) or ("Error: " .. tostring(msg)), ok and tty.color(10, 0) or tty.color(12, 0))
	end
elseif sub == "remove" then
	for i = 3, #args do
		local ok, msg = pkgmgr.remove(args[i])
		tty.writeln(ok and ("Removed: " .. args[i]) or ("Error: " .. tostring(msg)), ok and tty.color(10, 0) or tty.color(12, 0))
	end
elseif sub == "update" then
	local ok, msg = pkgmgr.update()
	tty.writeln(ok and "Package list updated." or ("Error: " .. tostring(msg)), ok and tty.color(10, 0) or tty.color(12, 0))
elseif sub == "list" then
	for _, p in ipairs(pkgmgr.list()) do
		tty.writeln(string.format("  %-20s %-10s %s", p.name, p.version, p.desc), p.installed and tty.color(10, 0) or tty.color(7, 0))
	end
elseif sub == "search" then
	for _, p in ipairs(pkgmgr.search(args[3] or "")) do
		tty.writeln(string.format("  %-20s %-10s %s", p.name, p.version, p.desc))
	end
else
	tty.writeln("usage: pkgmgr <install|remove|update|list|search> [package]")
	return 1
end

return 0
]],
}

function GuestPrograms.materialize(pragma)
	local materialized = {}
	for path, source in pairs(SOURCES) do
		materialized[path] = pragma .. "\n" .. source
	end
	return materialized
end

return GuestPrograms
