-- MemoryManager module

local MM = {}
MM.__index = MM

local PAGE_SIZE = 4096
local PTE_PRESENT = 0x01
local PTE_RW = 0x02
local PTE_USER = 0x04
local PTE_ACCESSED = 0x20
local PTE_DIRTY = 0x40

function MM.new(config, ram)
	local self = setmetatable({}, MM)
	self.config = config
	self.ram = ram

	local physBase = config.RAM_BASE
	local physEnd = config.RAM_BASE + config.RAM_SIZE

	self._physBase = physBase
	self._physEnd = physEnd
	self._pageSize = PAGE_SIZE

	-- Page frame bitmap: bit = 1 → frame used
	local totalPages = math.floor(config.RAM_SIZE / PAGE_SIZE)
	self._totalPages = totalPages
	self._freeBitmap = {} -- array of uint32, 1 bit per page
	local words = math.ceil(totalPages / 32)
	for i = 1, words do
		self._freeBitmap[i] = 0
	end

	-- Reserve kernel pages (0 → KERNEL_LOAD_ADDR)
	local kernelPages = math.floor((config.KERNEL_LOAD_ADDR - config.RAM_BASE) / PAGE_SIZE)
	for i = 0, kernelPages - 1 do
		self:_setPage(i, true)
	end

	-- Slab allocator zones
	self._slabs = {} -- size → {blocks=[addr,...], freeList=[addr,...]}

	-- Virtual memory areas (VMA) per process
	self._vmas = {} -- pid → [{base, size, flags, name}]

	self.stats = {
		totalPages = totalPages,
		freePages = totalPages - kernelPages,
		kernelPages = kernelPages,
		allocs = 0,
		frees = 0,
		pageFaults = 0,
	}
	return self
end

--  Bitmap helpers

function MM:_setPage(pfn, used)
	local word = math.floor(pfn / 32) + 1
	local bit = pfn % 32
	if used then
		self._freeBitmap[word] = bit32.bor(self._freeBitmap[word], (2 ^ bit))
	else
		self._freeBitmap[word] = bit32.band(self._freeBitmap[word], (bit32.bnot(2 ^ bit) % 0x100000000))
	end
end

function MM:_isPageUsed(pfn)
	local word = math.floor(pfn / 32) + 1
	local bit = pfn % 32
	return (bit32.band((self._freeBitmap[word] or 0), (2 ^ bit))) ~= 0
end

--  Physical page frame allocation

--- Allocate n contiguous physical pages.  Returns {base, size, pfn} or nil.
function MM:allocPages(n)
	n = n or 1
	-- First-fit contiguous search
	local run = 0
	local start = 0
	for pfn = 0, self._totalPages - 1 do
		if not self:_isPageUsed(pfn) then
			if run == 0 then
				start = pfn
			end
			run = run + 1
			if run == n then
				for i = start, start + n - 1 do
					self:_setPage(i, true)
				end
				self.stats.allocs = self.stats.allocs + 1
				self.stats.freePages = self.stats.freePages - n
				local physAddr = self._physBase + start * PAGE_SIZE
				return { base = physAddr, size = n * PAGE_SIZE, pfn = start, pages = n }
			end
		else
			run = 0
		end
	end
	return nil -- OOM
end

--- Allocate one physical page.
function MM:allocPage()
	return self:allocPages(1)
end

--- Free pages previously allocated with allocPages.
function MM:freePages(block)
	if not block then
		return
	end
	for i = block.pfn, block.pfn + block.pages - 1 do
		self:_setPage(i, false)
	end
	self.stats.frees = self.stats.frees + 1
	self.stats.freePages = self.stats.freePages + block.pages
end

--  Page Table management

--- Build a minimal page directory for kernel space.
--- Maps virtual 0x00100000–0x007FFFFF → physical RAM.
function MM:buildKernelPageDir()
	-- Allocate 1 page for page directory
	local pd = self:allocPage()
	if not pd then
		return nil
	end

	-- Map kernel space: identity map (virt == phys)
	-- Virtual 0x00100000 → PDE index 0 → PTE with physical frames
	local pdBase = pd.base - self._physBase -- RAM offset

	-- For simplicity, do a 4MB large-page mapping (PSE)
	-- PDE entry for 0x00100000: present, R/W, 4MB page
	local pdeIdx = math.floor(0x00100000 / (1024 * 4096)) -- = 0
	local pde = bit32.bor(0x00100000, 0x83) -- base addr | Present | R/W | Page Size (4MB)
	self.ram:memWrite(pdBase + pdeIdx * 4, pde % 256)
	self.ram:memWrite(pdBase + pdeIdx * 4 + 1, math.floor(pde / 256) % 256)
	self.ram:memWrite(pdBase + pdeIdx * 4 + 2, math.floor(pde / 65536) % 256)
	self.ram:memWrite(pdBase + pdeIdx * 4 + 3, math.floor(pde / 16777216) % 256)

	return pd
end

--  Virtual Memory Area (VMA) management

function MM:mmap(pid, size, flags, name)
	-- Allocate physical memory and record VMA
	local pages = math.ceil(size / PAGE_SIZE)
	local block = self:allocPages(pages)
	if not block then
		return nil, "out of memory"
	end

	if not self._vmas[pid] then
		self._vmas[pid] = {}
	end
	table.insert(self._vmas[pid], {
		base = block.base,
		size = block.size,
		flags = flags or bit32.bor(PTE_PRESENT, PTE_RW, PTE_USER),
		name = name or "[anon]",
		block = block,
	})

	return block.base
end

function MM:munmap(pid, addr)
	if not self._vmas[pid] then
		return false
	end
	for i, vma in ipairs(self._vmas[pid]) do
		if vma.base == addr then
			self:freePages(vma.block)
			table.remove(self._vmas[pid], i)
			return true
		end
	end
	return false
end

function MM:getVMAs(pid)
	return self._vmas[pid] or {}
end

--- Clean up all VMAs for a process (on exit)
function MM:cleanupProcess(pid)
	if not self._vmas[pid] then
		return
	end
	for _, vma in ipairs(self._vmas[pid]) do
		self:freePages(vma.block)
	end
	self._vmas[pid] = nil
end

--  Slab / kernel heap allocator
-- Sizes: 8, 16, 32, 64, 128, 256, 512

local SLAB_SIZES = { 8, 16, 32, 64, 128, 256, 512 }

function MM:kmalloc(size)
	-- Round up to nearest slab size
	local slabSize = 512
	for _, s in ipairs(SLAB_SIZES) do
		if size <= s then
			slabSize = s
			break
		end
	end

	if not self._slabs[slabSize] then
		self._slabs[slabSize] = { freeList = {}, page = nil, cursor = 0 }
	end
	local slab = self._slabs[slabSize]

	-- Use free list first
	if #slab.freeList > 0 then
		return table.remove(slab.freeList)
	end

	-- Allocate a new page if needed
	if not slab.page or slab.cursor + slabSize > PAGE_SIZE then
		slab.page = self:allocPage()
		slab.cursor = 0
	end
	if not slab.page then
		return nil
	end

	local addr = slab.page.base + slab.cursor
	slab.cursor = slab.cursor + slabSize
	return addr
end

function MM:kfree(addr, size)
	local slabSize = 512
	for _, s in ipairs(SLAB_SIZES) do
		if size and size <= s then
			slabSize = s
			break
		end
	end
	if self._slabs[slabSize] then
		table.insert(self._slabs[slabSize].freeList, addr)
	end
end

--  Stats & info

function MM:getStats()
	return self.stats
end

function MM:getMemInfo()
	return {
		total = self._totalPages * PAGE_SIZE,
		free = self.stats.freePages * PAGE_SIZE,
		used = (self._totalPages - self.stats.freePages) * PAGE_SIZE,
		kernel = self.stats.kernelPages * PAGE_SIZE,
		pageSize = PAGE_SIZE,
		totalPages = self._totalPages,
		freePages = self.stats.freePages,
	}
end

return MM
