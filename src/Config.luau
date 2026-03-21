--Central configuration for the Machina x86 PC emulator.
--PcSystem reads this directly. buildBoardConfig() merges Config.X86 fields
--on top of the defaults below, so X86 values always take precedence.

local Config = {}

Config.EMULATION = {
	PROFILE = "x86-bios",
}

Config.DISPLAY_REFRESH_HZ = 60

Config.SCREEN_W = 320
Config.SCREEN_H = 200
Config.TEXT_COLS = 80
Config.TEXT_ROWS = 25

Config.CHAR_W = 6
Config.CHAR_H = 10
Config.GLYPH_W = 4
Config.GLYPH_H = 8
Config.PAD_X = 1
Config.PAD_Y = 1
Config.FONT_SMOOTHING = false

--Storage
Config.DISK_BLOCKS = 204800
Config.DISK_MODEL = "Machina Virtual ATA"

--Memory layout defaults
--These are fallbacks only. Config.X86 overrides all of them at runtime
--via buildBoardConfig(), so edit Config.X86 for actual values.
Config.PAGE_SIZE = 4096

Config.ROM_BASE = 0x000F0000
Config.ROM_SIZE = 0x00010000

Config.RAM_BASE = 0x00000000
Config.RAM_SIZE = 0x000A0000

Config.VRAM_BASE = 0x000B8000
Config.VRAM_SIZE = 0x00008000

--Interrupt controller
--Defaults before the BIOS programs the PIC. X86 overrides these to the
--real BIOS values (master 0x08 / slave 0x70).
Config.PIC_VECTOR_BASE_MASTER = 0x20
Config.PIC_VECTOR_BASE_SLAVE = 0x28

Config.IRQ = {
	TIMER = 0,
	KEYBOARD = 1,
	COM1 = 4,
	RTC = 8,
	ATA = 14,
}

Config.TIMER = {
	BASE_HZ = 1193182,
	DEFAULT_DIVISOR = 65536,
}

--I/O port
Config.PORT = {
	PIC_MASTER_CMD = 0x0020,
	PIC_MASTER_DATA = 0x0021,
	PIC_SLAVE_CMD = 0x00A0,
	PIC_SLAVE_DATA = 0x00A1,

	PIT_CHAN0 = 0x0040,
	PIT_CMD = 0x0043,

	KBD_DATA = 0x0060,
	KBD_STATUS = 0x0064,

	RTC_INDEX = 0x0070,
	RTC_DATA = 0x0071,

	VGA_MISC_WRITE = 0x03C2,
	VGA_CRTC_INDEX = 0x03D4,
	VGA_CRTC_DATA = 0x03D5,

	COM1_BASE = 0x03F8,

	IDE_PRIMARY_CMD = 0x01F0,
	IDE_PRIMARY_CTRL = 0x03F6,
}

--x86 BIOS subsystem
Config.X86 = {
	HEARTBEAT_HZ = Config.DISPLAY_REFRESH_HZ,
	BOOT_CYCLES_PER_TICK = 1536,
	RUN_CYCLES_PER_TICK = 1024,

	ROM_BASE = 0x000F0000,
	ROM_SIZE = 0x00010000,

	LOW_RAM_BASE = 0x00000000,
	LOW_RAM_SIZE = 0x000A0000,

	VIDEO_BASE = 0x000B8000,
	VIDEO_SIZE = 0x00008000,

	RESET_VECTOR_SEG = 0xF000,
	RESET_VECTOR_OFF = 0xFFF0,
	BIOS_ENTRY_OFFSET = 0x0100,

	BOOT_DRIVE = 0x80,
	BOOT_SECTOR_LOAD_SEG = 0x0000,
	BOOT_SECTOR_LOAD_OFF = 0x7C00,
	KERNEL_LOAD_SEG = 0x1000,
	KERNEL_LOAD_OFF = 0x0000,

	SECTORS_PER_TRACK = 18,
	HEADS = 1,

	PIC_VECTOR_BASE_MASTER = 0x08,
	PIC_VECTOR_BASE_SLAVE = 0x70,

	IMAGE = {
		SOURCE = "imported",
		IMPORT_IMAGE = "ProtectedModeBringUp",
	},

	DIAGNOSTICS = {
		ENABLED = true,
		PRINT_SUMMARY = true,
	},
}

return Config
