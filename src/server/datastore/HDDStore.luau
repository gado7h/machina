-- HDDStore module

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local HDDStore = {}
HDDStore.__index = HDDStore

function HDDStore.new(namespace)
	local self = setmetatable({}, HDDStore)
	self.namespace = namespace or "NovaHDD-v1"
	self.store = DataStoreService:GetDataStore(self.namespace)
	return self
end

function HDDStore:_keyForPlayer(player)
	return string.format("player:%d:hdd", player.UserId)
end

function HDDStore:saveSnapshot(player, hddImage)
	local key = self:_keyForPlayer(player)
	local payload = {
		updatedAt = os.time(),
		hdd = hddImage,
	}

	local ok, err = pcall(function()
		self.store:SetAsync(key, payload)
	end)
	if not ok then
		return false, tostring(err)
	end

	return true
end

function HDDStore:loadSnapshot(player)
	local key = self:_keyForPlayer(player)
	local ok, result = pcall(function()
		return self.store:GetAsync(key)
	end)

	if not ok then
		return nil, tostring(result)
	end

	return result
end

function HDDStore:encodeSectorDump(sectors)
	return HttpService:JSONEncode(sectors)
end

function HDDStore:decodeSectorDump(raw)
	if type(raw) ~= "string" or raw == "" then
		return {}
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok then
		return {}
	end

	return decoded
end

return HDDStore
