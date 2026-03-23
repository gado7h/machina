-- HDDStore module

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local DEFAULT_NAMESPACE = "MachinaHDD-v1"

local HDDStore = {}
HDDStore.__index = HDDStore

local function buildPayload(hddImage)
	return {
		updatedAt = os.time(),
		hdd = hddImage,
	}
end

local function pcallResult(run)
	local ok, result = pcall(run)
	if not ok then
		return nil, tostring(result)
	end
	return result
end

function HDDStore.new(namespace)
	local self = setmetatable({}, HDDStore)
	self.namespace = namespace or DEFAULT_NAMESPACE
	self.store = DataStoreService:GetDataStore(self.namespace)
	return self
end

function HDDStore:_keyForPlayer(player)
	return string.format("player:%d:hdd", player.UserId)
end

function HDDStore:saveSnapshot(player, hddImage)
	local key = self:_keyForPlayer(player)
	local payload = buildPayload(hddImage)
	local _, err = pcallResult(function()
		self.store:SetAsync(key, payload)
	end)
	if err then
		return false, err
	end
	return true
end

function HDDStore:loadSnapshot(player)
	local key = self:_keyForPlayer(player)
	return pcallResult(function()
		return self.store:GetAsync(key)
	end)
end

function HDDStore:encodeSectorDump(sectors)
	return HttpService:JSONEncode(sectors)
end

function HDDStore:decodeSectorDump(raw)
	if type(raw) ~= "string" or raw == "" then
		return {}
	end

	local decoded = pcallResult(function()
		return HttpService:JSONDecode(raw)
	end)
	if decoded == nil then
		return {}
	end

	return decoded
end

return HDDStore
