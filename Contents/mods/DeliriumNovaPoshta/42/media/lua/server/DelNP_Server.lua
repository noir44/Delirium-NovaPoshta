--[[
Authoritative half of sealing and opening Nova Poshta boxes, and the waybill
register.

The register is an append-only file, Zomboid/Lua/DelNovaPoshta/waybills.txt,
one tab-separated line per event, written BEFORE the item is touched:

  seal  <no>  <branch>  <sender>  <recipient>  <date>  <box type>  <real ms>
  open  <no>  <by>  <date>  <real ms>

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
  seal    <no> <branch> <sender> <recipient> <date> <box type> <ms>
  open    <no> <by> <date> <ms>
  status  <no> <accepted|transit|arrived> <branch> <by> <date> <ms>   (terminal, staff)
]]
local function load()
	loaded = true
	DelNP.register = {}
	DelNP.lastNo = 0
	DelNP.journalRead(FILE, function(p)
		local no = tonumber(p[2])
		if p[1] == "seal" and no and #p == 8 and DelNP.BOXES[p[7]] and tonumber(p[8]) then
			DelNP.register[no] = {
				no = no, branch = p[3], sender = p[4], recipient = p[5],
				date = p[6], box = p[7], time = tonumber(p[8]), status = "sealed", track = {},
			}
			if no > DelNP.lastNo then DelNP.lastNo = no end
		elseif p[1] == "open" and no and #p == 5 and tonumber(p[5]) and DelNP.register[no] then
			local wb = DelNP.register[no]
			wb.status = "opened"; wb.openedBy = p[3]; wb.openedDate = p[4]; wb.openedTime = tonumber(p[5])
		elseif p[1] == "status" and no and #p == 7 and DelNP.STATUSES[p[3]] and tonumber(p[7]) and DelNP.register[no] then
			table.insert(DelNP.register[no].track, { status = p[3], branch = p[4], by = p[5], date = p[6] })
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

-- A post-office status set by staff (server/DelNP_Office.lua checks who).
function DelNP.setStatus(no, status, branch, by)
	DelNP.ensureLoaded()
	local wb = DelNP.register[no]
	if not wb or not DelNP.STATUSES[status] then return false end
	local date = DelNP.todayText()
	if not append({ "status", no, status, branch, by, date, getTimestampMs() }) then return false end
	table.insert(wb.track, { status = status, branch = branch, by = by, date = date })
	return true
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

	-- Never number from an unread register.
	DelNP.ensureLoaded()
	local no = DelNP.lastNo + 1
	local wb = {
		no = no, branch = values.branch, sender = who(player), recipient = values.recipient,
		date = DelNP.todayText(), box = item:getFullType(), time = getTimestampMs(), status = "sealed", track = {},
	}
	-- The register first: a number written there is spent even if the world
	-- (and with it this box) rolls back.
	if not append({ "seal", no, wb.branch, wb.sender, wb.recipient, wb.date, wb.box, wb.time }) then
		tell(player, "IGUI_DelNP_Msg_Failed")
		return
	end
	DelNP.lastNo = no
	DelNP.register[no] = wb

	local md = item:getModData()
	md.DelNP_no = DelNP.formatNo(no)
	md.DelNP_branch = wb.branch
	md.DelNP_sender = wb.sender
	md.DelNP_recipient = wb.recipient
	md.DelNP_date = wb.date
	md.DelNP_openedBy = nil
	md.DelNP_openedDate = nil
	md.DelNP_sealed = true
	syncItemModData(player, item)

	print("DelNP: " .. who(player) .. " sealed " .. wb.box .. " [" .. md.DelNP_no .. "] to " ..
		wb.recipient .. ", branch " .. wb.branch)
	sendServerCommand(player, MODULE, "sealed", { id = item:getID() })
end

local function onOpen(player, args)
	local item = findBox(player, args and args.id)
	if not item then
		print("DelNP: open refused, no box " .. tostring(args and args.id) .. " in " .. who(player) .. "'s inventory")
		return
	end
	local noText = tostring(DelNP.value(item, "no"))
	if not DelNP.isSealed(item) then return end
	if not DelNP.canOpen(player, item) then
		print("DelNP: open refused, " .. who(player) .. " is neither the recipient of [" .. noText .. "] nor an admin")
		tell(player, "IGUI_DelNP_Msg_NotYours")
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

Events.OnServerStarted.Add(load)

Events.OnClientCommand.Add(function(module, command, player, args)
	if module ~= MODULE or not player then return end
	if command == "seal" then onSeal(player, args)
	elseif command == "open" then onOpen(player, args) end
end)
