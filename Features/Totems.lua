local addonName, ns = ...

-- The player's active totems with the time they have left, in a row under the custom
-- player frame (Unit Frames). Round icons in a class-coloured ring like the portrait, or
-- square ones with a 1 px border. Right-click a totem to dismiss it; hovering shows
-- Blizzard's tooltip. Blizzard's own totem frame is hidden while this is on. Switched
-- off, Blizzard's comes back, and with the custom frames its holder (the container under
-- the player frame, which also holds the pet frame and class bars) is moved under ours:
-- it would sit under the hidden Blizzard player frame otherwise.
--
-- Totem data can be secret (GetTotemInfo: SecretWhenTotemSlotSecret). The time left is
-- the cooldown's countdown, which takes secret durations, and a slot whose "have totem"
-- flag is secret is shown or hidden through its alpha, never compared.

local Totems = ns:RegisterModule("Totems", {
	title = "Totems",
	order = 22.9,
	navParent = "UnitFrames", -- listed under Unit Frames in the window
	defaults = {
		enabled = true,
		round = true,          -- round icon in a class-coloured ring; off: square, 1 px border
		ringWidth = 2,         -- the coloured ring, between the black edges
		size = 30,
		spacing = 3,
		textSize = 12,
		textPosition = "below", -- key in TEXT_POSITIONS
		x = 0,                  -- row's top left, from the player frame's bottom left
		y = -14,
	},
})

local TEXT_POSITIONS = {
	{ key = "below", name = "Below the icon" },
	{ key = "center", name = "On the icon" },
}

local PLAYER_FRAME = "AdamAddonPlayerFrame" -- built by UnitFrames
local BLIZZARD_CONTAINER = "PlayerBottomManagedFrameContainer" -- Blizzard_UnitFrame, [Family]\PlayerFrame.xml
local BLIZZARD_CONTAINER_POINT = { "TOP", "PlayerFrame", "BOTTOM", 30, 25 } -- its XML anchor
local PREVIEW_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local PREVIEW_DURATION = 45
local ICON_CROP = 0.08
local SWIPE_COLOR = { 0, 0, 0, 0.65 } -- as on Blizzard's totem buttons

local row            -- holds the buttons; nil until first needed
local buttons = {}
local texts = {}     -- countdown font strings, for text size changes
local blizzardOff = false
local blizzardHooked = false
local containerPoints     -- Blizzard's anchors for its container, saved before the first move
local containerMoved = false
local containerHooked = false
local movingContainer = false -- our own SetPoint calls, so the hook leaves them alone
local pendingContainer = false

-- Shown with sample totems while this page is open or the frames are unlocked.
local previewTotems = false

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function IsPreview()
	return previewTotems or (ns.IsUnlocked ~= nil and ns.IsUnlocked())
end

local function GetUnitFramesDB()
	local unitFrames = ns:GetModule("UnitFrames")
	return unitFrames and unitFrames.db
end

-- On only while the custom player frame is: it's what the row hangs off.
local function IsActive()
	local unitFramesDB = GetUnitFramesDB()
	return Totems.db.enabled and unitFramesDB ~= nil and unitFramesDB.enabled and _G[PLAYER_FRAME] ~= nil
end

-- Shamans' slots in Blizzard's order (earth, fire, water, air).
local function GetSlotOrder()
	local _, classFile = UnitClass("player")
	if not IsSecret(classFile) and classFile == "SHAMAN" and SHAMAN_TOTEM_PRIORITIES then
		return SHAMAN_TOTEM_PRIORITIES
	end
	return STANDARD_TOTEM_PRIORITIES or { 1, 2, 3, 4 }
end

local function GetClassColor()
	local _, classFile = UnitClass("player")
	local color = classFile and not IsSecret(classFile) and C_ClassColor.GetClassColor(classFile)
	if color then
		return color:GetRGB()
	end
	return 0.5, 0.5, 0.5
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

-- A countdown-only cooldown over one style's icon. round: a circular swipe, as Blizzard's
-- totem buttons do it (the CircleMask atlas as the swipe texture).
local function CreateCooldown(button, icon, round)
	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:ClearAllPoints()
	cooldown:SetAllPoints(icon)
	cooldown:SetDrawEdge(false)
	cooldown:SetReverse(true)
	cooldown:SetHideCountdownNumbers(false)
	cooldown:SetSwipeColor(unpack(SWIPE_COLOR))
	if round then
		local atlas = C_Texture.GetAtlasInfo("CircleMask")
		if atlas then
			cooldown:SetSwipeTexture(atlas.file or atlas.filename)
			cooldown:SetTexCoordRange(
				{ x = atlas.leftTexCoord, y = atlas.topTexCoord },
				{ x = atlas.rightTexCoord, y = atlas.bottomTexCoord })
		else
			cooldown:SetDrawSwipe(false)
		end
	end
	local text = cooldown:GetCountdownFontString()
	table.insert(texts, text)
	return cooldown, text
end

local function OnButtonClick(button, mouseButton)
	if mouseButton ~= "RightButton" or not button.slot then
		return
	end
	local cannotDismiss = GetTotemCannotDismiss(button.slot)
	if not IsSecret(cannotDismiss) and not cannotDismiss then
		DestroyTotem(button.slot)
	end
end

local function OnButtonEnter(button)
	if not button.slot then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:SetTotem(button.slot)
end

-- Both looks are built; Layout shows one. Round: black edge, class-coloured ring, black
-- edge, icon, like the portrait. Square: black background, cropped icon 1 px inside.
local function CreateButton()
	local button = CreateFrame("Button", nil, row)
	button:RegisterForClicks("RightButtonUp")
	button:SetScript("OnClick", OnButtonClick)
	button:SetScript("OnEnter", OnButtonEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)

	local round = {}
	round.Edge = ns.CreateCircle(button, "BACKGROUND", 0)
	round.Edge:SetColorTexture(0, 0, 0, 1)
	round.Ring = ns.CreateCircle(button, "BACKGROUND", 1)
	round.InnerEdge = ns.CreateCircle(button, "BACKGROUND", 2)
	round.InnerEdge:SetColorTexture(0, 0, 0, 1)
	round.Icon = ns.CreateCircle(button, "ARTWORK", 0)
	round.Cooldown, round.Text = CreateCooldown(button, round.Icon, true)
	button.Round = round

	local square = {}
	square.Background = button:CreateTexture(nil, "BACKGROUND")
	square.Background:SetAllPoints()
	square.Background:SetColorTexture(0, 0, 0, 1)
	square.Icon = button:CreateTexture(nil, "ARTWORK")
	square.Icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	square.Cooldown, square.Text = CreateCooldown(button, square.Icon, false)
	button.Square = square

	button:Hide()
	return button
end

local function Build()
	row = CreateFrame("Frame", nil, UIParent)
	row:SetFrameStrata("LOW")
	row:SetSize(1, 1)
	for index = 1, (MAX_TOTEMS or 4) do
		buttons[index] = CreateButton()
	end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function Inset(texture, inset)
	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", inset, -inset)
	texture:SetPoint("BOTTOMRIGHT", -inset, inset)
end

local function LayoutButton(button, index)
	local db = Totems.db
	local size = db.size
	button:SetSize(size, size)
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", row, "TOPLEFT", (index - 1) * (size + db.spacing), 0)

	local scale = button:GetEffectiveScale()
	-- The countdown text is left to its cooldown, which hides with it.
	local round, square = button.Round, button.Square
	for key, region in pairs(round) do
		if key ~= "Text" then
			region:SetShown(db.round)
		end
	end
	for key, region in pairs(square) do
		if key ~= "Text" then
			region:SetShown(not db.round)
		end
	end

	local style
	if db.round then
		-- The portrait's border thickness (Unit Frames), 0 = no black edges.
		local borderSize = GetUnitFramesDB().borderSize
		local border = borderSize > 0 and PixelUtil.GetNearestPixelSize(borderSize, scale, 1) or 0
		-- Never so thick that the icon disappears: at most a quarter of the button.
		local ringWidth = math.max(1, math.min(db.ringWidth, math.floor(size / 4)))
		Inset(round.Edge, 0)
		Inset(round.Ring, border)
		Inset(round.InnerEdge, border + ringWidth)
		Inset(round.Icon, 2 * border + ringWidth)
		round.Edge:SetShown(border > 0)
		round.InnerEdge:SetShown(border > 0)
		round.Ring:SetColorTexture(GetClassColor())
		style = round
	else
		Inset(square.Icon, PixelUtil.GetNearestPixelSize(1, scale, 1))
		style = square
	end

	-- Text on the icon, or under it. Above the swipe either way (it's the cooldown's own).
	local text = style.Text
	text:ClearAllPoints()
	if db.textPosition == "center" then
		text:SetPoint("CENTER", button, "CENTER", 0, 0)
	else
		text:SetPoint("TOP", button, "BOTTOM", 0, -1)
	end
	button.Style = style
end

local function PlaceRow()
	local playerFrame = _G[PLAYER_FRAME]
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", playerFrame, "BOTTOMLEFT", Totems.db.x, Totems.db.y)
	row:SetFrameLevel(playerFrame:GetFrameLevel() + 12)
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------

local function ClearButton(button)
	button.slot = nil
	button.Round.Cooldown:Clear()
	button.Square.Cooldown:Clear()
	button:Hide()
end

-- Readable times go straight in; secret ones through the slot's duration object.
local function SetButtonTime(button, slot, startTime, duration)
	local cooldown = button.Style.Cooldown
	if not IsSecret(startTime) and not IsSecret(duration) then
		cooldown:SetCooldown(startTime, duration)
		return
	end
	local ok, durationObject = pcall(GetTotemDuration, slot)
	if ok and durationObject and not IsSecret(durationObject) then
		pcall(cooldown.SetCooldownFromDurationObject, cooldown, durationObject)
	else
		cooldown:Clear()
	end
end

local function ShowPreview()
	local now = GetTime()
	for index, button in ipairs(buttons) do
		button.slot = nil
		button.Style.Icon:SetTexture(PREVIEW_ICON)
		button.Style.Cooldown:SetCooldown(now - index * 5, PREVIEW_DURATION)
		button:SetAlpha(1)
		button:Show()
	end
end

-- Active totems left to right, in Blizzard's slot order. A slot whose flag is secret
-- takes a place and is shown or hidden by alpha.
local function UpdateTotems()
	if not row then
		return
	end
	if not IsActive() then
		row:Hide()
		return
	end
	row:Show()
	if IsPreview() then
		ShowPreview()
		return
	end

	local index = 0
	for _, slot in ipairs(GetSlotOrder()) do
		local haveTotem, _, startTime, duration, icon = GetTotemInfo(slot)
		local secretFlag = IsSecret(haveTotem)
		local active = secretFlag
			or (haveTotem and (IsSecret(duration) or (duration and duration > 0)))
		local button = buttons[index + 1]
		if active and button then
			index = index + 1
			button.slot = slot
			button.Style.Icon:SetTexture(icon)
			SetButtonTime(button, slot, startTime, duration)
			if secretFlag then
				button:SetAlphaFromBoolean(haveTotem)
			else
				button:SetAlpha(1)
			end
			button:Show()
		end
	end
	for unused = index + 1, #buttons do
		ClearButton(buttons[unused])
	end
end

---------------------------------------------------------------------------
-- Blizzard's totem frame
---------------------------------------------------------------------------

-- Hidden the way UnitFrames hides Blizzard's player cast bar: hidden now, and again each
-- time Blizzard shows it. Given back with an update, so it shows if totems are out.
local function SetBlizzardTotemsOff(off)
	local blizzard = _G.TotemFrame
	if not blizzard then
		return
	end
	if not blizzardHooked then
		blizzardHooked = true
		blizzard:HookScript("OnShow", function(self)
			if blizzardOff then
				self:Hide()
			end
		end)
	end
	if blizzardOff == off then
		return
	end
	blizzardOff = off
	if off then
		blizzard:Hide()
	elseif blizzard.Update then
		blizzard:Update()
	end
end

-- Blizzard's totems under the custom player frame: this is switched off, the custom
-- frames are on.
local function UsesBlizzardTotems()
	local unitFramesDB = GetUnitFramesDB()
	return not Totems.db.enabled and unitFramesDB ~= nil and unitFramesDB.enabled and _G[PLAYER_FRAME] ~= nil
end

-- Same place as our row: X and Y from the player frame's bottom left.
local function AnchorContainer(container)
	movingContainer = true
	container:ClearAllPoints()
	container:SetPoint("TOPLEFT", _G[PLAYER_FRAME], "BOTTOMLEFT", Totems.db.x, Totems.db.y)
	movingContainer = false
end

-- Moved under the custom player frame, or given Blizzard's anchors back. Blizzard sets
-- its anchor again when the player frame's size changes in Edit Mode or an alternate
-- power bar shows, so that's hooked and undone. The pet frame (a secure frame) can be in
-- the container, so it's only moved out of combat.
local function UpdateBlizzardContainer()
	local container = _G[BLIZZARD_CONTAINER]
	if not container then
		return
	end
	local wanted = UsesBlizzardTotems()
	if not wanted and not containerMoved then
		return
	end
	if InCombatLockdown() then
		pendingContainer = true
		return
	end
	pendingContainer = false

	if not containerHooked then
		containerHooked = true
		hooksecurefunc(container, "SetPoint", function(self)
			if not containerMoved or movingContainer then
				return
			end
			if InCombatLockdown() then
				pendingContainer = true
			else
				AnchorContainer(self)
			end
		end)
	end

	if wanted then
		if not containerMoved then
			containerPoints = {}
			for index = 1, container:GetNumPoints() do
				containerPoints[index] = { container:GetPoint(index) }
			end
			containerMoved = true
		end
		AnchorContainer(container)
	else
		containerMoved = false
		movingContainer = true
		container:ClearAllPoints()
		if containerPoints and #containerPoints > 0 then
			for _, point in ipairs(containerPoints) do
				container:SetPoint(unpack(point))
			end
		else
			container:SetPoint(unpack(BLIZZARD_CONTAINER_POINT))
		end
		movingContainer = false
	end
end

---------------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------------

function Totems:Apply()
	if not self.db then
		return
	end
	local active = IsActive()
	SetBlizzardTotemsOff(active)
	UpdateBlizzardContainer()
	if not active then
		if row then
			row:Hide()
		end
		return
	end

	if not row then
		Build()
	end
	PlaceRow()
	for index, button in ipairs(buttons) do
		LayoutButton(button, index)
	end
	ns.SetAuraTextSize(texts, self.db.textSize)
	UpdateTotems()
end

-- Unit Frames calls this after laying out its frames (border size, switched on or off).
function ns.RefreshTotems()
	Totems:Apply()
end

function Totems:OnLogin()
	self:Apply()
end

function Totems:OnTotemUpdate()
	if self.db then
		UpdateTotems()
	end
end

function Totems:OnCombatEnded()
	if pendingContainer and self.db then
		UpdateBlizzardContainer()
	end
end

function Totems:OnFontChanged()
	self:Apply()
end

function Totems:OnUnlockChanged()
	self:Apply()
end

Totems:RegisterEvent("PLAYER_TOTEM_UPDATE", "OnTotemUpdate")
Totems:RegisterEvent("PLAYER_ENTERING_WORLD", "OnTotemUpdate")
Totems:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")

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
	slider:Init(Totems.db[key], range[1], range[2], range[3], {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(value)
			return string.format("%d", value)
		end,
	})
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		value = math.floor(value + 0.5)
		if Totems.db[key] ~= value then
			Totems.db[key] = value
			Totems:Apply()
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

function Totems:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Totems", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)
	local intro = CreateLabel(page, "Your active totems and the time they have left, under the player frame "
		.. "(needs the custom unit frames). Right-click a totem to dismiss it. "
		.. "X and Y move the row from the player frame's bottom left corner. Sample totems show while this page is open. "
		.. "Switched off, Blizzard's totem bar shows under the player frame instead, and X and Y move that.",
		"GameFontDisableSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local enableCheck = CreateCheck(page, "Show totems under the player frame (hides Blizzard's)", self.db.enabled, function(checked)
		module.db.enabled = checked
		module:Apply()
	end)
	enableCheck:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -4, -6)

	-- Ring thickness only applies to round icons, so it's greyed out for square ones.
	local ringSlider, ringLabel
	local function UpdateRingEnabled()
		local usable = module.db.round
		ringSlider:SetEnabled(usable)
		ringLabel:SetFontObject(usable and "GameFontHighlight" or "GameFontDisable")
	end

	local roundCheck = CreateCheck(page, "Round, with a class-coloured ring like the portrait", self.db.round, function(checked)
		module.db.round = checked
		UpdateRingEnabled()
		module:Apply()
	end)
	roundCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, 2)
	local roundNote = CreateLabel(page, "Off: square icons with a 1 px border.", "GameFontDisableSmall")
	roundNote:SetPoint("TOPLEFT", roundCheck, "BOTTOMLEFT", 4, 0)

	ringSlider, ringLabel = CreateSlider(page, roundNote, "Ring thickness", "ringWidth", { 1, 10, 9 })
	UpdateRingEnabled()
	local _, sizeLabel = CreateSlider(page, ringLabel, "Size", "size", { 16, 60, 44 })
	local _, spacingLabel = CreateSlider(page, sizeLabel, "Spacing", "spacing", { 0, 20, 20 })
	local _, textSizeLabel = CreateSlider(page, spacingLabel, "Text size", "textSize", { 6, 24, 18 })
	local _, positionLabel = CreateDropdown(page, textSizeLabel, "Time left", function(rootDescription)
		local function IsSelected(key)
			return module.db.textPosition == key
		end
		local function SetSelected(key)
			module.db.textPosition = key
			module:Apply()
		end
		for _, position in ipairs(TEXT_POSITIONS) do
			rootDescription:CreateRadio(position.name, IsSelected, SetSelected, position.key)
		end
	end)
	local _, xLabel = CreateSlider(page, positionLabel, "X", "x", { -200, 300, 500 })
	CreateSlider(page, xLabel, "Y", "y", { -150, 150, 300 })

	page:HookScript("OnHide", function()
		previewTotems = false
		UpdateTotems()
	end)
end

function Totems:OnPageShown(page)
	previewTotems = true
	self:Apply()
end
