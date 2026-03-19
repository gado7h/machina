# ⚙️ Machina

[![Language](https://img.shields.io/badge/language-Luau-00A2FF?style=flat-square)](https://luau-lang.org/)
[![Platform](https://img.shields.io/badge/platform-Roblox-E2231A?style=flat-square)](https://www.roblox.com/)
[![Status](https://img.shields.io/badge/status-active-brightgreen?style=flat-square)]()

Machina is an IBM PC–compatible computer emulator implemented in Luau and running inside Roblox.

The project models a complete system at the hardware level, including CPU execution, memory mapping, system bus communication, and common PC peripherals. It is designed for experimentation, education, and low-level systems exploration within the constraints of the Roblox engine.

The CPU implementation begins with an 8086-compatible core and extends toward 80386 features, including 32-bit registers, descriptor tables, and protected mode support. The current runtime profile targets a BIOS-driven boot process starting from the reset vector (`F000:FFF0`) in real mode.

System components are connected through a simulated bus and include RAM, ROM, VGA, disk controllers, interrupt controllers, timers, and input devices. Memory-mapped I/O and port-mapped I/O are both supported, following conventional PC layouts.

A runtime-assembled BIOS initializes the system, provides interrupt services (video, disk, keyboard, clock), and loads a boot sector into memory. Disk images can be constructed or imported and are used to drive the boot process and kernel loading.

Rendering is handled through a virtual VGA device with text and pixel modes, displayed via Roblox UI primitives. Input is translated into hardware-level keyboard signals, and system state can be observed through a live interface.

MachinaOS is the default environment, providing a minimal operating system layer for interacting with the emulated hardware and experimenting with low-level software.

---

## Hosting

Machina runs inside a Roblox client through a **host script** — a `LocalScript` that sits alongside the Machina module folder and owns both the GUI and the machine lifecycle.

A host is responsible for:

- providing a `ScreenGui` with an `ImageLabel` as the display surface
- attaching an `EditableImage` to that `ImageLabel` as the framebuffer
- creating a `PcSystem` instance with `Config` and the `EditableImage`
- calling `machine:powerOn()` and `machine:bindInput(UserInputService)`
- calling `machine:shutdown()` when the character is removed

### Minimal example

```lua
local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Machina = script.Parent
local Config = require(Machina:WaitForChild("Config"))
local PcSystem = require(Machina.platforms.x86:WaitForChild("PcSystem"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function createEditableImage(imageLabel)
    local editableImage = AssetService:CreateEditableImage({
        Size = Vector2.new(Config.SCREEN_W, Config.SCREEN_H),
    })
    imageLabel.ImageContent = Content.fromObject(editableImage)
    return editableImage
end

local function main()
    local gui = Instance.new("ScreenGui")
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = playerGui

    local imageLabel = Instance.new("ImageLabel")
    imageLabel.Size = UDim2.fromScale(1, 1)
    imageLabel.BackgroundColor3 = Color3.new(0, 0, 0)
    imageLabel.BorderSizePixel = 0
    imageLabel.ScaleType = Enum.ScaleType.Stretch
    imageLabel.ResampleMode = Enum.ResamplerMode.Pixelated
    imageLabel.Parent = gui

    local editableImage = createEditableImage(imageLabel)
    local machine = PcSystem.new(Config, editableImage)
    machine:powerOn()
    machine:bindInput(UserInputService)
end

main()
```

| Field | Type | Purpose |
|---|---|---|
| `imageLabel` | `ImageLabel` | **Required.** The GPU renders pixels here. |
| `offOverlay` | `TextButton` | Shown while the machine is off. Clicking it boots the machine. |
| `rebootButton` | `TextButton` | Calls `machine:reboot()` when activated. |
| `shutdownButton` | `TextButton` | Calls `machine:shutdown()` when activated. |
| `stageDot` | `Frame` | `BackgroundColor3` is set to green, amber, or red based on boot stage. |
| `stageLabel` | `TextLabel` | `Text` is set to the current boot stage string. |

Set `AUTO_POWER = true` at the top of the script to boot immediately on spawn, or `false` to require a manual trigger.

### PcSystem API

```lua
-- Construction
local machine = PcSystem.new(config, editableImage)

-- Lifecycle
machine:powerOn() 
machine:shutdown() 
machine:reboot() 

-- State
machine:isPowered() -- boolean
machine:getBootStage() -- "BIOS" | "RUNNING" | "FAULT" | ...

-- Input
machine:bindInput(UserInputService)

-- Diagnostics
machine:getStats()
-- {
--   bootStage: string,
--   uptime: number,
--   cpuStats: { cycles, instructions },
--   ramStats: { reads, writes },
--   hddStats: { reads, writes },
--   busStats: { irqFired },
--   gpuStats: { flushes },
-- }
```