--[[
The waybill of a box: the sheet artwork with the waybill's values written into
its frames. A plain ISPanel, like the Delirium License sheet - vanilla has no
item that shows a page image.
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

function DelNPWaybillUI:render()
	if self.texture then
		self:drawTextureScaledAspect(self.texture, 0, 0, self.width, self.height, 1, 1, 1, 1)
	end
	local tm = getTextManager()
	for id, f in pairs(DelNP.fields) do
		local text = DelNP.value(self.item, id)
		if text then
			local pad = 0.012 * self.width
			local left, right = f.x1 * self.width + pad, f.x2 * self.width - pad
			local font = fontFor(text, right - left)
			-- Vertically centred in the frame.
			local y = ((f.y1 + f.y2) / 2) * self.height - tm:getFontHeight(font) / 2
			self:drawText(text, left, y, 0.08, 0.07, 0.05, 1, font)
		end
	end
	-- An opened box says so in red, in the free space right of the date frame.
	if not DelNP.isSealed(self.item) and DelNP.value(self.item, "openedBy") then
		local text = getText("IGUI_DelNP_OpenedStamp", DelNP.value(self.item, "openedBy"), DelNP.value(self.item, "openedDate") or "")
		local d = DelNP.fields.date
		local left, right = 0.59 * self.width, 0.948 * self.width
		local font = fontFor(text, right - left)
		local y = ((d.y1 + d.y2) / 2) * self.height - tm:getFontHeight(font) / 2
		self:drawText(text, right - tm:MeasureStringX(font, text), y, 0.75, 0.08, 0.08, 1, font)
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
end
