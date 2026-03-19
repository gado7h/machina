# Outdated Code

`outdated/legacy/` contains the previous Nova-specific machine stack that is not part of the current `x86-bios` boot path.

`outdated/x86-generated/` contains the removed generated x86 image path (`DiskImage`, `GuestOS`, `FileSystemImage`, and `ExecutableFormat`) that was replaced by external x86 image providers.

It is kept here for reference and possible reuse, but the active emulator now boots through `platforms/x86/`.
