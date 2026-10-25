local addonName, ns = ...

-- Tracked buffs: your own buffs from a list of spell IDs, shown together somewhere you
-- choose, styled like the other auras (UnitFrames shares its aura button setup).
--
-- Blizzard's aura container does the filtering (candidate filter includeSpellIDs), so
-- it works while aura data is secret; filtering your own buffs by spell ID is always
-- allowed. Only active buffs are shown.
--
-- The icons hang off a handle (one icon in size) that Unlock frames moves; it's only
-- visible while unlocked. The container is as big as its icons, so anchoring it by its
-- centre to the handle centres the row: one buff in the middle, two around the gap.

local TrackedBuffs = ns:RegisterModule("TrackedBuffs", {
	title = "Tracked Buffs",
	order = 27,
	defaults = {
		enabled = true,
		spells = {},        -- spell IDs, in the order they were added
		size = 40,
		spacing = 4,
		textSize = 14,
		showSwipe = true,   -- off: only the time-left text
		growth = "center",  -- key in GROWTH
		position = nil,     -- { x, y } handle centre from the screen centre; nil = default
	},
})

local MAX_SHOWN = 40
local DEFAULT_POSITION = { 0, -80 }
local ROW_HEIGHT = 22
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local FAR = 4000 -- a line size no row reaches

-- flowAnchor/horizontal/vertical: how the icons flow inside the container.
-- point: which point of the container sits on the same point of the handle.
-- column: one icon per line.
local GROWTH = {
	{ key = "center", name = "Centred row", flowAnchor = "TOPLEFT", horizontal = "Right", vertical = "Down", point = "CENTER" },
	{ key = "right", name = "To the right", flowAnchor = "TOPLEFT", horizontal = "Right", vertical = "Down", point = "LEFT" },
	{ key = "left", name = "To the left", flowAnchor = "TOPRIGHT", horizontal = "Left", vertical = "Down", point = "RIGHT" },
	{ key = "down", name = "Downwards", flowAnchor = "TOPLEFT", horizontal = "Right", vertical = "Down", point = "TOP", column = true },
	{ key = "up", name = "Upwards", flowAnchor = "BOTTOMLEFT", horizontal = "Right", vertical = "Up", point = "BOTTOM", column = true },
}

local handle, container
local texts = {}     -- countdown and stack count font strings, for the text size
local cooldowns = {} -- cooldown frames, for the swipe on/off

local function GetGrowth(key)
	for _, growth in ipairs(GROWTH) do
		if growth.key == key then
			return growth
		end
	end
	return GROWTH[1]
end

local function IsUnlocked()
	return ns.IsUnlocked ~= nil and ns.IsUnlocked()
end

-- name, icon of a spell ID, or a stand-in when the client doesn't know it.
local function GetSpellDisplay(spellID)
	local info = C_Spell.GetSpellInfo(spellID)
	if info then
		return info.name, info.iconID
	end
	return "Spell " .. spellID, UNKNOWN_ICON
end

---------------------------------------------------------------------------
-- Building and layout
---------------------------------------------------------------------------

local function Build()
	handle = CreateFrame("Frame", nil, UIParent)
	handle:SetFrameStrata("MEDIUM")
	handle:SetClampedToScreen(true)
	handle:SetMovable(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function(self)
		if IsUnlocked() then
			self:StartMoving()
			self.moving = true
		end
	end)
	handle:SetScript("OnDragStop", function(self)
		if not self.moving then
			return
		end
		self.moving = false
		self:StopMovingOrSizing()
		ns.MoverDropped("trackedbuffs") -- snaps and saves
	end)
	handle.Background = handle:CreateTexture(nil, "BACKGROUND")
	handle.Background:SetAllPoints()
	handle.Background:SetColorTexture(0.2, 0.6, 1, 0.25)
	handle.Label = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	handle.Label:SetPoint("BOTTOM", handle, "TOP", 0, 2)
	handle.Label:SetText("Tracked buffs")

	container = CreateFrame("AuraContainer", nil, handle, "CustomAuraContainerTemplate")
	container:AddAuraGroup("auras", "HELPFUL", {
		maxFrameCount = MAX_SHOWN,
		initializeFrame = function(button)
			local db = TrackedBuffs.db
			ns.InitializeAuraButton(button, db.size, db.textSize, texts, cooldowns)
			button:SetTooltipAnchorPoint("ANCHOR_BOTTOMLEFT")
			for _, cooldown in ipairs(cooldowns) do
				pcall(cooldown.SetDrawSwipe, cooldown, db.showSwipe == true)
			end
		end,
	})
	container:SetUnit("player")
end

local function PlaceHandle()
	local position = TrackedBuffs.db.position or DEFAULT_POSITION
	handle:ClearAllPoints()
	handle:SetPoint("CENTER", UIParent, "CENTER", position[1], position[2])
end

-- The spell list as the set the candidate filter wants: [spellID] = true.
local function GetSpellSet()
	local set = {}
	for _, spellID in ipairs(TrackedBuffs.db.spells) do
		set[spellID] = true
	end
	return set
end

local function Layout()
	local db = TrackedBuffs.db
	local size, spacing = db.size, db.spacing
	local growth = GetGrowth(db.growth)

	handle:SetSize(size, size)
	PlaceHandle()
	handle:SetShown(db.enabled)
	local unlocked = IsUnlocked()
	handle:EnableMouse(unlocked)
	handle.Background:SetShown(unlocked)
	handle.Label:SetShown(unlocked)

	container:ClearAllPoints()
	container:SetPoint(growth.point, handle, growth.point)
	container:SetFlowLayoutAnchorPoint(growth.flowAnchor)
	container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection[growth.horizontal], AnchorUtil.FlowDirection[growth.vertical])
	container:SetFlowLayoutMaximumLineSize(growth.column and size or FAR)
	container:SetAuraGroupLayout("auras", {
		elementWidth = size,
		elementHeight = size,
		elementSpacing = spacing,
		lineSpacing = spacing,
	})
	container:SetAuraGroupCandidateFilters("auras", { includeSpellIDs = GetSpellSet() })
	container:SetAuraGroupEnabled("auras", db.enabled == true)

	ns.ResizeAuraButtons(container, size)
	ns.SetAuraTextSize(texts, db.textSize)
	for _, cooldown in ipairs(cooldowns) do
		pcall(cooldown.SetDrawSwipe, cooldown, db.showSwipe == true)
	end
end

function TrackedBuffs:Apply()
	if not handle then
		Build()
	end
	xpcall(Layout, geterrorhandler())
end

function TrackedBuffs:OnLogin()
	self:Apply()
end

-- The Unlock frames checkbox: the handle shows and takes the mouse.
function TrackedBuffs:OnUnlockChanged()
	self:Apply()
end

function TrackedBuffs:OnFontChanged()
	self:Apply()
end

if ns.RegisterMover then
	ns:RegisterMover("trackedbuffs", {
		title = "Tracked buffs",
		getFrame = function()
			if TrackedBuffs.db and TrackedBuffs.db.enabled then
				return handle
			end
		end,
		save = function(x, y)
			TrackedBuffs.db.position = { x, y }
			if handle then
				PlaceHandle()
			end
		end,
	})
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

-- Adds a buff by spell ID or by the name of a spell the client knows. Returns an
-- error message, or nil when it was added.
function TrackedBuffs:AddSpell(input)
	input = strtrim(input or "")
	if input == "" then
		return "Type a spell ID or name."
	end
	local spellID = tonumber(input)
	local info = C_Spell.GetSpellInfo(spellID or input)
	if info then
		spellID = info.spellID
	elseif not spellID then
		return "No spell called \"" .. input .. "\" found. Try its spell ID."
	end
	for _, tracked in ipairs(self.db.spells) do
		if tracked == spellID then
			return "That one is already tracked."
		end
	end
	table.insert(self.db.spells, spellID)
	self:Apply()
	self:UpdateList()
end

function TrackedBuffs:RemoveSpell(spellID)
	for index, tracked in ipairs(self.db.spells) do
		if tracked == spellID then
			table.remove(self.db.spells, index)
			break
		end
	end
	self:Apply()
	self:UpdateList()
end

function TrackedBuffs:UpdateList()
	if not self.listBox then
		return
	end
	local entries = {}
	for _, spellID in ipairs(self.db.spells) do
		local name, icon = GetSpellDisplay(spellID)
		table.insert(entries, { spellID = spellID, name = name, icon = icon })
	end
	self.listBox:SetDataProvider(CreateDataProvider(entries), ScrollBoxConstants.RetainScrollPosition)
	self.emptyText:SetShown(#entries == 0)
end

local function InitializeListRow(row, entry)
	if not row.Icon then
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:RegisterForClicks("LeftButtonUp")

		row.Icon = row:CreateTexture(nil, "ARTWORK")
		row.Icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
		row.Icon:SetPoint("LEFT", 2, 0)
		row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
		row.Name:SetPoint("RIGHT", -4, 0)
		row.Name:SetJustifyH("LEFT")
		row.Name:SetWordWrap(false)

		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetSpellByID(self.spellID)
			GameTooltip:AddLine("Click to stop tracking it", 0.6, 0.8, 1)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", function(self)
			GameTooltip:Hide()
			TrackedBuffs:RemoveSpell(self.spellID)
		end)
	end

	row.spellID = entry.spellID
	row.Icon:SetTexture(entry.icon)
	row.Name:SetText(entry.name .. "  |cff808080" .. entry.spellID .. "|r")
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------

local function CreateLabel(parent, text, template)
	local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

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

-- range = { min, max, steps }
local function CreateSlider(parent, anchor, labelText, key, range)
	local label = CreateLabel(parent, labelText)
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
	label:SetWidth(120)

	local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("LEFT", label, "RIGHT", 8, 0)
	slider:SetSize(200, 20)
	slider:Init(TrackedBuffs.db[key], range[1], range[2], range[3], {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(value)
			return string.format("%d", value)
		end,
	})
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		value = math.floor(value + 0.5)
		if TrackedBuffs.db[key] ~= value then
			TrackedBuffs.db[key] = value
			TrackedBuffs:Apply()
		end
	end, slider)
	ns.MakeSliderEditable(slider)
	return slider, label
end

function TrackedBuffs:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Tracked Buffs", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)
	local intro = CreateLabel(page, "Your own buffs from this list, shown together while active. Add a buff by its "
		.. "spell ID (the buff's own ID; it can differ from the ability's) or by the name of a spell you know. "
		.. "Move them with |cffffd100Unlock frames|r or on the Layout page.", "GameFontDisableSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local enableCheck = CreateCheck(page, "Show tracked buffs", self.db.enabled, function(checked)
		module.db.enabled = checked
		module:Apply()
	end)
	enableCheck:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -4, -6)

	-- Adding: spell ID or name, Enter or the button.
	local addLabel = CreateLabel(page, "Spell ID or name")
	addLabel:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 4, -10)
	local addBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
	addBox:SetSize(150, 20)
	addBox:SetPoint("LEFT", addLabel, "RIGHT", 12, 0)
	addBox:SetAutoFocus(false)
	local addButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	addButton:SetSize(70, 22)
	addButton:SetPoint("LEFT", addBox, "RIGHT", 8, 0)
	addButton:SetText("Add")
	local addError = CreateLabel(page, "", "GameFontRedSmall")
	addError:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -6)

	local function Add()
		local message = module:AddSpell(addBox:GetText())
		addError:SetText(message or "")
		if not message then
			addBox:SetText("")
		end
		addBox:ClearFocus()
	end
	addButton:SetScript("OnClick", Add)
	addBox:SetScript("OnEnterPressed", Add)
	addBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)

	-- The tracked list: click a row to remove it.
	local listBox = CreateFrame("Frame", nil, page, "WowScrollBoxList")
	listBox:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -22)
	listBox:SetPoint("RIGHT", page, "RIGHT", -16, 0)
	listBox:SetHeight(ROW_HEIGHT * 6)
	local listBar = CreateFrame("EventFrame", nil, page, "MinimalScrollBar")
	listBar:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 4, 0)
	listBar:SetPoint("BOTTOMLEFT", listBox, "BOTTOMRIGHT", 4, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", InitializeListRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(listBox, listBar, view)
	self.listBox = listBox
	self.emptyText = CreateLabel(page, "Nothing tracked yet.", "GameFontDisable")
	self.emptyText:SetPoint("TOPLEFT", listBox, "TOPLEFT", 4, -4)

	local listAnchor = CreateFrame("Frame", nil, page)
	listAnchor:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 0, -4)
	listAnchor:SetSize(1, 1)

	local _, sizeLabel = CreateSlider(page, listAnchor, "Icon size", "size", { 16, 80, 64 })
	local _, gapLabel = CreateSlider(page, sizeLabel, "Gap", "spacing", { 0, 20, 20 })
	local _, textLabel = CreateSlider(page, gapLabel, "Text size", "textSize", { 6, 32, 26 })

	local swipeCheck = CreateCheck(page, "Cooldown swipe (off: only the time left as text)", self.db.showSwipe, function(checked)
		module.db.showSwipe = checked
		module:Apply()
	end)
	swipeCheck:SetPoint("TOPLEFT", textLabel, "BOTTOMLEFT", -4, -8)

	local growthLabel = CreateLabel(page, "Grows")
	growthLabel:SetPoint("TOPLEFT", swipeCheck, "BOTTOMLEFT", 4, -8)
	growthLabel:SetWidth(120)
	local growthDropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
	growthDropdown:SetPoint("LEFT", growthLabel, "RIGHT", 8, 0)
	growthDropdown:SetWidth(200)
	growthDropdown:SetupMenu(function(_, rootDescription)
		local function IsSelected(key)
			return module.db.growth == key
		end
		local function SetSelected(key)
			module.db.growth = key
			module:Apply()
		end
		for _, growth in ipairs(GROWTH) do
			rootDescription:CreateRadio(growth.name, IsSelected, SetSelected, growth.key)
		end
	end)

	self:UpdateList()
end

function TrackedBuffs:OnPageShown(page)
	-- Spell names can come in after the first look-up.
	self:UpdateList()
end
