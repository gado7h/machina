-- CPU module

local CPU = {}
CPU.__index = CPU

local OP = {
	NOP = 0,
	MOV = 1,
	MOVI = 2,
	ADD = 3,
	ADDI = 4,
	SUB = 5,
	SUBI = 6,
	MUL = 7,
	DIV = 8,
	AND = 9,
	OR = 10,
	XOR = 11,
	NOT = 12,
	SHL = 13,
	SHR = 14,
	SAR = 15,
	CMP = 16,
	CMPI = 17,
	JMP = 18,
	JMPI = 19,
	JEQ = 20,
	JNE = 21,
	JLT = 22,
	JGT = 23,
	JLE = 24,
	JGE = 25,
	CALL = 26,
	RET = 27,
	LW = 28,
	SW = 29,
	LB = 30,
	SB = 31,
	PUSH = 32,
	POP = 33,
	INT = 34,
	IRET = 35,
	IN = 36,
	OUT = 37,
	HLT = 38,
	LMOVI = 39,
	INC = 40,
	DEC = 41,
	MOD = 42,
	NEG = 43,
}

local OP_NAME = {}
for k, v in pairs(OP) do
	OP_NAME[v] = k
end

local FLAG_CF = 1
local FLAG_ZF = 2
local FLAG_SF = 4
local FLAG_OF = 8
local FLAG_IF = 16
local FLAG_HLT = 32

local CR0_PG = 0x80000000

local REG_IDX = {}
local REG_NAMES =
	{ "R0", "R1", "R2", "R3", "R4", "R5", "R6", "R7", "PC", "SP", "LR", "FLAGS", "CR0", "CR3", "IDTR", "TR" }
for i, n in ipairs(REG_NAMES) do
	REG_IDX[n] = i
end

function CPU.new(bus, config)
	local self = setmetatable({}, CPU)
	self.bus = bus
	self.config = config

	self.reg = {}
	for i = 1, #REG_NAMES do
		self.reg[i] = 0
	end

	self._R = self.reg
	self.pipeline = { IF = "NOP", ID = "NOP", RF = "NOP", EX = "NOP", MA = "NOP", WB = "NOP" }
	self.pipelineActive = {}

	self._idtBase = 0
	self._pendingSWInterrupts = {}
	self._interruptStack = {}
	self._lastInterruptVector = nil
	self._inTrap = false

	self.stats = {
		cycles = 0,
		instructions = 0,
		interrupts = 0,
		branches = 0,
		branchMispredicts = 0,
		memReads = 0,
		memWrites = 0,
		cacheHits = { L1I = 0, L1D = 0, L2 = 0, L3 = 0 },
		cacheMisses = { L1I = 0, L1D = 0 },
		tlbHits = 0,
		tlbMisses = 0,
		exceptions = 0,
		guestSessions = 0,
		guestSessionFaults = 0,
	}

	self._icache = {}
	self._dcache = {}
	self._tlb = {}
	self._tlbLimit = 64
	self._tlbCount = 0
	self._branchPredictor = {}
	for i = 0, 1023 do
		self._branchPredictor[i] = 2
	end
	self._managedRuntimes = {}
	self._defaultManagedRuntime = nil
	self._guestBackends = {}
	self._defaultGuestBackend = nil
	self._guestSessionQueue = {}
	self._guestSessions = {}
	self._guestSessionSerial = 1
	self._guestLastSessionId = nil

	self._latchIF = nil
	self._latchID = nil
	self._latchEX = nil
	self._latchMA = nil

	self:reset()
	return self
end

function CPU:reset()
	for i = 1, #REG_NAMES do
		self.reg[i] = 0
	end
	self.reg[REG_IDX.PC] = self.config.ROM_BASE
	self.reg[REG_IDX.SP] = self.config.RAM_BASE + self.config.RAM_SIZE - 4
	self.reg[REG_IDX.FLAGS] = FLAG_IF
	self._icache = {}
	self._dcache = {}
	self._tlb = {}
	self._tlbCount = 0
	self._pendingSWInterrupts = {}
	self._interruptStack = {}
	self._lastInterruptVector = nil
	self._inTrap = false
	self.stats.cycles = 0
	self.stats.instructions = 0
	self.stats.branchMispredicts = 0
	self.stats.tlbHits = 0
	self.stats.tlbMisses = 0
	self.stats.exceptions = 0
	self.stats.guestSessions = 0
	self.stats.guestSessionFaults = 0
	for i = 0, 1023 do
		self._branchPredictor[i] = 2
	end
	self._latchIF = nil
	self._latchID = nil
	self._latchEX = nil
	self._latchMA = nil
	self._managedRuntimes = {}
	self._defaultManagedRuntime = nil
	self._guestBackends = {}
	self._defaultGuestBackend = nil
	self._guestSessionQueue = {}
	self._guestSessions = {}
	self._guestSessionSerial = 1
	self._guestLastSessionId = nil
end

function CPU:getReg(name)
	local idx = REG_IDX[name]
	if not idx then
		error("CPU: unknown register " .. tostring(name))
	end
	return self.reg[idx]
end

function CPU:setReg(name, value)
	local idx = REG_IDX[name]
	if not idx then
		error("CPU: unknown register " .. tostring(name))
	end
	if name == "R0" then
		return
	end
	self.reg[idx] = value % 0x100000000
end

function CPU:getRegIdx(i)
	return self.reg[i] or 0
end

function CPU:setRegIdx(i, v)
	if i == 1 then
		return
	end
	self.reg[i] = v % 0x100000000
end

function CPU:flag(bit)
	return (self.reg[REG_IDX.FLAGS] % (bit * 2)) >= bit
end

function CPU:setFlag(bit, v)
	if v then
		self.reg[REG_IDX.FLAGS] = self.reg[REG_IDX.FLAGS] + (self:flag(bit) and 0 or bit)
	elseif self:flag(bit) then
		self.reg[REG_IDX.FLAGS] = self.reg[REG_IDX.FLAGS] - bit
	end
end

local function toSigned32(v)
	if v >= 0x80000000 then
		return v - 0x100000000
	end
	return v
end

local function signExt16(v)
	if v >= 0x8000 then
		return v - 0x10000
	end
	return v
end

function CPU:alu(op, a, b)
	local r, cf, of = 0, false, false
	if op == "ADD" or op == "ADDI" then
		local s = a + b
		cf = s >= 0x100000000
		r = s % 0x100000000
		of = (toSigned32(a) >= 0) == (toSigned32(b) >= 0) and (toSigned32(a) >= 0) ~= (toSigned32(r) >= 0)
	elseif op == "SUB" or op == "SUBI" or op == "CMP" or op == "CMPI" then
		local s = a - b
		cf = s < 0
		r = s % 0x100000000
		of = (toSigned32(a) >= 0) ~= (toSigned32(b) >= 0) and (toSigned32(a) >= 0) ~= (toSigned32(r) >= 0)
	elseif op == "MUL" then
		r = (a * b) % 0x100000000
	elseif op == "DIV" then
		r = b ~= 0 and math.floor(a / b) or 0
	elseif op == "MOD" then
		r = b ~= 0 and (a % b) or 0
	elseif op == "AND" then
		r = bit32.band(a, b)
	elseif op == "OR" then
		r = bit32.bor(a, b)
	elseif op == "XOR" then
		r = bit32.bxor(a, b)
	elseif op == "NOT" then
		r = bit32.bnot(a)
	elseif op == "NEG" then
		r = (-toSigned32(a)) % 0x100000000
	elseif op == "SHL" then
		r = (a * (2 ^ b)) % 0x100000000
	elseif op == "SHR" then
		r = math.floor(a / (2 ^ b))
	elseif op == "SAR" then
		local sa = toSigned32(a)
		r = math.floor(sa / (2 ^ b)) % 0x100000000
	elseif op == "INC" then
		r = (a + 1) % 0x100000000
	elseif op == "DEC" then
		r = (a - 1) % 0x100000000
	end
	return r, cf, r == 0, r >= 0x80000000, of
end

function CPU:fetch(addr)
	local cline = addr % (256 * 4)
	if self._icache[cline] and self._icache[cline].addr == addr then
		self.stats.cacheHits.L1I = self.stats.cacheHits.L1I + 1
		return self._icache[cline].data
	end
	self.stats.cacheMisses.L1I = self.stats.cacheMisses.L1I + 1
	local w = self.bus:memRead32(addr)
	self._icache[cline] = { addr = addr, data = w }
	return w
end

local function bpIndex(pc)
	return pc % 1024
end

function CPU:_predictBranch(pc)
	local state = self._branchPredictor[bpIndex(pc)] or 1
	return state >= 2
end

function CPU:_trainBranch(pc, taken)
	local idx = bpIndex(pc)
	local state = self._branchPredictor[idx] or 1
	if taken then
		state = math.min(3, state + 1)
	else
		state = math.max(0, state - 1)
	end
	self._branchPredictor[idx] = state
end

function CPU:_translateAddress(vaddr, _isWrite)
	if bit32.band(self.reg[REG_IDX.CR0], CR0_PG) == 0 then
		return vaddr % 0x100000000
	end

	local pageSize = self.config.PAGE_SIZE or 4096
	local vpn = math.floor(vaddr / pageSize)
	local off = vaddr % pageSize
	local ppn = self._tlb[vpn]
	if ppn then
		self.stats.tlbHits = self.stats.tlbHits + 1
		return (ppn * pageSize + off) % 0x100000000
	end

	self.stats.tlbMisses = self.stats.tlbMisses + 1
	ppn = vpn
	if not self._tlb[vpn] then
		self._tlbCount = self._tlbCount + 1
	end
	if self._tlbCount > self._tlbLimit then
		self._tlb = {}
		self._tlbCount = 1
	end
	self._tlb[vpn] = ppn
	return (ppn * pageSize + off) % 0x100000000
end

function CPU:_checkBusFault(addr, _op)
	if not self.bus or type(self.bus.consumeFault) ~= "function" then
		return false
	end
	local fault = self.bus:consumeFault()
	if not fault or self._inTrap then
		return fault ~= nil
	end
	self:_raiseException("bus-fault:" .. tostring(fault.kind), addr or fault.addr, self.config.EXCEPTION.BUS_FAULT)
	return true
end

function CPU:_memRead32(addr)
	local paddr = self:_translateAddress(addr, false)
	local cline = paddr % (256 * 4)
	if self._dcache[cline] and self._dcache[cline].addr == paddr then
		self.stats.cacheHits.L1D = self.stats.cacheHits.L1D + 1
		return self._dcache[cline].data
	end
	self.stats.cacheMisses.L1D = self.stats.cacheMisses.L1D + 1
	local data = self.bus:memRead32(paddr)
	self:_checkBusFault(paddr, "read32")
	self._dcache[cline] = { addr = paddr, data = data }
	return data
end

function CPU:_memWrite32(addr, value)
	local paddr = self:_translateAddress(addr, true)
	local cline = paddr % (256 * 4)
	self._dcache[cline] = { addr = paddr, data = value % 0x100000000 }
	self.bus:memWrite32(paddr, value)
	self:_checkBusFault(paddr, "write32")
end

function CPU:_memRead8(addr)
	local paddr = self:_translateAddress(addr, false)
	local v = self.bus:memRead(paddr)
	self:_checkBusFault(paddr, "read8")
	return v
end

function CPU:_memWrite8(addr, value)
	local paddr = self:_translateAddress(addr, true)
	self.bus:memWrite(paddr, value % 256)
	self:_checkBusFault(paddr, "write8")
end

function CPU:_pollExternalInterrupt()
	if not self.bus or type(self.bus.getPendingInterruptVector) ~= "function" then
		return nil
	end
	return self.bus:getPendingInterruptVector()
end

function CPU:_enterInterrupt(vector, force, isExternal)
	if vector == nil then
		return false
	end
	if not force and not self:flag(FLAG_IF) then
		return false
	end

	local frame = {
		pc = self.reg[REG_IDX.PC],
		flags = self.reg[REG_IDX.FLAGS],
		vector = vector % 256,
		external = isExternal == true,
	}
	table.insert(self._interruptStack, frame)

	self:setFlag(FLAG_IF, false)
	self:setFlag(FLAG_HLT, false)

	local idtEntry = self._idtBase + frame.vector * 8
	self._inTrap = true
	local handlerAddr = self:_memRead32(idtEntry)
	self._inTrap = false

	if handlerAddr ~= 0 then
		self.reg[REG_IDX.PC] = handlerAddr
		self._lastInterruptVector = frame.vector
		self.stats.interrupts = self.stats.interrupts + 1
		return true
	end

	table.remove(self._interruptStack)
	self.reg[REG_IDX.PC] = frame.pc
	self.reg[REG_IDX.FLAGS] = frame.flags
	return false
end

function CPU:_serviceInterrupts(force)
	if #self._pendingSWInterrupts > 0 then
		local vec = table.remove(self._pendingSWInterrupts, 1)
		return self:_enterInterrupt(vec, true, false)
	end

	if force or self:flag(FLAG_IF) then
		local vec = self:_pollExternalInterrupt()
		if vec ~= nil then
			return self:_enterInterrupt(vec, false, true)
		end
	end
	return false
end

function CPU:_raiseException(reason, addr, vector)
	self.stats.exceptions = self.stats.exceptions + 1
	self.pipeline.EX = "EXC " .. tostring(reason)
	if addr then
		self.reg[REG_IDX.TR] = addr % 0x100000000
	end
	self:interrupt(vector or 0)
	self:_serviceInterrupts(true)
end

local function decode(word)
	local opcode = math.floor(word / (2 ^ 26)) % 64
	local rd = math.floor(word / (2 ^ 21)) % 32
	local rs1 = math.floor(word / (2 ^ 16)) % 32
	local rs2 = math.floor(word / (2 ^ 11)) % 32
	local imm11 = word % (2 ^ 11)
	local imm16 = word % (2 ^ 16)
	local imm8 = word % (2 ^ 8)
	return opcode, rd + 1, rs1 + 1, rs2 + 1, imm11, imm16, imm8
end

function CPU:step()
	local flags = self.reg[REG_IDX.FLAGS]
	if flags % (FLAG_HLT * 2) >= FLAG_HLT then
		self:_serviceInterrupts(false)
		self.stats.cycles = self.stats.cycles + 1
		return "HLT"
	end

	local pc = self.reg[REG_IDX.PC]
	self._latchIF = { pc = pc }

	self.pipeline.IF = string.format("%08X", pc)
	local word = self:fetch(pc)
	if self:_checkBusFault(pc, "fetch") then
		self.stats.cycles = self.stats.cycles + 1
		return "FAULT"
	end

	local opcode, rd, rs1, rs2, _imm11, imm16, imm8 = decode(word)
	local opname = OP_NAME[opcode] or "???"
	self._latchID = { opcode = opcode, rd = rd, rs1 = rs1, rs2 = rs2, imm16 = imm16 }
	self.pipeline.ID = opname

	local a = self:getRegIdx(rs1)
	local b = self:getRegIdx(rs2)
	self.pipeline.RF = string.format("r%d=%08X r%d=%08X", rs1 - 1, a, rs2 - 1, b)
	self.reg[REG_IDX.PC] = (pc + 4) % 0x100000000

	local branched = false
	local branchPredictedTaken = false
	local isBranchInstruction = false

	if opcode == OP.NOP then
		-- nothing
	elseif opcode == OP.MOV then
		self:setRegIdx(rd, a)
	elseif opcode == OP.MOVI then
		self:setRegIdx(rd, signExt16(imm16))
	elseif opcode == OP.LMOVI then
		local hi = self.bus:memRead32(self.reg[REG_IDX.PC])
		self.reg[REG_IDX.PC] = self.reg[REG_IDX.PC] + 4
		self:setRegIdx(rd, bit32.bor(bit32.lshift(bit32.band(hi, 0xFFFF), 16), bit32.band(imm16, 0xFFFF)))
	elseif
		opcode == OP.ADD
		or opcode == OP.SUB
		or opcode == OP.MUL
		or opcode == OP.DIV
		or opcode == OP.AND
		or opcode == OP.OR
		or opcode == OP.XOR
		or opcode == OP.SHL
		or opcode == OP.SHR
		or opcode == OP.SAR
		or opcode == OP.MOD
	then
		if (opcode == OP.DIV or opcode == OP.MOD) and b == 0 then
			self:_raiseException("divide-by-zero", pc, self.config.EXCEPTION.DIVIDE_BY_ZERO)
			self.pipeline.EX = "EXC divide-by-zero"
		else
			local r, cf, zf, sf, of = self:alu(opname, a, b)
			self:setRegIdx(rd, r)
			self:setFlag(FLAG_CF, cf)
			self:setFlag(FLAG_ZF, zf)
			self:setFlag(FLAG_SF, sf)
			self:setFlag(FLAG_OF, of)
			self.pipeline.EX = string.format("%s %08X %08X = %08X", opname, a, b, r)
		end
	elseif opcode == OP.ADDI or opcode == OP.SUBI then
		local r, cf, zf, sf, of = self:alu(opname, a, signExt16(imm16))
		self:setRegIdx(rd, r)
		self:setFlag(FLAG_CF, cf)
		self:setFlag(FLAG_ZF, zf)
		self:setFlag(FLAG_SF, sf)
		self:setFlag(FLAG_OF, of)
	elseif opcode == OP.NOT or opcode == OP.NEG or opcode == OP.INC or opcode == OP.DEC then
		local r, _cf, zf, sf = self:alu(opname, a, 0)
		self:setRegIdx(rd, r)
		self:setFlag(FLAG_ZF, zf)
		self:setFlag(FLAG_SF, sf)
	elseif opcode == OP.CMP or opcode == OP.CMPI then
		local bval = (opcode == OP.CMPI) and signExt16(imm16) or b
		local _r, cf, zf, sf, of = self:alu("SUB", a, bval)
		self:setFlag(FLAG_CF, cf)
		self:setFlag(FLAG_ZF, zf)
		self:setFlag(FLAG_SF, sf)
		self:setFlag(FLAG_OF, of)
	elseif opcode == OP.JMP then
		isBranchInstruction = true
		branchPredictedTaken = self:_predictBranch(pc)
		self.reg[REG_IDX.PC] = a
		branched = true
	elseif opcode == OP.JMPI then
		isBranchInstruction = true
		branchPredictedTaken = self:_predictBranch(pc)
		self.reg[REG_IDX.PC] = (pc + 4 + signExt16(imm16)) % 0x100000000
		branched = true
	elseif opcode == OP.JEQ then
		isBranchInstruction = true
		branchPredictedTaken = self:_predictBranch(pc)
		if self:flag(FLAG_ZF) then
			self.reg[REG_IDX.PC] = (pc + 4 + signExt16(imm16)) % 0x100000000
			branched = true
		end
	elseif opcode == OP.JNE then
		isBranchInstruction = true
		branchPredictedTaken = self:_predictBranch(pc)
		if not self:flag(FLAG_ZF) then
			self.reg[REG_IDX.PC] = (pc + 4 + signExt16(imm16)) % 0x100000000
			branched = true
		end
	elseif opcode == OP.JLT then
		isBranchInstruction = true
		branchPredictedTaken = self:_predictBranch(pc)
		if self:flag(FLAG_SF) ~= self:flag(FLAG_OF) then
			self.reg[REG_IDX.PC] = (pc + 4 + signExt16(imm16)) % 0x100000000
			branched = true
		end
	elseif opcode == OP.JGT then
		isBranchInstruction = true
		branchPredictedTaken = self:_predictBranch(pc)
		if not self:flag(FLAG_ZF) and (self:flag(FLAG_SF) == self:flag(FLAG_OF)) then
			self.reg[REG_IDX.PC] = (pc + 4 + signExt16(imm16)) % 0x100000000
			branched = true
		end
	elseif opcode == OP.JLE then
		isBranchInstruction = true
		branchPredictedTaken = self:_predictBranch(pc)
		if self:flag(FLAG_ZF) or (self:flag(FLAG_SF) ~= self:flag(FLAG_OF)) then
			self.reg[REG_IDX.PC] = (pc + 4 + signExt16(imm16)) % 0x100000000
			branched = true
		end
	elseif opcode == OP.JGE then
		isBranchInstruction = true
		branchPredictedTaken = self:_predictBranch(pc)
		if self:flag(FLAG_SF) == self:flag(FLAG_OF) then
			self.reg[REG_IDX.PC] = (pc + 4 + signExt16(imm16)) % 0x100000000
			branched = true
		end
	elseif opcode == OP.CALL then
		isBranchInstruction = true
		branchPredictedTaken = self:_predictBranch(pc)
		self.reg[REG_IDX.LR] = self.reg[REG_IDX.PC]
		self.reg[REG_IDX.PC] = a
		branched = true
	elseif opcode == OP.RET then
		isBranchInstruction = true
		branchPredictedTaken = self:_predictBranch(pc)
		self.reg[REG_IDX.PC] = self.reg[REG_IDX.LR]
		branched = true
	elseif opcode == OP.LW then
		local addr = (a + signExt16(imm16)) % 0x100000000
		self.stats.memReads = self.stats.memReads + 1
		self:setRegIdx(rd, self:_memRead32(addr))
		self.pipeline.MA = string.format("LOAD [%08X]", addr)
	elseif opcode == OP.SW then
		local addr = (a + signExt16(imm16)) % 0x100000000
		self.stats.memWrites = self.stats.memWrites + 1
		self:_memWrite32(addr, b)
		self.pipeline.MA = string.format("STORE [%08X]=%08X", addr, b)
	elseif opcode == OP.LB then
		local addr = (a + signExt16(imm16)) % 0x100000000
		self.stats.memReads = self.stats.memReads + 1
		self:setRegIdx(rd, self:_memRead8(addr))
	elseif opcode == OP.SB then
		local addr = (a + signExt16(imm16)) % 0x100000000
		self.stats.memWrites = self.stats.memWrites + 1
		self:_memWrite8(addr, b % 256)
	elseif opcode == OP.PUSH then
		self.reg[REG_IDX.SP] = (self.reg[REG_IDX.SP] - 4) % 0x100000000
		self:_memWrite32(self.reg[REG_IDX.SP], a)
	elseif opcode == OP.POP then
		self:setRegIdx(rd, self:_memRead32(self.reg[REG_IDX.SP]))
		self.reg[REG_IDX.SP] = (self.reg[REG_IDX.SP] + 4) % 0x100000000
	elseif opcode == OP.INT then
		self:interrupt(imm8)
		self:_serviceInterrupts(true)
	elseif opcode == OP.IRET then
		local frame = table.remove(self._interruptStack)
		if frame then
			self.reg[REG_IDX.PC] = frame.pc
			self.reg[REG_IDX.FLAGS] = frame.flags
			if frame.external and self.bus and type(self.bus.endOfInterrupt) == "function" then
				self.bus:endOfInterrupt(frame.vector)
			end
		end
	elseif opcode == OP.IN then
		self:setRegIdx(rd, self.bus:portRead(imm16))
	elseif opcode == OP.OUT then
		self.bus:portWrite(imm16, a)
	elseif opcode == OP.HLT then
		self:setFlag(FLAG_HLT, true)
	else
		self:_raiseException("illegal-opcode", pc, self.config.EXCEPTION.ILLEGAL_OPCODE)
	end

	if isBranchInstruction then
		self:_trainBranch(pc, branched)
		if branchPredictedTaken ~= branched then
			self.stats.branchMispredicts = self.stats.branchMispredicts + 1
		end
	end

	if branched then
		self.stats.branches = self.stats.branches + 1
	end

	self:_serviceInterrupts(false)

	self._latchEX = { opname = opname, branched = branched }
	self._latchMA = { rd = rd }
	self.pipeline.WB = string.format("rd%d<-", rd)
	self.stats.cycles = self.stats.cycles + 1
	self.stats.instructions = self.stats.instructions + 1
	return opname
end

function CPU:interrupt(vector)
	table.insert(self._pendingSWInterrupts, (tonumber(vector) or 0) % 256)
end

function CPU:_handleInterrupt()
	return self:_serviceInterrupts(true)
end

function CPU:setIDTBase(addr)
	self._idtBase = addr
	self.reg[REG_IDX.IDTR] = addr
end

function CPU:tick(n)
	n = n or 1
	local ops = {}
	for i = 1, n do
		local op = self:step()
		table.insert(ops, op)
	end
	return ops
end

function CPU:dumpRegisters()
	local out = {}
	for i, name in ipairs(REG_NAMES) do
		table.insert(out, string.format("%-6s= %08X", name, self.reg[i]))
	end
	return out
end

function CPU:getRegSnapshot()
	local snap = {}
	for i, name in ipairs(REG_NAMES) do
		snap[name] = self.reg[i]
	end
	return snap
end

function CPU:getPipelineState()
	return {
		IF = self.pipeline.IF,
		ID = self.pipeline.ID,
		RF = self.pipeline.RF,
		EX = self.pipeline.EX,
		MA = self.pipeline.MA,
		WB = self.pipeline.WB,
	}
end

function CPU:getStats()
	return self.stats
end

function CPU:_nextGuestSessionId()
	local id = self._guestSessionSerial
	self._guestSessionSerial = id + 1
	return id
end

function CPU:_traceGuestSession(session, phase, detail)
	local vmConfig = self.config.VM or {}
	if vmConfig.TRACE_GUEST_EXECUTION ~= true then
		return
	end
	warn(
		string.format(
			"[CPU guest] id=%d phase=%s backend=%s detail=%s",
			session.id or -1,
			tostring(phase),
			tostring(session.backendName),
			tostring(detail or "")
		)
	)
end

function CPU:registerGuestExecutionBackend(name, backend)
	if type(name) ~= "string" or name == "" or type(backend) ~= "table" then
		return false
	end

	local executeFn = backend.execute
	if type(executeFn) ~= "function" then
		return false
	end

	self._guestBackends[name] = {
		kind = backend.kind or "custom",
		runtime = backend.runtime,
		execute = executeFn,
	}
	if not self._defaultGuestBackend then
		self._defaultGuestBackend = name
	end
	return true
end

function CPU:getGuestBackend(name)
	return self._guestBackends[name or self._defaultGuestBackend]
end

function CPU:ensureManagedGuestBackend(runtimeName, backendName)
	local vmConfig = self.config.VM or {}
	local selectedRuntime = runtimeName or vmConfig.MANAGED_RUNTIME or self._defaultManagedRuntime or "luauvm"
	local selectedBackend = backendName or vmConfig.CPU_BACKEND or (selectedRuntime .. "-cpu")

	if self._guestBackends[selectedBackend] then
		return selectedBackend
	end

	self:registerGuestExecutionBackend(selectedBackend, {
		kind = "managed-runtime-adapter",
		runtime = selectedRuntime,
		execute = function(cpu, session)
			local runtimeId = session.runtimeName or selectedRuntime
			local runtime = cpu:getManagedRuntime(runtimeId)
			if not runtime or type(runtime.loadBytecode) ~= "function" then
				return nil, "managed-runtime-unavailable:" .. tostring(runtimeId)
			end
			return runtime.loadBytecode(session.bytecode, session.env, session.context)
		end,
	})

	return selectedBackend
end

function CPU:attachManagedRuntime(name, runtime)
	if type(name) ~= "string" or name == "" or type(runtime) ~= "table" then
		return false
	end
	self._managedRuntimes[name] = runtime
	if not self._defaultManagedRuntime then
		self._defaultManagedRuntime = name
	end
	local vmConfig = self.config.VM or {}
	local preferredRuntime = vmConfig.MANAGED_RUNTIME or self._defaultManagedRuntime or name
	local preferredBackend = nil
	if name == preferredRuntime then
		preferredBackend = vmConfig.CPU_BACKEND
	end
	self:ensureManagedGuestBackend(name, preferredBackend)
	return true
end

function CPU:getManagedRuntime(name)
	return self._managedRuntimes[name or self._defaultManagedRuntime]
end

function CPU:createExecutionContext(opts)
	opts = opts or {}
	local execContext = {
		kind = "nova.exec-context",
		abi = "nova.exec.v1",
		pid = opts.pid or 0,
		argv = opts.argv or {},
		env = opts.env or {},
		executable = opts.executable or {},
		backend = opts.backend or "auto",
		cpuBackend = opts.cpuBackend,
	}
	local cpu = self

	function execContext:resolveBackend()
		return cpu:getGuestExecutionBackend(self)
	end

	function execContext:executeBytecode(bytecode, envOverride, overrides)
		local dispatchContext = {
			kind = self.kind,
			abi = self.abi,
			pid = self.pid,
			argv = self.argv,
			env = self.env,
			executable = self.executable,
			backend = self.backend,
			cpuBackend = self.cpuBackend,
		}
		if type(overrides) == "table" then
			for key, value in pairs(overrides) do
				dispatchContext[key] = value
			end
		end
		return cpu:executeGuestBytecode(bytecode, envOverride or self.env, dispatchContext)
	end

	return execContext
end

function CPU:createGuestSession(bytecode, env, context, backend)
	local session = {
		id = self:_nextGuestSessionId(),
		bytecode = bytecode,
		env = env,
		context = context or {},
		backendKind = backend and backend.kind or "unknown",
		backendName = backend and backend.name or "unknown",
		backend = backend and backend.backend or nil,
		runtimeName = backend and backend.runtimeName or nil,
		state = "created",
		createdCycle = self.stats.cycles,
		startedCycle = nil,
		finishedCycle = nil,
		result = nil,
		error = nil,
	}
	self._guestSessions[session.id] = session
	return session
end

function CPU:enqueueGuestSession(session)
	if type(session) ~= "table" or type(session.id) ~= "number" then
		return false
	end
	session.state = "queued"
	table.insert(self._guestSessionQueue, session)
	self:_traceGuestSession(session, "queued")
	return true
end

function CPU:runNextGuestSession()
	if #self._guestSessionQueue == 0 then
		return nil
	end

	local session = table.remove(self._guestSessionQueue, 1)
	session.state = "running"
	session.startedCycle = self.stats.cycles
	self:_traceGuestSession(session, "running")

	local backend = session.backend
	if not backend and session.runtimeName then
		self:ensureManagedGuestBackend(session.runtimeName, session.backendName)
		backend = self:getGuestBackend(session.backendName)
		session.backend = backend
	end

	if not backend or type(backend.execute) ~= "function" then
		session.state = "faulted"
		session.error = "guest-backend-unavailable:" .. tostring(session.backendName)
		self.stats.guestSessionFaults = self.stats.guestSessionFaults + 1
		self:_traceGuestSession(session, "faulted", session.error)
	else
		local ok, fn, runtimeErr = pcall(backend.execute, self, session)
		if not ok then
			session.state = "faulted"
			session.error = "guest-backend-crash:" .. tostring(fn)
			self.stats.guestSessionFaults = self.stats.guestSessionFaults + 1
			self:_traceGuestSession(session, "faulted", session.error)
		elseif type(fn) ~= "function" then
			session.state = "faulted"
			session.error = runtimeErr or "guest-entrypoint-missing"
			self.stats.guestSessionFaults = self.stats.guestSessionFaults + 1
			self:_traceGuestSession(session, "faulted", session.error)
		else
			session.state = "ready"
			session.result = fn
			self:_traceGuestSession(session, "ready")
		end
	end

	session.finishedCycle = self.stats.cycles
	self.stats.guestSessions = self.stats.guestSessions + 1
	self._guestLastSessionId = session.id
	return session
end

function CPU:drainGuestSessions(maxSessions)
	local processed = 0
	local last = nil
	while #self._guestSessionQueue > 0 and (maxSessions == nil or processed < maxSessions) do
		last = self:runNextGuestSession()
		processed = processed + 1
	end
	return processed, last
end

function CPU:getGuestSession(sessionId)
	return self._guestSessions[sessionId]
end

function CPU:getGuestExecutionState()
	return {
		queueDepth = #self._guestSessionQueue,
		sessionCount = self.stats.guestSessions,
		faultCount = self.stats.guestSessionFaults,
		lastSessionId = self._guestLastSessionId,
		defaultBackend = self._defaultGuestBackend,
	}
end

function CPU:getGuestExecutionBackend(context)
	context = context or {}
	local vmConfig = self.config.VM or {}
	local exec = context.executable or {}
	local requested = context.backend or "auto"
	local defaultBackend = vmConfig.DEFAULT_BACKEND or "cpu-managed"
	local runtimeName = exec.runtime
		or context.runtime
		or vmConfig.MANAGED_RUNTIME
		or self._defaultManagedRuntime
		or "luauvm"

	if requested == "native" or exec.kind == "native" or exec.format == "native" then
		return { kind = "native", name = "nova32" }
	end

	if requested == "managed-vm" then
		return {
			kind = "managed-vm",
			name = runtimeName,
			runtimeName = runtimeName,
			runtime = self:getManagedRuntime(runtimeName),
		}
	end

	local cpuBackedRequested = requested == "cpu-managed" or requested == "cpu-guest"
	local cpuBackedByDefault = requested == "auto" and defaultBackend ~= "managed-vm"
	local cpuBackedByExecutable = exec.kind == "vm" or exec.format == "luau"
	if cpuBackedRequested or cpuBackedByDefault or cpuBackedByExecutable then
		local backendName = exec.cpuBackend or context.cpuBackend or vmConfig.CPU_BACKEND or (runtimeName .. "-cpu")
		return {
			kind = "cpu-guest",
			name = backendName,
			runtimeName = runtimeName,
			backend = self:getGuestBackend(backendName),
		}
	end

	if requested == "auto" and defaultBackend == "managed-vm" then
		return {
			kind = "managed-vm",
			name = runtimeName,
			runtimeName = runtimeName,
			runtime = self:getManagedRuntime(runtimeName),
		}
	end

	return { kind = "unknown", name = tostring(requested) }
end

function CPU:_executeManagedRuntimeDirect(runtimeName, bytecode, env, context)
	local runtime = self:getManagedRuntime(runtimeName)
	if not runtime or type(runtime.loadBytecode) ~= "function" then
		return nil, "managed-runtime-unavailable:" .. tostring(runtimeName)
	end
	return runtime.loadBytecode(bytecode, env, context)
end

function CPU:executeGuestExecutable(executable, env, context)
	if type(executable) ~= "table" then
		return nil, "invalid-executable-spec"
	end

	local exec = table.clone(executable)
	context = context or {}
	context.executable = context.executable or exec

	if exec.kind == "native" or exec.format == "native" then
		return nil, "native-guest-loader-not-implemented"
	end

	local runtimeName = exec.runtime or context.runtime or (self.config.VM or {}).MANAGED_RUNTIME or "luauvm"
	local bytecode = exec.bytecode

	if not bytecode then
		local runtime = self:getManagedRuntime(runtimeName)
		if not runtime or type(runtime.compileSource) ~= "function" then
			return nil, "managed-runtime-compiler-unavailable:" .. tostring(runtimeName)
		end
		if type(exec.content) ~= "string" then
			return nil, "guest-executable-content-missing"
		end
		bytecode = runtime.compileSource(exec.content)
		exec.bytecode = bytecode
		context.executable = exec
	end

	return self:executeGuestBytecode(bytecode, env, context)
end

function CPU:executeGuestBytecode(bytecode, env, context)
	local backend = self:getGuestExecutionBackend(context)
	if backend.kind == "native" then
		return nil, "backend-requires-native-loader"
	end

	if backend.kind == "cpu-guest" then
		local session = self:createGuestSession(bytecode, env, context, backend)
		self:enqueueGuestSession(session)
		self:drainGuestSessions(1)
		if session.state == "ready" and type(session.result) == "function" then
			return session.result, nil, session
		end

		local vmConfig = self.config.VM or {}
		local strictCPU = vmConfig.STRICT_CPU_BACKEND == true
		local allowFallback = vmConfig.ALLOW_HOST_FALLBACK ~= false
		if strictCPU or not allowFallback then
			return nil, session.error or "cpu-guest-execution-failed", session
		end

		local fn, err = self:_executeManagedRuntimeDirect(backend.runtimeName, bytecode, env, context)
		if fn then
			session.fallback = "managed-runtime"
			return fn, nil, session
		end
		return nil, err or session.error or "guest-execution-failed", session
	end

	if backend.kind ~= "managed-vm" then
		return nil, "backend-unavailable:" .. tostring(backend.kind)
	end

	local fn, err = self:_executeManagedRuntimeDirect(backend.runtimeName, bytecode, env, context)
	if not fn then
		return nil, err
	end
	return fn, nil
end

CPU.OP = OP
CPU.OP_NAME = OP_NAME
CPU.REG_IDX = REG_IDX
CPU.REG_NAMES = REG_NAMES

return CPU
