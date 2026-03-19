-- Canonical native guest source files seeded into the virtual filesystem.

local NativeSourcePrograms = {}

local SOURCES = {
	["/bin/echo.luau"] = [[
--!native
SYSCALL ECHO
HLT
]],
	["/bin/cat.luau"] = [[
--!native
SYSCALL CAT
HLT
]],
	["/bin/pwd.luau"] = [[
--!native
SYSCALL PWD
HLT
]],
	["/bin/mkdir.luau"] = [[
--!native
SYSCALL MKDIR
HLT
]],
	["/bin/rm.luau"] = [[
--!native
SYSCALL RM
HLT
]],
	["/bin/cp.luau"] = [[
--!native
SYSCALL CP
HLT
]],
	["/bin/mv.luau"] = [[
--!native
SYSCALL MV
HLT
]],
	["/bin/touch.luau"] = [[
--!native
SYSCALL TOUCH
HLT
]],
	["/bin/ls.luau"] = [[
--!native
SYSCALL LS
HLT
]],
	["/bin/ps.luau"] = [[
--!native
SYSCALL PS
HLT
]],
	["/bin/date.luau"] = [[
--!native
SYSCALL DATE
HLT
]],
	["/bin/clear.luau"] = [[
--!native
SYSCALL CLEAR
HLT
]],
	["/bin/true.luau"] = [[
--!native
SYSCALL TRUE
HLT
]],
	["/bin/false.luau"] = [[
--!native
SYSCALL FALSE
HLT
]],
	["/bin/sleep.luau"] = [[
--!native
SYSCALL SLEEP
HLT
]],
	["/bin/uname.luau"] = [[
--!native
SYSCALL UNAME
HLT
]],
	["/bin/whoami.luau"] = [[
--!native
SYSCALL WHOAMI
HLT
]],
	["/bin/id.luau"] = [[
--!native
SYSCALL ID
HLT
]],
	["/bin/hostname.luau"] = [[
--!native
SYSCALL HOSTNAME
HLT
]],
	["/bin/uptime.luau"] = [[
--!native
SYSCALL UPTIME
HLT
]],
	["/bin/free.luau"] = [[
--!native
SYSCALL FREE
HLT
]],
	["/bin/df.luau"] = [[
--!native
SYSCALL DF
HLT
]],
	["/bin/env.luau"] = [[
--!native
SYSCALL ENV
HLT
]],
	["/bin/wc.luau"] = [[
--!native
SYSCALL WC
HLT
]],
	["/bin/grep.luau"] = [[
--!native
SYSCALL GREP
HLT
]],
	["/bin/head.luau"] = [[
--!native
SYSCALL HEAD
HLT
]],
	["/bin/tail.luau"] = [[
--!native
SYSCALL TAIL
HLT
]],
	["/bin/sysinfo.luau"] = [[
--!native
SYSCALL SYSINFO
HLT
]],
	["/bin/dmesg.luau"] = [[
--!native
SYSCALL DMESG
HLT
]],
	["/bin/lspci.luau"] = [[
--!native
SYSCALL LSPCI
HLT
]],
	["/bin/lsblk.luau"] = [[
--!native
SYSCALL LSBLK
HLT
]],
	["/bin/mount.luau"] = [[
--!native
SYSCALL MOUNT
HLT
]],
	["/bin/hello-native.luau"] = [[
--!native
PRINT "hello from native source\n"
EXIT 0
]],
}

function NativeSourcePrograms.materialize()
	local materialized = {}
	for path, source in pairs(SOURCES) do
		materialized[path] = source
	end
	return materialized
end

return NativeSourcePrograms
