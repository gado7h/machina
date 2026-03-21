-- VgaAdapter module

local VgaAdapter = {}
VgaAdapter.__index = VgaAdapter

-- CGA 16-color palette (packed ARGB as Lua integer)
local PALETTE = {
	[0] = 0xFF000000, -- black
	[1] = 0xFF0000AA, -- blue
	[2] = 0xFF00AA00, -- green
	[3] = 0xFF00AAAA, -- cyan
	[4] = 0xFFAA0000, -- red
	[5] = 0xFFAA00AA, -- magenta
	[6] = 0xFFAA5500, -- brown
	[7] = 0xFFAAAAAA, -- light gray
	[8] = 0xFF555555, -- dark gray
	[9] = 0xFF5555FF, -- bright blue
	[10] = 0xFF55FF55, -- bright green
	[11] = 0xFF55FFFF, -- bright cyan
	[12] = 0xFFFF5555, -- bright red
	[13] = 0xFFFF55FF, -- bright magenta
	[14] = 0xFFFFFF55, -- yellow
	[15] = 0xFFFFFFFF, -- white
}

-- 4Ã—8 bitmap font (ASCII 32-126).
-- Each glyph is 8 bytes; each byte is one scanline with bits 3..0 = columns 0..3.
local function F(...)
	return { ... }
end
local _GLYPHS = {
	[32] = F(0, 0, 0, 0, 0, 0, 0, 0), -- space
	[33] = F(4, 4, 4, 4, 0, 4, 0, 0), -- !
	[34] = F(10, 10, 0, 0, 0, 0, 0, 0), -- "
	[35] = F(10, 10, 15, 10, 15, 10, 10, 0), -- #
	[36] = F(4, 7, 8, 6, 1, 14, 4, 0), -- $
	[37] = F(9, 1, 2, 4, 8, 9, 0, 0), -- %
	[38] = F(4, 10, 10, 4, 11, 9, 6, 0), -- &
	[39] = F(4, 4, 0, 0, 0, 0, 0, 0), -- '
	[40] = F(2, 4, 8, 8, 8, 4, 2, 0), -- (
	[41] = F(8, 4, 2, 2, 2, 4, 8, 0), -- )
	[42] = F(0, 4, 14, 4, 14, 4, 0, 0), -- *
	[43] = F(0, 4, 4, 15, 4, 4, 0, 0), -- +
	[44] = F(0, 0, 0, 0, 4, 4, 8, 0), -- ,
	[45] = F(0, 0, 0, 15, 0, 0, 0, 0), -- -
	[46] = F(0, 0, 0, 0, 0, 6, 6, 0), -- .
	[47] = F(1, 1, 2, 4, 8, 8, 0, 0), -- /
	[48] = F(6, 9, 11, 13, 9, 6, 0, 0), -- 0
	[49] = F(4, 6, 4, 4, 4, 14, 0, 0), -- 1
	[50] = F(6, 9, 1, 2, 4, 15, 0, 0), -- 2
	[51] = F(6, 9, 2, 1, 9, 6, 0, 0), -- 3
	[52] = F(2, 6, 10, 15, 2, 2, 0, 0), -- 4
	[53] = F(15, 8, 14, 1, 9, 6, 0, 0), -- 5
	[54] = F(3, 4, 14, 9, 9, 6, 0, 0), -- 6
	[55] = F(15, 1, 2, 4, 4, 4, 0, 0), -- 7
	[56] = F(6, 9, 6, 9, 9, 6, 0, 0), -- 8
	[57] = F(6, 9, 7, 1, 2, 12, 0, 0), -- 9
	[58] = F(0, 6, 6, 0, 6, 6, 0, 0), -- :
	[59] = F(0, 6, 6, 0, 6, 6, 4, 0), -- ;
	[60] = F(2, 4, 8, 4, 2, 0, 0, 0), -- <
	[61] = F(0, 15, 0, 15, 0, 0, 0, 0), -- =
	[62] = F(8, 4, 2, 4, 8, 0, 0, 0), -- >
	[63] = F(6, 9, 1, 2, 0, 2, 0, 0), -- ?
	[64] = F(6, 9, 11, 13, 8, 6, 0, 0), -- @
	[65] = F(6, 9, 15, 9, 9, 9, 0, 0), -- A
	[66] = F(14, 9, 14, 9, 9, 14, 0, 0), -- B
	[67] = F(6, 9, 8, 8, 9, 6, 0, 0), -- C
	[68] = F(14, 9, 9, 9, 9, 14, 0, 0), -- D
	[69] = F(15, 8, 14, 8, 8, 15, 0, 0), -- E
	[70] = F(15, 8, 14, 8, 8, 8, 0, 0), -- F
	[71] = F(6, 9, 8, 11, 9, 7, 0, 0), -- G
	[72] = F(9, 9, 15, 9, 9, 9, 0, 0), -- H
	[73] = F(14, 4, 4, 4, 4, 14, 0, 0), -- I
	[74] = F(7, 2, 2, 2, 10, 4, 0, 0), -- J
	[75] = F(9, 10, 12, 10, 9, 9, 0, 0), -- K
	[76] = F(8, 8, 8, 8, 8, 15, 0, 0), -- L
	[77] = F(9, 15, 15, 9, 9, 9, 0, 0), -- M
	[78] = F(9, 13, 11, 9, 9, 9, 0, 0), -- N
	[79] = F(6, 9, 9, 9, 9, 6, 0, 0), -- O
	[80] = F(14, 9, 14, 8, 8, 8, 0, 0), -- P
	[81] = F(6, 9, 9, 11, 9, 7, 0, 0), -- Q
	[82] = F(14, 9, 14, 10, 9, 9, 0, 0), -- R
	[83] = F(7, 8, 6, 1, 9, 6, 0, 0), -- S
	[84] = F(15, 4, 4, 4, 4, 4, 0, 0), -- T
	[85] = F(9, 9, 9, 9, 9, 6, 0, 0), -- U
	[86] = F(9, 9, 9, 9, 6, 4, 0, 0), -- V
	[87] = F(9, 9, 9, 15, 15, 9, 0, 0), -- W
	[88] = F(9, 9, 6, 6, 9, 9, 0, 0), -- X
	[89] = F(9, 9, 6, 4, 4, 4, 0, 0), -- Y
	[90] = F(15, 1, 2, 4, 8, 15, 0, 0), -- Z
	[91] = F(6, 4, 4, 4, 4, 6, 0, 0), -- [
	[92] = F(8, 8, 4, 2, 1, 1, 0, 0), -- backslash
	[93] = F(6, 2, 2, 2, 2, 6, 0, 0), -- ]
	[94] = F(4, 10, 0, 0, 0, 0, 0, 0), -- ^
	[95] = F(0, 0, 0, 0, 0, 0, 15, 0), -- _
	[96] = F(8, 4, 0, 0, 0, 0, 0, 0), -- `
	[97] = F(0, 0, 6, 1, 7, 7, 0, 0), -- a
	[98] = F(8, 8, 14, 9, 9, 14, 0, 0), -- b
	[99] = F(0, 0, 6, 8, 8, 6, 0, 0), -- c
	[100] = F(1, 1, 7, 9, 9, 7, 0, 0), -- d
	[101] = F(0, 0, 6, 15, 8, 6, 0, 0), -- e
	[102] = F(3, 4, 14, 4, 4, 4, 0, 0), -- f
	[103] = F(0, 0, 7, 9, 7, 1, 6, 0), -- g
	[104] = F(8, 8, 14, 9, 9, 9, 0, 0), -- h
	[105] = F(4, 0, 4, 4, 4, 6, 0, 0), -- i
	[106] = F(2, 0, 2, 2, 10, 4, 0, 0), -- j
	[107] = F(8, 8, 9, 14, 9, 9, 0, 0), -- k
	[108] = F(6, 4, 4, 4, 4, 6, 0, 0), -- l
	[109] = F(0, 0, 15, 15, 9, 9, 0, 0), -- m
	[110] = F(0, 0, 14, 9, 9, 9, 0, 0), -- n
	[111] = F(0, 0, 6, 9, 9, 6, 0, 0), -- o
	[112] = F(0, 0, 14, 9, 14, 8, 8, 0), -- p
	[113] = F(0, 0, 7, 9, 7, 1, 1, 0), -- q
	[114] = F(0, 0, 11, 12, 8, 8, 0, 0), -- r
	[115] = F(0, 0, 6, 4, 2, 14, 0, 0), -- s
	[116] = F(4, 4, 14, 4, 4, 3, 0, 0), -- t
	[117] = F(0, 0, 9, 9, 9, 7, 0, 0), -- u
	[118] = F(0, 0, 9, 9, 6, 4, 0, 0), -- v
	[119] = F(0, 0, 9, 15, 15, 6, 0, 0), -- w
	[120] = F(0, 0, 9, 6, 6, 9, 0, 0), -- x
	[121] = F(0, 0, 9, 7, 1, 6, 0, 0), -- y
	[122] = F(0, 0, 15, 2, 4, 15, 0, 0), -- z
	[123] = F(3, 4, 4, 8, 4, 4, 3, 0), -- {
	[124] = F(4, 4, 4, 4, 4, 4, 0, 0), -- |
	[125] = F(12, 2, 2, 1, 2, 2, 12, 0), -- }
	[126] = F(0, 0, 5, 10, 0, 0, 0, 0), -- ~
}
local FONT = table.clone(_GLYPHS)

local GLYPH_DEFAULT = F(15, 9, 9, 9, 9, 15, 0, 0)
local function getGlyph(ch)
	return FONT[ch] or GLYPH_DEFAULT
end

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function unpackARGB(c)
	local a = math.floor(c / 16777216) % 256
	local r = math.floor(c / 65536) % 256
	local g = math.floor(c / 256) % 256
	local b = c % 256
	return a, r, g, b
end

local function packARGB(a, r, g, b)
	return ((a % 256) * 16777216) + ((r % 256) * 65536) + ((g % 256) * 256) + (b % 256)
end

local function blendARGB(bg, fg, alpha)
	if alpha <= 0 then
		return bg
	elseif alpha >= 255 then
		return fg
	end
	local _, br, bgc, bb = unpackARGB(bg)
	local _, fr, fgc, fb = unpackARGB(fg)
	local t = alpha / 255
	return packARGB(
		255,
		math.floor(lerp(br, fr, t) + 0.5),
		math.floor(lerp(bgc, fgc, t) + 0.5),
		math.floor(lerp(bb, fb, t) + 0.5)
	)
end

local function glyphBit(glyph, gx, gy)
	if gx < 0 or gx > 3 or gy < 0 or gy > 7 then
		return 0
	end
	local bits = glyph[gy + 1] or 0
	local mask = 2 ^ (3 - gx)
	return (bits % (mask * 2)) >= mask and 1 or 0
end

local function sampleGlyphSmooth(glyph, u, v)
	local x = clamp(u, 0, 3)
	local y = clamp(v, 0, 7)
	local x0 = math.floor(x)
	local y0 = math.floor(y)
	local x1 = math.min(3, x0 + 1)
	local y1 = math.min(7, y0 + 1)
	local tx = x - x0
	local ty = y - y0

	local a = glyphBit(glyph, x0, y0)
	local b = glyphBit(glyph, x1, y0)
	local c = glyphBit(glyph, x0, y1)
	local d = glyphBit(glyph, x1, y1)

	local top = lerp(a, b, tx)
	local bot = lerp(c, d, tx)
	return lerp(top, bot, ty)
end

function VgaAdapter.new(config)
	local self = setmetatable({}, VgaAdapter)
	self.config = config
	self.W = config.SCREEN_W
	self.H = config.SCREEN_H
	self.CW = config.CHAR_W
	self.CH = config.CHAR_H

	self.GW = config.GLYPH_W or self.CW
	self.GH = config.GLYPH_H or self.CH
	self.PX = config.PAD_X or 0
	self.PY = config.PAD_Y or 0

	self.mode = "TEXT"
	self.fontSmoothing = config.FONT_SMOOTHING == true
	self.guiOps = {}

	self._nextFrameTime = 0
	self._frameInterval = 1 / math.max(1, config.DISPLAY_REFRESH_HZ or 60)

	self._textCellCount = math.max(
		config.TEXT_COLS * config.TEXT_ROWS,
		math.floor((config.VIDEO_SIZE or (config.TEXT_COLS * config.TEXT_ROWS * 2)) / 2)
	)
	self._crtcIndex = 0
	self._crtc = {
		[0x0A] = 0x06,
		[0x0B] = 0x07,
		[0x0C] = 0x00,
		[0x0D] = 0x00,
		[0x0E] = 0x00,
		[0x0F] = 0x00,
	}
	self._miscOutput = 0x67

	-- Text buffer: flat array [0 .. textCellCount-1], each entry {char, attr}
	self._textBuf = {}
	for i = 0, self._textCellCount - 1 do
		self._textBuf[i] = { char = 32, attr = 0x07 }
	end
	self._cursorRow = 0
	self._cursorCol = 0
	self._cursorVisible = true
	self._lastCursor = { col = 0, row = 0 }

	self._dirtyCells = {}
	self._dirtyCellList = {}

	-- Pixel framebuffer: flat array [0 .. W*H-1] of packed ARGB integers
	self._framebuf = {}
	for i = 0, self.W * self.H - 1 do
		self._framebuf[i] = 0xFF000000
	end

	-- Native buffer for WritePixelsBuffer â€” allocated once, reused every frame.
	-- Layout: RGBA u8 bytes, row-major. Size = W * H * 4 bytes.
	self._pixelBuffer = buffer.create(self.W * self.H * 4)

	-- VRAM (bus-mapped region, written by CPU via memWrite)
	self._vram = {}
	self._dirty = true

	self.stats = { flushes = 0, textWrites = 0, pixelWrites = 0, guiDrawCalls = 0 }

	return self
end

local function markCellDirty(self, col, row)
	if col < 0 or col >= self.config.TEXT_COLS then
		return
	end
	if row < 0 or row >= self.config.TEXT_ROWS then
		return
	end
	local idx = row * self.config.TEXT_COLS + col
	if not self._dirtyCells[idx] then
		self._dirtyCells[idx] = true
		table.insert(self._dirtyCellList, idx)
	end
end

local function markAllCellsDirty(self)
	for row = 0, self.config.TEXT_ROWS - 1 do
		for col = 0, self.config.TEXT_COLS - 1 do
			markCellDirty(self, col, row)
		end
	end
end

local function syncCellToVRAM(self, absoluteIdx)
	local cell = self._textBuf[absoluteIdx] or { char = 32, attr = 0x07 }
	local base = absoluteIdx * 2
	self._vram[base] = cell.char
	self._vram[base + 1] = cell.attr
end

local function textStartCell(self)
	local startAddress = ((self._crtc[0x0C] or 0) * 256) + (self._crtc[0x0D] or 0)
	return startAddress % math.max(1, self._textCellCount)
end

local function updateCursorRegisters(self)
	local cursorCell = (textStartCell(self) + (self._cursorRow * self.config.TEXT_COLS) + self._cursorCol)
		% math.max(1, self._textCellCount)
	self._crtc[0x0E] = math.floor(cursorCell / 256) % 256
	self._crtc[0x0F] = cursorCell % 256
end

local function applyCursorRegisters(self)
	local cursorCell = (((self._crtc[0x0E] or 0) * 256) + (self._crtc[0x0F] or 0)) % math.max(1, self._textCellCount)
	local visibleCell = (cursorCell - textStartCell(self)) % math.max(1, self._textCellCount)
	local screenCells = self.config.TEXT_COLS * self.config.TEXT_ROWS
	if visibleCell < screenCells then
		self._cursorRow = math.floor(visibleCell / self.config.TEXT_COLS)
		self._cursorCol = visibleCell % self.config.TEXT_COLS
	end
end

local function absoluteCellToVisible(self, absoluteCell)
	local startCell = textStartCell(self)
	local visibleCell = (absoluteCell - startCell) % math.max(1, self._textCellCount)
	if visibleCell < 0 or visibleCell >= (self.config.TEXT_COLS * self.config.TEXT_ROWS) then
		return nil
	end
	return visibleCell % self.config.TEXT_COLS, math.floor(visibleCell / self.config.TEXT_COLS)
end

function VgaAdapter:attachBus(bus)
	bus:registerPort(self.config.PORT.VGA_MISC_WRITE, function()
		return self._miscOutput
	end, function(v)
		self._miscOutput = bit32.band(tonumber(v) or 0, 0xFF)
	end, "VGA Misc")
	bus:registerPort(self.config.PORT.VGA_CRTC_INDEX, function()
		return self._crtcIndex
	end, function(v)
		self._crtcIndex = bit32.band(tonumber(v) or 0, 0x1F)
	end, "VGA CRTC Index")
	bus:registerPort(self.config.PORT.VGA_CRTC_DATA, function()
		return self._crtc[self._crtcIndex] or 0
	end, function(v)
		local value = bit32.band(tonumber(v) or 0, 0xFF)
		self._crtc[self._crtcIndex] = value
		if self._crtcIndex == 0x0C or self._crtcIndex == 0x0D then
			markAllCellsDirty(self)
			self._dirty = true
			applyCursorRegisters(self)
		elseif self._crtcIndex == 0x0E or self._crtcIndex == 0x0F then
			markCellDirty(self, self._cursorCol, self._cursorRow)
			applyCursorRegisters(self)
			markCellDirty(self, self._cursorCol, self._cursorRow)
			self._dirty = true
		end
	end, "VGA CRTC Data")
end

--  Bus / VRAM interface

function VgaAdapter:memRead(offset)
	return self._vram[offset] or 0
end

function VgaAdapter:memWrite(offset, value)
	self._vram[offset] = value % 256
	self._dirty = true

	if self.mode == "TEXT" then
		local cellIdx = math.floor(offset / 2)
		if self._textBuf[cellIdx] then
			if offset % 2 == 0 then
				self._textBuf[cellIdx].char = value % 256
			else
				self._textBuf[cellIdx].attr = value % 256
			end
			local visibleCol, visibleRow = absoluteCellToVisible(self, cellIdx)
			if visibleCol ~= nil and visibleRow ~= nil then
				markCellDirty(self, visibleCol, visibleRow)
			end
		end
	else
		-- Pixel mode: 4 bytes per pixel (A R G B at offsets 0 1 2 3)
		local pixIdx = math.floor(offset / 4)
		local comp = offset % 4
		local cur = self._framebuf[pixIdx] or 0xFF000000
		if comp == 0 then
			self._framebuf[pixIdx] = bit32.bor(bit32.band(cur, 0x00FFFFFF), value * 16777216)
		elseif comp == 1 then
			self._framebuf[pixIdx] = bit32.bor(bit32.band(cur, 0xFF00FFFF), value * 65536)
		elseif comp == 2 then
			self._framebuf[pixIdx] = bit32.bor(bit32.band(cur, 0xFFFF00FF), value * 256)
		else
			self._framebuf[pixIdx] = bit32.bor(bit32.band(cur, 0xFFFFFF00), value)
		end
	end
end

--  High-level text API  (called by BIOS / kernel / shell)

function VgaAdapter:setMode(mode)
	self.mode = mode
	self._dirty = true
	if mode == "TEXT" then
		self:clearScreen()
	end
end

function VgaAdapter:clearScreen(attr)
	attr = attr or 0x07
	for i = 0, self._textCellCount - 1 do
		self._textBuf[i] = { char = 32, attr = attr }
		syncCellToVRAM(self, i)
	end
	self._cursorRow = 0
	self._cursorCol = 0
	self._crtc[0x0C] = 0
	self._crtc[0x0D] = 0
	updateCursorRegisters(self)
	self._lastCursor.col = 0
	self._lastCursor.row = 0
	markAllCellsDirty(self)
	self._dirty = true
end

function VgaAdapter:putChar(col, row, ch, attr)
	if col < 0 or col >= self.config.TEXT_COLS then
		return
	end
	if row < 0 or row >= self.config.TEXT_ROWS then
		return
	end
	local idx = (textStartCell(self) + (row * self.config.TEXT_COLS) + col) % math.max(1, self._textCellCount)
	local newChar = (type(ch) == "string") and string.byte(ch, 1) or ch
	local newAttr = attr or 0x07
	local cur = self._textBuf[idx]
	if cur and cur.char == newChar and cur.attr == newAttr then
		return
	end
	self._textBuf[idx] = {
		char = newChar,
		attr = newAttr,
	}
	syncCellToVRAM(self, idx)
	markCellDirty(self, col, row)
	self._dirty = true
	self.stats.textWrites = self.stats.textWrites + 1
end

function VgaAdapter:writeString(col, row, str, attr)
	for i = 1, #str do
		self:putChar(col + i - 1, row, string.byte(str, i), attr)
	end
end

function VgaAdapter:print(str, attr)
	attr = attr or 0x07
	for i = 1, #str do
		local c = string.byte(str, i)
		if c == 10 then
			self._cursorCol = 0
			self._cursorRow = self._cursorRow + 1
		elseif c == 13 then
			self._cursorCol = 0
		elseif c == 8 then
			if self._cursorCol > 0 then
				self._cursorCol = self._cursorCol - 1
				self:putChar(self._cursorCol, self._cursorRow, 32, attr)
			end
		else
			self:putChar(self._cursorCol, self._cursorRow, c, attr)
			self._cursorCol = self._cursorCol + 1
			if self._cursorCol >= self.config.TEXT_COLS then
				self._cursorCol = 0
				self._cursorRow = self._cursorRow + 1
			end
		end
		if self._cursorRow >= self.config.TEXT_ROWS then
			self:_scrollUp()
			self._cursorRow = self.config.TEXT_ROWS - 1
		end
	end
	updateCursorRegisters(self)
	self._dirty = true
end

function VgaAdapter:println(str, attr)
	self:print(str .. "\n", attr)
end

function VgaAdapter:_scrollUp()
	local cols = self.config.TEXT_COLS
	local rows = self.config.TEXT_ROWS
	local startCell = textStartCell(self)
	for row = 0, rows - 2 do
		for col = 0, cols - 1 do
			local dstIdx = (startCell + row * cols + col) % math.max(1, self._textCellCount)
			local srcIdx = (startCell + (row + 1) * cols + col) % math.max(1, self._textCellCount)
			self._textBuf[dstIdx] = table.clone(self._textBuf[srcIdx] or { char = 32, attr = 0x07 })
			syncCellToVRAM(self, dstIdx)
		end
	end
	for col = 0, cols - 1 do
		local idx = (startCell + (rows - 1) * cols + col) % math.max(1, self._textCellCount)
		self._textBuf[idx] = { char = 32, attr = 0x07 }
		syncCellToVRAM(self, idx)
	end
	markAllCellsDirty(self)
end

function VgaAdapter:moveCursor(col, row)
	markCellDirty(self, self._cursorCol, self._cursorRow)
	self._cursorCol = math.max(0, math.min(col, self.config.TEXT_COLS - 1))
	self._cursorRow = math.max(0, math.min(row, self.config.TEXT_ROWS - 1))
	updateCursorRegisters(self)
	markCellDirty(self, self._cursorCol, self._cursorRow)
	self._dirty = true
end

function VgaAdapter:getCursor()
	return self._cursorCol, self._cursorRow
end

function VgaAdapter:toggleCursor()
	markCellDirty(self, self._lastCursor.col, self._lastCursor.row)
	markCellDirty(self, self._cursorCol, self._cursorRow)
	self._cursorVisible = not self._cursorVisible
	self._dirty = true
end

function VgaAdapter:_setPixelRaw(x, y, argb)
	if x < 0 or x >= self.W or y < 0 or y >= self.H then
		return
	end
	self._framebuf[y * self.W + x] = argb
end

--  Pixel API

function VgaAdapter:setPixel(x, y, argb)
	if x < 0 or x >= self.W or y < 0 or y >= self.H then
		return
	end
	self._framebuf[y * self.W + x] = argb
	self._dirty = true
	self.stats.pixelWrites = self.stats.pixelWrites + 1
end

function VgaAdapter:fillRect(x, y, w, h, argb)
	if w <= 0 or h <= 0 then
		return
	end
	local x0 = math.max(0, x)
	local y0 = math.max(0, y)
	local x1 = math.min(self.W - 1, x + w - 1)
	local y1 = math.min(self.H - 1, y + h - 1)
	if x1 < x0 or y1 < y0 then
		return
	end

	local written = 0
	for row = y0, y1 do
		local base = row * self.W
		for col = x0, x1 do
			self._framebuf[base + col] = argb
			written = written + 1
		end
	end
	self.stats.pixelWrites = self.stats.pixelWrites + written
	self._dirty = true
end

function VgaAdapter:drawLine(x0, y0, x1, y1, argb)
	x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
	local dx = math.abs(x1 - x0)
	local dy = -math.abs(y1 - y0)
	local sx = (x0 < x1) and 1 or -1
	local sy = (y0 < y1) and 1 or -1
	local err = dx + dy
	local W = self.W
	local H = self.H
	local fb = self._framebuf
	local written = 0
	while true do
		if x0 >= 0 and x0 < W and y0 >= 0 and y0 < H then
			fb[y0 * W + x0] = argb
			written = written + 1
		end
		if x0 == x1 and y0 == y1 then
			break
		end
		local e2 = err * 2
		if e2 >= dy then
			err = err + dy
			x0 = x0 + sx
		end
		if e2 <= dx then
			err = err + dx
			y0 = y0 + sy
		end
	end
	if written > 0 then
		self.stats.pixelWrites = self.stats.pixelWrites + written
		self._dirty = true
	end
end

function VgaAdapter:drawRect(x, y, w, h, argb, filled)
	if w <= 0 or h <= 0 then
		return
	end
	if filled then
		self:fillRect(x, y, w, h, argb)
		return
	end
	if w == 1 or h == 1 then
		self:fillRect(x, y, w, h, argb)
		return
	end
	self:drawLine(x, y, x + w - 1, y, argb)
	self:drawLine(x, y + h - 1, x + w - 1, y + h - 1, argb)
	self:drawLine(x, y + 1, x, y + h - 2, argb)
	self:drawLine(x + w - 1, y + 1, x + w - 1, y + h - 2, argb)
end

function VgaAdapter:drawText(x, y, text, fgARGB, bgARGB)
	bgARGB = bgARGB or 0x00000000
	for i = 1, #text do
		self:drawChar(x + (i - 1) * self.CW, y, text:sub(i, i), fgARGB, bgARGB)
	end
	self.stats.guiDrawCalls = self.stats.guiDrawCalls + 1
end

function VgaAdapter:drawChar(x, y, ch, fgARGB, bgARGB)
	local code = (type(ch) == "string") and string.byte(ch, 1) or ch
	local glyph = getGlyph(code)
	local written = 0

	-- Clear full cell first so deletes / narrow glyphs do not leave artifacts
	for row = 0, self.CH - 1 do
		local py = y + row
		if py >= 0 and py < self.H then
			local base = py * self.W
			for col = 0, self.CW - 1 do
				local px = x + col
				if px >= 0 and px < self.W then
					self._framebuf[base + px] = bgARGB
					written = written + 1
				end
			end
		end
	end

	local drawW = math.max(1, self.GW)
	local drawH = math.max(1, self.GH)
	for row = 0, drawH - 1 do
		for col = 0, drawW - 1 do
			local px = x + self.PX + col
			local py = y + self.PY + row
			if
				px >= x
				and px < x + self.CW
				and py >= y
				and py < y + self.CH
				and px >= 0
				and px < self.W
				and py >= 0
				and py < self.H
			then
				local coverage
				if self.fontSmoothing then
					local denomW = math.max(1, drawW)
					local denomH = math.max(1, drawH)
					local u0 = ((col + 0.25) / denomW) * 4 - 0.5
					local v0 = ((row + 0.25) / denomH) * 8 - 0.5
					local u1 = ((col + 0.75) / denomW) * 4 - 0.5
					local v1 = ((row + 0.75) / denomH) * 8 - 0.5
					coverage = (
						sampleGlyphSmooth(glyph, u0, v0)
						+ sampleGlyphSmooth(glyph, u1, v0)
						+ sampleGlyphSmooth(glyph, u0, v1)
						+ sampleGlyphSmooth(glyph, u1, v1)
					) * 0.25
				else
					coverage = glyphBit(glyph, math.floor((col / drawW) * 4), math.floor((row / drawH) * 8))
				end
				if coverage > 0 then
					local idx = py * self.W + px
					self._framebuf[idx] = blendARGB(self._framebuf[idx] or bgARGB, fgARGB, math.floor(coverage * 255))
					written = written + 1
				end
			end
		end
	end
	self.stats.pixelWrites = self.stats.pixelWrites + written
	self._dirty = true
end

function VgaAdapter:blitRect(srcX, srcY, w, h, dstX, dstY)
	if w <= 0 or h <= 0 then
		return
	end

	local srcX0 = math.max(0, srcX)
	local srcY0 = math.max(0, srcY)
	local srcX1 = math.min(self.W - 1, srcX + w - 1)
	local srcY1 = math.min(self.H - 1, srcY + h - 1)
	if srcX1 < srcX0 or srcY1 < srcY0 then
		return
	end

	local copyW = srcX1 - srcX0 + 1
	local copyH = srcY1 - srcY0 + 1
	local fb = self._framebuf
	local W = self.W
	local scratch = table.create(copyW * copyH)
	local n = 1
	for row = 0, copyH - 1 do
		local base = (srcY0 + row) * W + srcX0
		for col = 0, copyW - 1 do
			scratch[n] = fb[base + col]
			n = n + 1
		end
	end

	n = 1
	local written = 0
	for row = 0, copyH - 1 do
		local py = dstY + row
		if py >= 0 and py < self.H then
			local base = py * W
			for col = 0, copyW - 1 do
				local px = dstX + col
				local c = scratch[n]
				if px >= 0 and px < self.W and c ~= nil then
					fb[base + px] = c
					written = written + 1
				end
				n = n + 1
			end
		else
			n = n + copyW
		end
	end

	if written > 0 then
		self.stats.pixelWrites = self.stats.pixelWrites + written
		self._dirty = true
	end
end

function VgaAdapter:moveWindow(srcX, srcY, w, h, dstX, dstY, clearARGB)
	self:blitRect(srcX, srcY, w, h, dstX, dstY)
	if clearARGB ~= nil then
		self:fillRect(srcX, srcY, w, h, clearARGB)
	end
end

function VgaAdapter:_packPixelBuffer()
	local fb = self._framebuf
	local pb = self._pixelBuffer
	local W = self.W
	local H = self.H

	local needed = W * H * 4
	if buffer.len(pb) ~= needed then
		pb = buffer.create(needed)
		self._pixelBuffer = pb
	end

	for i = 0, W * H - 1 do
		local argb = fb[i] or 0xFF000000
		local base = i * 4
		local a = math.floor(argb / 16777216) % 256
		local r = math.floor(argb / 65536) % 256
		local g = math.floor(argb / 256) % 256
		local b = argb % 256
		buffer.writeu8(pb, base, r)
		buffer.writeu8(pb, base + 1, g)
		buffer.writeu8(pb, base + 2, b)
		buffer.writeu8(pb, base + 3, a)
	end

	return pb
end

function VgaAdapter:present(presentFn)
	if not self._dirty then
		return
	end

	local now = os.clock()
	if self._nextFrameTime ~= 0 and now < self._nextFrameTime then
		return
	end

	if self.mode == "TEXT" then
		self:_renderText()
	end

	self.stats.flushes = self.stats.flushes + 1

	local pixelBuffer = self:_packPixelBuffer()
	if presentFn then
		presentFn(pixelBuffer, self.W, self.H)
	end

	self._dirty = false
	self._nextFrameTime = now + self._frameInterval
end

function VgaAdapter:getFrame()
	if self.mode == "TEXT" and self._dirty then
		self:_renderText()
	end

	return {
		width = self.W,
		height = self.H,
		buffer = self:_packPixelBuffer(),
	}
end

function VgaAdapter:_renderText()
	local cols = self.config.TEXT_COLS
	local startCell = textStartCell(self)

	for _, idx in ipairs(self._dirtyCellList) do
		local row = math.floor(idx / cols)
		local col = idx % cols
		local absoluteIdx = (startCell + idx) % math.max(1, self._textCellCount)
		local cell = self._textBuf[absoluteIdx] or { char = 32, attr = 0x07 }
		local fg = PALETTE[cell.attr % 16] or 0xFFAAAAAA
		local bg = PALETTE[math.floor(cell.attr / 16) % 16] or 0xFF000000
		self:drawChar(col * self.CW, row * self.CH, cell.char, fg, bg)
		self._dirtyCells[idx] = nil
	end
	self._dirtyCellList = {}

	markCellDirty(self, self._lastCursor.col, self._lastCursor.row)
	local cursorDisabled = bit32.band(self._crtc[0x0A] or 0, 0x20) ~= 0
	if self._cursorVisible and not cursorDisabled then
		local cx = self._cursorCol * self.CW
		local cy = self._cursorRow * self.CH + (self.CH - 1)
		for i = 0, self.CW - 1 do
			self:_setPixelRaw(cx + i, cy, 0xFFAAAAAA)
		end
		self.stats.pixelWrites = self.stats.pixelWrites + self.CW
	end
	self._lastCursor.col = self._cursorCol
	self._lastCursor.row = self._cursorRow
end

function VgaAdapter:getStats()
	return self.stats
end
VgaAdapter.PALETTE = PALETTE

return VgaAdapter