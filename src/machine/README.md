# Machine Layout

Active emulator code lives in:

- `Config.luau`
- `Main.client.luau`
- `platforms/x86/` for the active x86 emulator stack:
  `PcSystem`, `Cpu8086`, `Cpu80386`, `BiosInterrupts`, `BiosRom`, `Assembler8086`, `BootImageCatalog`, `BootImageLoader`, `HardwareDiagnostics`, `ProtectedModeSelfTest`, and `BootController`
- `platforms/x86/devices/` for the active x86 machine devices:
  `SystemBus`, `VgaAdapter`, `AtaController`, `Pic8259`, `I8042Controller`, `PhysicalMemory`, `FirmwareRom`, `CmosRtc`, `Uart8250`, and `Pit8254`

Inactive legacy NovaOS code lives in:

- `outdated/legacy/`
- `outdated/x86-generated/`

Those folders keep the previous Nova-specific stack and the removed generated x86 image path out of the active emulator tree.
