--[[
A sealed box cannot be looked into, nor can anything go in or out - for
anyone, recipient and admins included: they open (unseal) it first.

Two client-side gates, the way vanilla gates its own containers:
- the loot/inventory window gets no button for the box's container
  (OnRefreshInventoryWindowContainers, stage "buttonsAdded": vanilla's hook
  for mods to edit the list before it picks the selected container, so a
  selection that pointed at the box falls back like any vanished container);
- ISInventoryTransferAction:isValid refuses a transfer whose source or
  destination is a sealed box's container (grab-all, drag and drop, equip all
  go through it).
Transfers are requested by the client and validated by the engine, not by
server Lua, so a modified client could still get round this.
]]

if isServer() then return end

require "DelNP_Shared"
require "TimedActions/ISInventoryTransferAction"

local function onRefreshContainers(page, stage)
	if stage ~= "buttonsAdded" then return end
	local kept = {}
	for _, button in ipairs(page.backpacks) do
		if DelNP.sealedBoxOf(button.inventory) then
			page.containerButtonPanel:removeChild(button)
			table.insert(page.buttonPool, button)
		else
			table.insert(kept, button)
		end
	end
	if #kept == #page.backpacks then return end
	-- Close the gaps left by removed buttons (addContainerButton lays them out
	-- by index).
	table.wipe(page.backpacks)
	for i, button in ipairs(kept) do
		button:setY(((i - 1) * page.buttonSize) - 1)
		page.backpacks[i] = button
	end
	if DelNP.sealedBoxOf(page.inventoryPane.lastinventory) then
		page.inventoryPane.lastinventory = page.backpacks[1] and page.backpacks[1].inventory or nil
	end
end

Events.OnRefreshInventoryWindowContainers.Add(onRefreshContainers)

local oldIsValid = ISInventoryTransferAction.isValid
function ISInventoryTransferAction:isValid()
	if DelNP.sealedBoxOf(self.srcContainer) or DelNP.sealedBoxOf(self.destContainer) then
		return false
	end
	return oldIsValid(self)
end
