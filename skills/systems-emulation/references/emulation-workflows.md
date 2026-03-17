# Emulation Workflows

Use this reference for emulator, kernel, and low-level software tasks.

## Layering Checklist

- Identify the owning layer before editing behavior.
- Keep hardware state, kernel state, and userland state distinct.
- Validate each handoff point: power-on to firmware, firmware to bootloader, bootloader to kernel, kernel to userland.

## Device Modeling

- Define the device state clearly.
- Define reads, writes, interrupts, and reset behavior.
- Document whether the device is memory-mapped, port-mapped, event-driven, or tick-driven.
- Keep side effects predictable and observable.

## Kernel And OS Workflow

- Define subsystem ownership first: memory, process, files, syscalls, scheduling, drivers.
- Add narrow interfaces between subsystems.
- Favor explicit error paths and panic conditions over silent corruption.
- Check whether a change alters ABI-like contracts with userland.

## Debugging Workflow

- Reproduce the bug at the earliest visible stage.
- Check initialization and default state.
- Trace forward one stage at a time rather than skipping across layers.
- Confirm whether the issue is in mechanism, policy, serialization, or bad assumptions at a boundary.
