# CPU80386 Checklist

## Scope

This checklist tracks the active CPU target for Machina's locked baseline machine.

The CPU target is:

- `80386`-class core
- real-mode reset and BIOS boot
- protected-mode entry and ring-`0` execution
- descriptor-table and interrupt behavior needed by the locked machine

This checklist is **not** a claim of full universal `80386` compatibility.

## Target Boundaries

### Included

- real-mode execution needed for BIOS boot
- `16`-bit and `32`-bit operand-size behavior used by the platform
- `16`-bit and `32`-bit address-size behavior used by the platform
- near and far control transfers used by the platform
- GDT / IDT loading and use
- protected-mode interrupt and exception entry for the locked target
- ring-`0` stack behavior

### Not Included In The Locked Target

- paging
- V86 mode
- task switching / TSS task gates
- call gates
- ring transitions between privilege levels
- user-mode process ABI

Privilege behavior in Machina's current target is therefore intentionally narrow: protected-mode ring-`0` correctness matters, but full privilege-ring switching is not part of the acceptance bar yet.

## Instruction / Behavior Checklist

### Reset / Real Mode

- [ ] reset vector execution at `F000:FFF0`
- [ ] real-mode segment:offset translation
- [ ] BIOS boot path runs without host-side shortcuts

### Operand / Address Size

- [x] default operand size follows current code-segment default
- [x] `0x66` operand-size override flips between `16` and `32`
- [x] default address size follows current code-segment default
- [x] `0x67` address-size override flips between `16` and `32`
- [x] `32`-bit ModRM + SIB addressing works for supported forms
- [x] `16`-bit addressing still works inside default-`32` code when overridden

### Core Data Movement

- [x] `MOV r, imm`
- [x] `MOV r/m, r`
- [x] `MOV r, r/m`
- [x] `MOV segment, r/m16`
- [x] `MOV r/m16, segment`
- [x] `PUSH` / `POP`

### Arithmetic / Logic

- [x] `ADD`
- [x] `SUB`
- [x] `CMP`
- [x] `XOR`
- [x] flags update correctly for implemented widths

### Control Transfer

- [x] near `CALL`
- [x] near `JMP`
- [x] near `RET`
- [x] far immediate `CALL`
- [x] far immediate `JMP`
- [x] far indirect `CALL` (memory far pointer forms)
- [x] far indirect `JMP` (memory far pointer forms)
- [x] `RETF`
- [x] `IRET`

### Protected Mode

- [x] `LGDT`
- [x] `LIDT`
- [x] `LMSW`
- [x] protected-mode segment loading through GDT descriptors for the locked ring-`0` target
- [x] descriptor present / basic code-data type validation
- [x] code-segment default-size behavior

### Interrupts / Exceptions

- [x] software interrupt dispatch through IDT
- [ ] hardware interrupt dispatch through IDT
- [ ] interrupt vs trap gate IF behavior
- [x] invalid opcode exception path for unsupported opcodes
- [x] stack frame shape matches the implemented ring-`0` gate width

## Guest-Visible CPU Self-Tests

Bundled guest-visible CPU validation images:

- `CpuProtectedModeValidation`
- `CpuExceptionValidation`

Headless diagnostic result names:

- `cpu_pm_validation`
- `cpu_exception_validation`

Review-only entry points:

- `HardwareDiagnostics.runGuestCPUValidations(machine, config)`
- `HardwareDiagnostics.runReviewSuite(machine, config)`

These guest CPU validations do **not** run during normal boot diagnostics. They are review-only because they step full guest images and can stall Roblox Studio if they are kept on the synchronous boot path.

### CpuProtectedModeValidation

Intended to verify:

- protected-mode entry
- `32`-bit operand behavior
- `16`-bit operand override inside default-`32` code
- `32`-bit addressing
- `16`-bit address override inside default-`32` code
- near call / return
- far jump
- far call / far return
- software interrupt through IDT

Expected visible result:

- `cpu pm validation PASS`

Diagnostics evidence:

- `cpu_pm_validation`

### CpuExceptionValidation

Intended to verify:

- IDT installation
- invalid-opcode exception dispatch
- exception handler stack-frame handling with `IRET`
- software interrupt dispatch

Expected visible result:

- `cpu exception validation PASS`

Diagnostics evidence:

- `cpu_exception_validation`

## Pass / Fail Acceptance

### Pass

The CPU subsystem passes the current phase when:

- the bundled guest-visible CPU validation images boot and show their pass strings
- the review-only CPU validation suite reports passing `cpu_pm_validation` and `cpu_exception_validation` results
- protected-mode bring-up no longer depends on fake host control-flow shortcuts
- operand-size and address-size behavior match the locked machine contract for the implemented instruction set
- far control transfers and interrupt returns behave consistently in protected mode

### Fail

The CPU subsystem fails the current phase when:

- bootable CPU validation images report a visible failure string
- protected-mode code still depends on incomplete far-control-transfer behavior
- invalid opcodes crash the emulator instead of entering the modeled exception path
- address-size or operand-size handling corrupts guest-visible execution

## Notes

- This checklist is intentionally narrower than a complete `80386` manual.
- New CPU work should be tied either to the locked target machine or to a documented future target revision.
