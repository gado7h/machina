# Architecture And Logic

Use this reference for digital logic and computer architecture decisions.

## Digital Logic Checklist

- Separate inputs, outputs, internal state, and derived signals.
- Check whether outputs should be Moore-style or Mealy-style.
- Check reset behavior and illegal states.
- Avoid mixing unrelated responsibilities into one state machine.

## Datapath And Control

- Name each register, mux, ALU path, and control signal.
- Verify that every control bit has a clear producer and consumer.
- Check write-enable timing and read-after-write assumptions.
- Prefer simple, inspectable control over clever compact encodings unless constrained.

## ISA And Microarchitecture

- Keep the instruction format, decode path, and execution side effects aligned.
- Document condition flags, traps, memory ordering assumptions, and privilege boundaries.
- Check how loads, stores, branches, and interrupts interact with the pipeline or execution loop.

## Memory Systems

- Distinguish storage capacity, bandwidth, latency, and persistence.
- Define addressing granularity and alignment rules.
- Check coherence/consistency assumptions before discussing shared state.
- Be explicit about caches, page tables, MMIO, DMA, or bus arbitration when they matter.

## Hardware-Software Boundary

- Define which layer initializes hardware and which layer consumes it.
- Expose status, control, and fault paths clearly.
- Favor deterministic interfaces and observable failure modes.
