-- Main.server module

local Players = game:GetService("Players")

local NetworkService = require(script.Parent.network.NetworkService)
local HDDStore = require(script.Parent.datastore.HDDStore)

local network = NetworkService.new()
network:start()

local hddStore = HDDStore.new("MachinaHDD-v2")

network.remotes.SaveHDD.OnServerInvoke = function(player, hddSnapshot)
	if type(hddSnapshot) ~= "table" then
		return false, "invalid snapshot"
	end
	return hddStore:saveSnapshot(player, hddSnapshot)
end

network.remotes.LoadHDD.OnServerInvoke = function(player)
	local snapshot, err = hddStore:loadSnapshot(player)
	if not snapshot then
		return nil, err
	end
	return snapshot
end

network.remotes.SyncMachineState.OnServerInvoke = function(_, state)
	if type(state) ~= "table" then
		return false, "invalid state"
	end
	return true
end

Players.PlayerRemoving:Connect(function(_)
	-- Hook point for deferred autosave orchestration
	-- (machines can call SaveHDD proactively before player leaves)
end)
