-- NetworkService module

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkService = {}
NetworkService.__index = NetworkService

function NetworkService.new()
	local self = setmetatable({}, NetworkService)
	self.folder = nil
	self.remotes = {}
	return self
end

function NetworkService:start()
	local folder = ReplicatedStorage:FindFirstChild("NovaNet")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "NovaNet"
		folder.Parent = ReplicatedStorage
	end
	self.folder = folder

	self.remotes.SaveHDD = self:_ensureRemote("SaveHDD")
	self.remotes.LoadHDD = self:_ensureRemote("LoadHDD")
	self.remotes.SyncMachineState = self:_ensureRemote("SyncMachineState")

	return true
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

return NetworkService
