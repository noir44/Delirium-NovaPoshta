--[[
Nova Poshta as an app of the Delirium Terminal ([8] on the desktop).

Pages: NP_HOME (menu), NP_REQ (pickup requests), NP_TRACK (parcel status, my
parcels), NP_BRANCH (branches and staff), NP_DESK (staff: parcel statuses),
NP_PRICES / NP_PRICES_EDIT. Everything is decided on the server
(server/DelNP_Office.lua); the client only hides what the reply says the
player cannot use. Without the terminal mod this file registers nothing.
]]

if isServer() then return end

require "DelNP_Shared"

local U -- DelTerm_UI, set at registration

local function T(key, ...) return getText("IGUI_DelNP_T_" .. key, ...) end

local function send(win, command, args)
	args = args or {}
	args.computerId = win.computerId
	U.send("DelNP", command, args)
end

local function trim(s) return (string.match(s or "", "^%s*(.-)%s*$")) or "" end

local function statusText(code) return getText("IGUI_DelNP_St_" .. tostring(code)) end

-- Header, Back button and status line shared by every page.
local function page(win, name, title, back)
	win:clearScreen()
	win.currentPage = name
	U.remember(win, name)
	local w, h = win.mainPanel.width, win.mainPanel.height
	U.label(win, 10, 6, title)
	local tBack = T("Btn_Back")
	local wB = U.BtnW(tBack, 90)
	U.button(win, w - 10 - wB, h - 30, wB, tBack, back)
	U.statusLabel(win, h - 30)
	return w, h
end

local function status(win, msg, ok) win:setPageStatus(msg, ok ~= false) end

-- "Reading..." until the reply is drawn; a reply clears only that, so a
-- result message that arrived just before the refreshed list stays visible.
local function reading(win) win.npReading = true; status(win, T("Reading")) end
local function doneReading(win, msg)
	if win.npReading then win.npReading = false; status(win, msg or "") end
end

local NP = {}

---- home ---------------------------------------------------------------------

function NP.home(win)
	local w, h = page(win, "NP_HOME", T("Home_Header"), function(s) s:loadDesktop() end)
	win.npRoles = win.npRoles or {}
	local y = 50
	local function item(txt, fn)
		local bw = math.max(320, getTextManager():MeasureStringX(U.THEME.font, txt) + 20)
		local btn = ISButton:new(win:centerX(bw), y, bw, 20, txt, win, fn)
		btn:initialise(); btn:setFont(U.THEME.font)
		btn.borderColor = {r=0,g=0,b=0,a=0}; btn.backgroundColor = {r=0,g=0,b=0,a=0}
		btn.backgroundColorMouseOver = {r=0,g=0.3,b=0,a=0.5}; btn.textColor = {r=0,g=1,b=0,a=1}
		win.mainPanel:addChild(btn)
		y = y + 30
	end
	local r = win.npRoles
	item(T("Menu_Request"), function(s) NP.requests(s) end)
	item(T("Menu_Track"), function(s) NP.track(s) end)
	if r.isAdmin or (r.works and #r.works > 0) then
		item(T("Menu_Branches"), function(s) NP.branches(s) end)
		item(T("Menu_Desk"), function(s) NP.desk(s) end)
	end
	item(T("Menu_Prices"), function(s) NP.prices(s) end)

	y = y + 20
	if r.me then
		U.label(win, 10, y, T("Home_Me", r.me))
		local roles = {}
		if r.isAdmin then table.insert(roles, T("Role_Admin")) end
		for _, n in ipairs(r.directs or {}) do table.insert(roles, T("Role_Director", n)) end
		for _, n in ipairs(r.works or {}) do
			local dir = false
			for _, d in ipairs(r.directs or {}) do if d == n then dir = true end end
			if not dir then table.insert(roles, T("Role_Staff", n)) end
		end
		U.label(win, 10, y + 20, T("Home_Roles", #roles > 0 and table.concat(roles, ", ") or T("Role_Client")))
	end
	if not win.npHomeAsked then
		win.npHomeAsked = true
		send(win, "T_Home")
	end
end

---- pickup requests ----------------------------------------------------------

function NP.requests(win)
	local w, h = page(win, "NP_REQ", T("Req_Header"), function(s) NP.home(s) end)
	win.npText = U.textPanel(win, 10, 30, w - 20, h - 200)

	local y = h - 160
	U.label(win, 10, y + 4, T("Req_Branch"))
	local lw = getTextManager():MeasureStringX(U.THEME.font, T("Req_Branch")) + 16
	win.npBranch = U.entry(win, 10 + lw, y, 70, "№", 5)
	win.npBranch:setOnlyNumbers(true)
	win.npAddress = U.entry(win, 20 + lw + 70, y, w - 30 - lw - 70, T("Req_Address"), 80)
	y = y + 32
	local tSend = T("Btn_Send")
	local wS = U.BtnW(tSend, 110)
	win.npComment = U.entry(win, 10, y, w - 30 - wS, T("Req_Comment"), 160)
	U.button(win, w - 10 - wS, y, wS, tSend, function(s)
		local address = trim(s.npAddress:getInternalText())
		local branch = trim(s.npBranch:getInternalText())
		if branch == "" or address == "" then return status(s, T("Err_ReqFields"), false) end
		send(s, "T_ReqCreate", { branch = branch, address = address, comment = s.npComment:getInternalText() })
	end)

	-- Staff row, shown once the server says so.
	y = y + 32
	local tClose = T("Btn_CloseReq")
	local wC = U.BtnW(tClose, 140)
	win.npReqId = U.entry(win, 10, y, 80, "#", 6)
	win.npReqId:setOnlyNumbers(true)
	win.npReqCloseBtn = U.button(win, 100, y, wC, tClose, function(s)
		local id = trim(s.npReqId:getInternalText())
		if id ~= "" then send(s, "T_ReqClose", { id = id }) end
	end)
	win.npReqId:setVisible(false); win.npReqCloseBtn:setVisible(false)

	reading(win)
	send(win, "T_Requests")
end

local function requestLine(r, showUser)
	local st = r.status == "open" and ("<RGB:1,1,0> " .. T("Req_Open")) or ("<RGB:0.6,0.6,0.6> " .. T("Req_Done", U.RichSafe(r.doneBy or "?"), r.doneDate or ""))
	local s = " <RGB:0.6,0.6,0.6> #" .. r.id .. "  [" .. (r.date or "") .. "]  <RGB:0,1,0> " .. T("Req_ToBranch", r.branch) .. "  " .. st .. " <LINE> "
	if showUser then s = s .. " <RGB:0,1,0> " .. U.RichSafe(r.user) .. " <RGB:1,1,1> : " else s = s .. " <RGB:1,1,1> " end
	s = s .. U.RichSafe(r.address)
	if r.comment and r.comment ~= "" then s = s .. " <LINE> <RGB:0.7,0.7,0.7> " .. U.RichSafe(r.comment) end
	return s .. " <LINE> <RGB:0.3,0.3,0.3> ------------------------------------------------ <LINE> "
end

function NP.renderRequests(win, args)
	if not win.npText then return end
	local txt = " <FONT:Code> <RGB:0,1,0> " .. T("Req_Mine") .. " <LINE> "
	if #(args.mine or {}) == 0 then txt = txt .. " <RGB:0.6,0.6,0.6> " .. T("Req_None") .. " <LINE> " end
	for _, r in ipairs(args.mine or {}) do txt = txt .. requestLine(r, false) end
	if args.isStaff then
		txt = txt .. " <LINE> <RGB:0,1,0> " .. T("Req_All") .. " <LINE> "
		if #(args.all or {}) == 0 then txt = txt .. " <RGB:0.6,0.6,0.6> " .. T("Req_None") .. " <LINE> " end
		for _, r in ipairs(args.all or {}) do txt = txt .. requestLine(r, true) end
	end
	local names = {}
	for _, b in ipairs(args.branches or {}) do table.insert(names, b.num .. " - " .. U.RichSafe(b.name)) end
	txt = txt .. " <LINE> <RGB:0.6,0.6,0.6> " .. T("Req_Branches", #names > 0 and table.concat(names, "; ") or T("Branch_None")) .. " <LINE> "
	win.npText.text = txt; win.npText:paginate()
	win.npReqId:setVisible(args.isStaff == true); win.npReqCloseBtn:setVisible(args.isStaff == true)
	doneReading(win)
end

---- parcel status ------------------------------------------------------------

local function branchLabel(num, name)
	if not num or num == "" then return "?" end
	if name and name ~= "" then return num .. " (" .. U.RichSafe(name) .. ")" end
	return num
end

local function waybillText(wb)
	local s = " <RGB:0,1,0> " .. T("Wb_No", wb.no) .. " <LINE> "
	s = s .. " <RGB:1,1,1> " .. T("Wb_From", U.RichSafe(wb.sender), wb.date or "") .. " <LINE> "
	s = s .. " <RGB:1,1,1> " .. T("Wb_Route", branchLabel(wb.origin, wb.originName), branchLabel(wb.branch, wb.branchName)) .. " <LINE> "
	s = s .. " <RGB:1,1,1> " .. T("Wb_To", U.RichSafe(wb.recipient)) .. " <LINE> "
	if wb.pay then
		if wb.pay.paid then
			s = s .. " <RGB:0.6,1,0.6> " .. T("Wb_Paid", wb.pay.priceText, U.RichSafe(wb.pay.paidBy or "?"), wb.pay.paidDate or "") .. " <LINE> "
		else
			s = s .. " <RGB:1,0.6,0> " .. T("Wb_ToPay", wb.pay.priceText) .. " <LINE> "
		end
	elseif wb.money then
		s = s .. " <RGB:0.6,0.6,0.6> " .. T("Wb_NoPrice") .. " <LINE> "
	end
	if wb.sealed then
		s = s .. " <RGB:1,1,0> " .. T("Wb_Sealed") .. " <LINE> "
	else
		s = s .. " <RGB:0.6,1,0.6> " .. T("Wb_Opened", U.RichSafe(wb.openedBy or "?"), wb.openedDate or "") .. " <LINE> "
	end
	if #(wb.track or {}) == 0 then
		s = s .. " <RGB:0.6,0.6,0.6> " .. T("Wb_NoTrack") .. " <LINE> "
	end
	for _, t in ipairs(wb.track or {}) do
		s = s .. " <RGB:0.6,0.6,0.6> [" .. (t.date or "") .. "] <RGB:0,1,0> " .. statusText(t.status) ..
			" <RGB:0.6,0.6,0.6> " .. T("Wb_TrackAt", t.branch or "?", U.RichSafe(t.by or "?")) .. " <LINE> "
	end
	return s .. " <RGB:0.3,0.3,0.3> ------------------------------------------------ <LINE> "
end

function NP.track(win)
	local w, h = page(win, "NP_TRACK", T("Track_Header"), function(s) NP.home(s) end)
	local tFind, tMine = T("Btn_Find"), T("Btn_Mine")
	local wF, wM = U.BtnW(tFind, 90), U.BtnW(tMine, 140)
	win.npNo = U.entry(win, 10, 30, 160, T("Track_No"), 10)
	win.npNo:setOnlyNumbers(true)
	win.npNo.onCommandEntered = function() NP.find(win) end
	U.button(win, 180, 30, wF, tFind, function(s) NP.find(s) end)
	U.button(win, 190 + wF, 30, wM, tMine, function(s) reading(s); send(s, "T_Mine") end)
	-- Shown for a found parcel the player sent and has not paid for yet.
	local tPay = T("Btn_Pay")
	local wP = U.BtnW(tPay, 140)
	win.npPayBtn = U.button(win, w - 10 - wP, 30, wP, tPay, function(s)
		if s.npPayNo then send(s, "T_Pay", { no = s.npPayNo }) end
	end)
	win.npPayBtn:setVisible(false)
	win.npText = U.textPanel(win, 10, 62, w - 20, h - 102)
	reading(win)
	send(win, "T_Mine")
end

-- The pay button for the found parcel, if this player owes for it.
local function updatePay(win, wb)
	if not win.npPayBtn then return end
	local me = win.npRoles and win.npRoles.me
	local owes = wb and wb.pay and not wb.pay.paid and me and string.lower(wb.sender or "") == string.lower(me)
	win.npPayNo = owes and wb.no or nil
	if owes then win.npPayBtn:setTitle(T("Btn_PayAmount", wb.pay.priceText)) end
	win.npPayBtn:setVisible(owes and true or false)
end

function NP.find(win)
	local no = trim(win.npNo and win.npNo:getInternalText())
	if no == "" then return status(win, T("Err_NoNumber"), false) end
	reading(win)
	send(win, "T_Track", { no = no })
end

function NP.renderTrack(win, args)
	if not win.npText then return end
	local txt = " <FONT:Code> "
	if args.wb then txt = txt .. waybillText(args.wb)
	else txt = txt .. " <RGB:1,0,0> " .. T("Track_NotFound", U.RichSafe(args.asked or "")) .. " <LINE> " end
	win.npText.text = txt; win.npText:paginate()
	if win.currentPage == "NP_DESK" then NP.fillEdit(win, args.wb) end
	if win.currentPage == "NP_TRACK" then updatePay(win, args.wb) end
	doneReading(win)
end

function NP.renderMine(win, args)
	if not win.npText then return end
	local txt = " <FONT:Code> <RGB:0,1,0> " .. T("Track_Mine") .. " <LINE> "
	if #(args.list or {}) == 0 then txt = txt .. " <RGB:0.6,0.6,0.6> " .. T("Track_MineNone") .. " <LINE> " end
	for _, wb in ipairs(args.list or {}) do txt = txt .. waybillText(wb) end
	updatePay(win, nil)
	if win.npPayBtn then
		for _, wb in ipairs(args.list or {}) do
			if wb.pay and not wb.pay.paid and string.lower(wb.sender or "") == string.lower(win.npRoles and win.npRoles.me or "") then txt = txt .. " <RGB:1,0.6,0> " .. T("Track_PayHint") .. " <LINE> "; break end
		end
	end
	win.npText.text = txt; win.npText:paginate()
	doneReading(win)
end

---- branches -----------------------------------------------------------------

function NP.branches(win)
	local w, h = page(win, "NP_BRANCH", T("Branch_Header"), function(s) NP.home(s) end)
	win.npText = U.textPanel(win, 10, 30, w - 20, h - 240)
	local tSave, tDel = T("Btn_Save"), T("Btn_Delete")
	local wS, wD = U.BtnW(tSave, 100), U.BtnW(tDel, 100)

	-- Admin: create / update / delete a branch.
	local y = h - 200
	win.npBNum = U.entry(win, 10, y, 70, "№", 5)
	win.npBNum:setOnlyNumbers(true)
	local free = w - 10 - 80 - 10 - wS - 10 - wD - 10
	win.npBName = U.entry(win, 90, y, math.floor(free * 0.6), T("Branch_Name"), 40)
	win.npBDir = U.entry(win, 100 + math.floor(free * 0.6), y, free - math.floor(free * 0.6) - 10, T("Branch_Director"), 40)
	local bSave = U.button(win, w - 20 - wS - wD, y, wS, tSave, function(s)
		send(s, "T_BranchSave", { num = trim(s.npBNum:getInternalText()), name = s.npBName:getInternalText(), director = s.npBDir:getInternalText() })
	end)
	win.npBDelBtn = U.button(win, w - 10 - wD, y, wD, tDel, function(s)
		local num = trim(s.npBNum:getInternalText())
		if num == "" then return status(s, T("Err_NoBranchNum"), false) end
		if s.npBDelArmed ~= num then
			s.npBDelArmed = num
			s.npBDelBtn:setTitle(T("Btn_Sure"))
			return status(s, T("Branch_ConfirmDelete", num), false)
		end
		s.npBDelArmed = nil
		s.npBDelBtn:setTitle(T("Btn_Delete"))
		send(s, "T_BranchDelete", { num = num })
	end)
	win.npBDelBtn.borderColor = U.THEME.error_red
	win.npAdminRow = { win.npBNum, win.npBName, win.npBDir, bSave, win.npBDelBtn }

	-- Director or admin: staff of a branch.
	y = y + 40
	local tAdd, tRem = T("Btn_AddStaff"), T("Btn_RemoveStaff")
	local wA, wR = U.BtnW(tAdd, 110), U.BtnW(tRem, 110)
	win.npSNum = U.entry(win, 10, y, 70, "№", 5)
	win.npSNum:setOnlyNumbers(true)
	win.npSLogin = U.entry(win, 90, y, w - 120 - wA - wR, T("Branch_StaffLogin"), 40)
	local bAdd = U.button(win, w - 20 - wA - wR, y, wA, tAdd, function(s)
		send(s, "T_StaffAdd", { num = trim(s.npSNum:getInternalText()), login = s.npSLogin:getInternalText() })
	end)
	local bRem = U.button(win, w - 10 - wR, y, wR, tRem, function(s)
		send(s, "T_StaffRemove", { num = trim(s.npSNum:getInternalText()), login = s.npSLogin:getInternalText() })
	end)
	win.npStaffRow = { win.npSNum, win.npSLogin, bAdd, bRem }

	-- Director or admin: pay out from the branch's cash desk to a bank account.
	y = y + 40
	local tPay = T("Btn_Payout")
	local wPo = U.BtnW(tPay, 120)
	win.npPNum = U.entry(win, 10, y, 70, "№", 5)
	win.npPNum:setOnlyNumbers(true)
	win.npPAmount = U.entry(win, 90, y, 110, T("Branch_Amount"), 12)
	win.npPAccount = U.entry(win, 210, y, w - 230 - wPo, T("Branch_Account"), 40)
	local bPay = U.button(win, w - 10 - wPo, y, wPo, tPay, function(s)
		send(s, "T_Payout", { num = trim(s.npPNum:getInternalText()), amount = s.npPAmount:getInternalText(), account = trim(s.npPAccount:getInternalText()) })
	end)
	win.npPayRow = { win.npPNum, win.npPAmount, win.npPAccount, bPay }

	for _, el in ipairs(win.npAdminRow) do el:setVisible(false) end
	for _, el in ipairs(win.npStaffRow) do el:setVisible(false) end
	for _, el in ipairs(win.npPayRow) do el:setVisible(false) end

	reading(win)
	send(win, "T_Branches")
end

function NP.renderBranches(win, args)
	if not win.npText then return end
	local txt = " <FONT:Code> "
	if #(args.list or {}) == 0 then txt = txt .. " <RGB:0.6,0.6,0.6> " .. T("Branch_None") .. " <LINE> " end
	for _, b in ipairs(args.list or {}) do
		txt = txt .. " <RGB:0,1,0> " .. T("Branch_Line", b.num, U.RichSafe(b.name)) .. " <LINE> "
		txt = txt .. " <RGB:1,1,1> " .. T("Branch_DirectorIs", b.director and U.RichSafe(b.director) or T("Branch_NoDirector")) .. " <LINE> "
		local staff = {}
		for _, s in ipairs(b.staff or {}) do table.insert(staff, U.RichSafe(s)) end
		txt = txt .. " <RGB:0.7,0.7,0.7> " .. T("Branch_StaffAre", #staff > 0 and table.concat(staff, ", ") or "-") .. " <LINE> "
		if b.desk then txt = txt .. " <RGB:1,0.8,0> " .. T("Branch_Desk", b.desk) .. " <LINE> " end
		txt = txt .. " <RGB:0.3,0.3,0.3> ------------------------------------------------ <LINE> "
	end
	win.npText.text = txt; win.npText:paginate()
	local isAdmin = args.isAdmin == true
	local canStaff = isAdmin or #(args.directs or {}) > 0
	for _, el in ipairs(win.npAdminRow or {}) do el:setVisible(isAdmin) end
	for _, el in ipairs(win.npStaffRow or {}) do el:setVisible(canStaff) end
	for _, el in ipairs(win.npPayRow or {}) do el:setVisible(canStaff and args.money == true) end
	if canStaff and not isAdmin and args.directs[1] and trim(win.npSNum:getInternalText()) == "" then
		win.npSNum:setText(args.directs[1])
		win.npPNum:setText(args.directs[1])
	end
	doneReading(win, canStaff and "" or T("Branch_ReadOnly"))
end

---- staff desk ---------------------------------------------------------------

function NP.desk(win)
	local w, h = page(win, "NP_DESK", T("Desk_Header"), function(s) NP.home(s) end)
	local tShow = T("Btn_Find")
	local wF = U.BtnW(tShow, 90)
	win.npNo = U.entry(win, 10, 30, 160, T("Track_No"), 10)
	win.npNo:setOnlyNumbers(true)
	win.npNo.onCommandEntered = function() NP.find(win) end
	U.button(win, 180, 30, wF, tShow, function(s) NP.find(s) end)
	win.npText = U.textPanel(win, 10, 62, w - 20, h - 250)

	-- Correcting the found waybill: filled in when it is found (NP.fillEdit).
	local tm = getTextManager()
	local function labelled(x, y, key, width, maxLen, numeric)
		local txt = T(key)
		U.label(win, x, y + 4, txt)
		local lw = tm:MeasureStringX(U.THEME.font, txt) + 8
		local e = U.entry(win, x + lw, y, width, nil, maxLen)
		if numeric then e:setOnlyNumbers(true) end
		return e, x + lw + width + 14
	end
	local y = h - 180
	local x
	win.npEdit = {}
	win.npEdit.origin, x = labelled(10, y, "Edit_Origin", 60, 5, true)
	win.npEdit.branch, x = labelled(x, y, "Edit_Branch", 60, 5, true)
	win.npEdit.date, x = labelled(x, y, "Edit_Date", 110, 10)
	y = y + 32
	local tSave = T("Btn_SaveEdit")
	local wSave = U.BtnW(tSave, 120)
	local half = math.floor((w - 40 - wSave) / 2)
	win.npEdit.sender, x = labelled(10, y, "Edit_Sender", half - 110, 40)
	win.npEdit.recipient, x = labelled(x, y, "Edit_Recipient", half - 110, 40)
	win.npEditSave = U.button(win, w - 10 - wSave, y, wSave, tSave, function(s)
		if not s.npDeskWb then return status(s, T("Err_FindFirst"), false) end
		local values = {}
		for _, id in ipairs(DelNP.editOrder) do values[id] = s.npEdit[id]:getInternalText() end
		send(s, "T_Edit", { no = s.npDeskWb.no, values = values })
	end)
	NP.fillEdit(win, nil)

	-- Delivery price: sent with ACCEPTED; changed before payment by its button.
	y = h - 108
	local tPrice = T("Btn_SetPrice")
	local wPr = U.BtnW(tPrice, 120)
	win.npPrice, x = labelled(10, y, "Desk_Price", 100, 12)
	U.button(win, x, y, wPr, tPrice, function(s)
		local no = trim(s.npNo:getInternalText())
		if no == "" then return status(s, T("Err_NoNumber"), false) end
		send(s, "T_SetPrice", { no = no, price = s.npPrice:getInternalText() })
	end)

	y = h - 70
	U.label(win, 10, y + 4, T("Desk_Branch"))
	local lw = getTextManager():MeasureStringX(U.THEME.font, T("Desk_Branch")) + 16
	win.npDeskBranch = U.entry(win, 10 + lw, y, 70, "№", 5)
	win.npDeskBranch:setOnlyNumbers(true)
	local works = win.npRoles and win.npRoles.works or {}
	if works[1] then win.npDeskBranch:setText(works[1]) end
	local x = 20 + lw + 70
	for _, code in ipairs({ "accepted", "transit", "arrived" }) do
		local txt = statusText(code)
		local bw = U.BtnW(txt, 100)
		U.button(win, x, y, bw, txt, function(s)
			local no = trim(s.npNo:getInternalText())
			local branch = trim(s.npDeskBranch:getInternalText())
			if no == "" then return status(s, T("Err_NoNumber"), false) end
			if branch == "" then return status(s, T("Err_NoBranchNum"), false) end
			send(s, "T_Status", { no = no, status = code, branch = branch, price = s.npPrice:getInternalText() })
		end)
		x = x + bw + 10
	end
	status(win, T("Desk_Hint"))
end

-- The found waybill's values into the correction fields (empty when none).
function NP.fillEdit(win, wb)
	win.npDeskWb = wb
	if not win.npEdit then return end
	for _, id in ipairs(DelNP.editOrder) do
		win.npEdit[id]:setText(wb and wb[id] or "")
		win.npEdit[id]:setEditable(wb ~= nil)
	end
	win.npEditSave:setEnable(wb ~= nil)
	-- Without thousands separators: DelShops.parseAmount reads "," as the decimal point.
	if win.npPrice then win.npPrice:setText(wb and wb.pay and (string.gsub(wb.pay.priceText, ",", "")) or "") end
end

---- prices -------------------------------------------------------------------

function NP.prices(win)
	local w, h = page(win, "NP_PRICES", T("Prices_Header"), function(s) NP.home(s) end)
	win.npText = U.textPanel(win, 10, 30, w - 20, h - 70)
	local tEdit = T("Btn_Edit")
	local wE = U.BtnW(tEdit, 100)
	local wB = U.BtnW(T("Btn_Back"), 90)
	win.npEditBtn = U.button(win, w - 20 - wB - wE, h - 30, wE, tEdit, function(s) NP.pricesEdit(s) end)
	win.npEditBtn:setVisible(false)
	reading(win)
	send(win, "T_Prices")
end

function NP.renderPrices(win, args)
	win.npPricesText = args.text or ""
	if win.currentPage == "NP_PRICES" and win.npText then
		local body = win.npPricesText ~= "" and U.RichSafe(win.npPricesText) or T("Prices_Empty")
		win.npText.text = " <FONT:Code> <RGB:1,1,1> " .. body
		win.npText:paginate()
		win.npEditBtn:setVisible(args.canEdit == true)
		doneReading(win)
	end
end

function NP.pricesEdit(win)
	local w, h = page(win, "NP_PRICES_EDIT", T("Prices_EditHeader"), function(s) NP.prices(s) end)
	win.npEditor = U.editor(win, 10, 30, w - 20, h - 70, 4000)
	win.npEditor:setText(win.npPricesText or "")
	win.npEditor:focus()
	local tSave = T("Btn_Save")
	local wS = U.BtnW(tSave, 100)
	local wB = U.BtnW(T("Btn_Back"), 90)
	U.button(win, w - 20 - wB - wS, h - 30, wS, tSave, function(s)
		send(s, "T_PricesSave", { text = s.npEditor:getInternalText() or "" })
		NP.prices(s)
	end)
	status(win, T("Prices_EditHint"))
end

---- server replies -----------------------------------------------------------

Events.OnServerCommand.Add(function(module, command, args)
	if module ~= "DelNP" or not U or not args then return end
	local win = U.getUI(args.computerId)
	if not win then return end
	local p = win.currentPage
	if command == "T_Home" then
		win.npRoles = args
		if p == "NP_HOME" then NP.home(win) end
	elseif command == "T_Result" then
		local key = "IGUI_DelNP_TMsg_" .. tostring(args.msg)
		local msg = args.arg ~= nil and getText(key, tostring(args.arg)) or getText(key)
		win.npReading = false
		status(win, msg, args.ok ~= false)
	elseif command == "T_Requests" and p == "NP_REQ" then NP.renderRequests(win, args)
	elseif command == "T_Track" and (p == "NP_TRACK" or p == "NP_DESK") then NP.renderTrack(win, args)
	elseif command == "T_Mine" and p == "NP_TRACK" then NP.renderMine(win, args)
	elseif command == "T_Branches" and p == "NP_BRANCH" then NP.renderBranches(win, args)
	elseif command == "T_Prices" then NP.renderPrices(win, args)
	end
end)

---- registration -------------------------------------------------------------

local PAGES = { NP_HOME = true, NP_REQ = true, NP_TRACK = true, NP_BRANCH = true, NP_DESK = true, NP_PRICES = true, NP_PRICES_EDIT = true }

Events.OnGameStart.Add(function()
	-- Said in console.txt either way: an old Delirium Terminal (before its app
	-- registry) would otherwise just show no menu entry, with nothing in the log.
	if not (DelTerm_RegisterApp and DelTerm_UI) then
		print("DelNP: terminal app NOT registered - Delirium Terminal " ..
			(DelTerm_Window and "is too old (no DelTerm_RegisterApp)" or "is not loaded"))
		return
	end
	print("DelNP: terminal app registered")
	U = DelTerm_UI
	DelTerm_RegisterApp({
		id = "NovaPoshta",
		menuText = function() return T("Menu") end,
		pages = PAGES,
		title = function(pg) return T("Title_" .. pg) end,
		-- Roles are asked again every time the app is entered from the desktop.
		load = function(win) win.npHomeAsked = false; NP.home(win) end,
	})
end)
