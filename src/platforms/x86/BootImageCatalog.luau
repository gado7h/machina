local ProductionImages = require(script.Parent.BootImageCatalogProductionImages)
local ValidationImages = require(script.Parent.BootImageCatalogValidationImages)

local BootImageCatalog = {}

local function mergeEntries(source)
	for name, entry in pairs(source) do
		BootImageCatalog[name] = entry
	end
end

mergeEntries(ProductionImages)
mergeEntries(ValidationImages)

return BootImageCatalog
