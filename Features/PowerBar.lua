local addonName, ns = ...

-- A movable bar showing the player's current power: whatever the default UI would show,
-- so mana for casters, energy in cat form, rage in bear form, and so on.
--
-- Power values can be secret in WoW Forever. They go straight into the bar and the font
-- string, which accept secrets, and are never compared or calculated with. The bar is a
-- plain (not secure) frame, so it updates and can be changed in combat.

local PowerBar = ns:RegisterModule("PowerBar", {
	title = "Power Bar",
	order = 25,
	defaults = {
		enabled = true,
		locked = true,
		width = 220,
		height = 14,
		druidManaHeight = 4,     -- mana bar under the bar in cat/bear form; 0 = off
		showBorder = true,
		backgroundOpacity = 50,  -- percent
		combatOpacity = 100,     -- percent, while in combat
		idleOpacity = 100,       -- percent, out of combat
		barTexture = "flat",     -- key from the Unit Frames texture list
		textMode = "percent",    -- "none", "value", "percent", "both"
		textSize = 11,
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

-- Power types with their own colour picker on the page.
local COLOR_TYPES = {
	{ token = "MANA", name = "Mana" },
	{ token = "RAGE", name = "Rage" },
	{ token = "ENERGY", name = "Energy" },
}

local frame

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function GetFont()
	local actionBars = ns:GetModule("ActionBars")
	local settings = actionBars and actionBars.db
	local path = settings and ns.GetFontPath and ns.GetFontPath(settings.font)
	return path or DEFAULT_FONT, settings and settings.outline or "OUTLINE"
end

local function GetTexturePath(key)
	if ns.GetBarTexturePath then
		return ns.GetBarTexturePath(key)
	end
	return FALLBACK_TEXTURE
end

local function GetBorderSize()
	return PixelUtil.GetNearestPixelSize(ns.borderPixels or 1, frame:GetEffectiveScale(), 1)
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
	UpdateValue()
end

local function UpdateAlpha()
	if not frame then
		return
	end
	local db = PowerBar.db
	local opacity = UnitAffectingCombat("player") and db.combatOpacity or db.idleOpacity
	-- Always fully visible while unlocked, so it can be found and moved.
	if not db.locked then
		opacity = 100
	end
	frame:SetAlpha(opacity / 100)
end

---------------------------------------------------------------------------
-- Building and layout
---------------------------------------------------------------------------

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	PowerBar.db.position = { point, relativePoint, x, y }
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
		if not PowerBar.db.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
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
	frame.Text:SetPoint("CENTER", frame.Bar, "CENTER", 0, 0)
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

	-- Other features (the mana spark) draw on top of the bar.
	ns.PowerBarFrame = frame
end

local function Layout()
	local db = PowerBar.db
	local border = db.showBorder and GetBorderSize() or 0

	frame:SetSize(db.width, db.height)
	frame.Background:SetColorTexture(0, 0, 0, db.backgroundOpacity / 100)
	frame:EnableMouse(not db.locked) -- never block clicks in the middle of the screen while locked

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
	mana.Background:SetColorTexture(0, 0, 0, db.backgroundOpacity / 100)
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

	local fontPath, outline = GetFont()
	frame.Text:SetFont(fontPath, db.textSize, outline)
	frame.Text:SetShown(db.textMode ~= "none")

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

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

function PowerBar:OnLogin()
	self:Apply()
end

function PowerBar:OnPower(event, unit)
	if unit == "player" then
		UpdateValue(true)
	end
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

local function UpdateSwatch(swatch)
	swatch.Color:SetColorTexture(GetTypeColor(swatch.token))
end

local function SetTypeColor(token, r, g, b)
	PowerBar.db.colors[token] = { r, g, b }
	UpdatePowerType()
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
				UpdatePowerType()
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

function PowerBar:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Power Bar", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)

	-- Two checkboxes per row to keep the page short.
	local enableCheck = CreateCheck(page, "Show power bar", self.db.enabled, function(checked)
		module:SetEnabled(checked)
	end)
	enableCheck:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -4, -6)
	self.enableCheck = enableCheck

	local lockCheck = CreateCheck(page, "Lock (untick to drag)", self.db.locked, function(checked)
		module.db.locked = checked
		module:Apply()
	end)
	lockCheck:SetPoint("LEFT", enableCheck, "LEFT", 220, 0)
	self.lockCheck = lockCheck

	local borderCheck = CreateCheck(page, "Black border", self.db.showBorder, function(checked)
		module.db.showBorder = checked
		module:Apply()
	end)
	borderCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, 4)

	local classCheck = CreateCheck(page, "Class colour", self.db.classColor, function(checked)
		module.db.classColor = checked
		module:Apply()
	end)
	classCheck:SetPoint("LEFT", borderCheck, "LEFT", 220, 0)

	local anchor = CreateFrame("Frame", nil, page)
	anchor:SetPoint("TOPLEFT", borderCheck, "BOTTOMLEFT", 4, 0)
	anchor:SetSize(1, 1)

	local _, widthLabel = CreateSlider(self, page, anchor, "Width", "width", { 60, 500, 44, NUMBER })
	local _, heightLabel = CreateSlider(self, page, widthLabel, "Height", "height", { 4, 40, 36, NUMBER })
	local _, druidLabel = CreateSlider(self, page, heightLabel, "Druid mana height", "druidManaHeight", { 0, 20, 20, NUMBER })
	local _, backgroundLabel = CreateSlider(self, page, druidLabel, "Background", "backgroundOpacity", { 0, 100, 20, PERCENT })
	local _, combatLabel = CreateSlider(self, page, backgroundLabel, "Opacity in combat", "combatOpacity", { 0, 100, 20, PERCENT })
	local _, idleLabel = CreateSlider(self, page, combatLabel, "Opacity out of combat", "idleOpacity", { 0, 100, 20, PERCENT })
	local _, textSizeLabel = CreateSlider(self, page, idleLabel, "Text size", "textSize", { 6, 24, 18, NUMBER })

	local textureDropdown, textureLabel = CreateDropdown(page, textSizeLabel, "Bar texture", function(_, rootDescription)
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

	local _, textLabel = CreateDropdown(page, textureLabel, "Text", function(_, rootDescription)
		local function IsSelected(key)
			return module.db.textMode == key
		end
		local function SetSelected(key)
			module.db.textMode = key
			module:Apply()
		end
		for _, mode in ipairs(TEXT_MODES) do
			rootDescription:CreateRadio(mode.name, IsSelected, SetSelected, mode.key)
		end
	end)

	-- Colour pickers: label, then the three swatches in a row.
	local colorsLabel = CreateLabel(page, "Colours")
	colorsLabel:SetPoint("TOPLEFT", textLabel, "BOTTOMLEFT", 0, -16)
	colorsLabel:SetWidth(130)

	self.swatches = {}
	local previous
	for _, colorType in ipairs(COLOR_TYPES) do
		local swatch = CreateSwatch(page, colorType)
		if previous then
			swatch:SetPoint("LEFT", previous, "RIGHT", 70, 0)
		else
			swatch:SetPoint("LEFT", colorsLabel, "RIGHT", 8, 0)
		end
		table.insert(self.swatches, swatch)
		previous = swatch
	end

	local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	reset:SetPoint("TOPLEFT", colorsLabel, "BOTTOMLEFT", 0, -14)
	reset:SetSize(140, 22)
	reset:SetText("Reset position")
	reset:SetScript("OnClick", function()
		module:ResetPosition()
	end)

	local resetColors = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	resetColors:SetPoint("LEFT", reset, "RIGHT", 8, 0)
	resetColors:SetSize(140, 22)
	resetColors:SetText("Reset colours")
	resetColors:SetScript("OnClick", function()
		wipe(module.db.colors)
		UpdatePowerType()
		for _, swatch in ipairs(module.swatches) do
			UpdateSwatch(swatch)
		end
	end)
end

function PowerBar:OnPageShown(page)
	self.enableCheck:SetChecked(self.db.enabled)
	self.lockCheck:SetChecked(self.db.locked)
	for _, swatch in ipairs(self.swatches) do
		UpdateSwatch(swatch)
	end
	-- The shared media list can grow after login.
	self.textureDropdown:GenerateMenu()
end
