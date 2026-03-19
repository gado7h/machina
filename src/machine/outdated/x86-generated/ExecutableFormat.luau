local ExecutableFormat = {}

ExecutableFormat.MAGIC = "NX16"
ExecutableFormat.VERSION = 1
ExecutableFormat.HEADER_SIZE = 32
ExecutableFormat.FLAG_EXECUTABLE = 0x01

local function writeWord(bytes, index, value)
	local v = (tonumber(value) or 0) % 0x10000
	bytes[index] = v % 256
	bytes[index + 1] = math.floor(v / 256) % 256
end

function ExecutableFormat.wrap(payloadBytes, opts)
	opts = opts or {}
	local headerSize = tonumber(opts.headerSize) or ExecutableFormat.HEADER_SIZE
	assert(headerSize >= ExecutableFormat.HEADER_SIZE, "ExecutableFormat: header size is too small")

	local loadOffset = tonumber(opts.loadOffset) or 0
	local entryOffset = tonumber(opts.entryOffset) or loadOffset
	local version = tonumber(opts.version) or ExecutableFormat.VERSION
	local flags = tonumber(opts.flags) or ExecutableFormat.FLAG_EXECUTABLE

	local bytes = {}
	for i = 1, headerSize do
		bytes[i] = 0
	end

	bytes[1] = string.byte("N")
	bytes[2] = string.byte("X")
	bytes[3] = string.byte("1")
	bytes[4] = string.byte("6")
	bytes[5] = version % 256
	bytes[6] = flags % 256
	writeWord(bytes, 7, headerSize)
	writeWord(bytes, 9, loadOffset)
	writeWord(bytes, 11, entryOffset)
	writeWord(bytes, 13, #payloadBytes)

	for index, byte in ipairs(payloadBytes) do
		bytes[headerSize + index] = byte % 256
	end

	return {
		bytes = bytes,
		headerSize = headerSize,
		loadOffset = loadOffset,
		entryOffset = entryOffset,
		imageSize = #payloadBytes,
	}
end

return ExecutableFormat
