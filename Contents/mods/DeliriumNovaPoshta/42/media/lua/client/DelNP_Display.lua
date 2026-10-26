--[[
Box names are composed locally, in the viewer's own language ("... [No]"
while sealed). The server stores only the facts in modData - a name written
there would reach everyone in the server's language. Same hooks as the
Delirium License documents.
]]

if isServer() then return end

require "DelNP_Shared"
require "ISUI/ISInventoryPane"
require "ISUI/ISToolTipInv"

local oldRefreshContainer = ISInventoryPane.refreshContainer
function ISInventoryPane:refreshContainer()
	local items = self.inventory and self.inventory:getItems()
	if items then
		for i = 0, items:size() - 1 do DelNP.refreshName(items:get(i)) end
	end
	oldRefreshContainer(self)
end

local oldSetItem = ISToolTipInv.setItem
function ISToolTipInv:setItem(item)
	DelNP.refreshName(item)
	oldSetItem(self, item)
end
