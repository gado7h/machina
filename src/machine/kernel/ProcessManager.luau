-- ProcessManager module

local PM = {}
PM.__index = PM

-- Process states
PM.STATE = {
	RUNNING = "R",
	READY = "S", -- "runnable" / sleeping interruptibly
	SLEEPING = "D", -- uninterruptible sleep (I/O wait)
	ZOMBIE = "Z",
	STOPPED = "T",
}

-- Signal numbers
PM.SIG = {
	SIGHUP = 1,
	SIGINT = 2,
	SIGQUIT = 3,
	SIGKILL = 9,
	SIGTERM = 15,
	SIGCHLD = 17,
	SIGSTOP = 19,
	SIGCONT = 18,
}

local MAX_PID = 65535

function PM.new(config, memMgr)
	local self = setmetatable({}, PM)
	self.config = config
	self.memMgr = memMgr
	self._procs = {} -- pid → PCB
	self._runQ = { {}, {}, {}, {} } -- 4 priority queues (0=highest)
	self._nextPid = 1
	self._currentPid = nil
	self._idlePid = nil
	self._tickCount = 0

	self.stats = {
		totalCreated = 0,
		totalExited = 0,
		contextSwitches = 0,
		schedCalls = 0,
	}
	return self
end

--  PCB creation

--- Create a new process.
--- body: function(process) called as the process coroutine
--- Returns pid or nil, err
function PM:spawn(name, body, ppid, priority, uid, env)
	local pid = self:_allocPid()
	if not pid then
		return nil, "pid exhausted"
	end

	priority = priority or 2 -- default normal priority (0-3)
	uid = uid or 1000

	-- Allocate user-space memory for this process
	local mem = nil
	if self.memMgr then
		mem = self.memMgr:allocPages(4) -- 4 pages = 16KB per process default
	end

	local pcb = {
		pid = pid,
		name = name,
		ppid = ppid or 0,
		state = PM.STATE.READY,
		priority = priority, -- 0..3 (0=highest)
		nice = 0, -- -20..+19 Unix nice
		uid = uid,
		gid = uid,
		cwd = "/",
		env = env or {},
		mem = mem, -- MemBlock from MemoryManager
		-- CPU context (saved on context switch)
		ctx = {
			regs = {}, -- register snapshot
			pc = 0,
			sp = mem and (mem.base + mem.size - 4) or 0,
			flags = 0,
		},
		-- Timing
		startTime = os.clock(),
		cpuTime = 0,
		lastSched = 0,
		-- File descriptors
		fds = {
			[0] = { type = "stdin", readable = true, writable = false },
			[1] = { type = "stdout", readable = false, writable = true },
			[2] = { type = "stderr", readable = false, writable = true },
		},
		nextFd = 3,
		-- Signals
		sigPending = 0,
		sigMask = 0,
		sigHandlers = {},
		-- Children
		children = {},
		exitCode = nil,
		-- Coroutine body
		_co = nil,
		_body = body,
		_started = false,
		-- Wait queue (for sleep/wakeup)
		_wakeTime = nil,
		-- Command line
		argv = {},
	}

	self._procs[pid] = pcb
	self.stats.totalCreated = self.stats.totalCreated + 1

	-- Add to parent's children list
	if ppid and self._procs[ppid] then
		table.insert(self._procs[ppid].children, pid)
	end

	-- Enqueue
	self:_enqueue(pcb)

	return pid
end

--- The idle process — runs when nothing else is ready
function PM:spawnIdle()
	local pid = self:spawn("idle", function(p)
		while true do
			p:yield()
		end
	end, 0, 3)
	self._idlePid = pid
	return pid
end

--  Coroutine management

function PM:_startCoroutine(pcb)
	local body = pcb._body
	pcb._co = coroutine.create(function()
		local ok, err = pcall(body, pcb)
		if not ok then
			-- Process crashed
			pcb._crashErr = err
		end
		self:exit(pcb.pid, ok and 0 or 1)
	end)
	pcb._started = true
end

--  Scheduler (MLFQ)

--- Advance the scheduler by one tick.
--- Returns the pid that ran, or nil.
function PM:tick(dt)
	self.stats.schedCalls = self.stats.schedCalls + 1
	self._tickCount = self._tickCount + 1

	-- Wake sleeping processes whose timer expired
	self:_wakeTimers()

	-- Demote current process (move to lower priority queue after quantum)
	local cur = self._currentPid and self._procs[self._currentPid]
	if cur and cur.state == PM.STATE.RUNNING then
		cur.state = PM.STATE.READY
		cur.cpuTime = cur.cpuTime + (dt or 0)
		-- Priority aging: running processes in high-priority queues get demoted
		if self._tickCount % 4 == 0 and cur.priority < 3 then
			cur.priority = cur.priority + 1
		end
		self:_enqueue(cur)
	end

	-- Pick next process from highest non-empty queue
	local next = self:_dequeue()
	if not next then
		self._currentPid = self._idlePid
		return nil
	end

	-- Context switch
	if self._currentPid ~= next.pid then
		self.stats.contextSwitches = self.stats.contextSwitches + 1
	end
	self._currentPid = next.pid
	next.state = PM.STATE.RUNNING
	next.lastSched = os.clock()

	-- Run one step of the coroutine
	if not next._started then
		self:_startCoroutine(next)
	end

	if coroutine.status(next._co) ~= "dead" then
		local ok, err = coroutine.resume(next._co)
		if not ok then
			next._crashErr = err
			self:exit(next.pid, 1)
		end
	else
		self:exit(next.pid, 0)
	end

	return next.pid
end

function PM:_wakeTimers()
	local now = os.clock()
	for _, pcb in pairs(self._procs) do
		if pcb.state == PM.STATE.SLEEPING and pcb._wakeTime and now >= pcb._wakeTime then
			pcb._wakeTime = nil
			pcb.state = PM.STATE.READY
			self:_enqueue(pcb)
		end
	end
end

function PM:_enqueue(pcb)
	local q = self._runQ[pcb.priority + 1]
	-- Avoid duplicates
	for _, p in ipairs(q) do
		if p.pid == pcb.pid then
			return
		end
	end
	table.insert(q, pcb)
end

function PM:_dequeue()
	for qi = 1, 4 do
		local q = self._runQ[qi]
		if #q > 0 then
			return table.remove(q, 1)
		end
	end
	return nil
end

--  Process lifecycle

function PM:exit(pid, code)
	local pcb = self._procs[pid]
	if not pcb then
		return
	end

	pcb.state = PM.STATE.ZOMBIE
	pcb.exitCode = code or 0
	self.stats.totalExited = self.stats.totalExited + 1

	-- Release memory
	if pcb.mem and self.memMgr then
		self.memMgr:freePages(pcb.mem)
		pcb.mem = nil
	end

	-- Signal parent (SIGCHLD)
	if pcb.ppid and self._procs[pcb.ppid] then
		self:sendSignal(pcb.ppid, PM.SIG.SIGCHLD)
	end

	-- Reparent children to init (pid 1)
	for _, childPid in ipairs(pcb.children) do
		local child = self._procs[childPid]
		if child then
			child.ppid = 1
		end
	end
end

function PM:reap(pid)
	-- Called by parent wait(); removes zombie
	local pcb = self._procs[pid]
	if pcb and pcb.state == PM.STATE.ZOMBIE then
		local code = pcb.exitCode
		self._procs[pid] = nil
		return code
	end
	return nil
end

function PM:kill(pid, sig)
	return self:sendSignal(pid, sig or PM.SIG.SIGTERM)
end

function PM:sendSignal(pid, sig)
	local pcb = self._procs[pid]
	if not pcb then
		return false
	end

	if sig == PM.SIG.SIGKILL then
		self:exit(pid, 128 + sig)
		return true
	end
	if sig == PM.SIG.SIGSTOP then
		pcb.state = PM.STATE.STOPPED
		return true
	end
	if sig == PM.SIG.SIGCONT then
		if pcb.state == PM.STATE.STOPPED then
			pcb.state = PM.STATE.READY
			self:_enqueue(pcb)
		end
		return true
	end

	-- Check for custom handler
	if pcb.sigHandlers[sig] then
		pcall(pcb.sigHandlers[sig], pcb, sig)
		return true
	end

	-- Default actions
	if sig == PM.SIG.SIGTERM or sig == PM.SIG.SIGHUP then
		self:exit(pid, 128 + sig)
	elseif sig == PM.SIG.SIGINT then
		self:exit(pid, 130)
	end
	return true
end

--  Sleep / wakeup

function PM:sleep(pid, seconds)
	local pcb = self._procs[pid]
	if not pcb then
		return
	end
	pcb.state = PM.STATE.SLEEPING
	pcb._wakeTime = os.clock() + seconds
end

function PM:wakeup(pid)
	local pcb = self._procs[pid]
	if not pcb then
		return
	end
	if pcb.state == PM.STATE.SLEEPING or pcb.state == PM.STATE.READY then
		pcb.state = PM.STATE.READY
		pcb._wakeTime = nil
		self:_enqueue(pcb)
	end
end

--  Process info

function PM:getProcess(pid)
	return self._procs[pid]
end

function PM:getCurrentProcess()
	return self._currentPid and self._procs[self._currentPid]
end

function PM:getProcessList()
	local out = {}
	for pid, pcb in pairs(self._procs) do
		table.insert(out, {
			pid = pcb.pid,
			ppid = pcb.ppid,
			name = pcb.name,
			state = pcb.state,
			pri = pcb.priority,
			uid = pcb.uid,
			cpu = math.floor(pcb.cpuTime * 100) / 100,
			mem = pcb.mem and math.floor(pcb.mem.size / 1024) or 0,
			cwd = pcb.cwd,
		})
	end
	table.sort(out, function(a, b)
		return a.pid < b.pid
	end)
	return out
end

function PM:_allocPid()
	local start = self._nextPid
	for i = 0, MAX_PID do
		local pid = (start + i - 1) % MAX_PID + 1
		if not self._procs[pid] then
			self._nextPid = pid + 1
			return pid
		end
	end
	return nil
end

function PM:getStats()
	return self.stats
end

return PM
