--[[
Sealing a Nova Poshta box: shared rules.

A sealed box carries a waybill in its modData (DelNP_<field>). While it is
sealed nobody can look into it or move items in or out; the recipient named on
the waybill, or an admin, opens it ("unseals"), after which it is an ordinary
box again until it is sealed anew. The server numbers waybills and keeps every
seal and opening in its own file (server/DelNP_Server.lua).
]]

DelNP = DelNP or {}

DelNP.BOXES = {
	["DelNP.Box5"] = true,
	["DelNP.Box10"] = true,
	["DelNP.Box25"] = true,
}

-- What the sealer types: where the parcel is sent from (origin), where it
-- goes (branch) and the recipient's login. Origin and branch are a branch
-- number or, for a courier pickup or an address delivery, an address in words
-- (DelNP.isBranchNo tells them apart). The waybill number, the sender (login)
-- and the date are never typed: the server fills them in.
DelNP.PLACE_MAX = 60
DelNP.inputs = {
	origin    = { max = DelNP.PLACE_MAX },
	branch    = { max = DelNP.PLACE_MAX },
	recipient = { max = 40 },
}
DelNP.inputOrder = { "origin", "branch", "recipient" }

-- What staff and admins may correct afterwards (terminal desk). The number is
-- the waybill's identity and stays.
DelNP.editable = {
	origin    = { max = DelNP.PLACE_MAX },
	branch    = { max = DelNP.PLACE_MAX },
	sender    = { max = 40 },
	recipient = { max = 40 },
	date      = { max = 10 },
}
DelNP.editOrder = { "origin", "branch", "sender", "recipient", "date" }

-- The waybill sheet (media/ui/DelNP_Waybill_UA.png, 1:1): the inside of each
-- frame as fractions of the picture, measured by scanning the artwork for the
-- frames' dark border runs (NP2.png, 1254 px: x 395..1195, date 395..739;
-- y 332/403, 430/514, 543/629, 655/730, 755/837, 861/931).
DelNP.sheet = "media/ui/DelNP_Waybill_UA.png"
DelNP.fields = {
	no        = { x1 = 0.318, x2 = 0.950, y1 = 0.265, y2 = 0.321 },
	origin    = { x1 = 0.318, x2 = 0.950, y1 = 0.343, y2 = 0.410 },
	branch    = { x1 = 0.318, x2 = 0.950, y1 = 0.433, y2 = 0.502 },
	sender    = { x1 = 0.318, x2 = 0.950, y1 = 0.522, y2 = 0.582 },
	recipient = { x1 = 0.318, x2 = 0.950, y1 = 0.602, y2 = 0.667 },
	date      = { x1 = 0.318, x2 = 0.586, y1 = 0.687, y2 = 0.742 },
}
-- Free space right of the date frame: the "opened" / status mark.
DelNP.stampArea = { x1 = 0.610, x2 = 0.950 }

-- One value cleaned for storage: one line, trimmed, capped, digits only where
-- asked. nil when unusable. Runs on the server for everything a client sends.
function DelNP.clean(spec, text)
	if not spec or type(text) ~= "string" then return nil end
	text = text:gsub("[%c]", " ")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil end
	if #text > spec.max then text = text:sub(1, spec.max) end
	if spec.numeric and not text:match("^%d+$") then return nil end
	return text
end

-- A place written as digits only is a branch number (and must exist when the
-- server has branches); anything else is an address.
function DelNP.isBranchNo(text)
	return type(text) == "string" and #text <= 5 and text:match("^%d+$") ~= nil
end

-- Who may pay for the delivery: the sender or the recipient.
function DelNP.isParty(login, wb)
	login = string.lower(tostring(login or ""))
	return login ~= "" and (login == string.lower(tostring(wb.sender or "")) or login == string.lower(tostring(wb.recipient or "")))
end

function DelNP.isBox(item)
	return item ~= nil and DelNP.BOXES[item:getFullType()] == true
end

function DelNP.value(item, id)
	local v = item:getModData()["DelNP_" .. id]
	if v == nil or v == "" then return nil end
	return tostring(v)
end

-- Has a waybill at all (sealed now, or opened since).
function DelNP.hasWaybill(item)
	return DelNP.isBox(item) and DelNP.value(item, "no") ~= nil
end

function DelNP.isSealed(item)
	return DelNP.isBox(item) and item:getModData().DelNP_sealed == true
end

-- The box whose contents this container is, if it is a sealed one.
function DelNP.sealedBoxOf(container)
	if not container or not container.getContainingItem then return nil end
	local item = container:getContainingItem()
	if item and DelNP.isSealed(item) then return item end
	return nil
end

function DelNP.formatNo(n)
	return string.format("%07d", math.floor(tonumber(n) or 0))
end

function DelNP.todayText()
	local gt = getGameTime()
	return string.format("%02d.%02d.%d", gt:getDay() + 1, gt:getMonth() + 1, gt:getYear())
end

-- Copy of DelShops.hasAdminRights: plain isAdmin() means nothing server-side.
function DelNP.isAdmin(player)
	if not player then return false end
	if player.getAccessLevel and player:getAccessLevel() == "admin" then return true end
	local role = player.getRole and player:getRole()
	if role and role.hasCapability and Capability and Capability.CanSetupNonPVPZone then
		if role:hasCapability(Capability.CanSetupNonPVPZone) then return true end
	end
	if role and role.hasAdminPower and role:hasAdminPower() then return true end
	return false
end

-- The recipient is written as a login; compared without case.
function DelNP.isRecipient(player, item)
	local r = DelNP.value(item, "recipient")
	return player ~= nil and r ~= nil and string.lower(r) == string.lower(tostring(player:getUsername()))
end

function DelNP.canOpen(player, item)
	return DelNP.isSealed(item) and (DelNP.isAdmin(player) or DelNP.isRecipient(player, item))
end

--[[
One typed value: one line, trimmed, length-capped, digits only for numeric
inputs. Runs on the server too - the client may send anything. nil when
unusable.
]]
function DelNP.sanitiseInput(id, text)
	return DelNP.clean(DelNP.inputs[id], text)
end

-- Visible name: the box's own name plus the waybill number while sealed.
-- Built on each client in its own language (see client/DelNP_Display.lua).
function DelNP.refreshName(item)
	if not DelNP.isBox(item) then return end
	local base = getItemNameFromFullType(item:getFullType())
	local name = base
	if DelNP.isSealed(item) then
		name = getText("IGUI_DelNP_SealedName", base, DelNP.value(item, "no") or "?")
	end
	if item:getName() == name then return end
	item:setName(name)
	item:setCustomName(name ~= base)
end
