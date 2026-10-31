--[[
Delirium Express in the Delirium Terminal: the server half.

Who you are is your game login (player:getUsername()), the same login the
waybill names as sender and recipient - not the terminal account you logged
in with. A command is served only from a computer that has a terminal session
open and only to a player standing at it (as the terminal's own files).

Roles:
  admin      everything (DelNP.isAdmin)
  director   of a branch: adds and removes that branch's staff, and is staff
  staff      of a branch: sets parcel statuses for that branch, closes
             pickup requests
  anyone     pickup requests of their own, status of any parcel by number,
             list of their own parcels, prices

Data, all append-only journals in Zomboid/Lua/DelNovaPoshta/ (world ModData
would roll back with an unsaved world):
  org.txt       branch    <num> <name> <director> <by> <ms>   create / update
                branchdel <num> <by> <ms>
                staff     <num> <login> <by> <ms>
                staffdel  <num> <login> <by> <ms>
  requests.txt  req       <id> <user> <branch> <address> <comment> <date> <ms>
                reqdone   <id> <by> <date> <ms>
  waybills.txt  status    lines, see server/DelNP_Server.lua
  prices.txt    plain text, rewritten by the admin from the terminal; may also
                be edited by hand on the server, it is read on every request.
]]

if not isServer() then return end

require "DelNP_Shared"
require "DelNP_Server"
require "DelNP_Money"

local MODULE = "DelNP"
local ORG = "DelNovaPoshta/org.txt"
local REQ = "DelNovaPoshta/requests.txt"
local PRICES = "DelNovaPoshta/prices.txt"

local NAME_MAX, LOGIN_MAX, ADDRESS_MAX, COMMENT_MAX = 40, 40, 80, 160
local PRICES_MAX = 4000
local OPEN_REQUESTS_PER_USER = 5
local ACCESS_DIST = 6

DelNP.branches = {}   -- num (string) -> { num, name, director, staff = { [lower login] = login } }
DelNP.requests = {}   -- id -> { id, user, branch, address, comment, date, status, doneBy, doneDate }
DelNP.lastRequest = 0
local orgLoaded, reqLoaded = false, false

local function lower(s) return string.lower(tostring(s or "")) end
local function who(player) return tostring(player:getUsername()) end
local function trim(s) return (string.match(tostring(s or ""), "^%s*(.-)%s*$")) or "" end

local function clean(text, max, numeric)
	if type(text) ~= "string" then return nil end
	text = text:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil end
	if #text > max then text = text:sub(1, max) end
	if numeric and not text:match("^%d+$") then return nil end
	return text
end

---- loading ------------------------------------------------------------------

local function loadOrg()
	orgLoaded = true
	DelNP.branches = {}
	DelNP.journalRead(ORG, function(p)
		local kind, num = p[1], p[2]
		if not num or not num:match("^%d+$") then return end
		if kind == "branch" and #p == 6 and tonumber(p[6]) then
			local b = DelNP.branches[num] or { num = num, staff = {} }
			b.name = p[3]; b.director = p[4] ~= "" and p[4] or nil
			DelNP.branches[num] = b
		elseif kind == "branchdel" and #p == 4 and tonumber(p[4]) then
			DelNP.branches[num] = nil
		elseif kind == "staff" and #p == 5 and tonumber(p[5]) and DelNP.branches[num] and p[3] ~= "" then
			DelNP.branches[num].staff[lower(p[3])] = p[3]
		elseif kind == "staffdel" and #p == 5 and tonumber(p[5]) and DelNP.branches[num] then
			DelNP.branches[num].staff[lower(p[3])] = nil
		end
	end)
end

local function loadRequests()
	reqLoaded = true
	DelNP.requests = {}
	DelNP.lastRequest = 0
	DelNP.journalRead(REQ, function(p)
		local id = tonumber(p[2])
		if not id then return end
		if p[1] == "req" and #p == 8 and tonumber(p[8]) then
			DelNP.requests[id] = { id = id, user = p[3], branch = p[4], address = p[5], comment = p[6], date = p[7], status = "open" }
			if id > DelNP.lastRequest then DelNP.lastRequest = id end
		elseif p[1] == "reqdone" and #p == 5 and tonumber(p[5]) and DelNP.requests[id] then
			local r = DelNP.requests[id]
			r.status = "done"; r.doneBy = p[3]; r.doneDate = p[4]
		end
	end)
end

local function org()
	if not orgLoaded then loadOrg() end
	return DelNP.branches
end

-- For the sealing rules (server/DelNP_Server.lua) and the waybill cards.
function DelNP.hasBranches()
	for _ in pairs(org()) do return true end
	return false
end
function DelNP.branchExists(num) return num ~= nil and org()[tostring(num)] ~= nil end
function DelNP.branchName(num)
	local b = num and org()[tostring(num)]
	return b and b.name or nil
end

local function requests()
	if not reqLoaded then loadRequests() end
	return DelNP.requests
end

---- roles --------------------------------------------------------------------

local function isDirector(login, num)
	local b = org()[num]
	return b ~= nil and b.director ~= nil and lower(b.director) == lower(login)
end

local function isStaffOf(login, num)
	local b = org()[num]
	return b ~= nil and (isDirector(login, num) or b.staff[lower(login)] ~= nil)
end

-- Sorted branch numbers where this login directs / works.
local function rolesOf(login)
	local directs, works = {}, {}
	for num, _ in pairs(org()) do
		if isDirector(login, num) then table.insert(directs, num) end
		if isStaffOf(login, num) then table.insert(works, num) end
	end
	local byNum = function(a, b) return tonumber(a) < tonumber(b) end
	table.sort(directs, byNum); table.sort(works, byNum)
	return directs, works
end

local function isAnyStaff(player)
	if DelNP.isAdmin(player) then return true end
	local _, works = rolesOf(who(player))
	return #works > 0
end

---- access -------------------------------------------------------------------

-- Same rule as the terminal's own files: a live session on that computer and
-- the player standing at it. Without the terminal mod nothing is served.
local function atTerminal(player, computerId)
	if not (DelTerm_Data and DelTerm_Data.sessions and computerId) then return false end
	if not DelTerm_Data.sessions[computerId] then return false end
	-- The terminal's own rule (computer in reach, or an open charged laptop in hand).
	if DelTerm_AtTerminal then return DelTerm_AtTerminal(player, computerId, ACCESS_DIST) end
	local x, y, z = string.match(tostring(computerId), "(-?%d+),(-?%d+),(-?%d+)")
	if not x then return false end
	if math.floor(player:getZ()) ~= tonumber(z) then return false end
	local dx, dy = player:getX() - tonumber(x), player:getY() - tonumber(y)
	return dx * dx + dy * dy <= ACCESS_DIST * ACCESS_DIST
end

---- replies ------------------------------------------------------------------

local function reply(player, command, computerId, args)
	args = args or {}
	args.computerId = computerId
	sendServerCommand(player, MODULE, command, args)
end

-- msg is a code the client shows as IGUI_DelNP_TMsg_<code>, arg fills its %1.
local function result(player, computerId, ok, msg, arg)
	reply(player, "T_Result", computerId, { ok = ok, msg = msg, arg = arg })
end

local function waybillView(wb)
	local v = DelNP.waybillView(wb)
	v.pay = DelNP.paymentView(wb.no)
	v.money = DelNP.moneyEnabled()
	return v
end

local function branchList()
	local list = {}
	for num, b in pairs(org()) do
		local staff = {}
		for _, login in pairs(b.staff) do table.insert(staff, login) end
		table.sort(staff, function(a, c) return lower(a) < lower(c) end)
		table.insert(list, { num = num, name = b.name, director = b.director, staff = staff })
	end
	table.sort(list, function(a, c) return tonumber(a.num) < tonumber(c.num) end)
	return list
end

local function requestView(r)
	return { id = r.id, user = r.user, branch = r.branch, address = r.address, comment = r.comment,
		date = r.date, status = r.status, doneBy = r.doneBy, doneDate = r.doneDate }
end

local function readPrices()
	local lines = {}
	local r = getFileReader(PRICES, false)
	if r then
		local line = r:readLine()
		while line ~= nil do
			table.insert(lines, (string.gsub(line, "\r$", "")))
			line = r:readLine()
		end
		r:close()
	end
	return table.concat(lines, "\n")
end

---- commands -----------------------------------------------------------------

local handlers = {}

function handlers.T_Home(player, args, cid)
	local directs, works = rolesOf(who(player))
	reply(player, "T_Home", cid, { me = who(player), isAdmin = DelNP.isAdmin(player), directs = directs, works = works })
end

function handlers.T_Track(player, args, cid)
	DelNP.ensureLoaded()
	local no = tonumber(args.no)
	local wb = no and DelNP.register[no]
	reply(player, "T_Track", cid, { wb = wb and waybillView(wb) or nil, asked = tostring(args.no or "") })
end

-- The player's own parcels, sent or to receive, newest first.
function handlers.T_Mine(player, args, cid)
	local me = lower(who(player))
	local list = {}
	local all = DelNP.waybills()
	for i = #all, 1, -1 do
		local wb = all[i]
		if lower(wb.sender) == me or lower(wb.recipient) == me then
			table.insert(list, waybillView(wb))
			if #list >= 30 then break end
		end
	end
	reply(player, "T_Mine", cid, { list = list })
end

local function sendRequests(player, cid)
	local me = lower(who(player))
	local staff = isAnyStaff(player)
	local mine, all = {}, {}
	local ids = {}
	for id, _ in pairs(requests()) do table.insert(ids, id) end
	table.sort(ids, function(a, b) return a > b end)
	for _, id in ipairs(ids) do
		local r = DelNP.requests[id]
		if lower(r.user) == me and #mine < 20 then table.insert(mine, requestView(r)) end
		if staff and (r.status == "open" or #all < 40) then table.insert(all, requestView(r)) end
	end
	reply(player, "T_Requests", cid, { mine = mine, all = staff and all or nil, isStaff = staff, branches = branchList() })
end

function handlers.T_Requests(player, args, cid) sendRequests(player, cid) end

function handlers.T_ReqCreate(player, args, cid)
	local branch = clean(args.branch, 5, true)
	local address = clean(args.address, ADDRESS_MAX)
	local comment = clean(args.comment, COMMENT_MAX) or ""
	if not branch or not address then return result(player, cid, false, "ReqFields") end
	if not org()[branch] then return result(player, cid, false, "NoBranch", branch) end
	local me = who(player)
	local open = 0
	for _, r in pairs(requests()) do
		if r.status == "open" and lower(r.user) == lower(me) then open = open + 1 end
	end
	if open >= OPEN_REQUESTS_PER_USER then return result(player, cid, false, "ReqTooMany", OPEN_REQUESTS_PER_USER) end
	local id = DelNP.lastRequest + 1
	local date = DelNP.todayText()
	if not DelNP.journalAppend(REQ, { "req", id, me, branch, address, comment, date, getTimestampMs() }) then
		return result(player, cid, false, "Failed")
	end
	DelNP.lastRequest = id
	DelNP.requests[id] = { id = id, user = me, branch = branch, address = address, comment = comment, date = date, status = "open" }
	print("DelNP: pickup request #" .. id .. " by " .. me .. " to branch " .. branch)
	result(player, cid, true, "ReqCreated", id)
	sendRequests(player, cid)
end

function handlers.T_ReqClose(player, args, cid)
	local id = tonumber(args.id)
	local r = id and requests()[id]
	if not r then return result(player, cid, false, "ReqNotFound", tostring(args.id or "")) end
	-- Staff of the branch it was sent to, or an admin.
	if not (DelNP.isAdmin(player) or isStaffOf(who(player), r.branch)) then
		return result(player, cid, false, "NotStaffOf", r.branch)
	end
	if r.status ~= "open" then return result(player, cid, false, "ReqClosed", id) end
	local date = DelNP.todayText()
	if not DelNP.journalAppend(REQ, { "reqdone", id, who(player), date, getTimestampMs() }) then
		return result(player, cid, false, "Failed")
	end
	r.status = "done"; r.doneBy = who(player); r.doneDate = date
	result(player, cid, true, "ReqDone", id)
	sendRequests(player, cid)
end

local function sendBranches(player, cid)
	local directs = rolesOf(who(player))
	-- Cash desks: shown to the branch's director and to admins only.
	local list = branchList()
	local admin = DelNP.isAdmin(player)
	for _, b in ipairs(list) do
		if DelNP.moneyEnabled() and (admin or isDirector(who(player), b.num)) then b.desk = DelNP.fmt(DelNP.deskAmount(b.num)) end
	end
	reply(player, "T_Branches", cid, { list = list, isAdmin = admin, directs = directs, money = DelNP.moneyEnabled() })
end

function handlers.T_Branches(player, args, cid) sendBranches(player, cid) end

function handlers.T_BranchSave(player, args, cid)
	if not DelNP.isAdmin(player) then return result(player, cid, false, "AdminOnly") end
	local num = clean(args.num, 5, true)
	local name = clean(args.name, NAME_MAX)
	local director = clean(args.director, LOGIN_MAX) or ""
	if not num or not name then return result(player, cid, false, "BranchFields") end
	local existed = org()[num] ~= nil
	if not DelNP.journalAppend(ORG, { "branch", num, name, director, who(player), getTimestampMs() }) then
		return result(player, cid, false, "Failed")
	end
	local b = DelNP.branches[num] or { num = num, staff = {} }
	b.name = name; b.director = director ~= "" and director or nil
	DelNP.branches[num] = b
	print("DelNP: " .. who(player) .. (existed and " updated" or " created") .. " branch " .. num .. " (" .. name .. "), director " .. director)
	result(player, cid, true, existed and "BranchUpdated" or "BranchCreated", num)
	sendBranches(player, cid)
end

function handlers.T_BranchDelete(player, args, cid)
	if not DelNP.isAdmin(player) then return result(player, cid, false, "AdminOnly") end
	local num = clean(args.num, 5, true)
	if not num or not org()[num] then return result(player, cid, false, "NoBranch", tostring(args.num or "")) end
	if not DelNP.journalAppend(ORG, { "branchdel", num, who(player), getTimestampMs() }) then
		return result(player, cid, false, "Failed")
	end
	DelNP.branches[num] = nil
	print("DelNP: " .. who(player) .. " deleted branch " .. num)
	result(player, cid, true, "BranchDeleted", num)
	sendBranches(player, cid)
end

local function staffChange(player, args, cid, add)
	local num = clean(args.num, 5, true)
	local login = clean(args.login, LOGIN_MAX)
	if not num or not login then return result(player, cid, false, "StaffFields") end
	if not org()[num] then return result(player, cid, false, "NoBranch", num) end
	if not (DelNP.isAdmin(player) or isDirector(who(player), num)) then
		return result(player, cid, false, "DirectorOnly", num)
	end
	local b = DelNP.branches[num]
	if add and b.staff[lower(login)] then return result(player, cid, false, "StaffExists", login) end
	if not add and not b.staff[lower(login)] then return result(player, cid, false, "StaffMissing", login) end
	if not DelNP.journalAppend(ORG, { add and "staff" or "staffdel", num, login, who(player), getTimestampMs() }) then
		return result(player, cid, false, "Failed")
	end
	b.staff[lower(login)] = add and login or nil
	print("DelNP: " .. who(player) .. (add and " added " or " removed ") .. login .. (add and " to" or " from") .. " branch " .. num)
	result(player, cid, true, add and "StaffAdded" or "StaffRemoved", login)
	sendBranches(player, cid)
end

function handlers.T_StaffAdd(player, args, cid) staffChange(player, args, cid, true) end
function handlers.T_StaffRemove(player, args, cid) staffChange(player, args, cid, false) end

function handlers.T_Status(player, args, cid)
	DelNP.ensureLoaded()
	local no = tonumber(args.no)
	local wb = no and DelNP.register[no]
	if not wb then return result(player, cid, false, "WaybillNotFound", tostring(args.no or "")) end
	local status = args.status
	if not DelNP.STATUSES[status] then return result(player, cid, false, "BadStatus") end
	local branch = clean(args.branch, 5, true)
	if not branch or not org()[branch] then return result(player, cid, false, "NoBranch", tostring(args.branch or "")) end
	if not (DelNP.isAdmin(player) or isStaffOf(who(player), branch)) then
		return result(player, cid, false, "NotStaffOf", branch)
	end
	-- Money: accepting names the price (once, unless it is changed before
	-- payment); nothing moves on until it is paid.
	if DelNP.moneyEnabled() then
		if status == "accepted" and not DelNP.payment(no) then
			local amount = trim(args.price) ~= "" and DelShops.parseAmount(args.price) or nil
			if not amount then return result(player, cid, false, "PriceNeeded") end
			DelNP.setPrice(no, amount, branch, who(player))
		elseif status ~= "accepted" and not DelNP.isPaid(no) then
			return result(player, cid, false, DelNP.payment(no) and "NotPaidYet" or "AcceptFirst")
		end
	end
	if not DelNP.setStatus(no, status, branch, who(player)) then return result(player, cid, false, "Failed") end
	print("DelNP: " .. who(player) .. " set [" .. DelNP.formatNo(no) .. "] " .. status .. " at branch " .. branch)
	DelNP.notifyStatus(wb, status, branch)
	result(player, cid, true, "StatusSet", DelNP.formatNo(no))
	reply(player, "T_Track", cid, { wb = waybillView(wb), asked = DelNP.formatNo(no) })
end

-- A price changed before payment: staff of the branch that accepted the
-- parcel, or an admin.
function handlers.T_SetPrice(player, args, cid)
	local wb = DelNP.waybill(args.no)
	if not wb then return result(player, cid, false, "WaybillNotFound", tostring(args.no or "")) end
	if not DelNP.moneyEnabled() then return result(player, cid, false, "NoMoneyMod") end
	local p = DelNP.payment(wb.no)
	if not p then return result(player, cid, false, "AcceptFirst") end
	if not (DelNP.isAdmin(player) or isStaffOf(who(player), p.branch)) then
		return result(player, cid, false, "NotStaffOf", p.branch)
	end
	local amount = trim(args.price) ~= "" and DelShops.parseAmount(args.price) or nil
	if not amount then return result(player, cid, false, "PriceNeeded") end
	local ok, err = DelNP.setPrice(wb.no, amount, p.branch, who(player))
	if not ok then return result(player, cid, false, err) end
	print("DelNP: " .. who(player) .. " set the price of [" .. DelNP.formatNo(wb.no) .. "] to " .. DelNP.fmt(amount))
	DelNP.mailParties(wb, "IGUI_DelNP_Mail_ToPay", { DelNP.formatNo(wb.no), p.branch, DelNP.fmt(amount) })
	result(player, cid, true, "PriceSet", DelNP.fmt(amount))
	reply(player, "T_Track", cid, { wb = waybillView(wb), asked = DelNP.formatNo(wb.no) })
end

-- The sender or the recipient pays (terminal, "parcel status" page).
function handlers.T_Pay(player, args, cid)
	local wb = DelNP.waybill(args.no)
	if not wb then return result(player, cid, false, "WaybillNotFound", tostring(args.no or "")) end
	local ok, err, arg = DelNP.pay(player, wb)
	if not ok then return result(player, cid, false, err, arg) end
	result(player, cid, true, "Paid", DelNP.formatNo(wb.no))
	reply(player, "T_Track", cid, { wb = waybillView(wb), asked = DelNP.formatNo(wb.no) })
end

-- From a branch's cash desk to a bank account: its director or an admin.
function handlers.T_Payout(player, args, cid)
	local num = clean(args.num, 5, true)
	if not num or not org()[num] then return result(player, cid, false, "NoBranch", tostring(args.num or "")) end
	if not (DelNP.isAdmin(player) or isDirector(who(player), num)) then
		return result(player, cid, false, "DirectorOnly", num)
	end
	if not DelNP.moneyEnabled() then return result(player, cid, false, "NoMoneyMod") end
	local amount = DelShops.parseAmount(args.amount)
	local account = clean(args.account, LOGIN_MAX)
	if not amount or amount <= 0 or not account then return result(player, cid, false, "PayoutFields") end
	local ok, err, arg = DelNP.payout(num, amount, account, who(player))
	if not ok then return result(player, cid, false, err, arg) end
	result(player, cid, true, "PaidOut", DelNP.fmt(amount))
	sendBranches(player, cid)
end

--[[
Correcting a waybill (a mistyped login, the wrong branch): staff of its
sending or receiving branch, or an admin. Only fields that really change are
written, one `edit` record each; branches must exist. The number stays.
]]
function handlers.T_Edit(player, args, cid)
	local wb = DelNP.waybill(args.no)
	if not wb then return result(player, cid, false, "WaybillNotFound", tostring(args.no or "")) end
	local me = who(player)
	if not (DelNP.isAdmin(player) or isStaffOf(me, wb.origin) or isStaffOf(me, wb.branch)) then
		return result(player, cid, false, "NotStaffOfWaybill")
	end
	local sent = type(args.values) == "table" and args.values or {}
	local changes = {}
	for _, id in ipairs(DelNP.editOrder) do
		if sent[id] ~= nil then
			local v = DelNP.clean(DelNP.editable[id], sent[id])
			if not v then return result(player, cid, false, "EditInvalid", id) end
			if (id == "origin" or id == "branch") and DelNP.isBranchNo(v) and not DelNP.branchExists(v) then
				return result(player, cid, false, "NoBranch", v)
			end
			if v ~= (wb[id] or "") then table.insert(changes, { id = id, value = v }) end
		end
	end
	if #changes == 0 then return result(player, cid, true, "EditNothing") end
	for _, c in ipairs(changes) do
		if not DelNP.editField(wb.no, c.id, c.value, me) then return result(player, cid, false, "Failed") end
		print("DelNP: " .. me .. " corrected [" .. DelNP.formatNo(wb.no) .. "] " .. c.id .. " = " .. c.value)
	end
	result(player, cid, true, "EditSaved", DelNP.formatNo(wb.no))
	reply(player, "T_Track", cid, { wb = waybillView(wb), asked = DelNP.formatNo(wb.no) })
end

function handlers.T_Prices(player, args, cid)
	reply(player, "T_Prices", cid, { text = readPrices(), canEdit = DelNP.isAdmin(player) })
end

function handlers.T_PricesSave(player, args, cid)
	if not DelNP.isAdmin(player) then return result(player, cid, false, "AdminOnly") end
	local text = type(args.text) == "string" and args.text or ""
	text = string.gsub(text, "\r", "")
	if #text > PRICES_MAX then text = string.sub(text, 1, PRICES_MAX) end
	local w = getFileWriter(PRICES, true, false)
	if not w then return result(player, cid, false, "Failed") end
	w:write((string.gsub(text, "\n", "\r\n")))
	w:close()
	print("DelNP: " .. who(player) .. " saved the price list (" .. #text .. " chars)")
	result(player, cid, true, "PricesSaved")
	handlers.T_Prices(player, args, cid)
end

Events.OnClientCommand.Add(function(module, command, player, args)
	if module ~= MODULE or not player then return end
	local h = handlers[command]
	if not h then return end
	args = type(args) == "table" and args or {}
	local cid = args.computerId
	if not atTerminal(player, cid) then
		print("DelNP: terminal command " .. command .. " refused to " .. who(player) .. " (no session at " .. tostring(cid) .. " or too far)")
		return result(player, cid, false, "NoSession")
	end
	h(player, args, cid)
end)
