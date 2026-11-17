local _, ns = ...
local UI = ns.UI

local Merchant = {}
ns.Merchant = Merchant

local function open()
	return MerchantFrame and MerchantFrame:IsShown()
end

function Merchant.Info(i)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local ok, t = pcall(C_MerchantFrame.GetItemInfo, i)
		if ok and type(t) == "table" then
			return {
				name = t.name, price = t.price or 0, stack = (t.stackCount or 0) > 0 and t.stackCount or 1, available = t.numAvailable,
				usable = t.isUsable, extended = t.hasExtendedCost,
			}
		end
	end
	if GetMerchantItemInfo then
		local name, _, price, stack, available, usable, extended = GetMerchantItemInfo(i)
		if name then
			return { name = name, price = price or 0, stack = (stack or 0) > 0 and stack or 1, available = available, usable = usable, extended = extended }
		end
	end
	return nil
end

function Merchant.ID(i)
	if GetMerchantItemID then
		local id = GetMerchantItemID(i)
		if id then return id end
	end
	if GetMerchantItemLink then return ns.ItemID(GetMerchantItemLink(i)) end
	return nil
end

local function count()
	return GetMerchantNumItems and GetMerchantNumItems() or 0
end

local function maxStack(i)
	local n = GetMerchantItemMaxStack and GetMerchantItemMaxStack(i)
	if type(n) ~= "number" or n < 1 then n = 1 end
	return n
end

local function money()
	local m = GetMoney and GetMoney() or 0
	if type(m) ~= "number" or ns.IsSecret(m) then return 0 end
	return m
end

function Merchant.Buy(i, amount)
	local info = Merchant.Info(i)
	if not info or not BuyMerchantItem or amount < 1 then return 0, 0 end
	if info.extended then return 0, 0 end
	local bought, spent = 0, 0
	local funds = money()
	local left = amount
	if type(info.available) == "number" and info.available >= 0 then
		left = math.min(left, info.available * info.stack)
	end
	if info.stack > 1 then
		local batches = math.min(math.ceil(left / info.stack), 40)
		for _ = 1, batches do
			if spent + info.price > funds then break end
			BuyMerchantItem(i)
			bought = bought + info.stack
			spent = spent + info.price
		end
	else
		local per = maxStack(i)
		local guard = 0
		while left > 0 and guard < 40 do
			guard = guard + 1
			local n = math.min(left, per)
			if spent + info.price * n > funds then
				n = math.floor((funds - spent) / math.max(info.price, 1))
				if n < 1 then break end
				left = n
			end
			BuyMerchantItem(i, n)
			bought = bought + n
			spent = spent + info.price * n
			left = left - n
		end
	end
	return bought, spent
end

function Merchant.Restock(manual)
	if not open() then
		if manual then ns.Print("open a merchant first") end
		return
	end
	local list = ns.chardb.restock
	if not next(list) then
		if manual then ns.Print("the restock list is empty") end
		return
	end
	local cap = ns.db.restockCap or 0
	local total, lines, skipped = 0, {}, 0
	local seen = {}
	for i = 1, count() do
		local id = Merchant.ID(i)
		local want = id and list[id]
		if want and not seen[id] then
			seen[id] = true
			local need = want - ns.Count(id)
			local info = Merchant.Info(i)
			if need > 0 and info then
				local unit = info.price / math.max(info.stack, 1)
				if cap > 0 and total + unit * need > cap then
					local affordable = math.floor((cap - total) / math.max(unit, 1))
					if info.stack > 1 then affordable = math.floor(affordable / info.stack) * info.stack end
					skipped = skipped + (need - math.max(affordable, 0))
					need = math.max(affordable, 0)
				end
				if need > 0 then
					local bought, spent = Merchant.Buy(i, need)
					if bought > 0 then
						total = total + spent
						lines[#lines + 1] = bought .. "x " .. (info.name or ns.ItemName(id))
					end
				end
			end
		end
	end
	if #lines > 0 then
		ns.Print("restocked " .. table.concat(lines, ", ") .. " for " .. ACore.Money(total))
	elseif manual then
		ns.Print("nothing to restock here")
	end
	if skipped > 0 then
		ns.Print("spending limit reached, " .. skipped .. " not bought")
	end
	return total
end

function Merchant.Repair()
	if not ns.db.repair or not CanMerchantRepair or not CanMerchantRepair() then return end
	if not GetRepairAllCost or not RepairAllItems then return end
	local cost, can = GetRepairAllCost()
	if type(cost) ~= "number" or cost <= 0 or not can then return end
	if ns.db.guildRepair and CanGuildBankRepair and CanGuildBankRepair() then
		local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
		if type(limit) == "number" and (limit == -1 or limit >= cost) then
			RepairAllItems(true)
			ns.Print("repaired with guild funds for " .. ACore.Money(cost))
			return
		end
	end
	if cost > money() then
		ns.Print("not enough gold to repair (" .. ACore.Money(cost) .. ")")
		return
	end
	RepairAllItems(false)
	ns.Print("repaired for " .. ACore.Money(cost))
end

local function known(i, id)
	local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if getInstant then
		local ok, _, _, _, _, _, classID = pcall(getInstant, id)
		if ok and classID and classID ~= 9 then return false end
	end
	if C_TooltipInfo and C_TooltipInfo.GetMerchantItem then
		local ok, data = pcall(C_TooltipInfo.GetMerchantItem, i)
		if ok and type(data) == "table" and type(data.lines) == "table" then
			for _, l in ipairs(data.lines) do
				if l.leftText and l.leftText == ITEM_SPELL_KNOWN then return true end
			end
		end
	end
	return false
end

local extras = {}
local function extra(slot, frame, button)
	local e = extras[slot]
	if e then return e end
	e = {}
	e.count = UI.Text(frame, "GameFontDisableSmall", "RIGHT", UI.colors.dim)
	e.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
	e.keep = UI.Text(frame, "GameFontDisableSmall", "RIGHT", UI.colors.accent)
	e.keep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	e.icon = button.icon or button.Icon or _G["MerchantItem" .. slot .. "ItemButtonIconTexture"]
	if button.HookScript then
		button:HookScript("OnClick", function(self, mouse) Merchant.Click(self, mouse) end)
	end
	e.button = button
	extras[slot] = e
	return e
end

function Merchant.Decorate()
	if not open() then return end
	local buying = not MerchantFrame.selectedTab or MerchantFrame.selectedTab == 1
	for slot = 1, MERCHANT_ITEMS_PER_PAGE or 10 do
		local frame = _G["MerchantItem" .. slot]
		local button = frame and (frame.ItemButton or _G["MerchantItem" .. slot .. "ItemButton"])
		if frame and button then
			local e = extra(slot, frame, button)
			local i = button.GetID and button:GetID()
			local id = buying and type(i) == "number" and i > 0 and Merchant.ID(i)
			if id and (not button.IsShown or button:IsShown()) then
				local have = ns.Count(id, true)
				e.count:SetText(ns.db.counts and have > 0 and ("own " .. have) or "")
				local keep = ns.chardb.restock[id]
				e.keep:SetText(keep and ("keep " .. keep) or "")
				if e.icon and e.icon.SetVertexColor and ns.db.tint then
					local info = Merchant.Info(i)
					if known(i, id) then
						e.icon:SetVertexColor(0.35, 0.35, 0.35)
						e.count:SetText("known")
					elseif info and info.usable == false then
						e.icon:SetVertexColor(1, 0.25, 0.25)
					else
						e.icon:SetVertexColor(1, 1, 1)
					end
				end
			else
				e.count:SetText("")
				e.keep:SetText("")
			end
		end
	end
end

function Merchant.Click(button, mouse)
	if not open() then return end
	if MerchantFrame.selectedTab and MerchantFrame.selectedTab ~= 1 then return end
	local i = button.GetID and button:GetID()
	if type(i) ~= "number" or i < 1 then return end
	local id = Merchant.ID(i)
	local info = Merchant.Info(i)
	if not id or not info then return end
	local alt = IsAltKeyDown and IsAltKeyDown()
	local shift = IsShiftKeyDown and IsShiftKeyDown()
	if alt and mouse == "RightButton" then
		UI.Prompt("How many " .. (info.name or "of these") .. " to keep in your bags? (0 removes)", tostring(ns.chardb.restock[id] or maxStack(i)), function(text)
			local n = tonumber(text)
			if not n then return end
			ns.chardb.restock[id] = n > 0 and math.floor(n) or nil
			ns:Fire("LISTS")
			Merchant.Decorate()
		end)
	elseif alt then
		local n = math.max(maxStack(i), info.stack)
		local bought, spent = Merchant.Buy(i, n)
		if bought > 0 then ns.Print("bought " .. bought .. "x " .. (info.name or "") .. " for " .. ACore.Money(spent)) end
	elseif shift and mouse == "RightButton" then
		if StackSplitFrame and StackSplitFrame.Hide then StackSplitFrame:Hide() end
		UI.Prompt("Buy how many " .. (info.name or "") .. "?", tostring(maxStack(i)), function(text)
			local n = tonumber(text)
			if not n or n < 1 then return end
			local bought, spent = Merchant.Buy(i, math.floor(n))
			if bought > 0 then ns.Print("bought " .. bought .. "x " .. (info.name or "") .. " for " .. ACore.Money(spent)) end
		end)
	end
end

ns:On("MERCHANT_SHOW", function()
	ns.After(0.3, function()
		if not open() then return end
		Merchant.Repair()
		if ns.db.restock then Merchant.Restock() end
		if ns.db.sellListed and ns.Protect then ns.Protect.SellListed() end
		Merchant.Decorate()
	end)
end)
ns:On("MERCHANT_UPDATE", function() Merchant.Decorate() end)
ns:On("BAG_UPDATE_DELAYED", function()
	if open() then ns.Debounce("decorate", 0.2, Merchant.Decorate) end
end)
ns:Listen("OPTIONS", function() Merchant.Decorate() end)
ns:Listen("LISTS", function() Merchant.Decorate() end)

ns:Listen("LOGIN", function()
	if hooksecurefunc and MerchantFrame_UpdateMerchantInfo then
		pcall(hooksecurefunc, "MerchantFrame_UpdateMerchantInfo", function() Merchant.Decorate() end)
	end
	if hooksecurefunc and MerchantFrame_UpdateBuybackInfo then
		pcall(hooksecurefunc, "MerchantFrame_UpdateBuybackInfo", function() Merchant.Decorate() end)
	end
end)
