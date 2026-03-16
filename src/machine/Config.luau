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
Config.KERNEL_LOAD_ADDR = 0x00100000 -- kernel loaded here by bootloader
Config.USER_SPACE_BASE = 0x00200000 -- user processes start here
Config.USER_SPACE_TOP = 0x00800000
Config.PAGE_SIZE = 4096 -- 4 KB pages
Config.MAX_PAGES = math.floor(0x00800000 / 4096)

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
	COM1 = 3,
	DISK = 6,
	RTC = 8,
	MOUSE = 12,
	FPU = 13,
	ATA = 14,
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

return Config
