local addonName, ns = ...

-- Main hand, off hand and ranged swing timers, looking like the cast bars (no icon):
-- "MH" / "OH" / "R" on the left, the time to the next swing on the right. Three
-- separate bars, each with its own size and place, moved like the separated player
-- cast bar (Unlock frames, the Layout page).
--
-- WoW Forever only: the client has a swing timer API (C_SwingTimer, PLAYER_SWING),
-- retail doesn't. PLAYER_SWING gives the time until the next swing of a hand; the bar
-- fills over that time. Like Blizzard's own swing timers (Blizzard_SwingTimer, which
-- this follows): a bar only shows with a weapon in that slot, follows weapon swaps, and
-- dims while the target is out of range.
--
-- Background (opacity and colour) and bar texture are their own settings, shared by the
-- three bars; the border thickness follows the Unit Frames setting, the font the Fonts
-- page.

local SwingTimers = ns:RegisterModule("SwingTimers", {
	title = "Swing Timers",
	order = 26.5,
	defaults = {
		enabled = true,
		onlyInCombat = true,
		showTime = true,
		hideBlizzard = true,
		textSize = 11,
		backgroundOpacity = 40,          -- percent
		backgroundColor = { 0, 0, 0 },
		barTexture = "melli",            -- key from the Unit Frames texture list, or shared media
		bars = {
			-- position: { x, y } centre from the screen centre
			mainhand = { show = true, color = { 0.95, 0.75, 0.3 }, width = 220, height = 14, position = { 0, -220 } },
			offhand = { show = true, color = { 0.6, 0.65, 1 }, width = 220, height = 14, position = { 0, -240 } },
			ranged = { show = true, color = { 0.45, 0.85, 0.45 }, width = 220, height = 14, position = { 0, -260 } },
		},
	},
})

local AVAILABLE = C_SwingTimer ~= nil and Enum.PlayerSwingType ~= nil

local BARS = {
	{ key = "mainhand", label = "MH", name = "Main hand", swingType = "MainHand", blizzard = "SwingTimerMainHandFrame" },
	{ key = "offhand", label = "OH", name = "Off hand", swingType = "OffHand", blizzard = "SwingTimerOffHandFrame" },
	{ key = "ranged", label = "R", name = "Ranged", swingType = "Ranged", blizzard = "SwingTimerRangedFrame" },
}

local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local OUT_OF_RANGE_ALPHA = 0.4

local bars = {} -- [key] = bar frame
local blizzardHooked = false

local function IsUnlocked()
	return ns.IsUnlocked ~= nil and ns.IsUnlocked()
end

local function GetUnitFrameSettings()
	local unitFrames = ns:GetModule("UnitFrames")
	return unitFrames and unitFrames.db
end

local function GetBarSettings(bar)
	return SwingTimers.db.bars[bar.info.key]
end

---------------------------------------------------------------------------
-- Weapons and visibility
---------------------------------------------------------------------------

local function HasWeapon(bar)
	local _, offHandSpeed, rangedSpeed = UnitAttackSpeed("player")
	if bar.info.key == "offhand" then
		return offHandSpeed ~= nil and offHandSpeed > 0
	elseif bar.info.key == "ranged" then
		return rangedSpeed ~= nil and rangedSpeed > 0
	end
	return true
end

local function GetEquippedSpeed(bar)
	local mainHandSpeed, offHandSpeed, rangedSpeed = UnitAttackSpeed("player")
	if bar.info.key == "offhand" then
		return offHandSpeed
	elseif bar.info.key == "ranged" then
		return rangedSpeed
	end
	return mainHandSpeed
end

-- Switched on (feature and bar).
local function IsBarOn(bar)
	return AVAILABLE and SwingTimers.db.enabled and GetBarSettings(bar).show
end

-- Switched on and with a weapon in its slot.
local function IsBarActive(bar)
	return IsBarOn(bar) and HasWeapon(bar)
end

-- While unlocked, every switched-on bar shows (as a sample) so it can be placed,
-- weapon or not. Otherwise: in combat (or always), or while a swing is running.
local function ShouldShow(bar)
	if not IsBarOn(bar) then
		return false
	end
	if IsUnlocked() then
		return true
	end
	if not HasWeapon(bar) then
		return false
	end
	if bar.endTime then
		return true
	end
	return not SwingTimers.db.onlyInCombat or UnitAffectingCombat("player")
end

---------------------------------------------------------------------------
-- One bar
---------------------------------------------------------------------------

local function ApplyRangeLook(bar)
	-- Like Blizzard's: a running swing isn't dimmed.
	local outOfRange = bar.outOfRange and not bar.endTime and not IsUnlocked()
	bar:SetAlpha(outOfRange and OUT_OF_RANGE_ALPHA or 1)
	local r, g, b = 1, 1, 1
	if outOfRange then
		r, g, b = 1, 0.2, 0.2
	end
	bar.LabelText:SetTextColor(r, g, b)
	bar.TimeText:SetTextColor(r, g, b)
end

local function ClearSwing(bar)
	bar.duration, bar.endTime = nil, nil
	bar.Bar:SetValue(0)
	bar.TimeText:SetText("0.0")
	ApplyRangeLook(bar)
end

local function StartSwing(bar, duration)
	if not duration or duration <= 0 then
		return
	end
	bar.duration = duration
	bar.endTime = GetTime() + duration
	bar.Bar:SetValue(0)
	bar.TimeText:SetFormattedText("%.1f", duration)
	ApplyRangeLook(bar)
end

local function UpdateShown(bar)
	bar:SetShown(ShouldShow(bar))
	if IsUnlocked() and not bar.endTime then
		-- A sample, to see it while placing it.
		bar.Bar:SetValue(0.6)
		bar.TimeText:SetText("1.4")
	end
	ApplyRangeLook(bar)
end

local function OnBarUpdate(bar)
	if not bar.endTime then
		return
	end
	local remaining = bar.endTime - GetTime()
	if remaining <= 0 then
		ClearSwing(bar)
		UpdateShown(bar)
		return
	end
	bar.Bar:SetValue((bar.duration - remaining) / bar.duration)
	bar.TimeText:SetFormattedText("%.1f", remaining)
end

local function CreateLine(parent)
	local line = parent:CreateTexture(nil, "OVERLAY", nil, 7)
	line:SetColorTexture(0, 0, 0, 1)
	line:SetSnapToPixelGrid(false)
	line:SetTexelSnappingBias(0)
	return line
end

local function CreateBar(info)
	local bar = CreateFrame("Frame", nil, UIParent)
	bar.info = info
	bar:SetFrameStrata("MEDIUM")
	bar:SetClampedToScreen(true)
	bar:SetMovable(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function(self)
		if IsUnlocked() then
			self:StartMoving()
			self.moving = true
		end
	end)
	bar:SetScript("OnDragStop", function(self)
		if not self.moving then
			return
		end
		self.moving = false
		self:StopMovingOrSizing()
		ns.MoverDropped("swing" .. info.key) -- snaps and saves
	end)

	bar.Background = bar:CreateTexture(nil, "BACKGROUND")
	bar.Background:SetAllPoints()

	bar.Bar = CreateFrame("StatusBar", nil, bar)
	bar.Bar:SetMinMaxValues(0, 1)

	local borderFrame = CreateFrame("Frame", nil, bar)
	borderFrame:SetAllPoints()
	borderFrame:SetFrameLevel(bar.Bar:GetFrameLevel() + 1)
	bar.Border = {
		TOP = CreateLine(borderFrame),
		BOTTOM = CreateLine(borderFrame),
		LEFT = CreateLine(borderFrame),
		RIGHT = CreateLine(borderFrame),
	}

	local textLayer = CreateFrame("Frame", nil, bar)
	textLayer:SetAllPoints()
	textLayer:SetFrameLevel(borderFrame:GetFrameLevel() + 1)
	bar.LabelText = textLayer:CreateFontString(nil, "OVERLAY")
	bar.LabelText:SetJustifyH("LEFT")
	bar.LabelText:SetText(info.label)
	bar.TimeText = textLayer:CreateFontString(nil, "OVERLAY")
	bar.TimeText:SetJustifyH("RIGHT")

	bar:SetScript("OnUpdate", OnBarUpdate)
	bar:Hide()
	return bar
end

local function PlaceBar(bar)
	local position = GetBarSettings(bar).position
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", UIParent, "CENTER", position[1], position[2])
end

local function LayoutBar(bar)
	local db = SwingTimers.db
	local settings = GetBarSettings(bar)
	local unitFrames = GetUnitFrameSettings()
	local fontPath, outline = ns.GetFont()
	local borderSize = unitFrames and unitFrames.borderSize or 1
	local border = borderSize > 0 and PixelUtil.GetNearestPixelSize(borderSize, bar:GetEffectiveScale(), 1) or 0

	bar:SetSize(settings.width, settings.height)
	PlaceBar(bar)
	bar:EnableMouse(IsUnlocked()) -- never in the way of clicks while locked
	local background = db.backgroundColor
	bar.Background:SetColorTexture(background[1], background[2], background[3], db.backgroundOpacity / 100)

	local lines = bar.Border
	lines.TOP:ClearAllPoints()
	lines.TOP:SetPoint("TOPLEFT")
	lines.TOP:SetPoint("TOPRIGHT")
	lines.TOP:SetHeight(border)
	lines.BOTTOM:ClearAllPoints()
	lines.BOTTOM:SetPoint("BOTTOMLEFT")
	lines.BOTTOM:SetPoint("BOTTOMRIGHT")
	lines.BOTTOM:SetHeight(border)
	lines.LEFT:ClearAllPoints()
	lines.LEFT:SetPoint("TOPLEFT")
	lines.LEFT:SetPoint("BOTTOMLEFT")
	lines.LEFT:SetWidth(border)
	lines.RIGHT:ClearAllPoints()
	lines.RIGHT:SetPoint("TOPRIGHT")
	lines.RIGHT:SetPoint("BOTTOMRIGHT")
	lines.RIGHT:SetWidth(border)
	for _, line in pairs(lines) do
		line:SetShown(border > 0)
	end

	bar.Bar:ClearAllPoints()
	bar.Bar:SetPoint("TOPLEFT", border, -border)
	bar.Bar:SetPoint("BOTTOMRIGHT", -border, border)
	if ns.GetBarTexturePath then
		bar.Bar:SetStatusBarTexture(ns.GetBarTexturePath(db.barTexture))
	end
	local color = settings.color
	bar.Bar:SetStatusBarColor(color[1], color[2], color[3])

	bar.LabelText:ClearAllPoints()
	bar.LabelText:SetPoint("LEFT", bar.Bar, "LEFT", 3, 0)
	bar.LabelText:SetFont(fontPath or DEFAULT_FONT, db.textSize, outline)
	bar.TimeText:ClearAllPoints()
	bar.TimeText:SetPoint("RIGHT", bar.Bar, "RIGHT", -3, 0)
	bar.TimeText:SetFont(fontPath or DEFAULT_FONT, db.textSize, outline)
	bar.TimeText:SetShown(db.showTime)
end

---------------------------------------------------------------------------
-- All bars
---------------------------------------------------------------------------

local function UpdateRangeChecks()
	if not AVAILABLE then
		return
	end
	for _, info in ipairs(BARS) do
		local bar = bars[info.key]
		local check = IsBarActive(bar) == true
		if bar.rangeCheck ~= check then
			bar.rangeCheck = check
			C_SwingTimer.EnableRangeCheck(Enum.PlayerSwingType[info.swingType], check)
		end
		if check then
			local inRange = C_SwingTimer.IsTargetWithinSwingRange(Enum.PlayerSwingType[info.swingType])
			bar.outOfRange = inRange == false -- nil means "couldn't check", not out of range
		else
			bar.outOfRange = false
		end
	end
end

-- Blizzard's own swing timers: kept hidden while ours are on (they show themselves
-- again on their own events, so their OnShow hides them again; not in Edit Mode).
local function UpdateBlizzardBars()
	local hide = AVAILABLE and SwingTimers.db.enabled and SwingTimers.db.hideBlizzard
	for _, info in ipairs(BARS) do
		local blizzard = _G[info.blizzard]
		if blizzard then
			if not blizzardHooked then
				blizzard:HookScript("OnShow", function(self)
					local db = SwingTimers.db
					if db and db.enabled and db.hideBlizzard and not self.isInEditMode then
						self:Hide()
					end
				end)
			end
			if hide then
				if not blizzard.isInEditMode then
					blizzard:Hide()
				end
			elseif blizzard.UpdateShownState then
				blizzard:UpdateShownState()
			end
		end
	end
	blizzardHooked = true
end

function SwingTimers:Apply()
	if not next(bars) then
		for _, info in ipairs(BARS) do
			bars[info.key] = CreateBar(info)
		end
	end
	for _, info in ipairs(BARS) do
		local bar = bars[info.key]
		LayoutBar(bar)
		if not IsBarActive(bar) then
			ClearSwing(bar)
		end
	end
	UpdateRangeChecks()
	for _, bar in pairs(bars) do
		UpdateShown(bar)
	end
	UpdateBlizzardBars()
end

local function UpdateAllShown()
	for _, bar in pairs(bars) do
		UpdateShown(bar)
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- Left over from the first version, where the bars shared one size and one place.
function SwingTimers:OnInit()
	self.db.width, self.db.height, self.db.gap, self.db.position = nil, nil, nil, nil
end

function SwingTimers:OnLogin()
	self:Apply()
end

function SwingTimers:OnSwing(event, duration, swingType)
	for _, info in ipairs(BARS) do
		local bar = bars[info.key]
		if bar and Enum.PlayerSwingType[info.swingType] == swingType and IsBarActive(bar) then
			StartSwing(bar, duration)
			UpdateShown(bar)
		end
	end
end

-- Weapon swaps (no payload) and attack speed changes (unit): a running swing is
-- re-timed to the new weapon, as Blizzard does on a swap.
function SwingTimers:OnWeaponsChanged(event, unit)
	if unit and unit ~= "player" then
		return
	end
	if event == "WEAPON_SLOT_CHANGED" then
		for _, bar in pairs(bars) do
			if bar.endTime and IsBarActive(bar) then
				StartSwing(bar, GetEquippedSpeed(bar))
			end
		end
	end
	self:Apply()
end

function SwingTimers:OnRangeUpdate(event, swingType, isInRange, checksRange)
	for _, info in ipairs(BARS) do
		local bar = bars[info.key]
		if bar and Enum.PlayerSwingType[info.swingType] == swingType then
			bar.outOfRange = checksRange and not isInRange
			ApplyRangeLook(bar)
		end
	end
end

function SwingTimers:OnTargetChanged()
	if next(bars) then
		UpdateRangeChecks()
		UpdateAllShown()
	end
end

function SwingTimers:OnCombatChanged()
	UpdateAllShown()
end

-- The Unlock frames checkbox: the bars show as samples and take the mouse.
function SwingTimers:OnUnlockChanged()
	self:Apply()
end

function SwingTimers:OnFontChanged()
	self:Apply()
end

-- Retail doesn't know these events (registering an unknown one is an error).
if AVAILABLE then
	SwingTimers:RegisterEvent("PLAYER_SWING", "OnSwing")
	SwingTimers:RegisterEvent("PLAYER_SWING_RANGE_UPDATE", "OnRangeUpdate")
	SwingTimers:RegisterEvent("WEAPON_SLOT_CHANGED", "OnWeaponsChanged")
	SwingTimers:RegisterEvent("UNIT_ATTACK_SPEED", "OnWeaponsChanged")
	SwingTimers:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
	SwingTimers:RegisterEvent("PLAYER_IN_COMBAT_CHANGED", "OnCombatChanged")
	SwingTimers:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatChanged")
	SwingTimers:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatChanged")
end

-- One mover per bar.
if ns.RegisterMover then
	for _, info in ipairs(BARS) do
		ns:RegisterMover("swing" .. info.key, {
			title = info.name .. " swing",
			getFrame = function()
				local bar = bars[info.key]
				if bar and IsBarOn(bar) then
					return bar
				end
			end,
			save = function(x, y)
				SwingTimers.db.bars[info.key].position = { x, y }
				if bars[info.key] then
					PlaceBar(bars[info.key])
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

-- range = { min, max, steps }; settings is the table the key lives in.
local function CreateSlider(parent, anchor, labelText, settings, key, range)
	local label = CreateLabel(parent, labelText)
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
	label:SetWidth(120)

	local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("LEFT", label, "RIGHT", 8, 0)
	slider:SetSize(200, 20)
	slider:Init(settings[key], range[1], range[2], range[3], {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(value)
			return string.format("%d", value)
		end,
	})
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		value = math.floor(value + 0.5)
		if settings[key] ~= value then
			settings[key] = value
			SwingTimers:Apply()
		end
	end, slider)
	ns.MakeSliderEditable(slider)
	return slider, label
end

-- A colour picker for settings[key] (an { r, g, b }); the bars change while you drag.
local function CreateColorSwatch(parent, settings, key, tooltipTitle)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetSize(18, 18)
	local edge = swatch:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0.5, 0.5, 0.5, 1) -- grey, so a black colour still shows
	local colorTexture = swatch:CreateTexture(nil, "ARTWORK")
	colorTexture:SetPoint("TOPLEFT", 1, -1)
	colorTexture:SetPoint("BOTTOMRIGHT", -1, 1)

	local function Update()
		local color = settings[key]
		colorTexture:SetColorTexture(color[1], color[2], color[3])
	end
	local function SetColor(r, g, b)
		settings[key] = { r, g, b }
		SwingTimers:Apply()
		Update()
	end

	swatch:SetScript("OnClick", function()
		local old = settings[key]
		local r, g, b = old[1], old[2], old[3]
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r,
			g = g,
			b = b,
			swatchFunc = function()
				SetColor(ColorPickerFrame:GetColorRGB())
			end,
			cancelFunc = function()
				SetColor(r, g, b)
			end,
		})
	end)
	swatch:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(tooltipTitle)
		GameTooltip:AddLine("Click to change.", 1, 1, 1)
		GameTooltip:Show()
	end)
	swatch:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	Update()
	return swatch
end

function SwingTimers:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Swing Timers", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)
	local introText = "Three separate bars, each with its own size, colour and place: move them with "
		.. "|cffffd100Unlock frames|r or on the Layout page. The border thickness follows the Unit Frames "
		.. "setting, the font the Fonts page. A bar shows only with a weapon in that slot."
	if not AVAILABLE then
		introText = "|cffff5050This client has no swing timer API: swing timers only work in WoW Forever.|r " .. introText
	end
	local intro = CreateLabel(page, introText, "GameFontDisableSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local enableCheck = CreateCheck(page, "Show swing timers", self.db.enabled, function(checked)
		module.db.enabled = checked
		module:Apply()
	end)
	enableCheck:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -4, -6)

	local combatCheck = CreateCheck(page, "Only in combat", self.db.onlyInCombat, function(checked)
		module.db.onlyInCombat = checked
		module:Apply()
	end)
	combatCheck:SetPoint("LEFT", enableCheck, "LEFT", 220, 0)

	local timeCheck = CreateCheck(page, "Show the time left", self.db.showTime, function(checked)
		module.db.showTime = checked
		module:Apply()
	end)
	timeCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, 2)

	local blizzardCheck = CreateCheck(page, "Hide Blizzard's swing timers", self.db.hideBlizzard, function(checked)
		module.db.hideBlizzard = checked
		module:Apply()
	end)
	blizzardCheck:SetPoint("LEFT", timeCheck, "LEFT", 220, 0)

	local sliderAnchor = CreateFrame("Frame", nil, page)
	sliderAnchor:SetPoint("TOPLEFT", timeCheck, "BOTTOMLEFT", 4, 0)
	sliderAnchor:SetSize(1, 1)
	local _, textSizeLabel = CreateSlider(page, sliderAnchor, "Text size", self.db, "textSize", { 6, 24, 18 })

	-- Background and bar texture, as on the power bar; shared by the three bars.
	local _, opacityLabel = CreateSlider(page, textSizeLabel, "Background opacity", self.db, "backgroundOpacity", { 0, 100, 100 })
	local backgroundLabel = CreateLabel(page, "Background colour")
	backgroundLabel:SetPoint("TOPLEFT", opacityLabel, "BOTTOMLEFT", 0, -12)
	backgroundLabel:SetWidth(120)
	local backgroundSwatch = CreateColorSwatch(page, self.db, "backgroundColor", "Background colour")
	backgroundSwatch:SetPoint("LEFT", backgroundLabel, "RIGHT", 8, 0)

	local textureLabel = CreateLabel(page, "Bar texture")
	textureLabel:SetPoint("TOPLEFT", backgroundLabel, "BOTTOMLEFT", 0, -14)
	textureLabel:SetWidth(120)
	local textureDropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
	textureDropdown:SetPoint("LEFT", textureLabel, "RIGHT", 8, 0)
	textureDropdown:SetWidth(200)
	textureDropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetScrollMode(300)
		local function IsSelected(key)
			return module.db.barTexture == key
		end
		local function SetSelected(key)
			module.db.barTexture = key
			module:Apply()
		end
		for _, texture in ipairs(ns.BarTextures or {}) do
			rootDescription:CreateRadio(texture.name, IsSelected, SetSelected, texture.key)
		end
		local media = LibStub and LibStub("LibSharedMedia-3.0", true)
		if media then
			rootDescription:CreateDivider()
			rootDescription:CreateTitle("Shared media")
			for _, name in ipairs(media:List("statusbar")) do
				rootDescription:CreateRadio(name, IsSelected, SetSelected, name)
			end
		end
	end)
	self.textureDropdown = textureDropdown
	local previous = textureLabel

	-- Per bar: on/off with its colour, then its own width and height.
	for _, info in ipairs(BARS) do
		local settings = self.db.bars[info.key]
		local check = CreateCheck(page, info.name .. " (" .. info.label .. ")", settings.show, function(checked)
			settings.show = checked
			module:Apply()
		end)
		check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", -4, -10)
		local swatch = CreateColorSwatch(page, settings, "color", info.name .. " colour")
		swatch:SetPoint("LEFT", check, "LEFT", 220, 0)
		local checkAnchor = CreateFrame("Frame", nil, page)
		checkAnchor:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 4, 4)
		checkAnchor:SetSize(1, 1)
		local _, widthLabel = CreateSlider(page, checkAnchor, "Width", settings, "width", { 40, 500, 460 })
		local _, heightLabel = CreateSlider(page, widthLabel, "Height", settings, "height", { 4, 40, 36 })
		previous = heightLabel
	end
end

function SwingTimers:OnPageShown(page)
	-- The Unit Frames border thickness may have changed meanwhile.
	self:Apply()
	-- The shared media list can grow after login.
	self.textureDropdown:GenerateMenu()
end
