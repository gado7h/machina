-- RAM module

local RAM = {}
RAM.__index = RAM

function RAM.new(config)
	local self = setmetatable({}, RAM)
	self.config = config
	self.size = config.RAM_SIZE
	self._mem = {} -- sparse: addr → byte value
	self._dirty = {} -- page_index → true/false

	-- ECC simulation counters
	self.stats = { reads = 0, writes = 0, eccCorrections = 0 }
	return self
end

function RAM:memRead(offset)
	self.stats.reads = self.stats.reads + 1
	return self._mem[offset] or 0
end

function RAM:memWrite(offset, value)
	self.stats.writes = self.stats.writes + 1
	self._mem[offset] = value % 256
	-- mark page dirty
	local page = math.floor(offset / self.config.PAGE_SIZE)
	self._dirty[page] = true
end

function RAM:readRegion(offset, length)
	local out = {}
	for i = 0, length - 1 do
		table.insert(out, self._mem[offset + i] or 0)
	end
	return out
end

function RAM:writeRegion(offset, bytes)
	for i, b in ipairs(bytes) do
		self._mem[offset + i - 1] = b % 256
	end
	local page = math.floor(offset / self.config.PAGE_SIZE)
	self._dirty[page] = true
end

function RAM:clear(offset, length)
	for i = 0, length - 1 do
		self._mem[offset + i] = 0
	end
end

function RAM:getUsedBytes()
	local n = 0
	for _ in pairs(self._mem) do
		n = n + 1
	end
	return n
end

function RAM:getDirtyPageCount()
	local n = 0
	for _ in pairs(self._dirty) do
		n = n + 1
	end
	return n
end

function RAM:clearDirty()
	self._dirty = {}
end
function RAM:getStats()
	return self.stats
end

return RAM
