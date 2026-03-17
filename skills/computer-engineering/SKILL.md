---
name: computer-engineering
description: Design, analyze, explain, and debug computer engineering systems. Use when Codex needs to work on digital logic, computer architecture, CPU datapaths, instruction sets, memory hierarchies, buses, firmware-adjacent systems, embedded interfaces, timing tradeoffs, or low-level hardware-software interaction.
---

# Computer Engineering

Start by identifying the abstraction level of the request: logic gate, sequential circuit, datapath/control, ISA, memory subsystem, board-level interface, firmware boundary, or full-system architecture. Solve the problem at the right layer before jumping into implementation details.

Model the system explicitly. Name the important signals, state elements, interfaces, clock domains, storage elements, and invariants before proposing changes or explanations.

Prefer concrete representations over vague prose:

- Use truth tables for logic behavior.
- Use state transition descriptions for sequential systems.
- Use block-level data flow for datapaths and buses.
- Use timing assumptions when discussing synchronization or throughput.
- Use memory maps and access paths when discussing storage subsystems.

Separate combinational behavior from sequential behavior. Distinguish current state, next state, and outputs so race conditions and hidden assumptions are easier to spot.

Trace cause and effect across hardware-software boundaries. When a bug or feature touches firmware, drivers, or low-level code, identify which side owns configuration, which side observes status, and how errors propagate.

Make tradeoffs explicit. For architecture or design questions, compare latency, throughput, area/complexity, power, correctness risk, and debuggability instead of optimizing only one metric.

Prefer incremental reasoning for debugging:

1. State the expected behavior.
2. Identify the smallest failing path or component.
3. Check inputs, control signals, storage updates, and timing assumptions.
4. Isolate whether the issue is specification, design, implementation, or testbench usage.
5. Propose the smallest coherent fix, then re-evaluate adjacent effects.

Use the references selectively:

- For general workflows and checklists, read [references/core-workflows.md](references/core-workflows.md).
- For architecture and digital-design heuristics, read [references/architecture-and-logic.md](references/architecture-and-logic.md).

When producing an answer or implementation, keep the output structured around signals, modules, interfaces, and observed behavior rather than generic summaries.
