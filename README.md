# Machina

[![Language](https://img.shields.io/badge/language-Luau-00A2FF?style=flat-square)](https://luau-lang.org/)
[![Runtime](https://img.shields.io/badge/runtime-host--neutral-4B5563?style=flat-square)]()
[![Status](https://img.shields.io/badge/status-active-brightgreen?style=flat-square)]()

Machina is a host-neutral IBM PC-compatible emulator core implemented in Luau.

This repo is the shared source of truth for emulator behavior, stable `src/...` module IDs, and host-facing platform contracts. Downstream hosts such as `machina-roblox` and `machina-web` should consume versioned bundle artifacts from tagged Machina workflows instead of depending on repo-local build output.

The emulator models CPU execution, memory mapping, buses, firmware, storage, timers, interrupts, and VGA behavior. The current target remains a BIOS-driven x86 machine starting at reset vector `F000:FFF0`.

The locked emulator target and subsystem acceptance criteria are documented in [`docs/TARGET_MACHINE.md`](docs/TARGET_MACHINE.md). VGA fidelity and current implementation limits are documented in [`docs/VGA_EMULATION.md`](docs/VGA_EMULATION.md).

## Repo Role

This repo owns:

- `src/Config`
- `src/platforms/**`
- `src/platform/**`
- shared package/release tooling
- public contracts for consumer repos

This repo does not own:

- Roblox host/runtime code
- browser embedder/runtime code
- Rojo projects or deployment packaging
- remotes, persistence, UI, or host input adapters

## Public Entry Points

- `src/Config`
- `src/platforms/x86/PcSystem`
- `src/platform/Contracts`

See [`docs/PUBLIC_CONTRACT.md`](docs/PUBLIC_CONTRACT.md) for the full contract.

## Bundle Artifacts

Tagged workflows upload one bundle artifact that contains:

- `machina-luau`: host-neutral Luau package for `machina-web` and other Luau runtimes
- `machina-roblox`: Roblox-ready package with generated Roblox-compatible internal requires
- release metadata and checksums for both archives

Local `dist/**` output is an internal maintainer detail used by CI packaging. Consumer repos should treat the uploaded GitHub Actions artifact from a tagged Machina run as the supported handoff.

## Consumer Repos

- `machina-roblox` should import the `machina-roblox` package from the tagged bundle artifact and own all Roblox-specific runtime wiring.
- `machina-web` should import the `machina-luau` package from the tagged bundle artifact and own the browser loader/embedder.

See:

- [`docs/RELEASE_BUNDLES.md`](docs/RELEASE_BUNDLES.md)
- [`docs/VENDORING.md`](docs/VENDORING.md)
- [`docs/WEB_HOST_CONTRACT.md`](docs/WEB_HOST_CONTRACT.md)
- [`templates/machina-roblox/README.md`](templates/machina-roblox/README.md)
- [`templates/machina-web/README.md`](templates/machina-web/README.md)
