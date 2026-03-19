-- Syscall module

local Syscall = {}
Syscall.__index = Syscall

-- Syscall numbers
Syscall.SYS = {
	-- Process
	exit = 1,
	fork = 2,
	read = 3,
	write = 4,
	open = 5,
	close = 6,
	waitpid = 7,
	execv = 11,
	getpid = 20,
	getppid = 64,
	kill = 37,
	signal = 48,
	nice = 34,
	pause = 29,
	alarm = 27,
	-- Memory
	brk = 45,
	mmap = 90,
	munmap = 91,
	mprotect = 125,
	-- Filesystem
	creat = 8,
	link = 9,
	unlink = 10,
	chdir = 12,
	getcwd = 183,
	mkdir = 39,
	rmdir = 40,
	rename = 38,
	stat = 106,
	fstat = 108,
	lstat = 107,
	lseek = 19,
	dup = 41,
	dup2 = 63,
	pipe = 42,
	-- I/O
	ioctl = 54,
	select = 82,
	poll = 168,
	-- Time
	time = 13,
	stime = 25,
	times = 43,
	gettimeofday = 78,
	nanosleep = 162,
	-- System
	uname = 122,
	reboot = 88,
	sync = 36,
	mount = 21,
	umount = 22,
	getuid = 24,
	setuid = 23,
	getgid = 47,
	setgid = 46,
	sysinfo = 116,
	-- IPC
	semget = 64,
	semop = 65,
	shmget = 29,
	-- Network (stub)
	socket = 359,
	bind = 361,
	listen = 363,
	accept = 364,
	connect = 362,
	send = 369,
	recv = 370,
}

-- Error codes
Syscall.E = {
	EPERM = 1,
	ENOENT = 2,
	ESRCH = 3,
	EINTR = 4,
	EIO = 5,
	ENXIO = 6,
	ENOEXEC = 8,
	EBADF = 9,
	ECHILD = 10,
	EAGAIN = 11,
	ENOMEM = 12,
	EACCES = 13,
	EFAULT = 14,
	EBUSY = 16,
	EEXIST = 17,
	ENOTDIR = 20,
	EISDIR = 21,
	EINVAL = 22,
	ENOSPC = 28,
	ENOSYS = 38,
}

local E = Syscall.E

function Syscall.new(kernel)
	local self = setmetatable({}, Syscall)
	self.kernel = kernel
	self.pm = kernel.pm
	self.mm = kernel.mm
	self.vfs = kernel.vfs
	self.drivers = kernel.drivers
	self._openFiles = {} -- fd table (global, keyed by "pid:fd")
	self._pipes = {} -- pipe id → {buf={}, readers=n, writers=n}
	self._nextPipe = 1
	return self
end

function Syscall:_keyboardReadChar()
	local keyboard = self.drivers and self.drivers.keyboard
	if keyboard and keyboard.readChar then
		return keyboard:readChar()
	end
	return nil
end

function Syscall:_consoleWrite(text, attr)
	local console = self.drivers and self.drivers.console
	if console and console.print then
		console:print(text, attr)
		return true
	end
	return false
end

--  Main dispatch

--- Dispatch a syscall.
--- pid: calling process pid
--- num: syscall number
--- ...: arguments
function Syscall:call(pid, num, ...)
	local SYS = Syscall.SYS
	local args = { ... }

	-- Get PCB
	local pcb = self.pm:getProcess(pid)
	if not pcb then
		return -E.ESRCH
	end

	-- Dispatch
	if num == SYS.exit then
		self.pm:exit(pid, args[1] or 0)
		return 0
	elseif num == SYS.getpid then
		return pid
	elseif num == SYS.getppid then
		return pcb.ppid or 0
	elseif num == SYS.getuid then
		return pcb.uid or 0
	elseif num == SYS.getgid then
		return pcb.gid or 0
	elseif num == SYS.fork then
		return self:_sysFork(pid)
	elseif num == SYS.execv then
		return self:_sysExecv(pid, args[1], args[2])
	elseif num == SYS.kill then
		local targetPid = args[1]
		local sig = args[2] or 15
		local ok = self.pm:sendSignal(targetPid, sig)
		return ok and 0 or -E.ESRCH
	elseif num == SYS.nice then
		local inc = args[1] or 0
		pcb.nice = math.max(-20, math.min(19, (pcb.nice or 0) + inc))
		return pcb.nice
	elseif num == SYS.waitpid then
		return self:_sysWaitpid(pid, args[1], args[2])
	elseif num == SYS.write then
		return self:_sysWrite(pid, args[1], args[2])
	elseif num == SYS.read then
		return self:_sysRead(pid, args[1], args[2])
	elseif num == SYS.open then
		return self:_sysOpen(pid, args[1], args[2])
	elseif num == SYS.close then
		return self:_sysClose(pid, args[1])
	elseif num == SYS.creat then
		return self:_sysCreat(pid, args[1])
	elseif num == SYS.unlink then
		local ok, err = self.vfs:remove(args[1])
		return ok and 0 or -E.ENOENT
	elseif num == SYS.mkdir then
		local ok, err = self.vfs:mkdir(args[1])
		return ok and 0 or -E.EEXIST
	elseif num == SYS.rmdir then
		local ok = self.vfs:remove(args[1])
		return ok and 0 or -E.ENOENT
	elseif num == SYS.rename then
		-- Read+write+delete
		local data = self.vfs:readFile(args[1])
		if not data then
			return -E.ENOENT
		end
		self.vfs:writeFile(args[2], data)
		self.vfs:remove(args[1])
		return 0
	elseif num == SYS.chdir then
		local path = args[1]
		if not self.vfs:exists(path) then
			return -E.ENOENT
		end
		local s = self.vfs:stat(path)
		if not s or not s.isDir then
			return -E.ENOTDIR
		end
		pcb.cwd = path
		return 0
	elseif num == SYS.getcwd then
		return pcb.cwd or "/"
	elseif num == SYS.stat then
		local st = self.vfs:stat(args[1])
		if not st then
			return -E.ENOENT
		end
		return st
	elseif num == SYS.time then
		return os.time and os.time() or 0
	elseif num == SYS.gettimeofday then
		local t = os.time and os.time() or 0
		return { sec = t, usec = 0 }
	elseif num == SYS.nanosleep then
		-- args[1] = seconds (float ok)
		self.pm:sleep(pid, args[1] or 0)
		return 0
	elseif num == SYS.mmap then
		local addr, err2 = self.mm:mmap(pid, args[1] or 4096, nil, args[2])
		if not addr then
			return -E.ENOMEM
		end
		return addr
	elseif num == SYS.munmap then
		self.mm:munmap(pid, args[1])
		return 0
	elseif num == SYS.brk then
		-- Simple brk: just mmap more memory
		if args[1] and args[1] > 0 then
			local a = self.mm:mmap(pid, args[1], nil, "[heap]")
			return a or -E.ENOMEM
		end
		return 0
	elseif num == SYS.pipe then
		return self:_sysPipe(pid)
	elseif num == SYS.dup then
		return self:_sysDup(pid, args[1])
	elseif num == SYS.dup2 then
		return self:_sysDup2(pid, args[1], args[2])
	elseif num == SYS.uname then
		return {
			sysname = self.kernel.config.OS_NAME,
			nodename = self.kernel.config.HOSTNAME,
			release = self.kernel.config.KERNEL_VERSION,
			version = "#1 SMP " .. os.date("%Y-%m-%d"),
			machine = self.kernel.config.ARCH,
		}
	elseif num == SYS.sysinfo then
		local mem = self.mm:getMemInfo()
		local uptime = os.clock()
		return {
			uptime = math.floor(uptime),
			totalram = mem.total,
			freeram = mem.free,
			procs = #self.pm:getProcessList(),
		}
	elseif num == SYS.sync then
		-- No-op in simulation (disk always consistent)
		return 0
	elseif num == SYS.reboot then
		-- Signal kernel to reboot
		self.kernel:reboot()
		return 0
	elseif num == SYS.ioctl then
		return self:_sysIoctl(pid, args[1], args[2], args[3])
	elseif num == SYS.socket then
		return -E.ENOSYS -- not yet implemented
	else
		return -E.ENOSYS
	end
end

--  File descriptor operations

function Syscall:_fdKey(pid, fd)
	return pid .. ":" .. fd
end

function Syscall:_sysOpen(pid, path, flags)
	local pcb = self.pm:getProcess(pid)
	if not pcb then
		return -E.ESRCH
	end

	-- Resolve absolute path
	if path:sub(1, 1) ~= "/" then
		path = (pcb.cwd or "/") .. "/" .. path
	end
	-- Normalize double slashes
	path = path:gsub("//+", "/")

	local s = self.vfs:stat(path)
	if not s then
		-- O_CREAT flag (bit 6 = 64)
		if flags and (bit32.band(flags, 64)) ~= 0 then
			local ok = self.vfs:writeFile(path, {})
			if not ok then
				return -E.EIO
			end
			s = self.vfs:stat(path)
		else
			return -E.ENOENT
		end
	end

	local fd = pcb.nextFd
	pcb.nextFd = pcb.nextFd + 1
	pcb.fds[fd] = {
		type = s.isDir and "dir" or "file",
		path = path,
		flags = flags or 0,
		offset = 0,
		readable = true,
		writable = flags and (bit32.band(flags, 2)) ~= 0 or false,
		isDir = s.isDir,
	}
	return fd
end

function Syscall:_sysClose(pid, fd)
	local pcb = self.pm:getProcess(pid)
	if not pcb then
		return -E.ESRCH
	end
	if not pcb.fds[fd] then
		return -E.EBADF
	end
	pcb.fds[fd] = nil
	return 0
end

function Syscall:_sysCreat(pid, path)
	return self:_sysOpen(pid, path, 0x41) -- O_CREAT|O_WRONLY
end

function Syscall:_sysRead(pid, fd, count)
	local pcb = self.pm:getProcess(pid)
	if not pcb then
		return -E.ESRCH
	end

	local fde = pcb.fds[fd]
	if not fde then
		return -E.EBADF
	end

	if fd == 0 then
		local ch = self:_keyboardReadChar()
		if ch then
			return ch, 1
		end
		return "", 0
	end

	if fde.type == "file" then
		local data = self.vfs:readFile(fde.path)
		if not data then
			return -E.EIO
		end
		local off = fde.offset
		local available = #data - off
		local toRead = math.min(count or available, available)
		if toRead <= 0 then
			return "", 0
		end
		local out = {}
		for i = off + 1, off + toRead do
			table.insert(out, string.char(data[i] or 0))
		end
		fde.offset = fde.offset + toRead
		return table.concat(out), toRead
	end

	return -E.EINVAL
end

function Syscall:_sysWrite(pid, fd, data)
	local pcb = self.pm:getProcess(pid)
	if not pcb then
		return -E.ESRCH
	end

	local fde = pcb.fds[fd]
	if not fde and fd ~= 1 and fd ~= 2 then
		return -E.EBADF
	end

	local str = (type(data) == "table") and table.concat(data) or tostring(data)

	if fd == 1 or fd == 2 then
		-- stdout/stderr → GPU terminal
		local attr = (fd == 2) and 0x0C or 0x07
		self:_consoleWrite(str, attr)
		return #str
	end

	if fde and fde.type == "file" then
		local bytes = {}
		for i = 1, #str do
			bytes[i] = string.byte(str, i)
		end
		-- Write at offset
		if fde.offset == 0 then
			self.vfs:writeFile(fde.path, bytes)
		else
			-- Append
			local existing = self.vfs:readFile(fde.path) or {}
			for i, b in ipairs(bytes) do
				existing[fde.offset + i] = b
			end
			self.vfs:writeFile(fde.path, existing)
		end
		fde.offset = fde.offset + #bytes
		return #bytes
	end

	return -E.EINVAL
end

function Syscall:_sysFork(pid)
	local parent = self.pm:getProcess(pid)
	if not parent then
		return -E.ESRCH
	end

	local childPid, err = self.pm:spawn(
		parent.name,
		function(p)
			coroutine.yield()
		end, -- child continues from yield
		pid,
		parent.priority,
		parent.uid,
		-- Copy env
		(function()
			local e = {}
			for k, v in pairs(parent.env) do
				e[k] = v
			end
			return e
		end)()
	)
	if not childPid then
		return -E.ENOMEM
	end

	local child = self.pm:getProcess(childPid)
	child.cwd = parent.cwd
	-- Copy file descriptors (table field copy, not array unpack).
	for k, v in pairs(parent.fds) do
		if type(v) == "table" then
			local copy = {}
			for fk, fv in pairs(v) do
				copy[fk] = fv
			end
			child.fds[k] = copy
		else
			child.fds[k] = v
		end
	end
	child.nextFd = parent.nextFd

	return childPid -- parent gets child pid; child gets 0 (on resume)
end

function Syscall:_sysExecv(pid, path, argv)
	-- In our model, execv just looks up the command in the kernel's command table
	-- and replaces the process body.  The Shell handles this directly.
	return -E.ENOSYS -- handled at Shell level
end

function Syscall:_sysWaitpid(pid, targetPid, opts)
	local parent = self.pm:getProcess(pid)
	if not parent then
		return -E.ESRCH
	end

	if targetPid and targetPid > 0 then
		local code = self.pm:reap(targetPid)
		if code then
			return targetPid, code
		end
		return -E.ECHILD
	end
	-- Wait for any child
	for _, childPid in ipairs(parent.children) do
		local child = self.pm:getProcess(childPid)
		if child and child.state == self.pm.STATE.ZOMBIE then
			local code = self.pm:reap(childPid)
			return childPid, code or 0
		end
	end
	return -E.ECHILD
end

function Syscall:_sysPipe(pid)
	local pcb = self.pm:getProcess(pid)
	if not pcb then
		return -E.ESRCH
	end

	local pipeId = self._nextPipe
	self._nextPipe = self._nextPipe + 1
	self._pipes[pipeId] = { buf = {}, readers = 1, writers = 1 }

	local readFd = pcb.nextFd
	pcb.nextFd = pcb.nextFd + 1
	local writeFd = pcb.nextFd
	pcb.nextFd = pcb.nextFd + 1

	pcb.fds[readFd] = { type = "pipe", pipeId = pipeId, readable = true, writable = false }
	pcb.fds[writeFd] = { type = "pipe", pipeId = pipeId, readable = false, writable = true }

	return readFd, writeFd
end

function Syscall:_sysDup(pid, oldFd)
	local pcb = self.pm:getProcess(pid)
	if not pcb or not pcb.fds[oldFd] then
		return -E.EBADF
	end
	local newFd = pcb.nextFd
	pcb.nextFd = pcb.nextFd + 1
	pcb.fds[newFd] = pcb.fds[oldFd] -- shared reference
	return newFd
end

function Syscall:_sysDup2(pid, oldFd, newFd)
	local pcb = self.pm:getProcess(pid)
	if not pcb or not pcb.fds[oldFd] then
		return -E.EBADF
	end
	if pcb.fds[newFd] then
		pcb.fds[newFd] = nil
	end
	pcb.fds[newFd] = pcb.fds[oldFd]
	return newFd
end

function Syscall:_sysIoctl(pid, fd, request, arg)
	-- TIOCGWINSZ (get terminal size) = 0x5413
	if request == 0x5413 then
		local rows = self.kernel.config.TEXT_ROWS
		local cols = self.kernel.config.TEXT_COLS
		local console = self.drivers and self.drivers.console
		if console and console.size then
			cols, rows = console:size()
		end
		return { rows = rows, cols = cols }
	end
	return -E.EINVAL
end

return Syscall
