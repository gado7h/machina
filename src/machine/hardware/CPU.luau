-- CPU module

local CPU = {}
CPU.__index = CPU

local OP = {
	NOP = 0,
	MOV = 1, -- rd = rs1
	MOVI = 2, -- rd = imm16
	ADD = 3, -- rd = rs1 + rs2
	ADDI = 4, -- rd = rs1 + imm16
	SUB = 5, -- rd = rs1 - rs2
	SUBI = 6,
	MUL = 7,
	DIV = 8,
	AND = 9,
	OR = 10,
	XOR = 11,
	NOT = 12,
	SHL = 13, -- shift left
	SHR = 14, -- shift right logical
	SAR = 15, -- shift right arithmetic
	CMP = 16, -- set flags from rs1 - rs2
	CMPI = 17,
	JMP = 18, -- PC = rs1
	JMPI = 19, -- PC = PC + imm16
	JEQ = 20, -- jump if ZF
	JNE = 21,
	JLT = 22,
	JGT = 23,
	JLE = 24,
	JGE = 25,
	CALL = 26, -- LR=PC+4; PC=rs1
	RET = 27, -- PC=LR
	LW = 28, -- rd = mem[rs1 + imm16]
	SW = 29, -- mem[rs1 + imm16] = rs2
	LB = 30, -- load byte
	SB = 31, -- store byte
	PUSH = 32, -- mem[SP]=rs1; SP-=4
	POP = 33, -- rd=mem[SP]; SP+=4
	INT = 34, -- software interrupt (imm8 = vector)
	IRET = 35, -- return from interrupt
	IN = 36, -- rd = port[imm16]
	OUT = 37, -- port[imm16] = rs1
	HLT = 38,
	LMOVI = 39, -- load 32-bit immediate (2-word instruction)
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

-- Control register bits (CR0)
local CR0_PG = 0x80000000 -- paging enabled

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

	-- Register file (1-indexed matching REG_NAMES)
	self.reg = {}
	for i = 1, #REG_NAMES do
		self.reg[i] = 0
	end

	-- Named convenience aliases (set in :reset)
	self._R = self.reg -- direct array

	-- Pipeline state (for visualisation)
	self.pipeline = { IF = "NOP", ID = "NOP", RF = "NOP", EX = "NOP", MA = "NOP", WB = "NOP" }
	self.pipelineActive = {} -- which stages are lit this tick

	-- Interrupt Descriptor Table base (virtual)
	self._idtBase = 0
	self._interruptPending = nil -- vector number or nil
	self._savedPC = 0
	self._savedFlags = 0

	-- Statistics
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
	}

	-- Simple L1 instruction cache simulation (direct-mapped, 256 lines)
	self._icache = {} -- addr → instruction word
	-- Simple L1 data cache simulation (write-through, 256 lines)
	self._dcache = {} -- addr → {addr, data}

	-- Tiny fully-associative TLB (virtual page -> physical page)
	self._tlb = {}
	self._tlbLimit = 64
	self._tlbCount = 0

	-- 2-bit branch predictor table (1024 entries)
	self._branchPredictor = {}
	for i = 0, 1023 do
		self._branchPredictor[i] = 2 -- weakly taken
	end

	-- Execution staging (realistic pipeline latches used for debug/inspection)
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
	-- PC starts at ROM base (firmware entry point)
	self.reg[REG_IDX.PC] = self.config.ROM_BASE
	self.reg[REG_IDX.SP] = self.config.RAM_BASE + self.config.RAM_SIZE - 4
	self.reg[REG_IDX.FLAGS] = FLAG_IF -- interrupts enabled by default
	self._icache = {}
	self._dcache = {}
	self._tlb = {}
	self._tlbCount = 0
	self._interruptPending = nil
	self.stats.cycles = 0
	self.stats.instructions = 0
	self.stats.branchMispredicts = 0
	self.stats.tlbHits = 0
	self.stats.tlbMisses = 0
	self.stats.exceptions = 0
	for i = 0, 1023 do
		self._branchPredictor[i] = 2
	end
	self._latchIF = nil
	self._latchID = nil
	self._latchEX = nil
	self._latchMA = nil
end

--  Register helpers

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
	end -- R0 is hardwired zero
	self.reg[idx] = value % 0x100000000 -- keep 32-bit
end

function CPU:getRegIdx(i)
	return self.reg[i] or 0
end
function CPU:setRegIdx(i, v)
	if i == 1 then
		return
	end -- R0 hardwired
	self.reg[i] = v % 0x100000000
end

--  FLAGS helpers

function CPU:flag(bit)
	return (self.reg[REG_IDX.FLAGS] % (bit * 2)) >= bit
end
function CPU:setFlag(bit, v)
	if v then
		self.reg[REG_IDX.FLAGS] = self.reg[REG_IDX.FLAGS] + (self:flag(bit) and 0 or bit)
	else
		if self:flag(bit) then
			self.reg[REG_IDX.FLAGS] = self.reg[REG_IDX.FLAGS] - bit
		end
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

--  ALU

function CPU:alu(op, a, b)
	-- returns {result, CF, ZF, SF, OF}
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

--  Instruction Fetch  (with I-cache sim)

function CPU:fetch(addr)
	-- L1 I-cache: 256-entry direct mapped, 4-byte lines
	local cline = addr % (256 * 4)
	if self._icache[cline] and self._icache[cline].addr == addr then
		self.stats.cacheHits.L1I = self.stats.cacheHits.L1I + 1
		return self._icache[cline].data
	end
	-- cache miss → bus fetch
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

function CPU:_translateAddress(vaddr, isWrite)
	-- When paging is disabled, virtual == physical
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
	-- Lightweight identity walk fallback keeps runtime compatible while allowing realistic paging path.
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

function CPU:_memRead32(addr)
	local paddr = self:_translateAddress(addr, false)
	local cline = paddr % (256 * 4)
	if self._dcache[cline] and self._dcache[cline].addr == paddr then
		self.stats.cacheHits.L1D = self.stats.cacheHits.L1D + 1
		return self._dcache[cline].data
	end
	self.stats.cacheMisses.L1D = self.stats.cacheMisses.L1D + 1
	local data = self.bus:memRead32(paddr)
	self._dcache[cline] = { addr = paddr, data = data }
	return data
end

function CPU:_memWrite32(addr, value)
	local paddr = self:_translateAddress(addr, true)
	local cline = paddr % (256 * 4)
	self._dcache[cline] = { addr = paddr, data = value % 0x100000000 }
	self.bus:memWrite32(paddr, value)
end

function CPU:_memRead8(addr)
	local paddr = self:_translateAddress(addr, false)
	return self.bus:memRead(paddr)
end

function CPU:_memWrite8(addr, value)
	local paddr = self:_translateAddress(addr, true)
	self.bus:memWrite(paddr, value % 256)
end

function CPU:_raiseException(reason, addr)
	self.stats.exceptions = self.stats.exceptions + 1
	self.pipeline.EX = "EXC " .. tostring(reason)
	-- Keep compatibility: trap to interrupt vector 0 unless IF disabled.
	if self:flag(FLAG_IF) then
		self:interrupt(0)
	end
	if addr then
		self.reg[REG_IDX.TR] = addr % 0x100000000
	end
end

--  Instruction Decode

local function decode(word)
	local opcode = math.floor(word / (2 ^ 26)) % 64
	local rd = math.floor(word / (2 ^ 21)) % 32
	local rs1 = math.floor(word / (2 ^ 16)) % 32
	local rs2 = math.floor(word / (2 ^ 11)) % 32
	local imm11 = word % (2 ^ 11)
	local imm16 = word % (2 ^ 16)
	local imm8 = word % (2 ^ 8)
	return opcode, rd + 1, rs1 + 1, rs2 + 1, imm11, imm16, imm8 -- +1 for Lua 1-based reg array
end

--  Execute one instruction

function CPU:step()
	local flags = self.reg[REG_IDX.FLAGS]
	if flags % (FLAG_HLT * 2) >= FLAG_HLT then
		-- CPU halted; only an interrupt can wake it
		if self._interruptPending then
			self:_handleInterrupt()
		end
		self.stats.cycles = self.stats.cycles + 1
		return "HLT"
	end

	local pc = self.reg[REG_IDX.PC]
	self._latchIF = { pc = pc }

	self.pipeline.IF = string.format("%08X", pc)
	local word = self:fetch(pc)

	local opcode, rd, rs1, rs2, imm11, imm16, imm8 = decode(word)
	local opname = OP_NAME[opcode] or "???"
	self._latchID = { opcode = opcode, rd = rd, rs1 = rs1, rs2 = rs2, imm16 = imm16 }
	self.pipeline.ID = opname

	local a = self:getRegIdx(rs1)
	local b = self:getRegIdx(rs2)
	self.pipeline.RF = string.format("r%d=%08X r%d=%08X", rs1 - 1, a, rs2 - 1, b)

	-- advance PC (before EX so relative jumps work from current PC)
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
		-- next word is upper 16 bits; lower 16 in imm16
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
		local r, cf, zf, sf, of = self:alu(opname, a, b)
		self:setRegIdx(rd, r)
		self:setFlag(FLAG_CF, cf)
		self:setFlag(FLAG_ZF, zf)
		self:setFlag(FLAG_SF, sf)
		self:setFlag(FLAG_OF, of)
		self.pipeline.EX = string.format("%s %08X %08X = %08X", opname, a, b, r)
	elseif opcode == OP.ADDI or opcode == OP.SUBI then
		local r, cf, zf, sf, of = self:alu(opname, a, signExt16(imm16))
		self:setRegIdx(rd, r)
		self:setFlag(FLAG_CF, cf)
		self:setFlag(FLAG_ZF, zf)
		self:setFlag(FLAG_SF, sf)
		self:setFlag(FLAG_OF, of)
	elseif opcode == OP.NOT or opcode == OP.NEG or opcode == OP.INC or opcode == OP.DEC then
		local r, cf, zf, sf, of = self:alu(opname, a, 0)
		self:setRegIdx(rd, r)
		self:setFlag(FLAG_ZF, zf)
		self:setFlag(FLAG_SF, sf)
	elseif opcode == OP.CMP or opcode == OP.CMPI then
		local bval = (opcode == OP.CMPI) and signExt16(imm16) or b
		local r, cf, zf, sf, of = self:alu("SUB", a, bval)
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
	elseif opcode == OP.IRET then
		-- restore saved context
		self.reg[REG_IDX.PC] = self._savedPC
		self.reg[REG_IDX.FLAGS] = self._savedFlags
	elseif opcode == OP.IN then
		self:setRegIdx(rd, self.bus:portRead(imm16))
	elseif opcode == OP.OUT then
		self.bus:portWrite(imm16, a)
	elseif opcode == OP.HLT then
		self:setFlag(FLAG_HLT, true)
	else
		self:_raiseException("illegal-opcode", pc)
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

	-- Check for pending hardware interrupt
	if self._interruptPending and self:flag(FLAG_IF) then
		self:_handleInterrupt()
	end

	self._latchEX = { opname = opname, branched = branched }
	self._latchMA = { rd = rd }
	self.pipeline.WB = string.format("rd%d←", rd)
	self.stats.cycles = self.stats.cycles + 1
	self.stats.instructions = self.stats.instructions + 1
	return opname
end

--  Interrupt handling

--- Called by bus/devices to raise an external interrupt.
function CPU:interrupt(vector)
	self._interruptPending = vector
end

function CPU:_handleInterrupt()
	if not self:flag(FLAG_IF) then
		return
	end -- interrupts masked
	local vec = self._interruptPending
	self._interruptPending = nil
	self.stats.interrupts = self.stats.interrupts + 1

	-- save context
	self._savedPC = self.reg[REG_IDX.PC]
	self._savedFlags = self.reg[REG_IDX.FLAGS]

	-- disable interrupts (re-entrant disabled)
	self:setFlag(FLAG_IF, false)
	-- clear halt
	self:setFlag(FLAG_HLT, false)

	-- jump to IDT handler (read handler address from IDT table in memory)
	local idtEntry = self._idtBase + vec * 8
	local handlerAddr = self:_memRead32(idtEntry)
	if handlerAddr ~= 0 then
		self.reg[REG_IDX.PC] = handlerAddr
	else
		-- no handler — restore and continue
		self.reg[REG_IDX.PC] = self._savedPC
		self.reg[REG_IDX.FLAGS] = self._savedFlags
	end
end

--- Software way to install an interrupt handler (kernel uses this).
function CPU:setIDTBase(addr)
	self._idtBase = addr
	self.reg[REG_IDX.IDTR] = addr
end

--  Run N ticks (called by Motherboard each heartbeat)

function CPU:tick(n)
	n = n or 1
	local ops = {}
	for i = 1, n do
		local op = self:step()
		table.insert(ops, op)
	end
	return ops
end

--  Debug / inspection

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

-- Export opcode table for assembler use
CPU.OP = OP
CPU.OP_NAME = OP_NAME
CPU.REG_IDX = REG_IDX
CPU.REG_NAMES = REG_NAMES

return CPU
