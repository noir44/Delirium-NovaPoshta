--[[
Authoritative half of sealing and opening Nova Poshta boxes, and the waybill
register.

The register is an append-only file, Zomboid/Lua/DelNovaPoshta/waybills.txt,
one tab-separated line per event, written BEFORE the item is touched:

  seal2 <no> <origin> <branch> <sender> <recipient> <date> <box type> <real ms>
  open  <no> <by> <date> <real ms>
  (full list, with statuses and corrections: below, above load())

World ModData would roll back with an unsaved world (SaveWorldEveryMinutes);
this file does not, so numbers are never handed out twice. On start the file
is replayed: the highest number continues the sequence and DelNP.register
holds every waybill for whoever wants to show them (DelNP.waybills()).
A line cut short by a crash fails to parse and is skipped; every record is
written after a line break of its own so nothing gets glued to such a line.

The client only shapes the menu; every check is redone here and the box is
looked up in the sender's own inventory only.
]]

if not isServer() then return end

require "DelNP_Shared"


local MODULE = "DelNP"
local FILE = "DelNovaPoshta/waybills.txt"

DelNP.register = {}     -- no (number) -> waybill table
DelNP.lastNo = 0
local loaded = false

local function who(player)
	return tostring(player:getUsername())
end

local function field(s)
	return (string.gsub(tostring(s or ""), "[%c]", " "))
end

---- journals ------------------------------------------------------------------
-- All of the mod's records (waybills, branches, pickup requests) are
-- append-only journals in Zomboid/Lua/DelNovaPoshta/, replayed on start.

-- One record = one tab-separated line.
function DelNP.journalAppend(file, parts)
	local w = getFileWriter(file, true, true)
	if not w then
		print("DelNP: cannot write Zomboid/Lua/" .. file)
		return false
	end
	local out = {}
	for i, p in ipairs(parts) do out[i] = field(p) end
	-- Leading line break too: a line cut short by a crash would otherwise get
	-- this record glued to its end and turn into garbage that may still parse.
	w:write("\r\n" .. table.concat(out, "\t") .. "\r\n")
	w:close()
	return true
end

-- Tab-separated fields, empty ones kept. string.find only: everything here is
-- known to work in Kahlua.
function DelNP.split(line)
	local out = {}
	local pos = 1
	while true do
		local tab = string.find(line, "\t", pos, true)
		if not tab then
			table.insert(out, string.sub(line, pos))
			return out
		end
		table.insert(out, string.sub(line, pos, tab - 1))
		pos = tab + 1
	end
end

-- Calls onRecord(fields) for every line of a journal; false if there is none.
function DelNP.journalRead(file, onRecord)
	local r = getFileReader(file, false)
	if not r then return false end
	local line = r:readLine()
	while line ~= nil do
		line = string.gsub(line, "\r$", "")
		if line ~= "" then onRecord(DelNP.split(line)) end
		line = r:readLine()
	end
	r:close()
	return true
end

local function append(parts)
	return DelNP.journalAppend(FILE, parts)
end

DelNP.STATUSES = { accepted = true, transit = true, arrived = true }

--[[
waybills.txt records:
  seal2   <no> <origin> <branch> <sender> <recipient> <date> <box type> <ms>
  seal    <no> <branch> <sender> <recipient> <date> <box type> <ms>   (before origin existed)
  open    <no> <by> <date> <ms>
  status  <no> <accepted|transit|arrived> <branch> <by> <date> <ms>   (terminal, staff)
  edit    <no> <field> <value> <by> <ms>                              (terminal, staff/admin)

The register is the truth about a waybill. A box carries a copy in its
modData, refreshed whenever the server has the box at hand (DelNP.syncItem);
who may open it is decided by the register.
]]
local function newWaybill(no, origin, branch, sender, recipient, date, box, time)
	return { no = no, origin = origin, branch = branch, sender = sender, recipient = recipient,
		date = date, box = box, time = time, status = "sealed", track = {} }
end

local function load()
	loaded = true
	DelNP.register = {}
	DelNP.lastNo = 0
	DelNP.journalRead(FILE, function(p)
		local no = tonumber(p[2])
		if not no then return end
		local kind = p[1]
		if kind == "seal2" and #p == 9 and DelNP.BOXES[p[8]] and tonumber(p[9]) then
			DelNP.register[no] = newWaybill(no, p[3], p[4], p[5], p[6], p[7], p[8], tonumber(p[9]))
			if no > DelNP.lastNo then DelNP.lastNo = no end
		elseif kind == "seal" and #p == 8 and DelNP.BOXES[p[7]] and tonumber(p[8]) then
			DelNP.register[no] = newWaybill(no, "", p[3], p[4], p[5], p[6], p[7], tonumber(p[8]))
			if no > DelNP.lastNo then DelNP.lastNo = no end
		elseif not DelNP.register[no] then
			return
		elseif kind == "open" and #p == 5 and tonumber(p[5]) then
			local wb = DelNP.register[no]
			wb.status = "opened"; wb.openedBy = p[3]; wb.openedDate = p[4]; wb.openedTime = tonumber(p[5])
		elseif kind == "status" and #p == 7 and DelNP.STATUSES[p[3]] and tonumber(p[7]) then
			table.insert(DelNP.register[no].track, { status = p[3], branch = p[4], by = p[5], date = p[6] })
		elseif kind == "edit" and #p == 6 and DelNP.editable[p[3]] and tonumber(p[6]) then
			DelNP.register[no][p[3]] = p[4]
		end
	end)
	print("DelNP: register loaded, last waybill " .. DelNP.formatNo(DelNP.lastNo))
end

function DelNP.ensureLoaded()
	if not loaded then load() end
end

-- Every waybill, oldest first: for other mods (a terminal, an admin window).
function DelNP.waybills()
	DelNP.ensureLoaded()
	local list = {}
	for _, wb in pairs(DelNP.register) do table.insert(list, wb) end
	table.sort(list, function(a, b) return a.no < b.no end)
	return list
end

function DelNP.waybill(no)
	DelNP.ensureLoaded()
	return DelNP.register[tonumber(no) or -1]
end

-- A post-office status set by staff (server/DelNP_Office.lua checks who).
function DelNP.setStatus(no, status, branch, by)
	local wb = DelNP.waybill(no)
	if not wb or not DelNP.STATUSES[status] then return false end
	local date = DelNP.todayText()
	if not append({ "status", wb.no, status, branch, by, date, getTimestampMs() }) then return false end
	table.insert(wb.track, { status = status, branch = branch, by = by, date = date })
	return true
end

-- A corrected field (server/DelNP_Office.lua checks who and cleans the value).
function DelNP.editField(no, fieldId, value, by)
	local wb = DelNP.waybill(no)
	if not wb or not DelNP.editable[fieldId] then return false end
	if not append({ "edit", wb.no, fieldId, value, by, getTimestampMs() }) then return false end
	wb[fieldId] = value
	return true
end

-- Branch rules live in server/DelNP_Office.lua; without branches anything goes.
local function branchKnown(num)
	if DelNP.hasBranches and DelNP.hasBranches() then return DelNP.branchExists(num) end
	return true
end
DelNP.branchKnown = branchKnown

-- What a client gets to draw a waybill or a status card.
function DelNP.waybillView(wb)
	local track = {}
	for i, t in ipairs(wb.track or {}) do
		track[i] = { status = t.status, branch = t.branch, by = t.by, date = t.date }
	end
	local name = DelNP.branchName or function() return nil end
	return {
		no = DelNP.formatNo(wb.no), origin = wb.origin, originName = name(wb.origin),
		branch = wb.branch, branchName = name(wb.branch),
		sender = wb.sender, recipient = wb.recipient, date = wb.date, box = wb.box,
		sealed = wb.status == "sealed", openedBy = wb.openedBy, openedDate = wb.openedDate, track = track,
	}
end

-- Copy the register's waybill onto the box the server has at hand.
function DelNP.syncItem(player, item)
	local wb = DelNP.waybill(DelNP.value(item, "no"))
	if not wb then return end
	local md = item:getModData()
	local changed = false
	for _, id in ipairs(DelNP.editOrder) do
		local v = wb[id] ~= "" and wb[id] or nil
		if md["DelNP_" .. id] ~= v then md["DelNP_" .. id] = v; changed = true end
	end
	if changed then syncItemModData(player, item) end
end

local function tell(player, key)
	sendServerCommand(player, MODULE, "msg", { key = key })
end

local function findBox(player, id)
	if not id then return nil end
	local inv = player:getInventory()
	local item = inv and inv:getItemWithIDRecursiv(id)
	if item and DelNP.isBox(item) then return item end
	return nil
end

local function onSeal(player, args)
	local item = findBox(player, args and args.id)
	if not item then
		print("DelNP: seal refused, no box " .. tostring(args and args.id) .. " in " .. who(player) .. "'s inventory")
		return
	end
	if DelNP.isSealed(item) then
		print("DelNP: seal refused, box already sealed [" .. tostring(DelNP.value(item, "no")) .. "], attempt by " .. who(player))
		return
	end
	local sent = type(args.values) == "table" and args.values or {}
	local values = {}
	for _, id in ipairs(DelNP.inputOrder) do
		local v = DelNP.sanitiseInput(id, sent[id])
		if not v then
			print("DelNP: seal refused, missing or invalid '" .. id .. "' from " .. who(player))
			tell(player, "IGUI_DelNP_Msg_Invalid")
			return
		end
		values[id] = v
	end
	for _, id in ipairs({ "origin", "branch" }) do
		if not branchKnown(values[id]) then
			print("DelNP: seal refused, no branch " .. values[id] .. " (" .. id .. ") from " .. who(player))
			tell(player, "IGUI_DelNP_Msg_NoBranch")
			return
		end
	end

	-- Never number from an unread register.
	DelNP.ensureLoaded()
	local no = DelNP.lastNo + 1
	local wb = newWaybill(no, values.origin, values.branch, who(player), values.recipient,
		DelNP.todayText(), item:getFullType(), getTimestampMs())
	-- The register first: a number written there is spent even if the world
	-- (and with it this box) rolls back.
	if not append({ "seal2", no, wb.origin, wb.branch, wb.sender, wb.recipient, wb.date, wb.box, wb.time }) then
		tell(player, "IGUI_DelNP_Msg_Failed")
		return
	end
	DelNP.lastNo = no
	DelNP.register[no] = wb

	local md = item:getModData()
	md.DelNP_no = DelNP.formatNo(no)
	md.DelNP_openedBy = nil
	md.DelNP_openedDate = nil
	md.DelNP_sealed = true
	for _, id in ipairs(DelNP.editOrder) do md["DelNP_" .. id] = wb[id] end
	syncItemModData(player, item)

	print("DelNP: " .. who(player) .. " sealed " .. wb.box .. " [" .. md.DelNP_no .. "] to " ..
		wb.recipient .. ", branch " .. wb.origin .. " -> " .. wb.branch)
	sendServerCommand(player, MODULE, "sealed", { id = item:getID() })
end

local function onOpen(player, args)
	local item = findBox(player, args and args.id)
	if not item then
		print("DelNP: open refused, no box " .. tostring(args and args.id) .. " in " .. who(player) .. "'s inventory")
		return
	end
	if not DelNP.isSealed(item) then return end
	-- The register decides: a recipient corrected by staff counts at once.
	DelNP.syncItem(player, item)
	local noText = tostring(DelNP.value(item, "no"))
	if not DelNP.canOpen(player, item) then
		print("DelNP: open refused, " .. who(player) .. " is neither the recipient of [" .. noText .. "] nor an admin")
		tell(player, "IGUI_DelNP_Msg_NotYours")
		return
	end
	-- Not before the delivery is paid (server/DelNP_Money.lua); admins may.
	if DelNP.isPaid and not DelNP.isAdmin(player) and not DelNP.isPaid(noText) then
		print("DelNP: open refused, [" .. noText .. "] is not paid yet, attempt by " .. who(player))
		tell(player, "IGUI_DelNP_Msg_NotPaid")
		return
	end

	local date = DelNP.todayText()
	local no = tonumber(noText)
	append({ "open", noText, who(player), date, getTimestampMs() })
	local wb = no and DelNP.register[no]
	if wb then wb.status = "opened"; wb.openedBy = who(player); wb.openedDate = date end

	local md = item:getModData()
	md.DelNP_sealed = false
	md.DelNP_openedBy = who(player)
	md.DelNP_openedDate = date
	syncItemModData(player, item)
	print("DelNP: " .. who(player) .. " opened [" .. noText .. "]")
	sendServerCommand(player, MODULE, "opened", { id = item:getID() })
end

-- The waybill sheet asks for the register's version (with branch names and
-- the latest status); a box in the asker's own inventory is refreshed too.
local function onView(player, args)
	local wb = DelNP.waybill(args and args.no)
	if not wb then
		sendServerCommand(player, MODULE, "view", { no = args and args.no, missing = true })
		return
	end
	local item = args.id and findBox(player, args.id)
	if item then DelNP.syncItem(player, item) end
	sendServerCommand(player, MODULE, "view", { no = DelNP.formatNo(wb.no), wb = DelNP.waybillView(wb) })
end

local function onSync(player, args)
	local item = findBox(player, args and args.id)
	if item then DelNP.syncItem(player, item) end
end

Events.OnServerStarted.Add(load)

Events.OnClientCommand.Add(function(module, command, player, args)
	if module ~= MODULE or not player then return end
	if command == "seal" then onSeal(player, args)
	elseif command == "open" then onOpen(player, args)
	elseif command == "view" then onView(player, args)
	elseif command == "sync" then onSync(player, args) end
end)
