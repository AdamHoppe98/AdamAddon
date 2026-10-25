local addonName, ns = ...

-- Restyles Blizzard's action buttons: square icons, a 2 px black border instead of the
-- round frame art, transparent slot background, and the addon's font (the Fonts page)
-- for the button texts. Optionally rounded corners (mask images in Media\Masks).
-- Everything is undone when the feature is switched off on its page.
--
-- The buttons are secure, so changes are only made out of combat. A change asked for
-- in combat is applied as soon as combat ends.

local ActionBars = ns:RegisterModule("ActionBars", {
	title = "Action Bars",
	order = 10,
	defaults = {
		enabled = true,
		borderSize = 1,     -- black border on the buttons, as on the unit frames; 0 = none
		rounded = false,    -- rounded corners (icon, border, highlights, cooldown swipe)
		roundness = 4,      -- 1 (slightly) .. 8 (circle); which Media\Masks\Rounded<n>.tga
		backgroundOpacity = 0, -- percent; black square fill behind the icon
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

-- Cooldown swipes are inset 2-3 px for the round art; stretch them out to the border.
local COOLDOWNS = { "cooldown", "chargeCooldown", "lossOfControlCooldown" }

-- Rounded corners: white rounded squares whose alpha is the shape, used as masks and as
-- the cooldown swipe. Rounded<n>.tga has a corner radius of n/16 of the button (8 = circle).
local MASK_PATH = "Interface\\AddOns\\" .. addonName .. "\\Media\\Masks\\Rounded%d.tga"
local MAX_ROUNDNESS = 8
-- Solid white: as the swipe texture it gives the normal flat swipe back (the swipe needs
-- a texture; nil is refused).
local SQUARE_SWIPE = "Interface\\AddOns\\" .. addonName .. "\\Media\\Masks\\Square.tga"
local SWIPE_COLOR = { 0, 0, 0, 0.64 } -- CooldownFrameTemplate's swipe colour

-- Per-button state lives here, not on Blizzard's frames, to keep their tables untouched.
local styled = {}   -- [button] = { saved originals and our own textures }
local pendingRefresh = false

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

-- Border thickness in whole screen pixels at the button's scale, worked out the same way
-- as the unit frames' and power bar's border; 0 = none.
local function GetBorderSize(button)
	local size = ActionBars.db.borderSize
	if size <= 0 then
		return 0
	end
	return PixelUtil.GetNearestPixelSize(size, button:GetEffectiveScale(), 1)
end

-- The lines snap to whole screen pixels, like Blizzard's icon does. Unsnapped, a 1 px
-- line on a button whose edges fall between pixels (small bars, odd UI scales) is drawn
-- half over two pixels, and pokes a pixel out past the icon.
local function CreateBorder(button)
	local border = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local line = button:CreateTexture(nil, "OVERLAY", nil, 7)
		line:SetColorTexture(0, 0, 0, 1)
		line:SetSnapToPixelGrid(true)
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

-- Adds or removes a mask, remembering which is on so it's never added twice.
local function SetMasked(state, texture, mask, masked)
	local current = state.masked[texture]
	if current and (not masked or current ~= mask) then
		texture:RemoveMaskTexture(current)
		state.masked[texture] = nil
	end
	if masked and not state.masked[texture] then
		texture:AddMaskTexture(mask)
		state.masked[texture] = mask
	end
end

-- The icon back where Blizzard had it (no anchors of its own: it filled the button).
local function RestoreIconPoints(button, state)
	if #state.iconPoints > 0 then
		RestorePoints(button.icon, state.iconPoints)
	else
		button.icon:ClearAllPoints()
		button.icon:SetAllPoints(button)
	end
end

-- Rounded corners on or off. On: the icon is inset by the border thickness and cut to
-- the rounded shape; the black rounded shape behind it shows as the border; the slot
-- background, hover/pressed/checked highlights and the cooldown swipes take the same
-- shape. Off: all of that undone.
local function ApplyRounding(button, state, rounded, roundness, pixel)
	local maskFile = MASK_PATH:format(math.min(math.max(roundness, 1), MAX_ROUNDNESS))
	if rounded then
		state.outerMask:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		state.innerMask:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	end

	if button.icon then
		if rounded then
			button.icon:ClearAllPoints()
			button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", pixel, -pixel)
			button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -pixel, pixel)
			state.innerMask:ClearAllPoints()
			state.innerMask:SetAllPoints(button.icon)
		else
			RestoreIconPoints(button, state)
		end
		SetMasked(state, button.icon, state.innerMask, rounded)
	end

	state.roundBorder:SetShown(rounded and pixel > 0)
	SetMasked(state, state.roundBorder, state.outerMask, rounded)
	SetMasked(state, state.background, state.outerMask, rounded)
	for key in pairs(STATE_COLORS) do
		if button[key] then
			SetMasked(state, button[key], state.outerMask, rounded)
		end
	end

	-- The swipe is a plain colour normally; the mask image gives it the rounded shape, a
	-- solid square gives the plain one back. Its colour is set again after a new texture.
	for key in pairs(state.cooldownPoints) do
		local cooldown = button[key]
		if rounded or state.swipeChanged then
			cooldown:SetSwipeTexture(rounded and maskFile or SQUARE_SWIPE)
			cooldown:SetSwipeColor(unpack(SWIPE_COLOR))
		end
	end
	state.swipeChanged = rounded
end

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

		-- Rounded corners: a black rounded shape behind the icon is the border (the
		-- straight lines can't follow a curve); the masks are filled in by ApplyRounding.
		if button.icon then
			state.iconPoints = SavePoints(button.icon)
		end
		state.roundBorder = button:CreateTexture(nil, "BACKGROUND", nil, -7)
		state.roundBorder:SetAllPoints(button)
		state.roundBorder:SetColorTexture(0, 0, 0, 1)
		state.roundBorder:Hide()
		state.outerMask = button:CreateMaskTexture()
		state.outerMask:SetAllPoints(button)
		state.innerMask = button:CreateMaskTexture()
		state.masked = {} -- [texture] = mask, while it's added
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
	local pixel = GetBorderSize(button)
	for key in pairs(state.cooldownPoints) do
		local cooldown = button[key]
		cooldown:ClearAllPoints()
		cooldown:SetPoint("TOPLEFT", button, "TOPLEFT", pixel, -pixel)
		cooldown:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -pixel, pixel)
	end

	LayoutBorder(button, state.border)
	-- Rounded: the rounded shape behind the icon is the border instead of the lines.
	ApplyRounding(button, state, db.rounded, db.roundness, pixel)
	SetBorderShown(state.border, pixel > 0 and not db.rounded)

	-- Fonts: the addon's font and outline, our sizes.
	local fontPath, outline = ns.GetFont()
	local sizes = { HotKey = db.hotkeySize, Count = db.countSize, Name = db.nameSize }
	for key, saved in pairs(state.fonts) do
		local fontString = button[key]
		RestoreFontString(fontString, saved)
		if fontPath then
			fontString:SetFont(fontPath, sizes[key], outline)
		else
			-- Blizzard's face, our size and outline.
			local path = fontString:GetFont()
			if path then
				fontString:SetFont(path, sizes[key], outline)
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
	ApplyRounding(button, state, false, 1, 0)
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
	-- The border used to be on/off (showBorder); on becomes thickness 1, off 0.
	if self.db.showBorder ~= nil then
		self.db.borderSize = self.db.showBorder and 1 or 0
		self.db.showBorder = nil
	end
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
	ns.MakeSliderEditable(slider)
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

	local sliderAnchor = CreateFrame("Frame", nil, page)
	sliderAnchor:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 4, 0)
	sliderAnchor:SetSize(1, 1)
	local _, borderLabel = CreateSlider(self, page, sliderAnchor, "Border thickness", "borderSize", { 0, 5, 5, "%d" })
	local _, opacityLabel = CreateSlider(self, page, borderLabel, "Background", "backgroundOpacity", OPACITY_RANGE)

	-- Rounded corners; the roundness slider is greyed out while they're off.
	local roundnessSlider, roundnessLabel
	local function UpdateRoundnessEnabled()
		roundnessSlider:SetEnabled(module.db.rounded)
		roundnessLabel:SetFontObject(module.db.rounded and "GameFontHighlight" or "GameFontDisable")
	end
	local roundedCheck = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	roundedCheck:SetPoint("TOPLEFT", opacityLabel, "BOTTOMLEFT", -4, -10)
	roundedCheck.Text:SetFontObject("GameFontHighlight")
	roundedCheck.Text:SetText("Rounded corners")
	roundedCheck:SetChecked(self.db.rounded)
	roundedCheck:SetScript("OnClick", function(button)
		module.db.rounded = button:GetChecked()
		UpdateRoundnessEnabled()
		module:Refresh()
	end)
	local roundedAnchor = CreateFrame("Frame", nil, page)
	roundedAnchor:SetPoint("TOPLEFT", roundedCheck, "BOTTOMLEFT", 4, 14)
	roundedAnchor:SetSize(1, 1)
	roundnessSlider, roundnessLabel = CreateSlider(self, page, roundedAnchor, "Corner roundness", "roundness", { 1, MAX_ROUNDNESS, MAX_ROUNDNESS - 1, "%d" })
	UpdateRoundnessEnabled()

	local fontsHeader = CreateLabel(page, "Text sizes", "GameFontNormal")
	fontsHeader:SetPoint("TOPLEFT", roundnessLabel, "BOTTOMLEFT", 0, -20)
	local fontsNote = CreateLabel(page, "The font and outline are on the Fonts page.", "GameFontDisableSmall")
	fontsNote:SetPoint("TOPLEFT", fontsHeader, "BOTTOMLEFT", 0, -6)

	local _, hotkeyLabel = CreateSlider(self, page, fontsNote, "Keybind size", "hotkeySize", SIZE_RANGE)
	local _, countLabel = CreateSlider(self, page, hotkeyLabel, "Stack count size", "countSize", SIZE_RANGE)
	local _, nameLabel = CreateSlider(self, page, countLabel, "Macro name size", "nameSize", SIZE_RANGE)

	local note = CreateLabel(page, "", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -20)
	note:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	note:SetJustifyV("TOP")
	note:SetText("Background is how dark the inside of each slot is (0% = see-through). "
		.. "Background and text settings only apply while the restyle is on. "
		.. "Changes made in combat are applied when combat ends. "
		.. "Type |cffffd100/adam barstyle|r to switch the restyle on or off.")
end

function ActionBars:OnPageShown(page)
	self.enableCheck:SetChecked(self.db.enabled)
end

-- The Fonts page changed the font or outline.
function ActionBars:OnFontChanged()
	self:Refresh()
end
