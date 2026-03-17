# Core Workflows

Use this reference when a task needs a step-by-step engineering approach.

## Problem Framing

- Identify whether the task is analysis, design, debugging, verification, or explanation.
- Identify the target abstraction level.
- Define constraints: correctness, timing, area, power, interface compatibility, tooling, or pedagogy.

## Debugging Workflow

- Reduce the problem to the smallest reproducible failing path.
- Inspect assumptions about reset, initialization, timing, and ownership of state.
- Check whether the issue comes from bad stimulus, wrong decoding, stale state, or unintended coupling.
- Verify that observed outputs match both the written spec and the implied architecture.

## Design Workflow

- Define interfaces first.
- Define state and data movement second.
- Define control sequencing third.
- Add error handling, reset behavior, and observability last.

## Explanation Workflow

- Start with the role of the component in the larger system.
- Show the important signals or state.
- Walk through one representative cycle or event path.
- Call out common failure modes or misconceptions.
