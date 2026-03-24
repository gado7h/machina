local Assembler8086 = require("@src/platforms/x86/Assembler8086")
local Utils = require("@src/platforms/x86/BootImageCatalogUtils")

local ValidationImages = {}

local function buildProtectedModeValidationKernel(config, passText, options)
	options = options or {}
	local x86 = config.X86 or {}
	local interruptVector = options.interruptVector
	local interruptHandler = options.interruptHandler
	local interruptGateType = options.interruptGateType or "0x8E00"
	local bodyLines = options.bodyLines or {}
	local handlerLines = options.handlerLines or {}
	local maxVector = math.max(interruptVector or 0, options.exceptionVector or 0)
	local idtEntries = {}
	if interruptVector and interruptHandler then
		idtEntries[interruptVector] = {
			offset = interruptHandler,
			selector = "0x0008",
			typeWord = interruptGateType,
		}
	end
	if options.exceptionVector and options.exceptionHandler then
		idtEntries[options.exceptionVector] = {
			offset = options.exceptionHandler,
			selector = "0x0008",
			typeWord = options.exceptionGateType or "0x8E00",
		}
	end

	local lines = {
		"ORG 0x0500",
		"START:",
		"  CLI",
		"  LGDT [GDT_DESC]",
		"  LIDT [IDT_DESC]",
		"  MOV AX, 1",
		"  LMSW AX",
		"  DB 0xEA",
		"  DW PM_ENTRY",
		"  DW 0x0008",
		"PM_ENTRY:",
		"  MOV AX, 0x0010",
		"  MOV DS, AX",
		"  MOV SS, AX",
		"  MOV ESP, 0x00007B00",
		"  MOV AX, 0x0018",
		"  MOV ES, AX",
		"  XOR EDI, EDI",
	}

	for _, line in ipairs(bodyLines) do
		lines[#lines + 1] = line
	end

	lines[#lines + 1] = "  MOV ESI, PASS_MSG"
	lines[#lines + 1] = "  CALL PRINT_STRING_PM"
	lines[#lines + 1] = "PM_HANG:"
	lines[#lines + 1] = "  HLT"
	lines[#lines + 1] = "  JMP PM_HANG"

	for _, line in ipairs(handlerLines) do
		lines[#lines + 1] = line
	end

	for _, line in ipairs(Utils.buildProtectedModeKernelRoutines(passText)) do
		lines[#lines + 1] = line
	end

	lines[#lines + 1] = "PM_FLAG:"
	lines[#lines + 1] = "  DB 0"
	lines[#lines + 1] = "EX_FLAG:"
	lines[#lines + 1] = "  DB 0"

	local kernelCode = Utils.descriptorWords(0, 0x9A, 0x000FFFFF, 0x0C)
	local kernelData = Utils.descriptorWords(0, 0x92, 0x000FFFFF, 0x0C)
	local videoData = Utils.descriptorWords(
		x86.TEXT_BUFFER_BASE or 0xB8000,
		0x92,
		math.max(0, (x86.TEXT_BUFFER_SIZE or 0x8000) - 1),
		0x04
	)

	lines[#lines + 1] = "GDT:"
	lines[#lines + 1] = "  DW 0x0000, 0x0000, 0x0000, 0x0000"
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelCode.limitLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelCode.baseLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelCode.accessBaseMid)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelCode.flagsBaseHigh)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelData.limitLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelData.baseLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelData.accessBaseMid)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelData.flagsBaseHigh)
	lines[#lines + 1] = "  DW " .. Utils.hex16(videoData.limitLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(videoData.baseLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(videoData.accessBaseMid)
	lines[#lines + 1] = "  DW " .. Utils.hex16(videoData.flagsBaseHigh)
	lines[#lines + 1] = "GDT_DESC:"
	lines[#lines + 1] = "  DW GDT_END - GDT - 1"
	lines[#lines + 1] = "  DW GDT"
	lines[#lines + 1] = "  DW 0x0000"
	lines[#lines + 1] = "GDT_END:"

	lines[#lines + 1] = "IDT:"
	for _, line in ipairs(Utils.buildIdtEntries(maxVector, idtEntries)) do
		lines[#lines + 1] = line
	end
	lines[#lines + 1] = "IDT_DESC:"
	lines[#lines + 1] = "  DW IDT_END - IDT - 1"
	lines[#lines + 1] = "  DW IDT"
	lines[#lines + 1] = "  DW 0x0000"
	lines[#lines + 1] = "IDT_END:"

	return table.concat(lines, "\n")
end

local function buildCpuProtectedModeValidation(config)
	local kernelSource = buildProtectedModeValidationKernel(config, "cpu pm validation PASS", {
		interruptVector = 0x30,
		interruptHandler = "PM_INT_HANDLER",
		interruptGateType = "0x8E00",
		bodyLines = {
			"  CALL PM_NEAR_CHECK",
			"  INT 0x30",
			"  CMP BYTE [PM_FLAG], 1",
			"  JNE PM_FAIL",
		},
		handlerLines = {
			"PM_NEAR_CHECK:",
			"  RET",
			"PM_INT_HANDLER:",
			"  MOV BYTE [PM_FLAG], 1",
			"  IRET",
			"PM_FAIL:",
			"  MOV ESI, FAIL_MSG",
			"  CALL PRINT_STRING_PM",
			"  HLT",
			"  JMP PM_FAIL",
		},
	})
	return Utils.buildLoadedBootImage(config, "CpuProtectedModeValidation", kernelSource, {
		kernelOrigin = 0x0500,
		defaultOperand32 = true,
		bootMessage = "cpu pm validation",
	})
end

local function buildCpuExceptionValidation(config)
	local kernelSource = buildProtectedModeValidationKernel(config, "cpu exception validation PASS", {
		exceptionVector = 6,
		exceptionHandler = "PM_EXCEPTION_HANDLER",
		exceptionGateType = "0x8E00",
		bodyLines = {
			"  DB 0x0F, 0x0B",
			"  CMP BYTE [EX_FLAG], 1",
			"  JNE PM_FAIL",
		},
		handlerLines = {
			"PM_EXCEPTION_HANDLER:",
			"  MOV BYTE [EX_FLAG], 1",
			"  IRET",
			"PM_FAIL:",
			"  MOV ESI, FAIL_MSG",
			"  CALL PRINT_STRING_PM",
			"  HLT",
			"  JMP PM_FAIL",
		},
	})
	return Utils.buildLoadedBootImage(config, "CpuExceptionValidation", kernelSource, {
		kernelOrigin = 0x0500,
		defaultOperand32 = true,
		bootMessage = "cpu exception validation",
	})
end

local function buildPrivilegeTransitionKernelSource(config, tssBase)
	local x86 = config.X86 or {}
	local kernelCode = Utils.descriptorWords(0, 0x9A, 0x000FFFFF, 0x0C)
	local kernelData = Utils.descriptorWords(0, 0x92, 0x000FFFFF, 0x0C)
	local userCode = Utils.descriptorWords(0, 0xFA, 0x000FFFFF, 0x0C)
	local userData = Utils.descriptorWords(0, 0xF2, 0x000FFFFF, 0x0C)
	local videoData = Utils.descriptorWords(
		x86.TEXT_BUFFER_BASE or 0xB8000,
		0x92,
		math.max(0, (x86.TEXT_BUFFER_SIZE or 0x8000) - 1),
		0x04
	)
	local tssDescriptor = Utils.descriptorWords(tssBase or 0, 0x89, 0x0067, 0x00)

	local lines = {
		"ORG 0x0500",
		"START:",
		"  CLI",
		"  LGDT [GDT_DESC]",
		"  LIDT [IDT_DESC]",
		"  MOV AX, 0x0030",
		"  DB 0x0F, 0x00, 0xD8",
		"  MOV AX, 1",
		"  LMSW AX",
		"  DB 0xEA",
		"  DD PM_ENTRY",
		"  DW 0x0008",
		"PM_ENTRY:",
		"  MOV AX, 0x0010",
		"  MOV DS, AX",
		"  MOV SS, AX",
		"  MOV ESP, 0x00007B00",
		"  MOV AX, 0x0018",
		"  MOV ES, AX",
		"  XOR EDI, EDI",
		"  PUSH 0x0000002B",
		"  PUSH 0x00007900",
		"  PUSH 0x00000202",
		"  PUSH 0x00000023",
		"  PUSH USER_ENTRY",
		"  IRET",
		"PM_FAIL:",
		"  MOV ESI, FAIL_MSG",
		"  CALL PRINT_STRING_PM",
		"PM_FAIL_HANG:",
		"  HLT",
		"  JMP PM_FAIL_HANG",
		"USER_ENTRY:",
		"  MOV AX, 0x002B",
		"  MOV DS, AX",
		"  MOV BYTE [USER_FLAG], 1",
		"  INT 0x31",
		"  CMP BYTE [PRIV_FLAG], 1",
		"  JNE PM_FAIL",
		"  MOV AX, SS",
		"  CMP AX, 0x002B",
		"  JNE PM_FAIL",
		"  MOV ESI, PASS_MSG",
		"  CALL PRINT_STRING_PM",
		"USER_HANG:",
		"  HLT",
		"  JMP USER_HANG",
		"PM_PRIV_HANDLER:",
		"  MOV AX, SS",
		"  CMP AX, 0x0010",
		"  JNE PM_FAIL",
		"  CMP BYTE [USER_FLAG], 1",
		"  JNE PM_FAIL",
		"  MOV BYTE [PRIV_FLAG], 1",
		"  IRET",
	}

	for _, line in ipairs(Utils.buildProtectedModeKernelRoutines("privilege transition validation PASS")) do
		lines[#lines + 1] = line
	end

	lines[#lines + 1] = "USER_FLAG:"
	lines[#lines + 1] = "  DB 0"
	lines[#lines + 1] = "PRIV_FLAG:"
	lines[#lines + 1] = "  DB 0"

	lines[#lines + 1] = "GDT:"
	lines[#lines + 1] = "  DW 0x0000, 0x0000, 0x0000, 0x0000"
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelCode.limitLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelCode.baseLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelCode.accessBaseMid)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelCode.flagsBaseHigh)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelData.limitLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelData.baseLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelData.accessBaseMid)
	lines[#lines + 1] = "  DW " .. Utils.hex16(kernelData.flagsBaseHigh)
	lines[#lines + 1] = "  DW " .. Utils.hex16(videoData.limitLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(videoData.baseLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(videoData.accessBaseMid)
	lines[#lines + 1] = "  DW " .. Utils.hex16(videoData.flagsBaseHigh)
	lines[#lines + 1] = "  DW " .. Utils.hex16(userCode.limitLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(userCode.baseLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(userCode.accessBaseMid)
	lines[#lines + 1] = "  DW " .. Utils.hex16(userCode.flagsBaseHigh)
	lines[#lines + 1] = "  DW " .. Utils.hex16(userData.limitLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(userData.baseLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(userData.accessBaseMid)
	lines[#lines + 1] = "  DW " .. Utils.hex16(userData.flagsBaseHigh)
	lines[#lines + 1] = "  DW " .. Utils.hex16(tssDescriptor.limitLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(tssDescriptor.baseLow)
	lines[#lines + 1] = "  DW " .. Utils.hex16(tssDescriptor.accessBaseMid)
	lines[#lines + 1] = "  DW " .. Utils.hex16(tssDescriptor.flagsBaseHigh)
	lines[#lines + 1] = "GDT_DESC:"
	lines[#lines + 1] = "  DW GDT_END - GDT - 1"
	lines[#lines + 1] = "  DW GDT"
	lines[#lines + 1] = "  DW 0x0000"
	lines[#lines + 1] = "GDT_END:"

	lines[#lines + 1] = "IDT:"
	for vector = 0, 0x31 do
		if vector == 0x31 then
			lines[#lines + 1] = "  DW PM_PRIV_HANDLER, 0x0008, 0x0000, 0xEE00, 0x0000"
		else
			lines[#lines + 1] = "  DW 0x0000, 0x0000, 0x0000, 0x0000, 0x0000"
		end
	end
	lines[#lines + 1] = "IDT_DESC:"
	lines[#lines + 1] = "  DW IDT_END - IDT - 1"
	lines[#lines + 1] = "  DW IDT"
	lines[#lines + 1] = "  DW 0x0000"
	lines[#lines + 1] = "IDT_END:"

	lines[#lines + 1] = "TSS:"
	lines[#lines + 1] = "  DW 0x0000, 0x0000"
	lines[#lines + 1] = "  DD 0x00007B00"
	lines[#lines + 1] = "  DW 0x0010, 0x0000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DW 0x0000, 0x0000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DW 0x0000, 0x0000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DD 0x00000000"
	lines[#lines + 1] = "  DD 0x00000068"
	lines[#lines + 1] = "  PADTO TSS + 0x68, 0"

	return table.concat(lines, "\n")
end

local function buildPrivilegeTransitionValidation(config)
	local kernelSource = buildPrivilegeTransitionKernelSource(config, 0)
	local artifact = Assembler8086.compile(kernelSource, {
		origin = 0x0500,
		defaultOperand32 = true,
	})
	kernelSource = buildPrivilegeTransitionKernelSource(config, artifact.symbols and artifact.symbols.TSS or 0)
	return Utils.buildLoadedBootImage(config, "PrivilegeTransitionValidation", kernelSource, {
		kernelOrigin = 0x0500,
		defaultOperand32 = true,
		bootMessage = "privilege transition validation",
	})
end

local function buildBiosBootValidation(config)
	local kernelSource = Utils.buildTextValidationBootSource("bios boot validation PASS")
	return Utils.buildLoadedBootImage(config, "BiosBootValidation", kernelSource, {
		kernelOrigin = 0x0500,
		bootMessage = "bios boot validation",
	})
end

local function buildInterruptIntegrationValidation(config)
	local kernelSource = table.concat({
		"ORG 0x0500",
		"START:",
		"  CLI",
		"  XOR AX, AX",
		"  MOV DS, AX",
		"  MOV ES, AX",
		"  MOV SS, AX",
		"  MOV SP, 0x7B00",
		"  MOV AX, IRQ0_HANDLER",
		"  MOV [IRQ0_VECTOR], AX",
		"  MOV AX, 0x0000",
		"  MOV [IRQ0_VECTOR + 2], AX",
		"  XOR AL, AL",
		"  OUT 0x21, AL",
		"  OUT 0xA1, AL",
		"  MOV AL, 0x34",
		"  OUT 0x43, AL",
		"  MOV AL, 0x02",
		"  OUT 0x40, AL",
		"  XOR AL, AL",
		"  OUT 0x40, AL",
		"  STI",
		"WAIT_IRQ:",
		"  CMP BYTE [IRQ_FLAG], 1",
		"  JNE WAIT_IRQ",
		"  MOV SI, PASS_MSG",
		"  CALL PRINT_STRING",
		"HANG:",
		"  HLT",
		"  JMP HANG",
		"IRQ0_HANDLER:",
		"  MOV BYTE [IRQ_FLAG], 1",
		"  MOV AL, 0x20",
		"  OUT 0x20, AL",
		"  IRET",
		"PRINT_STRING:",
		"  MOV AL, [SI]",
		"  CMP AL, 0",
		"  JE PRINT_DONE",
		"  MOV AH, 0x0E",
		"  INT 0x10",
		"  INC SI",
		"  JMP PRINT_STRING",
		"PRINT_DONE:",
		"  RET",
		"IRQ0_VECTOR:",
		"  DW 0x0000, 0x0000",
		"IRQ_FLAG:",
		"  DB 0",
		"PASS_MSG:",
		'  DB "interrupt integration validation PASS", 13, 10, 0',
	}, "\n")
	return Utils.buildLoadedBootImage(config, "InterruptIntegrationValidation", kernelSource, {
		kernelOrigin = 0x0500,
		bootMessage = "interrupt integration validation",
	})
end

local function buildResetVectorValidation(config)
	return Utils.buildStandaloneBootImage(
		config,
		"ResetVectorValidation",
		Utils.buildTextValidationBootSource("reset vector validation PASS")
	)
end

local function buildVgaTextValidation(config)
	local source = table.concat({
		"ORG 0x7C00",
		"START:",
		"  MOV AX, 0x0003",
		"  INT 0x10",
		"  MOV AX, 0xB800",
		"  MOV DS, AX",
		"  XOR DI, DI",
		"  MOV SI, TEXT_MSG",
		"TEXT_LOOP:",
		"  MOV AL, [SI]",
		"  CMP AL, 0",
		"  JE HANG",
		"  MOV [DI], AL",
		"  INC DI",
		"  MOV BYTE [DI], 0x1E",
		"  INC DI",
		"  INC SI",
		"  JMP TEXT_LOOP",
		"HANG:",
		"  HLT",
		"  JMP HANG",
		"TEXT_MSG:",
		'  DB "VGA 03h TEXT VALIDATION", 0',
		"PADTO 0x7DFE, 0",
		"DW 0xAA55",
	}, "\n")
	return Utils.buildStandaloneBootImage(config, "VgaTextValidation", source)
end

local function buildVgaMode13Validation(config)
	local source = table.concat({
		"ORG 0x7C00",
		"START:",
		"  MOV AX, 0x0013",
		"  INT 0x10",
		"  MOV AX, 0xA000",
		"  MOV DS, AX",
		"  XOR DI, DI",
		"  XOR BX, BX",
		"FILL_LOOP:",
		"  MOV AL, BL",
		"  MOV [DI], AL",
		"  INC DI",
		"  INC BL",
		"  CMP DI, 0xFA00",
		"  JNE FILL_LOOP",
		"HANG:",
		"  HLT",
		"  JMP HANG",
		"PADTO 0x7DFE, 0",
		"DW 0xAA55",
	}, "\n")
	return Utils.buildStandaloneBootImage(config, "VgaMode13Validation", source)
end

local function buildVgaPlanarValidation(config)
	local source = table.concat({
		"ORG 0x7C00",
		"START:",
		"  MOV AX, 0x000D",
		"  INT 0x10",
		"  MOV DX, 0x03C4",
		"  MOV AL, 0x02",
		"  OUT DX, AL",
		"  INC DX",
		"  MOV AL, 0x0F",
		"  OUT DX, AL",
		"  MOV DX, 0x03CE",
		"  MOV AL, 0x08",
		"  OUT DX, AL",
		"  INC DX",
		"  MOV AL, 0xFF",
		"  OUT DX, AL",
		"  MOV AX, 0xA000",
		"  MOV DS, AX",
		"  XOR DI, DI",
		"  MOV CX, 8000",
		"  MOV AL, 0xAA",
		"PLANAR_LOOP:",
		"  MOV [DI], AL",
		"  INC DI",
		"  LOOP PLANAR_LOOP",
		"HANG:",
		"  HLT",
		"  JMP HANG",
		"PADTO 0x7DFE, 0",
		"DW 0xAA55",
	}, "\n")
	return Utils.buildStandaloneBootImage(config, "VgaPlanarValidation", source)
end

local function buildVgaFontValidation(config)
	local source = table.concat({
		"ORG 0x7C00",
		"START:",
		"  MOV AX, 0x0003",
		"  INT 0x10",
		"  MOV DX, 0x03C4",
		"  MOV AL, 0x02",
		"  OUT DX, AL",
		"  INC DX",
		"  MOV AL, 0x04",
		"  OUT DX, AL",
		"  MOV DX, 0x03CE",
		"  MOV AL, 0x04",
		"  OUT DX, AL",
		"  INC DX",
		"  MOV AL, 0x02",
		"  OUT DX, AL",
		"  DEC DX",
		"  MOV AL, 0x06",
		"  OUT DX, AL",
		"  INC DX",
		"  MOV AL, 0x00",
		"  OUT DX, AL",
		"  MOV AX, 0xA000",
		"  MOV DS, AX",
		"  MOV DI, 0x0820",
		"  MOV CX, 16",
		"FONT_LOOP:",
		"  MOV AL, 0x18",
		"  MOV [DI], AL",
		"  INC DI",
		"  LOOP FONT_LOOP",
		"  MOV AX, 0x0003",
		"  INT 0x10",
		"  MOV AX, 0xB800",
		"  MOV DS, AX",
		"  MOV BYTE [0], 'A'",
		"  MOV BYTE [1], 0x1F",
		"HANG:",
		"  HLT",
		"  JMP HANG",
		"PADTO 0x7DFE, 0",
		"DW 0xAA55",
	}, "\n")
	return Utils.buildStandaloneBootImage(config, "VgaFontValidation", source)
end

local function buildVgaPaletteValidation(config)
	local source = table.concat({
		"ORG 0x7C00",
		"START:",
		"  MOV AX, 0x0013",
		"  INT 0x10",
		"  MOV DX, 0x03C8",
		"  XOR AL, AL",
		"  OUT DX, AL",
		"  INC DX",
		"  MOV AL, 0x3F",
		"  OUT DX, AL",
		"  XOR AL, AL",
		"  OUT DX, AL",
		"  XOR AL, AL",
		"  OUT DX, AL",
		"  MOV AX, 0xA000",
		"  MOV DS, AX",
		"  XOR DI, DI",
		"  MOV CX, 0xFA00",
		"  XOR AL, AL",
		"PALETTE_LOOP:",
		"  MOV [DI], AL",
		"  INC DI",
		"  LOOP PALETTE_LOOP",
		"HANG:",
		"  HLT",
		"  JMP HANG",
		"PADTO 0x7DFE, 0",
		"DW 0xAA55",
	}, "\n")
	return Utils.buildStandaloneBootImage(config, "VgaPaletteValidation", source)
end

ValidationImages.ResetVectorValidation = {
	name = "ResetVectorValidation",
	build = buildResetVectorValidation,
}

ValidationImages.BiosBootValidation = {
	name = "BiosBootValidation",
	build = buildBiosBootValidation,
}

ValidationImages.InterruptIntegrationValidation = {
	name = "InterruptIntegrationValidation",
	build = buildInterruptIntegrationValidation,
}

ValidationImages.CpuProtectedModeValidation = {
	name = "CpuProtectedModeValidation",
	build = buildCpuProtectedModeValidation,
}

ValidationImages.CpuExceptionValidation = {
	name = "CpuExceptionValidation",
	build = buildCpuExceptionValidation,
}

ValidationImages.PrivilegeTransitionValidation = {
	name = "PrivilegeTransitionValidation",
	build = buildPrivilegeTransitionValidation,
}

ValidationImages.VgaTextValidation = {
	name = "VgaTextValidation",
	build = buildVgaTextValidation,
}

ValidationImages.VgaMode13Validation = {
	name = "VgaMode13Validation",
	build = buildVgaMode13Validation,
}

ValidationImages.VgaPlanarValidation = {
	name = "VgaPlanarValidation",
	build = buildVgaPlanarValidation,
}

ValidationImages.VgaFontValidation = {
	name = "VgaFontValidation",
	build = buildVgaFontValidation,
}

ValidationImages.VgaPaletteValidation = {
	name = "VgaPaletteValidation",
	build = buildVgaPaletteValidation,
}

return ValidationImages
