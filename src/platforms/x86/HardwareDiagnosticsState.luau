local State = {}

function State.deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in pairs(value) do
		out[key] = State.deepCopy(child)
	end
	return out
end

function State.restoreTable(target, snapshot)
	for key in pairs(target) do
		target[key] = nil
	end
	for key, value in pairs(snapshot) do
		target[key] = State.deepCopy(value)
	end
end

function State.copyStats(device)
	return State.deepCopy(device and device.stats or {})
end

function State.restoreStats(device, snapshot)
	if device and device.stats and snapshot then
		State.restoreTable(device.stats, snapshot)
	end
end

function State.assignFields(target, snapshot)
	if not target or not snapshot then
		return
	end
	for key, value in pairs(snapshot) do
		target[key] = State.deepCopy(value)
	end
end

function State.snapshotPIC(pic)
	if not pic then
		return nil
	end
	return {
		master = State.deepCopy(pic.master),
		slave = State.deepCopy(pic.slave),
		stats = State.copyStats(pic),
	}
end

function State.restorePIC(pic, snapshot)
	pic.master = State.deepCopy(snapshot.master)
	pic.slave = State.deepCopy(snapshot.slave)
	State.restoreStats(pic, snapshot.stats)
end

function State.snapshotTimer(timer)
	if not timer then
		return nil
	end
	return {
		_baseHz = timer._baseHz,
		_channels = State.deepCopy(timer._channels),
		_subTicks = timer._subTicks,
		_enabled = timer._enabled,
		_irqEnabled = timer._irqEnabled,
		stats = State.copyStats(timer),
	}
end

function State.restoreTimer(timer, snapshot)
	if not timer or not snapshot then
		return
	end
	timer._baseHz = snapshot._baseHz
	timer._channels = State.deepCopy(snapshot._channels)
	timer._subTicks = snapshot._subTicks
	timer._enabled = snapshot._enabled
	timer._irqEnabled = snapshot._irqEnabled
	State.restoreStats(timer, snapshot.stats)
end

function State.snapshotCpu(cpu)
	if not cpu then
		return nil
	end
	return {
		reg16 = State.deepCopy(cpu.reg16),
		reg32 = State.deepCopy(cpu.reg32),
		seg = State.deepCopy(cpu.seg),
		ip = cpu.ip,
		eip = cpu.eip,
		flags = cpu.flags,
		halted = cpu.halted,
		gdtr = State.deepCopy(cpu.gdtr),
		idtr = State.deepCopy(cpu.idtr),
		cr0 = cpu.cr0,
		protectedMode = cpu.protectedMode,
		segCache = State.deepCopy(cpu.segCache),
		lastError = cpu._lastError,
		lastStep = State.deepCopy(cpu._lastStep),
		stats = State.deepCopy(cpu.stats),
		bios = cpu._bios,
	}
end

function State.restoreCpu(cpu, snapshot)
	if not cpu or not snapshot then
		return
	end
	State.assignFields(cpu.reg16, snapshot.reg16)
	State.assignFields(cpu.reg32, snapshot.reg32)
	State.assignFields(cpu.seg, snapshot.seg)
	cpu.ip = snapshot.ip
	cpu.eip = snapshot.eip
	cpu.flags = snapshot.flags
	cpu.halted = snapshot.halted
	State.assignFields(cpu.gdtr, snapshot.gdtr)
	State.assignFields(cpu.idtr, snapshot.idtr)
	cpu.cr0 = snapshot.cr0
	cpu.protectedMode = snapshot.protectedMode
	State.assignFields(cpu.segCache, snapshot.segCache)
	cpu._lastError = snapshot.lastError
	State.assignFields(cpu._lastStep, snapshot.lastStep)
	State.assignFields(cpu.stats, snapshot.stats)
	cpu:attachBIOS(snapshot.bios)
end

function State.snapshotVga(gpu)
	if not gpu then
		return nil
	end
	return {
		_biosMode = gpu._biosMode,
		_nextFrameTime = gpu._nextFrameTime,
		_frameInterval = gpu._frameInterval,
		_apertureBase = gpu._apertureBase,
		_apertureSize = gpu._apertureSize,
		_textBaseOffset = gpu._textBaseOffset,
		_textByteCount = gpu._textByteCount,
		_textCellCount = gpu._textCellCount,
		_planeSize = gpu._planeSize,
		_crtcIndex = gpu._crtcIndex,
		_crtc = State.deepCopy(gpu._crtc),
		_miscOutput = gpu._miscOutput,
		_status1 = gpu._status1,
		_featureControl = gpu._featureControl,
		_attrFlipFlop = gpu._attrFlipFlop,
		_attrIndex = gpu._attrIndex,
		_seqIndex = gpu._seqIndex,
		_gcIndex = gpu._gcIndex,
		_dacMask = gpu._dacMask,
		_dacReadIndex = gpu._dacReadIndex,
		_dacWriteIndex = gpu._dacWriteIndex,
		_dacReadComponent = gpu._dacReadComponent,
		_dacWriteComponent = gpu._dacWriteComponent,
		_sequencer = State.deepCopy(gpu._sequencer),
		_graphics = State.deepCopy(gpu._graphics),
		_attribute = State.deepCopy(gpu._attribute),
		_dac = State.deepCopy(gpu._dac),
		_textBuf = State.deepCopy(gpu._textBuf),
		_vram = State.deepCopy(gpu._vram),
		_cursorRow = gpu._cursorRow,
		_cursorCol = gpu._cursorCol,
		_cursorVisible = gpu._cursorVisible,
		_lastCursor = State.deepCopy(gpu._lastCursor),
		_dirtyCells = State.deepCopy(gpu._dirtyCells),
		_dirtyCellList = State.deepCopy(gpu._dirtyCellList),
		_hostOverlay = State.deepCopy(gpu._hostOverlay),
		_latch = State.deepCopy(gpu._latch),
		_fontHeight = gpu._fontHeight,
		_timing = State.deepCopy(gpu._timing),
		_dirty = gpu._dirty,
		stats = State.copyStats(gpu),
	}
end

function State.restoreVga(gpu, snapshot)
	if not gpu or not snapshot then
		return
	end
	gpu._biosMode = snapshot._biosMode
	gpu._nextFrameTime = snapshot._nextFrameTime
	gpu._frameInterval = snapshot._frameInterval
	gpu._apertureBase = snapshot._apertureBase
	gpu._apertureSize = snapshot._apertureSize
	gpu._textBaseOffset = snapshot._textBaseOffset
	gpu._textByteCount = snapshot._textByteCount
	gpu._textCellCount = snapshot._textCellCount
	gpu._planeSize = snapshot._planeSize
	gpu._crtcIndex = snapshot._crtcIndex
	State.assignFields(gpu._crtc, snapshot._crtc)
	gpu._miscOutput = snapshot._miscOutput
	gpu._status1 = snapshot._status1
	gpu._featureControl = snapshot._featureControl
	gpu._attrFlipFlop = snapshot._attrFlipFlop
	gpu._attrIndex = snapshot._attrIndex
	gpu._seqIndex = snapshot._seqIndex
	gpu._gcIndex = snapshot._gcIndex
	gpu._dacMask = snapshot._dacMask
	gpu._dacReadIndex = snapshot._dacReadIndex
	gpu._dacWriteIndex = snapshot._dacWriteIndex
	gpu._dacReadComponent = snapshot._dacReadComponent
	gpu._dacWriteComponent = snapshot._dacWriteComponent
	State.assignFields(gpu._sequencer, snapshot._sequencer)
	State.assignFields(gpu._graphics, snapshot._graphics)
	State.assignFields(gpu._attribute, snapshot._attribute)
	State.assignFields(gpu._dac, snapshot._dac)
	State.assignFields(gpu._textBuf, snapshot._textBuf)
	gpu._vram = State.deepCopy(snapshot._vram)
	gpu._cursorRow = snapshot._cursorRow
	gpu._cursorCol = snapshot._cursorCol
	gpu._cursorVisible = snapshot._cursorVisible
	State.assignFields(gpu._lastCursor, snapshot._lastCursor)
	State.assignFields(gpu._dirtyCells, snapshot._dirtyCells)
	State.assignFields(gpu._dirtyCellList, snapshot._dirtyCellList)
	State.assignFields(gpu._hostOverlay, snapshot._hostOverlay)
	State.assignFields(gpu._latch, snapshot._latch)
	gpu._fontHeight = snapshot._fontHeight
	State.assignFields(gpu._timing, snapshot._timing)
	gpu._dirty = snapshot._dirty
	State.restoreStats(gpu, snapshot.stats)
end

function State.snapshotMachine(machine)
	local bus = machine.bus
	local ram = machine.ram
	local rom = machine.rom
	local hdd = machine.hdd
	local gpu = machine.gpu
	return {
		bootStage = machine._bootStage,
		bootRecord = State.deepCopy(machine._bootRecord),
		powered = machine._powered,
		heartbeatGeneration = machine._heartbeatGeneration,
		lastHeartbeatAt = machine._lastHeartbeatAt,
		uptimeStart = machine._uptimeStart,
		cursorTimer = machine._cursorTimer,
		bus = {
			stats = State.copyStats(bus),
			fault = State.deepCopy(bus and bus._fault),
			pic = State.snapshotPIC(bus and bus.pic),
			timer = State.snapshotTimer(bus and bus.timer),
		},
		cpu = State.snapshotCpu(machine.cpu),
		ram = ram and {
			_mem = State.deepCopy(ram._mem),
			_dirty = State.deepCopy(ram._dirty),
			stats = State.copyStats(ram),
		} or nil,
		rom = rom and {
			_data = State.deepCopy(rom._data),
			_locked = rom._locked,
			_unlockSeq = State.deepCopy(rom._unlockSeq),
			_unlockStep = rom._unlockStep,
			stats = State.copyStats(rom),
		} or nil,
		hdd = hdd and {
			_sectors = State.deepCopy(hdd._sectors),
			_mediaPresent = hdd._mediaPresent,
			_activity = hdd._activity,
			_headPos = hdd._headPos,
			_status = hdd._status,
			_error = hdd._error,
			_features = hdd._features,
			_sectorCount = hdd._sectorCount,
			_sectorNumber = hdd._sectorNumber,
			_cylinderLow = hdd._cylinderLow,
			_cylinderHigh = hdd._cylinderHigh,
			_driveHead = hdd._driveHead,
			_deviceControl = hdd._deviceControl,
			_ioBuffer = State.deepCopy(hdd._ioBuffer),
			_transfer = State.deepCopy(hdd._transfer),
			_pending = State.deepCopy(hdd._pending),
			stats = State.copyStats(hdd),
		} or nil,
		gpu = State.snapshotVga(gpu),
	}
end

function State.restoreMachine(machine, snapshot)
	if not snapshot then
		return
	end
	machine._bootStage = snapshot.bootStage
	machine._bootRecord = State.deepCopy(snapshot.bootRecord)
	machine._powered = snapshot.powered
	machine._heartbeatGeneration = snapshot.heartbeatGeneration
	machine._lastHeartbeatAt = snapshot.lastHeartbeatAt
	machine._uptimeStart = snapshot.uptimeStart
	machine._cursorTimer = snapshot.cursorTimer

	if machine.bus and snapshot.bus then
		State.assignFields(machine.bus.stats, snapshot.bus.stats)
		machine.bus._fault = State.deepCopy(snapshot.bus.fault)
		State.restorePIC(machine.bus.pic, snapshot.bus.pic)
		State.restoreTimer(machine.bus.timer, snapshot.bus.timer)
	end

	State.restoreCpu(machine.cpu, snapshot.cpu)

	if machine.ram and snapshot.ram then
		machine.ram._mem = State.deepCopy(snapshot.ram._mem)
		machine.ram._dirty = State.deepCopy(snapshot.ram._dirty)
		State.restoreStats(machine.ram, snapshot.ram.stats)
	end

	if machine.rom and snapshot.rom then
		machine.rom._data = State.deepCopy(snapshot.rom._data)
		machine.rom._locked = snapshot.rom._locked
		machine.rom._unlockSeq = State.deepCopy(snapshot.rom._unlockSeq)
		machine.rom._unlockStep = snapshot.rom._unlockStep
		State.restoreStats(machine.rom, snapshot.rom.stats)
	end

	if machine.hdd and snapshot.hdd then
		machine.hdd._sectors = State.deepCopy(snapshot.hdd._sectors)
		machine.hdd._mediaPresent = snapshot.hdd._mediaPresent
		machine.hdd._activity = snapshot.hdd._activity
		machine.hdd._headPos = snapshot.hdd._headPos
		machine.hdd._status = snapshot.hdd._status
		machine.hdd._error = snapshot.hdd._error
		machine.hdd._features = snapshot.hdd._features
		machine.hdd._sectorCount = snapshot.hdd._sectorCount
		machine.hdd._sectorNumber = snapshot.hdd._sectorNumber
		machine.hdd._cylinderLow = snapshot.hdd._cylinderLow
		machine.hdd._cylinderHigh = snapshot.hdd._cylinderHigh
		machine.hdd._driveHead = snapshot.hdd._driveHead
		machine.hdd._deviceControl = snapshot.hdd._deviceControl
		machine.hdd._ioBuffer = State.deepCopy(snapshot.hdd._ioBuffer)
		machine.hdd._transfer = State.deepCopy(snapshot.hdd._transfer)
		machine.hdd._pending = State.deepCopy(snapshot.hdd._pending)
		State.restoreStats(machine.hdd, snapshot.hdd.stats)
	end

	State.restoreVga(machine.gpu, snapshot.gpu)
end

function State.readTextScreen(machine, config)
	local x86 = config.X86 or {}
	local textBase = x86.TEXT_BUFFER_BASE or 0xB8000
	local textByteCount = x86.TEXT_BUFFER_SIZE or 0x8000
	local chars = {}
	for offset = 0, textByteCount - 2, 2 do
		local ch = (machine.bus and machine.bus.memRead and machine.bus:memRead(textBase + offset)) or 0
		if ch == 0 then
			ch = 32
		end
		chars[#chars + 1] = string.char(ch % 0x100)
	end
	return table.concat(chars)
end

return State
