local addonName, ns = ...

-- A movable bar showing the player's current power: whatever the default UI would show,
-- so mana for casters, energy in cat form, rage in bear form, and so on. Druids in cat or
-- bear form get a thin mana bar under it; rogues and cat-form druids a row of combo point
-- squares on top.
--
-- Combo points: in WoW Forever they belong to the target (GetComboPoints on "target"),
-- in retail to the player (UnitPower). Each square is its own status bar covering one
-- point, so the count fills them without ever being compared.
--
-- Power values can be secret in WoW Forever. They go straight into the bar and the font
-- string, which accept secrets, and are never compared or calculated with. The bar is a
-- plain (not secure) frame, so it updates and can be changed in combat.

local PowerBar = ns:RegisterModule("PowerBar", {
	title = "Power Bar",
	order = 25,
	defaults = {
		enabled = true,
		width = 220,
		height = 14,
		druidManaHeight = 4,     -- mana bar under the bar in cat/bear form; 0 = off
		comboHeight = 6,         -- combo point squares on top (rogue, cat form); 0 = off
		comboGap = 1,            -- space between the squares
		borderSize = 1,          -- black border, as on the unit frames; 0 = none
		backgroundOpacity = 50,  -- percent
		backgroundColor = { 0, 0, 0 },
		combatOpacity = 100,     -- percent, while in combat
		idleOpacity = 100,       -- percent, out of combat
		barTexture = "flat",     -- key from the Unit Frames texture list
		textMode = "percent",    -- "none", "value", "percent", "both"
		textSize = 11,
		textPosition = "center", -- key in TEXT_POSITIONS
		textX = 0,
		textY = 0,
		classColor = false,      -- class colour instead of the power colour
		colors = {},             -- [power token] = { r, g, b }; missing = Blizzard's colour
		position = nil,          -- { point, relativePoint, x, y }; nil = default
	},
	commands = {
		powerbar = {
			desc = "show or hide the power bar",
			func = function(module)
				module:SetEnabled(not module.db.enabled)
			end,
		},
	},
})

local DEFAULT_POSITION = { "CENTER", "CENTER", 0, -200 }
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local FALLBACK_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local TEXT_MODES = {
	{ key = "none", name = "No text" },
	{ key = "value", name = "Number" },
	{ key = "percent", name = "Percent" },
	{ key = "both", name = "Number and percent" },
}

-- Where the text sits. "above" and "below" go past the combo points and the druid mana
-- bar while those are shown.
local TEXT_POSITIONS = {
	{ key = "center", name = "Centre" },
	{ key = "left", name = "Left" },
	{ key = "right", name = "Right" },
	{ key = "above", name = "Above the bar" },
	{ key = "below", name = "Below the bar" },
}

-- Power types with their own colour picker on the page.
local COLOR_TYPES = {
	{ token = "MANA", name = "Mana" },
	{ token = "RAGE", name = "Rage" },
	{ token = "ENERGY", name = "Energy" },
	{ token = "COMBO_POINTS", name = "Combo" },
}

local IS_FOREVER = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
local MAX_COMBO_SQUARES = 10
local DEFAULT_COMBO_POINTS = 5 -- when the maximum can't be read

local frame

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- The addon's font (the Fonts page); Friz Quadrata for "Blizzard default".
local function GetFont()
	local path, outline = ns.GetFont()
	return path or DEFAULT_FONT, outline
end

local function GetTexturePath(key)
	if ns.GetBarTexturePath then
		return ns.GetBarTexturePath(key)
	end
	return FALLBACK_TEXTURE
end

-- Whole screen pixels, worked out the same way as the unit frames' border; 0 = none.
local function GetBorderSize()
	local size = PowerBar.db.borderSize
	if size <= 0 then
		return 0
	end
	return PixelUtil.GetNearestPixelSize(size, frame:GetEffectiveScale(), 1)
end

-- r, g, b, a for the backgrounds of the bar, the druid mana bar and the combo squares.
local function GetBackgroundColor()
	local db = PowerBar.db
	local color = db.backgroundColor
	return color[1], color[2], color[3], db.backgroundOpacity / 100
end

local function GetBarColor(powerType, powerToken)
	if PowerBar.db.classColor then
		local _, classFile = UnitClass("player")
		local color = classFile and not IsSecret(classFile) and C_ClassColor.GetClassColor(classFile)
		if color then
			return color:GetRGB()
		end
	end
	local custom = powerToken and PowerBar.db.colors[powerToken]
	if custom then
		return custom[1], custom[2], custom[3]
	end
	local color = (powerToken and PowerBarColor[powerToken]) or PowerBarColor[powerType]
	if color then
		return color.r, color.g, color.b
	end
	return 0, 0.55, 1
end

-- The picked colour for a power type, nil when it's Blizzard's. Shared with UnitFrames,
-- whose target power bar uses the same colours.
function ns.GetCustomPowerColor(token)
	local custom = PowerBar.db and token and PowerBar.db.colors[token]
	if custom then
		return custom[1], custom[2], custom[3]
	end
end

-- The colour a power type has right now: the picked one, or Blizzard's.
local function GetTypeColor(token)
	local custom = PowerBar.db.colors[token]
	if custom then
		return custom[1], custom[2], custom[3]
	end
	local color = PowerBarColor[token]
	if color then
		return color.r, color.g, color.b
	end
	return 1, 1, 1
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------

-- Druids in cat or bear form: mana shown in a thin bar under the main one.
local function ShouldShowDruidMana()
	if PowerBar.db.druidManaHeight <= 0 then
		return false
	end
	-- Shown on the player unit frame instead (the checkbox on the Class Resources page).
	if ns.IsDruidManaOnPlayerFrame and ns.IsDruidManaOnPlayerFrame() then
		return false
	end
	local _, classFile = UnitClass("player")
	if IsSecret(classFile) then
		return false
	end
	return classFile == "DRUID" and UnitPowerType("player") ~= Enum.PowerType.Mana
end

local function UpdateDruidMana(interpolation)
	if not frame.Mana:IsShown() then
		return
	end
	local mana = Enum.PowerType.Mana
	frame.Mana.Bar:SetMinMaxValues(0, UnitPowerMax("player", mana))
	frame.Mana.Bar:SetValue(UnitPower("player", mana), interpolation)
end

-- Rogues, and druids in cat form (the form with energy).
local function ShouldShowCombo()
	if PowerBar.db.comboHeight <= 0 then
		return false
	end
	local _, classFile = UnitClass("player")
	if IsSecret(classFile) then
		return false
	end
	if classFile == "ROGUE" then
		return true
	end
	return classFile == "DRUID" and UnitPowerType("player") == Enum.PowerType.Energy
end

local function GetMaxComboPoints()
	local maxPoints = UnitPowerMax("player", Enum.PowerType.ComboPoints)
	if not maxPoints or IsSecret(maxPoints) or maxPoints <= 0 then
		return DEFAULT_COMBO_POINTS
	end
	return math.min(maxPoints, MAX_COMBO_SQUARES)
end

-- May be secret; only passed to the squares.
local function GetComboPointCount()
	if IS_FOREVER then
		return GetComboPoints("player", "target")
	end
	return UnitPower("player", Enum.PowerType.ComboPoints)
end

local LayoutCombo, PositionText -- defined with the layout code

local function UpdateCombo()
	if not frame or not frame.Combo:IsShown() then
		return
	end
	local count = GetMaxComboPoints()
	if count ~= frame.Combo.count then
		LayoutCombo(count)
	end
	local points = GetComboPointCount()
	for index = 1, count do
		frame.Combo.Squares[index]:SetValue(points)
	end
end

-- smooth: glide to the new value (the engine animates it, so secret values work).
-- Not smooth: jump, used when the power type changes (shifting into cat or bear form).
local function UpdateValue(smooth)
	if not frame or not frame:IsShown() then
		return
	end

	local powerType = UnitPowerType("player")
	local interpolation = smooth and Enum.StatusBarInterpolation.ExponentialEaseOut
		or Enum.StatusBarInterpolation.Immediate
	-- Secret values: passed through, never compared.
	frame.Bar:SetMinMaxValues(0, UnitPowerMax("player", powerType))
	frame.Bar:SetValue(UnitPower("player", powerType), interpolation)
	UpdateDruidMana(interpolation)

	local mode = PowerBar.db.textMode
	if mode == "value" then
		frame.Text:SetText(AbbreviateLargeNumbers(UnitPower("player", powerType)))
	elseif mode == "percent" then
		frame.Text:SetFormattedText("%.0f%%", UnitPowerPercent("player", powerType, false, CurveConstants.ScaleTo100))
	elseif mode == "both" then
		frame.Text:SetFormattedText("%s  |  %.0f%%",
			AbbreviateLargeNumbers(UnitPower("player", powerType)),
			UnitPowerPercent("player", powerType, false, CurveConstants.ScaleTo100))
	else
		frame.Text:SetText("")
	end
end

-- The power type changes with shapeshift forms (cat: energy, bear: rage).
local function UpdatePowerType()
	if not frame then
		return
	end
	local powerType, powerToken = UnitPowerType("player")
	frame.Bar:SetStatusBarColor(GetBarColor(powerType, powerToken))
	frame.Mana:SetShown(ShouldShowDruidMana())
	frame.Mana.Bar:SetStatusBarColor(GetTypeColor("MANA"))
	frame.Combo:SetShown(ShouldShowCombo())
	for _, square in ipairs(frame.Combo.Squares) do
		square:SetStatusBarColor(GetTypeColor("COMBO_POINTS"))
	end
	PositionText() -- "above" and "below" depend on which extra bars are shown
	UpdateValue()
	UpdateCombo()
end

-- The window's Unlock frames checkbox (Features/Layout.lua).
local function IsUnlocked()
	return ns.IsUnlocked ~= nil and ns.IsUnlocked()
end

local function UpdateAlpha()
	if not frame then
		return
	end
	local db = PowerBar.db
	local opacity = UnitAffectingCombat("player") and db.combatOpacity or db.idleOpacity
	-- Always fully visible while unlocked, so it can be found and moved.
	if IsUnlocked() then
		opacity = 100
	end
	frame:SetAlpha(opacity / 100)
end

---------------------------------------------------------------------------
-- Building and layout
---------------------------------------------------------------------------

-- Called by Layout (dragging, snapping, the X/Y sliders) with the bar's centre offset
-- from the screen centre.
local function SetPosition(x, y)
	PowerBar.db.position = { "CENTER", "CENTER", x, y }
	if frame then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
	end
end

local function CreateLine(parent)
	local line = parent:CreateTexture(nil, "OVERLAY", nil, 7)
	line:SetColorTexture(0, 0, 0, 1)
	line:SetSnapToPixelGrid(false)
	line:SetTexelSnappingBias(0)
	return line
end

local function BuildFrame()
	frame = CreateFrame("Frame", "AdamAddonPowerBar", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if IsUnlocked() then
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
		ns.MoverDropped("powerbar") -- snaps and saves
	end)

	frame.Background = frame:CreateTexture(nil, "BACKGROUND")
	frame.Background:SetAllPoints()

	frame.Bar = CreateFrame("StatusBar", nil, frame)

	-- Border and text above the bar.
	frame.Overlay = CreateFrame("Frame", nil, frame)
	frame.Overlay:SetAllPoints()
	frame.Overlay:SetFrameLevel(frame.Bar:GetFrameLevel() + 2)

	frame.Border = {
		TOP = CreateLine(frame.Overlay),
		BOTTOM = CreateLine(frame.Overlay),
		LEFT = CreateLine(frame.Overlay),
		RIGHT = CreateLine(frame.Overlay),
	}

	frame.Text = frame.Overlay:CreateFontString(nil, "OVERLAY")
	frame.Text:SetWordWrap(false)

	-- Druid mana, attached under the bar. Its top edge is the main bar's bottom border,
	-- so it only draws its own left, right and bottom lines.
	local mana = CreateFrame("Frame", nil, frame)
	mana.Background = mana:CreateTexture(nil, "BACKGROUND")
	mana.Background:SetAllPoints()
	mana.Bar = CreateFrame("StatusBar", nil, mana)
	mana.Overlay = CreateFrame("Frame", nil, mana)
	mana.Overlay:SetAllPoints()
	mana.Overlay:SetFrameLevel(mana.Bar:GetFrameLevel() + 2)
	mana.Border = {
		BOTTOM = CreateLine(mana.Overlay),
		LEFT = CreateLine(mana.Overlay),
		RIGHT = CreateLine(mana.Overlay),
	}
	mana:Hide()
	frame.Mana = mana

	-- Combo points, attached on top the same way: its bottom edge is the main bar's top
	-- border. The squares and the dividers between them are made by LayoutCombo.
	local combo = CreateFrame("Frame", nil, frame)
	combo.Overlay = CreateFrame("Frame", nil, combo)
	combo.Overlay:SetAllPoints()
	combo.Overlay:SetFrameLevel(combo:GetFrameLevel() + 3)
	combo.Border = {
		TOP = CreateLine(combo.Overlay),
		LEFT = CreateLine(combo.Overlay),
		RIGHT = CreateLine(combo.Overlay),
	}
	combo.Squares = {}
	combo.Dividers = {}
	combo:Hide()
	frame.Combo = combo

	-- Other features (the mana spark) draw on top of the bar.
	ns.PowerBarFrame = frame
end

local function CreateComboSquare(combo)
	local square = CreateFrame("StatusBar", nil, combo)
	square.Background = square:CreateTexture(nil, "BACKGROUND")
	square.Background:SetAllPoints()
	return square
end

-- count squares across the bar's width, comboGap apart (a black divider between them
-- when the border is on).
LayoutCombo = function(count)
	local db = PowerBar.db
	local combo = frame.Combo
	local border = GetBorderSize()
	local gap = db.comboGap
	local height = db.comboHeight
	local innerWidth = db.width - 2 * border
	local squareWidth = (innerWidth - (count - 1) * gap) / count
	local texture = GetTexturePath(db.barTexture)

	combo:ClearAllPoints()
	combo:SetPoint("BOTTOMLEFT", frame, "TOPLEFT")
	combo:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT")
	combo:SetHeight(height + border)

	local lines = combo.Border
	lines.TOP:ClearAllPoints()
	lines.TOP:SetPoint("TOPLEFT")
	lines.TOP:SetPoint("TOPRIGHT")
	lines.TOP:SetHeight(border)
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

	for index = 1, MAX_COMBO_SQUARES do
		local square = combo.Squares[index]
		if index <= count then
			if not square then
				square = CreateComboSquare(combo)
				combo.Squares[index] = square
			end
			local x = border + (index - 1) * (squareWidth + gap)
			square:ClearAllPoints()
			square:SetPoint("TOPLEFT", combo, "TOPLEFT", x, -border)
			square:SetSize(squareWidth, height)
			square:SetStatusBarTexture(texture)
			square:SetStatusBarColor(GetTypeColor("COMBO_POINTS"))
			square.Background:SetColorTexture(GetBackgroundColor())
			-- Filled once the count reaches this square's point.
			square:SetMinMaxValues(index - 1, index)
			square:Show()
		elseif square then
			square:Hide()
		end

		local divider = combo.Dividers[index]
		if index < count and border > 0 and gap > 0 then
			if not divider then
				divider = CreateLine(combo.Overlay)
				combo.Dividers[index] = divider
			end
			divider:ClearAllPoints()
			divider:SetPoint("TOPLEFT", combo, "TOPLEFT", border + index * squareWidth + (index - 1) * gap, -border)
			divider:SetSize(gap, height)
			divider:Show()
		elseif divider then
			divider:Hide()
		end
	end

	combo.count = count
end

-- Point on the text, the region and its point it hangs off, and the gap to it.
PositionText = function()
	local db = PowerBar.db
	local text = frame.Text
	local position = db.textPosition
	local point, region, relativePoint, x, y = "CENTER", frame.Bar, "CENTER", 0, 0
	if position == "left" then
		point, relativePoint, x = "LEFT", "LEFT", 3
	elseif position == "right" then
		point, relativePoint, x = "RIGHT", "RIGHT", -3
	elseif position == "above" then
		region = frame.Combo:IsShown() and frame.Combo or frame
		point, relativePoint, y = "BOTTOM", "TOP", 2
	elseif position == "below" then
		region = frame.Mana:IsShown() and frame.Mana or frame
		point, relativePoint, y = "TOP", "BOTTOM", -2
	end
	text:ClearAllPoints()
	text:SetPoint(point, region, relativePoint, x + db.textX, y + db.textY)
	text:SetJustifyH(point == "LEFT" and "LEFT" or point == "RIGHT" and "RIGHT" or "CENTER")
end

local function Layout()
	local db = PowerBar.db
	local border = GetBorderSize()

	frame:SetSize(db.width, db.height)
	frame.Background:SetColorTexture(GetBackgroundColor())
	frame:EnableMouse(IsUnlocked()) -- never block clicks in the middle of the screen while locked

	local lines = frame.Border
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

	frame.Bar:ClearAllPoints()
	frame.Bar:SetPoint("TOPLEFT", border, -border)
	frame.Bar:SetPoint("BOTTOMRIGHT", -border, border)
	frame.Bar:SetStatusBarTexture(GetTexturePath(db.barTexture))

	local mana = frame.Mana
	mana:ClearAllPoints()
	mana:SetPoint("TOPLEFT", frame, "BOTTOMLEFT")
	mana:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT")
	mana:SetHeight(math.max(db.druidManaHeight, 1) + border)
	mana.Background:SetColorTexture(GetBackgroundColor())
	mana.Border.BOTTOM:ClearAllPoints()
	mana.Border.BOTTOM:SetPoint("BOTTOMLEFT")
	mana.Border.BOTTOM:SetPoint("BOTTOMRIGHT")
	mana.Border.BOTTOM:SetHeight(border)
	mana.Border.LEFT:ClearAllPoints()
	mana.Border.LEFT:SetPoint("TOPLEFT")
	mana.Border.LEFT:SetPoint("BOTTOMLEFT")
	mana.Border.LEFT:SetWidth(border)
	mana.Border.RIGHT:ClearAllPoints()
	mana.Border.RIGHT:SetPoint("TOPRIGHT")
	mana.Border.RIGHT:SetPoint("BOTTOMRIGHT")
	mana.Border.RIGHT:SetWidth(border)
	for _, line in pairs(mana.Border) do
		line:SetShown(border > 0)
	end
	mana.Bar:ClearAllPoints()
	mana.Bar:SetPoint("TOPLEFT", border, 0)
	mana.Bar:SetPoint("BOTTOMRIGHT", -border, border)
	mana.Bar:SetStatusBarTexture(GetTexturePath(db.barTexture))

	LayoutCombo(GetMaxComboPoints())

	local fontPath, outline = GetFont()
	frame.Text:SetFont(fontPath, db.textSize, outline)
	frame.Text:SetShown(db.textMode ~= "none")
	PositionText()

	local position = db.position or DEFAULT_POSITION
	frame:ClearAllPoints()
	frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
end

function PowerBar:Apply()
	if not self.db.enabled then
		if frame then
			frame:Hide()
		end
		return
	end
	if not frame then
		BuildFrame()
	end
	Layout()
	frame:Show()
	UpdatePowerType()
	UpdateAlpha()
end

function PowerBar:SetEnabled(enabled)
	self.db.enabled = enabled
	self:Apply()
	if self.enableCheck then
		self.enableCheck:SetChecked(enabled)
	end
end

function PowerBar:ResetPosition()
	self.db.position = nil
	self:Apply()
end

-- The Unlock frames checkbox (Layout): mouse on and full opacity while unlocked.
function PowerBar:OnUnlockChanged(unlocked)
	self:Apply()
end

if ns.RegisterMover then
	ns:RegisterMover("powerbar", {
		title = "Power bar",
		getFrame = function()
			return frame
		end,
		save = SetPosition,
	})
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- The border used to be on/off (showBorder); off becomes thickness 0.
function PowerBar:OnInit()
	if self.db.showBorder == false then
		self.db.borderSize = 0
	end
	self.db.showBorder = nil
	-- Locking is the window's Unlock frames checkbox now, for all frames at once.
	self.db.locked = nil
end

function PowerBar:OnLogin()
	self:Apply()
end

-- The Fonts page changed the font or outline.
function PowerBar:OnFontChanged()
	self:Apply()
end

function PowerBar:OnPower(event, unit)
	if unit == "player" then
		UpdateValue(true)
		UpdateCombo()
	end
end

-- WoW Forever keeps combo points on the target, so a new target (or the points moving
-- to one) changes the count without a power event.
function PowerBar:OnComboTarget()
	UpdateCombo()
end

function PowerBar:OnDisplayPower(event, unit)
	if unit == nil or unit == "player" then
		UpdatePowerType()
	end
end

function PowerBar:OnCombatChanged()
	UpdateAlpha()
end

function PowerBar:OnScaleChanged()
	-- These events can fire before ADDON_LOADED has given us our settings.
	if self.db and self.db.enabled and frame then
		Layout()
	end
end

PowerBar:RegisterEvent("UNIT_POWER_FREQUENT", "OnPower")
PowerBar:RegisterEvent("UNIT_MAXPOWER", "OnPower")
PowerBar:RegisterEvent("UNIT_DISPLAYPOWER", "OnDisplayPower")
PowerBar:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "OnDisplayPower")
PowerBar:RegisterEvent("PLAYER_TARGET_CHANGED", "OnComboTarget")
PowerBar:RegisterEvent("COMBO_TARGET_CHANGED", "OnComboTarget")
PowerBar:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatChanged")
PowerBar:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatChanged")
PowerBar:RegisterEvent("UI_SCALE_CHANGED", "OnScaleChanged")
PowerBar:RegisterEvent("DISPLAY_SIZE_CHANGED", "OnScaleChanged")

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

-- range = { min, max, steps, format }
local function CreateSlider(module, parent, anchor, labelText, key, range)
	local label = CreateLabel(parent, labelText)
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
	label:SetWidth(130)

	local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("LEFT", label, "RIGHT", 8, 0)
	slider:SetSize(200, 20)
	slider:Init(module.db[key], range[1], range[2], range[3], {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(value)
			return string.format(range[4], value)
		end,
	})
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		value = math.floor(value + 0.5)
		if module.db[key] ~= value then
			module.db[key] = value
			module:Apply()
		end
	end, slider)
	ns.MakeSliderEditable(slider)
	return slider, label
end

local function CreateDropdown(parent, anchor, labelText, generator)
	local label = CreateLabel(parent, labelText)
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -13)
	label:SetWidth(130)

	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)
	dropdown:SetWidth(200)
	dropdown:SetupMenu(generator)
	return dropdown, label
end

local PERCENT = "%d%%"
local NUMBER = "%d"

-- After a colour changed: this bar and the unit frames' target power bar.
local function ColorsChanged()
	UpdatePowerType()
	local unitFrames = ns:GetModule("UnitFrames")
	if unitFrames and unitFrames.RefreshColors then
		unitFrames:RefreshColors()
	end
end

local function UpdateSwatch(swatch)
	swatch.Color:SetColorTexture(GetTypeColor(swatch.token))
end

local function SetTypeColor(token, r, g, b)
	PowerBar.db.colors[token] = { r, g, b }
	ColorsChanged()
end

local function OpenColorPicker(swatch)
	local token = swatch.token
	local r, g, b = GetTypeColor(token)
	local hadCustom = PowerBar.db.colors[token] ~= nil

	ColorPickerFrame:SetupColorPickerAndShow({
		r = r,
		g = g,
		b = b,
		-- Called on every change, so the bar updates while you drag.
		swatchFunc = function()
			local newR, newG, newB = ColorPickerFrame:GetColorRGB()
			SetTypeColor(token, newR, newG, newB)
			UpdateSwatch(swatch)
		end,
		cancelFunc = function()
			if hadCustom then
				SetTypeColor(token, r, g, b)
			else
				PowerBar.db.colors[token] = nil
				ColorsChanged()
			end
			UpdateSwatch(swatch)
		end,
	})
end

local function CreateSwatch(parent, colorType)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetSize(18, 18)
	swatch.token = colorType.token

	local edge = swatch:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0, 0, 0, 1)

	swatch.Color = swatch:CreateTexture(nil, "ARTWORK")
	swatch.Color:SetPoint("TOPLEFT", 1, -1)
	swatch.Color:SetPoint("BOTTOMRIGHT", -1, 1)

	swatch.Label = CreateLabel(parent, colorType.name)
	swatch.Label:SetPoint("LEFT", swatch, "RIGHT", 6, 0)

	swatch:SetScript("OnClick", OpenColorPicker)
	swatch:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(colorType.name .. " colour")
		GameTooltip:AddLine("Click to change.", 1, 1, 1)
		GameTooltip:Show()
	end)
	swatch:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	UpdateSwatch(swatch)
	return swatch
end

-- The background colour button: same look as the power colour swatches.
local function CreateBackgroundSwatch(parent)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetSize(18, 18)

	local edge = swatch:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0.5, 0.5, 0.5, 1) -- grey edge, so a black colour still shows

	swatch.Color = swatch:CreateTexture(nil, "ARTWORK")
	swatch.Color:SetPoint("TOPLEFT", 1, -1)
	swatch.Color:SetPoint("BOTTOMRIGHT", -1, 1)

	local function Update()
		local color = PowerBar.db.backgroundColor
		swatch.Color:SetColorTexture(color[1], color[2], color[3])
	end
	swatch.Update = Update

	local function SetColor(r, g, b)
		PowerBar.db.backgroundColor = { r, g, b }
		PowerBar:Apply()
		Update()
	end

	swatch:SetScript("OnClick", function()
		local old = PowerBar.db.backgroundColor
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
		GameTooltip:SetText("Background colour")
		GameTooltip:AddLine("Click to change. The opacity is the slider above.", 1, 1, 1)
		GameTooltip:Show()
	end)
	swatch:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	Update()
	return swatch
end

-- Title and a grey line under it; returns the line to anchor the first control below.
local function CreatePageHeader(page, titleText, introText)
	local title = CreateLabel(page, titleText, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)
	local intro = CreateLabel(page, introText, "GameFontDisableSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	return title, intro
end

-- The settings are split over pages: Power Bar itself (show, lock, size), and Text,
-- Style and Class Resources listed under it in the window. All use PowerBar.db.
local function RegisterSubPage(name, title, order)
	return ns:RegisterModule(name, { title = title, order = order, navParent = "PowerBar" })
end

-- Power Bar

function PowerBar:CreatePage(page)
	local module = self

	local _, intro = CreatePageHeader(page, "Power Bar",
		"Text, style and the class resource bars are on the pages under Power Bar in the list on the left. "
		.. "To move the bar, tick |cffffd100Unlock frames|r at the top of this window.")

	local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	reset:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -2)
	reset:SetSize(120, 22)
	reset:SetText("Reset position")
	reset:SetScript("OnClick", function()
		module:ResetPosition()
	end)

	local enableCheck = CreateCheck(page, "Show power bar", self.db.enabled, function(checked)
		module:SetEnabled(checked)
	end)
	enableCheck:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -4, -6)
	self.enableCheck = enableCheck

	local anchor = CreateFrame("Frame", nil, page)
	anchor:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 4, -4)
	anchor:SetSize(1, 1)

	local _, widthLabel = CreateSlider(self, page, anchor, "Width", "width", { 60, 500, 440, NUMBER })
	CreateSlider(self, page, widthLabel, "Height", "height", { 4, 40, 36, NUMBER })
end

function PowerBar:OnPageShown(page)
	self.enableCheck:SetChecked(self.db.enabled)
end

-- Text

local TextPage = RegisterSubPage("PowerBarText", "Text", 25.1)

function TextPage:CreatePage(page)
	local _, below = CreatePageHeader(page, "Power Bar Text",
		"The font and outline are on the Fonts page. X and Y move the text from the chosen spot.")

	local _, modeLabel = CreateDropdown(page, below, "Shows", function(_, rootDescription)
		local function IsSelected(key)
			return PowerBar.db.textMode == key
		end
		local function SetSelected(key)
			PowerBar.db.textMode = key
			PowerBar:Apply()
		end
		for _, mode in ipairs(TEXT_MODES) do
			rootDescription:CreateRadio(mode.name, IsSelected, SetSelected, mode.key)
		end
	end)

	local _, sizeLabel = CreateSlider(PowerBar, page, modeLabel, "Text size", "textSize", { 6, 24, 18, NUMBER })

	local _, positionLabel = CreateDropdown(page, sizeLabel, "Position", function(_, rootDescription)
		local function IsSelected(key)
			return PowerBar.db.textPosition == key
		end
		local function SetSelected(key)
			PowerBar.db.textPosition = key
			PowerBar:Apply()
		end
		for _, position in ipairs(TEXT_POSITIONS) do
			rootDescription:CreateRadio(position.name, IsSelected, SetSelected, position.key)
		end
	end)

	local _, xLabel = CreateSlider(PowerBar, page, positionLabel, "X", "textX", { -100, 100, 200, NUMBER })
	CreateSlider(PowerBar, page, xLabel, "Y", "textY", { -40, 40, 80, NUMBER })
end

-- Style

local StylePage = RegisterSubPage("PowerBarStyle", "Style", 25.2)

function StylePage:CreatePage(page)
	local module = self
	local _, below = CreatePageHeader(page, "Power Bar Style",
		"Opacity is for the whole bar; background is the dark fill behind it.")

	local classCheck = CreateCheck(page, "Class colour", PowerBar.db.classColor, function(checked)
		PowerBar.db.classColor = checked
		PowerBar:Apply()
	end)
	classCheck:SetPoint("TOPLEFT", below, "BOTTOMLEFT", -4, -6)

	local anchor = CreateFrame("Frame", nil, page)
	anchor:SetPoint("TOPLEFT", classCheck, "BOTTOMLEFT", 4, 0)
	anchor:SetSize(1, 1)

	local _, borderLabel = CreateSlider(PowerBar, page, anchor, "Border thickness", "borderSize", { 0, 5, 5, NUMBER })

	local textureDropdown, textureLabel = CreateDropdown(page, borderLabel, "Bar texture", function(_, rootDescription)
		rootDescription:SetScrollMode(300)
		local function IsSelected(key)
			return PowerBar.db.barTexture == key
		end
		local function SetSelected(key)
			PowerBar.db.barTexture = key
			PowerBar:Apply()
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

	local _, combatLabel = CreateSlider(PowerBar, page, textureLabel, "Opacity in combat", "combatOpacity", { 0, 100, 20, PERCENT })
	local _, idleLabel = CreateSlider(PowerBar, page, combatLabel, "Opacity out of combat", "idleOpacity", { 0, 100, 20, PERCENT })
	local _, backgroundLabel = CreateSlider(PowerBar, page, idleLabel, "Background opacity", "backgroundOpacity", { 0, 100, 20, PERCENT })

	local backgroundColorLabel = CreateLabel(page, "Background colour")
	backgroundColorLabel:SetPoint("TOPLEFT", backgroundLabel, "BOTTOMLEFT", 0, -14)
	backgroundColorLabel:SetWidth(130)
	self.backgroundSwatch = CreateBackgroundSwatch(page)
	self.backgroundSwatch:SetPoint("LEFT", backgroundColorLabel, "RIGHT", 8, 0)

	-- Power colour pickers: label, then the swatches in a row.
	local colorsLabel = CreateLabel(page, "Colours")
	colorsLabel:SetPoint("TOPLEFT", backgroundColorLabel, "BOTTOMLEFT", 0, -18)
	colorsLabel:SetWidth(130)

	self.swatches = {}
	local previous
	for _, colorType in ipairs(COLOR_TYPES) do
		local swatch = CreateSwatch(page, colorType)
		if previous then
			swatch:SetPoint("LEFT", previous, "RIGHT", 58, 0)
		else
			swatch:SetPoint("LEFT", colorsLabel, "RIGHT", 8, 0)
		end
		table.insert(self.swatches, swatch)
		previous = swatch
	end

	local resetColors = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	resetColors:SetPoint("TOPLEFT", colorsLabel, "BOTTOMLEFT", 0, -14)
	resetColors:SetSize(140, 22)
	resetColors:SetText("Reset colours")
	resetColors:SetScript("OnClick", function()
		wipe(PowerBar.db.colors)
		PowerBar.db.backgroundColor = { 0, 0, 0 }
		PowerBar:Apply()
		ColorsChanged()
		for _, swatch in ipairs(module.swatches) do
			UpdateSwatch(swatch)
		end
		module.backgroundSwatch.Update()
	end)
end

function StylePage:OnPageShown(page)
	for _, swatch in ipairs(self.swatches) do
		UpdateSwatch(swatch)
	end
	self.backgroundSwatch.Update()
	-- The shared media list can grow after login.
	self.textureDropdown:GenerateMenu()
end

-- Class resources

local ResourcesPage = RegisterSubPage("PowerBarResources", "Class Resources", 25.3)

function ResourcesPage:CreatePage(page)
	local _, below = CreatePageHeader(page, "Class Resources",
		"Extra bars attached to the power bar. A height of 0 turns that bar off. "
		.. "The combo point colour is on the Style page.")

	local manaHeader = CreateLabel(page, "Druid mana", "GameFontNormal")
	manaHeader:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -16)
	local manaNote = CreateLabel(page, "Under the bar while in cat or bear form, or on the player frame (tick below).", "GameFontDisableSmall")
	manaNote:SetPoint("TOPLEFT", manaHeader, "BOTTOMLEFT", 0, -4)
	local _, manaLabel = CreateSlider(PowerBar, page, manaNote, "Height", "druidManaHeight", { 0, 20, 20, NUMBER })
	local lastManaLabel = manaLabel

	-- Or on the player unit frame, like the target's power bar, with the same settings.
	-- Those live with the unit frames (playerMana...), which draw that bar.
	local unitFrames = ns:GetModule("UnitFrames")
	if unitFrames and unitFrames.db then
		local controls = {} -- greyed out while the checkbox is off
		local function UpdateControlsEnabled()
			local usable = unitFrames.db.druidManaOnPlayer
			for _, control in ipairs(controls) do
				control.widget:SetEnabled(usable)
				control.label:SetFontObject(usable and "GameFontHighlight" or "GameFontDisable")
			end
		end
		local function Add(widget, label)
			table.insert(controls, { widget = widget, label = label })
			return label
		end

		local onPlayerCheck = CreateCheck(page, "Show on the player frame instead, like the target's power bar",
			unitFrames.db.druidManaOnPlayer, function(checked)
				unitFrames.db.druidManaOnPlayer = checked
				UpdateControlsEnabled()
				unitFrames:Apply()
				PowerBar:Apply()
			end)
		onPlayerCheck:SetPoint("TOPLEFT", manaLabel, "BOTTOMLEFT", -4, -4)
		local checkAnchor = CreateFrame("Frame", nil, page)
		checkAnchor:SetPoint("TOPLEFT", onPlayerCheck, "BOTTOMLEFT", 4, 2)
		checkAnchor:SetSize(1, 1)

		-- X is measured from the far (right) end of the player's health bar.
		local label = Add(CreateSlider(unitFrames, page, checkAnchor, "Width", "playerManaWidth", { 10, 200, 190, NUMBER }))
		label = Add(CreateSlider(unitFrames, page, label, "Height", "playerManaHeight", { 2, 16, 14, NUMBER }))
		label = Add(CreateSlider(unitFrames, page, label, "X", "playerManaX", { 0, 400, 400, NUMBER }))
		label = Add(CreateSlider(unitFrames, page, label, "Y", "playerManaY", { -30, 30, 60, NUMBER }))
		label = Add(CreateSlider(unitFrames, page, label, "Background", "playerManaBackgroundOpacity", { 0, 100, 20, PERCENT }))

		local function CreateChoice(anchor, labelText, key, options)
			return CreateDropdown(page, anchor, labelText, function(_, rootDescription)
				local function IsSelected(value)
					return unitFrames.db[key] == value
				end
				local function SetSelected(value)
					unitFrames.db[key] = value
					unitFrames:Apply()
				end
				for _, option in ipairs(options) do
					rootDescription:CreateRadio(option.name, IsSelected, SetSelected, option.key)
				end
			end)
		end
		label = Add(CreateChoice(label, "Value position", "playerManaTextPosition", ns.PowerTextPositions or {}))
		label = Add(CreateChoice(label, "Value grows", "playerManaTextGrowth", ns.PowerTextGrowth or {}))
		label = Add(CreateSlider(unitFrames, page, label, "Text X", "playerManaTextX", { -80, 80, 160, NUMBER }))
		label = Add(CreateSlider(unitFrames, page, label, "Text Y", "playerManaTextY", { -20, 20, 40, NUMBER }))
		UpdateControlsEnabled()
		lastManaLabel = label
	end

	local comboHeader = CreateLabel(page, "Combo points", "GameFontNormal")
	comboHeader:SetPoint("TOPLEFT", lastManaLabel, "BOTTOMLEFT", 0, -24)
	local comboNote = CreateLabel(page, "On top of the bar for rogues and druids in cat form.", "GameFontDisableSmall")
	comboNote:SetPoint("TOPLEFT", comboHeader, "BOTTOMLEFT", 0, -4)
	local _, comboLabel = CreateSlider(PowerBar, page, comboNote, "Height", "comboHeight", { 0, 20, 20, NUMBER })
	CreateSlider(PowerBar, page, comboLabel, "Space between", "comboGap", { 0, 8, 8, NUMBER })
end
