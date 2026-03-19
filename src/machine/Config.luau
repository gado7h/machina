-- Config module

local Config = {}

--  CPU
Config.CPU_CLOCK_HZ = 20 -- simulated ticks/second (Roblox-safe)
Config.CPU_ARCH = "nova32"
Config.CPU_CORES = 4
Config.CPU_THREADS = 4
Config.CPU_MODEL = "NovaCPU-X1"
Config.CPU_REGISTERS = { -- general-purpose register names
	"R0",
	"R1",
	"R2",
	"R3",
	"R4",
	"R5",
	"R6",
	"R7",
	"PC",
	"SP",
	"LR",
	"FLAGS",
	"CR0",
	"CR3",
	"IDTR",
	"TR",
}
Config.CPU_PIPELINE_STAGES = {
	"IF",
	"ID",
	"RF",
	"EX",
	"MA",
	"WB", -- Fetch Decode RegFetch Execute MemAccess Writeback
}

--  Memory (all sizes in bytes)
Config.ROM_BASE = 0x00000000
Config.ROM_SIZE = 0x00010000 -- 64 KB  firmware image
Config.RAM_BASE = 0x00010000
Config.RAM_SIZE = 0x00800000 -- 8 MB   physical RAM
Config.VRAM_BASE = 0x00810000
Config.VRAM_SIZE = 0x00040000 -- 256 KB video RAM  (320×200 × 4 B)
Config.MMIO_BASE = 0x00F00000 -- memory-mapped I/O window
Config.MMIO_SIZE = 0x00001000
Config.KERNEL_LOAD_ADDR = 0x00100000 -- kernel loaded here by bootloader
Config.USER_SPACE_BASE = 0x00200000 -- user processes start here
Config.USER_SPACE_TOP = 0x00800000
Config.PAGE_SIZE = 4096 -- 4 KB pages
Config.MAX_PAGES = math.floor(0x00800000 / 4096)
Config.BUS_STRICT_MMIO = true

Config.MMIO = {
	HDD_BASE = Config.MMIO_BASE + 0x0000,
	HDD_SIZE = 0x0400,
	TIMER_BASE = Config.MMIO_BASE + 0x0400,
	TIMER_SIZE = 0x40,
	PIC_BASE = Config.MMIO_BASE + 0x0440,
	PIC_SIZE = 0x40,
}

--  Display
Config.DISPLAY_REFRESH_HZ = 60 -- target display presentation rate
Config.SCREEN_W = 320 -- VGA mode 13h width
Config.SCREEN_H = 200 -- VGA mode 13h height
Config.TEXT_COLS = 80
Config.TEXT_ROWS = 25

Config.CHAR_W = 6
Config.CHAR_H = 10

Config.GLYPH_W = 4
Config.GLYPH_H = 8
Config.PAD_X = 1
Config.PAD_Y = 1
-- Disable smoothing by default to keep terminal text crisp/pixel-perfect.
Config.FONT_SMOOTHING = false

--  Storage
Config.DISK_BLOCK_SIZE = 512 -- bytes per sector
Config.DISK_BLOCKS = 204800 -- ~100 MB
Config.DISK_MODEL = "Nova Virtual ATA"
Config.DISK_BUS = "sata"
Config.FS_MAGIC = "NOVAFS1"

--  Scheduler
Config.SCHED_QUANTUM_MS = 50 -- ms per time slice (Roblox heartbeat granularity)
Config.MAX_PROCESSES = 64
Config.MAX_PRIORITY = 39 -- Linux-like nice range -20..+19 mapped 0..39

--  IRQ Lines
Config.IRQ = {
	TIMER = 0,
	KEYBOARD = 1,
	COM1 = 4,
	DISK = 6,
	RTC = 8,
	MOUSE = 12,
	FPU = 13,
	ATA = 14,
}

Config.PIC_VECTOR_BASE_MASTER = 0x20
Config.PIC_VECTOR_BASE_SLAVE = 0x28

Config.EXCEPTION = {
	DIVIDE_BY_ZERO = 0x00,
	BUS_FAULT = 0x0D,
	ILLEGAL_OPCODE = 0x06,
}

Config.TIMER = {
	BASE_HZ = 1193182,
	DEFAULT_DIVISOR = 65536, -- ~18.2Hz
	MIN_INTERVAL_SEC = 1 / 1000,
}

--  I/O Ports (virtual)
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
	VGA_SEQ_INDEX = 0x03C4,
	VGA_CRTC_INDEX = 0x03D4,
	VGA_CRTC_DATA = 0x03D5,
	COM1_BASE = 0x03F8,
	IDE_PRIMARY_CMD = 0x01F0,
	IDE_PRIMARY_CTRL = 0x03F6,
	PCI_CONFIG_ADDR = 0x0CF8,
	PCI_CONFIG_DATA = 0x0CFC,
}

--  PCI Device IDs
Config.PCI = {
	{ bus = 0, dev = 0, fn = 0, vendor = 0x8086, device = 0x1237, class = "Host Bridge", subclass = "PCI" },
	{ bus = 0, dev = 1, fn = 0, vendor = 0x8086, device = 0x7000, class = "ISA Bridge", subclass = "PCI-ISA" },
	{ bus = 0, dev = 2, fn = 0, vendor = 0x1234, device = 0x1111, class = "Display", subclass = "VGA" },
	{ bus = 0, dev = 3, fn = 0, vendor = 0x1AF4, device = 0x1001, class = "Mass Storage", subclass = "SCSI" },
	{ bus = 0, dev = 4, fn = 0, vendor = 0x1AF4, device = 0x1000, class = "Network", subclass = "Ethernet" },
}

--  Kernel version string
Config.OS_NAME = "NovaOS"
Config.KERNEL_VERSION = "1.0.0-nova"
Config.ARCH = "nova32"
Config.HOSTNAME = "novamachine"

--  Networking
Config.NET = {
	HOST_IFACE = "eth0",
	LOOPBACK = "lo",
	DEFAULT_IP = "192.168.1.100",
	DEFAULT_GW = "192.168.1.1",
	DEFAULT_MASK = "255.255.255.0",
	DNS = { "1.1.1.1", "8.8.8.8" },
}

--  Platform personality
Config.PLATFORM = {
	KERNEL_ABI = "posix-like",
	FAMILY = "unix",
	COMPAT = { "linux", "macos", "windows-nt-userland" },
}

Config.VM = {
	ENABLED = false,
	PRAGMA = "--!vm",
	EXTENSION = ".luau",
	NATIVE_PRAGMA = "--!native",
	DEFAULT_BACKEND = "cpu-managed",
	CPU_BACKEND = "luauvm-cpu",
	MANAGED_RUNTIME = "luauvm",
	ALLOW_HOST_FALLBACK = true,
	STRICT_CPU_BACKEND = false,
	TRACE_GUEST_EXECUTION = false,
}

Config.NATIVE = {
	EXTENSION = ".nxe",
	MAGIC = "NVX1",
	VERSION = 1,
	HEADER_SIZE = 32,
	DEFAULT_LOAD_ADDRESS = Config.USER_SPACE_BASE,
	DEFAULT_STACK_ADDRESS = Config.USER_SPACE_TOP - 4,
	MAX_IMAGE_SIZE = 0x00010000,
	MAX_STEPS = 8192,
	EXIT_REGISTER = "R1",
	STDOUT_PORT = Config.PORT.COM1_BASE,
	SYSCALL_VECTOR = 0x80,
	BACKEND = "nova32-native",
}

Config.EMULATION = {
	PROFILE = "x86-bios",
	LEGACY_PROFILE = "nova-legacy",
}

Config.X86 = {
	MACHINE = "ibm-pc-real-mode",
	HEARTBEAT_HZ = Config.DISPLAY_REFRESH_HZ,
	BOOT_CYCLES_PER_TICK = 1536,
	RUN_CYCLES_PER_TICK = 1024,
	ROM_BASE = 0x000F0000,
	ROM_SIZE = 0x00010000,
	LOW_RAM_BASE = 0x00000000,
	LOW_RAM_SIZE = 0x000A0000,
	VIDEO_BASE = 0x000B8000,
	VIDEO_SIZE = 0x8000,
	RESET_VECTOR_SEG = 0xF000,
	RESET_VECTOR_OFF = 0xFFF0,
	BIOS_ENTRY_OFFSET = 0x0100,
	BOOT_SECTOR_LOAD_SEG = 0x0000,
	BOOT_SECTOR_LOAD_OFF = 0x7C00,
	KERNEL_LOAD_SEG = 0x1000,
	KERNEL_LOAD_OFF = 0x0000,
	SUPERBLOCK_BUFFER_OFFSET = 0x4000,
	ROOT_DIRECTORY_BUFFER_OFFSET = 0x4200,
	PROGRAM_STAGE_OFFSET = 0x5000,
	PROGRAM_LOAD_OFFSET = 0x8000,
	SHELL_LOAD_OFFSET = 0x9000,
	PROGRAM_STACK_OFFSET = 0xFFFE,
	DIRECTORY_BUFFER_OFFSET = 0x7000,
	COMMAND_BUFFER_OFFSET = 0x7200,
	COMMAND_TAIL_OFFSET = 0x7280,
	LINE_BUFFER_SIZE = 96,
	FS_MAGIC = "NXFS",
	FS_VERSION = 1,
	FS_ENTRY_SIZE = 32,
	FILE_NAME_SIZE = 11,
	EXEC_MAGIC = "NX16",
	EXEC_VERSION = 1,
	EXEC_HEADER_SIZE = 32,
	SECTORS_PER_TRACK = 18,
	HEADS = 1,
	BOOT_DRIVE = 0x80,
	PIC_VECTOR_BASE_MASTER = 0x08,
	PIC_VECTOR_BASE_SLAVE = 0x70,
	IMAGE = {
		SOURCE = "imported",
		IMPORT_IMAGE = "ProtectedModeBringUp",
		RAW_IMAGE = "ProtectedModeBringUp",
		PROVIDER = "ProtectedModeBringUp",
	},
	DIAGNOSTICS = {
		ENABLED = true,
		PRINT_SUMMARY = true,
	},
}

return Config
