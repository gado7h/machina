-- NovaMachine/Main.lua
-- Root LocalScript — place in StarterPlayerScripts.
--
-- Setup in Roblox:
--   1.  ReplicatedStorage
--         NovaMachine (Folder)
--           Main (this file as a LocalScript)
--           Config (ModuleScript)
--           hardware/  (Folder)
--           firmware/  (Folder)
--           bootloader/(Folder)
--           kernel/    (Folder)
--           userland/  (Folder)
--           pkgmgr/    (Folder)
--           LuauVM     (ModuleScript)
--
-- The computer boots automatically on join (AUTO_POWER = true).

local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local AssetService = game:GetService("AssetService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ─────────────────────────────────────────────
--  Module imports
-- ─────────────────────────────────────────────
local NovaMachine = script.Parent
local Config = require(NovaMachine:WaitForChild("Config"))
local Motherboard = require(NovaMachine.hardware:WaitForChild("Motherboard"))
local LuauVM = require(NovaMachine:WaitForChild("LuauVM"))

-- ─────────────────────────────────────────────
--  GUI setup
-- ─────────────────────────────────────────────
local function setupGUI()
	local existing = playerGui:FindFirstChild("NovaMachineGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "NovaMachineGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- CRT bezel (full screen dark background)
	local bezel = Instance.new("Frame")
	bezel.Name = "Bezel"
	bezel.Size = UDim2.fromScale(1, 1)
	bezel.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	bezel.BorderSizePixel = 0
	bezel.Parent = gui

	-- Inner screen frame — maintains 320:200 (16:10) aspect ratio
	local screen = Instance.new("Frame")
	screen.Name = "ScreenFrame"
	screen.AnchorPoint = Vector2.new(0.5, 0.5)
	screen.Position = UDim2.fromScale(0.5, 0.5)
	screen.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	screen.BorderSizePixel = 2
	screen.Parent = bezel

	local function updateScreenSize()
		local vp = gui.AbsoluteSize
		local maxH = vp.Y * 0.88
		local maxW = vp.X * 0.88
		local h = math.min(maxH, maxW * (200 / 320))
		local w = h * (320 / 200)
		screen.Size = UDim2.fromOffset(math.floor(w), math.floor(h))
	end
	updateScreenSize()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScreenSize)

	-- Scanline overlay (cosmetic)
	local scanlines = Instance.new("Frame")
	scanlines.Name = "Scanlines"
	scanlines.Size = UDim2.fromScale(1, 1)
	scanlines.BackgroundTransparency = 1
	scanlines.BorderSizePixel = 0
	scanlines.ZIndex = 3
	scanlines.Parent = screen

	local scanlineGrad = Instance.new("UIGradient")
	scanlineGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
		ColorSequenceKeypoint.new(0.49, Color3.new(0, 0, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	scanlineGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.82),
		NumberSequenceKeypoint.new(0.49, 0.82),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	scanlineGrad.Rotation = 90
	scanlineGrad.Parent = scanlines

	-- ImageLabel that renders the EditableImage (the actual screen)
	local imgLabel = Instance.new("ImageLabel")
	imgLabel.Name = "Screen"
	imgLabel.Size = UDim2.fromScale(1, 1)
	imgLabel.BackgroundColor3 = Color3.new(0, 0, 0)
	imgLabel.BackgroundTransparency = 0
	imgLabel.BorderSizePixel = 0
	imgLabel.ScaleType = Enum.ScaleType.Stretch
	imgLabel.ResampleMode = Enum.ResamplerMode.Pixelated
	imgLabel.ZIndex = 2
	imgLabel.Parent = screen

	-- Subtle CRT green glow
	local glow = Instance.new("Frame")
	glow.Name = "CRTGlow"
	glow.Size = UDim2.new(1, 10, 1, 10)
	glow.Position = UDim2.fromOffset(-5, -5)
	glow.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
	glow.BackgroundTransparency = 0.92
	glow.BorderSizePixel = 0
	glow.ZIndex = 1
	glow.Parent = screen
	Instance.new("UICorner", glow).CornerRadius = UDim.new(0, 5)

	-- Power LED (top-right bezel corner)
	local powerLED = Instance.new("Frame")
	powerLED.Name = "PowerLED"
	powerLED.Size = UDim2.fromOffset(8, 8)
	powerLED.Position = UDim2.new(1, -20, 0, 12)
	powerLED.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
	powerLED.BorderSizePixel = 0
	powerLED.ZIndex = 5
	powerLED.Parent = bezel
	Instance.new("UICorner", powerLED).CornerRadius = UDim.new(1, 0)

	return gui, screen, imgLabel, powerLED
end

-- ─────────────────────────────────────────────
--  EditableImage — MUST be exactly 320×200
--
--  KEY FIX: GPU:flush() calls WritePixels with size Vector2(320,200).
--  If the EditableImage is any other size (e.g. 1920×1080), the write
--  only fills the top-left corner and the rest of the image stays black,
--  making the screen appear completely black.
-- ─────────────────────────────────────────────
local function createEditableImage(imageLabel)
	local ei = AssetService:CreateEditableImage({
		Size = Vector2.new(Config.SCREEN_W, Config.SCREEN_H), -- 320×200
	})
	imageLabel.ImageContent = Content.fromObject(ei)
	return ei
end

-- ─────────────────────────────────────────────
--  Power / Reboot button strip
-- ─────────────────────────────────────────────
local function addPowerButton(bezelFrame, onPower, onReboot)
	local btnFrame = Instance.new("Frame")
	btnFrame.Size = UDim2.fromOffset(120, 30)
	btnFrame.Position = UDim2.new(0.5, -60, 1, -42)
	btnFrame.BackgroundColor3 = Color3.fromRGB(10, 18, 35)
	btnFrame.BorderSizePixel = 0
	btnFrame.ZIndex = 6
	btnFrame.Parent = bezelFrame
	Instance.new("UICorner", btnFrame).CornerRadius = UDim.new(0, 4)

	local function makeBtn(text, xOff, clr, fn)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromOffset(52, 22)
		btn.Position = UDim2.fromOffset(xOff, 4)
		btn.BackgroundColor3 = clr
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Text = text
		btn.TextSize = 11
		btn.Font = Enum.Font.Code
		btn.BorderSizePixel = 0
		btn.ZIndex = 7
		btn.Parent = btnFrame
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 3)
		btn.Activated:Connect(fn)
	end

	makeBtn("⏻ POWER", 4, Color3.fromRGB(20, 100, 20), onPower)
	makeBtn("↺ REBOOT", 64, Color3.fromRGB(60, 40, 10), onReboot)
end

-- ─────────────────────────────────────────────
--  Power LED colour based on boot stage
-- ─────────────────────────────────────────────
local function startLEDBlink(led, getMachine)
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t = t + dt
		if t < 0.4 then
			return
		end
		t = 0
		local m = getMachine()
		local stage = m and m:getBootStage() or "OFF"
		if stage == "OFF" then
			led.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
		elseif stage == "RUNNING" then
			local v = math.abs(math.sin(os.clock() * math.pi))
			led.BackgroundColor3 = Color3.new(0, v, v * 0.3)
		else
			-- amber blink during boot
			local v = (os.clock() % 1) < 0.5 and 1 or 0.35
			led.BackgroundColor3 = Color3.new(v, v * 0.5, 0)
		end
	end)
end

-- ─────────────────────────────────────────────
--  HDD activity LED
-- ─────────────────────────────────────────────
local function addHDDLED(screenFrame, getMachine)
	local led = Instance.new("Frame")
	led.Name = "HddLED"
	led.Size = UDim2.fromOffset(6, 6)
	led.Position = UDim2.new(1, -10, 1, -10)
	led.BackgroundColor3 = Color3.fromRGB(0, 20, 60)
	led.BorderSizePixel = 0
	led.ZIndex = 8
	led.Parent = screenFrame
	Instance.new("UICorner", led).CornerRadius = UDim.new(1, 0)

	RunService.Heartbeat:Connect(function()
		local m = getMachine()
		if m and m.hdd and m.hdd:isActive() then
			led.BackgroundColor3 = Color3.fromRGB(0, 100, 255)
		else
			led.BackgroundColor3 = Color3.fromRGB(0, 20, 60)
		end
	end)
end

-- ─────────────────────────────────────────────
--  F12 stats overlay
-- ─────────────────────────────────────────────
local function addStatsOverlay(bezelFrame, getMachine)
	local overlay = Instance.new("Frame")
	overlay.Name = "StatsOverlay"
	overlay.Size = UDim2.fromOffset(230, 150)
	overlay.Position = UDim2.fromOffset(8, 8)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.3
	overlay.BorderSizePixel = 1
	overlay.BorderColor3 = Color3.fromRGB(0, 200, 100)
	overlay.ZIndex = 10
	overlay.Visible = false
	overlay.Parent = bezelFrame

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(0, 220, 120)
	lbl.Font = Enum.Font.Code
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Top
	lbl.Text = ""
	lbl.ZIndex = 11
	lbl.Parent = overlay

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == Enum.KeyCode.F12 then
			overlay.Visible = not overlay.Visible
		end
	end)

	local statTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		statTimer = statTimer + dt
		if statTimer < 0.5 then
			return
		end
		statTimer = 0
		if not overlay.Visible then
			return
		end
		local m = getMachine()
		if not m or not m:isPowered() then
			lbl.Text = "POWERED OFF"
			return
		end
		local s = m:getStats()
		local cpu = s.cpuStats or {}
		local ram = s.ramStats or {}
		local hdd = s.hddStats or {}
		local bus = s.busStats or {}
		lbl.Text = string.format(
			"NovaMachine  [F12]\n"
				.. "Stage:  %s\n"
				.. "Uptime: %.1fs\n"
				.. "CPU cycles: %d\n"
				.. "CPU instrs: %d\n"
				.. "RAM  r/w: %d/%d\n"
				.. "HDD  r/w: %d/%d\n"
				.. "Bus IRQs: %d\n"
				.. "GPU flush: %d",
			tostring(s.bootStage),
			s.uptime or 0,
			cpu.cycles or 0,
			cpu.instructions or 0,
			ram.reads or 0,
			ram.writes or 0,
			hdd.reads or 0,
			hdd.writes or 0,
			bus.irqFired or 0,
			(s.gpuStats and s.gpuStats.flushes) or 0
		)
	end)
end

-- ─────────────────────────────────────────────
--  Entrypoint
-- ─────────────────────────────────────────────
local machine = nil
local function getMachine()
	return machine
end

local function main()
	local gui, screenFrame, imageLabel, powerLED = setupGUI()

	-- EditableImage: 320×200, same as GPU resolution
	local editableImage = createEditableImage(imageLabel)

	-- Build machine
	machine = Motherboard.new(Config, editableImage, LuauVM)

	-- UI chrome
	addHDDLED(screenFrame, getMachine)
	startLEDBlink(powerLED, getMachine)
	addStatsOverlay(gui:FindFirstChild("Bezel"), getMachine)

	local powered = false
	addPowerButton(gui:FindFirstChild("Bezel"), function()
		if not powered then
			powered = true
			machine:powerOn()
			machine:bindInput(UserInputService)
		end
	end, function()
		if powered then
			machine:reboot()
		end
	end)

	-- Auto-boot on join (change to false to require button press)
	local AUTO_POWER = false
	if AUTO_POWER then
		task.delay(0.3, function()
			if not powered then
				powered = true
				machine:powerOn()
				machine:bindInput(UserInputService)
			end
		end)
	end

	player.CharacterRemoving:Connect(function()
		if machine then
			machine._powered = false
		end
	end)
end

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
main()
