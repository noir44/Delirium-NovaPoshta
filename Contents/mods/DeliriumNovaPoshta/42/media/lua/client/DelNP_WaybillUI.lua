--[[
The waybill of a box: the sheet artwork with the waybill's values written into
its frames. A plain ISPanel, like the Delirium License sheet - vanilla has no
item that shows a page image.

The register on the server is the truth (staff may have corrected a login or a
branch since the box was sealed): the sheet opens with the copy the box
carries and redraws with the server's version, branch names and latest status
included, as soon as it arrives.
]]

if isServer() then return end

require "ISUI/ISPanel"
require "DelNP_Shared"

DelNPWaybillUI = ISPanel:derive("DelNPWaybillUI")

local SCREEN_FRACTION = 0.8

-- Largest font that fits the frame.
local function fontFor(text, maxWidth)
	local tm = getTextManager()
	for _, font in ipairs({ UIFont.Large, UIFont.Medium, UIFont.Small }) do
		if tm:MeasureStringX(font, text) <= maxWidth then return font end
	end
	return UIFont.Small
end

-- Cut to the frame with "..." when even the small font is too wide (an address).
local function fitText(text, maxWidth)
	local tm = getTextManager()
	if tm:MeasureStringX(UIFont.Small, text) <= maxWidth then return text end
	while #text > 1 and tm:MeasureStringX(UIFont.Small, text .. "...") > maxWidth do
		text = text:sub(1, #text - 1)
	end
	return text .. "..."
end

-- The box's own copy, in the shape of the server's waybill view.
local function fromItem(item)
	local d = {}
	for _, id in ipairs({ "no", "origin", "branch", "sender", "recipient", "date", "openedBy", "openedDate" }) do
		d[id] = DelNP.value(item, id)
	end
	d.sealed = DelNP.isSealed(item)
	return d
end

local function branchText(num, name)
	if not num then return nil end
	if name and name ~= "" then return getText("IGUI_DelNP_BranchWithName", num, name) end
	return num
end

function DelNPWaybillUI:valueOf(id)
	local d = self.data
	if id == "origin" then return branchText(d.origin, d.originName) end
	if id == "branch" then return branchText(d.branch, d.branchName) end
	return d[id]
end

function DelNPWaybillUI:render()
	if self.texture then
		self:drawTextureScaledAspect(self.texture, 0, 0, self.width, self.height, 1, 1, 1, 1)
	end
	local tm = getTextManager()
	for id, f in pairs(DelNP.fields) do
		local text = self:valueOf(id)
		if text then
			text = tostring(text)
			local pad = 0.012 * self.width
			local left, right = f.x1 * self.width + pad, f.x2 * self.width - pad
			text = fitText(text, right - left)
			local font = fontFor(text, right - left)
			-- Vertically centred in the frame.
			local y = ((f.y1 + f.y2) / 2) * self.height - tm:getFontHeight(font) / 2
			self:drawText(text, left, y, 0.08, 0.07, 0.05, 1, font)
		end
	end

	-- Right of the date frame: "opened" in red, else the latest post status.
	local d = self.data
	local stamp, r, g, b
	if not d.sealed and d.openedBy then
		stamp = getText("IGUI_DelNP_OpenedStamp", d.openedBy, d.openedDate or "")
		r, g, b = 0.75, 0.08, 0.08
	elseif d.track and #d.track > 0 then
		local t = d.track[#d.track]
		stamp = getText("IGUI_DelNP_StatusStamp", getText("IGUI_DelNP_St_" .. tostring(t.status)), t.branch or "?")
		r, g, b = 0.10, 0.35, 0.12
	end
	if stamp then
		local f = DelNP.fields.date
		local left, right = DelNP.stampArea.x1 * self.width, DelNP.stampArea.x2 * self.width
		local font = fontFor(stamp, right - left)
		local y = ((f.y1 + f.y2) / 2) * self.height - tm:getFontHeight(font) / 2
		self:drawText(stamp, right - tm:MeasureStringX(font, stamp), y, r, g, b, 1, font)
	end
end

function DelNPWaybillUI:onMouseDown() self:close(); return true end
function DelNPWaybillUI:onRightMouseDown() self:close(); return true end
function DelNPWaybillUI:onKeyRelease(key)
	if key == Keyboard.KEY_ESCAPE then self:close() end
end

function DelNPWaybillUI:close()
	self:setVisible(false)
	self:removeFromUIManager()
	if DelNPWaybillUI.instance == self then DelNPWaybillUI.instance = nil end
end

function DelNPWaybillUI:new(item)
	local o = ISPanel:new(0, 0, 10, 10)
	setmetatable(o, self)
	self.__index = self
	o.item = item
	o.data = fromItem(item)
	o.texture = getTexture(DelNP.sheet)
	o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
	o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
	o.moveWithMouse = true
	local size = getCore():getScreenHeight() * SCREEN_FRACTION
	o:setWidth(size)
	o:setHeight(size)
	o:setX((getCore():getScreenWidth() - size) / 2)
	o:setY((getCore():getScreenHeight() - size) / 2)
	return o
end

function DelNPWaybillUI.open(item)
	if not DelNP.hasWaybill(item) then return end
	if DelNPWaybillUI.instance then DelNPWaybillUI.instance:close() end
	local ui = DelNPWaybillUI:new(item)
	ui:initialise()
	ui:instantiate()
	ui:addToUIManager()
	DelNPWaybillUI.instance = ui
	sendClientCommand(getPlayer(), "DelNP", "view", { no = ui.data.no, id = item:getID() })
end

-- The server's version of the waybill on screen.
Events.OnServerCommand.Add(function(module, command, args)
	if module ~= "DelNP" or command ~= "view" or not args or not args.wb then return end
	local ui = DelNPWaybillUI.instance
	if ui and ui.data.no == args.no then ui.data = args.wb end
end)
