--[[
Inventory context menu of a Nova Poshta box: seal it (form), look at its
waybill, open it (recipient or admin). Presentation only - the server redoes
every check (server/DelNP_Server.lua).
]]

if isServer() then return end

require "ISUI/ISTextBox"
require "DelNP_Shared"
require "DelNP_WaybillUI"

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local PAD = 10

--[[
The sealing form: vanilla ISTextBox with one entry per typed input (branch,
recipient). Its own entry is the first input, the second is an extra
ISTextEntryBox. Above them, read-only, what the server will fill in itself:
the number, the sender (this login) and today's date.

Callback contract as in Delirium License: (target, button, param1..param4),
params being constructor args 10..13 - the `player` slot (arg 9) is for
positioning and never reaches the callback, so the player goes again as
param1.
]]
DelNPSealBox = ISTextBox:derive("DelNPSealBox")

function DelNPSealBox:initialise()
	ISTextBox.initialise(self)

	local entryH = self.entry:getHeight()
	local y = self:titleBarHeight() + PAD

	-- Read-only lines.
	self.info = {
		{ label = getText("IGUI_DelNP_Field_no"), value = getText("IGUI_DelNP_AutoNumber") },
		{ label = getText("IGUI_DelNP_Field_sender"), value = tostring(self.param1:getUsername()) },
		{ label = getText("IGUI_DelNP_Field_date"), value = DelNP.todayText() },
	}
	for _, line in ipairs(self.info) do
		line.y = y
		y = y + FONT_HGT_SMALL + 4
	end
	y = y + PAD

	self.rows = {}
	for i, id in ipairs(DelNP.inputOrder) do
		local labelY = y
		y = y + FONT_HGT_SMALL + 2
		local entry = self.entry
		if i == 1 then
			entry:setY(y)
		else
			entry = ISTextEntryBox:new("", self.entry:getX(), y, self.entry:getWidth(), entryH)
			entry.font = UIFont.Medium
			entry:initialise()
			entry:instantiate()
			entry:setClearButton(true)
			self:addChild(entry)
		end
		if DelNP.inputs[id].numeric then entry:setOnlyNumbers(true) end
		table.insert(self.rows, { id = id, entry = entry, labelY = labelY })
		y = y + entryH + PAD
	end

	self.yes:setY(y)
	self.no:setY(y)
	self:setHeight(self.yes:getBottom() + PAD + 1)
end

function DelNPSealBox:prerender()
	for _, row in ipairs(self.rows) do row.entry.backgroundColor.a = 0.8 end
	ISTextBox.prerender(self)
	local x = self.entry:getX()
	for _, line in ipairs(self.info) do
		self:drawText(line.label, x, line.y, 0.7, 0.7, 0.7, 1, UIFont.Small)
		self:drawText(line.value, x + 130, line.y, 1, 1, 1, 1, UIFont.Small)
	end
	for _, row in ipairs(self.rows) do
		self:drawText(getText("IGUI_DelNP_Field_" .. row.id), x, row.labelY, 1, 1, 1, 1, UIFont.Small)
	end
end

function DelNPSealBox:updateButtons()
	ISTextBox.updateButtons(self)
	for _, row in ipairs(self.rows) do
		local text = row.entry:getInternalText()
		local max = DelNP.inputs[row.id].max
		if string.trim(text) == "" then
			self.yes:setEnable(false)
			self.yes.tooltip = getText("IGUI_TextBox_CantBeEmpty")
		elseif text:len() > max then
			self.yes:setEnable(false)
			self.yes.tooltip = getText("IGUI_TextBox_TooManyChar", max)
		end
	end
end

local function onSealClick(target, button, player, item)
	if button.internal ~= "OK" then return end
	local values = {}
	for _, row in ipairs(button.parent.rows) do
		local v = DelNP.sanitiseInput(row.id, row.entry:getText())
		if not v then return end
		values[row.id] = v
	end
	sendClientCommand(player, "DelNP", "seal", { id = item:getID(), values = values })
end

local function onSeal(item, playerNum)
	local player = getSpecificPlayer(playerNum)
	if not player then return end
	local modal = DelNPSealBox:new(0, 0, 320, 200, getText("IGUI_DelNP_SealTitle"), "",
		nil, onSealClick, playerNum, player, item)
	modal:initialise()
	modal:addToUIManager()
	if JoypadState.players[playerNum + 1] then setJoypadFocus(playerNum, modal) end
end

local function onView(item)
	DelNPWaybillUI.open(item)
end

local function onOpen(item, playerNum)
	local player = getSpecificPlayer(playerNum)
	if not player then return end
	sendClientCommand(player, "DelNP", "open", { id = item:getID() })
end

local lastSync = {}

local function firstBox(items)
	for _, v in ipairs(items) do
		local item = v
		if not instanceof(v, "InventoryItem") then item = v.items and v.items[1] end
		if DelNP.isBox(item) then return item end
	end
	return nil
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
	local item = firstBox(items)
	if not item then return end

	if DelNP.hasWaybill(item) then
		context:addOption(getText("ContextMenu_DelNP_View"), item, onView)
	end

	-- Sealing and opening only from the player's own inventory - that is the
	-- only place the server looks.
	local player = getSpecificPlayer(playerNum)
	if not player or not player:getInventory():containsRecursive(item) then return end

	-- Staff may have corrected the waybill since: ask the server to refresh the
	-- box's copy (it decides who may open from its register anyway). At most
	-- every 10 s per box; this menu shows the copy as it is now.
	if DelNP.hasWaybill(item) then
		local now = getTimestampMs()
		lastSync[item:getID()] = lastSync[item:getID()] or 0
		if now - lastSync[item:getID()] > 10000 then
			lastSync[item:getID()] = now
			sendClientCommand(player, "DelNP", "sync", { id = item:getID() })
		end
	end

	if DelNP.isSealed(item) then
		if DelNP.canOpen(player, item) then
			context:addOption(getText("ContextMenu_DelNP_Open"), item, onOpen, playerNum)
		end
	else
		context:addOption(getText("ContextMenu_DelNP_Seal"), item, onSeal, playerNum)
	end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)

-- Server answers: show the fresh waybill, or say why nothing happened.
local function findOwnItem(id)
	local player = getPlayer()
	return player and id and player:getInventory():getItemWithIDRecursiv(id)
end

Events.OnServerCommand.Add(function(module, command, args)
	if module ~= "DelNP" then return end
	local player = getPlayer()
	if command == "sealed" then
		local item = findOwnItem(args and args.id)
		if item then
			DelNP.refreshName(item)
			DelNPWaybillUI.open(item)
		end
	elseif command == "opened" then
		local item = findOwnItem(args and args.id)
		if item then DelNP.refreshName(item) end
		if player then HaloTextHelper.addText(player, getText("IGUI_DelNP_Msg_Opened")) end
	elseif command == "msg" and player and args and args.key then
		HaloTextHelper.addText(player, getText(args.key))
	-- A parcel notification (also sent to the terminal mail): key + arguments.
	elseif command == "note" and player and args and args.key then
		local a = args.args or {}
		HaloTextHelper.addText(player, getText(args.key, a[1] and tostring(a[1]) or "", a[2] and tostring(a[2]) or "", a[3] and tostring(a[3]) or ""))
	end
end)
