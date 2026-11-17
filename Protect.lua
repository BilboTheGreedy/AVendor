local _, ns = ...
local UI = ns.UI

local Protect = {}
ns.Protect = Protect

local snapshot = {}
local allow = {}

local function open()
	return MerchantFrame and MerchantFrame:IsShown()
end

local function slotInfo(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local ok, t = pcall(C_Container.GetContainerItemInfo, bag, slot)
		if ok and type(t) == "table" and not ns.IsSecret(t.itemID) and t.itemID then
			return { id = t.itemID, link = t.hyperlink, quality = t.quality, count = t.stackCount or 1, noValue = t.hasNoValue, locked = t.isLocked }
		end
	elseif GetContainerItemInfo then
		local _, n, _, quality, _, _, link, _, noValue, id = GetContainerItemInfo(bag, slot)
		if id then return { id = id, link = link, quality = quality, count = n or 1, noValue = noValue } end
	end
	return nil
end

local function slots(bag)
	if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
	if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
	return 0
end

function Protect.Snap()
	snapshot = {}
	for bag = 0, 4 do
		for slot = 1, slots(bag) do
			local it = slotInfo(bag, slot)
			if it then snapshot[bag * 100 + slot] = it end
		end
	end
end

local function wished(id)
	local db = ALootDB
	if type(db) ~= "table" or type(db.lists) ~= "table" then return false end
	for _, list in ipairs(db.lists) do
		if type(list.items) == "table" and list.items[id] then return true end
	end
	return false
end

function Protect.Reason(it)
	if not it or not it.id then return nil end
	local db = ns.db
	if db.neverSell[it.id] then return "is on your never-sell list" end
	if not db.protect then return nil end
	if db.protectUpgrade and AGear and AGear.IsUpgrade then
		local ok, up = pcall(AGear.IsUpgrade, it.link or it.id)
		if ok and up then return "is an upgrade for you" end
	end
	if db.protectWish and wished(it.id) then return "is on your ALoot wishlist" end
	if db.protectRare and type(it.quality) == "number" and it.quality >= 3 then return "is rare or better" end
	return nil
end

AVendor = AVendor or {}
function AVendor.IsProtected(id, link, quality)
	if not ns.db or type(id) ~= "number" then return false end
	return Protect.Reason({ id = id, link = link, quality = quality }) ~= nil
end

local function use(bag, slot)
	if C_Container and C_Container.UseContainerItem then
		C_Container.UseContainerItem(bag, slot)
	elseif UseContainerItem then
		UseContainerItem(bag, slot)
	end
end

local function resell(id)
	for bag = 0, 4 do
		for slot = 1, slots(bag) do
			local it = slotInfo(bag, slot)
			if it and it.id == id then
				use(bag, slot)
				return true
			end
		end
	end
	return false
end

local function buyback(id)
	if not GetNumBuybackItems or not BuybackItem then return false end
	for i = GetNumBuybackItems() or 0, 1, -1 do
		local link = GetBuybackItemLink and GetBuybackItemLink(i)
		if ns.ItemID(link) == id then
			BuybackItem(i)
			return true
		end
	end
	return false
end

function Protect.Used(bag, slot)
	if not open() or type(bag) ~= "number" or type(slot) ~= "number" then return end
	local it = snapshot[bag * 100 + slot]
	if not it or it.noValue then return end
	if allow[it.id] then return end
	local reason = Protect.Reason(it)
	if not reason then return end
	ns.After(0.3, function()
		if not open() then return end
		local now = slotInfo(bag, slot)
		if now and now.id == it.id and now.count == it.count then return end
		if not buyback(it.id) then return end
		local link = it.link or ns.ItemName(it.id)
		ns.Print("bought back " .. link .. " because it " .. reason)
		UI.Confirm(link .. " " .. reason .. ". Sell it anyway?", function()
			allow[it.id] = true
			ns.After(0.5, function()
				if open() then resell(it.id) end
				ns.After(1.5, function() allow[it.id] = nil end)
			end)
		end)
	end)
end

local selling

local function sellStep(count, tried)
	if not open() then
		selling = nil
		return
	end
	local n = 0
	for bag = 0, 4 do
		for slot = 1, slots(bag) do
			local it = slotInfo(bag, slot)
			local key = bag * 100 + slot
			if n < 6 and it and ns.db.alwaysSell[it.id] and not ns.db.neverSell[it.id] and not it.noValue and not it.locked and (tried[key] or 0) < 2 then
				tried[key] = (tried[key] or 0) + 1
				allow[it.id] = true
				use(bag, slot)
				n = n + 1
			end
		end
	end
	count = count + n
	if n == 0 or count >= 120 then
		selling = nil
		if count > 0 then ns.Print("sold " .. count .. (count == 1 and " listed stack" or " listed stacks")) end
		return
	end
	ns.After(0.4, function() sellStep(count, tried) end)
end

function Protect.SellListed()
	if selling or not open() or not next(ns.db.alwaysSell) then return end
	selling = true
	sellStep(0, {})
end

ns:On("MERCHANT_SHOW", function()
	allow = {}
	Protect.Snap()
end)
ns:On("MERCHANT_CLOSED", function()
	allow = {}
	selling = nil
end)
ns:On("BAG_UPDATE_DELAYED", function()
	if open() then ns.Debounce("snap", 0.6, Protect.Snap) end
end)

ns:Listen("LOGIN", function()
	if not hooksecurefunc then return end
	if C_Container and C_Container.UseContainerItem then
		pcall(hooksecurefunc, C_Container, "UseContainerItem", function(bag, slot) Protect.Used(bag, slot) end)
	elseif UseContainerItem then
		pcall(hooksecurefunc, "UseContainerItem", function(bag, slot) Protect.Used(bag, slot) end)
	end
end)
