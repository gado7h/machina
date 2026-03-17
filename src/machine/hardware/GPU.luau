-- GPU module

local GPU = {}
GPU.__index = GPU

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

-- 8×8 bitmap font (ASCII 32-126), adapted from the richer NEXT renderer font.
-- Each glyph is 8 bytes; each byte is one scanline with bits 7..0 = columns 0..7.
local FONT_GLYPH_W = 8
local FONT_GLYPH_H = 8

local FONT = {}
local function F(...)
	return { ... }
end

FONT[32] = F(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
FONT[33] = F(0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x18, 0x00)
FONT[34] = F(0x6C, 0x6C, 0x48, 0x00, 0x00, 0x00, 0x00, 0x00)
FONT[35] = F(0x36, 0x36, 0x7F, 0x36, 0x7F, 0x36, 0x36, 0x00)
FONT[36] = F(0x0C, 0x3E, 0x03, 0x1E, 0x30, 0x1F, 0x06, 0x00)
FONT[37] = F(0x63, 0x33, 0x18, 0x0C, 0x06, 0x33, 0x31, 0x00)
FONT[38] = F(0x1C, 0x36, 0x1C, 0x6E, 0x3B, 0x33, 0x6E, 0x00)
FONT[39] = F(0x18, 0x18, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00)
FONT[40] = F(0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x18, 0x30, 0x00)
FONT[41] = F(0x0C, 0x18, 0x30, 0x30, 0x30, 0x18, 0x0C, 0x00)
FONT[42] = F(0x00, 0x66, 0x3C, 0x7E, 0x3C, 0x66, 0x00, 0x00)
FONT[43] = F(0x00, 0x18, 0x18, 0x7E, 0x18, 0x18, 0x00, 0x00)
FONT[44] = F(0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x0C)
FONT[45] = F(0x00, 0x00, 0x00, 0x7E, 0x00, 0x00, 0x00, 0x00)
FONT[46] = F(0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x00)
FONT[47] = F(0x60, 0x30, 0x18, 0x0C, 0x06, 0x03, 0x01, 0x00)
for i, rows in ipairs({
	F(0x3E, 0x63, 0x73, 0x7B, 0x6F, 0x67, 0x3E, 0x00),
	F(0x0C, 0x0E, 0x0C, 0x0C, 0x0C, 0x0C, 0x3F, 0x00),
	F(0x1E, 0x33, 0x30, 0x1C, 0x06, 0x33, 0x3F, 0x00),
	F(0x1E, 0x33, 0x30, 0x1C, 0x30, 0x33, 0x1E, 0x00),
	F(0x38, 0x3C, 0x36, 0x33, 0x7F, 0x30, 0x78, 0x00),
	F(0x3F, 0x03, 0x1F, 0x30, 0x30, 0x33, 0x1E, 0x00),
	F(0x1C, 0x06, 0x03, 0x1F, 0x33, 0x33, 0x1E, 0x00),
	F(0x3F, 0x33, 0x30, 0x18, 0x0C, 0x0C, 0x0C, 0x00),
	F(0x1E, 0x33, 0x33, 0x1E, 0x33, 0x33, 0x1E, 0x00),
	F(0x1E, 0x33, 0x33, 0x3E, 0x30, 0x18, 0x0E, 0x00),
}) do
	FONT[48 + i - 1] = rows
end
FONT[58] = F(0x00, 0x18, 0x18, 0x00, 0x18, 0x18, 0x00, 0x00)
FONT[59] = F(0x00, 0x18, 0x18, 0x00, 0x18, 0x18, 0x0C, 0x00)
FONT[60] = F(0x30, 0x18, 0x0C, 0x06, 0x0C, 0x18, 0x30, 0x00)
FONT[61] = F(0x00, 0x00, 0x7E, 0x00, 0x7E, 0x00, 0x00, 0x00)
FONT[62] = F(0x06, 0x0C, 0x18, 0x30, 0x18, 0x0C, 0x06, 0x00)
FONT[63] = F(0x1E, 0x33, 0x30, 0x18, 0x0C, 0x00, 0x0C, 0x00)
FONT[64] = F(0x3E, 0x63, 0x7B, 0x7B, 0x7B, 0x03, 0x1E, 0x00)
for i, rows in ipairs({
	F(0x0C, 0x1E, 0x33, 0x33, 0x3F, 0x33, 0x33, 0x00),
	F(0x3F, 0x66, 0x66, 0x3E, 0x66, 0x66, 0x3F, 0x00),
	F(0x3C, 0x66, 0x03, 0x03, 0x03, 0x66, 0x3C, 0x00),
	F(0x1F, 0x36, 0x66, 0x66, 0x66, 0x36, 0x1F, 0x00),
	F(0x7F, 0x46, 0x16, 0x1E, 0x16, 0x46, 0x7F, 0x00),
	F(0x7F, 0x46, 0x16, 0x1E, 0x16, 0x06, 0x0F, 0x00),
	F(0x3C, 0x66, 0x03, 0x03, 0x73, 0x66, 0x7C, 0x00),
	F(0x33, 0x33, 0x33, 0x3F, 0x33, 0x33, 0x33, 0x00),
	F(0x1E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00),
	F(0x78, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1E, 0x00),
	F(0x67, 0x66, 0x36, 0x1E, 0x36, 0x66, 0x67, 0x00),
	F(0x0F, 0x06, 0x06, 0x06, 0x46, 0x66, 0x7F, 0x00),
	F(0x63, 0x77, 0x7F, 0x7F, 0x6B, 0x63, 0x63, 0x00),
	F(0x63, 0x67, 0x6F, 0x7B, 0x73, 0x63, 0x63, 0x00),
	F(0x1C, 0x36, 0x63, 0x63, 0x63, 0x36, 0x1C, 0x00),
	F(0x3F, 0x66, 0x66, 0x3E, 0x06, 0x06, 0x0F, 0x00),
	F(0x1E, 0x33, 0x33, 0x33, 0x3B, 0x1E, 0x38, 0x00),
	F(0x3F, 0x66, 0x66, 0x3E, 0x36, 0x66, 0x67, 0x00),
	F(0x1E, 0x33, 0x07, 0x0E, 0x38, 0x33, 0x1E, 0x00),
	F(0x3F, 0x2D, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00),
	F(0x33, 0x33, 0x33, 0x33, 0x33, 0x33, 0x3F, 0x00),
	F(0x33, 0x33, 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x00),
	F(0x63, 0x63, 0x63, 0x6B, 0x7F, 0x77, 0x63, 0x00),
	F(0x63, 0x63, 0x36, 0x1C, 0x1C, 0x36, 0x63, 0x00),
	F(0x33, 0x33, 0x33, 0x1E, 0x0C, 0x0C, 0x1E, 0x00),
	F(0x7F, 0x63, 0x31, 0x18, 0x4C, 0x66, 0x7F, 0x00),
}) do
	FONT[65 + i - 1] = rows
end
for i, rows in ipairs({
	F(0x00, 0x00, 0x1E, 0x30, 0x3E, 0x33, 0x6E, 0x00),
	F(0x07, 0x06, 0x06, 0x3E, 0x66, 0x66, 0x3B, 0x00),
	F(0x00, 0x00, 0x1E, 0x33, 0x03, 0x33, 0x1E, 0x00),
	F(0x38, 0x30, 0x30, 0x3E, 0x33, 0x33, 0x6E, 0x00),
	F(0x00, 0x00, 0x1E, 0x33, 0x3F, 0x03, 0x1E, 0x00),
	F(0x1C, 0x36, 0x06, 0x0F, 0x06, 0x06, 0x0F, 0x00),
	F(0x00, 0x00, 0x6E, 0x33, 0x33, 0x3E, 0x30, 0x1F),
	F(0x07, 0x06, 0x36, 0x6E, 0x66, 0x66, 0x67, 0x00),
	F(0x0C, 0x00, 0x0E, 0x0C, 0x0C, 0x0C, 0x1E, 0x00),
	F(0x30, 0x00, 0x30, 0x30, 0x30, 0x33, 0x33, 0x1E),
	F(0x07, 0x06, 0x66, 0x36, 0x1E, 0x36, 0x67, 0x00),
	F(0x0E, 0x0C, 0x0C, 0x0C, 0x0C, 0x0C, 0x1E, 0x00),
	F(0x00, 0x00, 0x33, 0x7F, 0x7F, 0x6B, 0x63, 0x00),
	F(0x00, 0x00, 0x1F, 0x33, 0x33, 0x33, 0x33, 0x00),
	F(0x00, 0x00, 0x1E, 0x33, 0x33, 0x33, 0x1E, 0x00),
	F(0x00, 0x00, 0x3B, 0x66, 0x66, 0x3E, 0x06, 0x0F),
	F(0x00, 0x00, 0x6E, 0x33, 0x33, 0x3E, 0x30, 0x78),
	F(0x00, 0x00, 0x3B, 0x6E, 0x66, 0x06, 0x0F, 0x00),
	F(0x00, 0x00, 0x3E, 0x03, 0x1E, 0x30, 0x1F, 0x00),
	F(0x08, 0x0C, 0x3E, 0x0C, 0x0C, 0x2C, 0x18, 0x00),
	F(0x00, 0x00, 0x33, 0x33, 0x33, 0x33, 0x6E, 0x00),
	F(0x00, 0x00, 0x33, 0x33, 0x33, 0x1E, 0x0C, 0x00),
	F(0x00, 0x00, 0x63, 0x6B, 0x7F, 0x7F, 0x36, 0x00),
	F(0x00, 0x00, 0x63, 0x36, 0x1C, 0x36, 0x63, 0x00),
	F(0x00, 0x00, 0x33, 0x33, 0x33, 0x3E, 0x30, 0x1F),
	F(0x00, 0x00, 0x3F, 0x19, 0x0C, 0x26, 0x3F, 0x00),
}) do
	FONT[97 + i - 1] = rows
end

for ch = 32, 126 do
	if not FONT[ch] then
		FONT[ch] = F(0x3C, 0x42, 0x81, 0x81, 0x81, 0x42, 0x3C, 0x00)
	end
end

local GLYPH_DEFAULT = F(0x3C, 0x42, 0x81, 0x81, 0x81, 0x42, 0x3C, 0x00)
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
	return packARGB(255, math.floor(lerp(br, fr, t) + 0.5), math.floor(lerp(bgc, fgc, t) + 0.5), math.floor(lerp(bb, fb, t) + 0.5))
end

local function glyphBit(glyph, gx, gy)
	if gx < 0 or gx >= FONT_GLYPH_W or gy < 0 or gy >= FONT_GLYPH_H then
		return 0
	end
	local bits = glyph[gy + 1] or 0
	local mask = 2 ^ ((FONT_GLYPH_W - 1) - gx)
	return (bits % (mask * 2)) >= mask and 1 or 0
end

local function sampleGlyphSmooth(glyph, u, v)
	local x = clamp(u, 0, FONT_GLYPH_W - 1)
	local y = clamp(v, 0, FONT_GLYPH_H - 1)
	local x0 = math.floor(x)
	local y0 = math.floor(y)
	local x1 = math.min(FONT_GLYPH_W - 1, x0 + 1)
	local y1 = math.min(FONT_GLYPH_H - 1, y0 + 1)
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

function GPU.new(config, editableImage)
	local self = setmetatable({}, GPU)
	self.config = config
	self.editableImage = editableImage -- nil = headless/test mode

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

	-- Text buffer: flat array [0 .. COLS*ROWS-1], each entry {char, attr}
	self._textBuf = {}
	for i = 0, config.TEXT_COLS * config.TEXT_ROWS - 1 do
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

	-- Native buffer for WritePixelsBuffer — allocated once, reused every frame.
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

--  Bus / VRAM interface

function GPU:memRead(offset)
	return self._vram[offset] or 0
end

function GPU:memWrite(offset, value)
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

function GPU:setMode(mode)
	self.mode = mode
	self._dirty = true
	if mode == "TEXT" then
		self:clearScreen()
	end
end

function GPU:clearScreen(attr)
	attr = attr or 0x07
	for i = 0, self.config.TEXT_COLS * self.config.TEXT_ROWS - 1 do
		self._textBuf[i] = { char = 32, attr = attr }
	end
	self._cursorRow = 0
	self._cursorCol = 0
	self._lastCursor.col = 0
	self._lastCursor.row = 0
	markAllCellsDirty(self)
	self._dirty = true
end

function GPU:putChar(col, row, ch, attr)
	if col < 0 or col >= self.config.TEXT_COLS then
		return
	end
	if row < 0 or row >= self.config.TEXT_ROWS then
		return
	end
	local idx = row * self.config.TEXT_COLS + col
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
	markCellDirty(self, col, row)
	self._dirty = true
	self.stats.textWrites = self.stats.textWrites + 1
end

function GPU:writeString(col, row, str, attr)
	for i = 1, #str do
		self:putChar(col + i - 1, row, string.byte(str, i), attr)
	end
end

function GPU:print(str, attr)
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
	self._dirty = true
end

function GPU:println(str, attr)
	self:print(str .. "\n", attr)
end

function GPU:_scrollUp()
	local cols = self.config.TEXT_COLS
	local rows = self.config.TEXT_ROWS
	for row = 0, rows - 2 do
		for col = 0, cols - 1 do
			self._textBuf[row * cols + col] = self._textBuf[(row + 1) * cols + col] or { char = 32, attr = 0x07 }
		end
	end
	for col = 0, cols - 1 do
		self._textBuf[(rows - 1) * cols + col] = { char = 32, attr = 0x07 }
	end
	markAllCellsDirty(self)
end

function GPU:moveCursor(col, row)
	markCellDirty(self, self._cursorCol, self._cursorRow)
	self._cursorCol = math.max(0, math.min(col, self.config.TEXT_COLS - 1))
	self._cursorRow = math.max(0, math.min(row, self.config.TEXT_ROWS - 1))
	markCellDirty(self, self._cursorCol, self._cursorRow)
	self._dirty = true
end

function GPU:getCursor()
	return self._cursorCol, self._cursorRow
end

function GPU:toggleCursor()
	markCellDirty(self, self._lastCursor.col, self._lastCursor.row)
	markCellDirty(self, self._cursorCol, self._cursorRow)
	self._cursorVisible = not self._cursorVisible
	self._dirty = true
end


function GPU:_setPixelRaw(x, y, argb)
	if x < 0 or x >= self.W or y < 0 or y >= self.H then
		return
	end
	self._framebuf[y * self.W + x] = argb
end

--  Pixel API

function GPU:setPixel(x, y, argb)
	if x < 0 or x >= self.W or y < 0 or y >= self.H then
		return
	end
	self._framebuf[y * self.W + x] = argb
	self._dirty = true
	self.stats.pixelWrites = self.stats.pixelWrites + 1
end

function GPU:fillRect(x, y, w, h, argb)
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

function GPU:drawLine(x0, y0, x1, y1, argb)
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

function GPU:drawRect(x, y, w, h, argb, filled)
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

function GPU:drawText(x, y, text, fgARGB, bgARGB)
	bgARGB = bgARGB or 0x00000000
	for i = 1, #text do
		self:drawChar(x + (i - 1) * self.CW, y, text:sub(i, i), fgARGB, bgARGB)
	end
	self.stats.guiDrawCalls = self.stats.guiDrawCalls + 1
end

function GPU:drawChar(x, y, ch, fgARGB, bgARGB)
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
			if px >= x and px < x + self.CW and py >= y and py < y + self.CH and px >= 0 and px < self.W and py >= 0 and py < self.H then
				local coverage
				if self.fontSmoothing then
					local denomW = math.max(1, drawW)
					local denomH = math.max(1, drawH)
					local u0 = ((col + 0.25) / denomW) * FONT_GLYPH_W - 0.5
					local v0 = ((row + 0.25) / denomH) * FONT_GLYPH_H - 0.5
					local u1 = ((col + 0.75) / denomW) * FONT_GLYPH_W - 0.5
					local v1 = ((row + 0.75) / denomH) * FONT_GLYPH_H - 0.5
					coverage = (sampleGlyphSmooth(glyph, u0, v0) + sampleGlyphSmooth(glyph, u1, v0) + sampleGlyphSmooth(glyph, u0, v1) + sampleGlyphSmooth(glyph, u1, v1)) * 0.25
				else
					coverage = glyphBit(glyph, math.floor((col / drawW) * FONT_GLYPH_W), math.floor((row / drawH) * FONT_GLYPH_H))
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

function GPU:blitRect(srcX, srcY, w, h, dstX, dstY)
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

function GPU:moveWindow(srcX, srcY, w, h, dstX, dstY, clearARGB)
	self:blitRect(srcX, srcY, w, h, dstX, dstY)
	if clearARGB ~= nil then
		self:fillRect(srcX, srcY, w, h, clearARGB)
	end
end

--  Flush to EditableImage via WritePixelsBuffer
--
--  WritePixelsBuffer takes a native Luau buffer (RGBA u8, row-major).
--  This is ~10× faster than WritePixels(table) because it avoids
--  allocating and iterating a 64k-entry Lua table on every frame.

function GPU:flush()
	if not self._dirty then
		return
	end

	local now = os.clock()
	if self._nextFrameTime ~= 0 and now < self._nextFrameTime then
		return
	end

	if not self.editableImage then
		self._dirty = false
		self._nextFrameTime = now + self._frameInterval
		return
	end

	if self.mode == "TEXT" then
		self:_renderText()
	end

	self.stats.flushes = self.stats.flushes + 1

	local fb = self._framebuf
	local pb = self._pixelBuffer
	local W = self.W
	local H = self.H

	-- Ensure buffer is the right size (handles reboot/resize edge cases)
	local needed = W * H * 4
	if buffer.len(pb) ~= needed then
		pb = buffer.create(needed)
		self._pixelBuffer = pb
	end

	-- Pack ARGB integer → RGBA bytes into native buffer
	for i = 0, W * H - 1 do
		local argb = fb[i] or 0xFF000000
		local base = i * 4
		-- Arithmetic unpack (avoids bit32 overhead in tight loop)
		local a = math.floor(argb / 16777216) % 256
		local r = math.floor(argb / 65536) % 256
		local g = math.floor(argb / 256) % 256
		local b = argb % 256
		buffer.writeu8(pb, base, r)
		buffer.writeu8(pb, base + 1, g)
		buffer.writeu8(pb, base + 2, b)
		buffer.writeu8(pb, base + 3, a)
	end

	local ok, err = pcall(function()
		self.editableImage:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), pb)
	end)
	if not ok then
		warn("GPU:flush WritePixelsBuffer failed:", err)
	end

	self._dirty = false
	self._nextFrameTime = now + self._frameInterval
end

function GPU:_renderText()
	local cols = self.config.TEXT_COLS

	for _, idx in ipairs(self._dirtyCellList) do
		local row = math.floor(idx / cols)
		local col = idx % cols
		local cell = self._textBuf[idx] or { char = 32, attr = 0x07 }
		local fg = PALETTE[cell.attr % 16] or 0xFFAAAAAA
		local bg = PALETTE[math.floor(cell.attr / 16) % 16] or 0xFF000000
		self:drawChar(col * self.CW, row * self.CH, cell.char, fg, bg)
		self._dirtyCells[idx] = nil
	end
	self._dirtyCellList = {}

	markCellDirty(self, self._lastCursor.col, self._lastCursor.row)
	if self._cursorVisible then
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

function GPU:getStats()
	return self.stats
end
GPU.PALETTE = PALETTE

return GPU
