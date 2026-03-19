-- Native guest executable image format helpers for nova32.

local NativeExecutable = {}

local function getNativeConfig(config)
	local native = config and config.NATIVE or {}
	local userSpaceBase = (config and config.USER_SPACE_BASE) or 0x00200000
	local userSpaceTop = (config and config.USER_SPACE_TOP) or 0x00800000
	return {
		magic = native.MAGIC or "NVX1",
		version = native.VERSION or 1,
		headerSize = native.HEADER_SIZE or 32,
		extension = native.EXTENSION or ".nxe",
		defaultLoadAddress = native.DEFAULT_LOAD_ADDRESS or userSpaceBase,
		defaultStackAddress = native.DEFAULT_STACK_ADDRESS or (userSpaceTop - 4),
		maxImageSize = native.MAX_IMAGE_SIZE or 0x00010000,
	}
end

local function stringBytes(str)
	local bytes = {}
	for i = 1, #str do
		bytes[i] = string.byte(str, i)
	end
	return bytes
end

local function readU16(bytes, index)
	local b0 = bytes[index] or 0
	local b1 = bytes[index + 1] or 0
	return b0 + b1 * 256
end

local function readU32(bytes, index)
	local b0 = bytes[index] or 0
	local b1 = bytes[index + 1] or 0
	local b2 = bytes[index + 2] or 0
	local b3 = bytes[index + 3] or 0
	return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

local function appendU16(bytes, value)
	local v = (tonumber(value) or 0) % 0x10000
	bytes[#bytes + 1] = v % 256
	bytes[#bytes + 1] = math.floor(v / 256) % 256
end

local function appendU32(bytes, value)
	local v = (tonumber(value) or 0) % 0x100000000
	bytes[#bytes + 1] = v % 256
	bytes[#bytes + 1] = math.floor(v / 256) % 256
	bytes[#bytes + 1] = math.floor(v / 65536) % 256
	bytes[#bytes + 1] = math.floor(v / 16777216) % 256
end

function NativeExecutable.isImage(bytes, config)
	local native = getNativeConfig(config)
	local magicBytes = stringBytes(native.magic)
	if type(bytes) ~= "table" or #bytes < #magicBytes then
		return false
	end
	for i = 1, #magicBytes do
		if (bytes[i] or 0) ~= magicBytes[i] then
			return false
		end
	end
	return true
end

function NativeExecutable.parse(bytes, config)
	local native = getNativeConfig(config)
	if not NativeExecutable.isImage(bytes, config) then
		return nil, "native-image-bad-magic"
	end
	if #bytes < native.headerSize then
		return nil, "native-image-truncated-header"
	end

	local version = readU16(bytes, 5)
	local headerSize = readU16(bytes, 7)
	local entryOffset = readU32(bytes, 9)
	local loadAddress = readU32(bytes, 13)
	local imageSize = readU32(bytes, 17)
	local bssSize = readU32(bytes, 21)
	local stackPointer = readU32(bytes, 25)
	local flags = readU32(bytes, 29)

	if version ~= native.version then
		return nil, "native-image-unsupported-version:" .. tostring(version)
	end
	if headerSize < native.headerSize or #bytes < headerSize then
		return nil, "native-image-invalid-header-size"
	end
	if imageSize == 0 then
		return nil, "native-image-empty"
	end
	if imageSize > native.maxImageSize then
		return nil, "native-image-too-large"
	end
	if entryOffset >= imageSize then
		return nil, "native-image-entry-out-of-range"
	end

	local payloadFirst = headerSize + 1
	local payloadLast = payloadFirst + imageSize - 1
	if payloadLast > #bytes then
		return nil, "native-image-truncated-payload"
	end

	local imageBytes = {}
	for i = payloadFirst, payloadLast do
		imageBytes[#imageBytes + 1] = (bytes[i] or 0) % 256
	end

	return {
		kind = "native",
		format = "native",
		arch = (config and config.CPU_ARCH) or "nova32",
		version = version,
		headerSize = headerSize,
		flags = flags,
		entryOffset = entryOffset,
		entryAddress = (loadAddress + entryOffset) % 0x100000000,
		loadAddress = loadAddress,
		imageSize = imageSize,
		bssSize = bssSize,
		stackPointer = stackPointer,
		imageBytes = imageBytes,
		rawBytes = bytes,
	}
end

function NativeExecutable.buildFromBytes(payloadBytes, opts, config)
	local native = getNativeConfig(config)
	opts = opts or {}
	payloadBytes = payloadBytes or {}

	local imageSize = #payloadBytes
	local header = {}
	local magicBytes = stringBytes(native.magic)
	for i = 1, #magicBytes do
		header[#header + 1] = magicBytes[i]
	end
	appendU16(header, native.version)
	appendU16(header, native.headerSize)
	appendU32(header, opts.entryOffset or 0)
	appendU32(header, opts.loadAddress or native.defaultLoadAddress)
	appendU32(header, imageSize)
	appendU32(header, opts.bssSize or 0)
	appendU32(header, opts.stackPointer or native.defaultStackAddress)
	appendU32(header, opts.flags or 0)

	local bytes = table.clone(header)
	for i = 1, imageSize do
		bytes[#bytes + 1] = (payloadBytes[i] or 0) % 256
	end
	return bytes
end

function NativeExecutable.buildFromWords(words, opts, config)
	local payload = {}
	for _, word in ipairs(words or {}) do
		appendU32(payload, word)
	end
	return NativeExecutable.buildFromBytes(payload, opts, config)
end

return NativeExecutable
