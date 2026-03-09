-- NovaMachine/hardware/Keyboard.lua
-- PS/2 Keyboard controller emulation.
-- Roblox UserInputService events → keyboard scan codes → IRQ 1

local Keyboard = {}
Keyboard.__index = Keyboard

-- Scan code set 1 (XT/AT subset)
local SCAN_MAKE = {
	[Enum.KeyCode.A] = 0x1E,
	[Enum.KeyCode.B] = 0x30,
	[Enum.KeyCode.C] = 0x2E,
	[Enum.KeyCode.D] = 0x20,
	[Enum.KeyCode.E] = 0x12,
	[Enum.KeyCode.F] = 0x21,
	[Enum.KeyCode.G] = 0x22,
	[Enum.KeyCode.H] = 0x23,
	[Enum.KeyCode.I] = 0x17,
	[Enum.KeyCode.J] = 0x24,
	[Enum.KeyCode.K] = 0x25,
	[Enum.KeyCode.L] = 0x26,
	[Enum.KeyCode.M] = 0x32,
	[Enum.KeyCode.N] = 0x31,
	[Enum.KeyCode.O] = 0x18,
	[Enum.KeyCode.P] = 0x19,
	[Enum.KeyCode.Q] = 0x10,
	[Enum.KeyCode.R] = 0x13,
	[Enum.KeyCode.S] = 0x1F,
	[Enum.KeyCode.T] = 0x14,
	[Enum.KeyCode.U] = 0x16,
	[Enum.KeyCode.V] = 0x2F,
	[Enum.KeyCode.W] = 0x11,
	[Enum.KeyCode.X] = 0x2D,
	[Enum.KeyCode.Y] = 0x15,
	[Enum.KeyCode.Z] = 0x2C,
	[Enum.KeyCode.Zero] = 0x0B,
	[Enum.KeyCode.One] = 0x02,
	[Enum.KeyCode.Two] = 0x03,
	[Enum.KeyCode.Three] = 0x04,
	[Enum.KeyCode.Four] = 0x05,
	[Enum.KeyCode.Five] = 0x06,
	[Enum.KeyCode.Six] = 0x07,
	[Enum.KeyCode.Seven] = 0x08,
	[Enum.KeyCode.Eight] = 0x09,
	[Enum.KeyCode.Nine] = 0x0A,
	[Enum.KeyCode.Return] = 0x1C,
	[Enum.KeyCode.Space] = 0x39,
	[Enum.KeyCode.Backspace] = 0x0E,
	[Enum.KeyCode.Tab] = 0x0F,
	[Enum.KeyCode.Escape] = 0x01,
	[Enum.KeyCode.LeftShift] = 0x2A,
	[Enum.KeyCode.RightShift] = 0x36,
	[Enum.KeyCode.LeftControl] = 0x1D,
	[Enum.KeyCode.RightControl] = 0x1D,
	[Enum.KeyCode.LeftAlt] = 0x38,
	[Enum.KeyCode.CapsLock] = 0x3A,
	[Enum.KeyCode.F1] = 0x3B,
	[Enum.KeyCode.F2] = 0x3C,
	[Enum.KeyCode.F3] = 0x3D,
	[Enum.KeyCode.F4] = 0x3E,
	[Enum.KeyCode.F5] = 0x3F,
	[Enum.KeyCode.F6] = 0x40,
	[Enum.KeyCode.F7] = 0x41,
	[Enum.KeyCode.F8] = 0x42,
	[Enum.KeyCode.F9] = 0x43,
	[Enum.KeyCode.F10] = 0x44,
	[Enum.KeyCode.F11] = 0x57,
	[Enum.KeyCode.F12] = 0x58,
	[Enum.KeyCode.Up] = 0x48,
	[Enum.KeyCode.Down] = 0x50,
	[Enum.KeyCode.Left] = 0x4B,
	[Enum.KeyCode.Right] = 0x4D,
	[Enum.KeyCode.Delete] = 0x53,
	[Enum.KeyCode.Insert] = 0x52,
	[Enum.KeyCode.Home] = 0x47,
	[Enum.KeyCode.End] = 0x4F,
	[Enum.KeyCode.PageUp] = 0x49,
	[Enum.KeyCode.PageDown] = 0x51,
	[Enum.KeyCode.Minus] = 0x0C,
	[Enum.KeyCode.Equals] = 0x0D,
	[Enum.KeyCode.LeftBracket] = 0x1A,
	[Enum.KeyCode.RightBracket] = 0x1B,
	[Enum.KeyCode.Semicolon] = 0x27,
	[Enum.KeyCode.Quote] = 0x28,
	[Enum.KeyCode.Backquote] = 0x29,
	[Enum.KeyCode.BackSlash] = 0x2B,
	[Enum.KeyCode.Comma] = 0x33,
	[Enum.KeyCode.Period] = 0x34,
	[Enum.KeyCode.Slash] = 0x35,
}

-- Map scan code → ASCII (unshifted)
local SC_TO_ASCII_LOWER = {
	[0x02] = "1",
	[0x03] = "2",
	[0x04] = "3",
	[0x05] = "4",
	[0x06] = "5",
	[0x07] = "6",
	[0x08] = "7",
	[0x09] = "8",
	[0x0A] = "9",
	[0x0B] = "0",
	[0x0C] = "-",
	[0x0D] = "=",
	[0x0E] = "\b",
	[0x0F] = "\t",
	[0x10] = "q",
	[0x11] = "w",
	[0x12] = "e",
	[0x13] = "r",
	[0x14] = "t",
	[0x15] = "y",
	[0x16] = "u",
	[0x17] = "i",
	[0x18] = "o",
	[0x19] = "p",
	[0x1A] = "[",
	[0x1B] = "]",
	[0x1C] = "\n",
	[0x1E] = "a",
	[0x1F] = "s",
	[0x20] = "d",
	[0x21] = "f",
	[0x22] = "g",
	[0x23] = "h",
	[0x24] = "j",
	[0x25] = "k",
	[0x26] = "l",
	[0x27] = ";",
	[0x28] = "'",
	[0x29] = "`",
	[0x2B] = "\\",
	[0x2C] = "z",
	[0x2D] = "x",
	[0x2E] = "c",
	[0x2F] = "v",
	[0x30] = "b",
	[0x31] = "n",
	[0x32] = "m",
	[0x33] = ",",
	[0x34] = ".",
	[0x35] = "/",
	[0x39] = " ",
	[0x47] = "[HOME]",
	[0x48] = "[UP]",
	[0x4B] = "[LEFT]",
	[0x4D] = "[RIGHT]",
	[0x4F] = "[END]",
	[0x50] = "[DOWN]",
	[0x53] = "[DEL]",
}
local SC_TO_ASCII_UPPER = {
	[0x02] = "!",
	[0x03] = "@",
	[0x04] = "#",
	[0x05] = "$",
	[0x06] = "%",
	[0x07] = "^",
	[0x08] = "&",
	[0x09] = "*",
	[0x0A] = "(",
	[0x0B] = ")",
	[0x0C] = "_",
	[0x0D] = "+",
	[0x0E] = "\b",
	[0x0F] = "\t",
	[0x10] = "Q",
	[0x11] = "W",
	[0x12] = "E",
	[0x13] = "R",
	[0x14] = "T",
	[0x15] = "Y",
	[0x16] = "U",
	[0x17] = "I",
	[0x18] = "O",
	[0x19] = "P",
	[0x1A] = "{",
	[0x1B] = "}",
	[0x1C] = "\n",
	[0x1E] = "A",
	[0x1F] = "S",
	[0x20] = "D",
	[0x21] = "F",
	[0x22] = "G",
	[0x23] = "H",
	[0x24] = "J",
	[0x25] = "K",
	[0x26] = "L",
	[0x27] = ":",
	[0x28] = '"',
	[0x29] = "~",
	[0x2B] = "|",
	[0x2C] = "Z",
	[0x2D] = "X",
	[0x2E] = "C",
	[0x2F] = "V",
	[0x30] = "B",
	[0x31] = "N",
	[0x32] = "M",
	[0x33] = "<",
	[0x34] = ">",
	[0x35] = "?",
	[0x39] = " ",
}

function Keyboard.new(config, bus)
	local self = setmetatable({}, Keyboard)
	self.config = config
	self.bus = bus
	self._buffer = {} -- FIFO of scan codes
	self._ascii = {} -- FIFO of ASCII chars
	self._shift = false
	self._ctrl = false
	self._alt = false
	self._capsLock = false
	self._enabled = false
	self.stats = { keyPresses = 0, bufferOverruns = 0 }

	-- Register port handlers
	bus:registerPort(config.PORT.KBD_DATA, function()
		return self:_readData()
	end, nil, "KBD Data")
	bus:registerPort(config.PORT.KBD_STATUS, function()
		return self:_readStatus()
	end, function(v)
		self:_writeCtrl(v)
	end, "KBD Status/Ctrl")
	return self
end

--- Call this once from a LocalScript to hook Roblox input.
function Keyboard:bindRobloxInput(UIS)
	self:unbind()
	self._enabled = true
	self._uisDown = UIS.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		self:_onKeyDown(input)
	end)
	self._uisUp = UIS.InputEnded:Connect(function(input, _)
		self:_onKeyUp(input)
	end)
end

function Keyboard:unbind()
	if self._uisDown then
		self._uisDown:Disconnect()
		self._uisDown = nil
	end
	if self._uisUp then
		self._uisUp:Disconnect()
		self._uisUp = nil
	end
	self._enabled = false
end

function Keyboard:_onKeyDown(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	local kc = input.KeyCode
	-- Update modifier state
	if kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.RightShift then
		self._shift = true
		return
	end
	if kc == Enum.KeyCode.LeftControl or kc == Enum.KeyCode.RightControl then
		self._ctrl = true
		return
	end
	if kc == Enum.KeyCode.LeftAlt then
		self._alt = true
		return
	end
	if kc == Enum.KeyCode.CapsLock then
		self._capsLock = not self._capsLock
		return
	end

	local sc = SCAN_MAKE[kc]
	if not sc then
		return
	end

	self.stats.keyPresses = self.stats.keyPresses + 1

	-- Push scan code
	if #self._buffer < 16 then
		table.insert(self._buffer, sc)
	else
		self.stats.bufferOverruns = self.stats.bufferOverruns + 1
	end

	-- Resolve ASCII
	local lower = SC_TO_ASCII_LOWER[sc]
	local upper = SC_TO_ASCII_UPPER[sc]
	local ascii

	if lower and upper then
		local isLetter = lower:match("^[a-z]$") ~= nil

		if isLetter then
			-- For letters: Shift XOR CapsLock
			local useUpper = (self._shift and not self._capsLock) or (self._capsLock and not self._shift)
			ascii = useUpper and upper or lower
		else
			-- For non-letters: only Shift matters
			ascii = self._shift and upper or lower
		end
	else
		ascii = lower or upper
	end

	if self._ctrl and ascii and #ascii == 1 then
		local upperAscii = string.upper(ascii)
		local byte = string.byte(upperAscii)
		local code = byte - 64
		if code > 0 and code < 32 then
			ascii = string.char(code)
		end
	end

	if ascii then
		if #self._ascii < 64 then
			table.insert(self._ascii, ascii)
		end
	end

	-- Raise IRQ 1 (keyboard)
	self.bus:raiseIRQ(self.config.IRQ.KEYBOARD, sc)
end

function Keyboard:_onKeyUp(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.RightShift then
		self._shift = false
	end
	if kc == Enum.KeyCode.LeftControl or kc == Enum.KeyCode.RightControl then
		self._ctrl = false
	end
	if kc == Enum.KeyCode.LeftAlt then
		self._alt = false
	end
end

-- ── Port read/write ──
function Keyboard:_readData()
	return table.remove(self._buffer, 1) or 0
end

function Keyboard:_readStatus()
	-- bit 0 = OBF (output buffer full = data available)
	return (#self._buffer > 0) and 0x01 or 0x00
end

function Keyboard:_writeCtrl(v)
	-- 0xFF = reset
	if v == 0xFF then
		self._buffer = {}
		self._ascii = {}
	end
end

--- High-level: read one ASCII character (non-blocking, returns nil if empty)
function Keyboard:readChar()
	return table.remove(self._ascii, 1)
end

--- High-level: peek without consuming
function Keyboard:peekChar()
	return self._ascii[1]
end

--- High-level: read a line (blocking-style, call repeatedly)
--- Returns the line string when Enter is pressed, nil otherwise.
--- currentLine is a table passed in and mutated.
function Keyboard:pollLine(currentLine, echo, gpu)
	local ch = self:readChar()
	if not ch then
		return nil
	end

	if ch == "\n" or ch == "\r" then
		local line = table.concat(currentLine)
		for i = #currentLine, 1, -1 do
			currentLine[i] = nil
		end
		if echo and gpu then
			gpu:print("\n")
		end
		return line
	elseif ch == "\b" then
		if #currentLine > 0 then
			table.remove(currentLine)
			if echo and gpu then
				gpu:print("\b")
			end
		end
	else
		table.insert(currentLine, ch)
		if echo and gpu then
			gpu:print(ch)
		end
	end
	return nil
end

function Keyboard:getStats()
	return self.stats
end

return Keyboard
