# Nova Systems Reference

Use this reference when working in this repository.

## Architecture

- `src/machine/Main.client.luau` creates the display surface and machine instance.
- `src/machine/hardware/Motherboard.luau` wires and powers devices.
- `src/machine/software/RuntimeController.luau` advances boot stages.
- `src/machine/firmware/` owns BIOS-style startup.
- `src/machine/bootloader/` owns kernel handoff.
- `src/machine/kernel/` owns memory, process, syscall, and VFS subsystems.
- `src/machine/userland/` owns init and shell behavior.
- `src/machine/pkgmgr/` owns package management.
- `src/machine/LuauVM/` owns compiler and VM-backed execution support.

## Hardware Expectations

- `hardware/Bus.luau` coordinates I/O and IRQ flow.
- `hardware/CPU.luau`, `RAM.luau`, `ROM.luau`, `HDD.luau`, `GPU.luau`, and `Keyboard.luau` emulate devices.
- Changes to devices should preserve motherboard wiring and runtime assumptions.

## System Rules

- Preserve the staged boot pipeline from BIOS to bootloader to kernel to userland.
- Treat `Syscall.luau` as a contract boundary between kernel and userland.
- Keep persistence and network-backed storage concerns on the server side.
- Be careful with changes that affect save format, memory layout, or VM execution flow.
