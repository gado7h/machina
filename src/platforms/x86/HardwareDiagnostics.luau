local ProtectedModeSelfTest = require(script.Parent.ProtectedModeSelfTest)
local BiosInterrupts = require(script.Parent.BiosInterrupts)
local BootImageCatalog = require(script.Parent.BootImageCatalog)

local HardwareDiagnostics = {}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in pairs(value) do
		out[key] = deepCopy(child)
	end
	return out
end

local function restoreTable(target, snapshot)
	for key in pairs(target) do
		target[key] = nil
	end
	for key, value in pairs(snapshot) do
		target[key] = deepCopy(value)
	end
end

local function wrapTest(name, run)
	local ok, passed, detail = pcall(run)
	if not ok then
		return {
			name = name,
			passed = false,
			detail = tostring(passed),
		}
	end
	return {
		name = name,
		passed = passed ~= false,
		detail = tostring(detail or (passed ~= false and "ok" or "failed")),
	}
end

local function copyStats(device)
	return deepCopy(device and device.stats or {})
end

local function restoreStats(device, snapshot)
	if device and device.stats and snapshot then
		restoreTable(device.stats, snapshot)
	end
end

local function snapshotObjectState(object, excluded)
	local snapshot = {}
	for key, value in pairs(object) do
		if not (excluded and excluded[key]) and type(value) ~= "function" then
			snapshot[key] = deepCopy(value)
		end
	end
	return snapshot
end

local function restoreObjectState(object, snapshot, excluded)
	for key, value in pairs(object) do
		if not (excluded and excluded[key]) and type(value) ~= "function" and snapshot[key] == nil then
			object[key] = nil
		end
	end
	for key, value in pairs(snapshot) do
		object[key] = deepCopy(value)
	end
end

local function formatHex(value, width)
	local digits = width or 2
	return string.format("0x%0" .. tostring(digits) .. "X", (tonumber(value) or 0) % (2 ^ (digits * 4)))
end

local function decodeRTCValue(value, binaryMode)
	local byteValue = (tonumber(value) or 0) % 0x100
	if binaryMode then
		return byteValue
	end
	return ((math.floor(byteValue / 16) % 16) * 10) + (byteValue % 16)
end

local function snapshotPIC(pic)
	return {
		master = deepCopy(pic.master),
		slave = deepCopy(pic.slave),
		stats = copyStats(pic),
	}
end

local function restorePIC(pic, snapshot)
	pic.master = deepCopy(snapshot.master)
	pic.slave = deepCopy(snapshot.slave)
	restoreStats(pic, snapshot.stats)
end

local function snapshotMachineForGuestValidation(machine)
	return {
		cpu = snapshotObjectState(machine.cpu, {
			bus = true,
			config = true,
			x86 = true,
			_bios = true,
		}),
		cpuBios = machine.cpu._bios,
		ram = snapshotObjectState(machine.ram, {
			config = true,
		}),
		rom = snapshotObjectState(machine.rom, {
			config = true,
		}),
		hdd = snapshotObjectState(machine.hdd, {
			config = true,
			_bus = true,
		}),
		gpu = snapshotObjectState(machine.gpu, {
			config = true,
			_bus = true,
			_pixelBuffer = true,
		}),
		keyboard = snapshotObjectState(machine.keyboard, {
			config = true,
			_bus = true,
		}),
		pic = snapshotPIC(machine.bus.pic),
		timer = snapshotObjectState(machine.bus.timer, {
			config = true,
			_bus = true,
		}),
		busStats = copyStats(machine.bus),
		busFault = deepCopy(machine.bus:peekFault()),
	}
end

local function restoreMachineAfterGuestValidation(machine, snapshot)
	restoreObjectState(machine.cpu, snapshot.cpu, {
		bus = true,
		config = true,
		x86 = true,
		_bios = true,
	})
	machine.cpu:attachBIOS(snapshot.cpuBios)
	restoreObjectState(machine.ram, snapshot.ram, {
		config = true,
	})
	restoreObjectState(machine.rom, snapshot.rom, {
		config = true,
	})
	restoreObjectState(machine.hdd, snapshot.hdd, {
		config = true,
		_bus = true,
	})
	restoreObjectState(machine.gpu, snapshot.gpu, {
		config = true,
		_bus = true,
		_pixelBuffer = true,
	})
	restoreObjectState(machine.keyboard, snapshot.keyboard, {
		config = true,
		_bus = true,
	})
	restorePIC(machine.bus.pic, snapshot.pic)
	restoreObjectState(machine.bus.timer, snapshot.timer, {
		config = true,
		_bus = true,
	})
	restoreStats(machine.bus, snapshot.busStats)
	machine.bus._fault = deepCopy(snapshot.busFault)
	if machine.gpu and type(machine.gpu.flush) == "function" then
		machine.gpu:flush()
	end
end

local function buildCatalogImage(config, imageName)
	local entry = BootImageCatalog[imageName]
	assert(entry, "unknown guest validation image: " .. tostring(imageName))
	if type(entry) == "function" then
		return entry(config)
	end
	if type(entry) == "table" and type(entry.build) == "function" then
		return entry.build(config)
	end
	if type(entry) == "table" then
		return entry
	end
	error("invalid guest validation image entry: " .. tostring(imageName))
end

local function readGuestTextRows(machine, config, rowCount)
	local x86 = config.X86 or {}
	local cols = config.TEXT_COLS or 80
	local rows = rowCount or (config.TEXT_ROWS or 25)
	local textBase = x86.TEXT_BUFFER_BASE or 0xB8000
	local out = {}
	for row = 0, rows - 1 do
		local chars = {}
		for col = 0, cols - 1 do
			local byteValue = machine.bus:memRead(textBase + (row * cols + col) * 2)
			local ch = byteValue >= 32 and byteValue <= 126 and string.char(byteValue) or " "
			chars[#chars + 1] = ch
		end
		out[#out + 1] = table.concat(chars):gsub("%s+$", "")
	end
	return out
end

local function runGuestValidationImage(machine, config, imageName, expectedText)
	local snapshot = snapshotMachineForGuestValidation(machine)
	local success, passed, detail = pcall(function()
		local diagConfig = ((config.X86 or {}).DIAGNOSTICS or {})
		local maxSteps = diagConfig.REVIEW_GUEST_VALIDATION_MAX_STEPS or 50000
		local yieldEvery = diagConfig.REVIEW_GUEST_VALIDATION_YIELD_EVERY or 2000
		local image = buildCatalogImage(config, imageName)
		machine.hdd._sectors = {}
		for lba, sector in pairs(image.sectors or {}) do
			machine.hdd:writeSector(lba, sector)
		end
		machine.rom:flash(image.romBytes or {})
		machine.cpu:reset()
		machine.cpu:attachBIOS(BiosInterrupts.new(machine, {}, image))
		if machine.bus and machine.bus.timer then
			machine.bus.timer._enabled = false
			machine.bus.timer._irqEnabled = false
		end

		local haltedCount = 0
		local observed = ""
		for step = 1, maxSteps do
			if task and task.wait and yieldEvery > 0 and step % yieldEvery == 0 then
				task.wait()
			end
			local ok, result = pcall(function()
				return machine.cpu:step()
			end)
			if not ok then
				local rows = readGuestTextRows(machine, config, 4)
				return false, string.format("fault at step=%d err=%s text=%s", step, tostring(result), table.concat(rows, " | "))
			end

			if step % 64 == 0 or result == "HLT" then
				local rows = readGuestTextRows(machine, config, 6)
				observed = table.concat(rows, "\n")
				if observed:find(expectedText, 1, true) then
					return true, string.format("matched '%s' after %d steps", expectedText, step)
				end
				if observed:find("FAIL", 1, true) then
					return false, string.format("guest reported failure after %d steps: %s", step, table.concat(rows, " | "))
				end
			end

			if result == "HLT" then
				haltedCount = haltedCount + 1
				if haltedCount >= 16 then
					break
				end
			else
				haltedCount = 0
			end
		end

		local rows = readGuestTextRows(machine, config, 6)
		return false, string.format("timeout waiting for '%s': %s", expectedText, table.concat(rows, " | "))
	end)
	restoreMachineAfterGuestValidation(machine, snapshot)
	if not success then
		return false, tostring(passed)
	end
	return passed, detail
end

local function testPIC(machine, config)
	local bus = machine.bus
	local pic = bus.pic
	local snapshot = snapshotPIC(pic)
	local busStats = copyStats(bus)

	local ports = config.PORT
	bus:portWrite(ports.PIC_MASTER_CMD, 0x11)
	bus:portWrite(ports.PIC_SLAVE_CMD, 0x11)
	bus:portWrite(ports.PIC_MASTER_DATA, 0x20)
	bus:portWrite(ports.PIC_SLAVE_DATA, 0x28)
	bus:portWrite(ports.PIC_MASTER_DATA, 0x04)
	bus:portWrite(ports.PIC_SLAVE_DATA, 0x02)
	bus:portWrite(ports.PIC_MASTER_DATA, 0x01)
	bus:portWrite(ports.PIC_SLAVE_DATA, 0x01)
	bus:portWrite(ports.PIC_MASTER_DATA, 0x00)
	bus:portWrite(ports.PIC_SLAVE_DATA, 0x00)

	bus:raiseIRQ(1, { source = "diag-pic" })
	local vector1 = bus:getPendingInterruptVector()
	if vector1 then
		bus:endOfInterrupt(vector1)
	end

	bus:raiseIRQ(14, { source = "diag-pic" })
	local vector2 = bus:getPendingInterruptVector()
	if vector2 then
		bus:endOfInterrupt(vector2)
	end

	restorePIC(pic, snapshot)
	restoreStats(bus, busStats)

	local passed = vector1 == 0x21 and vector2 == 0x2E
	return passed, string.format("irq1=%s irq14=%s", formatHex(vector1), formatHex(vector2))
end

local function testPIT(machine, config)
	local bus = machine.bus
	local timer = bus.timer
	local picSnapshot = snapshotPIC(bus.pic)
	local timerChannels = deepCopy(timer._channels)
	local timerSubTicks = timer._subTicks
	local timerStats = copyStats(timer)
	local busStats = copyStats(bus)

	bus.pic.master.imr = 0x00
	bus.pic.slave.imr = 0x00
	bus:portWrite(config.PORT.PIT_CMD, 0x34)
	bus:portWrite(config.PORT.PIT_CHAN0, 0x02)
	bus:portWrite(config.PORT.PIT_CHAN0, 0x00)
	timer:tick(4 / math.max(1, timer._baseHz or 1193182))
	local vector = bus:getPendingInterruptVector()
	if vector then
		bus:endOfInterrupt(vector)
	end

	timer._channels = deepCopy(timerChannels)
	timer._subTicks = timerSubTicks
	restoreStats(timer, timerStats)
	restorePIC(bus.pic, picSnapshot)
	restoreStats(bus, busStats)

	local expected = ((config.X86 and config.X86.PIC_VECTOR_BASE_MASTER) or config.PIC_VECTOR_BASE_MASTER or 0x08)
	local passed = vector == expected
	return passed, string.format("pit_vector=%s expected=%s", formatHex(vector), formatHex(expected))
end

local function testVGA(machine, config)
	local bus = machine.bus
	local gpu = machine.gpu
	local x86 = config.X86 or {}
	local textBase = x86.TEXT_BUFFER_BASE or 0xB8000
	local graphicsBase = x86.VIDEO_BASE or config.VRAM_BASE or 0xA0000
	local busStats = copyStats(bus)
	local gpuStats = copyStats(gpu)
	local savedText0 = bus:memRead(textBase)
	local savedText1 = bus:memRead(textBase + 1)
	local savedGraphics0 = bus:memRead(graphicsBase)
	local savedGraphics1 = bus:memRead(graphicsBase + 1)
	local crtc = {
		index = gpu._crtcIndex,
		hi = gpu._crtc[0x0E] or 0,
		lo = gpu._crtc[0x0F] or 0,
		startHi = gpu._crtc[0x0C] or 0,
		startLo = gpu._crtc[0x0D] or 0,
		mode = gpu._biosMode,
		misc = gpu._miscOutput,
		attrIndex = gpu._attrIndex,
		attrFlipFlop = gpu._attrFlipFlop,
		dacMask = gpu._dacMask,
		dacReadIndex = gpu._dacReadIndex,
		dacWriteIndex = gpu._dacWriteIndex,
		dacReadComponent = gpu._dacReadComponent,
		dacWriteComponent = gpu._dacWriteComponent,
	}
	local savedSeq = deepCopy(gpu._sequencer)
	local savedGraphics = deepCopy(gpu._graphics)
	local savedAttr = deepCopy(gpu._attribute)
	local savedDac = deepCopy(gpu._dac)

	gpu:biosSetVideoMode(0x03)
	bus:memWrite(textBase, string.byte("Z"))
	bus:memWrite(textBase + 1, 0x1E)
	bus:portWrite(config.PORT.VGA_CRTC_INDEX, 0x0F)
	bus:portWrite(config.PORT.VGA_CRTC_DATA, 0x05)
	bus:portWrite(config.PORT.VGA_CRTC_INDEX, 0x0E)
	bus:portWrite(config.PORT.VGA_CRTC_DATA, 0x00)
	bus:portRead(config.PORT.VGA_INPUT_STATUS1)
	bus:portWrite(config.PORT.VGA_ATTR_INDEX, 0x02)
	bus:portWrite(config.PORT.VGA_ATTR_INDEX, 0x12)
	bus:portWrite(config.PORT.VGA_DAC_WRITE_INDEX, 0x12)
	bus:portWrite(config.PORT.VGA_DAC_DATA, 0x3F)
	bus:portWrite(config.PORT.VGA_DAC_DATA, 0x00)
	bus:portWrite(config.PORT.VGA_DAC_DATA, 0x00)
	bus:portWrite(config.PORT.VGA_DAC_READ_INDEX, 0x12)
	local dacR = bus:portRead(config.PORT.VGA_DAC_DATA)
	local dacG = bus:portRead(config.PORT.VGA_DAC_DATA)
	local dacB = bus:portRead(config.PORT.VGA_DAC_DATA)

	local glyph = bus:memRead(textBase)
	local attr = bus:memRead(textBase + 1)
	local col, row = gpu:getCursor()

	gpu:biosSetVideoMode(0x13)
	bus:memWrite(graphicsBase, 0x12)
	bus:memWrite(graphicsBase + 1, 0x34)
	local gfx0 = bus:memRead(graphicsBase)
	local gfx1 = bus:memRead(graphicsBase + 1)

	bus:memWrite(textBase, savedText0)
	bus:memWrite(textBase + 1, savedText1)
	bus:memWrite(graphicsBase, savedGraphics0)
	bus:memWrite(graphicsBase + 1, savedGraphics1)
	bus:portWrite(config.PORT.VGA_CRTC_INDEX, 0x0C)
	bus:portWrite(config.PORT.VGA_CRTC_DATA, crtc.startHi)
	bus:portWrite(config.PORT.VGA_CRTC_INDEX, 0x0D)
	bus:portWrite(config.PORT.VGA_CRTC_DATA, crtc.startLo)
	bus:portWrite(config.PORT.VGA_CRTC_INDEX, 0x0E)
	bus:portWrite(config.PORT.VGA_CRTC_DATA, crtc.hi)
	bus:portWrite(config.PORT.VGA_CRTC_INDEX, 0x0F)
	bus:portWrite(config.PORT.VGA_CRTC_DATA, crtc.lo)
	gpu._biosMode = crtc.mode
	gpu._miscOutput = crtc.misc
	gpu._crtcIndex = crtc.index
	gpu._attrIndex = crtc.attrIndex
	gpu._attrFlipFlop = crtc.attrFlipFlop
	gpu._dacMask = crtc.dacMask
	gpu._dacReadIndex = crtc.dacReadIndex
	gpu._dacWriteIndex = crtc.dacWriteIndex
	gpu._dacReadComponent = crtc.dacReadComponent
	gpu._dacWriteComponent = crtc.dacWriteComponent
	gpu._sequencer = deepCopy(savedSeq)
	gpu._graphics = deepCopy(savedGraphics)
	gpu._attribute = deepCopy(savedAttr)
	gpu._dac = deepCopy(savedDac)
	restoreStats(gpu, gpuStats)
	restoreStats(bus, busStats)

	local passed = glyph == string.byte("Z")
		and attr == 0x1E
		and col == 5
		and row == 0
		and dacR == 0x3F
		and dacG == 0x00
		and dacB == 0x00
		and gfx0 == 0x12
		and gfx1 == 0x34
	return passed,
		string.format(
			"char=%s attr=%s cursor=%d,%d dac=%s/%s/%s gfx=%s,%s",
			formatHex(glyph),
			formatHex(attr),
			col or -1,
			row or -1,
			formatHex(dacR),
			formatHex(dacG),
			formatHex(dacB),
			formatHex(gfx0),
			formatHex(gfx1)
		)
end

local function testVGAFontPlane(machine, config)
	local bus = machine.bus
	local gpu = machine.gpu
	local graphicsBase = (config.X86 or {}).VIDEO_BASE or config.VRAM_BASE or 0xA0000
	local busStats = copyStats(bus)
	local gpuStats = copyStats(gpu)
	local savedGraphics = deepCopy(gpu._graphics)
	local savedSeq = deepCopy(gpu._sequencer)
	local targetChar = 65
	local targetOffset = targetChar * 32
	local original = {}

	for row = 0, 15 do
		bus:portWrite(config.PORT.VGA_SEQ_INDEX, 0x02)
		bus:portWrite(config.PORT.VGA_SEQ_DATA, 0x04)
		bus:portWrite(config.PORT.VGA_GC_INDEX, 0x06)
		bus:portWrite(config.PORT.VGA_GC_DATA, 0x00)
		bus:portWrite(config.PORT.VGA_GC_INDEX, 0x04)
		bus:portWrite(config.PORT.VGA_GC_DATA, 0x02)
		original[row] = bus:memRead(graphicsBase + targetOffset + row)
	end

	for row = 0, 15 do
		bus:memWrite(graphicsBase + targetOffset + row, (row % 2 == 0) and 0x18 or 0x3C)
	end

	local uploaded = {}
	for row = 0, 15 do
		uploaded[row] = bus:memRead(graphicsBase + targetOffset + row)
	end

	for row = 0, 15 do
		bus:memWrite(graphicsBase + targetOffset + row, original[row] or 0)
	end

	gpu._graphics = deepCopy(savedGraphics)
	gpu._sequencer = deepCopy(savedSeq)
	restoreStats(gpu, gpuStats)
	restoreStats(bus, busStats)

	local passed = true
	for row = 0, 15 do
		local expected = (row % 2 == 0) and 0x18 or 0x3C
		if uploaded[row] ~= expected then
			passed = false
			break
		end
	end
	return passed,
		string.format("font_plane_char=%d row0=%s row1=%s", targetChar, formatHex(uploaded[0]), formatHex(uploaded[1]))
end

local function testVGAPlanar(machine, config)
	local bus = machine.bus
	local gpu = machine.gpu
	local graphicsBase = (config.X86 or {}).VIDEO_BASE or config.VRAM_BASE or 0xA0000
	local busStats = copyStats(bus)
	local gpuStats = copyStats(gpu)
	local savedGraphics = deepCopy(gpu._graphics)
	local savedSeq = deepCopy(gpu._sequencer)

	gpu:biosSetVideoMode(0x0D)
	bus:portWrite(config.PORT.VGA_SEQ_INDEX, 0x02)
	bus:portWrite(config.PORT.VGA_SEQ_DATA, 0x0F)
	bus:portWrite(config.PORT.VGA_GC_INDEX, 0x08)
	bus:portWrite(config.PORT.VGA_GC_DATA, 0xFF)
	bus:portWrite(config.PORT.VGA_GC_INDEX, 0x03)
	bus:portWrite(config.PORT.VGA_GC_DATA, 0x00)
	bus:portWrite(config.PORT.VGA_GC_INDEX, 0x05)
	bus:portWrite(config.PORT.VGA_GC_DATA, 0x00)
	bus:memWrite(graphicsBase, 0xA5)

	bus:portWrite(config.PORT.VGA_GC_INDEX, 0x04)
	bus:portWrite(config.PORT.VGA_GC_DATA, 0x00)
	local plane0 = bus:memRead(graphicsBase)

	bus:portWrite(config.PORT.VGA_GC_INDEX, 0x05)
	bus:portWrite(config.PORT.VGA_GC_DATA, 0x01)
	bus:memWrite(graphicsBase, 0x00)
	bus:portWrite(config.PORT.VGA_GC_INDEX, 0x05)
	bus:portWrite(config.PORT.VGA_GC_DATA, 0x00)
	local plane0AfterMode1 = bus:memRead(graphicsBase)

	bus:portWrite(config.PORT.VGA_GC_INDEX, 0x00)
	bus:portWrite(config.PORT.VGA_GC_DATA, 0x0F)
	bus:portWrite(config.PORT.VGA_GC_INDEX, 0x01)
	bus:portWrite(config.PORT.VGA_GC_DATA, 0x0F)
	bus:portWrite(config.PORT.VGA_GC_INDEX, 0x08)
	bus:portWrite(config.PORT.VGA_GC_DATA, 0xF0)
	bus:portWrite(config.PORT.VGA_GC_INDEX, 0x05)
	bus:portWrite(config.PORT.VGA_GC_DATA, 0x00)
	bus:memWrite(graphicsBase, 0x00)
	local setResetPlane0 = bus:memRead(graphicsBase)

	gpu._graphics = deepCopy(savedGraphics)
	gpu._sequencer = deepCopy(savedSeq)
	restoreStats(gpu, gpuStats)
	restoreStats(bus, busStats)

	local passed = plane0 == 0xA5 and plane0AfterMode1 == 0xA5 and setResetPlane0 == 0xF5
	return passed,
		string.format(
			"plane0=%s mode1=%s setreset=%s",
			formatHex(plane0),
			formatHex(plane0AfterMode1),
			formatHex(setResetPlane0)
		)
end

local function testVGATiming(machine, _config)
	local gpu = machine.gpu
	local bus = machine.bus
	local gpuStats = copyStats(gpu)
	local elapsed = gpu._timing.elapsed
	local sawDisplay = false
	local sawRetrace = false

	for _ = 1, 256 do
		gpu:tick((gpu._timing.frameTime or (1 / 70)) / 256)
		local status = bus:portRead(machine.config.PORT.VGA_INPUT_STATUS1)
		if bit32.band(status, 0x08) ~= 0 then
			sawRetrace = true
		end
		if bit32.band(status, 0x01) == 0 then
			sawDisplay = true
		end
	end

	gpu._timing.elapsed = elapsed
	gpu:tick(0)
	restoreStats(gpu, gpuStats)

	return sawDisplay and sawRetrace,
		string.format(
			"display_enable=%s vertical_retrace=%s line=%d column=%d",
			tostring(sawDisplay),
			tostring(sawRetrace),
			gpu._timing.currentLine or -1,
			gpu._timing.currentColumn or -1
		)
end

local function testKeyboard(machine, config)
	local bus = machine.bus
	local keyboard = machine.keyboard
	local picSnapshot = snapshotPIC(bus.pic)
	local busStats = copyStats(bus)
	local keyboardStats = copyStats(keyboard)
	local snapshot = {
		buffer = deepCopy(keyboard._buffer),
		ascii = deepCopy(keyboard._ascii),
		shift = keyboard._shift,
		ctrl = keyboard._ctrl,
		alt = keyboard._alt,
		capsLock = keyboard._capsLock,
		enabled = keyboard._enabled,
		scanningEnabled = keyboard._scanningEnabled,
		controllerCommandByte = keyboard._controllerCommandByte,
		pendingControllerData = keyboard._pendingControllerData,
		pendingKeyboardData = keyboard._pendingKeyboardData,
		status = keyboard._status,
	}

	bus:portWrite(config.PORT.KBD_STATUS, 0xAA)
	local selfTest = bus:portRead(config.PORT.KBD_DATA)
	bus:portWrite(config.PORT.KBD_DATA, 0xF2)
	local ack = bus:portRead(config.PORT.KBD_DATA)
	local identA = bus:portRead(config.PORT.KBD_DATA)
	local identB = bus:portRead(config.PORT.KBD_DATA)

	keyboard._buffer = deepCopy(snapshot.buffer)
	keyboard._ascii = deepCopy(snapshot.ascii)
	keyboard._shift = snapshot.shift
	keyboard._ctrl = snapshot.ctrl
	keyboard._alt = snapshot.alt
	keyboard._capsLock = snapshot.capsLock
	keyboard._enabled = snapshot.enabled
	keyboard._scanningEnabled = snapshot.scanningEnabled
	keyboard._controllerCommandByte = snapshot.controllerCommandByte
	keyboard._pendingControllerData = snapshot.pendingControllerData
	keyboard._pendingKeyboardData = snapshot.pendingKeyboardData
	keyboard._status = snapshot.status
	restoreStats(keyboard, keyboardStats)
	restorePIC(bus.pic, picSnapshot)
	restoreStats(bus, busStats)

	local passed = selfTest == 0x55 and ack == 0xFA and identA == 0xAB and identB == 0x83
	return passed,
		string.format(
			"selftest=%s ack=%s ident=%s,%s",
			formatHex(selfTest),
			formatHex(ack),
			formatHex(identA),
			formatHex(identB)
		)
end

local function testRTC(machine, config)
	local bus = machine.bus
	local rtc = machine.rtc
	local busStats = copyStats(bus)
	local rtcStats = copyStats(rtc)
	local previousIndex = rtc._index
	local previousNmi = rtc._nmiMasked

	bus:portWrite(config.PORT.RTC_INDEX, 0x0B)
	local statusB = bus:portRead(config.PORT.RTC_DATA)
	local binaryMode = bit32.band(statusB, 0x04) ~= 0
	bus:portWrite(config.PORT.RTC_INDEX, 0x00)
	local sec = decodeRTCValue(bus:portRead(config.PORT.RTC_DATA), binaryMode)
	bus:portWrite(config.PORT.RTC_INDEX, 0x02)
	local min = decodeRTCValue(bus:portRead(config.PORT.RTC_DATA), binaryMode)
	bus:portWrite(config.PORT.RTC_INDEX, 0x04)
	local hour = decodeRTCValue(bus:portRead(config.PORT.RTC_DATA), binaryMode)

	rtc._index = previousIndex
	rtc._nmiMasked = previousNmi
	restoreStats(rtc, rtcStats)
	restoreStats(bus, busStats)

	local passed = bit32.band(statusB, 0x02) ~= 0
		and sec >= 0
		and sec < 60
		and min >= 0
		and min < 60
		and hour >= 0
		and hour < 24
	return passed, string.format("time=%02d:%02d:%02d statusB=%s", hour, min, sec, formatHex(statusB))
end

local function testSerial(machine, config)
	local bus = machine.bus
	local serial = machine.serial
	local busStats = copyStats(bus)
	local serialStats = copyStats(serial)
	local snapshot = {
		divisor = serial._divisor,
		ier = serial._ier,
		iir = serial._iir,
		fcr = serial._fcr,
		lcr = serial._lcr,
		mcr = serial._mcr,
		lsr = serial._lsr,
		msr = serial._msr,
		scr = serial._scr,
		rxFifo = deepCopy(serial._rxFifo),
		txLog = deepCopy(serial._txLog),
		irqPending = serial._irqPending,
	}

	local base = config.PORT.COM1_BASE
	bus:portWrite(base + 4, 0x10)
	bus:portWrite(base + 0, string.byte("A"))
	local lsr = bus:portRead(base + 5)
	local echoed = bus:portRead(base + 0)

	serial._divisor = snapshot.divisor
	serial._ier = snapshot.ier
	serial._iir = snapshot.iir
	serial._fcr = snapshot.fcr
	serial._lcr = snapshot.lcr
	serial._mcr = snapshot.mcr
	serial._lsr = snapshot.lsr
	serial._msr = snapshot.msr
	serial._scr = snapshot.scr
	serial._rxFifo = deepCopy(snapshot.rxFifo)
	serial._txLog = deepCopy(snapshot.txLog)
	serial._irqPending = snapshot.irqPending
	restoreStats(serial, serialStats)
	restoreStats(bus, busStats)

	local passed = bit32.band(lsr, 0x01) ~= 0 and echoed == string.byte("A")
	return passed, string.format("lsr=%s echoed=%s", formatHex(lsr), formatHex(echoed))
end

local function testIDE(machine, config)
	local bus = machine.bus
	local hdd = machine.hdd
	local picSnapshot = snapshotPIC(bus.pic)
	local busStats = copyStats(bus)
	local hddStats = copyStats(hdd)
	local snapshot = {
		status = hdd._status,
		error = hdd._error,
		features = hdd._features,
		sectorCount = hdd._sectorCount,
		sectorNumber = hdd._sectorNumber,
		cylinderLow = hdd._cylinderLow,
		cylinderHigh = hdd._cylinderHigh,
		driveHead = hdd._driveHead,
		deviceControl = hdd._deviceControl,
		ioBuffer = deepCopy(hdd._ioBuffer),
		transfer = deepCopy(hdd._transfer),
		pending = deepCopy(hdd._pending),
		headPos = hdd._headPos,
		activity = hdd._activity,
	}

	local base = config.PORT.IDE_PRIMARY_CMD
	bus:portWrite(base + 6, 0xE0)
	bus:portWrite(base + 7, 0xEC)
	hdd:tick(0.01)
	local status = bus:portRead(base + 7)
	local word0 = bus:portRead16(base + 0)

	hdd._status = snapshot.status
	hdd._error = snapshot.error
	hdd._features = snapshot.features
	hdd._sectorCount = snapshot.sectorCount
	hdd._sectorNumber = snapshot.sectorNumber
	hdd._cylinderLow = snapshot.cylinderLow
	hdd._cylinderHigh = snapshot.cylinderHigh
	hdd._driveHead = snapshot.driveHead
	hdd._deviceControl = snapshot.deviceControl
	hdd._ioBuffer = deepCopy(snapshot.ioBuffer)
	hdd._transfer = deepCopy(snapshot.transfer)
	hdd._pending = deepCopy(snapshot.pending)
	hdd._headPos = snapshot.headPos
	hdd._activity = snapshot.activity
	restoreStats(hdd, hddStats)
	restorePIC(bus.pic, picSnapshot)
	restoreStats(bus, busStats)

	local passed = bit32.band(status, 0x01) == 0 and bit32.band(status, 0x08) ~= 0 and word0 == 0x0040
	return passed, string.format("status=%s identify_word0=%s", formatHex(status), formatHex(word0, 4))
end

local function testProtectedMode(machine, config)
	return ProtectedModeSelfTest.run(machine, config)
end

local function testCpuProtectedModeValidation(machine, config)
	return runGuestValidationImage(machine, config, "CpuProtectedModeValidation", "cpu pm validation PASS")
end

local function testCpuExceptionValidation(machine, config)
	return runGuestValidationImage(machine, config, "CpuExceptionValidation", "cpu exception validation PASS")
end

local function summarizeResults(results)
	local passedCount = 0
	for _, result in ipairs(results) do
		if result.passed then
			passedCount = passedCount + 1
		end
	end

	return {
		passed = passedCount == #results,
		passedCount = passedCount,
		totalCount = #results,
		results = results,
	}
end

function HardwareDiagnostics.run(machine, config)
	local results = {
		wrapTest("pic", function()
			return testPIC(machine, config)
		end),
		wrapTest("pit", function()
			return testPIT(machine, config)
		end),
		wrapTest("vga", function()
			return testVGA(machine, config)
		end),
		wrapTest("vga_font_plane", function()
			return testVGAFontPlane(machine, config)
		end),
		wrapTest("vga_planar_modes", function()
			return testVGAPlanar(machine, config)
		end),
		wrapTest("vga_timing", function()
			return testVGATiming(machine, config)
		end),
		wrapTest("keyboard", function()
			return testKeyboard(machine, config)
		end),
		wrapTest("rtc", function()
			return testRTC(machine, config)
		end),
		wrapTest("serial", function()
			return testSerial(machine, config)
		end),
		wrapTest("ide", function()
			return testIDE(machine, config)
		end),
		wrapTest("protected_mode_smoke", function()
			return testProtectedMode(machine, config)
		end),
	}

	return summarizeResults(results)
end

function HardwareDiagnostics.runGuestCPUValidations(machine, config)
	return summarizeResults({
		wrapTest("cpu_pm_validation", function()
			return testCpuProtectedModeValidation(machine, config)
		end),
		wrapTest("cpu_exception_validation", function()
			return testCpuExceptionValidation(machine, config)
		end),
	})
end

function HardwareDiagnostics.runReviewSuite(machine, config)
	local base = HardwareDiagnostics.run(machine, config)
	local cpu = HardwareDiagnostics.runGuestCPUValidations(machine, config)
	local results = {}
	for _, result in ipairs(base.results) do
		results[#results + 1] = result
	end
	for _, result in ipairs(cpu.results) do
		results[#results + 1] = result
	end
	return summarizeResults(results)
end

return HardwareDiagnostics
