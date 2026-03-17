---
name: systems-emulation
description: Build, debug, refactor, and explain emulated computer systems, hardware models, operating systems, kernels, boot pipelines, and low-level software stacks. Use when Codex needs to work on CPU/device emulation, buses, memory models, firmware, bootloaders, kernels, syscalls, filesystems, schedulers, or userland/runtime layers in a virtual machine or OS-style project.
---

# Systems Emulation

Start by locating the layer being changed: hardware device, interconnect, firmware, bootloader, kernel subsystem, syscall boundary, filesystem, runtime controller, or userland program. Avoid mixing responsibilities across layers unless the request explicitly requires an interface change.

Model execution flow before editing. Trace how control moves from power-on to firmware, bootloader, kernel, and userland, and note which modules own state transitions at each step.

Preserve clear contracts between layers:

- Hardware exposes registers, interrupts, buffers, or memory-mapped behavior.
- Firmware performs early checks and boot preparation.
- Bootloaders validate context and hand off control.
- Kernels own scheduling, memory, syscalls, and fault handling.
- Userland consumes kernel services rather than mutating kernel state directly.

Prefer deterministic emulation rules over ad hoc behavior. Define what each component stores, what inputs it accepts, what outputs or side effects it produces, and when it advances state.

Separate mechanism from policy. Keep low-level primitives generic and put higher-level decisions in the layer that should own them.

When debugging, reduce the failure to a path through the stack:

1. Identify the first incorrect observable behavior.
2. Trace backward to the owning layer.
3. Check state initialization, handoff assumptions, and invariants.
4. Inspect interfaces between adjacent layers before rewriting internals.
5. Apply the smallest coherent fix and re-check neighboring stages.

When creating new subsystems, define these explicitly:

- State and lifecycle.
- Public interface and callers.
- Error and reset behavior.
- Timing or tick model.
- Persistence or serialization rules, if any.

Favor inspectable state and explicit transitions. Hidden coupling between hardware, kernel, and userland makes emulators and OS projects hard to reason about.

Use the references selectively:

- For general system-building heuristics and debugging workflow, read [references/emulation-workflows.md](references/emulation-workflows.md).
- For architecture expectations in this repository, read [references/nova-systems.md](references/nova-systems.md).

When answering or implementing, describe behavior in terms of ownership, state transitions, interfaces, and invariants rather than generic high-level summaries.
