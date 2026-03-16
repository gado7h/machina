# Nova Architecture

## Boot Pipeline

1. `Main.client.luau` creates the display surface and motherboard instance.
2. `hardware/Motherboard.luau` powers and wires physical devices.
3. `software/RuntimeController.luau` drives BIOS -> bootloader -> kernel transitions.
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


### Software Runtime Layer

`software/*` owns OS bring-up flow and software-only runtime concerns:

- `RuntimeController` advances boot stages (BIOS -> BOOT -> KERNEL -> RUNNING).
- Instantiates firmware/bootloader/kernel modules once hardware is ready.
- Exposes host-side IDE activation against the running kernel runtime.

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
- IDE runtime replaces the former desktop launcher to encourage user-created GUI systems.

### LuauVM

`LuauVM/*` bundles compiler+Base64 runtime support for executing Luau payloads with FiU-backed bytecode execution.

## Data Flow Summary

- Input: Roblox keyboard events -> keyboard device -> IRQ/syscall path.
- Compute: scheduler selects runnable process -> syscall/kernel services.
- Storage: VFS operations -> HDD sector/block updates.
- Output: kernel/userland text/video writes -> GPU framebuffer -> GUI image.


## Server Services

- `Main.server.luau` initializes server-only runtime services.
- Network service provisions remotes for machine state and HDD save/load.
- Datastore service persists HDD snapshots per player key.
