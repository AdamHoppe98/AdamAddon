local addonName, ns = ...

-- Restyles Blizzard's action buttons: square icons, a 2 px black border instead of the
-- round frame art, transparent slot background, and a chosen font for the button texts.
-- Everything is undone when the feature is switched off on its page.
--
-- The buttons are secure, so changes are only made out of combat. A change asked for
-- in combat is applied as soon as combat ends.

local ActionBars = ns:RegisterModule("ActionBars", {
	title = "Action Bars",
	order = 10,
	defaults = {
		enabled = true,
		showBorder = false, -- black border on buttons and on the unit frames
		backgroundOpacity = 0, -- percent; black square fill behind the icon
		font = "default",   -- key in FONTS, or a LibSharedMedia font name
		outline = "OUTLINE",
		hotkeySize = 12,
		countSize = 14,
		nameSize = 10,
	},
	commands = {
		barstyle = {
			desc = "turn the action bar restyle on or off",
			func = function(module)
				module:SetEnabled(not module.db.enabled)
				module:Print("action bar restyle " .. (module.db.enabled and "on." or "off."))
			end,
		},
	},
})

-- Bars created by Blizzard_ActionBar (Shared/ActionBar.lua names the buttons this way).
local BUTTON_PREFIXES = {
	"ActionButton",
	"MultiBarBottomLeftButton",
	"MultiBarBottomRightButton",
	"MultiBarRightButton",
	"MultiBarLeftButton",
	"MultiBar5Button",
	"MultiBar6Button",
	"MultiBar7Button",
	"StanceButton",
	"PetActionButton",
	"PossessButton",
}
local BUTTONS_PER_BAR = 12

local ICON_CROP = 0.08
local BORDER_PIXELS = 1.3

-- Cooldown swipes are inset 2-3 px for the round art; stretch them out to the border.
local COOLDOWNS = { "cooldown", "chargeCooldown", "lossOfControlCooldown" }

-- Built-in fonts. "default" keeps Blizzard's own font objects.
local FONTS = {
	{ key = "default", name = "Blizzard default" },
	{ key = "friz", name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
	{ key = "arialn", name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
	{ key = "morpheus", name = "Morpheus", path = "Fonts\\MORPHEUS.ttf" },
	{ key = "skurri", name = "Skurri", path = "Fonts\\skurri.ttf" },
}

local OUTLINES = {
	{ key = "", name = "None" },
	{ key = "OUTLINE", name = "Outline" },
	{ key = "THICKOUTLINE", name = "Thick outline" },
	{ key = "MONOCHROME, OUTLINE", name = "Monochrome outline" },
}

-- Per-button state lives here, not on Blizzard's frames, to keep their tables untouched.
local styled = {}   -- [button] = { saved originals and our own textures }
local pendingRefresh = false

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------

-- LibSharedMedia is optional; other addons (e.g. Plater) often load it.
local function GetSharedMedia()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function GetFontPath(key)
	for _, font in ipairs(FONTS) do
		if font.key == key then
			return font.path
		end
	end
	local media = GetSharedMedia()
	if media and key then
		return media:Fetch("font", key, true)
	end
end

-- Shared with UnitFrames so both features use the same border and font.
ns.borderPixels = BORDER_PIXELS

function ns.IsBorderShown()
	return ActionBars.db == nil or ActionBars.db.showBorder
end
ns.GetFontPath = GetFontPath

---------------------------------------------------------------------------
-- Saving and restoring Blizzard's art
---------------------------------------------------------------------------

local function SavePoints(region)
	local points = {}
	for i = 1, region:GetNumPoints() do
		points[i] = { region:GetPoint(i) }
	end
	return points
end

local function RestorePoints(region, points)
	region:ClearAllPoints()
	for _, point in ipairs(points) do
		region:SetPoint(unpack(point))
	end
end

local function SaveTexture(texture)
	local width, height = texture:GetSize()
	return {
		atlas = texture:GetAtlas(),
		width = width,
		height = height,
		points = SavePoints(texture),
	}
end

local function RestoreTexture(texture, saved)
	if saved.atlas then
		texture:SetAtlas(saved.atlas)
	end
	texture:SetSize(saved.width, saved.height)
	RestorePoints(texture, saved.points)
end

local function SaveFontString(fontString)
	local path, size, flags = fontString:GetFont()
	return {
		object = fontString:GetFontObject(),
		path = path,
		size = size,
		flags = flags,
	}
end

local function RestoreFontString(fontString, saved)
	if saved.object then
		fontString:SetFontObject(saved.object)
	elseif saved.path then
		fontString:SetFont(saved.path, saved.size, saved.flags)
	end
end

---------------------------------------------------------------------------
-- Styling one button
---------------------------------------------------------------------------

-- Border thickness in screen pixels, snapped to whole pixels at the button's scale.
local function GetBorderSize(button)
	return PixelUtil.GetNearestPixelSize(BORDER_PIXELS, button:GetEffectiveScale(), BORDER_PIXELS)
end

local function CreateBorder(button)
	local border = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local line = button:CreateTexture(nil, "OVERLAY", nil, 7)
		line:SetColorTexture(0, 0, 0, 1)
		line:SetSnapToPixelGrid(false)
		line:SetTexelSnappingBias(0)
		border[side] = line
	end
	return border
end

local function LayoutBorder(button, border)
	local pixel = GetBorderSize(button)

	border.TOP:ClearAllPoints()
	border.TOP:SetPoint("TOPLEFT")
	border.TOP:SetPoint("TOPRIGHT")
	border.TOP:SetHeight(pixel)

	border.BOTTOM:ClearAllPoints()
	border.BOTTOM:SetPoint("BOTTOMLEFT")
	border.BOTTOM:SetPoint("BOTTOMRIGHT")
	border.BOTTOM:SetHeight(pixel)

	border.LEFT:ClearAllPoints()
	border.LEFT:SetPoint("TOPLEFT")
	border.LEFT:SetPoint("BOTTOMLEFT")
	border.LEFT:SetWidth(pixel)

	border.RIGHT:ClearAllPoints()
	border.RIGHT:SetPoint("TOPRIGHT")
	border.RIGHT:SetPoint("BOTTOMRIGHT")
	border.RIGHT:SetWidth(pixel)
end

local function SetBorderShown(border, shown)
	for _, line in pairs(border) do
		line:SetShown(shown)
	end
end

-- Flat replacements for the rounded hover / pressed / checked art.
local STATE_COLORS = {
	HighlightTexture = { 1, 1, 1, 0.2 },
	PushedTexture = { 0, 0, 0, 0.4 },
	CheckedTexture = { 1, 0.82, 0, 0.35 },
}

local function StyleButton(button, db)
	local state = styled[button]
	if not state then
		state = {
			alpha = {},
			textures = {},
			fonts = {},
		}
		for _, key in ipairs({ "NormalTexture", "SlotArt", "SlotBackground" }) do
			if button[key] then
				state.alpha[key] = button[key]:GetAlpha()
			end
		end
		for key in pairs(STATE_COLORS) do
			if button[key] then
				state.textures[key] = SaveTexture(button[key])
			end
		end
		state.cooldownPoints = {}
		for _, key in ipairs(COOLDOWNS) do
			if button[key] then
				state.cooldownPoints[key] = SavePoints(button[key])
			end
		end
		for _, key in ipairs({ "HotKey", "Count", "Name" }) do
			if button[key] then
				state.fonts[key] = SaveFontString(button[key])
			end
		end
		state.border = CreateBorder(button)
		-- Below the icon, which sits at BACKGROUND sublevel 0.
		state.background = button:CreateTexture(nil, "BACKGROUND", nil, -8)
		state.background:SetAllPoints(button)
		styled[button] = state
	end

	-- Frame art and Blizzard's rounded slot background off; our square fill instead.
	for key in pairs(state.alpha) do
		button[key]:SetAlpha(0)
	end
	state.background:SetColorTexture(0, 0, 0, db.backgroundOpacity / 100)
	state.background:Show()

	-- Square, cropped icon.
	if button.icon then
		if button.IconMask and not state.maskRemoved then
			button.icon:RemoveMaskTexture(button.IconMask)
			state.maskRemoved = true
		end
		button.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	end

	for key, color in pairs(STATE_COLORS) do
		local texture = button[key]
		if texture then
			texture:SetColorTexture(unpack(color))
			texture:ClearAllPoints()
			texture:SetAllPoints(button)
		end
	end

	-- Without a border the swipe covers the whole button.
	local pixel = db.showBorder and GetBorderSize(button) or 0
	for key in pairs(state.cooldownPoints) do
		local cooldown = button[key]
		cooldown:ClearAllPoints()
		cooldown:SetPoint("TOPLEFT", button, "TOPLEFT", pixel, -pixel)
		cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -pixel, pixel)
	end

	LayoutBorder(button, state.border)
	SetBorderShown(state.border, db.showBorder)

	-- Fonts.
	local fontPath = GetFontPath(db.font)
	local sizes = { HotKey = db.hotkeySize, Count = db.countSize, Name = db.nameSize }
	for key, saved in pairs(state.fonts) do
		local fontString = button[key]
		RestoreFontString(fontString, saved)
		if fontPath then
			fontString:SetFont(fontPath, sizes[key], db.outline)
		else
			-- Blizzard's face, our size and outline.
			local path = fontString:GetFont()
			if path then
				fontString:SetFont(path, sizes[key], db.outline)
			end
		end
	end
end

local function UnstyleButton(button)
	local state = styled[button]
	if not state then
		return
	end

	for key, alpha in pairs(state.alpha) do
		button[key]:SetAlpha(alpha)
	end
	state.background:Hide()

	if button.icon then
		if button.IconMask and state.maskRemoved then
			button.icon:AddMaskTexture(button.IconMask)
			state.maskRemoved = false
		end
		button.icon:SetTexCoord(0, 1, 0, 1)
	end

	for key, saved in pairs(state.textures) do
		RestoreTexture(button[key], saved)
	end

	for key, points in pairs(state.cooldownPoints) do
		RestorePoints(button[key], points)
	end

	for key, saved in pairs(state.fonts) do
		RestoreFontString(button[key], saved)
	end

	SetBorderShown(state.border, false)
end

---------------------------------------------------------------------------
-- All buttons
---------------------------------------------------------------------------

local function ForEachButton(func)
	for _, prefix in ipairs(BUTTON_PREFIXES) do
		for i = 1, BUTTONS_PER_BAR do
			local button = _G[prefix .. i]
			if button then
				func(button)
			end
		end
	end
end

function ActionBars:Refresh()
	if InCombatLockdown() then
		pendingRefresh = true
		return
	end
	pendingRefresh = false

	local db = self.db
	if db.enabled then
		ForEachButton(function(button)
			StyleButton(button, db)
		end)
	else
		ForEachButton(UnstyleButton)
	end
end

function ActionBars:SetEnabled(enabled)
	self.db.enabled = enabled
	self:Refresh()
	if self.enableCheck then
		self.enableCheck:SetChecked(enabled)
	end
	if InCombatLockdown() then
		self:Print("in combat; the change is applied when combat ends.")
	end
end

function ActionBars:OnInit()
	-- Left over from the earlier whole-button opacity slider.
	self.db.opacity = nil
end

function ActionBars:OnLogin()
	self:Refresh()
end

function ActionBars:OnCombatEnded()
	if pendingRefresh and self.db then
		self:Refresh()
	end
end

-- The pixel-snapped border depends on the effective scale, so redo the layout when it can change.
function ActionBars:OnScaleChanged()
	-- These events can fire before ADDON_LOADED has given us our settings.
	if self.db and self.db.enabled then
		self:Refresh()
	end
end

ActionBars:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")
ActionBars:RegisterEvent("UI_SCALE_CHANGED", "OnScaleChanged")
ActionBars:RegisterEvent("DISPLAY_SIZE_CHANGED", "OnScaleChanged")
ActionBars:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", "OnScaleChanged")

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------

local function CreateLabel(parent, text, template)
	local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

local function CreateDropdown(parent, anchor, labelText, width)
	local label = CreateLabel(parent, labelText)
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
	label:SetWidth(110)

	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)
	dropdown:SetWidth(width)
	return dropdown, label
end

-- range = { min, max, steps, format }; format turns the value into the label text.
local SIZE_RANGE = { 6, 24, 18, "%d" }
local OPACITY_RANGE = { 0, 100, 20, "%d%%" }

local function CreateSlider(module, parent, anchor, labelText, key, range)
	local label = CreateLabel(parent, labelText)
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -18)
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
			module:Refresh()
		end
	end, slider)
	return slider, label
end

function ActionBars:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Action Bars", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)

	local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	check:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -4, -10)
	check.Text:SetFontObject("GameFontHighlight")
	check.Text:SetText("Restyle action bars (square icons, no rounded frame art)")
	check:SetChecked(self.db.enabled)
	check:SetScript("OnClick", function(button)
		module:SetEnabled(button:GetChecked())
	end)
	self.enableCheck = check

	local borderCheck = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	borderCheck:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 0, 2)
	borderCheck.Text:SetFontObject("GameFontHighlight")
	borderCheck.Text:SetText("Black border (action bars and unit frames)")
	borderCheck:SetChecked(self.db.showBorder)
	borderCheck:SetScript("OnClick", function(button)
		module.db.showBorder = button:GetChecked()
		module:Refresh()
		local unitFrames = ns:GetModule("UnitFrames")
		if unitFrames and unitFrames.db and unitFrames.db.enabled then
			unitFrames:Apply()
		end
	end)

	local opacityAnchor = CreateFrame("Frame", nil, page)
	opacityAnchor:SetPoint("TOPLEFT", borderCheck, "BOTTOMLEFT", 4, 0)
	opacityAnchor:SetSize(1, 1)
	local _, opacityLabel = CreateSlider(self, page, opacityAnchor, "Background", "backgroundOpacity", OPACITY_RANGE)

	local fontsHeader = CreateLabel(page, "Fonts", "GameFontNormal")
	fontsHeader:SetPoint("TOPLEFT", opacityLabel, "BOTTOMLEFT", 0, -20)

	local fontDropdown, fontLabel = CreateDropdown(page, fontsHeader, "Font", 200)
	fontDropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetScrollMode(300)
		local function IsSelected(key)
			return module.db.font == key
		end
		local function SetSelected(key)
			module.db.font = key
			module:Refresh()
		end
		for _, font in ipairs(FONTS) do
			rootDescription:CreateRadio(font.name, IsSelected, SetSelected, font.key)
		end

		local media = GetSharedMedia()
		if media then
			rootDescription:CreateDivider()
			rootDescription:CreateTitle("Shared media")
			for _, name in ipairs(media:List("font")) do
				rootDescription:CreateRadio(name, IsSelected, SetSelected, name)
			end
		end
	end)

	local outlineDropdown, outlineLabel = CreateDropdown(page, fontLabel, "Outline", 200)
	outlineDropdown:SetupMenu(function(_, rootDescription)
		local function IsSelected(key)
			return module.db.outline == key
		end
		local function SetSelected(key)
			module.db.outline = key
			module:Refresh()
		end
		for _, outline in ipairs(OUTLINES) do
			rootDescription:CreateRadio(outline.name, IsSelected, SetSelected, outline.key)
		end
	end)

	local _, hotkeyLabel = CreateSlider(self, page, outlineLabel, "Keybind size", "hotkeySize", SIZE_RANGE)
	local _, countLabel = CreateSlider(self, page, hotkeyLabel, "Stack count size", "countSize", SIZE_RANGE)
	local _, nameLabel = CreateSlider(self, page, countLabel, "Macro name size", "nameSize", SIZE_RANGE)

	local note = CreateLabel(page, "", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -20)
	note:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	note:SetJustifyV("TOP")
	note:SetText("Background is how dark the inside of each slot is (0% = see-through). "
		.. "Background and font settings only apply while the restyle is on. "
		.. "Changes made in combat are applied when combat ends. "
		.. "Type |cffffd100/adam barstyle|r to switch the restyle on or off.")

	self.fontDropdown = fontDropdown
end

function ActionBars:OnPageShown(page)
	self.enableCheck:SetChecked(self.db.enabled)
	-- The dropdown's text is only refreshed on generate; the shared media list can also grow after login.
	self.fontDropdown:GenerateMenu()
end
