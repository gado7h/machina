local Assembler8086 = require("@src/platforms/x86/Assembler8086")
local MachineProfile = require("@src/platforms/x86/MachineProfile")
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

local function buildCompatibilityFloppyBootValidation(config)
	return Utils.buildStandaloneBootImage(
		config,
		"CompatibilityFloppyBootValidation",
		Utils.buildTextValidationBootSource("compat floppy boot PASS")
	)
end

local function buildCompatibilityAtaBootValidation(config)
	return Utils.buildStandaloneBootImage(
		config,
		"CompatibilityAtaBootValidation",
		Utils.buildTextValidationBootSource("compat ata boot PASS")
	)
end

local function buildCompatibilityFloppyGeometryValidation(config)
	local floppy = MachineProfile.getFloppyDriveA(config)
	local expectedCylinder = math.max(0, floppy.tracks - 1)
	local expectedHead = math.max(0, floppy.heads - 1)
	local expectedSector = math.max(1, floppy.sectors)
	local source = table.concat({
		"ORG 0x7C00",
		"START:",
		"  MOV [BOOT_DRIVE], DL",
		"  MOV AH, 0x08",
		"  MOV DL, [BOOT_DRIVE]",
		"  INT 0x13",
		"  JC FAIL",
		"  CMP CH, " .. string.format("0x%02X", expectedCylinder % 0x100),
		"  JNE FAIL",
		"  MOV AL, CL",
		"  AND AL, 0x3F",
		"  CMP AL, " .. string.format("0x%02X", expectedSector % 0x100),
		"  JNE FAIL",
		"  CMP DH, " .. string.format("0x%02X", expectedHead % 0x100),
		"  JNE FAIL",
		"  CMP DL, 0x01",
		"  JNE FAIL",
		"  MOV SI, PASS_MSG",
		"  CALL PRINT_STRING",
		"HANG:",
		"  HLT",
		"  JMP HANG",
		"FAIL:",
		"  MOV SI, FAIL_MSG",
		"  CALL PRINT_STRING",
		"  HLT",
		"  JMP FAIL",
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
		"BOOT_DRIVE:",
		"  DB 0",
		"PASS_MSG:",
		'  DB "compat floppy geometry PASS", 13, 10, 0',
		"FAIL_MSG:",
		'  DB "FAIL compat floppy geometry", 13, 10, 0',
		"PADTO 0x7DFE, 0",
		"DW 0xAA55",
	}, "\n")
	return Utils.buildStandaloneBootImage(config, "CompatibilityFloppyGeometryValidation", source)
end

local function buildCompatibilityMachineProfileValidation(config)
	local equipmentWord = MachineProfile.getEquipmentWord(config)
	local baseMemK = math.floor(((config.X86 or {}).LOW_RAM_SIZE or 0xA0000) / 1024)
	local floppyNibble = MachineProfile.getFloppyDriveA(config).nibble
	local source = table.concat({
		"ORG 0x7C00",
		"START:",
		"  INT 0x11",
		"  CMP AX, " .. Utils.hex16(equipmentWord),
		"  JNE FAIL",
		"  INT 0x12",
		"  CMP AX, " .. Utils.hex16(baseMemK),
		"  JNE FAIL",
		"  MOV AL, 0x10",
		"  OUT 0x70, AL",
		"  IN AL, 0x71",
		"  CMP AL, " .. string.format("0x%02X", bit32.lshift(floppyNibble, 4) % 0x100),
		"  JNE FAIL",
		"  MOV SI, PASS_MSG",
		"  CALL PRINT_STRING",
		"HANG:",
		"  HLT",
		"  JMP HANG",
		"FAIL:",
		"  MOV SI, FAIL_MSG",
		"  CALL PRINT_STRING",
		"  HLT",
		"  JMP FAIL",
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
		"PASS_MSG:",
		'  DB "compat machine profile PASS", 13, 10, 0',
		"FAIL_MSG:",
		'  DB "FAIL compat machine profile", 13, 10, 0',
		"PADTO 0x7DFE, 0",
		"DW 0xAA55",
	}, "\n")
	return Utils.buildStandaloneBootImage(config, "CompatibilityMachineProfileValidation", source)
end

local function expectedAtaGeometry(config)
	local x86 = config.X86 or {}
	local totalSectors = tonumber(config.DISK_BLOCKS) or 0
	local heads = tonumber(x86.HEADS) or 1
	local sectorsPerTrack = tonumber(x86.SECTORS_PER_TRACK) or 18
	local cylinders = math.max(1, math.floor(totalSectors / math.max(1, heads * sectorsPerTrack)))
	local ch = cylinders % 0x100
	local cl = bit32.bor(
		bit32.band(sectorsPerTrack, 0x3F),
		bit32.lshift(bit32.band(bit32.rshift(cylinders, 8), 0x03), 6)
	)
	local dh = math.max(0, heads - 1) % 0x100
	return ch, cl, dh
end

local function buildAtaGeometryValidation(config)
	local ch, cl, dh = expectedAtaGeometry(config)
	local kernelSource = table.concat({
		"ORG 0x0500",
		"  JMP START",
		"SIG:",
		'  DB "ATA GEOMETRY PASS", 13, 10, 0',
		"START:",
		"  XOR AX, AX",
		"  MOV DS, AX",
		"  MOV ES, AX",
		"  XOR BX, BX",
		"  MOV DL, 0x80",
		"  MOV AH, 0x08",
		"  INT 0x13",
		"  JC FAIL",
		"  CMP CH, " .. string.format("0x%02X", ch),
		"  JNE FAIL",
		"  MOV AL, CL",
		"  AND AL, 0x3F",
		"  CMP AL, " .. string.format("0x%02X", bit32.band(cl, 0x3F)),
		"  JNE FAIL",
		"  MOV AL, CL",
		"  AND AL, 0xC0",
		"  CMP AL, " .. string.format("0x%02X", bit32.band(cl, 0xC0)),
		"  JNE FAIL",
		"  CMP DH, " .. string.format("0x%02X", dh),
		"  JNE FAIL",
		"  CMP DL, 0x01",
		"  JNE FAIL",
		"  MOV AX, 0x0201",
		"  MOV BX, 0x0600",
		"  MOV CX, 0x0002",
		"  MOV DL, 0x80",
		"  INT 0x13",
		"  JC FAIL",
		"  MOV SI, SIG",
		"  MOV DI, 0x0600 + SIG - $$",
		"  MOV CX, 20",
		"COMPARE_LOOP:",
		"  MOV AL, [SI]",
		"  MOV BL, [DI]",
		"  CMP AL, BL",
		"  JNE FAIL",
		"  INC SI",
		"  INC DI",
		"  LOOP COMPARE_LOOP",
		"  MOV SI, PASS_MSG",
		"  CALL PRINT_STRING",
		"HANG:",
		"  HLT",
		"  JMP HANG",
		"FAIL:",
		"  MOV SI, FAIL_MSG",
		"  CALL PRINT_STRING",
		"  HLT",
		"  JMP FAIL",
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
		"PASS_MSG:",
		'  DB "compat ata geometry PASS", 13, 10, 0',
		"FAIL_MSG:",
		'  DB "FAIL compat ata geometry", 13, 10, 0',
	}, "\n")
	local image = Utils.buildLoadedBootImage(config, "AtaGeometryValidation", kernelSource, {
		kernelOrigin = 0x0500,
		bootMessage = "ata geometry validation",
	})
	image.configOverride = {
		BOOT_ORDER = { "ata", "floppy" },
		BOOT_DRIVE = 0x80,
	}
	return image
end

local function buildKeyboardControllerValidation(config)
	local source = table.concat({
		"ORG 0x7C00",
		"START:",
		"  MOV DX, 0x0064",
		"  MOV AL, 0xAA",
		"  OUT DX, AL",
		"  MOV DX, 0x0060",
		"  IN AL, DX",
		"  CMP AL, 0x55",
		"  JNE FAIL",
		"  MOV DX, 0x0064",
		"  MOV AL, 0x20",
		"  OUT DX, AL",
		"  MOV DX, 0x0060",
		"  IN AL, DX",
		"  CMP AL, 0x05",
		"  JNE FAIL",
		"  MOV DX, 0x0064",
		"  MOV AL, 0x60",
		"  OUT DX, AL",
		"  MOV DX, 0x0060",
		"  MOV AL, 0x05",
		"  OUT DX, AL",
		"  MOV DX, 0x0064",
		"  MOV AL, 0x20",
		"  OUT DX, AL",
		"  MOV DX, 0x0060",
		"  IN AL, DX",
		"  CMP AL, 0x05",
		"  JNE FAIL",
		"  MOV DX, 0x0064",
		"  MOV AL, 0xD0",
		"  OUT DX, AL",
		"  MOV DX, 0x0060",
		"  IN AL, DX",
		"  AND AL, 0x12",
		"  CMP AL, 0x12",
		"  JNE FAIL",
		"  MOV SI, PASS_MSG",
		"  CALL PRINT_STRING",
		"HANG:",
		"  HLT",
		"  JMP HANG",
		"FAIL:",
		"  MOV SI, FAIL_MSG",
		"  CALL PRINT_STRING",
		"  HLT",
		"  JMP FAIL",
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
		"PASS_MSG:",
		'  DB "compat keyboard controller PASS", 13, 10, 0',
		"FAIL_MSG:",
		'  DB "FAIL compat keyboard controller", 13, 10, 0',
		"PADTO 0x7DFE, 0",
		"DW 0xAA55",
	}, "\n")
	return Utils.buildStandaloneBootImage(config, "KeyboardControllerValidation", source)
end

local function buildRtcCmosValidation(config)
	local x86 = config.X86 or {}
	local equipmentWord = MachineProfile.getEquipmentWord(config)
	local baseMemK = math.floor((tonumber(x86.LOW_RAM_SIZE) or 0xA0000) / 1024)
	local floppyNibble = MachineProfile.getFloppyDriveA(config).nibble
	local source = table.concat({
		"ORG 0x7C00",
		"START:",
		"  INT 0x11",
		"  CMP AX, " .. Utils.hex16(equipmentWord),
		"  JNE FAIL",
		"  INT 0x12",
		"  CMP AX, " .. Utils.hex16(baseMemK),
		"  JNE FAIL",
		"  MOV AL, 0x10",
		"  OUT 0x70, AL",
		"  IN AL, 0x71",
		"  AND AL, 0xF0",
		"  CMP AL, " .. string.format("0x%02X", bit32.lshift(floppyNibble, 4) % 0x100),
		"  JNE FAIL",
		"  MOV AL, 0x0B",
		"  OUT 0x70, AL",
		"  IN AL, 0x71",
		"  AND AL, 0x02",
		"  CMP AL, 0x02",
		"  JNE FAIL",
		"  MOV AH, 0x02",
		"  INT 0x1A",
		"  JNC TIME_OK",
		"  JMP FAIL",
		"TIME_OK:",
		"  CMP CH, 0x60",
		"  JNC FAIL",
		"  CMP CL, 0x60",
		"  JNC FAIL",
		"  CMP DH, 0x24",
		"  JNC FAIL",
		"  MOV SI, PASS_MSG",
		"  CALL PRINT_STRING",
		"HANG:",
		"  HLT",
		"  JMP HANG",
		"FAIL:",
		"  MOV SI, FAIL_MSG",
		"  CALL PRINT_STRING",
		"  HLT",
		"  JMP FAIL",
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
		"PASS_MSG:",
		'  DB "compat rtc cmos PASS", 13, 10, 0',
		"FAIL_MSG:",
		'  DB "FAIL compat rtc cmos", 13, 10, 0',
		"PADTO 0x7DFE, 0",
		"DW 0xAA55",
	}, "\n")
	return Utils.buildStandaloneBootImage(config, "RtcCmosValidation", source)
end

local function buildPitProgrammingValidation(config)
	local source = table.concat({
		"ORG 0x7C00",
		"START:",
		"  MOV DX, 0x0043",
		"  MOV AL, 0x34",
		"  OUT DX, AL",
		"  MOV DX, 0x0040",
		"  MOV AL, 0x34",
		"  OUT DX, AL",
		"  MOV AL, 0x12",
		"  OUT DX, AL",
		"  MOV DX, 0x0043",
		"  MOV AL, 0x00",
		"  OUT DX, AL",
		"  MOV DX, 0x0040",
		"  IN AL, DX",
		"  MOV BL, AL",
		"  IN AL, DX",
		"  MOV BH, AL",
		"  MOV DX, 0x0043",
		"  MOV AL, 0x00",
		"  OUT DX, AL",
		"  MOV DX, 0x0040",
		"  IN AL, DX",
		"  CMP AL, BL",
		"  JNE FAIL",
		"  IN AL, DX",
		"  CMP AL, BH",
		"  JNE FAIL",
		"  MOV DX, 0x0043",
		"  MOV AL, 0xB6",
		"  OUT DX, AL",
		"  MOV DX, 0x0042",
		"  MOV AL, 0xFF",
		"  OUT DX, AL",
		"  MOV AL, 0x7F",
		"  OUT DX, AL",
		"  MOV SI, PASS_MSG",
		"  CALL PRINT_STRING",
		"HANG:",
		"  HLT",
		"  JMP HANG",
		"FAIL:",
		"  MOV SI, FAIL_MSG",
		"  CALL PRINT_STRING",
		"  HLT",
		"  JMP FAIL",
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
		"PASS_MSG:",
		'  DB "compat pit programming PASS", 13, 10, 0',
		"FAIL_MSG:",
		'  DB "FAIL compat pit programming", 13, 10, 0',
		"PADTO 0x7DFE, 0",
		"DW 0xAA55",
	}, "\n")
	return Utils.buildStandaloneBootImage(config, "PitProgrammingValidation", source)
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

ValidationImages.CompatibilityFloppyBootValidation = {
	name = "CompatibilityFloppyBootValidation",
	build = buildCompatibilityFloppyBootValidation,
}

ValidationImages.CompatibilityAtaBootValidation = {
	name = "CompatibilityAtaBootValidation",
	build = buildCompatibilityAtaBootValidation,
}

ValidationImages.CompatibilityFloppyGeometryValidation = {
	name = "CompatibilityFloppyGeometryValidation",
	build = buildCompatibilityFloppyGeometryValidation,
}

ValidationImages.CompatibilityMachineProfileValidation = {
	name = "CompatibilityMachineProfileValidation",
	build = buildCompatibilityMachineProfileValidation,
}

ValidationImages.AtaGeometryValidation = {
	name = "AtaGeometryValidation",
	build = buildAtaGeometryValidation,
}

ValidationImages.KeyboardControllerValidation = {
	name = "KeyboardControllerValidation",
	build = buildKeyboardControllerValidation,
}

ValidationImages.RtcCmosValidation = {
	name = "RtcCmosValidation",
	build = buildRtcCmosValidation,
}

ValidationImages.PitProgrammingValidation = {
	name = "PitProgrammingValidation",
	build = buildPitProgrammingValidation,
}

return ValidationImages
