-- PackageManager module

local PKG = {}
PKG.__index = PKG

function PKG.new(kernel)
	local self = setmetatable({}, PKG)
	self.kernel = kernel
	self.vfs = kernel.vfs
	self.gpu = kernel.gpu
	self.luauvm = kernel.machine and kernel.machine.luauvm
	self._dbModule = nil -- lazy-loaded PackageDB
	self._installed = {} -- name → {name,version,installTime}
	self._logFile = "/var/log/pkgmgr.log"
	return self
end

function PKG:_db()
	if not self._dbModule then
		self._dbModule = require(script.Parent.PackageDB)
	end
	return self._dbModule
end

function PKG:_log(msg)
	local line = string.format("[%s] %s\n", os.date("%H:%M:%S"), msg)
	self.vfs:appendFile(self._logFile, self:_strBytes(line))
end

function PKG:_strBytes(s)
	local b = {}
	for i = 1, #s do
		b[i] = string.byte(s, i)
	end
	return b
end

--  Load installed package list from disk
function PKG:_loadInstalled()
	local dbPath = "/pkg/db/installed.db"
	if not self.vfs:exists(dbPath) then
		return
	end
	local content = self.vfs:readFileStr(dbPath)
	if not content then
		return
	end
	for line in (content .. "\n"):gmatch("([^\n]+)") do
		local name, version, t = line:match("^([%w%-%.]+)\t([%w%.%-]+)\t(%d+)$")
		if name then
			self._installed[name] = { name = name, version = version, installTime = tonumber(t) or 0 }
		end
	end
end

function PKG:_saveInstalled()
	local lines = {}
	for name, rec in pairs(self._installed) do
		table.insert(lines, string.format("%s\t%s\t%d", rec.name, rec.version, rec.installTime))
	end
	self.vfs:writeFileStr("/pkg/db/installed.db", table.concat(lines, "\n"))
end

--  Dependency resolution (topological sort)
function PKG:_resolveDeps(name, visited, order)
	visited = visited or {}
	order = order or {}
	if visited[name] then
		return order
	end
	visited[name] = true
	local pkg = self:_db().get(name)
	if not pkg then
		return order
	end
	for _, dep in ipairs(pkg.deps or {}) do
		self:_resolveDeps(dep, visited, order)
	end
	table.insert(order, name)
	return order
end

--  Install
function PKG:install(name)
	self:_loadInstalled()

	local pkg = self:_db().get(name)
	if not pkg then
		return false, "package '" .. name .. "' not found in repository"
	end

	if self._installed[name] then
		return true, name .. " is already installed (version " .. self._installed[name].version .. ")"
	end

	-- Resolve + install dependencies first
	local order = self:_resolveDeps(name)
	for _, depName in ipairs(order) do
		if depName ~= name and not self._installed[depName] then
			local ok, err = self:install(depName)
			if not ok then
				return false, "dependency '" .. depName .. "' failed: " .. tostring(err)
			end
		end
	end

	self.gpu:println(string.format("Installing %s %s...", pkg.name, pkg.version), 0x07)

	-- Run preinst if present
	if pkg.preinst then
		self:_runHook(pkg.preinst, pkg.name, "preinst")
	end

	-- Install files
	local fileCount = 0
	for path, source in pairs(pkg.files or {}) do
		-- Ensure parent directory exists
		local dir = path:match("^(.*)/[^/]+$") or "/"
		if not self.vfs:exists(dir) then
			self.vfs:mkdir(dir)
		end

		-- Attempt to compile through LuauVM to validate syntax, then store source
		-- We store Lua source (not bytecode) so scripts remain human-readable
		-- and can be re-compiled on execution.
		if self.luauvm and (path:match("%.lua$") or not path:match("%.[a-z]+$")) then
			-- Validate by compiling (detect syntax errors early)
			if type(source) == "string" then
				local ok, result = pcall(function()
					return self.luauvm.compile(source)
				end)

				if not ok then
					self.gpu:println(string.format("  WARN: %s failed syntax check: %s", path, tostring(result)), 0x0E)
				end
			end
		end

		-- Write source to VFS
		self.vfs:writeFileStr(path, source)
		fileCount = fileCount + 1
		self.gpu:print(".")
	end
	self.gpu:println(string.format(" %d files", fileCount), 0x0A)

	-- Run postinst if present
	if pkg.postinst then
		self:_runHook(pkg.postinst, pkg.name, "postinst")
	end

	-- Record installation
	self._installed[name] = {
		name = name,
		version = pkg.version,
		installTime = os.time and os.time() or 0,
	}
	self:_saveInstalled()
	self:_log("installed " .. name .. " " .. pkg.version)

	self.gpu:println(string.format("Successfully installed %s %s", pkg.name, pkg.version), 0x0A)
	return true
end

--  Remove
function PKG:remove(name)
	self:_loadInstalled()

	if not self._installed[name] then
		return false, name .. " is not installed"
	end

	-- Check reverse dependencies
	for iname, _ in pairs(self._installed) do
		if iname ~= name then
			local pkg = self:_db().get(iname)
			if pkg then
				for _, dep in ipairs(pkg.deps or {}) do
					if dep == name then
						return false, iname .. " depends on " .. name
					end
				end
			end
		end
	end

	local pkg = self:_db().get(name)
	if pkg then
		-- Remove files
		for path, _ in pairs(pkg.files or {}) do
			if self.vfs:exists(path) then
				self.vfs:remove(path)
			end
		end
		self.gpu:println(string.format("Removed %d files for %s", #(pkg.files or {}), name), 0x07)
	end

	self._installed[name] = nil
	self:_saveInstalled()
	self:_log("removed " .. name)
	self.gpu:println("Successfully removed " .. name, 0x0A)
	return true
end

--  Update (re-install)
function PKG:update()
	self:_loadInstalled()
	local updated = 0
	for name, rec in pairs(self._installed) do
		local pkg = self:_db().get(name)
		if pkg and pkg.version ~= rec.version then
			self.gpu:println(string.format("Upgrading %s %s → %s", name, rec.version, pkg.version), 0x07)
			self:remove(name)
			self:install(name)
			updated = updated + 1
		end
	end
	if updated == 0 then
		self.gpu:println("All packages are up to date.", 0x0A)
	end
	return true
end

--  List
function PKG:list()
	self:_loadInstalled()
	local all = self:_db().getAll()
	local out = {}
	for _, pkg in ipairs(all) do
		local inst = self._installed[pkg.name]
		table.insert(out, {
			name = pkg.name,
			version = pkg.version,
			desc = pkg.desc,
			size = pkg.size,
			installed = inst ~= nil,
			instVer = inst and inst.version or nil,
		})
	end
	return out
end

--  Search
function PKG:search(query)
	return self:_db().search(query or "")
end

--  Info
function PKG:info(name)
	local pkg = self:_db().get(name)
	if not pkg then
		return nil
	end
	self:_loadInstalled()
	local inst = self._installed[name]

	local fileCount = 0
	for _ in pairs(pkg.files or {}) do
		fileCount = fileCount + 1
	end

	return {
		name = pkg.name,
		version = pkg.version,
		installed = inst and inst.version or "no",
		installDate = inst and os.date("%Y-%m-%d %H:%M", inst.installTime) or "-",
		description = pkg.desc,
		size = string.format("%d bytes", pkg.size or 0),
		depends = #(pkg.deps or {}) > 0 and table.concat(pkg.deps, ", ") or "none",
		files = tostring(fileCount),
	}
end

--  Hook runner (pre/postinst scripts via LuauVM)
function PKG:_runHook(source, pkgName, hookName)
	if type(source) ~= "string" or source == "" then
		return
	end

	local vm = self.luauvm
	if not vm then
		self.gpu:println(string.format("  [%s/%s] LuauVM unavailable, skipping hook", pkgName, hookName), 0x0E)
		return
	end

	local vfs = self.vfs
	local gpu = self.gpu
	if not vfs then
		self.gpu:println(string.format("  [%s/%s] VFS unavailable", pkgName, hookName), 0x0C)
		return
	end

	local sandbox = {
		print = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring(select(i, ...))
			end
			gpu:println(table.concat(parts, "\t"), 0x07)
		end,
		tty = {
			writeln = function(s, attr)
				gpu:println(tostring(s), attr or 0x07)
			end,
			write = function(s, attr)
				gpu:print(tostring(s), attr or 0x07)
			end,
			color = function(fg, bg)
				return (bg or 0) * 16 + (fg or 7)
			end,
			size = function()
				return 80, 25
			end,
			clear = function()
				gpu:clearScreen()
			end,
		},

		fs = {
			read = function(p)
				return vfs:readFileStr(p)
			end,
			write = function(p, s)
				return vfs:writeFileStr(p, tostring(s))
			end,
			exists = function(p)
				return vfs:exists(p)
			end,
			mkdir = function(p)
				return vfs:mkdir(p)
			end,
		},

		syscall = function(num, ...)
			if self.kernel and self.kernel.syscall then
				return self.kernel.syscall:call(1, num, ...)
			end
			return -38
		end,

		os = {
			time = os.time,
			date = os.date,
			clock = os.clock,
		},

		string = string,
		math = math,
		table = table,
		pairs = pairs,
		ipairs = ipairs,
		tostring = tostring,
		tonumber = tonumber,
		type = type,
		pcall = pcall,
		error = error,
		select = select,
		next = next,
		unpack = table.unpack or unpack,
		task = task,
		coroutine = coroutine,
	}

	local ok, func = pcall(function()
		return vm(source, false, sandbox)
	end)

	if not ok or type(func) ~= "function" then
		self.gpu:println(string.format("  [%s/%s] compile error: %s", pkgName, hookName, tostring(func)), 0x0C)
		return
	end

	local runOk, err = pcall(func)
	if not runOk then
		self.gpu:println(string.format("  [%s/%s] error: %s", pkgName, hookName, tostring(err)), 0x0C)
	end
end

return PKG
