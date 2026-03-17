-- Timer module (PIT-like, timing-aware)

local Timer = {}
Timer.__index = Timer

local STATUS_READY = 0x01
local STATUS_ENABLED = 0x02
local STATUS_FIRED = 0x04

function Timer.new(config)
	local self = setmetatable({}, Timer)
	self.config = config

	local timerCfg = config.TIMER or {}
	self._baseHz = timerCfg.BASE_HZ or 1193182
	self._divisor = timerCfg.DEFAULT_DIVISOR or 65536
	self._minInterval = timerCfg.MIN_INTERVAL_SEC or (1 / 1000)

	self._enabled = true
	self._periodic = true
	self._accum = 0
	self._irqEnabled = true
	self._pendingLow = nil
	self._status = bit32.bor(STATUS_READY, STATUS_ENABLED)

	self.stats = {
		ticks = 0,
		irqs = 0,
	}
	return self
end

function Timer:attachBus(bus)
	self._bus = bus
	bus:registerPort(self.config.PORT.PIT_CHAN0, function()
		return self:_readDivisorByte()
	end, function(v)
		self:_writeDivisorByte(v)
	end, "PIT CH0")
	bus:registerPort(self.config.PORT.PIT_CMD, function()
		return self._status
	end, function(v)
		self:_writeCommand(v)
	end, "PIT CMD")
end

function Timer:_periodSec()
	local hz = self._baseHz / math.max(1, self._divisor)
	if hz <= 0 then
		return self._minInterval
	end
	return math.max(self._minInterval, 1 / hz)
end

function Timer:_writeDivisorByte(v)
	v = bit32.band(tonumber(v) or 0, 0xFF)
	if self._pendingLow == nil then
		self._pendingLow = v
		return
	end
	local divisor = self._pendingLow + bit32.lshift(v, 8)
	self._pendingLow = nil
	if divisor == 0 then
		divisor = 65536
	end
	self._divisor = divisor
end

function Timer:_readDivisorByte()
	-- Return low byte for simple reads.
	return bit32.band(self._divisor, 0xFF)
end

function Timer:_writeCommand(v)
	v = tonumber(v) or 0
	-- Support a minimal command model:
	-- bit0 = enable, bit1 = periodic, bit2 = irq-enable.
	self._enabled = bit32.band(v, 0x01) ~= 0
	self._periodic = bit32.band(v, 0x02) ~= 0
	self._irqEnabled = bit32.band(v, 0x04) ~= 0
	self._status = STATUS_READY
	if self._enabled then
		self._status = bit32.bor(self._status, STATUS_ENABLED)
	end
end

function Timer:tick(dt)
	self.stats.ticks = self.stats.ticks + 1
	if not self._enabled then
		return
	end
	dt = tonumber(dt) or 0
	if dt <= 0 then
		return
	end

	self._accum = self._accum + dt
	local period = self:_periodSec()
	if self._accum < period then
		return
	end

	local fireCount = math.floor(self._accum / period)
	if not self._periodic and fireCount > 1 then
		fireCount = 1
	end
	self._accum = self._accum - (fireCount * period)
	self._status = bit32.bor(self._status, STATUS_FIRED)

	if not self._periodic then
		self._enabled = false
		self._status = bit32.band(self._status, bit32.bnot(STATUS_ENABLED))
	end

	if self._irqEnabled and self._bus then
		for _ = 1, fireCount do
			self._bus:raiseIRQ(self.config.IRQ.TIMER, { source = "timer", period = period })
			self.stats.irqs = self.stats.irqs + 1
		end
	end
end

function Timer:memRead(offset)
	offset = tonumber(offset) or -1
	if offset == 0x00 then
		return self._status
	elseif offset == 0x04 then
		return bit32.band(self._divisor, 0xFF)
	elseif offset == 0x05 then
		return bit32.band(bit32.rshift(self._divisor, 8), 0xFF)
	elseif offset == 0x08 then
		return self._enabled and 1 or 0
	elseif offset == 0x09 then
		return self._periodic and 1 or 0
	elseif offset == 0x0A then
		return self._irqEnabled and 1 or 0
	end
	return 0
end

function Timer:memWrite(offset, value)
	offset = tonumber(offset) or -1
	value = bit32.band(tonumber(value) or 0, 0xFF)
	if offset == 0x00 then
		self:_writeCommand(value)
	elseif offset == 0x04 then
		self._divisor = bit32.bor(bit32.band(self._divisor, 0xFF00), value)
	elseif offset == 0x05 then
		self._divisor = bit32.bor(bit32.band(self._divisor, 0x00FF), bit32.lshift(value, 8))
		if self._divisor == 0 then
			self._divisor = 65536
		end
	elseif offset == 0x08 then
		self._enabled = value ~= 0
	elseif offset == 0x09 then
		self._periodic = value ~= 0
	elseif offset == 0x0A then
		self._irqEnabled = value ~= 0
	end
end

function Timer:getStats()
	return self.stats
end

return Timer
