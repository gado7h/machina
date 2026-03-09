-- PackageDB module

local DB = {}

DB.packages = {

	--  coreutils
	{
		name = "coreutils",
		version = "9.1.0",
		desc = "Basic file/text/shell utilities",
		deps = {},
		size = 4200,
		files = {
			["/bin/seq"] = [[
local start = tonumber(args[2]) or 1
local stop  = tonumber(args[3])
local step  = 1
if not stop then stop = start; start = 1 end
if args[4]  then step = tonumber(args[3]); stop = tonumber(args[4]) end
local i = start
while (step > 0 and i <= stop) or (step < 0 and i >= stop) do
	print(i); i = i + step
end
]],
			["/bin/rev"] = [[
local s = args[2] or ""
if s == "" then s = io.read("l") or "" end
print(s:reverse())
]],
			["/bin/tr"] = [[
local from  = args[2] or ""
local to    = args[3] or ""
local input = io.read("*a") or ""
for i = 1, #from do
	local fc = from:sub(i,i):gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])","%%%1")
	local tc = to:sub(i,i) or ""
	input = input:gsub(fc, tc)
end
io.write(input)
]],
			["/bin/tac"] = [[
local lines = {}
for line in io.lines(args[2]) do table.insert(lines, 1, line) end
for _, l in ipairs(lines) do print(l) end
]],
			["/bin/basename"] = [[
local p    = args[2] or ""
local suf  = args[3]
local base = p:match("[^/]+$") or p
if suf and base:sub(-#suf) == suf then base = base:sub(1, -#suf-1) end
print(base)
]],
			["/bin/dirname"] = [[
local p   = args[2] or "."
local dir = p:match("^(.*)/[^/]+$") or "."
print(dir == "" and "/" or dir)
]],
			["/bin/realpath"] = [[
local p = args[2] or "."
print(p)
]],
			["/bin/numfmt"] = [[
local n        = tonumber(args[2]) or 0
local suffixes = {"","K","M","G","T"}
local i = 1
while n >= 1000 and i < #suffixes do n = n / 1000; i = i + 1 end
print(string.format("%.1f%s", n, suffixes[i]))
]],
			["/bin/shuf"] = [[
local lines = {}
for line in io.lines(args[2]) do table.insert(lines, line) end
for i = #lines, 2, -1 do
	local j = math.random(i)
	lines[i], lines[j] = lines[j], lines[i]
end
for _, l in ipairs(lines) do print(l) end
]],
		},
	},

	--  procps
	{
		name = "procps",
		version = "3.3.17",
		desc = "Process monitoring utilities (pmap, vmstat, iostat)",
		deps = {},
		size = 2100,
		files = {
			["/bin/pmap"] = [[
local pid = tonumber(args[2]) or process.pid
tty.writeln(string.format("%-6d: process %d memory map", pid, pid))
tty.writeln(string.format("%-18s %-8s %-8s %s","Address","Kbytes","Mode","Mapping"))
tty.writeln(string.format("%-18s %-8s %-8s %s","0x00100000","16","r-x--","[kernel]"))
tty.writeln(string.format("%-18s %-8s %-8s %s","0x00200000","64","rw---","[heap]"))
tty.writeln(string.format("%-18s %-8s %-8s %s","0x00700000","16","rw---","[stack]"))
]],
			["/bin/vmstat"] = [[
local free = 4194304
tty.writeln("procs ----------memory---------- ---swap-- -----io---- -system-- ------cpu-----")
tty.writeln(" r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st")
tty.writeln(string.format(" 1  0      0 %6d      0      0    0    0     0     0  100  50  5  2 93  0  0",
	math.floor(free/1024)))
]],
			["/bin/iostat"] = [[
tty.writeln("Linux " .. tostring(os.date()) .. "  (novamachine)  " .. os.date("%m/%d/%Y"))
tty.writeln("")
tty.writeln("avg-cpu:  %user   %nice %system %iowait  %steal   %idle")
tty.writeln("           5.00    0.00    2.00    0.00    0.00   93.00")
tty.writeln("")
tty.writeln("Device             tps    kB_read/s    kB_wrtn/s    kB_read    kB_wrtn")
tty.writeln("hda               0.00         0.00         0.00          0          0")
]],
		},
	},

	--  net-tools
	{
		name = "net-tools",
		version = "2.10",
		desc = "Networking tools: ifconfig, ping, netstat, route",
		deps = {},
		size = 1800,
		files = {
			["/bin/ifconfig"] = [[
local iface = args[2]
if not iface then
	tty.writeln("lo        Link encap:Local Loopback")
	tty.writeln("          inet addr:127.0.0.1  Mask:255.0.0.0")
	tty.writeln("          UP LOOPBACK RUNNING  MTU:65536  Metric:1")
	tty.writeln("")
	tty.writeln("eth0      Link encap:Ethernet  HWaddr 00:1A:2B:3C:4D:5E")
	tty.writeln("          inet addr:192.168.1.100  Bcast:192.168.1.255  Mask:255.255.255.0")
	tty.writeln("          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1")
else
	tty.writeln(iface .. ": error: no such device (simulated)")
end
]],
			["/bin/ping"] = [[
local host  = args[2] or "127.0.0.1"
local count = tonumber(args[3]) or 4
tty.writeln("PING " .. host .. " 56(84) bytes of data.")
for i = 1, count do
	local ms = math.random(1, 5)
	tty.writeln(string.format("64 bytes from %s: icmp_seq=%d ttl=64 time=%d.%02d ms",
		host, i, ms, math.random(0,99)))
end
tty.writeln(string.format("\n--- %s ping statistics ---", host))
tty.writeln(string.format("%d packets transmitted, %d received, 0%% packet loss", count, count))
]],
			["/bin/netstat"] = [[
tty.writeln("Active Internet connections (only servers)")
tty.writeln(string.format("%-5s %-10s %-10s %-22s %-22s %s",
	"Proto","Recv-Q","Send-Q","Local Address","Foreign Address","State"))
tty.writeln(string.format("%-5s %-10s %-10s %-22s %-22s %s",
	"tcp","0","0","0.0.0.0:22","0.0.0.0:*","LISTEN"))
tty.writeln(string.format("%-5s %-10s %-10s %-22s %-22s %s",
	"tcp","0","0","0.0.0.0:80","0.0.0.0:*","LISTEN"))
]],
			["/bin/route"] = [[
tty.writeln("Kernel IP routing table")
tty.writeln(string.format("%-16s %-16s %-16s %-6s %-6s %-6s %-8s %s",
	"Destination","Gateway","Genmask","Flags","Metric","Ref","Use","Iface"))
tty.writeln(string.format("%-16s %-16s %-16s %-6s %-6s %-6s %-8s %s",
	"192.168.1.0","0.0.0.0","255.255.255.0","U","100","0","0","eth0"))
tty.writeln(string.format("%-16s %-16s %-16s %-6s %-6s %-6s %-8s %s",
	"0.0.0.0","192.168.1.1","0.0.0.0","UG","100","0","0","eth0"))
]],
			["/bin/ss"] = [[
tty.writeln("Netid  State   Recv-Q  Send-Q  Local Address:Port  Peer Address:Port")
tty.writeln("tcp    LISTEN  0       128     0.0.0.0:22          0.0.0.0:*")
]],
			["/bin/wget"] = [[
tty.writeln("wget: network stack is simulated; real downloads not supported.", tty.color(14,0))
tty.writeln("To install software use: pkgmgr install <package>")
return 1
]],
			["/bin/curl"] = [[
tty.writeln("curl: network stack is simulated; real HTTP not supported.", tty.color(14,0))
return 1
]],
		},
	},

	--  textutils
	{
		name = "textutils",
		version = "1.4.0",
		desc = "Text processing: awk, sed, diff",
		deps = { "coreutils" },
		size = 3600,
		files = {
			["/bin/awk"] = [[
local prog   = args[2] or "{print}"
local infile = args[3]
local input  = infile and (io.open(infile,"r"):read("*a")) or io.read("*a") or ""
local beginProg = prog:match("BEGIN%s*{(.-)}")
local endProg   = prog:match("END%s*{(.-)}")
local mainProg  = prog:match("{(.-)}")
local function run(code, fields, NR, NF)
	if not code or code:match("^%s*$") then return end
	local sub = code:gsub("%$(%d+)", function(n)
		return '"'..(fields[tonumber(n)] or "")..'"'
	end):gsub("%$0", '"'..table.concat(fields," ")..'"')
	local fn = load("local NR,NF=...; "..sub)
	if fn then pcall(fn, NR, NF) end
end
if beginProg then run(beginProg, {}, 0, 0) end
local NR = 0
for line in (input.."\n"):gmatch("([^\n]*)\n") do
	NR = NR + 1
	local fields = {}
	for f in line:gmatch("%S+") do table.insert(fields, f) end
	if mainProg then run(mainProg, fields, NR, #fields) end
end
if endProg then run(endProg, {}, NR, 0) end
]],
			["/bin/sed"] = [[
local expr   = args[2] or ""
local infile = args[3]
local input  = infile and io.open(infile,"r"):read("*a") or io.read("*a") or ""
local pat, repl, flags = expr:match("^s/(.-)/(.-)/(.-)$")
if not pat then pat, repl = expr:match("^s/(.-)/(.-)/$"); flags = "" end
if not pat then
	local dpat = expr:match("^/(.-)/%s*d$")
	if dpat then
		for line in (input.."\n"):gmatch("([^\n]*)\n") do
			if not line:find(dpat) then print(line) end
		end
	else
		io.write(input)
	end
else
	local isGlobal = flags and flags:find("g")
	for line in (input.."\n"):gmatch("([^\n]*)\n") do
		local result
		if isGlobal then result = line:gsub(pat, repl)
		else result = line:gsub(pat, repl, 1) end
		print(result)
	end
end
]],
			["/bin/diff"] = [[
local f1 = io.open(args[2],"r")
local f2 = io.open(args[3],"r")
if not f1 or not f2 then tty.writeln("diff: missing file", tty.color(12,0)); return 1 end
local l1 = {} for l in f1:lines() do table.insert(l1, l) end
local l2 = {} for l in f2:lines() do table.insert(l2, l) end
local maxL = math.max(#l1, #l2)
for i = 1, maxL do
	local a = l1[i]; local b = l2[i]
	if a ~= b then
		if a then tty.writeln("< " .. a, tty.color(12,0)) end
		if b then tty.writeln("> " .. b, tty.color(10,0)) end
	end
end
]],
		},
	},

	--  lua-stdlib
	{
		name = "lua-stdlib",
		version = "41.2.2",
		desc = "Extended Lua libraries: json, base64, inspect, class, queue",
		deps = {},
		size = 5800,
		files = {
			["/usr/lib/json.lua"] = [[
local json = {}
function json.encode(v)
	local t = type(v)
	if t == "nil"     then return "null"
	elseif t == "boolean" then return tostring(v)
	elseif t == "number"  then return tostring(v)
	elseif t == "string"  then
		return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n')..'"'
	elseif t == "table" then
		local parts = {}
		if #v > 0 then
			for _, val in ipairs(v) do table.insert(parts, json.encode(val)) end
			return "["..table.concat(parts,",").."]"
		else
			for k, val in pairs(v) do
				table.insert(parts, '"'..tostring(k)..'":'..json.encode(val))
			end
			return "{"..table.concat(parts,",").."}"
		end
	end
	return "null"
end
function json.decode(s)
	s = s:match("^%s*(.-)%s*$")
	if s:sub(1,1) == "{" then
		local t = {}
		for k,v in s:gmatch('"(%w+)"%s*:%s*"([^"]*)"') do t[k]=v end
		for k,v in s:gmatch('"(%w+)"%s*:%s*(%d+%.?%d*)') do t[k]=tonumber(v) end
		for k,v in s:gmatch('"(%w+)"%s*:%s*(true)') do t[k]=true end
		for k,v in s:gmatch('"(%w+)"%s*:%s*(false)') do t[k]=false end
		return t
	elseif s:sub(1,1) == "[" then
		local t = {}
		for v in s:gmatch('"([^"]*)"') do table.insert(t,v) end
		return t
	elseif tonumber(s) then return tonumber(s)
	elseif s == "true" then return true
	elseif s == "false" then return false
	end
	return s:match('^"(.*)"$')
end
return json
]],
			["/usr/lib/base64.lua"] = [[
local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64 = {}
function b64.encode(s)
	local out = {}
	for i = 1, #s, 3 do
		local a = s:byte(i) or 0
		local b = s:byte(i+1) or 0
		local c = s:byte(i+2) or 0
		local n = a*65536 + b*256 + c
		table.insert(out, chars:sub(math.floor(n/262144)%64+1, math.floor(n/262144)%64+1))
		table.insert(out, chars:sub(math.floor(n/4096)%64+1,   math.floor(n/4096)%64+1))
		table.insert(out, i+1<=#s and chars:sub(math.floor(n/64)%64+1, math.floor(n/64)%64+1) or "=")
		table.insert(out, i+2<=#s and chars:sub(n%64+1, n%64+1) or "=")
	end
	return table.concat(out)
end
function b64.decode(s)
	local lut = {}
	for i = 1, #chars do lut[chars:sub(i,i)] = i-1 end
	local out = {}
	for i = 1, #s, 4 do
		local a = lut[s:sub(i,i)]   or 0
		local b = lut[s:sub(i+1,i+1)] or 0
		local c = lut[s:sub(i+2,i+2)] or 0
		local d = lut[s:sub(i+3,i+3)] or 0
		local n = a*262144 + b*4096 + c*64 + d
		table.insert(out, string.char(math.floor(n/65536)%256))
		if s:sub(i+2,i+2) ~= "=" then table.insert(out, string.char(math.floor(n/256)%256)) end
		if s:sub(i+3,i+3) ~= "=" then table.insert(out, string.char(n%256)) end
	end
	return table.concat(out)
end
return b64
]],
			["/usr/lib/inspect.lua"] = [[
local function inspect(v, depth, seen)
	depth = depth or 0; seen = seen or {}
	local t = type(v)
	if t == "table" then
		if seen[v] then return "<circular>" end
		seen[v] = true
		local parts = {}
		local indent = string.rep("  ", depth+1)
		for k, val in pairs(v) do
			table.insert(parts, indent..tostring(k).." = "..inspect(val, depth+1, seen))
		end
		return "{\n"..table.concat(parts,",\n").."\n"..string.rep("  ",depth).."}"
	elseif t == "string" then
		return '"'..v..'"'
	end
	return tostring(v)
end
return inspect
]],
			["/usr/lib/class.lua"] = [[
local function class(base)
	local cls = {}
	cls.__index = cls
	if base then setmetatable(cls, {__index=base}) end
	cls.new = function(...)
		local self = setmetatable({}, cls)
		if self.init then self:init(...) end
		return self
	end
	cls.is_a = function(self, klass)
		local mt = getmetatable(self)
		while mt do if mt==klass then return true end; mt=getmetatable(mt) end
		return false
	end
	return cls
end
return class
]],
			["/usr/lib/queue.lua"] = [[
local Queue = {}
Queue.__index = Queue
function Queue.new() return setmetatable({first=1,last=0,data={}}, Queue) end
function Queue:push(v) self.last=self.last+1; self.data[self.last]=v end
function Queue:pop()
	if self.first>self.last then return nil end
	local v=self.data[self.first]; self.data[self.first]=nil
	self.first=self.first+1; return v
end
function Queue:peek()  return self.data[self.first] end
function Queue:size()  return self.last - self.first + 1 end
function Queue:empty() return self.first > self.last end
return Queue
]],
		},
	},

	--  sysstat
	{
		name = "sysstat",
		version = "12.7.2",
		desc = "System performance monitoring tools (sar, mpstat)",
		deps = {},
		size = 1200,
		files = {
			["/bin/sar"] = [[
tty.writeln(string.format("Linux %s (%s)  %s  _%s_  (4 CPU)",
	"nova-1.0.0","novamachine",os.date("%m/%d/%Y"),"nova32"))
tty.writeln("")
tty.writeln(string.format("%-10s %-6s %-6s %-6s %-6s %-6s","Time","user","nice","system","iowait","idle"))
tty.writeln(string.format("%-10s %-6.2f %-6.2f %-6.2f %-6.2f %-6.2f",
	os.date("%H:%M:%S"),5.0,0.0,2.0,0.0,93.0))
]],
			["/bin/mpstat"] = [[
tty.writeln(string.format("Linux nova-1.0.0 (novamachine)  %s", os.date()))
tty.writeln(string.format("%-5s %-6s %-6s %-6s %-6s %-6s %-6s %-6s %-6s %-6s",
	"CPU","%usr","%nice","%sys","%iowait","%irq","%soft","%steal","%guest","%idle"))
for i = 0, 3 do
	tty.writeln(string.format("%-5d %-6.2f %-6.2f %-6.2f %-6.2f %-6.2f %-6.2f %-6.2f %-6.2f %-6.2f",
		i,5,0,2,0,0.1,0.05,0,0,92.85))
end
]],
		},
	},

	--  nano
	{
		name = "nano",
		version = "7.2",
		desc = "Simple terminal text editor",
		deps = {},
		size = 3400,
		files = {
			["/bin/nano"] = [[
local path = args[2]
if not path then tty.writeln("Usage: nano <file>"); return 1 end
local content = fs.exists(path) and (fs.read(path) or "") or ""
local lines = {}
for l in (content.."\n"):gmatch("([^\n]*)\n") do table.insert(lines, l) end
if #lines == 0 then lines = {""} end
local cols, rows = tty.size()
local curRow = 1; local curCol = 1; local topLine = 1; local modified = false
local clipLine = ""
local function render()
	tty.clear()
	tty.cursor(0, 0)
	tty.write(string.rep(" ", cols), tty.color(0, 7))
	tty.cursor(0, 0)
	local title = " GNU nano  7.2    " .. path .. (modified and " *" or "")
	tty.write(title:sub(1, cols), tty.color(0, 7))
	for row = 1, rows - 3 do
		local lineIdx = topLine + row - 1
		local line = lines[lineIdx] or ""
		tty.cursor(0, row)
		tty.write((line .. string.rep(" ", cols)):sub(1, cols), tty.color(7, 0))
	end
	local displayRow = curRow - topLine + 1
	if displayRow >= 1 and displayRow <= rows-3 then
		local line = lines[curRow] or ""
		local ch = line:sub(curCol, curCol)
		if ch == "" then ch = " " end
		tty.cursor(curCol - 1, displayRow)
		tty.write(ch, tty.color(0, 7))
	end
	tty.cursor(0, rows - 2)
	tty.write(string.rep(" ", cols), tty.color(0, 7))
	tty.cursor(0, rows - 2)
	tty.write(string.format(" [ Line %d/%d Col %d ]  ^X=Exit  ^S=Save  ^K=Cut  ^U=Paste",
		curRow, #lines, curCol):sub(1, cols), tty.color(0, 7))
end
local running = true
local function handleKey(ch)
	if not ch then return true end
	if ch == "\3" then
		if modified then fs.write(path, table.concat(lines, "\n")) end
		return false
	elseif ch == "\19" then
		fs.write(path, table.concat(lines, "\n")); modified = false
	elseif ch == "[UP]" then
		curRow = math.max(1, curRow - 1)
		if curRow < topLine then topLine = curRow end
		curCol = math.min(curCol, #(lines[curRow] or "") + 1)
	elseif ch == "[DOWN]" then
		curRow = math.min(#lines, curRow + 1)
		if curRow > topLine + rows - 4 then topLine = curRow - rows + 4 end
		curCol = math.min(curCol, #(lines[curRow] or "") + 1)
	elseif ch == "[LEFT]" then
		if curCol > 1 then curCol = curCol - 1
		elseif curRow > 1 then curRow=curRow-1; curCol=#(lines[curRow] or "")+1 end
	elseif ch == "[RIGHT]" then
		if curCol <= #(lines[curRow] or "") then curCol=curCol+1
		elseif curRow < #lines then curRow=curRow+1; curCol=1 end
	elseif ch == "\11" then
		clipLine = lines[curRow] or ""; table.remove(lines, curRow)
		if #lines == 0 then lines = {""} end
		curRow = math.min(curRow, #lines); modified = true
	elseif ch == "\21" then
		table.insert(lines, curRow, clipLine); modified = true
	elseif ch == "\n" or ch == "\r" then
		local line = lines[curRow] or ""
		lines[curRow] = line:sub(1, curCol-1)
		table.insert(lines, curRow+1, line:sub(curCol))
		curRow = curRow + 1; curCol = 1; modified = true
	elseif ch == "\b" then
		local line = lines[curRow] or ""
		if curCol > 1 then
			lines[curRow] = line:sub(1, curCol-2) .. line:sub(curCol)
			curCol = curCol - 1; modified = true
		elseif curRow > 1 then
			local prev = lines[curRow-1] or ""
			curCol = #prev + 1
			lines[curRow-1] = prev .. line
			table.remove(lines, curRow); curRow = curRow - 1; modified = true
		end
	elseif #ch == 1 and ch:byte(1) >= 32 then
		local line = lines[curRow] or ""
		lines[curRow] = line:sub(1, curCol-1) .. ch .. line:sub(curCol)
		curCol = curCol + 1; modified = true
	end
	return true
end
render()
local function poll()
	if not running then return end
	if syscall then
		local res = syscall(3, 0, 1)
		if res and res ~= "" then
			running = handleKey(res)
			render()
		end
	end
	if running then task.delay(0.04, poll) end
end
task.delay(0.04, poll)
return 0
]],
		},
	},

	--  desktop
	--  NOTE: postinst does NOT nest [[ ]] strings.
	--  The startx script is written via string concat.
	{
		name = "desktop",
		version = "1.2.0",
		desc = "NovaDE graphical desktop environment",
		deps = { "coreutils", "lua-stdlib" },
		size = 12000,
		files = {
			["/etc/desktop.conf"] = [[
DESKTOP=novade
WM=novawm
TERMINAL=nterm
]],

			["/usr/lib/novade/wallpaper.lua"] = [[
return function(DE)
	function DE:_drawWallpaper()
		local g = self.gpu
		local function packARGB(a, r, g2, b)
			return a * 16777216 + r * 65536 + g2 * 256 + b
		end

		for y = 0, 187 do
			local t = y / 187
			local r = math.floor(18 + (8 * t))
			local gr = math.floor(34 + (24 * t))
			local b = math.floor(48 + (60 * t))
			g:fillRect(0, y, 320, 1, packARGB(255, r, gr, b))
		end

		for y = 0, 187, 16 do
			for x = 0, 319, 16 do
				if ((x + y) / 16) % 2 == 0 then
					g:setPixel(x, y, packARGB(48, 255, 255, 255))
				end
			end
		end
	end
end
]],

			["/usr/lib/novade/taskbar.lua"] = [[
return function(DE)
	function DE:_drawTaskbar()
		local g = self.gpu

		local function packARGB(a, r, g2, b)
			return a * 16777216 + r * 65536 + g2 * 256 + b
		end

		local y = 188
		g:fillRect(0, y, 320, 12, packARGB(255, 10, 18, 30))
		g:fillRect(0, y, 320, 1, packARGB(255, 0, 220, 255))

		g:fillRect(2, y + 1, 30, 10, packARGB(255, 22, 44, 72))
		local title = "NOVA"
		for i = 1, #title do
			g:drawChar(
				4 + (i - 1) * 4,
				y + 2,
				title:sub(i, i),
				packARGB(255, 0, 240, 255),
				packARGB(255, 22, 44, 72)
			)
		end

		local timeStr = os.date("%H:%M")
		for i = 1, #timeStr do
			g:drawChar(
				298 + (i - 1) * 4,
				y + 2,
				timeStr:sub(i, i),
				packARGB(255, 180, 255, 180),
				packARGB(255, 10, 18, 30)
			)
		end
	end
end
]],

			["/usr/lib/novade/icons.lua"] = [[
return function(DE)
	function DE:_drawIcons()
		local g = self.gpu

		local function packARGB(a, r, g2, b)
			return a * 16777216 + r * 65536 + g2 * 256 + b
		end

		local icons = {
			{x=12,  y=20,  label="TERM",  char="T", color=packARGB(255,  0,220,255)},
			{x=52,  y=20,  label="FILES", char="F", color=packARGB(255,255,210,  0)},
			{x=92,  y=20,  label="TEXT",  char="E", color=packARGB(255,120,255,120)},
			{x=132, y=20,  label="PKG",   char="P", color=packARGB(255,255,140,  0)},
			{x=172, y=20,  label="INFO",  char="I", color=packARGB(255,210,100,255)},
		}

		for _, ic in ipairs(icons) do
			local bg = packARGB(255, 20, 34, 50)

			g:fillRect(ic.x, ic.y, 24, 20, bg)
			g:fillRect(ic.x, ic.y, 24, 1, ic.color)
			g:fillRect(ic.x, ic.y + 19, 24, 1, ic.color)
			g:fillRect(ic.x, ic.y, 1, 20, ic.color)
			g:fillRect(ic.x + 23, ic.y, 1, 20, ic.color)

			g:drawChar(ic.x + 10, ic.y + 6, ic.char, ic.color, bg)

			for i = 1, #ic.label do
				g:drawChar(
					ic.x + (i - 1) * 4,
					ic.y + 22,
					ic.label:sub(i, i),
					packARGB(255, 220, 220, 220),
					packARGB(255, 24, 44, 70)
				)
			end
		end
	end
end
]],

			["/usr/lib/novade/window.lua"] = [[
return function(DE)
	local function packARGB(a, r, g, b)
		return a * 16777216 + r * 65536 + g * 256 + b
	end

	local function clamp(n, lo, hi)
		if n < lo then return lo end
		if n > hi then return hi end
		return n
	end

	function DE:openWindow(title, x, y, w, h, content)
		local win = {
			title = title or "Window",
			x = clamp(x or 40, 0, 319),
			y = clamp(y or 30, 0, 199),
			w = clamp(w or 120, 40, 320),
			h = clamp(h or 80, 20, 200),
			content = content or {},
			visible = true,
		}

		table.insert(self.windows, win)
		self.focused = win
		self:_renderWindow(win)
		self.gpu:flush()
		return win
	end

	function DE:_renderWindow(win)
		local g = self.gpu
		local bg = packARGB(255, 12, 22, 36)
		local titleBG = packARGB(255, 28, 56, 92)
		local accent = packARGB(255, 0, 220, 255)
		local shadow = packARGB(120, 0, 0, 0)
		local white = packARGB(255, 255, 255, 255)
		local red = packARGB(255, 150, 16, 16)

		g:fillRect(win.x + 2, win.y + 2, win.w, win.h, shadow)
		g:fillRect(win.x, win.y, win.w, win.h, bg)
		g:fillRect(win.x, win.y, win.w, 10, titleBG)
		g:fillRect(win.x, win.y, win.w, 1, accent)
		g:fillRect(win.x, win.y, 1, win.h, accent)
		g:fillRect(win.x + win.w - 1, win.y, 1, win.h, accent)
		g:fillRect(win.x, win.y + win.h - 1, win.w, 1, accent)

		for i = 1, math.min(#win.title, math.floor((win.w - 14) / 4)) do
			g:drawChar(win.x + 2 + (i - 1) * 4, win.y + 2, win.title:sub(i, i), accent, titleBG)
		end

		g:fillRect(win.x + win.w - 10, win.y + 1, 8, 8, red)
		g:drawChar(win.x + win.w - 9, win.y + 1, "X", white, red)

		local cy = win.y + 12
		for _, line in ipairs(win.content) do
			line = tostring(line)
			if cy + 8 >= win.y + win.h - 2 then
				break
			end
			for j = 1, math.min(#line, math.floor((win.w - 4) / 4)) do
				g:drawChar(win.x + 2 + (j - 1) * 4, cy, line:sub(j, j), packARGB(255, 210, 255, 210), bg)
			end
			cy = cy + 9
		end
	end
end
]],

			["/usr/lib/novade/init.lua"] = [[
local DE = {}
DE.__index = DE

function DE.new(kernel)
	local self = setmetatable({}, DE)
	self.kernel = kernel
	self.gpu = kernel.gpu
	self.windows = {}
	self.focused = nil
	return self
end

function DE:start()
	if not self.gpu then
		return false, "GPU unavailable"
	end

	self.gpu:setMode("PIXEL")
	self:_drawWallpaper()
	self:_drawTaskbar()
	self:_drawIcons()
	self.gpu:flush()
	return true
end

local function loadPart(kernel, path)
	local src = kernel.vfs:readFileStr(path)
	if not src then
		error("missing NovaDE part: " .. path)
	end

	local vm = kernel.machine and kernel.machine.luauvm
	if not vm then
		error("LuauVM unavailable")
	end

	local fn = vm(src, false, {
		string = string,
		math = math,
		table = table,
		pairs = pairs,
		ipairs = ipairs,
		tostring = tostring,
		tonumber = tonumber,
		type = type,
		os = os,
	})
	return fn()
end

loadPart(kernel, "/usr/lib/novade/wallpaper.lua")(DE)
loadPart(kernel, "/usr/lib/novade/taskbar.lua")(DE)
loadPart(kernel, "/usr/lib/novade/icons.lua")(DE)
loadPart(kernel, "/usr/lib/novade/window.lua")(DE)

return DE
]],

			["/bin/novade"] = [[
tty.writeln("Launching NovaDE...", tty.color(11, 0))
local ok = os.execute("__host_activate_desktop__")
if ok then
	tty.writeln("NovaDE activated.", tty.color(10, 0))
	return 0
end
tty.writeln("novade: desktop activation failed", tty.color(12, 0))
return 1
]],

			["/bin/startx"] = [[
tty.writeln("Starting NovaDE...", tty.color(11, 0))
local rc = process.exec("novade")
if rc ~= 0 then
	tty.writeln("startx: novade failed", tty.color(12, 0))
	return rc or 1
end
return 0
]],
		},
	},

	--  dev-tools
	{
		name = "dev-tools",
		version = "1.0.0",
		desc = "Development tools: luac, hexdump, strings, md5sum, strace",
		deps = { "lua-stdlib" },
		size = 5000,
		files = {
			["/bin/luac"] = [[
local src = args[2]
local out = args[3] or (src and src:gsub("%.lua$","")..".luac")
if not src then tty.writeln("usage: luac <source.lua> [output]"); return 1 end
local content = fs.read(src)
if not content then tty.writeln("luac: cannot read "..src); return 1 end
if not luauvm  then tty.writeln("luac: LuauVM not available"); return 1 end
local bc = luauvm.compile(content)
fs.write(out, bc)
tty.writeln(string.format("luac: %s -> %s (%d bytes)", src, out, #bc))
return 0
]],
			["/bin/hexdump"] = [[
local src = args[2]
if not src then tty.writeln("usage: hexdump <file>"); return 1 end
local content = fs.read(src)
if not content then tty.writeln("hexdump: cannot read "..src); return 1 end
local offset = 0
while offset < #content do
	local hex = {}; local asc = {}
	for i = offset+1, math.min(offset+16, #content) do
		local b = content:byte(i)
		table.insert(hex, string.format("%02x", b))
		table.insert(asc, (b >= 32 and b < 127) and string.char(b) or ".")
	end
	while #hex < 16 do table.insert(hex, "  ") end
	tty.writeln(string.format("%08x  %-23s  %-23s  |%s|",
		offset,
		table.concat({table.unpack(hex,1,8)}, " "),
		table.concat({table.unpack(hex,9,16)}, " "),
		table.concat(asc)))
	offset = offset + 16
end
return 0
]],
			["/bin/strings"] = [[
local src = args[2]
if not src then tty.writeln("usage: strings <file>"); return 1 end
local content = fs.read(src)
if not content then tty.writeln("strings: cannot read "..src); return 1 end
local run = ""
for i = 1, #content do
	local b = content:byte(i)
	if b >= 32 and b < 127 then
		run = run .. string.char(b)
	else
		if #run >= 4 then tty.writeln(run) end
		run = ""
	end
end
if #run >= 4 then tty.writeln(run) end
return 0
]],
			-- FNV-1a hash using bit32.bxor — no ~ operator
			["/bin/md5sum"] = [[
local function fnv1a(s)
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, s:byte(i)) * 16777619 % 4294967296
	end
	return string.format("%08x%08x%08x%08x",
		h,
		bit32.bxor(h, 0xDEAD),
		bit32.bxor(h, 0xBEEF),
		bit32.bxor(h, 0xCAFE))
end
for i = 2, #args do
	local content = fs.read(args[i]) or ""
	tty.writeln(fnv1a(content) .. "  " .. args[i])
end
return 0
]],
			["/bin/strace"] = [[
tty.writeln("strace: attaching to PID "..(args[2] or tostring(process.pid)), tty.color(11,0))
tty.writeln('[  0.000] execve("'..(args[2] or "/bin/sh")..'", [], []) = 0')
tty.writeln("[  0.001] brk(0) = 0x00200000")
tty.writeln('[  0.002] open("/etc/ld.so.cache", O_RDONLY) = 3')
tty.writeln("[  0.003] close(3) = 0")
tty.writeln('[  0.004] read(0, "", 4096) = 0')
tty.writeln('[  0.005] write(1, "ready\\n", 6) = 6')
tty.writeln("--- strace: end of trace ---")
return 0
]],
		},
	},

	--  games
	{
		name = "games",
		version = "1.1.0",
		desc = "Terminal games: mandelbrot, tictactoe, life",
		deps = {},
		size = 5200,
		files = {
			["/bin/mandelbrot"] = [[
local function tclear()
	if tty and tty.clear then tty.clear() end
end

local function twrite(s, c)
	if tty and tty.writeln then tty.writeln(s, c) else print(s) end
end

local cols, rows = 80, 25
if tty and tty.size then
	cols, rows = tty.size()
end

local W = math.max(10, cols - 1)
local H = math.max(4, rows - 4)
local x1, x2 = -2.5, 1.0
local y1, y2 = -1.1, 1.1
local maxIter = 32
local chars = " .,:-=+*#%@"

tclear()
twrite("Mandelbrot Set")

for row = 0, H - 1 do
	local cy = y1 + (y2 - y1) * (row / H)
	local lineChars = {}
	for col = 0, W - 1 do
		local cx = x1 + (x2 - x1) * (col / W)
		local zx, zy = 0, 0
		local iter = 0
		while zx * zx + zy * zy <= 4 and iter < maxIter do
			local tmp = zx * zx - zy * zy + cx
			zy = 2 * zx * zy + cy
			zx = tmp
			iter = iter + 1
		end
		local ci = math.floor(iter / maxIter * (#chars - 1)) + 1
		lineChars[#lineChars + 1] = chars:sub(ci, ci)
	end
	twrite(table.concat(lineChars))
end

return 0
]],

			["/bin/tictactoe"] = [[
local function tclear()
	if tty and tty.clear then tty.clear() end
end

local function twrite(s, c)
	if tty and tty.writeln then tty.writeln(s, c) else print(s) end
end

local function tread()
	if syscall then
		local a, b = syscall(3, 0, 1)
		if type(a) == "string" then
			return a
		end
		if type(b) == "string" then
			return b
		end
	end
	if io and io.read then
		return io.read(1)
	end
	return nil
end

local board = {" "," "," "," "," "," "," "," "," "}
local running = true
local moveCount = 0

local function draw()
	tclear()
	twrite("TicTacToe  You=X  CPU=O", tty and tty.color and tty.color(11,0) or nil)
	twrite("")
	twrite(" " .. board[1] .. " | " .. board[2] .. " | " .. board[3])
	twrite("---+---+---")
	twrite(" " .. board[4] .. " | " .. board[5] .. " | " .. board[6])
	twrite("---+---+---")
	twrite(" " .. board[7] .. " | " .. board[8] .. " | " .. board[9])
	twrite("")
	twrite("Press 1-9 to place. Ctrl+C to quit.")
end

local function winner(p)
	local lines = {
		{1,2,3},{4,5,6},{7,8,9},
		{1,4,7},{2,5,8},{3,6,9},
		{1,5,9},{3,5,7},
	}
	for _, line in ipairs(lines) do
		if board[ line[1] ] == p and board[line[2] ] == p and board[ line[3] ] == p then
			return true
		end
	end
	return false
end

local function full()
	for i = 1, 9 do
		if board[i] == " " then
			return false
		end
	end
	return true
end

local function bestMoveFor(p)
	local lines = {
		{1,2,3},{4,5,6},{7,8,9},
		{1,4,7},{2,5,8},{3,6,9},
		{1,5,9},{3,5,7},
	}
	for _, line in ipairs(lines) do
		local a, b, c = line[1], line[2], line[3]
		local vals = {board[a], board[b], board[c]}
		local countP, countEmpty, emptyIdx = 0, 0, nil
		for i = 1, 3 do
			if vals[i] == p then countP = countP + 1 end
			if vals[i] == " " then
				countEmpty = countEmpty + 1
				emptyIdx = line[i]
			end
		end
		if countP == 2 and countEmpty == 1 then
			return emptyIdx
		end
	end
	return nil
end

local function cpuMove()
	local move =
		bestMoveFor("O") or
		bestMoveFor("X") or
		(board[5] == " " and 5) or
		nil

	if not move then
		for _, idx in ipairs({1,3,7,9,2,4,6,8}) do
			if board[idx] == " " then
				move = idx
				break
			end
		end
	end

	if move then
		board[move] = "O"
	end
end

draw()

local function poll()
	if not running then
		return
	end

	local ch = tread()
	if ch and ch ~= "" then
		if ch == "\3" then
			running = false
			twrite("Quit.")
			return
		end

		local n = tonumber(ch)
		if n and n >= 1 and n <= 9 and board[n] == " " then
			board[n] = "X"
			moveCount = moveCount + 1
			draw()

			if winner("X") then
				twrite("")
				twrite("You win.", tty and tty.color and tty.color(10,0) or nil)
				running = false
				return
			end

			if full() then
				twrite("")
				twrite("Draw.")
				running = false
				return
			end

			cpuMove()
			draw()

			if winner("O") then
				twrite("")
				twrite("CPU wins.", tty and tty.color and tty.color(12,0) or nil)
				running = false
				return
			end

			if full() then
				twrite("")
				twrite("Draw.")
				running = false
				return
			end
		end
	end

	if running and task and task.delay then
		task.delay(0.08, poll)
	end
end

if task and task.delay then
	task.delay(0.08, poll)
else
	return 0
end

return 0
]],

			["/bin/life"] = [[
local function tclear()
	if tty and tty.clear then tty.clear() end
end

local function twrite(s, c)
	if tty and tty.writeln then tty.writeln(s, c) else print(s) end
end

local cols, rows = 80, 25
if tty and tty.size then
	cols, rows = tty.size()
end

local W = math.max(10, cols)
local H = math.max(4, rows - 3)
local grid = {}
local gen = 0
local running = true

for y = 1, H do
	grid[y] = {}
	for x = 1, W do
		grid[y][x] = math.random() < 0.28
	end
end

local function step()
	local nxt = {}
	for y = 1, H do
		nxt[y] = {}
		for x = 1, W do
			local n = 0
			for dy = -1, 1 do
				for dx = -1, 1 do
					if not (dx == 0 and dy == 0) then
						local ny = ((y + dy - 1) % H) + 1
						local nx = ((x + dx - 1) % W) + 1
						if grid[ny][nx] then
							n = n + 1
						end
					end
				end
			end
			local alive = grid[y][x]
			nxt[y][x] = (n == 3) or (alive and n == 2)
		end
	end
	grid = nxt
	gen = gen + 1
end

local function render()
	tclear()
	twrite("Conway's Game of Life  Gen:" .. tostring(gen))
	for y = 1, H do
		local row = {}
		for x = 1, W do
			row[x] = grid[y][x] and "#" or " "
		end
		twrite(table.concat(row))
	end
end

local ticks = 0
local function tick()
	if not running or ticks >= 180 then
		return
	end
	step()
	render()
	ticks = ticks + 1
	if task and task.delay then
		task.delay(0.12, tick)
	end
end

render()
if task and task.delay then
	task.delay(0.12, tick)
end

return 0
]],
		},
	},
}

-- Index by name
local index = {}
for _, pkg in ipairs(DB.packages) do
	index[pkg.name] = pkg
end

function DB.get(name)
	return index[name]
end
function DB.getAll()
	return DB.packages
end
function DB.search(query)
	local results = {}
	local q = query:lower()
	for _, pkg in ipairs(DB.packages) do
		if pkg.name:lower():find(q, 1, true) or pkg.desc:lower():find(q, 1, true) then
			table.insert(results, pkg)
		end
	end
	return results
end

return DB
