-- Boot protocol shared by firmware, bootloader, and runtime handoff.

local BootProtocol = {}

BootProtocol.BOOTINFO_MAGIC = 0x4E4F5641 -- "NOVA"
BootProtocol.HANDOFF_MAGIC = 0x484E4446 -- "HNDF"
BootProtocol.HANDOFF_VERSION = 1

-- RAM offsets (relative to config.RAM_BASE)
BootProtocol.MEMMAP_BASE = 0x500
BootProtocol.BOOTINFO_BASE = 0x600
BootProtocol.CMDLINE_BASE = 0x700
BootProtocol.HANDOFF_BASE = 0x780
BootProtocol.BOOT_SECTOR_ADDR = 0x7C00

BootProtocol.BI = {
	MAGIC = 0,
	KERNEL_ENTRY = 4,
	KERNEL_SIZE = 8,
	MEM_MAP_PTR = 12,
	MEM_MAP_COUNT = 16,
	BOOT_DRIVE = 20, -- u8
	FLAGS = 21, -- u8
	CMDLINE_PTR = 24,
	BOOT_SECTOR_PTR = 28,
	BOOT_PART_LBA = 32,
	BOOT_PART_SIZE = 36,
}

BootProtocol.HS = {
	MAGIC = 0,
	VERSION = 4,
	STAGE = 8,
	FLAGS = 12,
	BOOTINFO_PTR = 16,
	KERNEL_ENTRY = 20,
	KERNEL_SIZE = 24,
	MEM_MAP_PTR = 28,
	MEM_MAP_COUNT = 32,
	BOOT_DRIVE = 36, -- u8
	BOOT_SECTOR_PTR = 40,
	BOOT_PART_LBA = 44,
	BOOT_PART_SIZE = 48,
	CMDLINE_PTR = 52,
}

BootProtocol.STAGE = {
	RESET = 0,
	FIRMWARE_READY = 1,
	BOOTLOADER_READY = 2,
	KERNEL_READY = 3,
	KERNEL_ENTERED = 4,
}

BootProtocol.FLAG = {
	BOOT_SECTOR_VALID = 0x01,
	BOOTINFO_VALID = 0x02,
	KERNEL_LOADED = 0x04,
}

local function writeCString(ram, offset, text)
	for i = 1, #text do
		ram:memWrite(offset + i - 1, string.byte(text, i))
	end
	ram:memWrite(offset + #text, 0)
end

local function writeU8(ram, offset, value)
	ram:memWrite(offset, (tonumber(value) or 0) % 256)
end

local function readU8(ram, offset)
	return ram:memRead(offset) or 0
end

local function readU32(bus, addr)
	return bus:memRead32(addr) or 0
end

function BootProtocol.writeBootInfo(machine, payload)
	local config = machine.config
	local bus = machine.bus
	local ram = machine.ram
	local bi = BootProtocol.BI

	local base = config.RAM_BASE + BootProtocol.BOOTINFO_BASE
	local baseOff = base - config.RAM_BASE
	local cmdlineOffset = BootProtocol.CMDLINE_BASE
	local cmdline = payload.cmdline or "nova ro quiet"
	local part = payload.partition or {}

	bus:memWrite32(base + bi.MAGIC, BootProtocol.BOOTINFO_MAGIC)
	bus:memWrite32(base + bi.KERNEL_ENTRY, payload.kernelEntry or 0)
	bus:memWrite32(base + bi.KERNEL_SIZE, payload.kernelSize or 0)
	bus:memWrite32(base + bi.MEM_MAP_PTR, config.RAM_BASE + BootProtocol.MEMMAP_BASE)
	bus:memWrite32(base + bi.MEM_MAP_COUNT, payload.memMapCount or 0)
	ram:memWrite(baseOff + bi.BOOT_DRIVE, (payload.bootDrive or 0x80) % 256)
	ram:memWrite(baseOff + bi.FLAGS, (payload.flags or 0) % 256)
	bus:memWrite32(base + bi.CMDLINE_PTR, config.RAM_BASE + cmdlineOffset)
	bus:memWrite32(base + bi.BOOT_SECTOR_PTR, payload.bootSectorAddr or 0)
	bus:memWrite32(base + bi.BOOT_PART_LBA, part.lbaStart or 0)
	bus:memWrite32(base + bi.BOOT_PART_SIZE, part.lbaSize or 0)

	writeCString(ram, cmdlineOffset, cmdline)
	return base
end

function BootProtocol.writeHandoff(machine, payload)
	local config = machine.config
	local bus = machine.bus
	local ram = machine.ram
	local hs = BootProtocol.HS

	local base = config.RAM_BASE + BootProtocol.HANDOFF_BASE
	local prev = BootProtocol.readHandoff(machine)
	local prevFlags = (prev and prev.flags) or 0

	local stage = payload.stage
	if stage == nil then
		stage = (prev and prev.stage) or BootProtocol.STAGE.RESET
	end
	local flags = payload.flags
	if flags == nil then
		flags = prevFlags
	end

	bus:memWrite32(base + hs.MAGIC, BootProtocol.HANDOFF_MAGIC)
	bus:memWrite32(base + hs.VERSION, BootProtocol.HANDOFF_VERSION)
	bus:memWrite32(base + hs.STAGE, stage)
	bus:memWrite32(base + hs.FLAGS, flags)
	bus:memWrite32(base + hs.BOOTINFO_PTR, payload.bootInfoAddr or (prev and prev.bootInfoAddr) or 0)
	bus:memWrite32(base + hs.KERNEL_ENTRY, payload.kernelEntry or (prev and prev.kernelEntry) or 0)
	bus:memWrite32(base + hs.KERNEL_SIZE, payload.kernelSize or (prev and prev.kernelSize) or 0)
	bus:memWrite32(
		base + hs.MEM_MAP_PTR,
		payload.memMapPtr or (prev and prev.memMapPtr) or (config.RAM_BASE + BootProtocol.MEMMAP_BASE)
	)
	bus:memWrite32(base + hs.MEM_MAP_COUNT, payload.memMapCount or (prev and prev.memMapCount) or 0)
	writeU8(ram, BootProtocol.HANDOFF_BASE + hs.BOOT_DRIVE, payload.bootDrive or (prev and prev.bootDrive) or 0x80)
	bus:memWrite32(base + hs.BOOT_SECTOR_PTR, payload.bootSectorAddr or (prev and prev.bootSectorAddr) or 0)
	bus:memWrite32(base + hs.BOOT_PART_LBA, payload.bootPartLba or (prev and prev.bootPartLba) or 0)
	bus:memWrite32(base + hs.BOOT_PART_SIZE, payload.bootPartSize or (prev and prev.bootPartSize) or 0)
	bus:memWrite32(
		base + hs.CMDLINE_PTR,
		payload.cmdlinePtr or (prev and prev.cmdlinePtr) or (config.RAM_BASE + BootProtocol.CMDLINE_BASE)
	)

	return base
end

function BootProtocol.readHandoff(machine)
	local config = machine.config
	local bus = machine.bus
	local ram = machine.ram
	local hs = BootProtocol.HS
	local base = config.RAM_BASE + BootProtocol.HANDOFF_BASE

	local magic = readU32(bus, base + hs.MAGIC)
	if magic ~= BootProtocol.HANDOFF_MAGIC then
		return nil, "bad handoff magic"
	end

	local info = {
		addr = base,
		magic = magic,
		version = readU32(bus, base + hs.VERSION),
		stage = readU32(bus, base + hs.STAGE),
		flags = readU32(bus, base + hs.FLAGS),
		bootInfoAddr = readU32(bus, base + hs.BOOTINFO_PTR),
		kernelEntry = readU32(bus, base + hs.KERNEL_ENTRY),
		kernelSize = readU32(bus, base + hs.KERNEL_SIZE),
		memMapPtr = readU32(bus, base + hs.MEM_MAP_PTR),
		memMapCount = readU32(bus, base + hs.MEM_MAP_COUNT),
		bootDrive = readU8(ram, BootProtocol.HANDOFF_BASE + hs.BOOT_DRIVE),
		bootSectorAddr = readU32(bus, base + hs.BOOT_SECTOR_PTR),
		bootPartLba = readU32(bus, base + hs.BOOT_PART_LBA),
		bootPartSize = readU32(bus, base + hs.BOOT_PART_SIZE),
		cmdlinePtr = readU32(bus, base + hs.CMDLINE_PTR),
	}
	return info
end

function BootProtocol.readBootInfo(machine, addr)
	local config = machine.config
	local bus = machine.bus
	local ram = machine.ram
	local bi = BootProtocol.BI
	local base = addr or (config.RAM_BASE + BootProtocol.BOOTINFO_BASE)
	local baseOff = base - config.RAM_BASE

	local magic = readU32(bus, base + bi.MAGIC)
	if magic ~= BootProtocol.BOOTINFO_MAGIC then
		return nil, "bad bootinfo magic"
	end

	local info = {
		addr = base,
		magic = magic,
		kernelEntry = readU32(bus, base + bi.KERNEL_ENTRY),
		kernelSize = readU32(bus, base + bi.KERNEL_SIZE),
		memMapPtr = readU32(bus, base + bi.MEM_MAP_PTR),
		memMapCount = readU32(bus, base + bi.MEM_MAP_COUNT),
		bootDrive = readU8(ram, baseOff + bi.BOOT_DRIVE),
		flags = readU8(ram, baseOff + bi.FLAGS),
		cmdlinePtr = readU32(bus, base + bi.CMDLINE_PTR),
		bootSectorAddr = readU32(bus, base + bi.BOOT_SECTOR_PTR),
		bootPartLba = readU32(bus, base + bi.BOOT_PART_LBA),
		bootPartSize = readU32(bus, base + bi.BOOT_PART_SIZE),
	}
	return info
end

function BootProtocol.readCpuRegs(machine)
	local cpu = machine.cpu
	if not cpu then
		return nil, "no cpu"
	end

	return {
		pc = cpu:getReg("PC") or 0,
		r1 = cpu:getReg("R1") or 0,
		r2 = cpu:getReg("R2") or 0,
		r3 = cpu:getReg("R3") or 0,
	}
end

local function hasFlag(mask, flag)
	return bit32.band(mask or 0, flag) ~= 0
end

function BootProtocol.readCpuKernelRegs(machine)
	local regs, err = BootProtocol.readCpuRegs(machine)
	if not regs then
		return nil, err
	end
	return {
		pc = regs.pc,
		bootInfoAddr = regs.r1,
		bootDrive = regs.r2,
		bootPartLba = regs.r3,
	}
end

function BootProtocol.readKernelContext(machine)
	local handoff, handoffErr = BootProtocol.readHandoff(machine)
	if not handoff then
		return nil, "handoff unreadable: " .. tostring(handoffErr)
	end
	if handoff.version ~= BootProtocol.HANDOFF_VERSION then
		return nil, "unsupported handoff version: " .. tostring(handoff.version)
	end
	if handoff.stage < BootProtocol.STAGE.KERNEL_READY then
		return nil, "handoff stage not ready: " .. tostring(handoff.stage)
	end
	if not hasFlag(handoff.flags, BootProtocol.FLAG.BOOTINFO_VALID) then
		return nil, "handoff missing BOOTINFO_VALID flag"
	end
	if not hasFlag(handoff.flags, BootProtocol.FLAG.KERNEL_LOADED) then
		return nil, "handoff missing KERNEL_LOADED flag"
	end

	local regs = BootProtocol.readCpuKernelRegs(machine)
	if regs then
		if regs.pc == 0 then
			return nil, "cpu pc not primed for kernel entry"
		end
		if regs.bootInfoAddr == 0 then
			return nil, "cpu r1 missing bootinfo pointer"
		end
		if handoff.bootInfoAddr ~= 0 and regs.bootInfoAddr ~= handoff.bootInfoAddr then
			return nil,
				string.format("cpu r1 mismatch: r1=0x%08X handoff=0x%08X", regs.bootInfoAddr, handoff.bootInfoAddr)
		end
	end

	local bootInfoAddr = handoff.bootInfoAddr
	if regs and regs.bootInfoAddr ~= 0 then
		bootInfoAddr = regs.bootInfoAddr
	end
	if bootInfoAddr == 0 then
		bootInfoAddr = machine.config.RAM_BASE + BootProtocol.BOOTINFO_BASE
	end

	local bootInfo, bootInfoErr = BootProtocol.readBootInfo(machine, bootInfoAddr)
	if not bootInfo then
		return nil, "bootinfo unreadable: " .. tostring(bootInfoErr)
	end
	if not hasFlag(bootInfo.flags, BootProtocol.FLAG.BOOTINFO_VALID) then
		return nil, "bootinfo missing BOOTINFO_VALID flag"
	end
	if not hasFlag(bootInfo.flags, BootProtocol.FLAG.KERNEL_LOADED) then
		return nil, "bootinfo missing KERNEL_LOADED flag"
	end

	local kernelEntry = bootInfo.kernelEntry
	if regs and regs.pc ~= 0 then
		if kernelEntry ~= 0 and regs.pc ~= kernelEntry then
			return nil, string.format("cpu pc mismatch: pc=0x%08X bootinfo=0x%08X", regs.pc, kernelEntry)
		end
		kernelEntry = regs.pc
	end
	if kernelEntry == 0 then
		return nil, "kernel entry is zero"
	end

	local bootDrive = bootInfo.bootDrive
	if regs and regs.bootDrive ~= 0 then
		bootDrive = regs.bootDrive
	end

	return {
		handoff = handoff,
		bootInfo = bootInfo,
		regs = regs,
		kernelEntry = kernelEntry,
		bootDrive = bootDrive,
		bootPartLba = (regs and regs.bootPartLba) or bootInfo.bootPartLba,
	}
end

function BootProtocol.seedCpuForKernel(machine, handoff, bootInfo)
	local cpu = machine.cpu
	if not cpu then
		return false, "no cpu"
	end
	local bootInfoAddr = (bootInfo and bootInfo.addr) or (handoff and handoff.bootInfoAddr)
	local bootDrive = (bootInfo and bootInfo.bootDrive) or (handoff and handoff.bootDrive) or 0x80
	local partLba = (bootInfo and bootInfo.bootPartLba) or (handoff and handoff.bootPartLba) or 0
	local entry = (bootInfo and bootInfo.kernelEntry) or (handoff and handoff.kernelEntry) or 0
	if entry == 0 then
		return false, "missing kernel entry"
	end

	cpu:setReg("PC", entry)
	cpu:setReg("R1", bootInfoAddr or 0)
	cpu:setReg("R2", bootDrive)
	cpu:setReg("R3", partLba)
	return true
end

return BootProtocol
