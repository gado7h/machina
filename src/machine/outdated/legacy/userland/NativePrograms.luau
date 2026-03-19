-- Canonical native guest program sources seeded into the virtual filesystem.

local NativeAssembler = require(script.Parent.NativeAssembler)

local NativePrograms = {}

local SOURCES = {
	["/bin/hello.nxe"] = [[
--!native
PRINT "hello from nova32 native"
MOVI R1, 10
OUT STDOUT, R1
EXIT 0
]],
}

function NativePrograms.materialize(config)
	local materialized = {}
	for path, source in pairs(SOURCES) do
		local imageBytes = NativeAssembler.compile(source, config, {
			sourcePath = path,
		})
		materialized[path] = imageBytes
	end
	return materialized
end

return NativePrograms
