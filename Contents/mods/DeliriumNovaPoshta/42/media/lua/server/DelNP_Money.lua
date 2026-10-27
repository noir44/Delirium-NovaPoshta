--[[
Nova Poshta money: delivery price, payment by the sender, branch cash desks;
and the notifications to the terminal mail.

Price: set by staff when the parcel is accepted (terminal desk), any amount,
0 = free; may be changed until paid. The sender pays from their Delirium Shops
bank account (terminal, by waybill No.); the money goes to the cash desk of
the branch that accepted the parcel. Until it is paid the parcel cannot go IN
TRANSIT / ARRIVED and the recipient cannot open it (admins can).

The cash desk works like a Delirium Economy city hall treasury: its director
(or an admin) pays out from it to any bank account.

Where it lives: global ModData "DelNP_Money" = { desks = { [branch] = amount },
parcels = { [no] = { price, branch, paid, paidBy, paidDate } } }, i.e. in the
world save next to the bank balances (ModData "DelShops_Balance"). A world
rolled back after a crash takes the payer's money, the desk and the "paid"
mark back together, so money is never doubled or lost. The journal
(waybills.txt: price / paid / payout lines) is history only.

Without Delirium Shops nothing here charges anyone: prices can't be set and
every parcel counts as paid.
]]

if not isServer() then return end

require "DelNP_Shared"
require "DelNP_Server"

local MONEY_KEY = "DelNP_Money"
local JOURNAL = "DelNovaPoshta/waybills.txt"

function DelNP.moneyEnabled()
	return DelShops ~= nil and DelShops.BALANCE_KEY ~= nil and DelShops.round ~= nil
end

local function round(v) return DelShops.round(v) end

function DelNP.fmt(v)
	if Currency and Currency.format then return Currency.format(v) end
	return string.format("%.2f", tonumber(v) or 0)
end

local function money()
	local m = ModData.getOrCreate(MONEY_KEY)
	m.desks = m.desks or {}
	m.parcels = m.parcels or {}
	return m
end

local function accounts() return ModData.getOrCreate(DelShops.BALANCE_KEY) end
local function transmitAccounts() ModData.transmit(DelShops.BALANCE_KEY) end

local function key(no) return tostring(tonumber(no) or no) end

function DelNP.payment(no)
	if not DelNP.moneyEnabled() then return nil end
	return money().parcels[key(no)]
end

-- No money mod: always paid. Otherwise a price must be set and paid.
function DelNP.isPaid(no)
	if not DelNP.moneyEnabled() then return true end
	local p = money().parcels[key(no)]
	return p ~= nil and p.paid == true
end

function DelNP.deskAmount(branch)
	if not DelNP.moneyEnabled() then return 0 end
	return money().desks[tostring(branch)] or 0
end

-- What a client is shown about a parcel's payment.
function DelNP.paymentView(no)
	local p = DelNP.payment(no)
	if not p then return nil end
	return { price = p.price, priceText = DelNP.fmt(p.price), branch = p.branch, paid = p.paid == true,
		paidBy = p.paidBy, paidDate = p.paidDate }
end

-- Staff set (or correct, until paid) the price. Returns ok, error code.
function DelNP.setPrice(no, amount, branch, by)
	if not DelNP.moneyEnabled() then return false, "NoMoneyMod" end
	local p = money().parcels[key(no)]
	if p and p.paid then return false, "AlreadyPaid" end
	amount = round(amount)
	money().parcels[key(no)] = { price = amount, branch = tostring(branch), paid = false }
	DelNP.journalAppend(JOURNAL, { "price", key(no), amount, branch, by, getTimestampMs() })
	return true
end

-- The sender pays from their bank account. Returns ok, error code, argument.
function DelNP.pay(player, wb)
	if not DelNP.moneyEnabled() then return false, "NoMoneyMod" end
	local p = money().parcels[key(wb.no)]
	if not p then return false, "NoPrice" end
	if p.paid then return false, "AlreadyPaid" end
	local username = player:getUsername()
	if string.lower(tostring(wb.sender)) ~= string.lower(username) then return false, "NotSender" end
	if p.price > 0 then
		local account = accounts()[username]
		if not account then return false, "NoAccount" end
		if (account.coin or 0) < p.price then return false, "NotEnough", DelNP.fmt(p.price) end
		account.coin = round(account.coin - p.price)
		local desks = money().desks
		desks[p.branch] = round((desks[p.branch] or 0) + p.price)
		transmitAccounts()
	end
	p.paid = true; p.paidBy = username; p.paidDate = DelNP.todayText()
	DelNP.journalAppend(JOURNAL, { "paid", key(wb.no), p.price, p.branch, username, getTimestampMs() })
	print("DelNP: " .. username .. " paid " .. DelNP.fmt(p.price) .. " for [" .. DelNP.formatNo(wb.no) .. "] to branch " .. p.branch)
	return true
end

-- From a branch's cash desk to any bank account (director / admin, checked
-- by the caller). Returns ok, error code, argument.
function DelNP.payout(branch, amount, recipientName, by)
	if not DelNP.moneyEnabled() then return false, "NoMoneyMod" end
	amount = round(amount)
	if amount <= 0 then return false, "BadAmount" end
	local recipient = accounts()[recipientName]
	if not recipient then return false, "NoAccountOf", recipientName end
	local desks = money().desks
	branch = tostring(branch)
	if (desks[branch] or 0) < amount then return false, "DeskTooLow", DelNP.fmt(desks[branch] or 0) end
	desks[branch] = round(desks[branch] - amount)
	recipient.coin = round((recipient.coin or 0) + amount)
	transmitAccounts()
	DelNP.journalAppend(JOURNAL, { "payout", branch, amount, recipientName, by, getTimestampMs() })
	print("DelNP: " .. by .. " paid out " .. DelNP.fmt(amount) .. " from branch " .. branch .. " desk to " .. recipientName)
	return true
end

-- A deleted branch's cash desk: kept, and shown again if the number returns.

---- notifications ------------------------------------------------------------

--[[
Mail goes to every terminal account REGISTERED BY the player's game login
(DelTerm_Data.accounts[name].owner), whatever the account is called - game
and terminal logins needn't match. A player without a terminal account gets
no mail; an online player also gets a note over their head.

The mail text is a translation key with arguments ("@KEY|arg|arg"); the
terminal draws it in the reader's language (DelTerm MailText).
]]
local function mailTo(login, keyName, args)
	local text = "@" .. keyName
	for _, a in ipairs(args) do text = text .. "|" .. tostring(a) end
	local sent = 0
	if DelTerm_Data and DelTerm_Data.accounts and DelTerm_Data.email_storage then
		for name, acc in pairs(DelTerm_Data.accounts) do
			if acc.owner and string.lower(tostring(acc.owner)) == string.lower(tostring(login)) then
				DelTerm_Data.email_storage[name] = DelTerm_Data.email_storage[name] or {}
				table.insert(DelTerm_Data.email_storage[name], { from = "NOVA_POSHTA", date = DelNP.todayText(), text = text, read = false })
				sent = sent + 1
			end
		end
	end
	local players = getOnlinePlayers()
	if players then
		for i = 0, players:size() - 1 do
			local p = players:get(i)
			if p and string.lower(p:getUsername()) == string.lower(tostring(login)) then
				sendServerCommand(p, "DelNP", "note", { key = keyName, args = args })
			end
		end
	end
	return sent
end
DelNP.mailTo = mailTo

-- Called by the terminal desk after a status change.
function DelNP.notifyStatus(wb, status, branch)
	local no = DelNP.formatNo(wb.no)
	if status == "accepted" then
		local pv = DelNP.paymentView(wb.no)
		if pv and not pv.paid and pv.price > 0 then
			mailTo(wb.sender, "IGUI_DelNP_Mail_ToPay", { no, branch, pv.priceText })
		else
			mailTo(wb.sender, "IGUI_DelNP_Mail_Accepted", { no, branch })
		end
	elseif status == "arrived" then
		mailTo(wb.recipient, "IGUI_DelNP_Mail_Arrived", { no, branch })
	end
end
