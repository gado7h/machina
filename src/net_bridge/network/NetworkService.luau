-- NetworkService module

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ROOT_FOLDER_NAME = "MachinaNet"
local REMOTE_NAMES = {
	"SaveHDD",
	"LoadHDD",
	"SyncMachineState",
}

local NetworkService = {}
NetworkService.__index = NetworkService

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

function NetworkService.new()
	local self = setmetatable({}, NetworkService)
	self.folder = nil
	self.remotes = {}
	return self
end

function NetworkService:_ensureRemote(name)
	local remote = self.folder:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = self.folder
	end
	return remote
end

function NetworkService:_bindRemotes()
	for _, name in ipairs(REMOTE_NAMES) do
		self.remotes[name] = self:_ensureRemote(name)
	end
end

function NetworkService:start()
	self.folder = ensureFolder(ReplicatedStorage, ROOT_FOLDER_NAME)
	self:_bindRemotes()
	return true
end

return NetworkService
