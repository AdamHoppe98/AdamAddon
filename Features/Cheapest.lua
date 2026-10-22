local addonName, ns = ...

-- A small always-on list of the 5 bag items a vendor would pay least for, so you can
-- make room. Ctrl + left-click a row to delete that item.
--
-- Only the backpack and the four normal bags are scanned; the reagent bag is skipped.
-- Items with no sell price are left out. Value is the whole stack (price x count).
-- The page in the main window holds the settings (show, lock, reset position).

local Cheapest = ns:RegisterModule("Cheapest", {
	title = "Cheapest Items",
	order = 30,
	defaults = {
		shown = true,
		locked = true,
		position = nil, -- { point, relativePoint, x, y }; nil = default
	},
	commands = {
		cheapestlist = {
			desc = "show or hide the cheapest items list",
			func = function(module)
				module:SetShown(not module.db.shown)
			end,
		},
	},
})

local FIRST_BAG = Enum.BagIndex.Backpack
local LAST_BAG = Enum.BagIndex.Bag_4   -- Enum.BagIndex.ReagentBag (5) comes after this
local NUM_ROWS = 5
local ROW_HEIGHT = 20
local FRAME_WIDTH = 260
local HEADER_HEIGHT = 18
local DEFAULT_POSITION = { "RIGHT", "RIGHT", -60, -120 }

local frame
local rows = {}
local pendingItemInfo = false

---------------------------------------------------------------------------
-- Scanning the bags
---------------------------------------------------------------------------

local function GetSellPrice(itemID)
	local sellPrice = select(11, C_Item.GetItemInfo(itemID))
	return sellPrice
end

local function ScanBags()
	local items = {}
	local missingInfo = false

	for bag = FIRST_BAG, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and not info.hasNoValue then
				local sellPrice = GetSellPrice(info.itemID)
				if sellPrice == nil then
					-- Not cached yet; GET_ITEM_INFO_RECEIVED refreshes the list.
					missingInfo = true
				elseif sellPrice > 0 then
					table.insert(items, {
						bag = bag,
						slot = slot,
						itemID = info.itemID,
						link = info.hyperlink,
						icon = info.iconFileID,
						count = info.stackCount,
						value = sellPrice * info.stackCount,
					})
				end
			end
		end
	end

	table.sort(items, function(a, b)
		if a.value ~= b.value then
			return a.value < b.value
		end
		if a.bag ~= b.bag then
			return a.bag < b.bag
		end
		return a.slot < b.slot
	end)

	pendingItemInfo = missingInfo
	return items
end

---------------------------------------------------------------------------
-- Deleting
---------------------------------------------------------------------------

function Cheapest:DeleteItem(item)
	if InCombatLockdown() then
		self:Print("can't delete items in combat.")
		return
	end
	if GetCursorInfo() then
		self:Print("your cursor is holding something; put it down first.")
		return
	end

	-- The bags may have changed since the list was drawn.
	local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
	if not info or info.itemID ~= item.itemID then
		self:Refresh()
		return
	end
	if info.isLocked then
		self:Print("that item is locked right now.")
		return
	end

	C_Container.PickupContainerItem(item.bag, item.slot)
	local cursorType, cursorItemID = GetCursorInfo()
	if cursorType == "item" and cursorItemID == item.itemID then
		DeleteCursorItem()
		self:Print("deleted " .. (info.hyperlink or "item") .. (info.stackCount > 1 and (" x" .. info.stackCount) or "") .. ".")
	end
	-- Never leave an item stuck on the cursor if the delete didn't happen.
	if GetCursorInfo() then
		ClearCursor()
	end
end

---------------------------------------------------------------------------
-- The list frame
---------------------------------------------------------------------------

local function CreateRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 4, -(HEADER_HEIGHT + (index - 1) * ROW_HEIGHT))
	row:SetPoint("TOPRIGHT", -4, -(HEADER_HEIGHT + (index - 1) * ROW_HEIGHT))
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row:RegisterForClicks("LeftButtonUp")

	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
	row.Icon:SetPoint("LEFT", 2, 0)
	row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.Value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Value:SetPoint("RIGHT", -2, 0)
	row.Value:SetJustifyH("RIGHT")

	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 4, 0)
	row.Name:SetPoint("RIGHT", row.Value, "LEFT", -6, 0)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)

	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetBagItem(self.item.bag, self.item.slot)
		GameTooltip:AddLine("Ctrl + left-click to delete", 1, 0.3, 0.3)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		if IsControlKeyDown() then
			Cheapest:DeleteItem(self.item)
		end
	end)

	row:Hide()
	return row
end

local function SetRow(row, item)
	row.item = item
	row.Icon:SetTexture(item.icon)
	local name = item.link or ""
	if item.count > 1 then
		name = name .. " |cffffffffx" .. item.count .. "|r"
	end
	row.Name:SetText(name)
	row.Value:SetText(GetMoneyString(item.value))
	row:Show()
end

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	Cheapest.db.position = { point, relativePoint, x, y }
end

local function RestorePosition()
	local position = Cheapest.db.position or DEFAULT_POSITION
	frame:ClearAllPoints()
	frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
end

local function CreateListFrame()
	frame = CreateFrame("Frame", "AdamAddonCheapestFrame", UIParent)
	frame:SetWidth(FRAME_WIDTH)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if not Cheapest.db.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)

	local background = frame:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.5)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", 6, -4)
	title:SetText("Cheapest items")

	frame.EmptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.EmptyText:SetPoint("TOPLEFT", 6, -HEADER_HEIGHT - 2)
	frame.EmptyText:SetText("Nothing with a sell price in your bags.")

	for i = 1, NUM_ROWS do
		rows[i] = CreateRow(frame, i)
	end

	RestorePosition()
end

function Cheapest:Refresh()
	if not frame or not frame:IsShown() then
		return
	end

	local items = ScanBags()
	local shownRows = 0
	for i, row in ipairs(rows) do
		local item = items[i]
		if item then
			SetRow(row, item)
			shownRows = i
		else
			row.item = nil
			row:Hide()
		end
	end

	frame.EmptyText:SetShown(shownRows == 0)
	frame:SetHeight(HEADER_HEIGHT + math.max(shownRows, 1) * ROW_HEIGHT + 4)
end

function Cheapest:SetShown(shown)
	self.db.shown = shown
	if frame then
		frame:SetShown(shown)
		self:Refresh()
	end
	if self.shownCheck then
		self.shownCheck:SetChecked(shown)
	end
end

function Cheapest:SetLocked(locked)
	self.db.locked = locked
end

function Cheapest:ResetPosition()
	self.db.position = nil
	if frame then
		RestorePosition()
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

function Cheapest:OnLogin()
	CreateListFrame()
	frame:SetShown(self.db.shown)
	self:Refresh()
end

function Cheapest:OnBagsChanged()
	self:Refresh()
end

function Cheapest:OnItemInfoReceived()
	if pendingItemInfo then
		self:Refresh()
	end
end

Cheapest:RegisterEvent("BAG_UPDATE_DELAYED", "OnBagsChanged")
Cheapest:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnItemInfoReceived")

---------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------

local function CreateCheck(parent, text, checked, onClick)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check.Text:SetFontObject("GameFontHighlight")
	check.Text:SetText(text)
	check:SetChecked(checked)
	check:SetScript("OnClick", function(button)
		onClick(button:GetChecked())
	end)
	return check
end

function Cheapest:CreatePage(page)
	local module = self

	local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)
	title:SetText("Cheapest Items")

	local help = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	help:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	help:SetJustifyH("LEFT")
	help:SetText("An on-screen list of the 5 bag items worth least at a vendor (whole stack). "
		.. "Reagent bag not included. |cffff5050Ctrl + left-click a row deletes the item, without asking.|r")

	local shownCheck = CreateCheck(page, "Show the list", self.db.shown, function(checked)
		module:SetShown(checked)
	end)
	shownCheck:SetPoint("TOPLEFT", help, "BOTTOMLEFT", -4, -10)
	self.shownCheck = shownCheck

	local lockCheck = CreateCheck(page, "Lock the list (untick to drag it by its background)", self.db.locked, function(checked)
		module:SetLocked(checked)
	end)
	lockCheck:SetPoint("TOPLEFT", shownCheck, "BOTTOMLEFT", 0, 2)
	self.lockCheck = lockCheck

	local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	reset:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 4, -10)
	reset:SetSize(140, 22)
	reset:SetText("Reset position")
	reset:SetScript("OnClick", function()
		module:ResetPosition()
	end)

	local note = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -12)
	note:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	note:SetJustifyH("LEFT")
	note:SetText("Type |cffffd100/adam cheapestlist|r to show or hide the list.")
end

function Cheapest:OnPageShown(page)
	self.shownCheck:SetChecked(self.db.shown)
	self.lockCheck:SetChecked(self.db.locked)
end
