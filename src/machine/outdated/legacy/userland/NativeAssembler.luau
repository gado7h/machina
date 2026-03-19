-- Assembles a small nova32 guest source format into native executable images.

local CPU = require(script.Parent.Parent.hardware.CPU)
local NativeExecutable = require(script.Parent.NativeExecutable)
local NativeSyscalls = require(script.Parent.Parent.software.NativeSyscalls)

local NativeAssembler = {}

local OP = CPU.OP

local function trim(value)
	return (tostring(value or ""):match("^%s*(.-)%s*$"))
end

local function splitLines(source)
	local lines = {}
	for line in (source .. "\n"):gmatch("([^\n]*)\n") do
		lines[#lines + 1] = line
	end
	return lines
end

local function stripComment(line)
	local value = line:gsub("%s*;.*$", "")
	value = value:gsub("%s*//.*$", "")
	value = value:gsub("%s*%-%-.*$", "")
	return trim(value)
end

local function splitArgs(raw)
	local args = {}
	for part in tostring(raw or ""):gmatch("([^,]+)") do
		args[#args + 1] = trim(part)
	end
	return args
end

local function parseRegister(token)
	local regNum = tostring(token or ""):upper():match("^R(%d+)$")
	if not regNum then
		return nil
	end
	local value = tonumber(regNum)
	if not value or value < 0 or value > 15 then
		return nil
	end
	return value
end

local function decodeEscapes(text)
	local sentinel = string.char(1)
	return tostring(text or "")
		:gsub("\\\\", sentinel)
		:gsub("\\n", "\n")
		:gsub("\\t", "\t")
		:gsub('\\"', '"')
		:gsub("\\0", "\0")
		:gsub(sentinel, "\\")
end

local function parseNumber(token, labels)
	local value = trim(token)
	if value == "" then
		return nil
	end
	if labels and labels[value] ~= nil then
		return labels[value]
	end
	if value:match("^[-+]?0x[%da-fA-F]+$") then
		return tonumber(value)
	end
	if value:match("^'.'$") then
		return string.byte(value:sub(2, 2))
	end
	if value:match('^".*"$') then
		local inner = decodeEscapes(value:sub(2, -2))
		if #inner == 1 then
			return string.byte(inner, 1)
		end
	end
	return tonumber(value)
end

local function encodeWord(opcode, rd, rs1, rs2, imm16)
	return bit32.bor(
		bit32.lshift((tonumber(opcode) or 0) % 64, 26),
		bit32.lshift((tonumber(rd) or 0) % 32, 21),
		bit32.lshift((tonumber(rs1) or 0) % 32, 16),
		bit32.lshift((tonumber(rs2) or 0) % 32, 11),
		(tonumber(imm16) or 0) % 0x10000
	)
end

local function registerOrError(token, lineNumber)
	local reg = parseRegister(token)
	if reg == nil then
		error(string.format("line %d: expected register, got '%s'", lineNumber, tostring(token)))
	end
	return reg
end

local function numberOrError(token, labels, lineNumber)
	local value = parseNumber(token, labels)
	if value == nil then
		error(string.format("line %d: expected immediate/label, got '%s'", lineNumber, tostring(token)))
	end
	return value
end

local function encodeInstruction(parsed, labels, config)
	local opName = parsed.op
	local args = parsed.args
	local lineNumber = parsed.lineNumber
	local pc = parsed.offset * 4

	if opName == "NOP" then
		return encodeWord(OP.NOP, 0, 0, 0, 0)
	end
	if opName == "HLT" then
		return encodeWord(OP.HLT, 0, 0, 0, 0)
	end
	if opName == "MOV" then
		return encodeWord(
			OP.MOV,
			registerOrError(args[1], lineNumber),
			registerOrError(args[2], lineNumber),
			0,
			0
		)
	end
	if opName == "MOVI" then
		return encodeWord(
			OP.MOVI,
			registerOrError(args[1], lineNumber),
			0,
			0,
			numberOrError(args[2], labels, lineNumber)
		)
	end
	if opName == "LMOVI" then
		return {
			encodeWord(
				OP.LMOVI,
				registerOrError(args[1], lineNumber),
				0,
				0,
				numberOrError(args[2], labels, lineNumber) % 0x10000
			),
			math.floor(numberOrError(args[2], labels, lineNumber) / 0x10000) % 0x10000,
		}
	end
	if opName == "ADD" or opName == "SUB" or opName == "MUL" or opName == "DIV" or opName == "MOD" then
		return encodeWord(
			OP[opName],
			registerOrError(args[1], lineNumber),
			registerOrError(args[2], lineNumber),
			registerOrError(args[3], lineNumber),
			0
		)
	end
	if opName == "ADDI" or opName == "SUBI" then
		return encodeWord(
			OP[opName],
			registerOrError(args[1], lineNumber),
			registerOrError(args[2], lineNumber),
			0,
			numberOrError(args[3], labels, lineNumber)
		)
	end
	if opName == "CMP" then
		return encodeWord(
			OP.CMP,
			0,
			registerOrError(args[1], lineNumber),
			registerOrError(args[2], lineNumber),
			0
		)
	end
	if opName == "CMPI" then
		return encodeWord(
			OP.CMPI,
			0,
			registerOrError(args[1], lineNumber),
			0,
			numberOrError(args[2], labels, lineNumber)
		)
	end
	if opName == "JMP" then
		return encodeWord(OP.JMP, 0, registerOrError(args[1], lineNumber), 0, 0)
	end
	if opName == "JEQ" or opName == "JNE" or opName == "JLT" or opName == "JGT" or opName == "JLE" or opName == "JGE" or opName == "JMPI" then
		local target = numberOrError(args[1], labels, lineNumber)
		local rel = target - (pc + 4)
		return encodeWord(OP[opName], 0, 0, 0, rel)
	end
	if opName == "CALL" then
		return encodeWord(OP.CALL, 0, registerOrError(args[1], lineNumber), 0, 0)
	end
	if opName == "RET" then
		return encodeWord(OP.RET, 0, 0, 0, 0)
	end
	if opName == "LW" or opName == "LB" then
		return encodeWord(
			OP[opName],
			registerOrError(args[1], lineNumber),
			registerOrError(args[2], lineNumber),
			0,
			numberOrError(args[3], labels, lineNumber)
		)
	end
	if opName == "SW" or opName == "SB" then
		return encodeWord(
			OP[opName],
			0,
			registerOrError(args[1], lineNumber),
			registerOrError(args[2], lineNumber),
			numberOrError(args[3], labels, lineNumber)
		)
	end
	if opName == "PUSH" then
		return encodeWord(OP.PUSH, 0, registerOrError(args[1], lineNumber), 0, 0)
	end
	if opName == "POP" then
		return encodeWord(OP.POP, registerOrError(args[1], lineNumber), 0, 0, 0)
	end
	if opName == "INT" then
		return encodeWord(OP.INT, 0, 0, 0, numberOrError(args[1], labels, lineNumber))
	end
	if opName == "IRET" then
		return encodeWord(OP.IRET, 0, 0, 0, 0)
	end
	if opName == "IN" then
		return encodeWord(
			OP.IN,
			registerOrError(args[1], lineNumber),
			0,
			0,
			numberOrError(args[2], labels, lineNumber)
		)
	end
	if opName == "OUT" then
		local portToken = args[1]
		local valueToken = args[2]
		local port = tostring(portToken or ""):upper() == "STDOUT" and config.PORT.COM1_BASE
			or numberOrError(portToken, labels, lineNumber)
		return encodeWord(OP.OUT, 0, registerOrError(valueToken, lineNumber), 0, port)
	end
	if opName == "PRINT" then
		local token = trim(args[1] or "")
		if not token:match('^".*"$') then
			error(string.format("line %d: PRINT expects a quoted string", lineNumber))
		end
		local text = decodeEscapes(token:sub(2, -2))
		local words = {}
		for i = 1, #text do
			local byte = string.byte(text, i)
			words[#words + 1] = encodeWord(OP.MOVI, 1, 0, 0, byte)
			words[#words + 1] = encodeWord(OP.OUT, 0, 1, 0, config.PORT.COM1_BASE)
		end
		return words
	end
	if opName == "EXIT" then
		local code = numberOrError(args[1] or "0", labels, lineNumber)
		return {
			encodeWord(OP.MOVI, 1, 0, 0, code),
			encodeWord(OP.HLT, 0, 0, 0, 0),
		}
	end
	if opName == "SYSCALL" then
		local syscallName = tostring(args[1] or ""):upper()
		local syscallId = NativeSyscalls.NAME_TO_ID[syscallName]
		if not syscallId then
			error(string.format("line %d: unknown syscall '%s'", lineNumber, tostring(args[1])))
		end
		return {
			encodeWord(OP.MOVI, 1, 0, 0, syscallId),
			encodeWord(OP.INT, 0, 0, 0, NativeSyscalls.VECTOR),
		}
	end

	error(string.format("line %d: unsupported instruction '%s'", lineNumber, tostring(opName)))
end

local function estimateWords(opName, args)
	if opName == "LMOVI" or opName == "EXIT" or opName == "SYSCALL" then
		return 2
	end
	if opName == "PRINT" then
		local token = trim(args and args[1] or "")
		if token:match('^".*"$') then
			return #decodeEscapes(token:sub(2, -2)) * 2
		end
		return 0
	end
	return 1
end

function NativeAssembler.compile(source, config, opts)
	opts = opts or {}
	local lines = splitLines(source)
	local parsed = {}
	local labels = {}
	local offset = 0
	local firstMeaningfulLineSkipped = false
	local nativePragma = ((config and config.VM and config.VM.NATIVE_PRAGMA) or "--!native")

	for lineNumber, rawLine in ipairs(lines) do
		local rawTrimmed = trim(rawLine)
		if not firstMeaningfulLineSkipped and rawTrimmed == nativePragma then
			firstMeaningfulLineSkipped = true
		else
			local line = stripComment(rawLine)
			if line ~= "" then
				if not firstMeaningfulLineSkipped then
					firstMeaningfulLineSkipped = true
				end
				local label = line:match("^([%a_][%w_]*)%:$")
				if label then
					labels[label] = offset * 4
				else
					local op, rest = line:match("^([%a]+)%s*(.*)$")
					if not op then
						error(string.format("line %d: cannot parse instruction", lineNumber))
					end
					op = op:upper()
					local args = splitArgs(rest)
					parsed[#parsed + 1] = {
						lineNumber = lineNumber,
						op = op,
						args = args,
						offset = offset,
					}
					offset = offset + estimateWords(op, args)
				end
			end
		end
	end

	local words = {}
	for _, instruction in ipairs(parsed) do
		local encoded = encodeInstruction(instruction, labels, config)
		if type(encoded) == "table" then
			for _, word in ipairs(encoded) do
				words[#words + 1] = word
			end
		else
			words[#words + 1] = encoded
		end
	end

	return NativeExecutable.buildFromWords(words, {
		loadAddress = opts.loadAddress or (config and config.NATIVE and config.NATIVE.DEFAULT_LOAD_ADDRESS) or config.USER_SPACE_BASE,
		stackPointer = opts.stackPointer or (config and config.NATIVE and config.NATIVE.DEFAULT_STACK_ADDRESS)
			or (config.USER_SPACE_TOP - 4),
		entryOffset = opts.entryOffset or 0,
		flags = opts.flags or 0,
	}, config)
end

return NativeAssembler
