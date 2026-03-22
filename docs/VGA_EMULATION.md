# VGA Coverage

## Target

Machina currently targets a baseline IBM VGA-compatible programming model for text mode, planar graphics modes, and mode `13h`-class chained `256`-color graphics.

The interrupt model follows that target:

- baseline VGA does not expose a standard dedicated IRQ line
- vertical retrace is surfaced through `Input Status 1` polling
- Machina therefore does **not** raise a VGA interrupt in the current machine model

## Acceptance Coverage

| Acceptance area | Status | Notes |
| --- | --- | --- |
| Guest software sees real VGA register surfaces | Partial | Attribute controller, sequencer, graphics controller, CRTC, misc-output, DAC, and `Input Status 1` are exposed through x86 port I/O. |
| BIOS / video code can interact with the adapter | Partial | BIOS mode set and teletype flow through the VGA device, and guest memory writes go through the VGA aperture rather than a host-only text console. |
| Text mode `03h` behavior | Partial | `0xB8000` text memory, cursor registers, blink/background intensity, start-address scrolling, and plane-2 font-backed text rendering are modeled. |
| Mode `13h` behavior | Partial | Chained `320x200x256` byte writes are supported and scan-doubled to the host surface. |
| Planar graphics behavior | Partial | Planar reads, write modes `0-3`, latches, set/reset, read mode `1`, and DAC/palette color resolution are modeled. |
| Plane `2` font upload | Implemented | Guest writes can upload glyph data into plane `2`, and text rendering consumes uploaded font rows. |
| DAC / palette handling | Implemented | DAC read/write index sequencing and palette lookup are supported. |
| Hardware cursor | Implemented | Cursor state is driven from CRTC registers and rendered in text mode. |
| Timing / retrace behavior | Partial | Retrace/display-enable status now derives from CRTC-style timing state instead of a fixed wall-clock bit, but it is not cycle-accurate. |
| VGA interrupt signaling | N/A by target | Baseline VGA IRQ generation is intentionally not modeled because the target hardware contract does not define one. |
| Stronger compatibility validation | Partial | Internal diagnostics now cover text, DAC, font upload, planar modes, and timing state; external compatibility suites are still pending. |

## Implemented Areas

- VGA aperture mapping across `0xA0000-0xBFFFF`
- text memory at `0xB8000`
- sequencer, graphics controller, attribute controller, CRTC, misc-output, DAC, and status-register access
- mode-driven rendering for text, planar graphics, and chained `13h`
- plane-`2` font-backed text rendering
- blink vs. background-intensity text attribute handling
- start-address scrolling and hardware cursor state
- host-only overlay output for emulator faults and diagnostics

## Remaining Gaps

- Full IBM VGA timing is still approximated, not cycle-accurate.
- Plane / odd-even corner cases and font-map selection are narrower than a full hardware implementation.
- No external VGA conformance suite is wired into the repo yet.
- The built-in default font is still a synthesized fallback until overwritten by guest font upload.

## Validation

Current internal diagnostics cover:

- text memory writes at `0xB8000`
- CRTC cursor behavior
- DAC read/write sequencing
- mode `13h` aperture byte access
- plane `2` font upload/readback
- planar write-mode and latch behavior
- timing status transitions across display-enable and retrace windows

Recommended next validation:

- run dedicated VGA register/mode conformance programs
- add explicit font-render regression images
- add planar write-mode reference cases from known VGA test software
