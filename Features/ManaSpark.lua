local addonName, ns = ...

-- Five-second rule on the power bar: spirit-based mana regen pauses for 5 seconds after
-- you spend mana. A spark sweeps across the power bar during those 5 seconds; when it
-- reaches the end, regen is back. Only drawn while the bar shows mana.
--
-- Needs the Power Bar feature (ns.PowerBarFrame); without it there's nothing to draw on.

local ManaSpark = ns:RegisterModule("ManaSpark", {
	title = "Mana Spark",
	order = 26,
	defaults = {
		enabled = true,
		style = "pip",       -- key in STYLES
		width = 8,
		extraHeight = 8,     -- added to the bar height; negative = shorter than the bar
		color = { 1, 1, 1 },
		opacity = 100,       -- percent
		glow = true,         -- additive blending: brighter, glowing look
		reverse = false,     -- right to left instead of left to right
	},
})

local FIVE_SECOND_RULE = 5

-- All verified in Blizzard's UI source (forever branch).
local STYLES = {
	{ key = "pip", name = "Cast bar spark", atlas = "ui-castingbar-pip" },
	{ key = "honor", name = "Honor bar spark", atlas = "honorsystem-bar-spark" },
	{ key = "stream", name = "Streak", file = "Interface\\COMMON\\StreamSpark" },
	{ key = "line", name = "Plain line" },
}

local spark
local startTime     -- GetTime() of the last mana spend, while the 5 seconds run
local isTest = false

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function GetStyle(key)
	for _, style in ipairs(STYLES) do
		if style.key == key then
			return style
		end
	end
	return STYLES[1]
end

---------------------------------------------------------------------------
-- The spark
---------------------------------------------------------------------------

-- Created the first time it's needed, on top of the power bar.
local function GetSpark()
	if spark then
		return spark
	end
	local bar = ns.PowerBarFrame
	if not bar then
		return nil
	end
	spark = bar.Overlay:CreateTexture(nil, "OVERLAY", nil, 6)
	spark:Hide()
	ManaSpark:ApplyLook()
	return spark
end

function ManaSpark:ApplyLook()
	if not spark then
		return
	end
	local db = self.db
	local style = GetStyle(db.style)
	if style.atlas then
		spark:SetAtlas(style.atlas)
	elseif style.file then
		spark:SetTexture(style.file)
	else
		spark:SetColorTexture(1, 1, 1, 1)
	end
	spark:SetVertexColor(db.color[1], db.color[2], db.color[3])
	spark:SetAlpha(db.opacity / 100)
	spark:SetBlendMode(db.glow and "ADD" or "BLEND")

	local barHeight = ns.PowerBarFrame and ns.PowerBarFrame:GetHeight() or 14
	spark:SetSize(db.width, math.max(barHeight + db.extraHeight, 1))
end

-- Drives the sweep only while the 5 seconds run.
local updater = CreateFrame("Frame")
updater:Hide()
updater:SetScript("OnUpdate", function(self)
	local elapsed = GetTime() - startTime
	local bar = ns.PowerBarFrame
	if elapsed >= FIVE_SECOND_RULE or not bar or not spark then
		startTime = nil
		isTest = false
		if spark then
			spark:Hide()
		end
		self:Hide()
		return
	end

	local showSpark = ManaSpark.db.enabled and bar:IsVisible()
		and (isTest or UnitPowerType("player") == Enum.PowerType.Mana)
	spark:SetShown(showSpark)
	if showSpark then
		local progress = elapsed / FIVE_SECOND_RULE
		if ManaSpark.db.reverse then
			progress = 1 - progress
		end
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", bar.Bar, "LEFT", bar.Bar:GetWidth() * progress, 0)
	end
end)

local function Start(test)
	if not GetSpark() then
		return
	end
	ManaSpark:ApplyLook() -- picks up a changed power bar height
	startTime = GetTime()
	isTest = test or false
	updater:Show()
end

-- True if the spell costs mana. Spell IDs from cast events can be secret; then we can't tell.
local function CostsMana(spellID)
	if spellID == nil or IsSecret(spellID) then
		return false
	end
	local costs = C_Spell.GetSpellPowerCost(spellID)
	if not costs then
		return false
	end
	for _, cost in ipairs(costs) do
		if cost.type == Enum.PowerType.Mana and not IsSecret(cost.cost) and cost.cost > 0 then
			return true
		end
	end
	return false
end

function ManaSpark:OnSpellCast(event, unit, castGUID, spellID)
	if self.db and self.db.enabled and unit == "player" and CostsMana(spellID) then
		Start(false)
	end
end

ManaSpark:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellCast")

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
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
	label:SetWidth(110)

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
			module:ApplyLook()
		end
	end, slider)
	ns.MakeSliderEditable(slider)
	return slider, label
end

local function UpdateSwatch(swatch)
	local color = ManaSpark.db.color
	swatch.Color:SetColorTexture(color[1], color[2], color[3])
end

local function OpenColorPicker(swatch)
	local db = ManaSpark.db
	local r, g, b = db.color[1], db.color[2], db.color[3]
	ColorPickerFrame:SetupColorPickerAndShow({
		r = r,
		g = g,
		b = b,
		-- Called on every change, so the spark updates while you drag.
		swatchFunc = function()
			local newR, newG, newB = ColorPickerFrame:GetColorRGB()
			db.color = { newR, newG, newB }
			ManaSpark:ApplyLook()
			UpdateSwatch(swatch)
		end,
		cancelFunc = function()
			db.color = { r, g, b }
			ManaSpark:ApplyLook()
			UpdateSwatch(swatch)
		end,
	})
end

function ManaSpark:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Mana Spark", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)

	local help = CreateLabel(page, "Five-second rule: after you spend mana, regen pauses for 5 seconds. "
		.. "A spark sweeps across the power bar during that time. Only shown while the bar shows mana.",
		"GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	help:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local enableCheck = CreateCheck(page, "Show the spark", self.db.enabled, function(checked)
		module.db.enabled = checked
	end)
	enableCheck:SetPoint("TOPLEFT", help, "BOTTOMLEFT", -4, -6)
	self.enableCheck = enableCheck

	local glowCheck = CreateCheck(page, "Glow", self.db.glow, function(checked)
		module.db.glow = checked
		module:ApplyLook()
	end)
	glowCheck:SetPoint("LEFT", enableCheck, "LEFT", 160, 0)

	local reverseCheck = CreateCheck(page, "Right to left", self.db.reverse, function(checked)
		module.db.reverse = checked
	end)
	reverseCheck:SetPoint("LEFT", glowCheck, "LEFT", 100, 0)

	local styleLabel = CreateLabel(page, "Style")
	styleLabel:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 4, -10)
	styleLabel:SetWidth(110)

	local styleDropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
	styleDropdown:SetPoint("LEFT", styleLabel, "RIGHT", 8, 0)
	styleDropdown:SetWidth(200)
	styleDropdown:SetupMenu(function(_, rootDescription)
		local function IsSelected(key)
			return module.db.style == key
		end
		local function SetSelected(key)
			module.db.style = key
			module:ApplyLook()
		end
		for _, style in ipairs(STYLES) do
			rootDescription:CreateRadio(style.name, IsSelected, SetSelected, style.key)
		end
	end)

	local colorLabel = CreateLabel(page, "Colour")
	colorLabel:SetPoint("TOPLEFT", styleLabel, "BOTTOMLEFT", 0, -16)
	colorLabel:SetWidth(110)

	local swatch = CreateFrame("Button", nil, page)
	swatch:SetSize(18, 18)
	swatch:SetPoint("LEFT", colorLabel, "RIGHT", 8, 0)
	local edge = swatch:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0, 0, 0, 1)
	swatch.Color = swatch:CreateTexture(nil, "ARTWORK")
	swatch.Color:SetPoint("TOPLEFT", 1, -1)
	swatch.Color:SetPoint("BOTTOMRIGHT", -1, 1)
	swatch:SetScript("OnClick", OpenColorPicker)
	UpdateSwatch(swatch)
	self.swatch = swatch

	local _, opacityLabel = CreateSlider(self, page, colorLabel, "Opacity", "opacity", { 10, 100, 18, "%d%%" })
	local _, widthLabel = CreateSlider(self, page, opacityLabel, "Width", "width", { 1, 40, 39, "%d" })
	local _, heightLabel = CreateSlider(self, page, widthLabel, "Extra height", "extraHeight", { -10, 30, 40, "%d" })

	local test = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	test:SetPoint("TOPLEFT", heightLabel, "BOTTOMLEFT", 0, -16)
	test:SetSize(140, 22)
	test:SetText("Test (5 s)")
	test:SetScript("OnClick", function()
		Start(true)
	end)

	local note = CreateLabel(page, "", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", test, "BOTTOMLEFT", 0, -12)
	note:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	note:SetText("Test shows the spark on the power bar whatever power you have, so you can see your changes. "
		.. "Needs the Power Bar to be shown.")
end

function ManaSpark:OnPageShown(page)
	self.enableCheck:SetChecked(self.db.enabled)
	UpdateSwatch(self.swatch)
end
