local addonName, ns = ...

-- The player's buffs and debuffs, styled like the target's (UnitFrames shares its aura
-- button setup): square icons with a 1 px border, debuff borders coloured by dispel
-- type, time left and stack count in the addon's font. Right-click cancels a buff
-- (Blizzard's aura button does that itself, so it works in combat); hovering shows
-- Blizzard's tooltip. Weapon enchants (poisons, oils) come first among the buffs.
--
-- Each group hangs off a handle the size of its first two rows. The handle is what
-- Unlock frames moves (an empty group has no size to grab) and is only visible while
-- unlocked. Blizzard's BuffFrame and DebuffFrame are hidden while this is on; they
-- contain secure buttons, so that's done out of combat.

local PlayerAuras = ns:RegisterModule("PlayerAuras", {
	title = "Player Buffs",
	order = 22.65,
	navParent = "UnitFrames", -- listed under Unit Frames in the window
	defaults = {
		enabled = true,
		weaponEnchants = true,
		spacing = 3,
		buffShow = true,
		buffSize = 30,
		buffTextSize = 11,
		buffPerRow = 12,
		buffMax = 32,
		buffGrowth = "leftdown", -- key in GROWTH
		buffPosition = nil,      -- { x, y } handle centre from the screen centre; nil = default
		debuffShow = true,
		debuffSize = 36,
		debuffTextSize = 12,
		debuffPerRow = 8,
		debuffMax = 16,
		debuffGrowth = "leftdown",
		debuffPosition = nil,
	},
})

local MAX_AURAS = 40

local GROUPS = {
	{ key = "buffs", prefix = "buff", filter = "HELPFUL", title = "Player buffs",
		defaultAnchor = { "TOPRIGHT", "TOPRIGHT", -220, -14 } },
	{ key = "debuffs", prefix = "debuff", filter = "HARMFUL", title = "Player debuffs",
		defaultAnchor = { "TOPRIGHT", "TOPRIGHT", -220, -120 } },
}

-- Which corner the icons start in and which way they grow.
local GROWTH = {
	{ key = "leftdown", name = "Left and down", corner = "TOPRIGHT", horizontal = "Left", vertical = "Down" },
	{ key = "rightdown", name = "Right and down", corner = "TOPLEFT", horizontal = "Right", vertical = "Down" },
	{ key = "leftup", name = "Left and up", corner = "BOTTOMRIGHT", horizontal = "Left", vertical = "Up" },
	{ key = "rightup", name = "Right and up", corner = "BOTTOMLEFT", horizontal = "Right", vertical = "Up" },
}

local BLIZZARD_FRAMES = { "BuffFrame", "DebuffFrame" }

local containers = {} -- [group key] = aura container
local handles = {}    -- [group key] = handle frame
local texts = {}      -- [group key] = { font strings }, for text size changes
local blizzardParents = {}
local pendingApply = false

local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

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

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function CreateHandle(group)
	local handle = CreateFrame("Frame", nil, UIParent)
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
		ns.MoverDropped("player" .. group.key) -- snaps and saves
	end)

	-- Only drawn while unlocked.
	handle.Background = handle:CreateTexture(nil, "BACKGROUND")
	handle.Background:SetAllPoints()
	handle.Background:SetColorTexture(0.2, 0.6, 1, 0.25)
	handle.Label = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	handle.Label:SetPoint("CENTER")
	handle.Label:SetText(group.title)
	return handle
end

local function CreateContainer(group, handle)
	local auras = CreateFrame("AuraContainer", nil, handle, "CustomAuraContainerTemplate")
	local groupTexts = {}
	texts[group.key] = groupTexts

	local function Initialize(button)
		local db = PlayerAuras.db
		ns.InitializeAuraButton(button, db[group.prefix .. "Size"], db[group.prefix .. "TextSize"], groupTexts)
		button:SetTooltipAnchorPoint("ANCHOR_BOTTOMLEFT")
		if group.key == "buffs" then
			button:SetCancelAuraButtons("RightButtonUp")
		end
	end

	auras:AddAuraGroup("auras", group.filter, {
		maxFrameCount = MAX_AURAS,
		initializeFrame = Initialize,
	})
	if group.key == "buffs" then
		-- Weapon enchants first, as on Blizzard's buff frame.
		for _, slot in ipairs({ AuraContainerItemEnchantmentSlot.MainHand, AuraContainerItemEnchantmentSlot.OffHand }) do
			auras:AddItemEnchantment(slot, { initializeFrame = Initialize })
		end
		auras:SetItemEnchantmentLayout({ placement = CustomAuraContainerItemEnchantmentPlacement.BeforeAuraGroups })
	end
	auras:SetUnit("player")
	return auras
end

local function Build()
	for _, group in ipairs(GROUPS) do
		local handle = CreateHandle(group)
		handles[group.key] = handle
		containers[group.key] = CreateContainer(group, handle)
	end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function PlaceHandle(group)
	local handle = handles[group.key]
	local position = PlayerAuras.db[group.prefix .. "Position"]
	handle:ClearAllPoints()
	if position then
		handle:SetPoint("CENTER", UIParent, "CENTER", position[1], position[2])
	else
		local anchor = group.defaultAnchor
		handle:SetPoint(anchor[1], UIParent, anchor[2], anchor[3], anchor[4])
	end
end

local function LayoutGroup(group)
	local db = PlayerAuras.db
	local prefix = group.prefix
	local handle, auras = handles[group.key], containers[group.key]
	local size, spacing = db[prefix .. "Size"], db.spacing
	local perRow = db[prefix .. "PerRow"]
	local shown = PlayerAuras.db.enabled and db[prefix .. "Show"]
	local rowWidth = perRow * size + (perRow - 1) * spacing

	-- The handle: the first two rows' area. The icons start in its growth corner.
	handle:SetSize(rowWidth, 2 * size + spacing)
	PlaceHandle(group)
	handle:SetShown(shown)
	local unlocked = IsUnlocked()
	handle:EnableMouse(unlocked)
	handle.Background:SetShown(unlocked)
	handle.Label:SetShown(unlocked)

	local growth = GetGrowth(db[prefix .. "Growth"])
	auras:ClearAllPoints()
	auras:SetPoint(growth.corner, handle, growth.corner)
	auras:SetFlowLayoutAnchorPoint(growth.corner)
	auras:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection[growth.horizontal], AnchorUtil.FlowDirection[growth.vertical])
	auras:SetFlowLayoutMaximumLineSize(rowWidth)

	auras:SetAuraGroupEnabled("auras", shown == true)
	auras:SetAuraGroupMaxFrameCount("auras", db[prefix .. "Max"])
	local layout = {
		elementWidth = size,
		elementHeight = size,
		elementSpacing = spacing,
		lineSpacing = spacing,
	}
	auras:SetAuraGroupLayout("auras", layout)
	if group.key == "buffs" then
		auras:SetItemEnchantmentLayout({
			placement = CustomAuraContainerItemEnchantmentPlacement.BeforeAuraGroups,
			elementWidth = size,
			elementHeight = size,
			elementSpacing = spacing,
			lineSpacing = spacing,
		})
		for _, slot in ipairs({ AuraContainerItemEnchantmentSlot.MainHand, AuraContainerItemEnchantmentSlot.OffHand }) do
			auras:SetItemEnchantmentEnabled(slot, (shown and db.weaponEnchants) == true)
		end
	end

	ns.ResizeAuraButtons(auras, size)
	ns.SetAuraTextSize(texts[group.key], db[prefix .. "TextSize"])
end

---------------------------------------------------------------------------
-- Blizzard's buff and debuff frames
---------------------------------------------------------------------------

local function SetBlizzardHidden(hidden)
	for _, name in ipairs(BLIZZARD_FRAMES) do
		local blizzard = _G[name]
		if blizzard then
			if hidden and not blizzardParents[name] then
				blizzardParents[name] = blizzard:GetParent()
				blizzard:SetParent(hiddenParent)
			elseif not hidden and blizzardParents[name] then
				blizzard:SetParent(blizzardParents[name])
				blizzardParents[name] = nil
			end
		end
	end
end

---------------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------------

function PlayerAuras:Apply()
	if InCombatLockdown() then
		pendingApply = true
		return
	end
	pendingApply = false

	if not self.db.enabled and not next(handles) then
		return -- never built, nothing to undo
	end
	if not next(handles) then
		Build()
	end
	for _, group in ipairs(GROUPS) do
		-- On its own, so an error in one group doesn't stop the other.
		xpcall(function()
			LayoutGroup(group)
		end, geterrorhandler())
	end
	SetBlizzardHidden(self.db.enabled)
end

function PlayerAuras:OnLogin()
	self:Apply()
end

function PlayerAuras:OnCombatEnded()
	if pendingApply then
		self:Apply()
	end
end

-- The Unlock frames checkbox: the handles show and take the mouse.
function PlayerAuras:OnUnlockChanged()
	self:Apply()
end

function PlayerAuras:OnFontChanged()
	self:Apply()
end

PlayerAuras:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")

if ns.RegisterMover then
	for _, group in ipairs(GROUPS) do
		ns:RegisterMover("player" .. group.key, {
			title = group.title,
			getFrame = function()
				if PlayerAuras.db and PlayerAuras.db.enabled then
					return handles[group.key]
				end
			end,
			save = function(x, y)
				PlayerAuras.db[group.prefix .. "Position"] = { x, y }
				if handles[group.key] then
					PlaceHandle(group)
				end
			end,
		})
	end
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
	slider:Init(PlayerAuras.db[key], range[1], range[2], range[3], {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(value)
			return string.format("%d", value)
		end,
	})
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		value = math.floor(value + 0.5)
		if PlayerAuras.db[key] ~= value then
			PlayerAuras.db[key] = value
			PlayerAuras:Apply()
		end
	end, slider)
	ns.MakeSliderEditable(slider)
	return slider, label
end

local function CreateDropdown(parent, anchor, labelText, setup)
	local label = CreateLabel(parent, labelText)
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
	label:SetWidth(120)

	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)
	dropdown:SetWidth(200)
	dropdown:SetupMenu(function(_, rootDescription)
		setup(rootDescription)
	end)
	return dropdown, label
end

-- One group's settings; returns the last label to anchor the next below.
local function CreateGroupSection(page, anchor, group, titleText)
	local db = PlayerAuras.db
	local prefix = group.prefix

	local header = CreateLabel(page, titleText, "GameFontNormal")
	header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)

	local showCheck = CreateCheck(page, "Show", db[prefix .. "Show"], function(checked)
		db[prefix .. "Show"] = checked
		PlayerAuras:Apply()
	end)
	showCheck:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -4, -2)
	local checkAnchor = CreateFrame("Frame", nil, page)
	checkAnchor:SetPoint("TOPLEFT", showCheck, "BOTTOMLEFT", 4, 4)
	checkAnchor:SetSize(1, 1)

	local _, sizeLabel = CreateSlider(page, checkAnchor, "Icon size", prefix .. "Size", { 12, 60, 48 })
	local _, textLabel = CreateSlider(page, sizeLabel, "Text size", prefix .. "TextSize", { 6, 24, 18 })
	local _, rowLabel = CreateSlider(page, textLabel, "Per row", prefix .. "PerRow", { 1, 20, 19 })
	local _, maxLabel = CreateSlider(page, rowLabel, "Max shown", prefix .. "Max", { 1, MAX_AURAS, MAX_AURAS - 1 })
	local _, growthLabel = CreateDropdown(page, maxLabel, "Grows", function(rootDescription)
		local function IsSelected(key)
			return db[prefix .. "Growth"] == key
		end
		local function SetSelected(key)
			db[prefix .. "Growth"] = key
			PlayerAuras:Apply()
		end
		for _, growth in ipairs(GROWTH) do
			rootDescription:CreateRadio(growth.name, IsSelected, SetSelected, growth.key)
		end
	end)
	return growthLabel
end

function PlayerAuras:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Player Buffs & Debuffs", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)
	local intro = CreateLabel(page, "Styled like the target's, replacing Blizzard's. Right-click a buff to cancel it. "
		.. "Move them with |cffffd100Unlock frames|r (the blue boxes) or on the Layout page.", "GameFontDisableSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	reset:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -2)
	reset:SetSize(120, 22)
	reset:SetText("Reset positions")
	reset:SetScript("OnClick", function()
		module.db.buffPosition = nil
		module.db.debuffPosition = nil
		module:Apply()
	end)

	local enableCheck = CreateCheck(page, "Use these instead of Blizzard's buffs and debuffs", self.db.enabled, function(checked)
		module.db.enabled = checked
		module:Apply()
		if InCombatLockdown() then
			module:Print("in combat; the change is applied when combat ends.")
		end
	end)
	enableCheck:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -4, -6)

	local enchantCheck = CreateCheck(page, "Weapon enchants (poisons, oils) first among the buffs", self.db.weaponEnchants, function(checked)
		module.db.weaponEnchants = checked
		module:Apply()
	end)
	enchantCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, 2)

	local checkAnchor = CreateFrame("Frame", nil, page)
	checkAnchor:SetPoint("TOPLEFT", enchantCheck, "BOTTOMLEFT", 4, 4)
	checkAnchor:SetSize(1, 1)
	local _, spacingLabel = CreateSlider(page, checkAnchor, "Spacing", "spacing", { 0, 10, 10 })

	local buffsEnd = CreateGroupSection(page, spacingLabel, GROUPS[1], "Buffs")
	CreateGroupSection(page, buffsEnd, GROUPS[2], "Debuffs")
end
