---
name: computer-science
description: Analyze, explain, design, and solve computer science problems. Use when Codex needs to work on algorithms, data structures, complexity analysis, discrete reasoning, systems concepts, programming paradigms, correctness arguments, or general CS problem-solving in code or prose.
---

# Computer Science

Start by classifying the task: algorithm design, data-structure selection, debugging, complexity analysis, system design, proof/explanation, or implementation. Let that classification drive the depth and format of the response.

Define the problem precisely before solving it. Identify the inputs, outputs, constraints, invariants, edge cases, and success criteria.

Prefer explicit reasoning over intuition-only answers:

- Name the candidate approaches.
- Compare their time and space complexity.
- State the tradeoffs that matter for the given constraints.
- Explain why one approach fits better than the others.

When working on algorithms or data structures, move in this order:

1. Restate the problem in operational terms.
2. Identify the core pattern or reduction.
3. Choose the data structures that support the needed operations.
4. Describe the algorithm clearly before coding.
5. Check complexity, edge cases, and correctness.

When debugging, separate symptom from cause. Reproduce the smallest failing case, inspect assumptions, and determine whether the issue is in the algorithm, implementation, input handling, state transitions, or test expectations.

When explaining a concept, start with the role it plays, then show a small example, then generalize. Prefer one strong example over several shallow ones.

When reviewing solutions, check all three:

- Correctness under normal and edge-case inputs.
- Complexity relative to the problem constraints.
- Clarity and maintainability of the implementation.

Use the references selectively:

- For general workflows and decision patterns, read [references/problem-solving.md](references/problem-solving.md).
- For algorithmic and systems-oriented heuristics, read [references/algorithms-and-systems.md](references/algorithms-and-systems.md).

When the user asks for a proof or justification, state the claim, identify the invariant or argument structure, and keep the reasoning tight and testable.
