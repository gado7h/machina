-- Main.server module

local Players = game:GetService("Players")

local HDDStore = require(script.Parent.datastore.HDDStore)
local NetworkService = require(script.Parent.network.NetworkService)

local HDD_NAMESPACE = "MachinaHDD-v2"

local network = NetworkService.new()
local hddStore = HDDStore.new(HDD_NAMESPACE)

local function bindRemote(remote, handler)
	remote.OnServerInvoke = handler
end

local function saveHDD(_player, hddSnapshot)
	if type(hddSnapshot) ~= "table" then
		return false, "invalid snapshot"
	end
	return hddStore:saveSnapshot(_player, hddSnapshot)
end

local function loadHDD(player)
	local snapshot, err = hddStore:loadSnapshot(player)
	if not snapshot then
		return nil, err
	end
	return snapshot
end

local function syncMachineState(_, state)
	if type(state) ~= "table" then
		return false, "invalid state"
	end
	return true
end

network:start()

bindRemote(network.remotes.SaveHDD, saveHDD)
bindRemote(network.remotes.LoadHDD, loadHDD)
bindRemote(network.remotes.SyncMachineState, syncMachineState)

Players.PlayerRemoving:Connect(function(_)
	-- Hook point for deferred autosave orchestration
	-- (machines can call SaveHDD proactively before player leaves)
end)
