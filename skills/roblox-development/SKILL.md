---
name: roblox-development
description: Build, debug, refactor, and review Roblox projects written in Luau. Use when Codex needs to work on Roblox Studio gameplay code, UI code, client/server boundaries, Rojo project layouts, remotes, DataStore-backed systems, or Luau module architecture, especially in repositories that sync source files into Studio with Rojo.
---

# Roblox Development

Inspect the repository layout before editing. Start with `README.md`, `default.project.json`, `rokit.toml`, and any architecture docs so the Studio tree, tooling, and ownership boundaries are clear.

Use idiomatic Luau and preserve the repository's naming, file placement, and module boundaries. Prefer small modules with explicit responsibilities over large mixed-purpose scripts.

Respect Roblox execution boundaries:

- Keep client-only code in client contexts and server-only code in server contexts.
- Treat remotes as trust boundaries; validate client input on the server.
- Keep persistence and privileged state changes on the server.
- Put shared contracts and pure logic in shared modules when both sides need them.

Follow the existing Rojo mapping instead of inventing new top-level trees. When adding files, place them where `default.project.json` and neighboring modules imply they belong.

Trace call flow before changing behavior. Identify the entry point, the modules it requires, and the side effects on replication, rendering, networking, and persistence.

Prefer incremental changes that preserve playability in Studio. If a request touches rendering, input, remotes, or save data, check for regressions in adjacent systems before finishing.

Use the local toolchain when available:

- Format Luau with StyLua if the repo already uses it.
- Lint with Selene when practical.
- Check Rojo and Rokit config before suggesting workflow changes.

Read only the references you need:

- For repo-specific structure and expectations, read [references/nova-project.md](references/nova-project.md).
- For implementation heuristics and review checklists, read [references/roblox-luau-guide.md](references/roblox-luau-guide.md).

When implementing a change, favor this workflow:

1. Identify the Studio tree location and runtime side.
2. Read the nearest entry point and directly-related modules.
3. Make the smallest coherent edit that solves the request.
4. Verify naming, replication, security, and lifecycle assumptions.
5. Run available formatting or linting tools if feasible, or state clearly if they could not be run.
