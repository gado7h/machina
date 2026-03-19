local ProtectedModeSelfTest = require(script.Parent.ProtectedModeSelfTest)

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
	local base = (config.X86 and config.X86.VIDEO_BASE) or config.VRAM_BASE or 0xB8000
	local busStats = copyStats(bus)
	local gpuStats = copyStats(gpu)
	local saved0 = bus:memRead(base)
	local saved1 = bus:memRead(base + 1)
	local crtc = {
		index = gpu._crtcIndex,
		hi = gpu._crtc[0x0E] or 0,
		lo = gpu._crtc[0x0F] or 0,
		startHi = gpu._crtc[0x0C] or 0,
		startLo = gpu._crtc[0x0D] or 0,
		cursorCol = gpu._cursorCol,
		cursorRow = gpu._cursorRow,
	}

	bus:memWrite(base, string.byte("Z"))
	bus:memWrite(base + 1, 0x1E)
	bus:portWrite(config.PORT.VGA_CRTC_INDEX, 0x0F)
	bus:portWrite(config.PORT.VGA_CRTC_DATA, 0x05)
	bus:portWrite(config.PORT.VGA_CRTC_INDEX, 0x0E)
	bus:portWrite(config.PORT.VGA_CRTC_DATA, 0x00)

	local glyph = bus:memRead(base)
	local attr = bus:memRead(base + 1)
	local col, row = gpu:getCursor()

	bus:memWrite(base, saved0)
	bus:memWrite(base + 1, saved1)
	bus:portWrite(config.PORT.VGA_CRTC_INDEX, 0x0C)
	bus:portWrite(config.PORT.VGA_CRTC_DATA, crtc.startHi)
	bus:portWrite(config.PORT.VGA_CRTC_INDEX, 0x0D)
	bus:portWrite(config.PORT.VGA_CRTC_DATA, crtc.startLo)
	bus:portWrite(config.PORT.VGA_CRTC_INDEX, 0x0E)
	bus:portWrite(config.PORT.VGA_CRTC_DATA, crtc.hi)
	bus:portWrite(config.PORT.VGA_CRTC_INDEX, 0x0F)
	bus:portWrite(config.PORT.VGA_CRTC_DATA, crtc.lo)
	gpu._crtcIndex = crtc.index
	gpu._cursorCol = crtc.cursorCol
	gpu._cursorRow = crtc.cursorRow
	restoreStats(gpu, gpuStats)
	restoreStats(bus, busStats)

	local passed = glyph == string.byte("Z") and attr == 0x1E and col == 5 and row == 0
	return passed, string.format("char=%s attr=%s cursor=%d,%d", formatHex(glyph), formatHex(attr), col or -1, row or -1)
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
	return passed, string.format(
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

	local passed = bit32.band(statusB, 0x02) ~= 0 and sec >= 0 and sec < 60 and min >= 0 and min < 60 and hour >= 0 and hour < 24
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

return HardwareDiagnostics
