local addonName, ns = ...

-- Missing buffs: the opposite of Tracked Buffs. Buffs from a list of spells (Thorns, an
-- armor, a weapon buff...) that you should have up; each one that's missing shows as a
-- blinking icon somewhere you choose, until you put it back up.
--
-- Checking: by spell ID (C_UnitAuras.GetPlayerAuraBySpellID), then by the spell's name
-- (GetAuraDataBySpellName), so any rank of a spell counts. Both need the aura not to be
-- secret ("RequiresNonSecretAura"): while restrictions are on (combat, encounters,
-- challenge mode, PvP) they can return nothing for a buff that is up. So a spell whose
-- auras are secret right now (C_Secrets.ShouldSpellAuraBeSecret) isn't checked: it keeps
-- its last known state, and is checked again once it can be.
--
-- The icons hang off a handle (one icon in size) that Unlock frames moves; it's only
-- visible while unlocked, and then every listed buff shows as a sample.

local MissingBuffs = ns:RegisterModule("MissingBuffs", {
	title = "Missing Buffs",
	order = 27.5,
	defaults = {
		enabled = true,
		spells = {},          -- spell IDs, in the order they were added
		size = 40,
		spacing = 4,
		blinkSpeed = 5,       -- tenths of a second per fade (out, then in)
		minAlpha = 20,        -- percent, the faintest point of a blink
		hideInCombat = false,
		growth = "center",    -- key in GROWTH
		position = nil,       -- { x, y } handle centre from the screen centre; nil = default
	},
})

local DEFAULT_POSITION = { 0, 120 }
local ROW_HEIGHT = 22
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON_CROP = 0.08

-- point: the point of each icon and of the handle the row starts from.
-- dx, dy: direction of the next icon. center: centred on the handle instead.
local GROWTH = {
	{ key = "center", name = "Centred row", point = "CENTER", dx = 1, dy = 0, center = true },
	{ key = "right", name = "To the right", point = "LEFT", dx = 1, dy = 0 },
	{ key = "left", name = "To the left", point = "RIGHT", dx = -1, dy = 0 },
	{ key = "down", name = "Downwards", point = "TOP", dx = 0, dy = -1 },
	{ key = "up", name = "Upwards", point = "BOTTOM", dx = 0, dy = 1 },
}

local handle
local icons = {}       -- pool of icon frames, reused in order
local known = {}       -- [spellID] = true (up) / false (missing); nil = never checked
local updatePending = false

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function IsUnlocked()
	return ns.IsUnlocked ~= nil and ns.IsUnlocked()
end

local function GetGrowth(key)
	for _, growth in ipairs(GROWTH) do
		if growth.key == key then
			return growth
		end
	end
	return GROWTH[1]
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
-- Checking
---------------------------------------------------------------------------

-- true: the buff is up. false: it's missing. nil: can't tell right now (secret).
local function CheckSpell(spellID)
	if C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
		local secret = C_Secrets.ShouldSpellAuraBeSecret(spellID)
		if IsSecret(secret) or secret then
			return nil
		end
	end
	if C_UnitAuras.GetPlayerAuraBySpellID(spellID) then
		return true
	end
	-- Another rank of the same spell has its own ID but the same name.
	local info = C_Spell.GetSpellInfo(spellID)
	if info and info.name and not IsSecret(info.name)
		and C_UnitAuras.GetAuraDataBySpellName("player", info.name, "HELPFUL") then
		return true
	end
	return false
end

local function IsPlayerDead()
	local dead = UnitIsDeadOrGhost("player")
	return not IsSecret(dead) and dead
end

local function IsPlayerInCombat()
	local inCombat = UnitAffectingCombat("player")
	return not IsSecret(inCombat) and inCombat
end

---------------------------------------------------------------------------
-- Building
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
		ns.MoverDropped("missingbuffs") -- snaps and saves
	end)
	handle.Background = handle:CreateTexture(nil, "BACKGROUND")
	handle.Background:SetAllPoints()
	handle.Background:SetColorTexture(1, 0.3, 0.2, 0.25)
	handle.Label = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	handle.Label:SetPoint("BOTTOM", handle, "TOP", 0, 2)
	handle.Label:SetText("Missing buffs")
end

-- A square icon with a 1 px black border that blinks (fades out and in) while shown.
-- Never takes the mouse, so it's never in the way of clicks.
local function CreateIcon()
	local icon = CreateFrame("Frame", nil, handle)
	icon:EnableMouse(false)
	icon.Background = icon:CreateTexture(nil, "BACKGROUND")
	icon.Background:SetAllPoints()
	icon.Background:SetColorTexture(0, 0, 0, 1)
	icon.Texture = icon:CreateTexture(nil, "ARTWORK")
	icon.Texture:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

	icon.Blink = icon:CreateAnimationGroup()
	icon.Blink:SetLooping("BOUNCE")
	icon.Fade = icon.Blink:CreateAnimation("Alpha")
	icon.Fade:SetFromAlpha(1)

	icon:Hide()
	return icon
end

local function GetIcon(index)
	if not icons[index] then
		icons[index] = CreateIcon()
	end
	return icons[index]
end

---------------------------------------------------------------------------
-- Layout and updating
---------------------------------------------------------------------------

local function PlaceHandle()
	local position = MissingBuffs.db.position or DEFAULT_POSITION
	handle:ClearAllPoints()
	handle:SetPoint("CENTER", UIParent, "CENTER", position[1], position[2])
end

local function LayoutIcon(icon)
	local db = MissingBuffs.db
	icon:SetSize(db.size, db.size)
	local inset = PixelUtil.GetNearestPixelSize(1, icon:GetEffectiveScale(), 1)
	icon.Texture:ClearAllPoints()
	icon.Texture:SetPoint("TOPLEFT", inset, -inset)
	icon.Texture:SetPoint("BOTTOMRIGHT", -inset, inset)

	local wasPlaying = icon.Blink:IsPlaying()
	icon.Blink:Stop()
	icon.Fade:SetToAlpha(db.minAlpha / 100)
	icon.Fade:SetDuration(db.blinkSpeed / 10)
	if wasPlaying then
		icon.Blink:Play()
	end
end

-- Icons 1..count placed from the handle in the chosen direction.
local function PlaceIcons(count)
	local db = MissingBuffs.db
	local growth = GetGrowth(db.growth)
	local step = db.size + db.spacing
	local start = 0
	if growth.center then
		start = -(count - 1) * step / 2
	end
	for index = 1, count do
		local offset = start + (index - 1) * step
		local icon = icons[index]
		icon:ClearAllPoints()
		icon:SetPoint(growth.point, handle, growth.point, offset * growth.dx, offset * growth.dy)
	end
end

local function Update()
	updatePending = false
	if not handle then
		return
	end
	local db = MissingBuffs.db
	local preview = IsUnlocked()

	local shown = {}
	for _, spellID in ipairs(db.spells) do
		local state = CheckSpell(spellID)
		if state ~= nil then
			known[spellID] = state
		end
		if preview or known[spellID] == false then
			table.insert(shown, spellID)
		end
	end

	local hidden = not preview and (not db.enabled or IsPlayerDead()
		or (db.hideInCombat and IsPlayerInCombat()))
	if hidden then
		shown = {}
	end

	for index, spellID in ipairs(shown) do
		local icon = GetIcon(index)
		local _, texture = GetSpellDisplay(spellID)
		icon.Texture:SetTexture(texture)
		if not icon.laidOut then
			LayoutIcon(icon)
			icon.laidOut = true
		end
		icon:Show()
		if not icon.Blink:IsPlaying() then
			icon.Blink:Play()
		end
	end
	for index = #shown + 1, #icons do
		icons[index].Blink:Stop()
		icons[index]:Hide()
	end
	PlaceIcons(#shown)
end

-- Aura events come in bursts (and for every unit); one check per frame is enough.
local function ScheduleUpdate()
	if updatePending or not handle then
		return
	end
	updatePending = true
	C_Timer.After(0, Update)
end

function MissingBuffs:Apply()
	if not handle then
		Build()
	end
	local db = self.db
	handle:SetSize(db.size, db.size)
	PlaceHandle()
	handle:SetShown(db.enabled or IsUnlocked())
	local unlocked = IsUnlocked()
	handle:EnableMouse(unlocked)
	handle.Background:SetShown(unlocked)
	handle.Label:SetShown(unlocked)
	for _, icon in ipairs(icons) do
		LayoutIcon(icon)
		icon.laidOut = true
	end
	Update()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

function MissingBuffs:OnLogin()
	self:Apply()
end

-- The unit can be secret while auras are restricted: then just check (it's cheap).
function MissingBuffs:OnUnitAura(event, unit)
	if IsSecret(unit) or unit == "player" then
		ScheduleUpdate()
	end
end

function MissingBuffs:OnStateChanged()
	ScheduleUpdate()
end

-- The Unlock frames checkbox: the handle shows with every listed buff as a sample.
function MissingBuffs:OnUnlockChanged()
	self:Apply()
end

MissingBuffs:RegisterEvent("UNIT_AURA", "OnUnitAura")
MissingBuffs:RegisterEvent("PLAYER_ENTERING_WORLD", "OnStateChanged")
MissingBuffs:RegisterEvent("PLAYER_REGEN_ENABLED", "OnStateChanged") -- restrictions lift: check again
MissingBuffs:RegisterEvent("PLAYER_REGEN_DISABLED", "OnStateChanged")
MissingBuffs:RegisterEvent("PLAYER_DEAD", "OnStateChanged")
MissingBuffs:RegisterEvent("PLAYER_ALIVE", "OnStateChanged")
MissingBuffs:RegisterEvent("PLAYER_UNGHOST", "OnStateChanged")

if ns.RegisterMover then
	ns:RegisterMover("missingbuffs", {
		title = "Missing buffs",
		getFrame = function()
			if MissingBuffs.db and MissingBuffs.db.enabled then
				return handle
			end
		end,
		save = function(x, y)
			MissingBuffs.db.position = { x, y }
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
function MissingBuffs:AddSpell(input)
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
	for _, listed in ipairs(self.db.spells) do
		if listed == spellID then
			return "That one is already on the list."
		end
	end
	table.insert(self.db.spells, spellID)
	self:Apply()
	self:UpdateList()
end

function MissingBuffs:RemoveSpell(spellID)
	for index, listed in ipairs(self.db.spells) do
		if listed == spellID then
			table.remove(self.db.spells, index)
			break
		end
	end
	known[spellID] = nil
	self:Apply()
	self:UpdateList()
end

function MissingBuffs:UpdateList()
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
		row.Icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

		row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
		row.Name:SetPoint("RIGHT", -4, 0)
		row.Name:SetJustifyH("LEFT")
		row.Name:SetWordWrap(false)

		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetSpellByID(self.spellID)
			GameTooltip:AddLine("Click to remove it from the list", 0.6, 0.8, 1)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		row:SetScript("OnClick", function(self)
			GameTooltip:Hide()
			MissingBuffs:RemoveSpell(self.spellID)
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

-- range = { min, max, steps }; format(value) gives the text on the right.
local function CreateSlider(parent, anchor, labelText, key, range, format)
	local label = CreateLabel(parent, labelText)
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
	label:SetWidth(120)

	local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("LEFT", label, "RIGHT", 8, 0)
	slider:SetSize(200, 20)
	slider:Init(MissingBuffs.db[key], range[1], range[2], range[3], {
		[MinimalSliderWithSteppersMixin.Label.Right] = format or function(value)
			return string.format("%d", value)
		end,
	})
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		value = math.floor(value + 0.5)
		if MissingBuffs.db[key] ~= value then
			MissingBuffs.db[key] = value
			MissingBuffs:Apply()
		end
	end, slider)
	ns.MakeSliderEditable(slider)
	return slider, label
end

function MissingBuffs:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Missing Buffs", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)
	local intro = CreateLabel(page, "Buffs you want to keep up. Each one on the list that you don't have blinks "
		.. "until you put it back up. Add a buff by its spell ID or by the name of a spell you know; any rank "
		.. "of the spell counts. In combat, encounters and PvP the game can hide your buffs from addons: a buff "
		.. "then keeps the state it had, and is checked again when it can be. "
		.. "Move the icons with |cffffd100Unlock frames|r or on the Layout page.", "GameFontDisableSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local enableCheck = CreateCheck(page, "Show missing buffs", self.db.enabled, function(checked)
		module.db.enabled = checked
		module:Apply()
	end)
	enableCheck:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -4, -6)

	local combatCheck = CreateCheck(page, "Hide in combat", self.db.hideInCombat, function(checked)
		module.db.hideInCombat = checked
		module:Apply()
	end)
	combatCheck:SetPoint("LEFT", enableCheck, "LEFT", 220, 0)

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

	-- The list: click a row to remove it.
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
	self.emptyText = CreateLabel(page, "Nothing on the list yet.", "GameFontDisable")
	self.emptyText:SetPoint("TOPLEFT", listBox, "TOPLEFT", 4, -4)

	local listAnchor = CreateFrame("Frame", nil, page)
	listAnchor:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 0, -4)
	listAnchor:SetSize(1, 1)

	local _, sizeLabel = CreateSlider(page, listAnchor, "Icon size", "size", { 16, 80, 64 })
	local _, gapLabel = CreateSlider(page, sizeLabel, "Gap", "spacing", { 0, 20, 20 })
	local _, speedLabel = CreateSlider(page, gapLabel, "Blink speed", "blinkSpeed", { 1, 20, 19 }, function(value)
		return string.format("%.1f s", value / 10)
	end)
	local _, alphaLabel = CreateSlider(page, speedLabel, "Faintest", "minAlpha", { 0, 90, 90 }, function(value)
		return string.format("%d%%", value)
	end)

	local growthLabel = CreateLabel(page, "Grows")
	growthLabel:SetPoint("TOPLEFT", alphaLabel, "BOTTOMLEFT", 0, -14)
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

function MissingBuffs:OnPageShown(page)
	-- Spell names can come in after the first look-up.
	self:UpdateList()
end
