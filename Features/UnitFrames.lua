local addonName, ns = ...

-- Replaces Blizzard's player and target frames with flat ones in the action bar style:
-- one thick health bar (no portrait, no power bar), border shared with the action bars.
-- Player: "% ... number". Target: mirrored, name on the top edge, level bottom left,
-- buffs above.
--
-- The frames are secure unit buttons (click to target, right-click for the menu), so
-- showing, hiding, moving and resizing them only happens out of combat. Health values
-- are secret in WoW Forever; they go straight into the bar and the font strings,
-- which accept secrets, and are never compared or calculated with.

local UnitFrames = ns:RegisterModule("UnitFrames", {
	title = "Unit Frames",
	order = 20,
	defaults = {
		enabled = true,
		locked = true,
		width = 220,
		height = 40,
		textSize = 13,
		buffSize = 22,
		barTexture = "blizzard", -- key in BAR_TEXTURES, or a LibSharedMedia statusbar name
		positions = {
			player = nil, -- { point, relativePoint, x, y }; nil = default
			target = nil,
		},
	},
	commands = {
		framestyle = {
			desc = "turn the custom player and target frames on or off",
			func = function(module)
				module:SetEnabled(not module.db.enabled)
				module:Print("custom unit frames " .. (module.db.enabled and "on." or "off."))
			end,
		},
	},
})

local UNITS = {
	player = {
		unit = "player",
		frameName = "AdamAddonPlayerFrame",
		blizzardFrame = "PlayerFrame",
		showCombat = true, -- crossed swords on the bottom-left edge while in combat
		defaultPosition = { "CENTER", "CENTER", -260, -160 },
	},
	target = {
		unit = "target",
		frameName = "AdamAddonTargetFrame",
		blizzardFrame = "TargetFrame",
		mirrored = true, -- number left, % right
		showName = true,
		levelLeft = true,
		showBuffs = true,
		defaultPosition = { "CENTER", "CENTER", 260, -160 },
	},
	-- Small, name left and % right, attached to the right of the target frame.
	-- Blizzard's own target-of-target frame lives inside TargetFrame, so it's already hidden.
	targettarget = {
		unit = "targettarget",
		frameName = "AdamAddonTargetTargetFrame",
		compact = true,
		showName = true,
		placeholderName = "Target of target",
		anchorTo = "target",
	},
}
local UNIT_ORDER = { "player", "target", "targettarget" } -- target before the frame anchored to it

-- Target of target size relative to the main frames, and how often it polls:
-- unit events don't fire for "targettarget".
local COMPACT_WIDTH_SCALE = 0.55
local COMPACT_HEIGHT_SCALE = 0.65
local COMPACT_GAP = 6
local POLL_INTERVAL = 0.25

-- Our own textures are plain grey levels in Media\BarTextures, tinted by the bar colour.
local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\BarTextures\\"
local BAR_TEXTURES = {
	{ key = "flat", name = "Flat", path = MEDIA .. "Flat.tga" },
	{ key = "smooth", name = "Smooth", path = MEDIA .. "Smooth.tga" },
	{ key = "glass", name = "Glass", path = MEDIA .. "Glass.tga" },
	{ key = "stripes", name = "Stripes", path = MEDIA .. "Stripes.tga" },
	{ key = "blizzard", name = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
	{ key = "raid", name = "Blizzard raid", path = "Interface\\RaidFrame\\UI-RaidFrame-HealthBar" },
	{ key = "skills", name = "Blizzard skills", path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
	{ key = "targetfill", name = "Blizzard target", path = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill" },
}
local DEFAULT_BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local ICON_CROP = 0.08
local COMBAT_ICON_ATLAS = "UI-HUD-UnitFrame-Player-CombatIcon" -- same art as Blizzard's player frame
local MAX_BUFFS = 16

local frames = {}           -- [key] = our frame
local blizzardParents = {}  -- [frame name] = original parent, while Blizzard's frame is hidden
local pendingApply = false

-- Blizzard's frames are parked under this hidden frame instead of being torn down,
-- so switching the feature off can give them back without a /reload.
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

---------------------------------------------------------------------------
-- Shared look (border, font, background) from the ActionBars feature
---------------------------------------------------------------------------

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- 0 when the border is switched off on the Action Bars page.
local function GetBorderSize(frame)
	if ns.IsBorderShown and not ns.IsBorderShown() then
		return 0
	end
	return PixelUtil.GetNearestPixelSize(ns.borderPixels or 1, frame:GetEffectiveScale(), 1)
end

local function GetActionBarSettings()
	local actionBars = ns:GetModule("ActionBars")
	return actionBars and actionBars.db
end

local function GetFont()
	local settings = GetActionBarSettings()
	local path = settings and ns.GetFontPath and ns.GetFontPath(settings.font)
	local outline = settings and settings.outline or "OUTLINE"
	return path or DEFAULT_FONT, outline
end

-- LibSharedMedia is optional; other addons (e.g. Plater) often load it.
local function GetSharedMedia()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

local function GetBarTexturePath(key)
	for _, texture in ipairs(BAR_TEXTURES) do
		if texture.key == key then
			return texture.path
		end
	end
	local media = GetSharedMedia()
	if media and key then
		return media:Fetch("statusbar", key, true) or DEFAULT_BAR_TEXTURE
	end
	return DEFAULT_BAR_TEXTURE
end

-- Shared with PowerBar so both offer the same textures.
ns.BarTextures = BAR_TEXTURES
ns.GetBarTexturePath = GetBarTexturePath

local function GetBackgroundAlpha()
	local settings = GetActionBarSettings()
	return (settings and settings.backgroundOpacity or 0) / 100
end

---------------------------------------------------------------------------
-- Updating one frame
---------------------------------------------------------------------------

-- smooth: glide to the new value (the engine animates it, so secret values work).
-- Not smooth: jump, used when the frame starts showing a different unit.
local function UpdateHealth(frame, smooth)
	local unit = frame.unit
	local bar = frame.HealthBar
	local interpolation = smooth and Enum.StatusBarInterpolation.ExponentialEaseOut
		or Enum.StatusBarInterpolation.Immediate

	if not UnitExists(unit) then
		-- Only seen while the frames are unlocked for moving.
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		frame.PercentText:SetText("100%")
		frame.ValueText:SetText("")
		return
	end

	if UnitIsDeadOrGhost(unit) then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0, interpolation)
		frame.PercentText:SetText("Dead")
		frame.ValueText:SetText("")
		return
	end

	if not UnitIsConnected(unit) then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		frame.PercentText:SetText("Offline")
		frame.ValueText:SetText("")
		return
	end

	-- Secret values: passed through, never compared.
	bar:SetMinMaxValues(0, UnitHealthMax(unit))
	bar:SetValue(UnitHealth(unit), interpolation)
	frame.ValueText:SetText(AbbreviateLargeNumbers(UnitHealth(unit)))
	frame.PercentText:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
end

local function UpdateColor(frame)
	local unit = frame.unit
	local r, g, b = 0.5, 0.5, 0.5

	if UnitExists(unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) and not UnitIsTapDenied(unit) then
		if UnitIsPlayer(unit) then
			local _, classFile = UnitClass(unit)
			local color = classFile and not IsSecret(classFile) and C_ClassColor.GetClassColor(classFile)
			if color then
				r, g, b = color:GetRGB()
			end
		else
			local reaction = UnitReaction(unit, "player")
			local color = reaction and not IsSecret(reaction) and FACTION_BAR_COLORS[reaction]
			if color then
				r, g, b = color.r, color.g, color.b
			end
		end
	elseif not UnitExists(unit) then
		r, g, b = 0.2, 0.6, 0.2
	end

	frame.HealthBar:SetStatusBarColor(r, g, b)
end

local function UpdateName(frame)
	if not frame.NameText then
		return
	end
	if UnitExists(frame.unit) then
		frame.NameText:SetText(UnitName(frame.unit))
	else
		frame.NameText:SetText(frame.info.placeholderName or "Target")
	end
end

local function UpdateLevel(frame)
	local unit = frame.unit
	if not UnitExists(unit) then
		frame.LevelText:SetText("")
		return
	end

	local level = UnitLevel(unit)
	if IsSecret(level) then
		frame.LevelText:SetText(level)
	elseif level and level > 0 then
		frame.LevelText:SetText(tostring(level))
	else
		frame.LevelText:SetText("??")
	end
end

local function UpdateCombat(frame)
	if frame.CombatIcon then
		frame.CombatIcon:SetShown(UnitAffectingCombat(frame.unit))
	end
end

-- smooth is only passed by the target-of-target poll; a new unit always snaps.
local function UpdateAll(frame, smooth)
	UpdateHealth(frame, smooth)
	UpdateColor(frame)
	UpdateName(frame)
	UpdateLevel(frame)
	UpdateCombat(frame)
	if frame.Buffs then
		frame.Buffs:UpdateAllAuras()
	end
end

local function ForUnit(unit, func)
	for _, frame in pairs(frames) do
		if frame.unit == unit and frame:IsShown() then
			func(frame)
		end
	end
end

---------------------------------------------------------------------------
-- Building and laying out
---------------------------------------------------------------------------

local function CreateLine(parent)
	local line = parent:CreateTexture(nil, "OVERLAY", nil, 7)
	line:SetColorTexture(0, 0, 0, 1)
	line:SetSnapToPixelGrid(false)
	line:SetTexelSnappingBias(0)
	return line
end

local function CreateText(parent, justify)
	local text = parent:CreateFontString(nil, "OVERLAY")
	text:SetJustifyH(justify)
	text:SetWordWrap(false)
	return text
end

-- Called once per buff button by Blizzard's aura container.
local function InitializeBuffButton(button)
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 1)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", -1, 1)
	icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	button:SetIcon(icon)

	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:ClearAllPoints()
	cooldown:SetAllPoints(icon)
	cooldown:SetDrawEdge(false)
	button:SetDurationCooldown(cooldown)

	-- Above the cooldown swipe.
	local textLayer = CreateFrame("Frame", nil, button)
	textLayer:SetAllPoints()
	textLayer:SetFrameLevel(cooldown:GetFrameLevel() + 1)
	local count = textLayer:CreateFontString(nil, "OVERLAY")
	count:SetFont(GetFont(), 10, "OUTLINE")
	count:SetPoint("BOTTOMRIGHT", 1, 0)
	button:SetApplicationCount(count)
end

local function CreateBuffs(frame)
	local buffs = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
	buffs:AddAuraGroup("buffs", "HELPFUL", {
		maxFrameCount = MAX_BUFFS,
		initializeFrame = InitializeBuffButton,
	})
	buffs:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
	buffs:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
	buffs:SetUnit(frame.unit)
	return buffs
end

local function SavePosition(frame)
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	UnitFrames.db.positions[frame.key] = { point, relativePoint, x, y }
end

local function BuildFrame(key)
	local info = UNITS[key]

	local frame = CreateFrame("Button", info.frameName, UIParent, "SecureUnitButtonTemplate")
	frame.key = key
	frame.unit = info.unit
	frame.info = info
	frame:SetAttribute("unit", info.unit)
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "togglemenu")
	frame:RegisterForClicks("AnyUp")
	frame:SetFrameStrata("LOW")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		-- Anchored frames move with the frame they hang off.
		if not UnitFrames.db.locked and not InCombatLockdown() and not self.info.anchorTo then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self)
	end)
	-- The unit watch shows the target frame a moment after PLAYER_TARGET_CHANGED.
	frame:HookScript("OnShow", function(self)
		UpdateAll(self)
	end)
	if info.unit == "targettarget" then
		local elapsedSinceUpdate = 0
		frame:HookScript("OnUpdate", function(self, elapsed)
			elapsedSinceUpdate = elapsedSinceUpdate + elapsed
			if elapsedSinceUpdate >= POLL_INTERVAL then
				elapsedSinceUpdate = 0
				UpdateAll(self, true)
			end
		end)
	end
	frame:Hide()

	frame.Background = frame:CreateTexture(nil, "BACKGROUND")
	frame.Background:SetAllPoints()

	frame.HealthBar = CreateFrame("StatusBar", nil, frame)
	frame.HealthBar:SetStatusBarTexture(GetBarTexturePath(UnitFrames.db.barTexture))

	-- Border and texts sit on a layer above the health bar.
	frame.Overlay = CreateFrame("Frame", nil, frame)
	frame.Overlay:SetAllPoints()
	frame.Overlay:SetFrameLevel(frame.HealthBar:GetFrameLevel() + 2)

	frame.Border = {
		TOP = CreateLine(frame.Overlay),
		BOTTOM = CreateLine(frame.Overlay),
		LEFT = CreateLine(frame.Overlay),
		RIGHT = CreateLine(frame.Overlay),
	}

	-- Player: "%" left, number right. Target: mirrored.
	local percentSide = info.mirrored and "RIGHT" or "LEFT"
	local valueSide = percentSide == "LEFT" and "RIGHT" or "LEFT"
	frame.PercentText = CreateText(frame.Overlay, percentSide)
	frame.ValueText = CreateText(frame.Overlay, valueSide)
	frame.LevelText = CreateText(frame.Overlay, "RIGHT")
	if info.showName then
		frame.NameText = CreateText(frame.Overlay, "LEFT")
	end
	if info.showCombat then
		frame.CombatIcon = frame.Overlay:CreateTexture(nil, "OVERLAY")
		frame.CombatIcon:SetAtlas(COMBAT_ICON_ATLAS)
		frame.CombatIcon:Hide()
	end

	if info.showBuffs then
		frame.Buffs = CreateBuffs(frame)
	end

	frames[key] = frame
	return frame
end

local function LayoutFrame(frame)
	local db = UnitFrames.db
	local border = GetBorderSize(frame)
	local compact = frame.info.compact
	local width, height = db.width, db.height
	if compact then
		width = math.floor(width * COMPACT_WIDTH_SCALE + 0.5)
		height = math.floor(height * COMPACT_HEIGHT_SCALE + 0.5)
	end
	frame:SetSize(width, height)
	frame.Background:SetColorTexture(0, 0, 0, GetBackgroundAlpha())

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

	local bar = frame.HealthBar
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", border, -border)
	bar:SetPoint("BOTTOMRIGHT", -border, border)

	local fontPath, outline = GetFont()
	local textSize = db.textSize
	local smallSize = math.max(textSize - 2, 6)

	frame.PercentText:ClearAllPoints()
	frame.ValueText:ClearAllPoints()
	if frame.info.mirrored then
		frame.ValueText:SetPoint("LEFT", bar, "LEFT", 4, 0)
		frame.PercentText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	else
		frame.PercentText:SetPoint("LEFT", bar, "LEFT", 4, 0)
		frame.ValueText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	end
	frame.PercentText:SetFont(fontPath, textSize, outline)
	frame.ValueText:SetFont(fontPath, textSize, outline)

	-- Level sits on the bottom edge (right for the player, left for the target);
	-- the target's name sits on the top edge, left.
	frame.LevelText:ClearAllPoints()
	if frame.info.levelLeft then
		frame.LevelText:SetPoint("LEFT", frame, "BOTTOMLEFT", 6, 0)
	else
		frame.LevelText:SetPoint("RIGHT", frame, "BOTTOMRIGHT", -6, 0)
	end
	frame.LevelText:SetFont(fontPath, smallSize, outline)

	if frame.CombatIcon then
		local iconSize = smallSize + 6
		frame.CombatIcon:SetSize(iconSize, iconSize)
		frame.CombatIcon:ClearAllPoints()
		frame.CombatIcon:SetPoint("LEFT", frame, "BOTTOMLEFT", 4, 0)
	end

	if frame.NameText and not compact then
		frame.NameText:ClearAllPoints()
		frame.NameText:SetPoint("LEFT", frame, "TOPLEFT", 6, 0)
		frame.NameText:SetWidth(width * 0.7)
		frame.NameText:SetFont(fontPath, smallSize, outline)
	end

	-- Compact: name inside the bar on the left, % on the right, nothing else.
	frame.ValueText:SetShown(not compact)
	frame.LevelText:SetShown(not compact)
	if compact then
		frame.PercentText:ClearAllPoints()
		frame.PercentText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
		frame.PercentText:SetFont(fontPath, smallSize, outline)
		frame.NameText:ClearAllPoints()
		frame.NameText:SetPoint("LEFT", bar, "LEFT", 3, 0)
		frame.NameText:SetPoint("RIGHT", frame.PercentText, "LEFT", -4, 0)
		frame.NameText:SetFont(fontPath, smallSize, outline)
	end

	if frame.Buffs then
		frame.Buffs:ClearAllPoints()
		-- Clear of the name on the top edge.
		local nameClearance = frame.NameText and math.ceil(smallSize / 2) or 0
		frame.Buffs:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 4 + nameClearance)
		frame.Buffs:SetFlowLayoutMaximumLineSize(width)
		frame.Buffs:SetAuraGroupLayout("buffs", {
			elementWidth = db.buffSize,
			elementHeight = db.buffSize,
			elementSpacing = 2,
			lineSpacing = 2,
		})
	end

	frame:ClearAllPoints()
	local anchorFrame = frame.info.anchorTo and frames[frame.info.anchorTo]
	if anchorFrame then
		frame:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMRIGHT", COMPACT_GAP, 0)
	else
		local position = db.positions[frame.key] or frame.info.defaultPosition
		frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
	end
end

---------------------------------------------------------------------------
-- Blizzard's frames
---------------------------------------------------------------------------

-- Frames Blizzard parents to PlayerFrame that must stay visible: the pet frame, totems
-- and class resource bars (combo points) all live in PlayerBottomManagedFrameContainer.
local KEEP_VISIBLE = {
	PlayerFrame = { "PlayerBottomManagedFrameContainer", "PetFrame", "TotemFrame", "RuneFrame" },
}
local rescued = {} -- [child name] = original parent

local function HideBlizzardFrame(name)
	if not name then
		return
	end
	local blizzard = _G[name]
	if not blizzard or blizzardParents[name] then
		return
	end

	for _, childName in ipairs(KEEP_VISIBLE[name] or {}) do
		local child = _G[childName]
		if child and child:GetParent() == blizzard then
			rescued[childName] = blizzard
			child:SetParent(UIParent)
		end
	end

	blizzardParents[name] = blizzard:GetParent()
	blizzard:SetParent(hiddenParent)
end

local function RestoreBlizzardFrame(name)
	if not name then
		return
	end
	local blizzard = _G[name]
	local parent = blizzardParents[name]
	if not blizzard or not parent then
		return
	end

	blizzard:SetParent(parent)
	blizzardParents[name] = nil

	for _, childName in ipairs(KEEP_VISIBLE[name] or {}) do
		local child = _G[childName]
		if child and rescued[childName] and child:GetParent() == UIParent then
			child:SetParent(rescued[childName])
		end
		rescued[childName] = nil
	end
end

---------------------------------------------------------------------------
-- Applying settings
---------------------------------------------------------------------------

local function ShowFrame(frame)
	local db = UnitFrames.db
	if frame.unit == "player" then
		frame:Show()
		return
	end

	-- The target frame follows the target, except while unlocked so it can be placed.
	if db.locked then
		if not frame.watched then
			RegisterUnitWatch(frame)
			frame.watched = true
		end
	else
		if frame.watched then
			UnregisterUnitWatch(frame)
			frame.watched = false
		end
		frame:Show()
	end
end

local function HideFrame(frame)
	if frame.watched then
		UnregisterUnitWatch(frame)
		frame.watched = false
	end
	frame:Hide()
end

function UnitFrames:Apply()
	if InCombatLockdown() then
		pendingApply = true
		return
	end
	pendingApply = false

	for _, key in ipairs(UNIT_ORDER) do
		local info = UNITS[key]
		local frame = frames[key]
		if self.db.enabled then
			frame = frame or BuildFrame(key)
			LayoutFrame(frame)
			HideBlizzardFrame(info.blizzardFrame)
			ShowFrame(frame)
			UpdateAll(frame)
		elseif frame then
			HideFrame(frame)
			RestoreBlizzardFrame(info.blizzardFrame)
		end
	end
end

function UnitFrames:SetEnabled(enabled)
	self.db.enabled = enabled
	self:Apply()
	if self.enableCheck then
		self.enableCheck:SetChecked(enabled)
	end
	if InCombatLockdown() then
		self:Print("in combat; the change is applied when combat ends.")
	end
end

-- The health bar isn't protected, so this works in combat too.
function UnitFrames:SetBarTexture(key)
	self.db.barTexture = key
	local path = GetBarTexturePath(key)
	for _, frame in pairs(frames) do
		frame.HealthBar:SetStatusBarTexture(path)
		UpdateColor(frame)
	end
end

function UnitFrames:SetLocked(locked)
	self.db.locked = locked
	self:Apply()
end

function UnitFrames:ResetPositions()
	self.db.positions.player = nil
	self.db.positions.target = nil
	self:Apply()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

function UnitFrames:OnLogin()
	self:Apply()
end

function UnitFrames:OnUnitHealth(event, unit)
	ForUnit(unit, function(frame)
		UpdateHealth(frame, true)
		UpdateColor(frame)
	end)
end

function UnitFrames:OnUnitLevel(event, unit)
	ForUnit(unit or "player", UpdateLevel)
end

function UnitFrames:OnUnitName(event, unit)
	ForUnit(unit, UpdateName)
end

function UnitFrames:OnUnitFaction(event, unit)
	ForUnit(unit, UpdateColor)
end

function UnitFrames:OnTargetChanged()
	for _, key in ipairs({ "target", "targettarget" }) do
		if frames[key] then
			UpdateAll(frames[key])
		end
	end
end

-- The target picked a new target.
function UnitFrames:OnUnitTarget(event, unit)
	if unit == "target" and frames.targettarget then
		UpdateAll(frames.targettarget)
	end
end

-- PLAYER_REGEN_DISABLED / ENABLED: entering or leaving combat.
function UnitFrames:OnCombatChanged()
	if frames.player then
		UpdateCombat(frames.player)
	end
end

function UnitFrames:OnCombatEnded()
	if pendingApply and self.db then
		self:Apply()
	end
end

function UnitFrames:OnScaleChanged()
	-- These events can fire before ADDON_LOADED has given us our settings.
	if self.db and self.db.enabled then
		self:Apply()
	end
end

UnitFrames:RegisterEvent("UNIT_HEALTH", "OnUnitHealth")
UnitFrames:RegisterEvent("UNIT_MAXHEALTH", "OnUnitHealth")
UnitFrames:RegisterEvent("UNIT_CONNECTION", "OnUnitHealth")
UnitFrames:RegisterEvent("UNIT_LEVEL", "OnUnitLevel")
UnitFrames:RegisterEvent("PLAYER_LEVEL_UP", function(module)
	module:OnUnitLevel(nil, "player")
end)
UnitFrames:RegisterEvent("UNIT_NAME_UPDATE", "OnUnitName")
UnitFrames:RegisterEvent("UNIT_FACTION", "OnUnitFaction")
UnitFrames:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
UnitFrames:RegisterEvent("UNIT_TARGET", "OnUnitTarget")
UnitFrames:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")
UnitFrames:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatChanged")
UnitFrames:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatChanged")
UnitFrames:RegisterEvent("UI_SCALE_CHANGED", "OnScaleChanged")
UnitFrames:RegisterEvent("DISPLAY_SIZE_CHANGED", "OnScaleChanged")

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
local function CreateSlider(module, parent, anchor, labelText, key, range)
	local label = CreateLabel(parent, labelText)
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -18)
	label:SetWidth(110)

	local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("LEFT", label, "RIGHT", 8, 0)
	slider:SetSize(200, 20)
	slider:Init(module.db[key], range[1], range[2], range[3], {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(value)
			return string.format("%d", value)
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

function UnitFrames:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Unit Frames", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)

	local enableCheck = CreateCheck(page, "Use custom player and target frames", self.db.enabled, function(checked)
		module:SetEnabled(checked)
	end)
	enableCheck:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -4, -10)
	self.enableCheck = enableCheck

	local lockCheck = CreateCheck(page, "Lock frames (untick to drag them; the target frame shows a preview)", self.db.locked, function(checked)
		module:SetLocked(checked)
	end)
	lockCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, 2)
	self.lockCheck = lockCheck

	local sliderAnchor = CreateFrame("Frame", nil, page)
	sliderAnchor:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 4, 0)
	sliderAnchor:SetSize(1, 1)

	local _, widthLabel = CreateSlider(self, page, sliderAnchor, "Width", "width", { 120, 400, 28 })
	local _, heightLabel = CreateSlider(self, page, widthLabel, "Height", "height", { 20, 80, 30 })
	local _, textLabel = CreateSlider(self, page, heightLabel, "Text size", "textSize", { 8, 24, 16 })
	local _, buffLabel = CreateSlider(self, page, textLabel, "Buff size", "buffSize", { 12, 40, 14 })

	local textureLabel = CreateLabel(page, "Bar texture")
	textureLabel:SetPoint("TOPLEFT", buffLabel, "BOTTOMLEFT", 0, -18)
	textureLabel:SetWidth(110)

	local textureDropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
	textureDropdown:SetPoint("LEFT", textureLabel, "RIGHT", 8, 0)
	textureDropdown:SetWidth(200)
	textureDropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetScrollMode(300)
		local function IsSelected(key)
			return module.db.barTexture == key
		end
		local function SetSelected(key)
			module:SetBarTexture(key)
		end
		for _, texture in ipairs(BAR_TEXTURES) do
			rootDescription:CreateRadio(texture.name, IsSelected, SetSelected, texture.key)
		end

		local media = GetSharedMedia()
		if media then
			rootDescription:CreateDivider()
			rootDescription:CreateTitle("Shared media")
			for _, name in ipairs(media:List("statusbar")) do
				rootDescription:CreateRadio(name, IsSelected, SetSelected, name)
			end
		end
	end)
	self.textureDropdown = textureDropdown

	local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	reset:SetPoint("TOPLEFT", textureLabel, "BOTTOMLEFT", 0, -18)
	reset:SetSize(140, 22)
	reset:SetText("Reset positions")
	reset:SetScript("OnClick", function()
		module:ResetPositions()
	end)

	local note = CreateLabel(page, "", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -12)
	note:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	note:SetJustifyV("TOP")
	note:SetText("Border, font and background follow the Action Bars settings. "
		.. "Changes made in combat are applied when combat ends. "
		.. "Type |cffffd100/adam framestyle|r to switch the frames on or off.")
end

function UnitFrames:OnPageShown(page)
	self.enableCheck:SetChecked(self.db.enabled)
	self.lockCheck:SetChecked(self.db.locked)
	-- The shared media list can grow after login.
	self.textureDropdown:GenerateMenu()
end
