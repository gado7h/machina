# machina-roblox Template

This template describes the intended role of `machina-roblox`.

## Owns

- Roblox host/runtime code
- Rojo project files
- Studio workflows
- Roblox UI and presentation
- remotes, persistence, and networking adapters

## Vendors

- `vendor/machina/**` from the `machina-roblox` archive inside the tagged Machina bundle artifact

## Import Workflow

- Download the tagged `machina-bundles-<version>` artifact from Machina CI.
- Use [`import-machina.ps1`](/C:/Users/ahmad/.codex/worktrees/8ee3/Machina/templates/machina-roblox/import-machina.ps1) to verify checksums and refresh `vendor/machina`.

## Does Not Own

- emulator CPU/device logic
- canonical module ID rules
- shared machine contracts
