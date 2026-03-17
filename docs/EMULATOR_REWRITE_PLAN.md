# Emulator Rewrite Plan

## Goal

Turn Nova from a host-driven virtual computer simulation into a system-accurate custom emulator where:

- the CPU is the execution substrate for firmware and native guest code
- devices are accessed through MMIO or port I/O instead of direct host shortcuts
- firmware, bootloader, and kernel interact through machine-visible state
- higher layers depend on lower layers the way a real computer would

This rewrite targets system accuracy rather than cycle accuracy. Correct boundaries, faults, interrupts, boot flow, and device contracts matter more than exact per-cycle timing.

## Target Machine

### CPU

- Architecture: `nova32`
- Endianness: little-endian
- Register file: 16 architectural registers already modeled by the project
- Core execution model: fetch -> decode -> execute on machine memory
- Privilege levels: supervisor and user
- Required CPU state:
  - general-purpose registers
  - `PC`, `SP`, `FLAGS`
  - control registers for paging/interrupt table
  - current privilege level
  - halted state
  - pending exception state

### Memory Map

The current layout is close enough to preserve while tightening semantics:

- ROM: `0x00000000` - `0x0000FFFF`
- RAM: `0x00010000` - `0x0080FFFF`
- VRAM: `0x00810000` - `0x0084FFFF`
- MMIO window: `0x00F00000` - `0x00F0FFFF`

Planned MMIO subregions:

- interrupt controller registers
- timer registers
- disk controller registers
- GPU control registers
- keyboard controller registers

Rules:

- ROM is read-only
- unmapped reads return fault conditions, not silent success
- invalid writes to protected regions are ignored or faulted consistently
- device state changes occur through mapped registers or ports

### Interrupts and Exceptions

- Hardware IRQ lines are asserted by devices and latched by an interrupt controller
- CPU acknowledges interrupts only when interrupts are enabled
- Exceptions are synchronous CPU events

Required exceptions:

- divide by zero
- invalid opcode
- invalid memory access
- privilege fault
- page fault when paging is enabled

Required IRQ sources:

- timer
- keyboard
- disk completion

### Devices

- Bus: address decoding, port I/O, MMIO routing, device ticking
- Interrupt controller: pending IRQ tracking, masking, priority selection, acknowledge path
- Timer: programmable interval, countdown/tick, IRQ generation
- Disk controller: sector commands, busy/ready state, data window, completion IRQ
- GPU: text/framebuffer memory plus mode/control registers
- Keyboard controller: scancode FIFO, status register, IRQ on key events

### Boot Chain

1. Power-on resets CPU and devices
2. CPU starts at ROM reset vector
3. Firmware runs from ROM and performs hardware initialization through machine interfaces
4. Firmware selects a boot device and loads boot code from disk into RAM
5. Bootloader loads a kernel image and boot info into guest-visible memory
6. Control is transferred by setting machine-visible state and jumping to an entry point
7. Kernel initializes interrupts, memory, drivers, scheduler, and userland

The host runtime may still instantiate machine objects, but it should not directly invoke kernel logic as the primary execution path.

## Execution Model

Nova should support two guest execution modes:

### Native Guest Execution

Used for:

- firmware
- bootloader
- kernel entry
- driver-facing low-level code
- diagnostics and monitor tooling

Requirement:

- loaded binaries or ROM routines execute through `CPU:step`

### Managed Guest Runtime

Used for:

- higher-level applications
- shell scripting
- package ecosystem

Requirement:

- the managed runtime is a guest-visible subsystem, not the machine itself
- the kernel launches it like any other guest program/runtime
- managed programs use syscalls or kernel APIs, not direct host object references

## Architecture Corrections

### Current problems to remove

- runtime directly calls `Kernel:kmain` from the host
- shell executes guest code directly in host Luau with broad machine access
- bus IRQ dispatch is immediate callback execution rather than latched interrupt delivery
- boot artifacts like `kernel.bin` exist, but loaded bytes are not the real execution substrate

### New boundaries

- CPU knows instructions, faults, and interrupt entry only
- bus knows address decoding and device routing only
- devices expose registers, FIFOs, status, and time-based progress
- firmware and bootloader use only CPU-visible and bus-visible interfaces
- kernel uses drivers and controller interfaces rather than direct device internals
- managed runtimes are optional guest subsystems layered above the kernel

## Migration Phases

### Phase 1: Machine contracts

- formalize the MMIO map in `Config.luau`
- add interrupt controller and timer devices
- make bus/device ticking explicit
- tighten CPU fault and interrupt semantics

### Phase 2: Honest boot path

- move hardware init and boot data handoff into firmware/bootloader behavior
- stop treating the kernel image as a placeholder artifact
- make `RuntimeController` coordinate machine startup instead of directly standing in for guest execution

### Phase 3: Kernel boundary cleanup

- isolate kernel/device interactions behind driver-style interfaces
- replace direct machine shortcuts where practical
- keep the current kernel while reducing architectural cheating

### Phase 4: Guest runtime split

- reframe `LuauVM` as a guest runtime
- make shell-launched programs go through a loader/runtime boundary
- keep host-assisted execution only where explicitly documented as transitional

### Phase 5: Validation

- instruction semantics tests
- interrupt delivery tests
- MMIO behavior tests
- boot chain trace logging
- device state inspection and debug dumps

## Definition Of Done

The rewrite is on the right track when all of the following are true:

- firmware and bootloader advance the machine without directly invoking the kernel as host code
- timer, keyboard, and disk interrupts are delivered through a real pending IRQ path
- disk access is controller-driven rather than direct filesystem magic
- managed runtimes are clearly guest subsystems, not the machine execution substrate
- emulator claims in docs match what the code actually does

## Immediate Work In This Pass

- introduce interrupt-controller and timer infrastructure
- strengthen CPU interrupt/fault handling
- improve disk controller semantics and MMIO contracts
- make motherboard and runtime boot flow more hardware-driven
- document the new target architecture so later passes converge
