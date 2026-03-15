# Module Documentation

## Entry Points

- `src/machine/Main.client.luau`
  - Creates UI screen and LEDs.
  - Instantiates motherboard + machine services.
  - Starts or reboots machine lifecycle.
- `src/server/Main.server.luau`
  - Server bootstrap and remote/data orchestration.

## Core Machine

- `src/machine/Config.luau`
  - Central constants used across hardware/kernel/userland.

- `src/machine/hardware/Motherboard.luau`
  - Integrates CPU, RAM, ROM, HDD, GPU, bus, keyboard.
  - Owns startup state and stage progression.

## Firmware & Boot

- `src/machine/firmware/BIOS.luau`
  - POST sequence and pre-boot checks.
- `src/machine/bootloader/Bootloader.luau`
  - Loads kernel target and transfers execution.

## Kernel

- `src/machine/kernel/Kernel.luau`
  - Kernel coordinator and lifecycle manager.
- `src/machine/kernel/MemoryManager.luau`
  - Physical/virtual memory abstractions.
- `src/machine/kernel/ProcessManager.luau`
  - PCB state, scheduler queues, process control.
- `src/machine/kernel/Syscall.luau`
  - Numeric syscall dispatch and argument routing.
- `src/machine/kernel/VFS.luau`
  - Filesystem object operations and path handling.

## Userland

- `src/machine/userland/Init.luau`
  - First user process initialization.
- `src/machine/userland/Shell.luau`
  - Command parser and shell commands.

## Package Management

- `src/machine/pkgmgr/PackageManager.luau`
  - Install/remove/resolve package actions.
- `src/machine/pkgmgr/PackageDB.luau`
  - Persistent package index structures.

## LuauVM Runtime

- `src/machine/LuauVM/init.luau` - public VM API (compiler+Base64 backed loader).
- `src/machine/LuauVM/Compiler.luau` - compiler implementation.
- `src/machine/LuauVM/Fiu.luau` - VM execution engine.
- `src/machine/LuauVM/Base64.luau` - bytecode encode/decode helper.


## Server Services

- `src/server/ServerScriptService/network/NetworkService.luau`
  - Creates NovaNet remotes for save/load/sync operations.
- `src/server/ServerScriptService/datastore/HDDStore.luau`
  - Persists virtual HDD snapshots in Roblox DataStore.
