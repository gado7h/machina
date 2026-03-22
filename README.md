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

The locked emulator target and subsystem acceptance criteria are documented in [`docs/TARGET_MACHINE.md`](docs/TARGET_MACHINE.md).

CPU behavior coverage and guest-visible CPU validation images are documented in [`docs/CPU80386_CHECKLIST.md`](docs/CPU80386_CHECKLIST.md).

VGA fidelity and current implementation limits are documented in [`docs/VGA_EMULATION.md`](docs/VGA_EMULATION.md).

MachinaOS is the default environment, providing a minimal operating system layer for interacting with the emulated hardware and experimenting with low-level software.

---

## Hosting

Machina runs inside a Roblox client through a **host script**: a `LocalScript` that sits alongside the Machina module folder and owns all Roblox-facing behavior.

The host is the only layer that should interact with Roblox APIs such as:

- `game:GetService(...)`
- `UserInputService`
- `AssetService`
- `EditableImage`
- `Content.fromObject(...)`
- camera, UI, topbar, remotes, and other client-side presentation logic

The emulator core itself is kept separate from Roblox-specific code. Device and platform modules expose a pure machine interface, while the host handles input capture and framebuffer presentation.

A host is responsible for:

- creating a `ScreenGui` and `ImageLabel` to display the machine output
- creating an `EditableImage` and assigning it to the `ImageLabel`
- creating a `PcSystem` instance with `Config`
- registering a frame presenter callback with `machine:setFramePresenter(...)`
- translating Roblox keyboard input into emulator key events with `machine:keyDown(...)` and `machine:keyUp(...)`
- powering the machine on and shutting it down when needed

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

local ROBLOX_KEYCODE_TO_EMU_KEY = {
	[Enum.KeyCode.A] = "A",
	[Enum.KeyCode.B] = "B",
	[Enum.KeyCode.C] = "C",
	[Enum.KeyCode.D] = "D",
	[Enum.KeyCode.E] = "E",
	[Enum.KeyCode.F] = "F",
	[Enum.KeyCode.G] = "G",
	[Enum.KeyCode.H] = "H",
	[Enum.KeyCode.I] = "I",
	[Enum.KeyCode.J] = "J",
	[Enum.KeyCode.K] = "K",
	[Enum.KeyCode.L] = "L",
	[Enum.KeyCode.M] = "M",
	[Enum.KeyCode.N] = "N",
	[Enum.KeyCode.O] = "O",
	[Enum.KeyCode.P] = "P",
	[Enum.KeyCode.Q] = "Q",
	[Enum.KeyCode.R] = "R",
	[Enum.KeyCode.S] = "S",
	[Enum.KeyCode.T] = "T",
	[Enum.KeyCode.U] = "U",
	[Enum.KeyCode.V] = "V",
	[Enum.KeyCode.W] = "W",
	[Enum.KeyCode.X] = "X",
	[Enum.KeyCode.Y] = "Y",
	[Enum.KeyCode.Z] = "Z",

	[Enum.KeyCode.Zero] = "Zero",
	[Enum.KeyCode.One] = "One",
	[Enum.KeyCode.Two] = "Two",
	[Enum.KeyCode.Three] = "Three",
	[Enum.KeyCode.Four] = "Four",
	[Enum.KeyCode.Five] = "Five",
	[Enum.KeyCode.Six] = "Six",
	[Enum.KeyCode.Seven] = "Seven",
	[Enum.KeyCode.Eight] = "Eight",
	[Enum.KeyCode.Nine] = "Nine",

	[Enum.KeyCode.Return] = "Return",
	[Enum.KeyCode.Space] = "Space",
	[Enum.KeyCode.Backspace] = "Backspace",
	[Enum.KeyCode.Tab] = "Tab",
	[Enum.KeyCode.Escape] = "Escape",

	[Enum.KeyCode.LeftShift] = "LeftShift",
	[Enum.KeyCode.RightShift] = "RightShift",
	[Enum.KeyCode.LeftControl] = "LeftControl",
	[Enum.KeyCode.RightControl] = "RightControl",
	[Enum.KeyCode.LeftAlt] = "LeftAlt",
	[Enum.KeyCode.RightAlt] = "RightAlt",
	[Enum.KeyCode.CapsLock] = "CapsLock",

	[Enum.KeyCode.Up] = "Up",
	[Enum.KeyCode.Down] = "Down",
	[Enum.KeyCode.Left] = "Left",
	[Enum.KeyCode.Right] = "Right",

	[Enum.KeyCode.Insert] = "Insert",
	[Enum.KeyCode.Delete] = "Delete",
	[Enum.KeyCode.Home] = "Home",
	[Enum.KeyCode.End] = "End",
	[Enum.KeyCode.PageUp] = "PageUp",
	[Enum.KeyCode.PageDown] = "PageDown",

	[Enum.KeyCode.F1] = "F1",
	[Enum.KeyCode.F2] = "F2",
	[Enum.KeyCode.F3] = "F3",
	[Enum.KeyCode.F4] = "F4",
	[Enum.KeyCode.F5] = "F5",
	[Enum.KeyCode.F6] = "F6",
	[Enum.KeyCode.F7] = "F7",
	[Enum.KeyCode.F8] = "F8",
	[Enum.KeyCode.F9] = "F9",
	[Enum.KeyCode.F10] = "F10",
	[Enum.KeyCode.F11] = "F11",
	[Enum.KeyCode.F12] = "F12",

	[Enum.KeyCode.Minus] = "Minus",
	[Enum.KeyCode.Equals] = "Equals",
	[Enum.KeyCode.LeftBracket] = "LeftBracket",
	[Enum.KeyCode.RightBracket] = "RightBracket",
	[Enum.KeyCode.Semicolon] = "Semicolon",
	[Enum.KeyCode.Quote] = "Quote",
	[Enum.KeyCode.Backquote] = "Backquote",
	[Enum.KeyCode.BackSlash] = "BackSlash",
	[Enum.KeyCode.Comma] = "Comma",
	[Enum.KeyCode.Period] = "Period",
	[Enum.KeyCode.Slash] = "Slash",
}

local function createEditableImage(imageLabel)
	local editableImage = AssetService:CreateEditableImage({
		Size = Vector2.new(Config.SCREEN_W, Config.SCREEN_H),
	})
	imageLabel.ImageContent = Content.fromObject(editableImage)
	return editableImage
end

local function attachKeyboard(machine)
	local beganConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		local key = ROBLOX_KEYCODE_TO_EMU_KEY[input.KeyCode]
		if key then
			machine:keyDown(key)
		end
	end)

	local endedConnection = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		local key = ROBLOX_KEYCODE_TO_EMU_KEY[input.KeyCode]
		if key then
			machine:keyUp(key)
		end
	end)

	return function()
		beganConnection:Disconnect()
		endedConnection:Disconnect()
	end
end

local function main()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MachinaHost"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "Display"
	imageLabel.Size = UDim2.fromScale(1, 1)
	imageLabel.BackgroundColor3 = Color3.new(0, 0, 0)
	imageLabel.BorderSizePixel = 0
	imageLabel.ScaleType = Enum.ScaleType.Stretch
	imageLabel.ResampleMode = Enum.ResamplerMode.Pixelated
	imageLabel.Parent = gui

	local editableImage = createEditableImage(imageLabel)

	local machine = PcSystem.new(Config)
	machine:setFramePresenter(function(pixelBuffer, width, height)
		editableImage:WritePixelsBuffer(Vector2.zero, Vector2.new(width, height), pixelBuffer)
	end)

	local detachKeyboard = attachKeyboard(machine)

	machine:powerOn()

	player.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			detachKeyboard()
			machine:shutdown()
		end
	end)
end

main()
```

Notes about diagnostics and validations

- Internal hardware self-tests remain available through `HardwareDiagnostics.run(...)`.
- Heavy guest-image CPU validation runners that were previously exposed via `HardwareDiagnostics.runGuestCPUValidations(...)` and `HardwareDiagnostics.runReviewSuite(...)` have been removed from the HardwareDiagnostics module. The repository still contains guest-visible VGA validation images (text, mode13, planar, font, palette) and internal diagnostics, but the review-only guest-image validation runners are no longer present in the default code paths.

