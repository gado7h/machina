-- Bus module

local Bus = {}
Bus.__index = Bus

function Bus.new(config)
	local self = setmetatable({}, Bus)
	self.config = config
	self._devices = {} -- name → device object
	self._memmap = {} -- {base, size, device, tag}  sorted list
	self._portmap = {} -- port_number → handler function
	self._irqLines = {} -- irq_num → {handler, device, count, active}
	self._dmaQueue = {} -- pending DMA transfers
	self._logs = {}

	-- Statistics
	self.stats = {
		memReads = 0,
		memWrites = 0,
		portReads = 0,
		portWrites = 0,
		irqFired = 0,
		dmaBytes = 0,
	}
	return self
end

--  Device Registration

function Bus:registerDevice(name, device)
	assert(not self._devices[name], "Bus: device '" .. name .. "' already registered")
	self._devices[name] = device
	self:_log("BUS", "Device registered: " .. name)
end

function Bus:getDevice(name)
	return self._devices[name]
end

--  Memory Map

--- Map a device into physical address space.
--- device must implement :memRead(offset) and :memWrite(offset, value)
function Bus:mapMemory(base, size, device, tag)
	table.insert(self._memmap, { base = base, size = size, device = device, tag = tag or "?" })
	-- keep sorted by base for binary search
	table.sort(self._memmap, function(a, b)
		return a.base < b.base
	end)
	self:_log("BUS", string.format("Mapped [%08X–%08X] → %s", base, base + size - 1, tag or "?"))
end

local function findMapping(self, addr)
	for _, m in ipairs(self._memmap) do
		if addr >= m.base and addr < m.base + m.size then
			return m
		end
	end
	return nil
end

function Bus:memRead(addr)
	self.stats.memReads = self.stats.memReads + 1
	local m = findMapping(self, addr)
	if not m then
		self:_log("BUS", string.format("WARN memRead unmapped addr %08X", addr))
		return 0
	end
	return m.device:memRead(addr - m.base)
end

function Bus:memWrite(addr, value)
	self.stats.memWrites = self.stats.memWrites + 1
	local m = findMapping(self, addr)
	if not m then
		self:_log("BUS", string.format("WARN memWrite unmapped addr %08X = %02X", addr, value))
		return
	end
	m.device:memWrite(addr - m.base, value)
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
	self:memWrite(addr, value % 256)
	self:memWrite(addr + 1, math.floor(value / 256) % 256)
	self:memWrite(addr + 2, math.floor(value / 65536) % 256)
	self:memWrite(addr + 3, math.floor(value / 16777216) % 256)
end

--  Port I/O

function Bus:registerPort(port, readFn, writeFn, label)
	self._portmap[port] = { read = readFn, write = writeFn, label = label or string.format("0x%04X", port) }
end

function Bus:portRead(port)
	self.stats.portReads = self.stats.portReads + 1
	local h = self._portmap[port]
	if h and h.read then
		return h.read()
	end
	return 0xFF -- floating bus
end

function Bus:portWrite(port, value)
	self.stats.portWrites = self.stats.portWrites + 1
	local h = self._portmap[port]
	if h and h.write then
		h.write(value)
	end
end

--  IRQ (Interrupt Request Lines)

function Bus:registerIRQ(irqNum, device, handler)
	if not self._irqLines[irqNum] then
		self._irqLines[irqNum] = {}
	end
	table.insert(self._irqLines[irqNum], { device = device, handler = handler, count = 0, active = false })
	self:_log("BUS", string.format("IRQ%d registered for device: %s", irqNum, tostring(device)))
end

--- Fire an interrupt — called by devices (timer, keyboard, disk, etc.)
function Bus:raiseIRQ(irqNum, data)
	self.stats.irqFired = self.stats.irqFired + 1
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

function Bus:getIRQStats()
	local out = {}
	for irq, handlers in pairs(self._irqLines) do
		for _, h in ipairs(handlers) do
			table.insert(out, { irq = irq, device = tostring(h.device), count = h.count, active = h.active })
		end
	end
	return out
end

--  DMA (Direct Memory Access)

--- Enqueue a DMA transfer.  src/dst are physical addresses; callback fires on completion.
function Bus:dmaTransfer(src, dst, length, callback)
	table.insert(self._dmaQueue, { src = src, dst = dst, length = length, cb = callback, done = false })
end

--- Process all pending DMA transfers (called each tick by the motherboard).
function Bus:processDMA()
	for i, xfer in ipairs(self._dmaQueue) do
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
	-- purge completed
	local live = {}
	for _, x in ipairs(self._dmaQueue) do
		if not x.done then
			table.insert(live, x)
		end
	end
	self._dmaQueue = live
end

--  Internal logging

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
