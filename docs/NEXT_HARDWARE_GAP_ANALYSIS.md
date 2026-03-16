# `next/*` vs current `src/machine/hardware/*` gap analysis

This compares the new architecture prototypes in `next/` against the currently wired runtime hardware in `src/machine/hardware/` (plus the current bootloader in `src/machine/bootloader`).

## Executive summary

- `next/` models a **more realistic, low-level machine** (MMU/TLB, separate unified memory subsystem with MMIO registration, richer interrupt model, multicore-ready CPU hooks, explicit boot stage stubs).
- `src/machine/hardware/*` models a **teaching/runtime-friendly machine** (clear modules, strong integration with Roblox-facing rendering/input path, simpler bus + component contracts).
- Biggest migration risk is not individual instructions; it is the **contract shift** from `Bus`-centric, port/MMIO-lite devices to the `next` **Memory/MMAP-first** design.

---

## 1) CPU: `next/CPU.luau` vs `src/machine/hardware/CPU.luau`

### `next/CPU.luau` strengths
- Implements a staged core with explicit pipeline latches (`if_latch`, `id_latch`, `ex_latch`, `mem_latch`) and performance counters (`instructions`, `cycles`, cache, tlb, branch metrics).  
- Adds architectural subsystems absent in current CPU: separate I/D caches, TLB, MMU toggle, branch predictor, IRQ mask/pending/in-service style state, syscall/exception callback hooks.  
- Uses buffer-backed register storage and a ROM-origin PC bootstrap path (`pc = MMAP.ROM_BASE`) for lower-level bring-up semantics.

### current `src` CPU strengths
- Simpler and very maintainable instruction model with explicit op table and helper ALU paths.
- Includes user-visible teaching/debug affordances (pipeline stage labels as strings, readable register names, basic cache statistics), easier for UI integration.
- Integrated with current `config` + `bus` flow and reset semantics already used by motherboard and kernel boot chain.

### gap to close
- `next` has deeper architecture realism, but lacks current `src` ergonomics/debug readability.
- Instruction encoding and register conventions are not drop-in compatible, so CPU replacement requires an ISA boundary plan (adapter or dual-mode decoder).

---

## 2) Motherboard: `next/Motherboard.luau` vs `src/machine/hardware/Motherboard.luau`

### `next/Motherboard.luau` strengths
- Boards in explicit controllers as first-class units (PIC, timer/PIT, keyboard MMIO, RNG/UART) and wires them via memory-mapped registrations.
- Designed around per-tick dispatch and system-level interrupt orchestration to CPU core(s).
- Better separation of concerns for hardware IRQ lifecycle (mask, pending, EOI).

### current `src` motherboard strengths
- End-to-end orchestration is already integrated with the existing runtime (power-on stages, module requires, heartbeat lifecycle, boot sequence progression).
- Hooks directly into existing machine stack (Bus, RAM/ROM/HDD/GPU/Keyboard, BIOS/Bootloader/Kernel transitions).
- Lower integration risk for current game/client behavior.

### gap to close
- `next` assumes a memory-centric MMIO fabric, while `src` motherboard assumes existing `Bus` contracts.
- A staged migration should likely begin by introducing a `Memory` facade behind the current board before swapping controllers.

---

## 3) Bootloader: `next/Bootloader.luau` vs `src/machine/bootloader/Bootloader.luau`

### `next/Bootloader.luau` strengths
- Explicit two-stage model (MBR-like stage1 + stage2 handoff) with generated instruction stubs and syscall-mediated kernel loading.
- Clear boot config parser and kernel path selection logic (`/etc/boot.cfg`) with direct PC handoff to kernel entry.
- Better foundation for authentic low-level boot simulation.

### current `src` bootloader strengths
- Robust practical flow: partition parsing, filesystem mount/format fallback, base-system install, boot info writing, and asynchronous stage transitions.
- Better user-facing resilience and first-boot recovery for current product behavior.
- Deeply integrated with existing VFS/kernel/module layout.

### gap to close
- `next` boot path is architecturally cleaner; `src` boot path is operationally richer.
- Recommended blend: keep current filesystem/bootstrap resilience while incrementally moving to `next` stage semantics.

---

## 4) GPU: `next/GPU.luau` vs `src/machine/hardware/GPU.luau`

### `next/GPU.luau` strengths
- GPU is MMIO-aware and aligned to the broader `next` memory-map architecture.
- Built with explicit text/graphics-oriented device behavior suitable for CPU-driven register/VRAM patterns.

### current `src` GPU strengths
- Very complete practical renderer with text buffer, glyph/font tables, dirty-cell tracking, framebuffer path, and editable image integration.
- Strong immediate usability and good performance-minded internals for current UI output.

### gap to close
- The biggest delta is interface contract, not rendering capability: current GPU APIs are tuned for present bus/config semantics.
- Porting should prioritize keeping existing render pipeline behavior while swapping only transport (bus/MMIO interface).

---

## 5) Memory/Storage/Input stack differences (`next/Memory.luau`, `next/HDD.luau` vs `src` RAM/ROM/HDD/Keyboard/Bus)

### `next` direction
- Unified `Memory` object owns ROM/RAM/BDA and MMIO registration/dispatch.
- Address-space enforcement and memory statistics are centralized.
- Device integration assumes global physical map lookups.

### current `src` direction
- Hardware is decomposed into separate modules (`RAM`, `ROM`, `HDD`, `Keyboard`) coordinated by `Bus`.
- Keyboard path and device ports are already wired to current client/runtime input behavior.
- Easier targeted debugging per component, but with more cross-module wiring overhead.

### gap to close
- This is the core architectural mismatch. `next` is map-first; `src` is module-first.
- Migration sequence should introduce compatibility adapters (e.g., Bus-backed MMIO map shim) before replacing devices.

---

## Practical migration recommendation

1. **Create a compatibility layer first**
   - Add a `MemoryBridge` that can satisfy current bus calls while exposing `registerMMIO`/address map semantics.
2. **Port motherboard controllers before CPU internals**
   - PIC/timer/keyboard IRQ model can be adopted incrementally with lower ISA risk.
3. **Keep current bootloader recovery paths**
   - Preserve current partition + filesystem fallback behaviors, then add stage1/stage2 authenticity on top.
4. **Treat CPU ISA migration as a separate milestone**
   - Introduce conformance tests and an instruction compatibility matrix before any default CPU switch.
5. **Preserve current GPU output contract**
   - Move bus transport to MMIO in a wrapper first; avoid changing text/dirty-cell rendering behavior early.

## Suggested decision

- If your goal is **shipping stability now**, continue with `src` hardware and cherry-pick selected `next` subsystems (PIC/timer/MMIO memory model).
- If your goal is **architectural realism and long-term platform evolution**, invest in the bridge layer and migrate in vertical slices (Memory → Motherboard IRQ controllers → Bootloader staging → CPU core).
