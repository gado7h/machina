-- InterruptController module (PIC-like, timing-aware but not cycle-accurate)

local PIC = {}
PIC.__index = PIC

local function bit(mask, n)
	return bit32.band(mask, bit32.lshift(1, n)) ~= 0
end

function PIC.new(config)
	local self = setmetatable({}, PIC)
	self.config = config
	self.vectorBaseMaster = config.PIC_VECTOR_BASE_MASTER or 0x20
	self.vectorBaseSlave = config.PIC_VECTOR_BASE_SLAVE or 0x28

	self._imrMaster = 0x00 -- bit=1 masked
	self._imrSlave = 0x00
	self._irrMaster = 0x00 -- pending
	self._irrSlave = 0x00
	self._isrMaster = 0x00 -- in service
	self._isrSlave = 0x00

	self._initStateMaster = 0
	self._initStateSlave = 0
	self._readRegMaster = "IRR"
	self._readRegSlave = "IRR"

	self.stats = {
		raised = 0,
		delivered = 0,
		eoi = 0,
		spurious = 0,
	}
	return self
end

function PIC:attachBus(bus)
	self._bus = bus
	bus:registerPort(self.config.PORT.PIC_MASTER_CMD, function()
		return self:_readMasterCommand()
	end, function(v)
		self:_writeMasterCommand(v)
	end, "PIC Master CMD")
	bus:registerPort(self.config.PORT.PIC_MASTER_DATA, function()
		return self._imrMaster
	end, function(v)
		self:_writeMasterData(v)
	end, "PIC Master DATA")

	bus:registerPort(self.config.PORT.PIC_SLAVE_CMD, function()
		return self:_readSlaveCommand()
	end, function(v)
		self:_writeSlaveCommand(v)
	end, "PIC Slave CMD")
	bus:registerPort(self.config.PORT.PIC_SLAVE_DATA, function()
		return self._imrSlave
	end, function(v)
		self:_writeSlaveData(v)
	end, "PIC Slave DATA")
end

local function highestPending(maskedPending)
	for irq = 0, 7 do
		if bit(maskedPending, irq) then
			return irq
		end
	end
	return nil
end

function PIC:raiseIRQ(irqNum)
	irqNum = tonumber(irqNum) or -1
	if irqNum < 0 or irqNum > 15 then
		self.stats.spurious = self.stats.spurious + 1
		return false
	end
	self.stats.raised = self.stats.raised + 1
	if irqNum < 8 then
		self._irrMaster = bit32.bor(self._irrMaster, bit32.lshift(1, irqNum))
	else
		self._irrSlave = bit32.bor(self._irrSlave, bit32.lshift(1, irqNum - 8))
		-- Slave interrupt raises cascade on IRQ2 of master.
		self._irrMaster = bit32.bor(self._irrMaster, bit32.lshift(1, 2))
	end
	return true
end

function PIC:hasPending()
	local pendingMaster = bit32.band(self._irrMaster, bit32.bnot(self._imrMaster))
	local pendingSlave = bit32.band(self._irrSlave, bit32.bnot(self._imrSlave))
	return pendingMaster ~= 0 or pendingSlave ~= 0
end

function PIC:getNextVector()
	local pendingMaster = bit32.band(self._irrMaster, bit32.bnot(self._imrMaster))
	local masterIRQ = highestPending(pendingMaster)
	if masterIRQ == nil then
		return nil
	end

	-- Cascade line: dispatch from slave if available.
	if masterIRQ == 2 then
		local pendingSlave = bit32.band(self._irrSlave, bit32.bnot(self._imrSlave))
		local slaveIRQ = highestPending(pendingSlave)
		if slaveIRQ ~= nil then
			self._irrSlave = bit32.band(self._irrSlave, bit32.bnot(bit32.lshift(1, slaveIRQ)))
			self._isrSlave = bit32.bor(self._isrSlave, bit32.lshift(1, slaveIRQ))
			if self._irrSlave == 0 then
				self._irrMaster = bit32.band(self._irrMaster, bit32.bnot(bit32.lshift(1, 2)))
			end
			self._isrMaster = bit32.bor(self._isrMaster, bit32.lshift(1, 2))
			self.stats.delivered = self.stats.delivered + 1
			return (self.vectorBaseSlave + slaveIRQ) % 256
		end
	end

	self._irrMaster = bit32.band(self._irrMaster, bit32.bnot(bit32.lshift(1, masterIRQ)))
	self._isrMaster = bit32.bor(self._isrMaster, bit32.lshift(1, masterIRQ))
	self.stats.delivered = self.stats.delivered + 1
	return (self.vectorBaseMaster + masterIRQ) % 256
end

function PIC:endOfInterrupt(vector)
	vector = tonumber(vector) or -1
	if vector >= self.vectorBaseSlave and vector < self.vectorBaseSlave + 8 then
		local irq = vector - self.vectorBaseSlave
		self._isrSlave = bit32.band(self._isrSlave, bit32.bnot(bit32.lshift(1, irq)))
		-- EOI slave implies cascade complete on master IRQ2.
		self._isrMaster = bit32.band(self._isrMaster, bit32.bnot(bit32.lshift(1, 2)))
		self.stats.eoi = self.stats.eoi + 1
		return true
	end
	if vector >= self.vectorBaseMaster and vector < self.vectorBaseMaster + 8 then
		local irq = vector - self.vectorBaseMaster
		self._isrMaster = bit32.band(self._isrMaster, bit32.bnot(bit32.lshift(1, irq)))
		self.stats.eoi = self.stats.eoi + 1
		return true
	end
	return false
end

function PIC:_readMasterCommand()
	return self._readRegMaster == "ISR" and self._isrMaster or self._irrMaster
end

function PIC:_readSlaveCommand()
	return self._readRegSlave == "ISR" and self._isrSlave or self._irrSlave
end

function PIC:_writeMasterCommand(v)
	v = tonumber(v) or 0
	if bit32.band(v, 0x10) ~= 0 then
		self._initStateMaster = 1
		self._irrMaster = 0
		self._isrMaster = 0
		return
	end
	if bit32.band(v, 0x20) ~= 0 then
		-- Non-specific EOI clears highest in-service bit.
		for irq = 0, 7 do
			if bit(self._isrMaster, irq) then
				self._isrMaster = bit32.band(self._isrMaster, bit32.bnot(bit32.lshift(1, irq)))
				self.stats.eoi = self.stats.eoi + 1
				break
			end
		end
		return
	end
	if bit32.band(v, 0x08) ~= 0 then
		self._readRegMaster = bit32.band(v, 0x01) ~= 0 and "ISR" or "IRR"
	end
end

function PIC:_writeSlaveCommand(v)
	v = tonumber(v) or 0
	if bit32.band(v, 0x10) ~= 0 then
		self._initStateSlave = 1
		self._irrSlave = 0
		self._isrSlave = 0
		return
	end
	if bit32.band(v, 0x20) ~= 0 then
		for irq = 0, 7 do
			if bit(self._isrSlave, irq) then
				self._isrSlave = bit32.band(self._isrSlave, bit32.bnot(bit32.lshift(1, irq)))
				self.stats.eoi = self.stats.eoi + 1
				break
			end
		end
		return
	end
	if bit32.band(v, 0x08) ~= 0 then
		self._readRegSlave = bit32.band(v, 0x01) ~= 0 and "ISR" or "IRR"
	end
end

function PIC:_writeMasterData(v)
	v = tonumber(v) or 0
	if self._initStateMaster == 1 then
		self.vectorBaseMaster = bit32.band(v, 0xF8)
		self._initStateMaster = 2
		return
	end
	if self._initStateMaster >= 2 then
		-- ICW3/ICW4 ignored in this simplified model.
		self._initStateMaster = self._initStateMaster + 1
		if self._initStateMaster > 3 then
			self._initStateMaster = 0
		end
		return
	end
	self._imrMaster = bit32.band(v, 0xFF)
end

function PIC:_writeSlaveData(v)
	v = tonumber(v) or 0
	if self._initStateSlave == 1 then
		self.vectorBaseSlave = bit32.band(v, 0xF8)
		self._initStateSlave = 2
		return
	end
	if self._initStateSlave >= 2 then
		self._initStateSlave = self._initStateSlave + 1
		if self._initStateSlave > 3 then
			self._initStateSlave = 0
		end
		return
	end
	self._imrSlave = bit32.band(v, 0xFF)
end

function PIC:getStats()
	return self.stats
end

return PIC
