local addonName, ns = ...

-- A small always-on list of the 5 bag items a vendor would pay least for, so you can
-- make room. Ctrl + left-click a row to delete that item; Shift + left-click hides that
-- item from the list for good (every stack of it), until the hidden list is cleared.
--
-- Only the backpack and the four normal bags are scanned; the reagent bag is skipped.
-- Items with no sell price are left out. Value is the whole stack (price x count).
-- The header shows used / total bag slots for those same bags, red when full.
-- The page in the main window holds the settings (show, reset position). Moving it is
-- the window's Unlock frames checkbox and the Layout page, like the other frames.

local Cheapest = ns:RegisterModule("Cheapest", {
	title = "Cheapest Items",
	order = 30,
	defaults = {
		shown = true,
		position = nil, -- { point, relativePoint, x, y }; nil = default
		hidden = {},    -- [itemID] = true for items never shown in the list
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
			if info and not info.hasNoValue and not Cheapest.db.hidden[info.itemID] then
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
-- Hiding
---------------------------------------------------------------------------

local function CountHidden()
	local count = 0
	for _ in pairs(Cheapest.db.hidden) do
		count = count + 1
	end
	return count
end

-- Name (quality-coloured link if the item is cached) and icon for an item that may not
-- be in the bags any more.
local function GetHiddenItemDisplay(itemID)
	local link = select(2, C_Item.GetItemInfo(itemID))
	local name = link or C_Item.GetItemNameByID(itemID)
	if not name then
		-- Not cached; GET_ITEM_INFO_RECEIVED refreshes the list once it loads.
		C_Item.RequestLoadItemDataByID(itemID)
		name = "Item #" .. itemID
	end
	return name, C_Item.GetItemIconByID(itemID)
end

function Cheapest:UnhideItem(itemID)
	self.db.hidden[itemID] = nil
	self:Refresh()
	self:UpdateHiddenText()
end

-- Updates the count and the list of hidden items on the page.
function Cheapest:UpdateHiddenText()
	if not self.hiddenText then
		return
	end
	local count = CountHidden()
	if count == 0 then
		self.hiddenText:SetText("No hidden items. Shift + left-click an item in the list to hide it.")
	else
		self.hiddenText:SetText("Hidden items (" .. count .. ") - click one to show it in the list again:")
	end

	local entries = {}
	for itemID in pairs(self.db.hidden) do
		local name, icon = GetHiddenItemDisplay(itemID)
		table.insert(entries, { itemID = itemID, name = name, icon = icon })
	end
	table.sort(entries, function(a, b)
		return a.itemID < b.itemID
	end)
	self.hiddenScrollBox:SetDataProvider(CreateDataProvider(entries), ScrollBoxConstants.RetainScrollPosition)
end

function Cheapest:HideItem(item)
	self.db.hidden[item.itemID] = true
	self:Print("hiding " .. (item.link or "item") .. " from the cheapest list. Clear it on the Cheapest Items page.")
	self:Refresh()
	self:UpdateHiddenText()
end

function Cheapest:ClearHidden()
	wipe(self.db.hidden)
	self:Refresh()
	self:UpdateHiddenText()
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
		GameTooltip:AddLine("Shift + left-click to hide from this list", 0.6, 0.8, 1)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	row:SetScript("OnClick", function(self)
		-- Both keys held: do nothing rather than guess.
		if IsControlKeyDown() and not IsShiftKeyDown() then
			Cheapest:DeleteItem(self.item)
		elseif IsShiftKeyDown() and not IsControlKeyDown() then
			Cheapest:HideItem(self.item)
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

local function RestorePosition()
	local position = Cheapest.db.position or DEFAULT_POSITION
	frame:ClearAllPoints()
	frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
end

-- Called by Layout (dragging, snapping, the X/Y sliders) with the list's centre offset
-- from the screen centre. Stored by its top edge, so the top stays put while the list
-- grows and shrinks with the number of rows.
local function SetPosition(x, y)
	local top = y + frame:GetHeight() / 2
	Cheapest.db.position = { "TOP", "CENTER", x, math.floor(top + 0.5) }
	RestorePosition()
end

local function CreateListFrame()
	frame = CreateFrame("Frame", "AdamAddonCheapestFrame", UIParent)
	frame:SetWidth(FRAME_WIDTH)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	-- Dragged by its background while the window's Unlock frames is ticked.
	frame:SetScript("OnDragStart", function(self)
		if ns.IsUnlocked and ns.IsUnlocked() then
			self:StartMoving()
			self.moving = true
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		if not self.moving then
			return
		end
		self.moving = false
		self:StopMovingOrSizing()
		ns.MoverDropped("cheapest") -- snaps and saves
	end)

	local background = frame:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.5)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", 6, -4)
	title:SetText("Cheapest items")

	-- Used / total bag slots, top right; red when the bags are full.
	frame.SpaceText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.SpaceText:SetPoint("TOPRIGHT", -6, -4)
	frame.SpaceText:SetJustifyH("RIGHT")

	frame.EmptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.EmptyText:SetPoint("TOPLEFT", 6, -HEADER_HEIGHT - 2)
	frame.EmptyText:SetText("Nothing with a sell price in your bags.")

	for i = 1, NUM_ROWS do
		rows[i] = CreateRow(frame, i)
	end

	RestorePosition()
end

-- Free and total slots in the same bags the list scans: the backpack and the four bags,
-- not the reagent bag.
local function GetBagSpace()
	local free, total = 0, 0
	for bag = FIRST_BAG, LAST_BAG do
		free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
		total = total + C_Container.GetContainerNumSlots(bag)
	end
	return free, total
end

function Cheapest:Refresh()
	if not frame or not frame:IsShown() then
		return
	end

	local free, total = GetBagSpace()
	frame.SpaceText:SetFormattedText("%d/%d", total - free, total) -- used / total
	if free == 0 then
		frame.SpaceText:SetTextColor(1, 0.2, 0.2)
	else
		frame.SpaceText:SetTextColor(1, 1, 1)
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

function Cheapest:ResetPosition()
	self.db.position = nil
	if frame then
		RestorePosition()
	end
end

if ns.RegisterMover then
	ns:RegisterMover("cheapest", {
		title = "Cheapest items list",
		getFrame = function()
			return frame
		end,
		save = SetPosition,
	})
end

-- Locking is the window's Unlock frames checkbox now, for all frames at once.
function Cheapest:OnInit()
	self.db.locked = nil
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

function Cheapest:OnItemInfoReceived(event, itemID, success)
	if pendingItemInfo then
		self:Refresh()
	end
	-- A hidden item's name may just have loaded. Only on success: a failed load would
	-- request it again and loop.
	if success and self.db and self.db.hidden[itemID] and self.hiddenScrollBox and self.hiddenScrollBox:IsVisible() then
		self:UpdateHiddenText()
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

local HIDDEN_ROW_HEIGHT = 20

-- Rows are recycled by the scroll box; the children are built the first time only.
local function InitializeHiddenRow(row, entry)
	if not row.Icon then
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:RegisterForClicks("LeftButtonUp")

		row.Icon = row:CreateTexture(nil, "ARTWORK")
		row.Icon:SetSize(HIDDEN_ROW_HEIGHT - 4, HIDDEN_ROW_HEIGHT - 4)
		row.Icon:SetPoint("LEFT", 2, 0)
		row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
		row.Name:SetPoint("RIGHT", -4, 0)
		row.Name:SetJustifyH("LEFT")
		row.Name:SetWordWrap(false)

		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(self.itemID)
			GameTooltip:AddLine("Click to show it in the cheapest list again", 0.6, 0.8, 1)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", function(self)
			GameTooltip:Hide()
			Cheapest:UnhideItem(self.itemID)
		end)
	end

	row.itemID = entry.itemID
	row.Icon:SetTexture(entry.icon)
	row.Name:SetText(entry.name)
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
		.. "Reagent bag not included. |cffff5050Ctrl + left-click a row deletes the item, without asking.|r "
		.. "|cff99ccffShift + left-click hides that item from the list.|r "
		.. "|cffffd100/adam cheapestlist|r shows or hides the list.")

	local shownCheck = CreateCheck(page, "Show the list", self.db.shown, function(checked)
		module:SetShown(checked)
	end)
	shownCheck:SetPoint("TOPLEFT", help, "BOTTOMLEFT", -4, -10)
	self.shownCheck = shownCheck

	local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	reset:SetPoint("TOPLEFT", shownCheck, "BOTTOMLEFT", 4, -10)
	reset:SetSize(140, 22)
	reset:SetText("Reset position")
	reset:SetScript("OnClick", function()
		module:ResetPosition()
	end)

	local clearHidden = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	clearHidden:SetPoint("LEFT", reset, "RIGHT", 8, 0)
	clearHidden:SetSize(160, 22)
	clearHidden:SetText("Clear hidden items")
	clearHidden:SetScript("OnClick", function()
		module:ClearHidden()
	end)

	self.hiddenText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.hiddenText:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -12)
	self.hiddenText:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	self.hiddenText:SetJustifyH("LEFT")

	-- Scrollable list of hidden items; click a row to show that item again.
	local scrollBox = CreateFrame("Frame", nil, page, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", self.hiddenText, "BOTTOMLEFT", 0, -6)
	scrollBox:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -16, 4)

	local scrollBar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(HIDDEN_ROW_HEIGHT)
	view:SetElementInitializer("Button", InitializeHiddenRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	self.hiddenScrollBox = scrollBox

	self:UpdateHiddenText()
end

function Cheapest:OnPageShown(page)
	self.shownCheck:SetChecked(self.db.shown)
	self:UpdateHiddenText()
end
