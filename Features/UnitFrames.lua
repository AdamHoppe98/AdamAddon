local addonName, ns = ...

-- Replaces Blizzard's player and target frames with portrait frames: a round portrait
-- in a ring of the unit's colour, with a health bar tucked behind it.
-- Player: portrait left, name above the bar, "value | %" right, level bottom left.
-- Target: mirrored, "% | value" left with a combat icon, power bar below, debuffs above,
-- level under the portrait coloured by difficulty, gold dragon for elites and bosses,
-- silver for rares. Target of target: a small bar with the name, right of the target.
--
-- The frames are secure unit buttons (click to target, right-click for the menu), so
-- showing, hiding, moving and resizing them only happens out of combat. Health and
-- power values are secret in WoW Forever; they go straight into the bars and the font
-- strings, which accept secrets, and are never compared or calculated with.

local UnitFrames = ns:RegisterModule("UnitFrames", {
	title = "Unit Frames",
	order = 20,
	defaults = {
		enabled = true,
		locked = true,
		width = 220,        -- health bar, including the part tucked behind the portrait
		barHeight = 20,
		portraitSize = 50,
		powerHeight = 6,
		textSize = 12,
		debuffSize = 22,
		barTexture = "melli", -- key in BAR_TEXTURES, or a LibSharedMedia statusbar name
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
		portraitSide = "LEFT",
		showCombat = true,
		defaultPosition = { "CENTER", "CENTER", -260, -160 },
	},
	target = {
		unit = "target",
		frameName = "AdamAddonTargetFrame",
		blizzardFrame = "TargetFrame",
		portraitSide = "RIGHT",
		percentFirst = true, -- "52.7% | 29"
		colorLevel = true,
		showCombat = true,
		showPower = true,
		showDebuffs = true,
		showClassification = true,
		placeholderName = "Target",
		defaultPosition = { "CENTER", "CENTER", 260, -160 },
	},
	-- Blizzard's own target-of-target frame lives inside TargetFrame, so it's already hidden.
	targettarget = {
		unit = "targettarget",
		frameName = "AdamAddonTargetTargetFrame",
		compact = true,
		placeholderName = "Target of target",
		anchorTo = "target",
	},
}
local UNIT_ORDER = { "player", "target", "targettarget" } -- target before the frame anchored to it

-- Target of target size relative to the main bar, and how often it polls:
-- unit events don't fire for "targettarget".
local COMPACT_WIDTH_SCALE = 0.45
local COMPACT_HEIGHT_SCALE = 0.8
local COMPACT_GAP = 4
local POLL_INTERVAL = 0.25

-- Our own textures are plain grey levels in Media\BarTextures, tinted by the bar colour.
-- Melli comes from ElvUI.
local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\BarTextures\\"
local BAR_TEXTURES = {
	{ key = "melli", name = "Melli", path = MEDIA .. "Melli.tga" },
	{ key = "flat", name = "Flat", path = MEDIA .. "Flat.tga" },
	{ key = "smooth", name = "Smooth", path = MEDIA .. "Smooth.tga" },
	{ key = "glass", name = "Glass", path = MEDIA .. "Glass.tga" },
	{ key = "stripes", name = "Stripes", path = MEDIA .. "Stripes.tga" },
	{ key = "blizzard", name = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
	{ key = "raid", name = "Blizzard raid", path = "Interface\\RaidFrame\\UI-RaidFrame-HealthBar" },
	{ key = "skills", name = "Blizzard skills", path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
	{ key = "targetfill", name = "Blizzard target", path = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill" },
}
local DEFAULT_BAR_TEXTURE = MEDIA .. "Melli.tga"
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local ICON_CROP = 0.08
local COMBAT_ICON_ATLAS = "UI-HUD-UnitFrame-Player-CombatIcon" -- same art as Blizzard's player frame
local PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MAX_DEBUFFS = 16

-- The dragon art from Blizzard's Camelot target frame (Camelot/TargetFrameUtils.lua).
-- x, y place the art's top-right corner the way Blizzard does: from its frame's corner,
-- where the 58 px portrait sits 26 px in and 19 px down. Scaled to our portrait size.
local BLIZZARD_PORTRAIT_SIZE = 58
local BLIZZARD_PORTRAIT_INSET_X = 26
local BLIZZARD_PORTRAIT_INSET_Y = 19
local CLASSIFICATION_ART = {
	boss = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", x = 11, y = -4 },
	rare = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged", x = 8, y = -7 },
	elite = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold", x = 0, y = 1 },
}

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

local function GetPowerColor(powerType, powerToken)
	local color = (powerToken and PowerBarColor[powerToken]) or PowerBarColor[powerType]
	if color then
		return color.r, color.g, color.b
	end
	return 0, 0.55, 1
end

-- nil for normal units.
local function GetClassificationArt(unit)
	local classification = UnitClassification(unit)
	if IsSecret(classification) then
		return nil
	end
	if UnitIsBossMob(unit) or classification == "worldboss" then
		return CLASSIFICATION_ART.boss
	elseif classification == "rare" or classification == "rareelite" then
		return CLASSIFICATION_ART.rare
	elseif classification == "elite" then
		return CLASSIFICATION_ART.elite
	end
	return nil
end

---------------------------------------------------------------------------
-- Updating one frame
---------------------------------------------------------------------------

local function GetInterpolation(smooth)
	return smooth and Enum.StatusBarInterpolation.ExponentialEaseOut
		or Enum.StatusBarInterpolation.Immediate
end

local function SetHealthText(frame, text)
	if frame.HealthText then
		frame.HealthText:SetText(text)
	end
end

-- smooth: glide to the new value (the engine animates it, so secret values work).
-- Not smooth: jump, used when the frame starts showing a different unit.
local function UpdateHealth(frame, smooth)
	local unit = frame.unit
	local bar = frame.HealthBar

	if not UnitExists(unit) then
		-- Only seen while the frames are unlocked for moving.
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		SetHealthText(frame, "100%")
		return
	end

	if UnitIsDeadOrGhost(unit) then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0, GetInterpolation(smooth))
		SetHealthText(frame, "Dead")
		return
	end

	if not UnitIsConnected(unit) then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		SetHealthText(frame, "Offline")
		return
	end

	-- Secret values: passed through, never compared.
	bar:SetMinMaxValues(0, UnitHealthMax(unit))
	bar:SetValue(UnitHealth(unit), GetInterpolation(smooth))
	if frame.HealthText then
		local value = AbbreviateLargeNumbers(UnitHealth(unit))
		local percent = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)
		if frame.info.percentFirst then
			frame.HealthText:SetFormattedText("%.1f%% | %s", percent, value)
		else
			frame.HealthText:SetFormattedText("%s | %.0f%%", value, percent)
		end
	end
end

local function UpdatePower(frame, smooth)
	local box = frame.PowerBox
	if not box then
		return
	end
	local unit = frame.unit
	local bar = box.Bar

	if not UnitExists(unit) then
		box:Show()
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		bar:SetStatusBarColor(GetPowerColor(Enum.PowerType.Mana, "MANA"))
		frame.PowerText:SetText("")
		return
	end

	-- Blizzard hides the power bar of "minus" mobs (critters and the like) too.
	local classification = UnitClassification(unit)
	if not IsSecret(classification) and classification == "minus" then
		box:Hide()
		return
	end
	box:Show()

	local powerType, powerToken = UnitPowerType(unit)
	local r, g, b = GetPowerColor(powerType, powerToken)
	bar:SetStatusBarColor(r, g, b)
	bar:SetMinMaxValues(0, UnitPowerMax(unit, powerType))
	bar:SetValue(UnitPower(unit, powerType), GetInterpolation(smooth))
	frame.PowerText:SetFormattedText("%d", UnitPower(unit, powerType))
	frame.PowerText:SetTextColor(r, g, b)
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
	if frame.Ring then
		frame.Ring:SetColorTexture(r, g, b, 1)
	end
end

local function UpdateName(frame)
	if UnitExists(frame.unit) then
		frame.NameText:SetText(UnitName(frame.unit))
	else
		frame.NameText:SetText(frame.info.placeholderName or "")
	end
end

-- Player: white. Target: coloured by difficulty when it can be attacked (grey, green,
-- yellow, orange, red), Blizzard's gold otherwise.
local function UpdateLevel(frame)
	local text = frame.LevelText
	if not text then
		return
	end
	local unit = frame.unit
	if not UnitExists(unit) then
		text:SetText("")
		return
	end

	local level = frame.info.colorLevel and UnitEffectiveLevel(unit) or UnitLevel(unit)
	if IsSecret(level) then
		text:SetText(level)
		text:SetTextColor(1, 1, 1)
		return
	end
	if not level or level <= 0 then
		-- Too high to tell.
		text:SetText("??")
		text:SetTextColor(1, 0.1, 0.1)
		return
	end

	text:SetText(tostring(level))
	local r, g, b = 1, 1, 1
	if frame.info.colorLevel then
		if UnitCanAttack("player", unit) then
			local difficulty = C_PlayerInfo.GetContentDifficultyCreatureForPlayer(unit)
			local color = difficulty and not IsSecret(difficulty) and GetDifficultyColor(difficulty)
			if color then
				r, g, b = color.r, color.g, color.b
			end
		else
			r, g, b = 1, 0.82, 0
		end
	end
	text:SetTextColor(r, g, b)
end

local function UpdatePortrait(frame)
	local portrait = frame.Portrait
	if not portrait then
		return
	end
	if UnitExists(frame.unit) then
		SetPortraitTexture(portrait, frame.unit)
	else
		portrait:SetColorTexture(0.1, 0.1, 0.1, 1)
	end
end

local function UpdateClassification(frame)
	local dragon = frame.Dragon
	if not dragon then
		return
	end
	local art = UnitExists(frame.unit) and GetClassificationArt(frame.unit)
	local info = art and C_Texture.GetAtlasInfo(art.atlas)
	if not info then
		dragon:Hide()
		return
	end

	local scale = UnitFrames.db.portraitSize / BLIZZARD_PORTRAIT_SIZE
	dragon:SetAtlas(art.atlas)
	dragon:SetSize(info.width * scale, info.height * scale)
	dragon:ClearAllPoints()
	dragon:SetPoint("TOPRIGHT", frame.PortraitFrame, "TOPRIGHT",
		(art.x + BLIZZARD_PORTRAIT_INSET_X) * scale, (art.y + BLIZZARD_PORTRAIT_INSET_Y) * scale)
	dragon:Show()
end

local function UpdateCombat(frame)
	if frame.CombatIcon then
		frame.CombatIcon:SetShown(UnitExists(frame.unit) and UnitAffectingCombat(frame.unit))
	end
end

-- smooth is only passed by the target-of-target poll; a new unit always snaps.
local function UpdateAll(frame, smooth)
	UpdateHealth(frame, smooth)
	UpdatePower(frame, smooth)
	UpdateColor(frame)
	UpdateName(frame)
	UpdateLevel(frame)
	UpdatePortrait(frame)
	UpdateClassification(frame)
	UpdateCombat(frame)
	if frame.Debuffs then
		frame.Debuffs:UpdateAllAuras()
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

-- A status bar on a background, inside the black border shared with the action bars.
local function CreateBox(frame)
	local box = CreateFrame("Frame", nil, frame)
	box.Background = box:CreateTexture(nil, "BACKGROUND")
	box.Background:SetAllPoints()

	box.Bar = CreateFrame("StatusBar", nil, box)
	box.Bar:SetStatusBarTexture(GetBarTexturePath(UnitFrames.db.barTexture))

	local borderFrame = CreateFrame("Frame", nil, box)
	borderFrame:SetAllPoints()
	borderFrame:SetFrameLevel(box.Bar:GetFrameLevel() + 1)
	box.Border = {
		TOP = CreateLine(borderFrame),
		BOTTOM = CreateLine(borderFrame),
		LEFT = CreateLine(borderFrame),
		RIGHT = CreateLine(borderFrame),
	}

	table.insert(frame.Boxes, box)
	return box
end

local function LayoutBox(box, border)
	box.Background:SetColorTexture(0, 0, 0, GetBackgroundAlpha())

	local lines = box.Border
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

	box.Bar:ClearAllPoints()
	box.Bar:SetPoint("TOPLEFT", border, -border)
	box.Bar:SetPoint("BOTTOMRIGHT", -border, border)
end

-- A texture cut to a circle.
local function CreateCircle(parent, layer, subLevel)
	local texture = parent:CreateTexture(nil, layer, nil, subLevel)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
	return texture
end

-- Called once per debuff button by Blizzard's aura container.
local function InitializeAuraButton(button)
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 1)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", -1, 1)
	icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	button:SetIcon(icon)

	-- The countdown numbers are the time left, as on the screenshots.
	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:ClearAllPoints()
	cooldown:SetAllPoints(icon)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(false)
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

local function CreateDebuffs(frame)
	local debuffs = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
	debuffs:AddAuraGroup("debuffs", "HARMFUL", {
		maxFrameCount = MAX_DEBUFFS,
		initializeFrame = InitializeAuraButton,
	})
	debuffs:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
	debuffs:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
	debuffs:SetUnit(frame.unit)
	return debuffs
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
	frame.Boxes = {}
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

	local baseLevel = frame:GetFrameLevel()

	frame.HealthBox = CreateBox(frame)
	frame.HealthBar = frame.HealthBox.Bar
	if info.showPower then
		frame.PowerBox = CreateBox(frame)
	end

	-- Texts sit on a layer above the bars; the portrait above that, its level text on top.
	frame.Overlay = CreateFrame("Frame", nil, frame)
	frame.Overlay:SetAllPoints()
	frame.Overlay:SetFrameLevel(baseLevel + 5)

	frame.NameText = CreateText(frame.Overlay, info.portraitSide == "RIGHT" and "RIGHT" or "LEFT")
	if not info.compact then
		frame.HealthText = CreateText(frame.Overlay, info.percentFirst and "LEFT" or "RIGHT")
	end
	if info.showPower then
		frame.PowerText = CreateText(frame.Overlay, "CENTER")
	end
	if info.showCombat then
		frame.CombatIcon = frame.Overlay:CreateTexture(nil, "OVERLAY")
		frame.CombatIcon:SetAtlas(COMBAT_ICON_ATLAS)
		frame.CombatIcon:Hide()
	end

	if info.portraitSide then
		local portraitFrame = CreateFrame("Frame", nil, frame)
		portraitFrame:SetFrameLevel(baseLevel + 7)
		frame.PortraitFrame = portraitFrame
		frame.RingEdge = CreateCircle(portraitFrame, "BACKGROUND", 0)
		frame.RingEdge:SetColorTexture(0, 0, 0, 1)
		frame.Ring = CreateCircle(portraitFrame, "BACKGROUND", 1)
		frame.Portrait = CreateCircle(portraitFrame, "ARTWORK", 0)
		if info.showClassification then
			frame.Dragon = portraitFrame:CreateTexture(nil, "OVERLAY")
			frame.Dragon:Hide()
		end

		local levelLayer = CreateFrame("Frame", nil, frame)
		levelLayer:SetAllPoints(portraitFrame)
		levelLayer:SetFrameLevel(baseLevel + 9)
		frame.LevelText = CreateText(levelLayer, "CENTER")
	end

	if info.showDebuffs then
		frame.Debuffs = CreateDebuffs(frame)
	end

	frames[key] = frame
	return frame
end

local function LayoutCompact(frame, border, fontPath, outline, smallSize)
	local db = UnitFrames.db
	frame:SetSize(math.floor(db.width * COMPACT_WIDTH_SCALE + 0.5),
		math.max(math.floor(db.barHeight * COMPACT_HEIGHT_SCALE + 0.5), 8))

	local box = frame.HealthBox
	box:ClearAllPoints()
	box:SetAllPoints()
	LayoutBox(box, border)

	frame.NameText:ClearAllPoints()
	frame.NameText:SetPoint("LEFT", box.Bar, "LEFT", 3, 0)
	frame.NameText:SetPoint("RIGHT", box.Bar, "RIGHT", -3, 0)
	frame.NameText:SetFont(fontPath, smallSize, outline)
end

local function LayoutFrame(frame)
	local db = UnitFrames.db
	local info = frame.info
	local border = GetBorderSize(frame)
	local fontPath, outline = GetFont()
	local textSize = db.textSize
	local smallSize = math.max(textSize - 2, 6)

	if info.compact then
		LayoutCompact(frame, border, fontPath, outline, smallSize)
	else
		local size = db.portraitSize
		local half = size / 2
		local mirrored = info.portraitSide == "RIGHT"
		local side = info.portraitSide
		local otherSide = mirrored and "LEFT" or "RIGHT"
		local visibleWidth = db.width - half -- the bar outside the portrait
		frame:SetSize(half + db.width, size)

		-- Portrait: black edge, coloured ring, picture.
		local portraitFrame = frame.PortraitFrame
		portraitFrame:ClearAllPoints()
		portraitFrame:SetPoint(side, frame, side, 0, 0)
		portraitFrame:SetSize(size, size)
		local ringWidth = math.max(2, math.floor(size * 0.06 + 0.5))
		frame.RingEdge:ClearAllPoints()
		frame.RingEdge:SetAllPoints(portraitFrame)
		frame.RingEdge:SetShown(border > 0)
		frame.Ring:ClearAllPoints()
		frame.Ring:SetPoint("TOPLEFT", border, -border)
		frame.Ring:SetPoint("BOTTOMRIGHT", -border, border)
		local inset = border + ringWidth
		frame.Portrait:ClearAllPoints()
		frame.Portrait:SetPoint("TOPLEFT", inset, -inset)
		frame.Portrait:SetPoint("BOTTOMRIGHT", -inset, inset)

		-- Health bar from the portrait's centre to the far end, centred on the portrait.
		local box = frame.HealthBox
		box:ClearAllPoints()
		box:SetPoint(side, portraitFrame, "CENTER", 0, 0)
		box:SetPoint(otherSide, frame, otherSide, 0, 0)
		box:SetHeight(db.barHeight)
		LayoutBox(box, border)

		local direction = mirrored and -1 or 1 -- away from the portrait
		frame.HealthText:ClearAllPoints()
		frame.HealthText:SetPoint(otherSide, box.Bar, otherSide, -4 * direction, 0)
		frame.HealthText:SetFont(fontPath, textSize, outline)

		if frame.CombatIcon then
			-- Next to the health text, on the side facing the portrait.
			local iconSize = smallSize + 4
			frame.CombatIcon:SetSize(iconSize, iconSize)
			frame.CombatIcon:ClearAllPoints()
			frame.CombatIcon:SetPoint(otherSide, frame.HealthText, side, -2 * direction, 0)
		end

		-- Name above the bar, starting next to the portrait.
		frame.NameText:ClearAllPoints()
		frame.NameText:SetPoint("BOTTOM" .. side, box, "TOP" .. side, (half + 4) * direction, 2)
		frame.NameText:SetWidth(visibleWidth * (info.showDebuffs and 0.55 or 0.9))
		frame.NameText:SetFont(fontPath, textSize, outline)

		-- Level on the portrait's bottom edge: the player's bottom left, the target's centred.
		frame.LevelText:ClearAllPoints()
		if mirrored then
			frame.LevelText:SetPoint("CENTER", portraitFrame, "BOTTOM", 0, size * 0.08)
		else
			frame.LevelText:SetPoint("CENTER", portraitFrame, "BOTTOMLEFT", size * 0.15, size * 0.15)
		end
		frame.LevelText:SetFont(fontPath, textSize + 1, outline)

		if frame.PowerBox then
			local powerBox = frame.PowerBox
			powerBox:ClearAllPoints()
			powerBox:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -1)
			powerBox:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -1)
			powerBox:SetHeight(db.powerHeight + 2 * border)
			LayoutBox(powerBox, border)
			-- Centred on the part outside the portrait.
			frame.PowerText:ClearAllPoints()
			frame.PowerText:SetPoint("CENTER", powerBox, "CENTER", size / 4 * direction, 0)
			frame.PowerText:SetFont(fontPath, smallSize, outline)
		end

		if frame.Debuffs then
			-- Above the bar at the far end, leaving room for the name next to the portrait.
			frame.Debuffs:ClearAllPoints()
			frame.Debuffs:SetPoint("BOTTOM" .. otherSide, box, "TOP" .. otherSide, 0, 3)
			frame.Debuffs:SetFlowLayoutMaximumLineSize(visibleWidth * 0.45)
			frame.Debuffs:SetAuraGroupLayout("debuffs", {
				elementWidth = db.debuffSize,
				elementHeight = db.debuffSize,
				elementSpacing = 2,
				lineSpacing = 2,
			})
		end
	end

	frame:ClearAllPoints()
	local anchorFrame = info.anchorTo and frames[info.anchorTo]
	if anchorFrame then
		-- Right of the target's portrait, level with its health bar.
		frame:SetPoint("LEFT", anchorFrame, "RIGHT", COMPACT_GAP, 0)
	else
		local position = db.positions[frame.key] or info.defaultPosition
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

-- The bars aren't protected, so this works in combat too.
function UnitFrames:SetBarTexture(key)
	self.db.barTexture = key
	local path = GetBarTexturePath(key)
	for _, frame in pairs(frames) do
		for _, box in ipairs(frame.Boxes) do
			box.Bar:SetStatusBarTexture(path)
		end
		UpdateColor(frame)
		UpdatePower(frame)
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

-- Layout 2 (portraits) switched to the Melli texture and replaced two settings.
function UnitFrames:OnInit()
	if (self.db.layoutVersion or 1) < 2 then
		self.db.barTexture = "melli"
		self.db.height = nil
		self.db.buffSize = nil
		self.db.layoutVersion = 2
	end
end

function UnitFrames:OnLogin()
	self:Apply()
end

function UnitFrames:OnUnitHealth(event, unit)
	ForUnit(unit, function(frame)
		UpdateHealth(frame, true)
		UpdateColor(frame)
	end)
end

function UnitFrames:OnUnitPower(event, unit)
	ForUnit(unit, function(frame)
		UpdatePower(frame, true)
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

function UnitFrames:OnUnitPortrait(event, unit)
	ForUnit(unit, UpdatePortrait)
end

function UnitFrames:OnUnitClassification(event, unit)
	ForUnit(unit, function(frame)
		UpdateClassification(frame)
		UpdatePower(frame)
	end)
end

-- UNIT_FLAGS fires when a unit enters or leaves combat.
function UnitFrames:OnUnitFlags(event, unit)
	ForUnit(unit, UpdateCombat)
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
UnitFrames:RegisterEvent("UNIT_POWER_UPDATE", "OnUnitPower")
UnitFrames:RegisterEvent("UNIT_MAXPOWER", "OnUnitPower")
UnitFrames:RegisterEvent("UNIT_DISPLAYPOWER", "OnUnitPower")
UnitFrames:RegisterEvent("UNIT_LEVEL", "OnUnitLevel")
UnitFrames:RegisterEvent("PLAYER_LEVEL_UP", function(module)
	module:OnUnitLevel(nil, "player")
end)
UnitFrames:RegisterEvent("UNIT_NAME_UPDATE", "OnUnitName")
UnitFrames:RegisterEvent("UNIT_FACTION", "OnUnitFaction")
UnitFrames:RegisterEvent("UNIT_PORTRAIT_UPDATE", "OnUnitPortrait")
UnitFrames:RegisterEvent("UNIT_MODEL_CHANGED", "OnUnitPortrait")
UnitFrames:RegisterEvent("UNIT_CLASSIFICATION_CHANGED", "OnUnitClassification")
UnitFrames:RegisterEvent("UNIT_FLAGS", "OnUnitFlags")
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
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
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

	local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	reset:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -2)
	reset:SetSize(130, 22)
	reset:SetText("Reset positions")
	reset:SetScript("OnClick", function()
		module:ResetPositions()
	end)

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

	local _, widthLabel = CreateSlider(self, page, sliderAnchor, "Bar width", "width", { 120, 400, 28 })
	local _, heightLabel = CreateSlider(self, page, widthLabel, "Bar height", "barHeight", { 10, 50, 40 })
	local _, portraitLabel = CreateSlider(self, page, heightLabel, "Portrait size", "portraitSize", { 30, 90, 60 })
	local _, powerLabel = CreateSlider(self, page, portraitLabel, "Power bar height", "powerHeight", { 2, 16, 14 })
	local _, textLabel = CreateSlider(self, page, powerLabel, "Text size", "textSize", { 8, 24, 16 })
	local _, debuffLabel = CreateSlider(self, page, textLabel, "Debuff size", "debuffSize", { 12, 40, 14 })

	local textureLabel = CreateLabel(page, "Bar texture")
	textureLabel:SetPoint("TOPLEFT", debuffLabel, "BOTTOMLEFT", 0, -14)
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

	local note = CreateLabel(page, "", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", textureLabel, "BOTTOMLEFT", 0, -16)
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
