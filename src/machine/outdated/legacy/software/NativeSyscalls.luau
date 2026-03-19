local NativeSyscalls = {}

NativeSyscalls.VECTOR = 0x80

NativeSyscalls.SYS = {
	ECHO = 1,
	CAT = 2,
	PWD = 3,
	MKDIR = 4,
	RM = 5,
	CP = 6,
	MV = 7,
	TOUCH = 8,
	LS = 9,
	PS = 10,
	DATE = 11,
	CLEAR = 12,
	TRUE = 13,
	FALSE = 14,
	SLEEP = 15,
	UNAME = 16,
	WHOAMI = 17,
	ID = 18,
	HOSTNAME = 19,
	UPTIME = 20,
	FREE = 21,
	DF = 22,
	ENV = 23,
	WC = 24,
	GREP = 25,
	HEAD = 26,
	TAIL = 27,
	SYSINFO = 28,
	DMESG = 29,
	LSPCI = 30,
	LSBLK = 31,
	MOUNT = 32,
}

NativeSyscalls.NAME_TO_ID = {}
for name, id in pairs(NativeSyscalls.SYS) do
	NativeSyscalls.NAME_TO_ID[name] = id
end

return NativeSyscalls
