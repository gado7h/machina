# Roblox Luau Guide

Use this reference for general Roblox implementation decisions.

## Module Placement

- Put rendering, camera, and local input handling on the client.
- Put authority, persistence, matchmaking, and anti-abuse validation on the server.
- Put constants, type definitions, and deterministic shared helpers in shared modules.

## Remote Safety

- Never trust values sent by the client.
- Validate player ownership, range, state, and schema on the server.
- Prefer narrow remote APIs over generic "do everything" payloads.

## Luau Style

- Prefer explicit local names over deep inline expressions.
- Keep tables and module returns simple and discoverable.
- Add short comments only where lifecycle or invariants are not obvious.

## Review Checklist

- Does the code run on the correct side of the client/server boundary?
- Does it preserve replication and initialization order?
- Does it avoid creating server trust on client input?
- Does it fit the existing Rojo tree and module layout?
- Does it keep persistent data access on the server?
