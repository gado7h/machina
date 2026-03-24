# machina-web Template

This template describes the intended role of `machina-web`.

## Owns

- browser loader/embedder
- web UI shell
- browser platform adapters
- deployment and packaging

## Vendors

- `vendor/machina/**` from the `machina-luau` archive inside the tagged Machina bundle artifact

## Import Workflow

- Download the tagged `machina-bundles-<version>` artifact from Machina CI.
- Use [`import-machina.ps1`](/C:/Users/ahmad/.codex/worktrees/8ee3/Machina/templates/machina-web/import-machina.ps1) to verify checksums and refresh `vendor/machina`.

## Does Not Own

- emulator CPU/device logic
- canonical module ID rules
- shared machine contracts
