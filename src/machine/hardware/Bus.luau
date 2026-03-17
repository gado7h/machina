-- Bus module

local Bus = {}
Bus.__index = Bus

local function defaultTickDt(config)
	local hz = math.max(config.CPU_CLOCK_HZ or 1, config.DISPLAY_REFRESH_HZ or 60)
	return 1 / math.max(1, hz)
end

function Bus.new(config)
	local self = setmetatable({}, Bus)
	self.config = config
	self._devices = {} -- name -> device object
	self._memmap = {} -- {base, size, device, tag, readOnly}
	self._portmap = {} -- port_number -> handler function
	self._irqLines = {} -- legacy callbacks: irq_num -> {handler, device, count, active}
	self._dmaQueue = {} -- pending DMA transfers
	self._logs = {}
	self._fault = nil
	self._defaultDt = defaultTickDt(config)

	-- Statistics
	self.stats = {
		memReads = 0,
		memWrites = 0,
		portReads = 0,
		portWrites = 0,
		irqFired = 0,
		irqDelivered = 0,
		dmaBytes = 0,
		faults = 0,
	}

	local PIC_M = require(script.Parent.InterruptController)
	local Timer_M = require(script.Parent.Timer)
	self.pic = PIC_M.new(config)
	self.timer = Timer_M.new(config)
	self._devices.pic = self.pic
	self._devices.timer = self.timer
	self.pic:attachBus(self)
	self.timer:attachBus(self)

	return self
end

-- Device Registration

function Bus:registerDevice(name, device)
	assert(not self._devices[name], "Bus: device '" .. name .. "' already registered")
	self._devices[name] = device
	if name == "cpu" then
		self._cpu = device
	end
	if device and type(device.attachBus) == "function" then
		pcall(function()
			device:attachBus(self)
		end)
	end
	self:_log("BUS", "Device registered: " .. name)
end

function Bus:getDevice(name)
	return self._devices[name]
end

-- Memory Map

-- device must implement :memRead(offset) and :memWrite(offset, value)
function Bus:mapMemory(base, size, device, tag, opts)
	opts = opts or {}
	local readOnly = opts.readOnly == true or (type(tag) == "string" and tag:find("ROM") ~= nil)
	table.insert(self._memmap, {
		base = base,
		size = size,
		device = device,
		tag = tag or "?",
		readOnly = readOnly,
	})
	table.sort(self._memmap, function(a, b)
		return a.base < b.base
	end)
	self:_log("BUS", string.format("Mapped [%08X-%08X] -> %s", base, base + size - 1, tag or "?"))
end

local function findMapping(self, addr)
	for _, m in ipairs(self._memmap) do
		if addr >= m.base and addr < m.base + m.size then
			return m
		end
	end
	return nil
end

function Bus:_setFault(kind, addr, op, detail)
	self.stats.faults = self.stats.faults + 1
	self._fault = {
		kind = kind,
		addr = addr,
		op = op,
		detail = detail,
		time = os.clock(),
	}
	self:_log(
		"BUS",
		string.format("FAULT %s op=%s addr=%08X (%s)", tostring(kind), tostring(op), addr or 0, tostring(detail))
	)
end

function Bus:peekFault()
	return self._fault
end

function Bus:consumeFault()
	local f = self._fault
	self._fault = nil
	return f
end

function Bus:memRead(addr)
	self.stats.memReads = self.stats.memReads + 1
	local m = findMapping(self, addr)
	if not m then
		self:_setFault("unmapped-read", addr, "read8", "Address not mapped")
		return 0xFF
	end
	local ok, value = pcall(function()
		return m.device:memRead(addr - m.base)
	end)
	if not ok then
		self:_setFault("device-read-fault", addr, "read8", value)
		return 0xFF
	end
	if value == nil then
		self:_setFault("device-read-nil", addr, "read8", m.tag)
		return 0xFF
	end
	return (tonumber(value) or 0) % 256
end

function Bus:memWrite(addr, value)
	self.stats.memWrites = self.stats.memWrites + 1
	local m = findMapping(self, addr)
	if not m then
		self:_setFault("unmapped-write", addr, "write8", "Address not mapped")
		return false
	end
	if m.readOnly then
		self:_setFault("readonly-write", addr, "write8", m.tag)
		return false
	end
	local ok, err = pcall(function()
		m.device:memWrite(addr - m.base, (tonumber(value) or 0) % 256)
	end)
	if not ok then
		self:_setFault("device-write-fault", addr, "write8", err)
		return false
	end
	return true
end

-- 32-bit word helpers
function Bus:memRead32(addr)
	local b0 = self:memRead(addr)
	local b1 = self:memRead(addr + 1)
	local b2 = self:memRead(addr + 2)
	local b3 = self:memRead(addr + 3)
	return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

function Bus:memWrite32(addr, value)
	local v = tonumber(value) or 0
	local ok0 = self:memWrite(addr, v % 256)
	local ok1 = self:memWrite(addr + 1, math.floor(v / 256) % 256)
	local ok2 = self:memWrite(addr + 2, math.floor(v / 65536) % 256)
	local ok3 = self:memWrite(addr + 3, math.floor(v / 16777216) % 256)
	return ok0 and ok1 and ok2 and ok3
end

-- Port I/O

function Bus:registerPort(port, readFn, writeFn, label)
	self._portmap[port] = { read = readFn, write = writeFn, label = label or string.format("0x%04X", port) }
end

function Bus:portRead(port)
	self.stats.portReads = self.stats.portReads + 1
	local h = self._portmap[port]
	if h and h.read then
		local ok, value = pcall(h.read)
		if ok then
			return (tonumber(value) or 0) % 256
		end
	end
	return 0xFF
end

function Bus:portWrite(port, value)
	self.stats.portWrites = self.stats.portWrites + 1
	local h = self._portmap[port]
	if h and h.write then
		local ok, err = pcall(h.write, (tonumber(value) or 0) % 256)
		if not ok then
			self:_setFault("port-write-fault", port, "out", err)
		end
	end
end

-- IRQ (Interrupt Request Lines)

function Bus:registerIRQ(irqNum, device, handler)
	if not self._irqLines[irqNum] then
		self._irqLines[irqNum] = {}
	end
	table.insert(self._irqLines[irqNum], { device = device, handler = handler, count = 0, active = false })
	self:_log("BUS", string.format("IRQ%d registered for device: %s", irqNum, tostring(device)))
end

-- Fire an interrupt: queue into PIC and also call legacy callbacks.
function Bus:raiseIRQ(irqNum, data)
	self.stats.irqFired = self.stats.irqFired + 1
	if self.pic then
		self.pic:raiseIRQ(irqNum)
	end

	local handlers = self._irqLines[irqNum]
	if not handlers then
		return
	end
	for _, h in ipairs(handlers) do
		h.count = h.count + 1
		h.active = true
		local ok, err = pcall(h.handler, irqNum, data)
		if not ok then
			self:_log("BUS", "IRQ handler error IRQ" .. irqNum .. ": " .. tostring(err))
		end
		h.active = false
	end
end

function Bus:hasPendingInterrupt()
	return self.pic and self.pic:hasPending() or false
end

function Bus:getPendingInterruptVector()
	if not self.pic then
		return nil
	end
	local vec = self.pic:getNextVector()
	if vec ~= nil then
		self.stats.irqDelivered = self.stats.irqDelivered + 1
	end
	return vec
end

function Bus:endOfInterrupt(vector)
	if self.pic then
		return self.pic:endOfInterrupt(vector)
	end
	return false
end

function Bus:getIRQStats()
	local out = {}
	for irq, handlers in pairs(self._irqLines) do
		for _, h in ipairs(handlers) do
			table.insert(out, { irq = irq, device = tostring(h.device), count = h.count, active = h.active })
		end
	end
	return out
end

-- DMA (Direct Memory Access)

-- Enqueue a DMA transfer. src/dst are physical addresses; callback fires on completion.
function Bus:dmaTransfer(src, dst, length, callback)
	table.insert(self._dmaQueue, { src = src, dst = dst, length = length, cb = callback, done = false })
end

-- Process all pending DMA transfers.
function Bus:processDMA(dt)
	for _, xfer in ipairs(self._dmaQueue) do
		if not xfer.done then
			for off = 0, xfer.length - 1 do
				local byte = self:memRead(xfer.src + off)
				self:memWrite(xfer.dst + off, byte)
			end
			self.stats.dmaBytes = self.stats.dmaBytes + xfer.length
			xfer.done = true
			if xfer.cb then
				pcall(xfer.cb)
			end
		end
	end

	local live = {}
	for _, x in ipairs(self._dmaQueue) do
		if not x.done then
			table.insert(live, x)
		end
	end
	self._dmaQueue = live

	self:tick(dt)
end

function Bus:tick(dt)
	dt = tonumber(dt) or self._defaultDt
	if self.timer and type(self.timer.tick) == "function" then
		self.timer:tick(dt)
	end
	-- Let devices progress asynchronous operations.
	for name, device in pairs(self._devices) do
		if name ~= "timer" and name ~= "pic" and name ~= "cpu" and type(device.tick) == "function" then
			device:tick(dt)
		end
	end
end

-- Internal logging

function Bus:_log(tag, msg)
	local entry = string.format("[%s] %s", tag, msg)
	table.insert(self._logs, entry)
	if #self._logs > 500 then
		table.remove(self._logs, 1)
	end
end

function Bus:getLog(n)
	n = n or #self._logs
	local start = math.max(1, #self._logs - n + 1)
	local out = {}
	for i = start, #self._logs do
		table.insert(out, self._logs[i])
	end
	return out
end

function Bus:getStats()
	return self.stats
end

return Bus
