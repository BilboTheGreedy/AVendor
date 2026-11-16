local ADDON, ns = ...

local defaults = {
	restock = true,
	restockCap = 100000,
	guildRepair = false,
	counts = true,
	tint = true,
	protect = true,
	protectRare = true,
	protectWish = true,
	protectUpgrade = true,
	neverSell = {},
	window = { scale = 1 },
}

local charDefaults = {
	restock = {},
}

ACore.New(ADDON, ns, { db = "AVendorDB", defaults = defaults, char = "AVendorCharDB", charDefaults = charDefaults })

ACore.Register({
	name = "AVendor",
	title = "AVendor",
	slash = "/avendor",
	desc = "restock, bulk buy, sell protection",
	toggle = function() ns.Window.Toggle() end,
})

local function loaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		local ok, v = pcall(C_AddOns.IsAddOnLoaded, name)
		return ok and v and true or false
	end
	if IsAddOnLoaded then return IsAddOnLoaded(name) and true or false end
	return false
end

ns:Listen("LOGIN", function()
	if ns.db.repair == nil then
		ns.db.repair = not (loaded("ABag") or ABagDB ~= nil)
	end
end)

function ns.ItemID(v)
	if type(v) == "number" then return v end
	if type(v) ~= "string" then return nil end
	local id = v:match("item:(%d+)") or v:match("^%s*(%d+)%s*$")
	return tonumber(id)
end

function ns.ItemName(id)
	local name
	if C_Item and C_Item.GetItemInfo then
		name = C_Item.GetItemInfo(id)
	elseif GetItemInfo then
		name = GetItemInfo(id)
	end
	return name or ("Item " .. id)
end

function ns.ItemLink(id)
	local _, link
	if C_Item and C_Item.GetItemInfo then
		_, link = C_Item.GetItemInfo(id)
	elseif GetItemInfo then
		_, link = GetItemInfo(id)
	end
	return link or ns.ItemName(id)
end

function ns.Count(id, bank)
	local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
	if not fn then return 0 end
	local ok, n = pcall(fn, id, bank and true or false)
	if ok and type(n) == "number" and not ns.IsSecret(n) then return n end
	return 0
end

function ns.Options()
	local db = ns.db
	local UI = ns.UI
	local function changed() ns:Fire("OPTIONS") end
	local entries = {
		{ text = "Buying", title = true },
		UI.Check(db, "restock", "Restock automatically", changed),
		UI.Check(db, "counts", "Show how many I own", changed),
		UI.Check(db, "tint", "Mark known recipes and unusable items", changed),
		{ text = "Restock spending limit", title = true },
	}
	for _, gold in ipairs({ 1, 5, 10, 50, 0 }) do
		local copper = gold * 10000
		entries[#entries + 1] = {
			text = gold == 0 and "No limit" or (gold .. "g per visit"), checked = db.restockCap == copper,
			func = function() db.restockCap = copper end,
		}
	end
	entries[#entries + 1] = { text = "Selling", title = true }
	entries[#entries + 1] = UI.Check(db, "protect", "Ask before selling protected items")
	entries[#entries + 1] = UI.Check(db, "protectRare", "Protect rare and better")
	entries[#entries + 1] = UI.Check(db, "protectWish", "Protect ALoot wishlist items")
	entries[#entries + 1] = UI.Check(db, "protectUpgrade", "Protect upgrades")
	entries[#entries + 1] = { text = "Repair", title = true }
	entries[#entries + 1] = UI.Check(db, "repair", "Repair automatically")
	entries[#entries + 1] = UI.Check(db, "guildRepair", "Use guild funds first")
	return entries
end

SLASH_AVENDOR1 = "/avendor"
SLASH_AVENDOR2 = "/av"
SlashCmdList["AVENDOR"] = function(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	cmd = cmd and cmd:lower()
	if not cmd then
		ns.Window.Toggle()
	elseif cmd == "restock" then
		ns.Merchant.Restock(true)
	elseif cmd == "keep" then
		local id = ns.ItemID(rest)
		if id then
			ns.db.neverSell[id] = true
			ns.Print("will not sell " .. ns.ItemLink(id) .. " without asking")
			ns:Fire("LISTS")
		else
			ns.Print("/avendor keep <item link or id>")
		end
	elseif cmd == "add" then
		local link, amount = rest:match("^(.-)%s+(%d+)$")
		local id = ns.ItemID(link)
		if id and tonumber(amount) then
			ns.chardb.restock[id] = tonumber(amount)
			ns.Print("keeping " .. amount .. " of " .. ns.ItemLink(id))
			ns:Fire("LISTS")
		else
			ns.Print("/avendor add <item link or id> <amount>")
		end
	else
		ns.Print("/avendor, /avendor restock, /avendor add <item> <amount>, /avendor keep <item>")
	end
end
