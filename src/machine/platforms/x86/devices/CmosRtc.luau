local CmosRtc = {}
CmosRtc.__index = CmosRtc

local STATUS_A_UIP = 0x80
local STATUS_B_24H = 0x02

local function toBCD(value)
	local v = tonumber(value) or 0
	return ((math.floor(v / 10) % 10) * 16) + (v % 10)
end

local function weekdayForOsDate(wday)
	if wday == 1 then
		return 7
	end
	return wday - 1
end

function CmosRtc.new(config)
	local self = setmetatable({}, CmosRtc)
	self.config = config
	self._index = 0
	self._nmiMasked = false
	self._statusA = 0x26
	self._statusB = STATUS_B_24H
	self._statusC = 0x00
	self._statusD = 0x80
	self.stats = {
		reads = 0,
		writes = 0,
	}
	return self
end

function CmosRtc:attachBus(bus)
	self._bus = bus
	bus:registerPort(self.config.PORT.RTC_INDEX, function()
		return bit32.bor(self._index, self._nmiMasked and 0x80 or 0x00)
	end, function(v)
		local value = bit32.band(tonumber(v) or 0, 0xFF)
		self._nmiMasked = bit32.band(value, 0x80) ~= 0
		self._index = bit32.band(value, 0x7F)
	end, "CmosRtc Index")
	bus:registerPort(self.config.PORT.RTC_DATA, function()
		return self:_readSelected()
	end, function(v)
		self:_writeSelected(v)
	end, "CmosRtc Data")
end

function CmosRtc:_timeTable()
	return os.date("*t")
end

function CmosRtc:_uipActive()
	local fractional = os.clock() % 1
	return fractional >= 0.998
end

function CmosRtc:_readClockRegister(index)
	local now = self:_timeTable()
	local binaryMode = bit32.band(self._statusB, 0x04) ~= 0
	local function encode(value)
		if binaryMode then
			return value % 0x100
		end
		return toBCD(value)
	end

	if index == 0x00 then
		return encode(now.sec)
	elseif index == 0x02 then
		return encode(now.min)
	elseif index == 0x04 then
		return encode(now.hour)
	elseif index == 0x06 then
		return encode(weekdayForOsDate(now.wday))
	elseif index == 0x07 then
		return encode(now.day)
	elseif index == 0x08 then
		return encode(now.month)
	elseif index == 0x09 then
		return encode(now.year % 100)
	end
	return nil
end

function CmosRtc:_readSelected()
	self.stats.reads = self.stats.reads + 1
	local clockValue = self:_readClockRegister(self._index)
	if clockValue ~= nil then
		return clockValue
	end

	if self._index == 0x0A then
		local value = self._statusA
		if self:_uipActive() then
			value = bit32.bor(value, STATUS_A_UIP)
		else
			value = bit32.band(value, bit32.bnot(STATUS_A_UIP))
		end
		return value
	elseif self._index == 0x0B then
		return self._statusB
	elseif self._index == 0x0C then
		local value = self._statusC
		self._statusC = 0
		return value
	elseif self._index == 0x0D then
		return self._statusD
	end
	return 0
end

function CmosRtc:readRegister(index)
	local previous = self._index
	self._index = bit32.band(tonumber(index) or 0, 0x7F)
	local value = self:_readSelected()
	self._index = previous
	return value
end

function CmosRtc:_writeSelected(value)
	self.stats.writes = self.stats.writes + 1
	local v = bit32.band(tonumber(value) or 0, 0xFF)
	if self._index == 0x0A then
		self._statusA = bit32.band(v, 0x7F)
	elseif self._index == 0x0B then
		self._statusB = v
	elseif self._index == 0x0C then
		self._statusC = 0
	elseif self._index == 0x0D then
		self._statusD = bit32.bor(bit32.band(v, 0x7F), 0x80)
	end
end

function CmosRtc:getBIOSClockTicks()
	local now = self:_timeTable()
	local midnight = os.time({
		year = now.year,
		month = now.month,
		day = now.day,
		hour = 0,
		min = 0,
		sec = 0,
	})
	local seconds = math.max(0, os.time(now) - midnight)
	return math.floor(seconds * 18.20648)
end

function CmosRtc:getStats()
	return self.stats
end

return CmosRtc
