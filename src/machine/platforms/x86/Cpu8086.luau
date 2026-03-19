local Cpu8086 = {}
Cpu8086.__index = Cpu8086

local FLAG_CF = 0x0001
local FLAG_ZF = 0x0040
local FLAG_SF = 0x0080
local FLAG_IF = 0x0200
local FLAG_OF = 0x0800

local function signExtend8(value)
	value = value % 0x100
	if value >= 0x80 then
		return value - 0x100
	end
	return value
end

local function signExtend16(value)
	value = value % 0x10000
	if value >= 0x8000 then
		return value - 0x10000
	end
	return value
end

local function maskForWidth(width)
	return width == 8 and 0xFF or 0xFFFF
end

local function signBit(width)
	return width == 8 and 0x80 or 0x8000
end

function Cpu8086.new(bus, config)
	local self = setmetatable({}, Cpu8086)
	self.bus = bus
	self.config = config
	self.x86 = config.X86 or {}
	self.reg16 = {
		AX = 0,
		CX = 0,
		DX = 0,
		BX = 0,
		SP = 0,
		BP = 0,
		SI = 0,
		DI = 0,
	}
	self.seg = {
		ES = 0,
		CS = 0,
		SS = 0,
		DS = 0,
	}
	self.ip = 0
	self.flags = 0x0002
	self.halted = false
	self._bios = nil
	self._lastError = nil
	self._lastStep = {
		opcode = nil,
		cs = 0,
		ip = 0,
	}
	self.stats = {
		cycles = 0,
		instructions = 0,
		interrupts = 0,
		memReads = 0,
		memWrites = 0,
		portReads = 0,
		portWrites = 0,
	}
	self:reset()
	return self
end

function Cpu8086:attachBIOS(bios)
	self._bios = bios
end

function Cpu8086:reset()
	for name in pairs(self.reg16) do
		self.reg16[name] = 0
	end
	self.seg.ES = 0
	self.seg.DS = 0
	self.seg.SS = 0
	self.seg.CS = self.x86.RESET_VECTOR_SEG or 0xF000
	self.ip = self.x86.RESET_VECTOR_OFF or 0xFFF0
	self.flags = 0x0002
	self.halted = false
	self._lastError = nil
	self._lastStep.opcode = nil
	self._lastStep.cs = self.seg.CS
	self._lastStep.ip = self.ip
	for name in pairs(self.stats) do
		self.stats[name] = 0
	end
end

function Cpu8086:getLinearPC()
	return bit32.band(self.seg.CS * 16 + self.ip, 0xFFFFF)
end

function Cpu8086:getStats()
	return {
		cycles = self.stats.cycles,
		instructions = self.stats.instructions,
		interrupts = self.stats.interrupts,
		memReads = self.stats.memReads,
		memWrites = self.stats.memWrites,
		portReads = self.stats.portReads,
		portWrites = self.stats.portWrites,
		halted = self.halted,
		lastError = self._lastError,
		pc = self:getLinearPC(),
		cs = self.seg.CS,
		ip = self.ip,
		lastOpcode = self._lastStep.opcode,
		lastCS = self._lastStep.cs,
		lastIP = self._lastStep.ip,
	}
end

function Cpu8086:getFlag(mask)
	return bit32.band(self.flags, mask) ~= 0
end

function Cpu8086:setFlag(mask, enabled)
	if enabled then
		self.flags = bit32.bor(self.flags, mask)
	else
		self.flags = bit32.band(self.flags, bit32.bnot(mask))
	end
end

function Cpu8086:getReg16(code)
	return ({
		self.reg16.AX,
		self.reg16.CX,
		self.reg16.DX,
		self.reg16.BX,
		self.reg16.SP,
		self.reg16.BP,
		self.reg16.SI,
		self.reg16.DI,
	})[code + 1] or 0
end

function Cpu8086:setReg16(code, value)
	local v = (tonumber(value) or 0) % 0x10000
	if code == 0 then
		self.reg16.AX = v
	elseif code == 1 then
		self.reg16.CX = v
	elseif code == 2 then
		self.reg16.DX = v
	elseif code == 3 then
		self.reg16.BX = v
	elseif code == 4 then
		self.reg16.SP = v
	elseif code == 5 then
		self.reg16.BP = v
	elseif code == 6 then
		self.reg16.SI = v
	elseif code == 7 then
		self.reg16.DI = v
	end
end

function Cpu8086:getReg8(code)
	local regIndex = code % 4
	local word = self:getReg16(regIndex)
	if code < 4 then
		return word % 0x100
	end
	return math.floor(word / 0x100) % 0x100
end

function Cpu8086:setReg8(code, value)
	local regIndex = code % 4
	local word = self:getReg16(regIndex)
	local byteValue = (tonumber(value) or 0) % 0x100
	if code < 4 then
		self:setReg16(regIndex, bit32.bor(bit32.band(word, 0xFF00), byteValue))
	else
		self:setReg16(regIndex, bit32.bor(bit32.band(word, 0x00FF), bit32.lshift(byteValue, 8)))
	end
end

function Cpu8086:getSeg(code)
	return ({ self.seg.ES, self.seg.CS, self.seg.SS, self.seg.DS })[code + 1] or 0
end

function Cpu8086:setSeg(code, value)
	local v = (tonumber(value) or 0) % 0x10000
	if code == 0 then
		self.seg.ES = v
	elseif code == 1 then
		self.seg.CS = v
	elseif code == 2 then
		self.seg.SS = v
	elseif code == 3 then
		self.seg.DS = v
	end
end

function Cpu8086:linearAddress(segment, offset)
	return bit32.band((segment % 0x10000) * 16 + (offset % 0x10000), 0xFFFFF)
end

function Cpu8086:readPhysical8(address)
	self.stats.memReads = self.stats.memReads + 1
	return self.bus:memRead(bit32.band(address, 0xFFFFF))
end

function Cpu8086:writePhysical8(address, value)
	self.stats.memWrites = self.stats.memWrites + 1
	self.bus:memWrite(bit32.band(address, 0xFFFFF), value % 0x100)
end

function Cpu8086:readPhysical16(address)
	local lo = self:readPhysical8(address)
	local hi = self:readPhysical8(address + 1)
	return lo + hi * 256
end

function Cpu8086:writePhysical16(address, value)
	local v = (tonumber(value) or 0) % 0x10000
	self:writePhysical8(address, v % 0x100)
	self:writePhysical8(address + 1, math.floor(v / 0x100) % 0x100)
end

function Cpu8086:readMem8(segment, offset)
	return self:readPhysical8(self:linearAddress(segment, offset))
end

function Cpu8086:readMem16(segment, offset)
	return self:readPhysical16(self:linearAddress(segment, offset))
end

function Cpu8086:writeMem8(segment, offset, value)
	self:writePhysical8(self:linearAddress(segment, offset), value)
end

function Cpu8086:writeMem16(segment, offset, value)
	self:writePhysical16(self:linearAddress(segment, offset), value)
end

function Cpu8086:fetch8()
	local value = self:readMem8(self.seg.CS, self.ip)
	self.ip = (self.ip + 1) % 0x10000
	return value
end

function Cpu8086:fetch16()
	local lo = self:fetch8()
	local hi = self:fetch8()
	return lo + hi * 256
end

function Cpu8086:push16(value)
	self.reg16.SP = (self.reg16.SP - 2) % 0x10000
	self:writeMem16(self.seg.SS, self.reg16.SP, value)
end

function Cpu8086:pop16()
	local value = self:readMem16(self.seg.SS, self.reg16.SP)
	self.reg16.SP = (self.reg16.SP + 2) % 0x10000
	return value
end

function Cpu8086:_decodeModRM()
	local byte = self:fetch8()
	local mod = bit32.rshift(byte, 6)
	local reg = bit32.band(bit32.rshift(byte, 3), 0x07)
	local rm = bit32.band(byte, 0x07)
	local disp = 0
	if mod == 1 then
		disp = signExtend8(self:fetch8())
	elseif mod == 2 or (mod == 0 and rm == 6) then
		disp = signExtend16(self:fetch16())
	end
	return {
		mod = mod,
		reg = reg,
		rm = rm,
		disp = disp,
	}
end

function Cpu8086:_effectiveAddress(decoded)
	if decoded.mod == 3 then
		return nil, nil
	end

	local base = 0
	local segment = self.seg.DS
	if decoded.mod == 0 and decoded.rm == 6 then
		base = decoded.disp
	else
		if decoded.rm == 0 then
			base = self.reg16.BX + self.reg16.SI
		elseif decoded.rm == 1 then
			base = self.reg16.BX + self.reg16.DI
		elseif decoded.rm == 2 then
			base = self.reg16.BP + self.reg16.SI
			segment = self.seg.SS
		elseif decoded.rm == 3 then
			base = self.reg16.BP + self.reg16.DI
			segment = self.seg.SS
		elseif decoded.rm == 4 then
			base = self.reg16.SI
		elseif decoded.rm == 5 then
			base = self.reg16.DI
		elseif decoded.rm == 6 then
			base = self.reg16.BP
			segment = self.seg.SS
		elseif decoded.rm == 7 then
			base = self.reg16.BX
		end
		base = base + decoded.disp
	end

	return segment, base % 0x10000
end

function Cpu8086:_readRM8(decoded)
	if decoded.mod == 3 then
		return self:getReg8(decoded.rm)
	end
	local segment, offset = self:_effectiveAddress(decoded)
	return self:readMem8(segment, offset)
end

function Cpu8086:_readRM16(decoded)
	if decoded.mod == 3 then
		return self:getReg16(decoded.rm)
	end
	local segment, offset = self:_effectiveAddress(decoded)
	return self:readMem16(segment, offset)
end

function Cpu8086:_writeRM8(decoded, value)
	if decoded.mod == 3 then
		self:setReg8(decoded.rm, value)
		return
	end
	local segment, offset = self:_effectiveAddress(decoded)
	self:writeMem8(segment, offset, value)
end

function Cpu8086:_writeRM16(decoded, value)
	if decoded.mod == 3 then
		self:setReg16(decoded.rm, value)
		return
	end
	local segment, offset = self:_effectiveAddress(decoded)
	self:writeMem16(segment, offset, value)
end

function Cpu8086:_updateLogicFlags(width, value)
	local masked = value % (maskForWidth(width) + 1)
	self:setFlag(FLAG_CF, false)
	self:setFlag(FLAG_OF, false)
	self:setFlag(FLAG_ZF, masked == 0)
	self:setFlag(FLAG_SF, bit32.band(masked, signBit(width)) ~= 0)
end

function Cpu8086:_add(width, a, b)
	local mask = maskForWidth(width)
	local result = (a + b) % (mask + 1)
	self:setFlag(FLAG_CF, a + b > mask)
	self:setFlag(FLAG_ZF, result == 0)
	self:setFlag(FLAG_SF, bit32.band(result, signBit(width)) ~= 0)
	local overflow = bit32.band(bit32.bnot(bit32.bxor(a, b)), bit32.bxor(a, result), signBit(width)) ~= 0
	self:setFlag(FLAG_OF, overflow)
	return result
end

function Cpu8086:_sub(width, a, b)
	local mask = maskForWidth(width)
	local result = (a - b) % (mask + 1)
	self:setFlag(FLAG_CF, a < b)
	self:setFlag(FLAG_ZF, result == 0)
	self:setFlag(FLAG_SF, bit32.band(result, signBit(width)) ~= 0)
	local overflow = bit32.band(bit32.bxor(a, b), bit32.bxor(a, result), signBit(width)) ~= 0
	self:setFlag(FLAG_OF, overflow)
	return result
end

function Cpu8086:_serviceExternalInterrupt()
	if not self:getFlag(FLAG_IF) then
		return false
	end
	if not self.bus or type(self.bus.getPendingInterruptVector) ~= "function" then
		return false
	end
	local vector = self.bus:getPendingInterruptVector()
	if vector == nil then
		return false
	end
	return self:_invokeInterrupt(vector, true)
end

function Cpu8086:_invokeInterrupt(vector, _hardware)
	vector = (tonumber(vector) or 0) % 0x100
	self.halted = false
	self:push16(self.flags)
	self:push16(self.seg.CS)
	self:push16(self.ip)
	self:setFlag(FLAG_IF, false)
	if self._bios and type(self._bios.handleInterrupt) == "function" then
		local handled = self._bios:handleInterrupt(self, vector)
		if handled then
			local returnIP = self:pop16()
			local returnCS = self:pop16()
			local savedFlags = self:pop16()
			local statusMask = bit32.bor(FLAG_CF, FLAG_ZF, FLAG_SF, FLAG_OF)
			self.ip = returnIP
			self.seg.CS = returnCS
			self.flags = bit32.bor(
				bit32.band(savedFlags, bit32.bnot(statusMask)),
				bit32.band(self.flags, statusMask),
				0x0002
			)
			self.stats.interrupts = self.stats.interrupts + 1
			return true
		end
	end

	local ivt = vector * 4
	local offset = self:readPhysical16(ivt)
	local segment = self:readPhysical16(ivt + 2)
	self.seg.CS = segment
	self.ip = offset
	self.stats.interrupts = self.stats.interrupts + 1
	return true
end

function Cpu8086:step()
	self.stats.cycles = self.stats.cycles + 1

	if self:_serviceExternalInterrupt() then
		self.stats.instructions = self.stats.instructions + 1
		return "INT"
	end

	if self.halted then
		return "HLT"
	end

	local startIP = self.ip
	local startCS = self.seg.CS
	local opcode = self:fetch8()
	self._lastStep.opcode = opcode
	self._lastStep.cs = startCS
	self._lastStep.ip = startIP

	if opcode >= 0xB8 and opcode <= 0xBF then
		self:setReg16(opcode - 0xB8, self:fetch16())
	elseif opcode >= 0xB0 and opcode <= 0xB7 then
		self:setReg8(opcode - 0xB0, self:fetch8())
	elseif opcode == 0x90 then
		-- nop
	elseif opcode == 0xFA then
		self:setFlag(FLAG_IF, false)
	elseif opcode == 0xFB then
		self:setFlag(FLAG_IF, true)
	elseif opcode == 0xF4 then
		self.halted = true
	elseif opcode >= 0x40 and opcode <= 0x47 then
		local reg = opcode - 0x40
		self:setReg16(reg, self:_add(16, self:getReg16(reg), 1))
	elseif opcode >= 0x48 and opcode <= 0x4F then
		local reg = opcode - 0x48
		self:setReg16(reg, self:_sub(16, self:getReg16(reg), 1))
	elseif opcode >= 0x50 and opcode <= 0x57 then
		self:push16(self:getReg16(opcode - 0x50))
	elseif opcode >= 0x58 and opcode <= 0x5F then
		self:setReg16(opcode - 0x58, self:pop16())
	elseif opcode == 0x68 then
		self:push16(self:fetch16())
	elseif opcode == 0x8E then
		local decoded = self:_decodeModRM()
		if decoded.reg == 1 then
			error("unsupported MOV CS, r/m16")
		end
		self:setSeg(decoded.reg, self:_readRM16(decoded))
	elseif opcode == 0x8C then
		local decoded = self:_decodeModRM()
		self:_writeRM16(decoded, self:getSeg(decoded.reg))
	elseif opcode == 0x8B then
		local decoded = self:_decodeModRM()
		self:setReg16(decoded.reg, self:_readRM16(decoded))
	elseif opcode == 0x89 then
		local decoded = self:_decodeModRM()
		self:_writeRM16(decoded, self:getReg16(decoded.reg))
	elseif opcode == 0x8A then
		local decoded = self:_decodeModRM()
		self:setReg8(decoded.reg, self:_readRM8(decoded))
	elseif opcode == 0x88 then
		local decoded = self:_decodeModRM()
		self:_writeRM8(decoded, self:getReg8(decoded.reg))
	elseif opcode == 0xC6 then
		local decoded = self:_decodeModRM()
		local imm = self:fetch8()
		self:_writeRM8(decoded, imm)
	elseif opcode == 0xC7 then
		local decoded = self:_decodeModRM()
		local imm = self:fetch16()
		self:_writeRM16(decoded, imm)
	elseif opcode == 0x33 then
		local decoded = self:_decodeModRM()
		local value = bit32.bxor(self:getReg16(decoded.reg), self:_readRM16(decoded))
		self:setReg16(decoded.reg, value)
		self:_updateLogicFlags(16, value)
	elseif opcode == 0x32 then
		local decoded = self:_decodeModRM()
		local value = bit32.bxor(self:getReg8(decoded.reg), self:_readRM8(decoded))
		self:setReg8(decoded.reg, value)
		self:_updateLogicFlags(8, value)
	elseif opcode == 0x80 or opcode == 0x81 then
		local decoded = self:_decodeModRM()
		local width = opcode == 0x80 and 8 or 16
		local imm = width == 8 and self:fetch8() or self:fetch16()
		local left = width == 8 and self:_readRM8(decoded) or self:_readRM16(decoded)
		if decoded.reg == 0 then
			local result = self:_add(width, left, imm)
			if width == 8 then
				self:_writeRM8(decoded, result)
			else
				self:_writeRM16(decoded, result)
			end
		elseif decoded.reg == 5 then
			local result = self:_sub(width, left, imm)
			if width == 8 then
				self:_writeRM8(decoded, result)
			else
				self:_writeRM16(decoded, result)
			end
		elseif decoded.reg == 7 then
			self:_sub(width, left, imm)
		else
			error("unsupported group 80/81 op")
		end
	elseif opcode == 0x38 then
		local decoded = self:_decodeModRM()
		self:_sub(8, self:_readRM8(decoded), self:getReg8(decoded.reg))
	elseif opcode == 0x39 then
		local decoded = self:_decodeModRM()
		self:_sub(16, self:_readRM16(decoded), self:getReg16(decoded.reg))
	elseif opcode == 0x3A then
		local decoded = self:_decodeModRM()
		self:_sub(8, self:getReg8(decoded.reg), self:_readRM8(decoded))
	elseif opcode == 0x3B then
		local decoded = self:_decodeModRM()
		self:_sub(16, self:getReg16(decoded.reg), self:_readRM16(decoded))
	elseif opcode == 0xE8 then
		local rel = signExtend16(self:fetch16())
		self:push16(self.ip)
		self.ip = (self.ip + rel) % 0x10000
	elseif opcode == 0xE9 then
		local rel = signExtend16(self:fetch16())
		self.ip = (self.ip + rel) % 0x10000
	elseif opcode == 0xEA then
		local offset = self:fetch16()
		local segment = self:fetch16()
		self.seg.CS = segment
		self.ip = offset
	elseif opcode == 0xEB then
		local rel = signExtend8(self:fetch8())
		self.ip = (self.ip + rel) % 0x10000
	elseif opcode == 0x74 then
		local rel = signExtend8(self:fetch8())
		if self:getFlag(FLAG_ZF) then
			self.ip = (self.ip + rel) % 0x10000
		end
	elseif opcode == 0x75 then
		local rel = signExtend8(self:fetch8())
		if not self:getFlag(FLAG_ZF) then
			self.ip = (self.ip + rel) % 0x10000
		end
	elseif opcode == 0x72 then
		local rel = signExtend8(self:fetch8())
		if self:getFlag(FLAG_CF) then
			self.ip = (self.ip + rel) % 0x10000
		end
	elseif opcode == 0x73 then
		local rel = signExtend8(self:fetch8())
		if not self:getFlag(FLAG_CF) then
			self.ip = (self.ip + rel) % 0x10000
		end
	elseif opcode == 0xFF then
		local decoded = self:_decodeModRM()
		if decoded.reg == 2 then
			self:push16(self.ip)
			self.ip = self:_readRM16(decoded)
		elseif decoded.reg == 4 then
			self.ip = self:_readRM16(decoded)
		else
			error(string.format("unsupported FF group /%d at %04X:%04X", decoded.reg, self.seg.CS, startIP))
		end
	elseif opcode == 0xC3 then
		self.ip = self:pop16()
	elseif opcode == 0xCB then
		self.ip = self:pop16()
		self.seg.CS = self:pop16()
	elseif opcode == 0xCF then
		self.ip = self:pop16()
		self.seg.CS = self:pop16()
		self.flags = self:pop16()
	elseif opcode == 0xCD then
		local vector = self:fetch8()
		self:_invokeInterrupt(vector, false)
	elseif opcode == 0xE4 then
		local port = self:fetch8()
		self.stats.portReads = self.stats.portReads + 1
		self:setReg8(0, self.bus:portRead(port))
	elseif opcode == 0xE5 then
		local port = self:fetch8()
		self.stats.portReads = self.stats.portReads + 1
		self:setReg16(0, self.bus:portRead16(port))
	elseif opcode == 0xEC then
		local port = self.reg16.DX
		self.stats.portReads = self.stats.portReads + 1
		self:setReg8(0, self.bus:portRead(port))
	elseif opcode == 0xED then
		local port = self.reg16.DX
		self.stats.portReads = self.stats.portReads + 1
		self:setReg16(0, self.bus:portRead16(port))
	elseif opcode == 0xE6 then
		local port = self:fetch8()
		self.stats.portWrites = self.stats.portWrites + 1
		self.bus:portWrite(port, self:getReg8(0))
	elseif opcode == 0xE7 then
		local port = self:fetch8()
		self.stats.portWrites = self.stats.portWrites + 1
		self.bus:portWrite16(port, self:getReg16(0))
	elseif opcode == 0xEE then
		local port = self.reg16.DX
		self.stats.portWrites = self.stats.portWrites + 1
		self.bus:portWrite(port, self:getReg8(0))
	elseif opcode == 0xEF then
		local port = self.reg16.DX
		self.stats.portWrites = self.stats.portWrites + 1
		self.bus:portWrite16(port, self:getReg16(0))
	else
		self._lastError = string.format(
			"unsupported opcode 0x%02X at %04X:%04X",
			opcode,
			self.seg.CS,
			startIP
		)
		self.halted = true
		error(self._lastError)
	end

	self.stats.instructions = self.stats.instructions + 1
	return opcode
end

return Cpu8086
