local I8042Controller = {}
I8042Controller.__index = I8042Controller

local KBD_ACK = 0xFA
local KBD_SELF_TEST_PASSED = 0xAA

local STATUS_OUTPUT_FULL = 0x01
local STATUS_INPUT_FULL = 0x02
local STATUS_SYSTEM = 0x04
local STATUS_COMMAND = 0x08

local COMMAND_IRQ1_ENABLE = 0x01
local COMMAND_SYSTEM_FLAG = 0x04
local COMMAND_DISABLE_KEYBOARD = 0x10

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
	[Enum.KeyCode.RightControl] = { 0xE0, 0x1D },
	[Enum.KeyCode.LeftAlt] = 0x38,
	[Enum.KeyCode.RightAlt] = { 0xE0, 0x38 },
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
	[Enum.KeyCode.Up] = { 0xE0, 0x48 },
	[Enum.KeyCode.Down] = { 0xE0, 0x50 },
	[Enum.KeyCode.Left] = { 0xE0, 0x4B },
	[Enum.KeyCode.Right] = { 0xE0, 0x4D },
	[Enum.KeyCode.Delete] = { 0xE0, 0x53 },
	[Enum.KeyCode.Insert] = { 0xE0, 0x52 },
	[Enum.KeyCode.Home] = { 0xE0, 0x47 },
	[Enum.KeyCode.End] = { 0xE0, 0x4F },
	[Enum.KeyCode.PageUp] = { 0xE0, 0x49 },
	[Enum.KeyCode.PageDown] = { 0xE0, 0x51 },
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

local function cloneSequence(entry)
	if type(entry) == "table" then
		return table.clone(entry)
	end
	return { entry }
end

function I8042Controller.new(config, bus)
	local self = setmetatable({}, I8042Controller)
	self.config = config
	self.bus = bus
	self._buffer = {}
	self._ascii = {}
	self._shift = false
	self._ctrl = false
	self._alt = false
	self._capsLock = false
	self._enabled = false
	self._scanningEnabled = true
	self._controllerCommandByte = bit32.bor(COMMAND_IRQ1_ENABLE, COMMAND_SYSTEM_FLAG)
	self._pendingControllerData = nil
	self._pendingI8042ControllerData = nil
	self._status = STATUS_SYSTEM
	self.stats = { keyPresses = 0, bufferOverruns = 0 }

	bus:registerPort(config.PORT.KBD_DATA, function()
		return self:_readData()
	end, function(v)
		self:_writeData(v)
	end, "KBD Data")
	bus:registerPort(config.PORT.KBD_STATUS, function()
		return self:_readStatus()
	end, function(v)
		self:_writeCtrl(v)
	end, "KBD Status/Ctrl")
	return self
end

function I8042Controller:_raiseIRQ()
	if bit32.band(self._controllerCommandByte, COMMAND_IRQ1_ENABLE) ~= 0 then
		self.bus:raiseIRQ(self.config.IRQ.KEYBOARD, { source = "keyboard", status = self._status })
	end
end

function I8042Controller:_pushOutputByte(value)
	if #self._buffer >= 64 then
		self.stats.bufferOverruns = self.stats.bufferOverruns + 1
		return
	end
	self._buffer[#self._buffer + 1] = bit32.band(tonumber(value) or 0, 0xFF)
	self._status = bit32.bor(self._status, STATUS_OUTPUT_FULL)
	self:_raiseIRQ()
end

function I8042Controller:_clearOutputStatus()
	if #self._buffer == 0 then
		self._status = bit32.band(self._status, bit32.bnot(STATUS_OUTPUT_FULL))
	end
end

function I8042Controller:_translateASCII(scanCode)
	local lower = SC_TO_ASCII_LOWER[scanCode]
	local upper = SC_TO_ASCII_UPPER[scanCode]
	local ascii
	if lower and upper then
		local isLetter = lower:match("^[a-z]$") ~= nil
		if isLetter then
			local useUpper = (self._shift and not self._capsLock) or (self._capsLock and not self._shift)
			ascii = useUpper and upper or lower
		else
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

	if ascii and #self._ascii < 128 then
		self._ascii[#self._ascii + 1] = ascii
	end
end

function I8042Controller:_queueScanSequence(sequence, isBreak)
	local codes = cloneSequence(sequence)
	if isBreak then
		codes[#codes] = bit32.bor(codes[#codes], 0x80)
	end
	for _, code in ipairs(codes) do
		self:_pushOutputByte(code)
	end
end

function I8042Controller:_setModifierState(kc, isDown)
	if kc == Enum.KeyCode.LeftShift or kc == Enum.KeyCode.RightShift then
		self._shift = isDown
	elseif kc == Enum.KeyCode.LeftControl or kc == Enum.KeyCode.RightControl then
		self._ctrl = isDown
	elseif kc == Enum.KeyCode.LeftAlt or kc == Enum.KeyCode.RightAlt then
		self._alt = isDown
	elseif kc == Enum.KeyCode.CapsLock and isDown then
		self._capsLock = not self._capsLock
	end
end

function I8042Controller:bindRobloxInput(UIS)
	self:unbind()
	self._enabled = true
	self._uisDown = UIS.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		self:_onKeyDown(input)
	end)
	self._uisUp = UIS.InputEnded:Connect(function(input)
		self:_onKeyUp(input)
	end)
end

function I8042Controller:unbind()
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

function I8042Controller:_onKeyDown(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard or not self._scanningEnabled then
		return
	end
	local kc = input.KeyCode
	self:_setModifierState(kc, true)

	local sequence = SCAN_MAKE[kc]
	if not sequence then
		return
	end

	self.stats.keyPresses = self.stats.keyPresses + 1
	self:_queueScanSequence(sequence, false)

	if type(sequence) ~= "table" then
		self:_translateASCII(sequence)
	end
end

function I8042Controller:_onKeyUp(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard or not self._scanningEnabled then
		return
	end
	local kc = input.KeyCode
	self:_setModifierState(kc, false)
	local sequence = SCAN_MAKE[kc]
	if sequence then
		self:_queueScanSequence(sequence, true)
	end
end

function I8042Controller:_readData()
	local value = table.remove(self._buffer, 1) or 0
	self:_clearOutputStatus()
	return value
end

function I8042Controller:_readStatus()
	return self._status
end

function I8042Controller:_writeI8042ControllerCommand(value)
	local v = bit32.band(tonumber(value) or 0, 0xFF)
	if self._pendingI8042ControllerData == "led" then
		self._pendingI8042ControllerData = nil
		self:_pushOutputByte(KBD_ACK)
		return
	end

	if v == 0xED then
		self._pendingI8042ControllerData = "led"
		self:_pushOutputByte(KBD_ACK)
	elseif v == 0xF2 then
		self:_pushOutputByte(KBD_ACK)
		self:_pushOutputByte(0xAB)
		self:_pushOutputByte(0x83)
	elseif v == 0xF4 then
		self._scanningEnabled = true
		self:_pushOutputByte(KBD_ACK)
	elseif v == 0xF5 then
		self._scanningEnabled = false
		self:_pushOutputByte(KBD_ACK)
	elseif v == 0xFF then
		self._buffer = {}
		self._ascii = {}
		self._scanningEnabled = true
		self:_pushOutputByte(KBD_ACK)
		self:_pushOutputByte(KBD_SELF_TEST_PASSED)
	else
		self:_pushOutputByte(KBD_ACK)
	end
end

function I8042Controller:_writeData(value)
	local v = bit32.band(tonumber(value) or 0, 0xFF)
	if self._pendingControllerData == "command-byte" then
		self._controllerCommandByte = v
		self._pendingControllerData = nil
		self._status = bit32.band(self._status, bit32.bnot(STATUS_INPUT_FULL))
		return
	end
	self:_writeI8042ControllerCommand(v)
end

function I8042Controller:_writeCtrl(value)
	local v = bit32.band(tonumber(value) or 0, 0xFF)
	self._status = bit32.bor(self._status, STATUS_COMMAND)
	if v == 0x20 then
		self:_pushOutputByte(self._controllerCommandByte)
	elseif v == 0x60 then
		self._pendingControllerData = "command-byte"
		self._status = bit32.bor(self._status, STATUS_INPUT_FULL)
	elseif v == 0xAA then
		self._status = bit32.bor(self._status, STATUS_SYSTEM)
		self:_pushOutputByte(0x55)
	elseif v == 0xAB or v == 0xFE then
		self:_pushOutputByte(0x00)
	elseif v == 0xAD then
		self._scanningEnabled = false
		self._controllerCommandByte = bit32.bor(self._controllerCommandByte, COMMAND_DISABLE_KEYBOARD)
	elseif v == 0xAE then
		self._scanningEnabled = true
		self._controllerCommandByte = bit32.band(self._controllerCommandByte, bit32.bnot(COMMAND_DISABLE_KEYBOARD))
	end
	self._status = bit32.band(self._status, bit32.bnot(STATUS_COMMAND))
end

function I8042Controller:readChar()
	return table.remove(self._ascii, 1)
end

function I8042Controller:peekChar()
	return self._ascii[1]
end

function I8042Controller:pollLine(currentLine, echo, gpu)
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

function I8042Controller:getStats()
	return self.stats
end

return I8042Controller
