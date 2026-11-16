local _, ns = ...
local UI = ns.UI
local C = UI.colors

local Window = {}
ns.Window = Window

local frame
local tab = "restock"

local function rows()
	local out = {}
	if tab == "restock" then
		for id, amount in pairs(ns.chardb.restock) do
			out[#out + 1] = { id = id, name = ns.ItemName(id), amount = amount, have = ns.Count(id) }
		end
	else
		for id in pairs(ns.db.neverSell) do
			out[#out + 1] = { id = id, name = ns.ItemName(id) }
		end
	end
	table.sort(out, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	if #out == 0 then
		out[1] = {
			note = tab == "restock" and "Nothing yet. Alt-right-click an item at a merchant, or use Add item."
				or "Nothing yet. Items here are never sold without asking.",
		}
	end
	return out
end

local function setAmount(id)
	UI.Prompt("How many " .. ns.ItemName(id) .. " to keep in your bags?", tostring(ns.chardb.restock[id] or 20), function(text)
		local n = tonumber(text)
		if not n then return end
		ns.chardb.restock[id] = n > 0 and math.floor(n) or nil
		ns:Fire("LISTS")
	end)
end

local function createRow(list)
	local row = CreateFrame("Button", nil, list)
	row.hl = UI.Fill(row, C.hover, "HIGHLIGHT")
	row.right = UI.Text(row, "GameFontHighlightSmall", "RIGHT", C.dim)
	row.right:SetPoint("RIGHT", -8, 0)
	row.text = UI.Text(row, "GameFontHighlight")
	row.text:SetPoint("LEFT", 10, 0)
	row.text:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", function(self)
		local d = self.data
		if not d or d.note then return end
		local entries = { { text = d.name, title = true } }
		if tab == "restock" then
			entries[#entries + 1] = { text = "Change amount", func = function() setAmount(d.id) end }
			entries[#entries + 1] = { text = "Remove", func = function()
				ns.chardb.restock[d.id] = nil
				ns:Fire("LISTS")
			end }
		else
			entries[#entries + 1] = { text = "Remove", func = function()
				ns.db.neverSell[d.id] = nil
				ns:Fire("LISTS")
			end }
		end
		UI.Menu(self, entries)
	end)
	return row
end

local function updateRow(row, d)
	if d.note then
		row.text:SetText(d.note)
		row.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
		row.right:SetText("")
		return
	end
	row.text:SetText(d.name)
	row.text:SetTextColor(C.text[1], C.text[2], C.text[3])
	if d.amount then
		row.right:SetText(d.have .. " / " .. d.amount)
		if d.have >= d.amount then
			row.right:SetTextColor(0.35, 0.8, 0.35)
		else
			row.right:SetTextColor(1, 0.6, 0.3)
		end
	else
		row.right:SetText("")
	end
end

local function addItem()
	UI.Prompt("Item link or item ID", "", function(text)
		local id = ns.ItemID(text)
		if not id then
			ns.Print("that is not an item link or ID")
			return
		end
		if tab == "restock" then
			setAmount(id)
		else
			ns.db.neverSell[id] = true
			ns:Fire("LISTS")
		end
	end)
end

local function build()
	frame = UI.Window("AVendorFrame", "AVendor", 420, 440, ns.db.window)
	local options = UI.Button(frame.bar, "Options", function(self) UI.Menu(self, ns.Options()) end)
	options:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)

	local body = frame.body
	local restock = UI.Button(body, "Restock list", function()
		tab = "restock"
		Window.Refresh()
	end)
	restock:SetPoint("TOPLEFT", 8, -6)
	frame.restockTab = restock
	local never = UI.Button(body, "Never sell", function()
		tab = "never"
		Window.Refresh()
	end)
	never:SetPoint("LEFT", restock, "RIGHT", 6, 0)
	frame.neverTab = never
	local add = UI.Button(body, "Add item", addItem)
	add:SetPoint("TOPRIGHT", -8, -6)
	frame.addButton = add
	local now = UI.Button(body, "Restock now", function() ns.Merchant.Restock(true) end)
	now:SetPoint("RIGHT", add, "LEFT", -6, 0)
	frame.nowButton = now

	local list = UI.List(body, 24, createRow, updateRow)
	list:SetPoint("TOPLEFT", 0, -34)
	list:SetPoint("BOTTOMRIGHT", 0, 24)
	frame.list = list

	local hint = UI.Text(body, "GameFontDisableSmall", "LEFT", C.dim)
	hint:SetPoint("BOTTOMLEFT", 10, 6)
	hint:SetText("At a merchant: alt-click buys a stack, shift-right-click buys an amount, alt-right-click sets restock")
end

function Window.Refresh()
	if not frame or not frame:IsShown() then return end
	frame.restockTab:SetActive(tab == "restock")
	frame.neverTab:SetActive(tab == "never")
	frame.nowButton:SetShown(tab == "restock")
	frame.list:SetData(rows(), true)
end

function Window.Show()
	if not frame then build() end
	frame:Show()
	Window.Refresh()
end

function Window.Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		Window.Show()
	end
end

ns:Listen("LISTS", Window.Refresh)
ns:On("BAG_UPDATE_DELAYED", function()
	if frame and frame:IsShown() then ns.Debounce("window", 0.4, Window.Refresh) end
end)
