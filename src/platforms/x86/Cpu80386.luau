local Cpu8086 = require(script.Parent.Cpu8086)

local Cpu80386 = {}
Cpu80386.__index = Cpu80386
setmetatable(Cpu80386, { __index = Cpu8086 })

local FLAG_CF = 0x0001
local FLAG_ZF = 0x0040
local FLAG_SF = 0x0080
local FLAG_IF = 0x0200
local FLAG_OF = 0x0800

local REG32 = {
	"EAX",
	"ECX",
	"EDX",
	"EBX",
	"ESP",
	"EBP",
	"ESI",
	"EDI",
}

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

local function signExtend32(value)
	value = value % 0x100000000
	if value >= 0x80000000 then
		return value - 0x100000000
	end
	return value
end

local function maskForWidth(width)
	if width == 8 then
		return 0xFF
	elseif width == 16 then
		return 0xFFFF
	end
	return 0xFFFFFFFF
end

local function signBit(width)
	if width == 8 then
		return 0x80
	elseif width == 16 then
		return 0x8000
	end
	return 0x80000000
end

function Cpu80386.new(bus, config)
	local self = Cpu8086.new(bus, config)
	setmetatable(self, Cpu80386)
	self.gdtr = { base = 0, limit = 0 }
	self.idtr = { base = 0, limit = 0x03FF }
	self.cr0 = 0x0010
	self.protectedMode = false
	self.segCache = {}
	self.reg32 = {}
	self.eip = 0
	self:reset()
	return self
end

function Cpu80386:_segmentName(code)
	return ({ "ES", "CS", "SS", "DS" })[code + 1]
end

function Cpu80386:_syncRealModeSegment(name)
	local selector = self.seg[name] or 0
	self.segCache[name] = {
		selector = selector,
		base = (selector % 0x10000) * 16,
		limit = 0xFFFF,
		default32 = false,
		present = true,
	}
end

function Cpu80386:_syncRealModeCaches()
	self:_syncRealModeSegment("ES")
	self:_syncRealModeSegment("CS")
	self:_syncRealModeSegment("SS")
	self:_syncRealModeSegment("DS")
end

function Cpu80386:reset()
	Cpu8086.reset(self)
	self.reg32 = {
		EAX = 0,
		ECX = 0,
		EDX = 0,
		EBX = 0,
		ESP = 0,
		EBP = 0,
		ESI = 0,
		EDI = 0,
	}
	self.gdtr = { base = 0, limit = 0 }
	self.idtr = { base = 0, limit = 0x03FF }
	self.cr0 = 0x0010
	self.protectedMode = false
	self.segCache = {}
	self.eip = self.ip
	self:_syncRealModeCaches()
end

function Cpu80386:_codeDefault32()
	return self.protectedMode and self.segCache.CS and self.segCache.CS.default32 or false
end

function Cpu80386:_stackDefault32()
	return self.protectedMode and self.segCache.SS and self.segCache.SS.default32 or false
end

function Cpu80386:_currentIP()
	if self:_codeDefault32() then
		return (tonumber(self.eip) or 0) % 0x100000000
	end
	return (tonumber(self.ip) or 0) % 0x10000
end

function Cpu80386:_setInstructionPointer(value)
	local nextValue = tonumber(value) or 0
	if self:_codeDefault32() then
		self.eip = nextValue % 0x100000000
		self.ip = self.eip % 0x10000
	else
		self.ip = nextValue % 0x10000
		self.eip = self.ip
	end
end

function Cpu80386:getReg32(code)
	local name = REG32[(tonumber(code) or 0) + 1]
	if not name then
		return 0
	end
	return (self.reg32 and self.reg32[name] or 0) % 0x100000000
end

function Cpu80386:setReg32(code, value)
	local name = REG32[(tonumber(code) or 0) + 1]
	if not name then
		return
	end
	local masked = (tonumber(value) or 0) % 0x100000000
	self.reg32[name] = masked
	Cpu8086.setReg16(self, code, masked % 0x10000)
end

function Cpu80386:getReg16(code)
	return self:getReg32(code) % 0x10000
end

function Cpu80386:setReg16(code, value)
	local index = (tonumber(code) or 0)
	local name = REG32[index + 1]
	local masked = (tonumber(value) or 0) % 0x10000
	if name then
		local current = self.reg32[name] or 0
		self.reg32[name] = bit32.bor(bit32.band(current, 0xFFFF0000), masked)
	end
	Cpu8086.setReg16(self, index, masked)
end

function Cpu80386:getReg8(code)
	local regIndex = (tonumber(code) or 0) % 4
	local word = self:getReg16(regIndex)
	if code < 4 then
		return word % 0x100
	end
	return math.floor(word / 0x100) % 0x100
end

function Cpu80386:setReg8(code, value)
	local regIndex = (tonumber(code) or 0) % 4
	local word = self:getReg16(regIndex)
	local byteValue = (tonumber(value) or 0) % 0x100
	if code < 4 then
		self:setReg16(regIndex, bit32.bor(bit32.band(word, 0xFF00), byteValue))
	else
		self:setReg16(regIndex, bit32.bor(bit32.band(word, 0x00FF), bit32.lshift(byteValue, 8)))
	end
end

function Cpu80386:getLinearPC()
	return self:linearAddress("CS", self:_currentIP())
end

function Cpu80386:getStats()
	local stats = Cpu8086.getStats(self)
	stats.mode = self.protectedMode and "protected" or "real"
	stats.protectedMode = self.protectedMode
	stats.cr0 = self.cr0
	stats.gdtBase = self.gdtr.base
	stats.gdtLimit = self.gdtr.limit
	stats.idtBase = self.idtr.base
	stats.idtLimit = self.idtr.limit
	stats.eip = self.eip
	stats.esp = self:getReg32(4)
	return stats
end

function Cpu80386:_physicalAddress(address)
	local value = tonumber(address) or 0
	if self.protectedMode then
		return value
	end
	return bit32.band(value, 0xFFFFF)
end

function Cpu80386:readPhysical8(address)
	self.stats.memReads = self.stats.memReads + 1
	return self.bus:memRead(self:_physicalAddress(address))
end

function Cpu80386:writePhysical8(address, value)
	self.stats.memWrites = self.stats.memWrites + 1
	self.bus:memWrite(self:_physicalAddress(address), value % 0x100)
end

function Cpu80386:readPhysical16(address)
	local lo = self:readPhysical8(address)
	local hi = self:readPhysical8(address + 1)
	return lo + hi * 0x100
end

function Cpu80386:readPhysical32(address)
	local b0 = self:readPhysical8(address)
	local b1 = self:readPhysical8(address + 1)
	local b2 = self:readPhysical8(address + 2)
	local b3 = self:readPhysical8(address + 3)
	return b0 + b1 * 0x100 + b2 * 0x10000 + b3 * 0x1000000
end

function Cpu80386:writePhysical16(address, value)
	local v = (tonumber(value) or 0) % 0x10000
	self:writePhysical8(address, v % 0x100)
	self:writePhysical8(address + 1, math.floor(v / 0x100) % 0x100)
end

function Cpu80386:writePhysical32(address, value)
	local v = (tonumber(value) or 0) % 0x100000000
	self:writePhysical8(address, v % 0x100)
	self:writePhysical8(address + 1, math.floor(v / 0x100) % 0x100)
	self:writePhysical8(address + 2, math.floor(v / 0x10000) % 0x100)
	self:writePhysical8(address + 3, math.floor(v / 0x1000000) % 0x100)
end

function Cpu80386:readMem32(segment, offset)
	return self:readPhysical32(self:linearAddress(segment, offset))
end

function Cpu80386:writeMem32(segment, offset, value)
	self:writePhysical32(self:linearAddress(segment, offset), value)
end

function Cpu80386:fetch8()
	local value = self:readMem8(self.seg.CS, self:_currentIP())
	self:_setInstructionPointer(self:_currentIP() + 1)
	return value
end

function Cpu80386:fetch16()
	local lo = self:fetch8()
	local hi = self:fetch8()
	return lo + hi * 0x100
end

function Cpu80386:fetch32()
	local w0 = self:fetch16()
	local w1 = self:fetch16()
	return w0 + w1 * 0x10000
end

function Cpu80386:_operand32Enabled(operandOverride)
	local default32 = self:_codeDefault32()
	if operandOverride then
		return not default32
	end
	return default32
end

function Cpu80386:_address32Enabled(addressOverride)
	local default32 = self:_codeDefault32()
	if addressOverride then
		return not default32
	end
	return default32
end

function Cpu80386:_operandWidth(operandOverride)
	return self:_operand32Enabled(operandOverride) and 32 or 16
end

function Cpu80386:_fetchImmediate(width)
	if width == 8 then
		return self:fetch8()
	elseif width == 16 then
		return self:fetch16()
	end
	return self:fetch32()
end

function Cpu80386:_readRM32(decoded)
	if decoded.mod == 3 then
		return self:getReg32(decoded.rm)
	end
	local segment, offset = self:_effectiveAddress(decoded)
	return self:readMem32(segment, offset)
end

function Cpu80386:_writeRM32(decoded, value)
	if decoded.mod == 3 then
		self:setReg32(decoded.rm, value)
		return
	end
	local segment, offset = self:_effectiveAddress(decoded)
	self:writeMem32(segment, offset, value)
end

function Cpu80386:_readRMByWidth(decoded, width)
	if width == 8 then
		return self:_readRM8(decoded)
	elseif width == 16 then
		return self:_readRM16(decoded)
	end
	return self:_readRM32(decoded)
end

function Cpu80386:_writeRMByWidth(decoded, width, value)
	if width == 8 then
		self:_writeRM8(decoded, value)
	elseif width == 16 then
		self:_writeRM16(decoded, value)
	else
		self:_writeRM32(decoded, value)
	end
end

function Cpu80386:_getRegByWidth(code, width)
	if width == 8 then
		return self:getReg8(code)
	elseif width == 16 then
		return self:getReg16(code)
	end
	return self:getReg32(code)
end

function Cpu80386:_setRegByWidth(code, width, value)
	if width == 8 then
		self:setReg8(code, value)
	elseif width == 16 then
		self:setReg16(code, value)
	else
		self:setReg32(code, value)
	end
end

function Cpu80386:_decodeModRMForAddressSize(addressOverride)
	if not self:_address32Enabled(addressOverride) then
		local decoded = self:_decodeModRM()
		decoded.addressWidth = 16
		return decoded
	end

	local byte = self:fetch8()
	local mod = bit32.rshift(byte, 6)
	local reg = bit32.band(bit32.rshift(byte, 3), 0x07)
	local rm = bit32.band(byte, 0x07)
	local sib = nil
	local disp = 0

	if mod ~= 3 and rm == 4 then
		local sibByte = self:fetch8()
		sib = {
			scale = bit32.lshift(1, bit32.rshift(sibByte, 6)),
			index = bit32.band(bit32.rshift(sibByte, 3), 0x07),
			base = bit32.band(sibByte, 0x07),
		}
	end

	if mod == 0 then
		if rm == 5 or (sib and sib.base == 5) then
			disp = signExtend32(self:fetch32())
		end
	elseif mod == 1 then
		disp = signExtend8(self:fetch8())
	elseif mod == 2 then
		disp = signExtend32(self:fetch32())
	end

	return {
		mod = mod,
		reg = reg,
		rm = rm,
		disp = disp,
		sib = sib,
		addressWidth = 32,
	}
end

function Cpu80386:_effectiveAddress(decoded)
	if decoded.mod == 3 then
		return nil, nil
	end
	if decoded.addressWidth ~= 32 then
		return Cpu8086._effectiveAddress(self, decoded)
	end

	local base = 0
	local segment = self.seg.DS
	local usesStackSegment = false
	local sib = decoded.sib

	if sib then
		if not (decoded.mod == 0 and sib.base == 5) then
			base = self:getReg32(sib.base)
			usesStackSegment = sib.base == 4 or sib.base == 5
		end
		if sib.index ~= 4 then
			base = (base + ((self:getReg32(sib.index) * sib.scale) % 0x100000000)) % 0x100000000
		end
	else
		if not (decoded.mod == 0 and decoded.rm == 5) then
			base = self:getReg32(decoded.rm)
			usesStackSegment = decoded.rm == 4 or decoded.rm == 5
		end
	end

	if usesStackSegment then
		segment = self.seg.SS
	end

	local offset = (base + (tonumber(decoded.disp) or 0)) % 0x100000000
	return segment, offset
end

function Cpu80386:_portReadByWidth(port, width)
	if width == 8 then
		return self.bus:portRead(port)
	elseif width == 16 then
		return self.bus:portRead16(port)
	end
	if type(self.bus.portRead32) == "function" then
		return self.bus:portRead32(port)
	end
	local lo = self.bus:portRead16(port)
	local hi = self.bus:portRead16(port + 2)
	return lo + hi * 0x10000
end

function Cpu80386:_portWriteByWidth(port, width, value)
	if width == 8 then
		self.bus:portWrite(port, value)
	elseif width == 16 then
		self.bus:portWrite16(port, value)
	elseif type(self.bus.portWrite32) == "function" then
		self.bus:portWrite32(port, value)
	else
		local masked = (tonumber(value) or 0) % 0x100000000
		self.bus:portWrite16(port, masked % 0x10000)
		self.bus:portWrite16(port + 2, math.floor(masked / 0x10000) % 0x10000)
	end
end

function Cpu80386:push32(value)
	local sp = self:_stackDefault32() and self:getReg32(4) or self:getReg16(4)
	sp = (sp - 4) % 0x100000000
	if self:_stackDefault32() then
		self:setReg32(4, sp)
	else
		self:setReg16(4, sp % 0x10000)
	end
	self:writeMem32(self.seg.SS, sp, value)
end

function Cpu80386:pop32()
	local sp = self:_stackDefault32() and self:getReg32(4) or self:getReg16(4)
	local value = self:readMem32(self.seg.SS, sp)
	sp = (sp + 4) % 0x100000000
	if self:_stackDefault32() then
		self:setReg32(4, sp)
	else
		self:setReg16(4, sp % 0x10000)
	end
	return value
end

function Cpu80386:_updateLogicFlags(width, value)
	local mask = maskForWidth(width)
	local masked = value % (mask + 1)
	self:setFlag(FLAG_CF, false)
	self:setFlag(FLAG_OF, false)
	self:setFlag(FLAG_ZF, masked == 0)
	self:setFlag(FLAG_SF, bit32.band(masked, signBit(width)) ~= 0)
end

function Cpu80386:_add(width, a, b)
	local mask = maskForWidth(width)
	local result = (a + b) % (mask + 1)
	self:setFlag(FLAG_CF, a + b > mask)
	self:setFlag(FLAG_ZF, result == 0)
	self:setFlag(FLAG_SF, bit32.band(result, signBit(width)) ~= 0)
	local overflow = bit32.band(bit32.bnot(bit32.bxor(a, b)), bit32.bxor(a, result), signBit(width)) ~= 0
	self:setFlag(FLAG_OF, overflow)
	return result
end

function Cpu80386:_sub(width, a, b)
	local mask = maskForWidth(width)
	local result = (a - b) % (mask + 1)
	self:setFlag(FLAG_CF, a < b)
	self:setFlag(FLAG_ZF, result == 0)
	self:setFlag(FLAG_SF, bit32.band(result, signBit(width)) ~= 0)
	local overflow = bit32.band(bit32.bxor(a, b), bit32.bxor(a, result), signBit(width)) ~= 0
	self:setFlag(FLAG_OF, overflow)
	return result
end

function Cpu80386:_decodeDescriptor(selector)
	local value = (tonumber(selector) or 0) % 0x10000
	if value == 0 then
		return nil, "null selector"
	end
	if bit32.band(value, 0x04) ~= 0 then
		return nil, "ldt selectors are not supported"
	end

	local index = bit32.rshift(value, 3)
	local offset = index * 8
	if (offset + 7) > (self.gdtr.limit or 0) then
		return nil, "selector outside gdt limit"
	end

	local baseAddress = (self.gdtr.base or 0) + offset
	local b0 = self:readPhysical8(baseAddress + 0)
	local b1 = self:readPhysical8(baseAddress + 1)
	local b2 = self:readPhysical8(baseAddress + 2)
	local b3 = self:readPhysical8(baseAddress + 3)
	local b4 = self:readPhysical8(baseAddress + 4)
	local b5 = self:readPhysical8(baseAddress + 5)
	local b6 = self:readPhysical8(baseAddress + 6)
	local b7 = self:readPhysical8(baseAddress + 7)

	if bit32.band(b5, 0x80) == 0 then
		return nil, "descriptor not present"
	end

	local limit = b0 + b1 * 0x100 + bit32.lshift(bit32.band(b6, 0x0F), 16)
	if bit32.band(b6, 0x80) ~= 0 then
		limit = limit * 0x1000 + 0x0FFF
	end

	local base = b2 + b3 * 0x100 + b4 * 0x10000 + b7 * 0x1000000
	return {
		selector = value,
		base = base,
		limit = limit,
		access = b5,
		flags = b6,
		default32 = bit32.band(b6, 0x40) ~= 0,
		present = true,
	}
end

function Cpu80386:_segmentCacheFor(segment)
	if type(segment) == "string" then
		return self.segCache[segment]
	end

	local value = (tonumber(segment) or 0) % 0x10000
	if value == self.seg.CS then
		return self.segCache.CS
	end
	if value == self.seg.SS then
		return self.segCache.SS
	end
	if value == self.seg.DS then
		return self.segCache.DS
	end
	if value == self.seg.ES then
		return self.segCache.ES
	end

	local descriptor = self:_decodeDescriptor(value)
	if descriptor then
		return descriptor
	end
	return nil
end

function Cpu80386:linearAddress(segment, offset)
	if not self.protectedMode then
		return bit32.band(((tonumber(segment) or 0) % 0x10000) * 16 + ((tonumber(offset) or 0) % 0x10000), 0xFFFFF)
	end

	local descriptor = self:_segmentCacheFor(segment)
	if not descriptor then
		error("segment translation failed for selector " .. tostring(segment))
	end

	local logical = tonumber(offset) or 0
	if logical < 0 or logical > (descriptor.limit or 0xFFFFFFFF) then
		error(string.format("segment limit exceeded selector=%s offset=%X", tostring(segment), logical))
	end
	return descriptor.base + logical
end

function Cpu80386:setSeg(code, value)
	Cpu8086.setSeg(self, code, value)
	local name = self:_segmentName(code)
	if not name then
		return
	end

	if self.protectedMode then
		local descriptor, err = self:_decodeDescriptor(value)
		if not descriptor then
			error(err or "invalid protected-mode selector")
		end
		self.segCache[name] = descriptor
	else
		self:_syncRealModeSegment(name)
	end
end

function Cpu80386:_loadTableRegister(decoded, target)
	if decoded.mod == 3 then
		error(target:upper() .. " requires a memory operand")
	end
	local segment, offset = self:_effectiveAddress(decoded)
	local limit = self:readMem16(segment, offset)
	local baseLo = self:readMem16(segment, offset + 2)
	local baseHi = self:readMem16(segment, offset + 4)
	self[target] = {
		base = baseLo + baseHi * 0x10000,
		limit = limit,
	}
end

function Cpu80386:_decodeInterruptGate(vector)
	local entryOffset = ((tonumber(vector) or 0) % 0x100) * 8
	if (entryOffset + 7) > (self.idtr.limit or 0) then
		return nil, "interrupt vector outside idt limit"
	end

	local base = (self.idtr.base or 0) + entryOffset
	local offsetLo = self:readPhysical16(base + 0)
	local selector = self:readPhysical16(base + 2)
	local typeAttr = self:readPhysical8(base + 5)
	local offsetHi = self:readPhysical16(base + 6)
	local present = bit32.band(typeAttr, 0x80) ~= 0
	local gateType = bit32.band(typeAttr, 0x1F)
	local isSupported = gateType == 0x06 or gateType == 0x07 or gateType == 0x0E or gateType == 0x0F
	if not present then
		return nil, "interrupt gate not present"
	end
	if not isSupported then
		return nil, string.format("unsupported protected-mode gate type 0x%02X", gateType)
	end

	return {
		selector = selector,
		offset = offsetLo + offsetHi * 0x10000,
		trapGate = gateType == 0x07 or gateType == 0x0F,
		gate32 = gateType == 0x0E or gateType == 0x0F,
	}
end

function Cpu80386:_invokeInterrupt(vector, hardware)
	self.halted = false
	if self.protectedMode then
		local gate, err = self:_decodeInterruptGate(vector)
		if not gate then
			error(string.format("protected-mode interrupt 0x%02X failed: %s", vector, tostring(err)))
		end

		if gate.gate32 then
			self:push32(self.flags)
			self:push32(self.seg.CS)
			self:push32(self:_currentIP())
		else
			self:push16(self.flags)
			self:push16(self.seg.CS)
			self:push16(self:_currentIP() % 0x10000)
		end
		if not gate.trapGate then
			self:setFlag(FLAG_IF, false)
		end
		self:setSeg(1, gate.selector)
		self:_setInstructionPointer(gate.offset)
		self.stats.interrupts = self.stats.interrupts + 1
		return true
	end
	return Cpu8086._invokeInterrupt(self, vector, hardware)
end

function Cpu80386:step()
	self.stats.cycles = self.stats.cycles + 1

	if self:_serviceExternalInterrupt() then
		self.stats.instructions = self.stats.instructions + 1
		return "INT"
	end

	if self.halted then
		return "HLT"
	end

	local startIP = self:_currentIP()
	local startCS = self.seg.CS
	local operandOverride = false
	local addressOverride = false
	local opcode = self:fetch8()
	while opcode == 0x66 or opcode == 0x67 do
		if opcode == 0x66 then
			operandOverride = not operandOverride
		else
			addressOverride = not addressOverride
		end
		opcode = self:fetch8()
	end
	local operandWidth = self:_operandWidth(operandOverride)
	self._lastStep.opcode = opcode
	self._lastStep.cs = startCS
	self._lastStep.ip = startIP % 0x10000
	self._lastStep.eip = startIP

	if opcode == 0x0F then
		local extended = self:fetch8()
		self._lastStep.opcode = bit32.bor(0x0F00, extended)
		if extended == 0x01 then
			local decoded = self:_decodeModRMForAddressSize(addressOverride)
			if decoded.reg == 2 then
				self:_loadTableRegister(decoded, "gdtr")
			elseif decoded.reg == 3 then
				self:_loadTableRegister(decoded, "idtr")
			elseif decoded.reg == 4 then
				self:_writeRM16(decoded, bit32.band(self.cr0, 0xFFFF))
			elseif decoded.reg == 6 then
				local value = self:_readRM16(decoded)
				self.cr0 = bit32.bor(bit32.band(self.cr0, bit32.bnot(0x0F)), bit32.band(value, 0x0F))
				if bit32.band(self.cr0, 0x0001) ~= 0 then
					self.protectedMode = true
				else
					self.protectedMode = false
					self:_syncRealModeCaches()
				end
			else
				error(string.format("unsupported 0F 01 group /%d", decoded.reg))
			end
		else
			error(string.format("unsupported 0F opcode 0x%02X", extended))
		end
		self.stats.instructions = self.stats.instructions + 1
		return self._lastStep.opcode
	end

	if opcode >= 0xB8 and opcode <= 0xBF then
		self:_setRegByWidth(opcode - 0xB8, operandWidth, self:_fetchImmediate(operandWidth))
	elseif opcode >= 0xB0 and opcode <= 0xB7 then
		self:setReg8(opcode - 0xB0, self:fetch8())
	--elseif opcode == 0x90 then
	elseif opcode == 0xFA then
		self:setFlag(FLAG_IF, false)
	elseif opcode == 0xFB then
		self:setFlag(FLAG_IF, true)
	elseif opcode == 0xF4 then
		self.halted = true
	elseif opcode >= 0x40 and opcode <= 0x47 then
		local reg = opcode - 0x40
		self:_setRegByWidth(reg, operandWidth, self:_add(operandWidth, self:_getRegByWidth(reg, operandWidth), 1))
	elseif opcode >= 0x48 and opcode <= 0x4F then
		local reg = opcode - 0x48
		self:_setRegByWidth(reg, operandWidth, self:_sub(operandWidth, self:_getRegByWidth(reg, operandWidth), 1))
	elseif opcode >= 0x50 and opcode <= 0x57 then
		if operandWidth == 32 then
			self:push32(self:getReg32(opcode - 0x50))
		else
			self:push16(self:getReg16(opcode - 0x50))
		end
	elseif opcode >= 0x58 and opcode <= 0x5F then
		if operandWidth == 32 then
			self:setReg32(opcode - 0x58, self:pop32())
		else
			self:setReg16(opcode - 0x58, self:pop16())
		end
	elseif opcode == 0x68 then
		if operandWidth == 32 then
			self:push32(self:fetch32())
		else
			self:push16(self:fetch16())
		end
	elseif opcode == 0x8E then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		if decoded.reg == 1 then
			error("unsupported MOV CS, r/m16")
		end
		self:setSeg(decoded.reg, self:_readRM16(decoded))
	elseif opcode == 0x8C then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		self:_writeRM16(decoded, self:getSeg(decoded.reg))
	elseif opcode == 0x8B then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		self:_setRegByWidth(decoded.reg, operandWidth, self:_readRMByWidth(decoded, operandWidth))
	elseif opcode == 0x89 then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		self:_writeRMByWidth(decoded, operandWidth, self:_getRegByWidth(decoded.reg, operandWidth))
	elseif opcode == 0x8A then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		self:setReg8(decoded.reg, self:_readRM8(decoded))
	elseif opcode == 0x88 then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		self:_writeRM8(decoded, self:getReg8(decoded.reg))
	elseif opcode == 0xC6 then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		local imm = self:fetch8()
		self:_writeRM8(decoded, imm)
	elseif opcode == 0xC7 then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		local imm = self:_fetchImmediate(operandWidth)
		self:_writeRMByWidth(decoded, operandWidth, imm)
	elseif opcode == 0x33 then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		local value =
			bit32.bxor(self:_getRegByWidth(decoded.reg, operandWidth), self:_readRMByWidth(decoded, operandWidth))
		self:_setRegByWidth(decoded.reg, operandWidth, value)
		self:_updateLogicFlags(operandWidth, value)
	elseif opcode == 0x32 then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		local value = bit32.bxor(self:getReg8(decoded.reg), self:_readRM8(decoded))
		self:setReg8(decoded.reg, value)
		self:_updateLogicFlags(8, value)
	elseif opcode == 0x80 or opcode == 0x81 then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		local width = opcode == 0x80 and 8 or operandWidth
		local imm = self:_fetchImmediate(width)
		local left = self:_readRMByWidth(decoded, width)
		if decoded.reg == 0 then
			local result = self:_add(width, left, imm)
			self:_writeRMByWidth(decoded, width, result)
		elseif decoded.reg == 5 then
			local result = self:_sub(width, left, imm)
			self:_writeRMByWidth(decoded, width, result)
		elseif decoded.reg == 7 then
			self:_sub(width, left, imm)
		else
			error("unsupported group 80/81 op")
		end
	elseif opcode == 0x38 then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		self:_sub(8, self:_readRM8(decoded), self:getReg8(decoded.reg))
	elseif opcode == 0x39 then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		self:_sub(
			operandWidth,
			self:_readRMByWidth(decoded, operandWidth),
			self:_getRegByWidth(decoded.reg, operandWidth)
		)
	elseif opcode == 0x3A then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		self:_sub(8, self:getReg8(decoded.reg), self:_readRM8(decoded))
	elseif opcode == 0x3B then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		self:_sub(
			operandWidth,
			self:_getRegByWidth(decoded.reg, operandWidth),
			self:_readRMByWidth(decoded, operandWidth)
		)
	elseif opcode == 0xE8 then
		local rel = operandWidth == 32 and signExtend32(self:fetch32()) or signExtend16(self:fetch16())
		local returnIP = self:_currentIP()
		if operandWidth == 32 then
			self:push32(returnIP)
		else
			self:push16(returnIP % 0x10000)
		end
		self:_setInstructionPointer(returnIP + rel)
	elseif opcode == 0xE9 then
		local rel = operandWidth == 32 and signExtend32(self:fetch32()) or signExtend16(self:fetch16())
		self:_setInstructionPointer(self:_currentIP() + rel)
	elseif opcode == 0xEA then
		local offset = self:fetch16()
		local segment = self:fetch16()
		self:setSeg(1, segment)
		self:_setInstructionPointer(offset)
	elseif opcode == 0xEB then
		local rel = signExtend8(self:fetch8())
		self:_setInstructionPointer(self:_currentIP() + rel)
	elseif opcode == 0x74 then
		local rel = signExtend8(self:fetch8())
		if self:getFlag(FLAG_ZF) then
			self:_setInstructionPointer(self:_currentIP() + rel)
		end
	elseif opcode == 0x75 then
		local rel = signExtend8(self:fetch8())
		if not self:getFlag(FLAG_ZF) then
			self:_setInstructionPointer(self:_currentIP() + rel)
		end
	elseif opcode == 0x72 then
		local rel = signExtend8(self:fetch8())
		if self:getFlag(FLAG_CF) then
			self:_setInstructionPointer(self:_currentIP() + rel)
		end
	elseif opcode == 0x73 then
		local rel = signExtend8(self:fetch8())
		if not self:getFlag(FLAG_CF) then
			self:_setInstructionPointer(self:_currentIP() + rel)
		end
	elseif opcode == 0xFF then
		local decoded = self:_decodeModRMForAddressSize(addressOverride)
		if decoded.reg == 2 then
			local returnIP = self:_currentIP()
			if operandWidth == 32 then
				self:push32(returnIP)
			else
				self:push16(returnIP % 0x10000)
			end
			self:_setInstructionPointer(self:_readRMByWidth(decoded, operandWidth))
		elseif decoded.reg == 4 then
			self:_setInstructionPointer(self:_readRMByWidth(decoded, operandWidth))
		else
			error(string.format("unsupported FF group /%d at %04X:%04X", decoded.reg, self.seg.CS, startIP))
		end
	elseif opcode == 0xC3 then
		if operandWidth == 32 then
			self:_setInstructionPointer(self:pop32())
		else
			self:_setInstructionPointer(self:pop16())
		end
	elseif opcode == 0xCB then
		local nextIP = operandWidth == 32 and self:pop32() or self:pop16()
		local nextCS = operandWidth == 32 and self:pop32() or self:pop16()
		self:setSeg(1, nextCS % 0x10000)
		self:_setInstructionPointer(nextIP)
	elseif opcode == 0xCF then
		local nextIP = operandWidth == 32 and self:pop32() or self:pop16()
		local nextCS = operandWidth == 32 and self:pop32() or self:pop16()
		local nextFlags = operandWidth == 32 and self:pop32() or self:pop16()
		self:setSeg(1, nextCS % 0x10000)
		self:_setInstructionPointer(nextIP)
		self.flags = nextFlags % 0x10000
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
		self:_setRegByWidth(0, operandWidth, self:_portReadByWidth(port, operandWidth))
	elseif opcode == 0xEC then
		local port = self.reg16.DX
		self.stats.portReads = self.stats.portReads + 1
		self:setReg8(0, self.bus:portRead(port))
	elseif opcode == 0xED then
		local port = self.reg16.DX
		self.stats.portReads = self.stats.portReads + 1
		self:_setRegByWidth(0, operandWidth, self:_portReadByWidth(port, operandWidth))
	elseif opcode == 0xE6 then
		local port = self:fetch8()
		self.stats.portWrites = self.stats.portWrites + 1
		self.bus:portWrite(port, self:getReg8(0))
	elseif opcode == 0xE7 then
		local port = self:fetch8()
		self.stats.portWrites = self.stats.portWrites + 1
		self:_portWriteByWidth(port, operandWidth, self:_getRegByWidth(0, operandWidth))
	elseif opcode == 0xEE then
		local port = self.reg16.DX
		self.stats.portWrites = self.stats.portWrites + 1
		self.bus:portWrite(port, self:getReg8(0))
	elseif opcode == 0xEF then
		local port = self.reg16.DX
		self.stats.portWrites = self.stats.portWrites + 1
		self:_portWriteByWidth(port, operandWidth, self:_getRegByWidth(0, operandWidth))
	else
		self._lastError = string.format("unsupported opcode 0x%02X at %04X:%08X", opcode, self.seg.CS, startIP)
		self.halted = true
		error(self._lastError)
	end

	self.stats.instructions = self.stats.instructions + 1
	return opcode
end

return Cpu80386
