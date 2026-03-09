-- NovaMachine/kernel/VFS.lua
-- NovaFS — Virtual Filesystem (ext2-inspired).
--
-- Disk layout from partition start (all offsets in sectors):
--   Sector 0      : Superblock (512 bytes)
--   Sector 1-8    : Block group descriptor table
--   Sector 9-40   : Block allocation bitmap (1 bit per block)
--   Sector 41-296 : Inode table (128 bytes per inode, 4 inodes/sector)
--   Sector 297+   : Data blocks (512 bytes each)
--
-- Inode structure (128 bytes):
--   [0-3]   mode       (type + permissions)
--   [4-7]   uid
--   [8-11]  size (bytes)
--   [12-15] atime
--   [16-19] mtime
--   [20-23] ctime
--   [24-27] links_count
--   [28-31] blocks     (number of 512-byte blocks used)
--   [32-63] direct block pointers (8 × 4B)
--   [64-67] single-indirect block pointer
--   [68-71] double-indirect block pointer
--   [72-127] reserved / extended attributes
--
-- Directory entry (variable length, 32-byte minimum):
--   [0-3]   inode number
--   [4-5]   rec_len
--   [6]     name_len
--   [7]     file_type (1=regular, 2=dir, 7=symlink)
--   [8+]    name bytes

local VFS = {}
VFS.__index = VFS

local SECTOR_SIZE = 512
local INODE_SIZE = 128
local INODES_PER_SECTOR = 4
local DIRENT_FIXED = 8 -- fixed header before name

-- Superblock offsets
local SB_MAGIC_OFF = 0 -- 8 bytes: "NOVAFS1\0"
local SB_TOTAL_BLOCKS = 8
local SB_FREE_BLOCKS = 12
local SB_TOTAL_INODES = 16
local SB_FREE_INODES = 20
local SB_INODE_TABLE_SEC = 24 -- sector of inode table start
local SB_DATA_START_SEC = 28 -- sector of first data block
local SB_BLOCK_SIZE = 32 -- bytes
local SB_STATE = 36 -- 1=clean, 2=errors
local SB_MTIME = 40

-- Sector layout within partition
local SEC_SUPERBLOCK = 0
local SEC_BITMAP_START = 9
local SEC_BITMAP_COUNT = 32
local SEC_INODE_START = 41
local SEC_INODE_COUNT = 256 -- 256 sectors = 1024 inodes max
local SEC_DATA_START = 297

local MAX_INODES = SEC_INODE_COUNT * INODES_PER_SECTOR -- 1024
local DIRECT_BLOCKS = 8

-- File type flags in mode
local S_IFREG = 0x8000
local S_IFDIR = 0x4000
local S_IFLNK = 0xA000
local S_IRWXU = 0x01C0
local S_IRWXG = 0x0038
local S_IRWXO = 0x0007

-- ────────────────────────────────────────────
function VFS.new(hdd, partStartLBA, config)
	local self = setmetatable({}, VFS)
	self.hdd = hdd
	self.partStart = partStartLBA
	self.config = config
	self._mounted = false
	self._superblock = nil
	self._inodeCache = {} -- ino → inode table
	self._dirCache = {} -- path → {name→ino}
	return self
end

-- ────────────────────────────────────────────
--  Low-level sector I/O (relative to partition)
-- ────────────────────────────────────────────

function VFS:_readSec(relSec)
	return self.hdd:readSector(self.partStart + relSec)
end

function VFS:_writeSec(relSec, data)
	return self.hdd:writeSector(self.partStart + relSec, data)
end

local function sec2Bytes(sector) -- copy 512-byte sector to mutable table
	local t = {}
	for i = 1, SECTOR_SIZE do
		t[i] = sector[i] or 0
	end
	return t
end

local function readU32(sec, off) -- 1-based offset
	return (sec[off] or 0) + (sec[off + 1] or 0) * 256 + (sec[off + 2] or 0) * 65536 + (sec[off + 3] or 0) * 16777216
end

local function writeU32(sec, off, v)
	sec[off] = v % 256
	sec[off + 1] = math.floor(v / 256) % 256
	sec[off + 2] = math.floor(v / 65536) % 256
	sec[off + 3] = math.floor(v / 16777216) % 256
end

local function readU16(sec, off)
	return (sec[off] or 0) + (sec[off + 1] or 0) * 256
end

local function writeU16(sec, off, v)
	sec[off] = v % 256
	sec[off + 1] = math.floor(v / 256) % 256
end

local function readStr(sec, off, len)
	local chars = {}
	for i = off, off + len - 1 do
		local b = sec[i] or 0
		if b == 0 then
			break
		end
		table.insert(chars, string.char(b))
	end
	return table.concat(chars)
end

local function writeStr(sec, off, str, fieldLen)
	for i = 1, fieldLen or #str do
		sec[off + i - 1] = (i <= #str) and string.byte(str, i) or 0
	end
end

local function now()
	return os.time and os.time() or 0
end

-- ────────────────────────────────────────────
--  Format (create fresh filesystem)
-- ────────────────────────────────────────────

function VFS:format()
	-- Write superblock
	local sb = {}
	for i = 1, SECTOR_SIZE do
		sb[i] = 0
	end
	writeStr(sb, 1, self.config.FS_MAGIC, 8) -- magic "NOVAFS1\0"
	writeU32(sb, SB_TOTAL_BLOCKS + 1, self.hdd:getTotalSectors() - self.partStart - SEC_DATA_START)
	writeU32(sb, SB_FREE_BLOCKS + 1, self.hdd:getTotalSectors() - self.partStart - SEC_DATA_START - 2)
	writeU32(sb, SB_TOTAL_INODES + 1, MAX_INODES)
	writeU32(sb, SB_FREE_INODES + 1, MAX_INODES - 1) -- inode 1 = root
	writeU32(sb, SB_INODE_TABLE_SEC + 1, SEC_INODE_START)
	writeU32(sb, SB_DATA_START_SEC + 1, SEC_DATA_START)
	writeU32(sb, SB_BLOCK_SIZE + 1, SECTOR_SIZE)
	sb[SB_STATE + 1] = 1 -- clean
	writeU32(sb, SB_MTIME + 1, now())
	self:_writeSec(SEC_SUPERBLOCK, sb)

	-- Clear block bitmap (sectors SEC_BITMAP_START to SEC_BITMAP_START+SEC_BITMAP_COUNT-1)
	local blank = {}
	for i = 1, SECTOR_SIZE do
		blank[i] = 0
	end
	for i = 0, SEC_BITMAP_COUNT - 1 do
		self:_writeSec(SEC_BITMAP_START + i, blank)
	end

	-- Reserve block 0 as null / unused sentinel
	self:_setBitmapBit(0, true)

	-- Use block 1 for the root directory
	self:_setBitmapBit(1, true)

	-- Clear inode table
	for i = 0, SEC_INODE_COUNT - 1 do
		self:_writeSec(SEC_INODE_START + i, blank)
	end

	-- Create root inode (inode 1)
	self:_writeInode(1, {
		mode = bit32.bor(S_IFDIR, 0x1ED), -- drwxr-xr-x
		uid = 0,
		size = SECTOR_SIZE,
		atime = now(),
		mtime = now(),
		ctime = now(),
		links = 2,
		blocks = 1,
		blockPtrs = { 1, 0, 0, 0, 0, 0, 0, 0 },
		iblock1 = 0,
		iblock2 = 0,
	})

	-- Write root directory entries (. and ..)
	local dirData = self:_makeDirBlock({
		{ ino = 1, name = ".", ftype = 2 },
		{ ino = 1, name = "..", ftype = 2 },
	})
	self:_writeDataBlock(1, dirData)

	self._mounted = false
	return true
end

-- ────────────────────────────────────────────
--  Mount
-- ────────────────────────────────────────────

function VFS:mount()
	local sb = self:_readSec(SEC_SUPERBLOCK)
	local magic = readStr(sb, 1, 8)
	local expected = self.config.FS_MAGIC
	if magic ~= expected then
		return false, "Bad magic: got '" .. tostring(magic) .. "', expected '" .. tostring(expected) .. "'"
	end
	self._superblock = {
		totalBlocks = readU32(sb, SB_TOTAL_BLOCKS + 1),
		freeBlocks = readU32(sb, SB_FREE_BLOCKS + 1),
		totalInodes = readU32(sb, SB_TOTAL_INODES + 1),
		freeInodes = readU32(sb, SB_FREE_INODES + 1),
		inodeTableSec = readU32(sb, SB_INODE_TABLE_SEC + 1),
		dataStartSec = readU32(sb, SB_DATA_START_SEC + 1),
		blockSize = readU32(sb, SB_BLOCK_SIZE + 1),
		state = sb[SB_STATE + 1],
	}
	self._mounted = true
	self._dirCache = {}
	return true
end

function VFS:getMagic()
	return self.config.FS_MAGIC
end
function VFS:getInodeCount()
	return self._superblock and self._superblock.totalInodes or 0
end
function VFS:isMounted()
	return self._mounted
end

-- ────────────────────────────────────────────
--  Inode table
-- ────────────────────────────────────────────

function VFS:_readInode(ino)
	if self._inodeCache[ino] then
		return self._inodeCache[ino]
	end
	local sec = SEC_INODE_START + math.floor((ino - 1) / INODES_PER_SECTOR)
	local off = ((ino - 1) % INODES_PER_SECTOR) * INODE_SIZE
	local s = self:_readSec(sec)
	local base = off + 1

	local ptrs = {}
	for i = 0, DIRECT_BLOCKS - 1 do
		ptrs[i + 1] = readU32(s, base + 32 + i * 4)
	end

	local inode = {
		ino = ino,
		mode = readU32(s, base + 0),
		uid = readU32(s, base + 4),
		size = readU32(s, base + 8),
		atime = readU32(s, base + 12),
		mtime = readU32(s, base + 16),
		ctime = readU32(s, base + 20),
		links = readU32(s, base + 24),
		blocks = readU32(s, base + 28),
		blockPtrs = ptrs,
		iblock1 = readU32(s, base + 64),
		iblock2 = readU32(s, base + 68),
	}
	self._inodeCache[ino] = inode
	return inode
end

function VFS:_writeInode(ino, inode)
	self._inodeCache[ino] = inode
	local sec = SEC_INODE_START + math.floor((ino - 1) / INODES_PER_SECTOR)
	local off = ((ino - 1) % INODES_PER_SECTOR) * INODE_SIZE
	local s = sec2Bytes(self:_readSec(sec))
	local base = off + 1

	writeU32(s, base + 0, inode.mode or 0)
	writeU32(s, base + 4, inode.uid or 0)
	writeU32(s, base + 8, inode.size or 0)
	writeU32(s, base + 12, inode.atime or 0)
	writeU32(s, base + 16, inode.mtime or 0)
	writeU32(s, base + 20, inode.ctime or 0)
	writeU32(s, base + 24, inode.links or 0)
	writeU32(s, base + 28, inode.blocks or 0)
	for i = 0, DIRECT_BLOCKS - 1 do
		writeU32(s, base + 32 + i * 4, (inode.blockPtrs and inode.blockPtrs[i + 1]) or 0)
	end
	writeU32(s, base + 64, inode.iblock1 or 0)
	writeU32(s, base + 68, inode.iblock2 or 0)
	self:_writeSec(sec, s)
end

-- ────────────────────────────────────────────
--  Block allocation
-- ────────────────────────────────────────────

function VFS:_setBitmapBit(blockIdx, used)
	local byteOff = math.floor(blockIdx / 8)
	local bitOff = blockIdx % 8
	local secOff = math.floor(byteOff / SECTOR_SIZE)
	local byteIn = byteOff % SECTOR_SIZE
	local s = sec2Bytes(self:_readSec(SEC_BITMAP_START + secOff))
	if used then
		s[byteIn + 1] = bit32.bor(s[byteIn + 1], (2 ^ bitOff))
	else
		s[byteIn + 1] = bit32.band(s[byteIn + 1], bit32.bnot(2 ^ bitOff) % 256)
	end
	self:_writeSec(SEC_BITMAP_START + secOff, s)
end

function VFS:_isBitmapBit(blockIdx)
	local byteOff = math.floor(blockIdx / 8)
	local bitOff = blockIdx % 8
	local secOff = math.floor(byteOff / SECTOR_SIZE)
	local byteIn = byteOff % SECTOR_SIZE
	local s = self:_readSec(SEC_BITMAP_START + secOff)
	return (bit32.band((s[byteIn + 1] or 0), (2 ^ bitOff))) ~= 0
end

function VFS:_allocBlock()
	local total = self._superblock and self._superblock.totalBlocks or 1000
	for i = 0, total - 1 do
		if not self:_isBitmapBit(i) then
			self:_setBitmapBit(i, true)
			if self._superblock then
				self._superblock.freeBlocks = self._superblock.freeBlocks - 1
			end
			return i
		end
	end
	return nil -- disk full
end

function VFS:_freeBlock(blockIdx)
	self:_setBitmapBit(blockIdx, false)
	if self._superblock then
		self._superblock.freeBlocks = self._superblock.freeBlocks + 1
	end
end

function VFS:_readDataBlock(blockIdx)
	return self:_readSec(SEC_DATA_START + blockIdx)
end

function VFS:_writeDataBlock(blockIdx, data)
	local s = {}
	for i = 1, SECTOR_SIZE do
		s[i] = data[i] or 0
	end
	self:_writeSec(SEC_DATA_START + blockIdx, s)
end

-- ────────────────────────────────────────────
--  Inode allocation
-- ────────────────────────────────────────────

function VFS:_allocInode()
	for ino = 2, MAX_INODES do
		local inode = self:_readInode(ino)
		if inode.mode == 0 then
			if self._superblock then
				self._superblock.freeInodes = self._superblock.freeInodes - 1
			end
			return ino
		end
	end
	return nil -- no free inodes
end

-- ────────────────────────────────────────────
--  Path resolution
-- ────────────────────────────────────────────

function VFS:_resolvePath(path)
	if path == "/" then
		return 1, 0, "/"
	end

	if path:sub(1, 1) ~= "/" then
		path = "/" .. path
	end
	while #path > 1 and path:sub(-1) == "/" do
		path = path:sub(1, -2)
	end

	local parts = {}
	for part in path:gmatch("[^/]+") do
		table.insert(parts, part)
	end

	local curIno = 1
	local parIno = 0

	for i, part in ipairs(parts) do
		local entries = self:_readDir(curIno)
		if not entries then
			return nil, nil, nil
		end

		local found = false
		for _, e in ipairs(entries) do
			if e.name == part then
				parIno = curIno
				curIno = e.ino
				found = true
				break
			end
		end

		if not found then
			if i == #parts then
				return nil, curIno, part
			end
			return nil, nil, nil
		end
	end

	return curIno, parIno, parts[#parts] or "/"
end

-- ────────────────────────────────────────────
--  Directory operations
-- ────────────────────────────────────────────

function VFS:_readDir(dirIno)
	local inode = self:_readInode(dirIno)
	if not inode or (bit32.band(inode.mode, 0xF000)) ~= S_IFDIR then
		return nil
	end

	local entries = {}
	for _, bptr in ipairs(inode.blockPtrs) do
		if bptr == 0 then
			break
		end
		local block = self:_readDataBlock(bptr)
		local off = 1
		while off + DIRENT_FIXED <= SECTOR_SIZE do
			local ino = readU32(block, off)
			local recLen = readU16(block, off + 4)
			local nameLen = block[off + 6] or 0
			local ftype = block[off + 7] or 0
			if ino == 0 or recLen == 0 then
				break
			end
			local name = readStr(block, off + DIRENT_FIXED, nameLen)
			table.insert(entries, { ino = ino, name = name, ftype = ftype, recLen = recLen })
			off = off + recLen
		end
	end
	return entries
end

function VFS:_addDirEntry(dirIno, newIno, name, ftype)
	local inode = self:_readInode(dirIno)
	local recLen = DIRENT_FIXED + #name
	-- round up to 4-byte alignment
	if recLen % 4 ~= 0 then
		recLen = recLen + (4 - recLen % 4)
	end

	-- Try to append to existing block
	local block = nil
	local blockIdx = nil
	local written = false

	for i, bptr in ipairs(inode.blockPtrs) do
		if bptr ~= 0 then
			block = sec2Bytes(self:_readDataBlock(bptr))
			blockIdx = bptr
			-- Find free space in this block
			local off = 1
			while off + DIRENT_FIXED <= SECTOR_SIZE do
				local ino = readU32(block, off)
				local rlen = readU16(block, off + 4)
				local nlen = block[off + 6] or 0
				if ino == 0 or rlen == 0 then
					-- Free slot — write here
					writeU32(block, off, newIno)
					writeU16(block, off + 4, recLen)
					block[off + 6] = #name
					block[off + 7] = ftype
					writeStr(block, off + DIRENT_FIXED, name)
					self:_writeDataBlock(blockIdx, block)
					written = true
					break
				end
				off = off + rlen
			end
			if written then
				break
			end
		elseif not written then
			-- Allocate a new block for this directory
			local newBlk = self:_allocBlock()
			if not newBlk then
				return false, "disk full"
			end
			inode.blockPtrs[i] = newBlk
			inode.blocks = inode.blocks + 1
			inode.size = inode.size + SECTOR_SIZE
			inode.mtime = now()
			self:_writeInode(dirIno, inode)

			block = {}
			for j = 1, SECTOR_SIZE do
				block[j] = 0
			end
			blockIdx = newBlk

			writeU32(block, 1, newIno)
			writeU16(block, 5, recLen)
			block[7] = #name
			block[8] = ftype
			writeStr(block, 1 + DIRENT_FIXED, name)
			self:_writeDataBlock(blockIdx, block)
			written = true
			break
		end
	end

	self._dirCache = {} -- invalidate
	if written then
		return true
	else
		return false, "no space for dir entry"
	end
end

function VFS:_makeDirBlock(entries)
	local block = {}
	for i = 1, SECTOR_SIZE do
		block[i] = 0
	end
	local off = 1
	for _, e in ipairs(entries) do
		local recLen = DIRENT_FIXED + #e.name
		if recLen % 4 ~= 0 then
			recLen = recLen + (4 - recLen % 4)
		end
		writeU32(block, off, e.ino)
		writeU16(block, off + 4, recLen)
		block[off + 6] = #e.name
		block[off + 7] = e.ftype or 1
		writeStr(block, off + DIRENT_FIXED, e.name)
		off = off + recLen
		if off + DIRENT_FIXED > SECTOR_SIZE then
			break
		end
	end
	return block
end

-- ────────────────────────────────────────────
--  Public API
-- ────────────────────────────────────────────

--- Create directory
function VFS:mkdir(path)
	if not self._mounted then
		return false, "not mounted"
	end
	if path == "/" then
		return true
	end -- root always exists

	local ino, parIno, name = self:_resolvePath(path)
	if ino then
		return true
	end -- already exists
	if not parIno then
		return false, "parent not found: " .. path
	end

	-- Allocate inode and data block
	local newIno = self:_allocInode()
	if not newIno then
		return false, "no free inodes"
	end
	local blk = self:_allocBlock()
	if not blk then
		return false, "disk full"
	end

	-- Write inode
	self:_writeInode(newIno, {
		mode = bit32.bor(S_IFDIR, 0x1ED),
		uid = 0,
		size = SECTOR_SIZE,
		atime = now(),
		mtime = now(),
		ctime = now(),
		links = 2,
		blocks = 1,
		blockPtrs = { blk, 0, 0, 0, 0, 0, 0, 0 },
		iblock1 = 0,
		iblock2 = 0,
	})

	-- Write "." and ".." entries
	local dirBlock = self:_makeDirBlock({
		{ ino = newIno, name = ".", ftype = 2 },
		{ ino = parIno, name = "..", ftype = 2 },
	})
	self:_writeDataBlock(blk, dirBlock)

	-- Add entry to parent
	self:_addDirEntry(parIno, newIno, name, 2)
	return true
end

--- Write file
function VFS:writeFile(path, data)
	if not self._mounted then
		return false, "not mounted"
	end
	-- data is a table of bytes

	-- Get parent path
	local parentPath = path:match("^(.*)/[^/]+$") or "/"
	if parentPath == "" then
		parentPath = "/"
	end

	local existIno = self:_resolvePath(path)

	local fileIno
	if existIno then
		fileIno = existIno
		-- Free existing blocks
		local inode = self:_readInode(fileIno)
		for _, bptr in ipairs(inode.blockPtrs) do
			if bptr ~= 0 then
				self:_freeBlock(bptr)
			end
		end
	else
		local pino = self:_resolvePath(parentPath)
		if not pino then
			return false, "parent dir not found: " .. parentPath
		end

		local fname = path:match("[^/]+$")
		fileIno = self:_allocInode()
		if not fileIno then
			return false, "no free inodes"
		end

		local ok, err = self:_addDirEntry(pino, fileIno, fname, 1)
		if not ok then
			return false, err
		end
	end

	-- Allocate blocks for data
	local nBlocks = math.ceil(#data / SECTOR_SIZE)

	if nBlocks > DIRECT_BLOCKS then
		return false, "file too large: exceeds direct block limit (" .. DIRECT_BLOCKS .. " blocks)"
	end

	local ptrs = { 0, 0, 0, 0, 0, 0, 0, 0 }
	for i = 1, math.min(nBlocks, DIRECT_BLOCKS) do
		local blk = self:_allocBlock()
		if not blk then
			return false, "disk full"
		end
		ptrs[i] = blk
		-- Write block data
		local slice = {}
		for j = 1, SECTOR_SIZE do
			slice[j] = data[(i - 1) * SECTOR_SIZE + j] or 0
		end
		self:_writeDataBlock(blk, slice)
	end

	self:_writeInode(fileIno, {
		mode = bit32.bor(S_IFREG, 0x1A4), -- -rw-r--r--
		uid = 0,
		size = #data,
		atime = now(),
		mtime = now(),
		ctime = now(),
		links = 1,
		blocks = nBlocks,
		blockPtrs = ptrs,
		iblock1 = 0,
		iblock2 = 0,
	})
	return true
end

--- Read file — returns byte table or nil, err
function VFS:readFile(path)
	if not self._mounted then
		return nil, "not mounted"
	end
	local ino = self:_resolvePath(path)
	if not ino then
		return nil, "file not found: " .. path
	end

	local inode = self:_readInode(ino)
	if not inode then
		return nil, "bad inode"
	end
	if (bit32.band(inode.mode, 0xF000)) == S_IFDIR then
		return nil, "is a directory"
	end

	local data = {}
	for _, bptr in ipairs(inode.blockPtrs) do
		if bptr == 0 then
			break
		end
		local block = self:_readDataBlock(bptr)
		for _, b in ipairs(block) do
			table.insert(data, b)
		end
	end
	-- Trim to actual file size
	while #data > inode.size do
		table.remove(data)
	end
	return data
end

--- Read file as string
function VFS:readFileStr(path)
	local data, err = self:readFile(path)
	if not data then
		return nil, err
	end
	local chars = {}
	for _, b in ipairs(data) do
		table.insert(chars, string.char(b))
	end
	return table.concat(chars)
end

--- List directory
function VFS:listDir(path)
	if not self._mounted then
		return nil, "not mounted"
	end
	path = path or "/"
	local ino = self:_resolvePath(path)
	if not ino then
		return nil, "not found: " .. path
	end
	local entries = self:_readDir(ino)
	if not entries then
		return nil, "not a directory"
	end

	local out = {}
	for _, e in ipairs(entries) do
		if e.name ~= "." and e.name ~= ".." then
			local inode = self:_readInode(e.ino)
			local isDir = inode and ((bit32.band(inode.mode, 0xF000)) == S_IFDIR)
			table.insert(out, {
				name = e.name,
				ino = e.ino,
				isDir = isDir,
				size = inode and inode.size or 0,
				mtime = inode and inode.mtime or 0,
				mode = inode and inode.mode or 0,
			})
		end
	end
	return out
end

--- Remove file
function VFS:remove(path)
	if not self._mounted then
		return false, "not mounted"
	end
	local ino = self:_resolvePath(path)
	if not ino then
		return false, "not found"
	end
	local inode = self:_readInode(ino)

	-- Free blocks
	for _, bptr in ipairs(inode.blockPtrs) do
		if bptr ~= 0 then
			self:_freeBlock(bptr)
		end
	end

	-- Zero inode
	self:_writeInode(ino, {
		mode = 0,
		uid = 0,
		size = 0,
		atime = 0,
		mtime = 0,
		ctime = 0,
		links = 0,
		blocks = 0,
		blockPtrs = { 0, 0, 0, 0, 0, 0, 0, 0 },
		iblock1 = 0,
		iblock2 = 0,
	})

	-- Remove from parent directory
	local parentPath = path:match("^(.*)/[^/]+$") or "/"
	if parentPath == "" then
		parentPath = "/"
	end
	local parIno = self:_resolvePath(parentPath)
	if parIno then
		self:_removeDirEntry(parIno, ino)
	end

	self._inodeCache[ino] = nil
	self._dirCache = {}
	return true
end

function VFS:_removeDirEntry(dirIno, targetIno)
	local inode = self:_readInode(dirIno)
	for _, bptr in ipairs(inode.blockPtrs) do
		if bptr ~= 0 then
			local block = sec2Bytes(self:_readDataBlock(bptr))
			local off = 1
			while off + DIRENT_FIXED <= SECTOR_SIZE do
				local ino = readU32(block, off)
				local rlen = readU16(block, off + 4)
				if rlen == 0 then
					break
				end
				if ino == targetIno then
					-- Zero out entry
					for i = off, off + rlen - 1 do
						block[i] = 0
					end
					self:_writeDataBlock(bptr, block)
					return
				end
				off = off + rlen
			end
		end
	end
end

--- Stat a path
function VFS:stat(path)
	if not self._mounted then
		return nil, "not mounted"
	end
	local ino = self:_resolvePath(path)
	if not ino then
		return nil, "not found"
	end
	local inode = self:_readInode(ino)
	return {
		ino = ino,
		mode = inode.mode,
		size = inode.size,
		mtime = inode.mtime,
		isDir = (bit32.band(inode.mode, 0xF000)) == S_IFDIR,
		isReg = (bit32.band(inode.mode, 0xF000)) == S_IFREG,
	}
end

--- Check path exists
function VFS:exists(path)
	local ino = self:_resolvePath(path)
	return ino ~= nil
end

--- Append bytes to existing file
function VFS:appendFile(path, data)
	local existing, _ = self:readFile(path)
	if not existing then
		existing = {}
	end
	for _, b in ipairs(data) do
		table.insert(existing, b)
	end
	return self:writeFile(path, existing)
end

--- Write string helper
function VFS:writeFileStr(path, str)
	local bytes = {}
	for i = 1, #str do
		bytes[i] = string.byte(str, i)
	end
	return self:writeFile(path, bytes)
end

function VFS:getDiskStats()
	if not self._superblock then
		return {}
	end
	return {
		totalBlocks = self._superblock.totalBlocks,
		freeBlocks = self._superblock.freeBlocks,
		usedBlocks = self._superblock.totalBlocks - self._superblock.freeBlocks,
		totalInodes = self._superblock.totalInodes,
		freeInodes = self._superblock.freeInodes,
		blockSize = self._superblock.blockSize,
	}
end

return VFS
