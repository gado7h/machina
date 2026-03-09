# Nova

Nova is a Roblox-based virtual machine project written in Luau. It emulates a small computer stack including firmware, bootloader, kernel, virtual filesystem, and userland shell.

## Features

- Simulated hardware: CPU, RAM, ROM, bus, HDD, keyboard, and GPU.
- Firmware POST and staged boot flow.
- Kernel subsystems for memory, process management, syscalls, and VFS.
- Basic userland init/shell and package-management modules.
- LuauVM integration for running compiled Luau bytecode.

## Project Layout

- `src/machine/Config.luau` – global machine constants.
- `src/machine/Main.client.luau` – client entry point and GUI boot surface.
- `src/machine/hardware/` – hardware emulation modules.
- `src/machine/firmware/` – BIOS-style firmware startup.
- `src/machine/bootloader/` – stage loader and kernel handoff.
- `src/machine/kernel/` – core OS modules.
- `src/machine/userland/` – init and shell logic.
- `src/machine/pkgmgr/` – package manager and package DB logic.
- `src/machine/LuauVM/` – bundled Luau VM/compiler runtime.

## Development

### Requirements

- [Rokit](https://github.com/rojo-rbx/rokit)
- [Rojo](https://rojo.space/) for Roblox syncing

### Common workflow

1. Install toolchain dependencies (via `rokit` and your local setup).
2. Open the project in Roblox Studio.
3. Sync source with Rojo.
4. Run the game and observe the Nova boot sequence.

## Style

Luau files are aligned to Lua style-guide conventions:

- clear naming and short, relevant comments
- minimal header comments
- consistent spacing and table/function formatting

References:

- https://roblox.github.io/lua-style-guide/
- https://github.com/Olivine-Labs/lua-style-guide

## Documentation

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/MODULES.md`](docs/MODULES.md) for architecture and module-level documentation.
