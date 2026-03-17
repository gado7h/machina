# Nova Project Reference

Use this reference when working in this repository.

## Tooling

- `rokit.toml` manages `rojo`, `selene`, `luau-lsp`, and `StyLua`.
- `default.project.json` maps `src/machine` to `ReplicatedStorage/Machine`.
- `default.project.json` maps `src/server` to `ServerScriptService/NovaServer`.

## Project Shape

- `src/machine/Main.client.luau` is the client entry point and boot surface.
- `src/server/Main.server.luau` is the server bootstrap.
- `src/machine/hardware/` owns hardware emulation.
- `src/machine/software/` owns runtime orchestration.
- `src/machine/firmware/` and `src/machine/bootloader/` own startup flow.
- `src/machine/kernel/` owns kernel subsystems.
- `src/machine/userland/` owns shell and first-process logic.
- `src/machine/pkgmgr/` owns package management.
- `src/machine/LuauVM/` owns compiler and VM-backed execution support.
- `src/server/ServerScriptService/network/` owns remotes and sync services.
- `src/server/ServerScriptService/datastore/` owns persistence.

## Working Rules

- Preserve the staged boot flow: firmware to bootloader to kernel to userland.
- Keep DataStore access server-side.
- Treat networking modules as security-sensitive.
- Be careful with changes that affect the virtual machine lifecycle, memory model, or save format.
