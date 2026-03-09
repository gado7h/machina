# Nova Architecture

## Boot Pipeline

1. `Main.client.luau` creates the display surface and machine instance.
2. `firmware/BIOS.luau` runs POST and hardware checks.
3. `bootloader/Bootloader.luau` loads kernel image/boot data.
4. `kernel/Kernel.luau` initializes core subsystems.
5. `userland/Init.luau` starts shell and user workflows.

## Layers

### Hardware Layer

`hardware/*` emulates machine devices and data transport:

- `Bus` coordinates memory-mapped/port I/O and IRQ flow.
- `CPU` executes machine instructions and timing.
- `RAM` and `ROM` provide volatile/non-volatile memory.
- `HDD` stores disk sectors and filesystem data.
- `GPU` manages pixel output to the Roblox screen surface.
- `Keyboard` converts Roblox input to scancodes.

### Firmware + Boot

- `BIOS` handles startup diagnostics.
- `Bootloader` validates boot context and hands control to kernel.

### Kernel Layer

- `MemoryManager` controls page allocation and mapping.
- `ProcessManager` tracks process lifecycle and scheduling.
- `VFS` provides filesystem primitives.
- `Syscall` is the user/kernel API boundary.
- `Kernel` coordinates initialization, ticks, panic/reboot paths.

### Userland + Packages

- `Init` performs first-process startup tasks.
- `Shell` implements command loop/UI interactions.
- `PackageManager` and `PackageDB` track and resolve installed packages.

### LuauVM

`LuauVM/*` bundles compiler/runtime support for executing compiled Luau payloads.

## Data Flow Summary

- Input: Roblox keyboard events -> keyboard device -> IRQ/syscall path.
- Compute: scheduler selects runnable process -> syscall/kernel services.
- Storage: VFS operations -> HDD sector/block updates.
- Output: kernel/userland text/video writes -> GPU framebuffer -> GUI image.
