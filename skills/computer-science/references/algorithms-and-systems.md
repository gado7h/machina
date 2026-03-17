# Algorithms And Systems

Use this reference for algorithmic analysis and core systems reasoning.

## Algorithms

- Match the problem shape to common patterns: hashing, sorting, two pointers, sliding window, divide and conquer, dynamic programming, graph traversal, greedy choice, or backtracking.
- Prefer the simplest data structure that supports the required operations efficiently.
- Be explicit about preprocessing costs versus per-query costs.
- Check worst-case behavior, not just average-case intuition.

## Correctness

- Identify the invariant, monotonic property, exchange argument, or induction step that makes the approach valid.
- Check empty input, minimal input, duplicates, overflow, and invalid-state transitions where relevant.

## Complexity

- State time and space complexity separately.
- Tie complexity claims to the dominant operations and data structure behavior.
- Mention amortized analysis only when it materially affects the answer.

## Systems Concepts

- Distinguish interface, implementation, state, and side effects.
- Be clear about concurrency, synchronization, persistence, caching, and fault handling when they matter.
- Prefer precise terminology over overloaded words like "fast" or "efficient."
