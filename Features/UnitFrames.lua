local addonName, ns = ...

-- Replaces Blizzard's player and target frames with portrait frames: a round portrait
-- in a ring of the unit's colour, with a health bar tucked behind it. Texts sit on the
-- bar's borders.
-- Player: portrait left, name on the top border left, "value | %" on the bottom border
-- right. Target: mirrored, "% | value" bottom left with a combat icon and a small power
-- bar after it, buffs and debuffs above (debuff borders by dispel type), a cast bar
-- below, gold dragon for elites and bosses, silver for rares.
-- Both: level centred on the portrait's bottom edge (the target's coloured by difficulty).
-- Target of target: a small bar with the name, right of the target.
--
-- The frames are secure unit buttons (click to target, right-click for the menu), so
-- showing, hiding, moving and resizing them only happens out of combat. Health and
-- power values are secret in restricted contexts; they go straight into the bars and
-- the font strings, which accept secrets, and are only compared after a secret check.

local UnitFrames = ns:RegisterModule("UnitFrames", {
	title = "Unit Frames",
	order = 20,
	defaults = {
		enabled = true,
		incomingHeals = true, -- incoming heals on the player's and target's health bars
		width = 220,       -- health bar, including the part tucked behind the portrait
		barHeight = 20,
		totWidth = 99,      -- target of target bar
		totHeight = 16,
		totX = 0,           -- offset from its place right of the target's portrait
		totY = 0,
		portraitSize = 50,
		portraitX = 0,      -- + moves the portrait out, away from the bar; - further over it
		powerHeight = 6,    -- target power bar
		powerWidth = 55,
		powerX = 100,       -- from the far end of the health bar's bottom border
		powerY = 0,
		powerTextPosition = "right", -- key in POWER_TEXT_POSITIONS
		powerTextGrowth = "auto",    -- key in POWER_TEXT_GROWTH
		powerTextX = 0,
		powerTextY = 0,
		druidManaOnPlayer = false, -- druid mana in cat/bear form on the player frame (set on the Power Bar page)
		playerManaWidth = 55,       -- that bar; same settings as the target power bar's
		playerManaHeight = 6,
		playerManaX = 100,          -- from the far (right) end of the player's bottom border
		playerManaY = 0,
		playerManaBackgroundOpacity = 40,
		playerManaTextPosition = "left", -- the health text and combat icon are to its right
		playerManaTextGrowth = "auto",
		playerManaTextX = 0,
		playerManaTextY = 0,
		borderSize = 1,     -- 0 = no border
		backgroundOpacity = 40,
		powerBackgroundOpacity = 40, -- target power bar
		combatIconSize = 14,
		combatPlayerX = 88, -- icon centre, from the far end of the bar's bottom border
		combatPlayerY = 0,
		combatTargetX = 88,
		combatTargetY = 0,
		castBar = true,     -- target cast bar
		playerCastBar = true, -- the player's, like the target's, same settings; hides Blizzard's
		playerCastDetached = false, -- its own size and place instead of under the player frame
		playerCastWidth = 220,
		playerCastHeight = 18,
		playerCastPosition = { 0, -180 }, -- centre offset from the screen centre
		castColors = { target = {}, player = {} }, -- see CAST_COLOR_DEFAULTS
		castMatchWidth = true, -- as wide as the target health bar (outside the portrait)
		castWidth = 187,    -- used when castMatchWidth is off
		castHeight = 14,
		castIcon = true,
		castBehindPortrait = false, -- where they overlap: behind the portrait, else in front
		castX = 0,          -- from the health bar's bottom corner at the far end
		castY = -10,
		npcColors = {},     -- [key in NPC_COLOR_TYPES] = { r, g, b }; missing = Blizzard's colour
		textSize = 12,
		levelOffsetY = 0,   -- texts on the borders, moved up (+) or down (-) from the line
		nameOffsetY = 0,
		healthOffsetY = 0,
		buffShow = true,    -- target buffs and debuffs (the Buffs & Debuffs page)
		buffPosition = "above", -- key in AURA_POSITIONS
		buffSize = 22,
		buffTextSize = 10,  -- time left and stack count on the icons
		buffMax = 16,
		buffX = 0,
		buffY = 0,
		debuffShow = true,
		debuffPosition = "above",
		debuffSize = 22,
		debuffTextSize = 10,
		debuffMax = 16,
		debuffX = 0,
		debuffY = 0,
		debuffOnlyMine = false,
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
		hideName = true,
		showCastBar = true,
		showPower = true,     -- druid mana in cat and bear form, when switched on
		druidMana = true,
		powerPrefix = "playerMana",
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
		powerPrefix = "power",
		showAuras = true, -- buffs and debuffs above the bar
		showClassification = true,
		showCastBar = true,
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

-- Target of target gap to the target's portrait, and how often it polls:
-- unit events don't fire for "targettarget".
local COMPACT_GAP = 4
local POLL_INTERVAL = 0.25

-- Where the target's power value sits, relative to its bar.
local POWER_TEXT_POSITIONS = {
	{ key = "right", name = "Right of the bar" },
	{ key = "left", name = "Left of the bar" },
	{ key = "center", name = "On the bar" },
	{ key = "hidden", name = "Hidden" },
}

-- Which way the power value gets longer: the opposite edge stays put. "auto" grows away
-- from the bar (or both ways when on it).
local POWER_TEXT_GROWTH = {
	{ key = "auto", name = "Away from the bar" },
	{ key = "right", name = "To the right" },
	{ key = "left", name = "To the left" },
	{ key = "center", name = "Both ways" },
}

-- Point on the bar the value hangs off, and the gap to it.
-- Shared with the Power Bar page, which sets up the player's druid mana bar.
ns.PowerTextPositions = POWER_TEXT_POSITIONS
ns.PowerTextGrowth = POWER_TEXT_GROWTH

local POWER_TEXT_ANCHORS = {
	right = { point = "RIGHT", x = 3, grow = "LEFT" },
	left = { point = "LEFT", x = -3, grow = "RIGHT" },
	center = { point = "CENTER", x = 0, grow = "CENTER" },
}
-- Growth key -> the text's own point that stays put.
local POWER_TEXT_FIXED_POINT = { right = "LEFT", left = "RIGHT", center = "CENTER" }

-- Cast bar colours. The target's and the player's are set separately (castColors.target
-- / .player, [kind] = { r, g, b }); missing ones use these. The player's bar has no
-- "can't be interrupted" colour.
local CAST_COLOR_DEFAULTS = {
	cast = { 1, 0.7, 0 },
	channel = { 0.3, 0.7, 1 },
	uninterruptible = { 0.6, 0.6, 0.6 },
}
local CAST_COLOR_KINDS = {
	target = {
		{ key = "cast", name = "Cast" },
		{ key = "channel", name = "Channel" },
		{ key = "uninterruptible", name = "Can't interrupt" },
	},
	player = {
		{ key = "cast", name = "Cast" },
		{ key = "channel", name = "Channel" },
	},
}
local CAST_PREVIEW_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local HEAL_COLOR = { 0.2, 1, 0.4, 0.55 } -- incoming heals, see-through green
local BLIZZARD_PLAYER_CAST_BAR = "PlayerCastingBarFrame" -- Blizzard_UIPanels_Game, [Family]\CastingBarFrame.xml

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
local MAX_AURAS = 16 -- per group (buffs, debuffs)

-- The dragon art from Blizzard's target frame. x, y place the art's top-right corner the
-- way Blizzard does: from its frame's corner, where the 58 px portrait sits 26 px in and
-- 19 px down (the same in both games). Scaled to our portrait size.
-- The atlases differ between the games, so each has its own offsets:
-- WoW Forever from Camelot/TargetFrameUtils.lua, retail from Mainline/TargetFrame.lua.
local BLIZZARD_PORTRAIT_SIZE = 58
local BLIZZARD_PORTRAIT_INSET_X = 26
local BLIZZARD_PORTRAIT_INSET_Y = 19
local IS_FOREVER = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
local CLASSIFICATION_ART
if IS_FOREVER then
	CLASSIFICATION_ART = {
		boss = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", x = 11, y = -4 },
		rare = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged", x = 8, y = -7 },
		elite = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold", x = 0, y = 1 },
	}
else
	CLASSIFICATION_ART = {
		boss = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", x = 8, y = -8 },
		rare = { atlas = "ui-hud-unitframe-target-portraiton-boss-rare-silver", x = -11, y = -8 },
		elite = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold", x = -11, y = -8 },
	}
end

local frames = {}           -- [key] = our frame
local blizzardParents = {}  -- [frame name] = original parent, while Blizzard's frame is hidden
local pendingApply = false

-- Blizzard's frames are parked under this hidden frame instead of being torn down,
-- so switching the feature off can give them back without a /reload.
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

---------------------------------------------------------------------------
-- Look: border, font, background, textures
---------------------------------------------------------------------------

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- Whole screen pixels, 0 when the border is switched off.
local function GetBorderSize(frame)
	local size = UnitFrames.db.borderSize
	if size <= 0 then
		return 0
	end
	return PixelUtil.GetNearestPixelSize(size, frame:GetEffectiveScale(), 1)
end

-- The addon's font (the Fonts page); Friz Quadrata for "Blizzard default".
local function GetFont()
	local path, outline = ns.GetFont()
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

-- The colour picked on the Power Bar page, or Blizzard's.
local function GetPowerColor(powerType, powerToken)
	if ns.GetCustomPowerColor and powerToken then
		local r, g, b = ns.GetCustomPowerColor(powerToken)
		if r then
			return r, g, b
		end
	end
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

-- Incoming heals: a bar that starts where the health fill ends. Blizzard's heal
-- prediction calculator clamps the amount to the missing health, so its fill never goes
-- past the end of the health bar; it's also a clipped child of the health bar, so not
-- even the moment while the health glides to a new value can push it outside. The amount
-- can be secret; it only goes into the bar.
local function UpdateHealPrediction(frame)
	local heal = frame.HealBar
	if not heal then
		return
	end
	local unit = frame.unit
	if not UnitFrames.db.incomingHeals or not UnitExists(unit) or UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
		heal:Hide()
		return
	end
	local calculator = frame.HealCalculator
	UnitGetDetailedHealPrediction(unit, "player", calculator)
	heal:SetMinMaxValues(0, UnitHealthMax(unit))
	heal:SetValue((calculator:GetIncomingHeals()))
	heal:Show()
end

-- smooth: glide to the new value (the engine animates it, so secret values work).
-- Not smooth: jump, used when the frame starts showing a different unit.
local function UpdateHealth(frame, smooth)
	local unit = frame.unit
	local bar = frame.HealthBar
	UpdateHealPrediction(frame)

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

-- The small power bars on the bottom border share their code and look: the target's
-- power (settings power...) and, when switched on, the player's druid mana in cat and
-- bear form (playerMana...). frame.PowerPrefix says which settings a frame uses.
local function GetPowerSetting(frame, name)
	return UnitFrames.db[frame.PowerPrefix .. name]
end

local function SetPowerShown(frame, shown)
	frame.PowerBox:SetShown(shown)
	frame.PowerText:SetShown(shown and GetPowerSetting(frame, "TextPosition") ~= "hidden")
end

-- Also asked by the Power Bar, which then leaves out its own druid mana bar.
function ns.IsDruidManaOnPlayerFrame()
	local db = UnitFrames.db
	return db ~= nil and db.enabled and db.druidManaOnPlayer
end

-- A druid in a form without mana (cat: energy, bear: rage).
local function IsDruidInForm()
	local _, classFile = UnitClass("player")
	if IsSecret(classFile) or classFile ~= "DRUID" then
		return false
	end
	local powerType = UnitPowerType("player")
	return not IsSecret(powerType) and powerType ~= Enum.PowerType.Mana
end

-- The player's druid mana, shown while in a form; also while the frames are unlocked
-- (on druids), so it can be placed.
local function UpdateDruidMana(frame, smooth)
	local unlocked = ns.IsUnlocked ~= nil and ns.IsUnlocked()
	if not UnitFrames.db.druidManaOnPlayer or not (IsDruidInForm() or (unlocked and select(2, UnitClass("player")) == "DRUID")) then
		SetPowerShown(frame, false)
		return
	end
	SetPowerShown(frame, true)

	local mana = Enum.PowerType.Mana
	local r, g, b = GetPowerColor(mana, "MANA")
	local bar = frame.PowerBox.Bar
	bar:SetStatusBarColor(r, g, b)
	bar:SetMinMaxValues(0, UnitPowerMax("player", mana))
	bar:SetValue(UnitPower("player", mana), GetInterpolation(smooth))
	frame.PowerText:SetFormattedText("%d", UnitPower("player", mana))
	frame.PowerText:SetTextColor(r, g, b)
end

-- Target: hidden when the target has none of its power (or no power at all), and for
-- "minus" mobs (critters and the like), as Blizzard does. Secret values can't be
-- checked, so the bar stays up while they are secret.
local function UpdatePower(frame, smooth)
	local box = frame.PowerBox
	if not box then
		return
	end
	if frame.info.druidMana then
		UpdateDruidMana(frame, smooth)
		return
	end
	local unit = frame.unit
	local bar = box.Bar

	if not UnitExists(unit) then
		SetPowerShown(frame, true)
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		bar:SetStatusBarColor(GetPowerColor(Enum.PowerType.Mana, "MANA"))
		frame.PowerText:SetText("")
		return
	end

	local classification = UnitClassification(unit)
	if not IsSecret(classification) and classification == "minus" then
		SetPowerShown(frame, false)
		return
	end

	local powerType, powerToken = UnitPowerType(unit)
	local power = UnitPower(unit, powerType)
	local maxPower = UnitPowerMax(unit, powerType)
	if (not IsSecret(power) and power <= 0) or (not IsSecret(maxPower) and maxPower <= 0) then
		SetPowerShown(frame, false)
		return
	end
	SetPowerShown(frame, true)

	local r, g, b = GetPowerColor(powerType, powerToken)
	bar:SetStatusBarColor(r, g, b)
	bar:SetMinMaxValues(0, maxPower)
	bar:SetValue(power, GetInterpolation(smooth))
	frame.PowerText:SetFormattedText("%d", power)
	frame.PowerText:SetTextColor(r, g, b)
end

-- NPC colours, by reaction to the player (1-2 hostile, 3 unfriendly, 4 neutral,
-- 5-8 friendly), plus mobs tapped by someone else. Players keep their class colour.
-- reaction: the one Blizzard's colour is taken from while no custom colour is set.
local NPC_COLOR_TYPES = {
	{ key = "hostile", name = "Hostile", reaction = 2 },
	{ key = "unfriendly", name = "Unfriendly", reaction = 3 },
	{ key = "neutral", name = "Neutral", reaction = 4 },
	{ key = "friendly", name = "Friendly", reaction = 5 },
	{ key = "tapped", name = "Tapped" },
}
local TAPPED_COLOR = { r = 0.5, g = 0.5, b = 0.5 }

local function GetReactionColorKey(reaction)
	if reaction <= 2 then
		return "hostile"
	elseif reaction == 3 then
		return "unfriendly"
	elseif reaction == 4 then
		return "neutral"
	end
	return "friendly"
end

-- The custom colour, or Blizzard's for that reaction (or the type's own reaction).
local function GetNPCColor(colorType, reaction)
	local custom = UnitFrames.db.npcColors[colorType.key]
	if custom then
		return custom[1], custom[2], custom[3]
	end
	local color = TAPPED_COLOR
	if colorType.reaction then
		color = FACTION_BAR_COLORS[reaction or colorType.reaction] or TAPPED_COLOR
	end
	return color.r, color.g, color.b
end

local function GetNPCColorType(key)
	for _, colorType in ipairs(NPC_COLOR_TYPES) do
		if colorType.key == key then
			return colorType
		end
	end
end

local function UpdateColor(frame)
	local unit = frame.unit
	local r, g, b = 0.5, 0.5, 0.5

	if not UnitExists(unit) then
		r, g, b = 0.2, 0.6, 0.2
	elseif UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
		-- Grey.
	elseif UnitIsTapDenied(unit) then
		r, g, b = GetNPCColor(GetNPCColorType("tapped"))
	elseif UnitIsPlayer(unit) then
		local _, classFile = UnitClass(unit)
		local color = classFile and not IsSecret(classFile) and C_ClassColor.GetClassColor(classFile)
		if color then
			r, g, b = color:GetRGB()
		end
	else
		local reaction = UnitReaction(unit, "player")
		if reaction and not IsSecret(reaction) then
			r, g, b = GetNPCColor(GetNPCColorType(GetReactionColorKey(reaction)), reaction)
		end
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

-- Shown regardless of combat while the Combat Icon page is open, to place it.
local previewCombatIcon = false

local function UpdateCombat(frame)
	if frame.CombatIcon then
		frame.CombatIcon:SetShown(previewCombatIcon
			or (UnitExists(frame.unit) and UnitAffectingCombat(frame.unit)))
	end
end

-- Target cast bar. OnUpdate sets it every frame, always with small numbers: large ones
-- (the raw cast times, milliseconds since the computer started) are stored too coarsely
-- by the bar and make it move in steps. Three ways, best first:
--   readable times (your own casts): 0 to the cast's length, arithmetic as usual;
--   secret times (other units' casts): the cast's duration object, whose seconds
--     (total, elapsed, left) may be secret but go straight into the bar and the timer;
--   no usable duration object: the raw times as the range, fed the current time, so
--     the engine works out the fill (a little steppy, no timer, channels fill).

-- Shown with a sample cast while the Cast Bar page is open or the frames are unlocked.
local previewCastBar = false

local function IsCastPreview()
	return previewCastBar or (ns.IsUnlocked ~= nil and ns.IsUnlocked())
end

-- The cast's duration object, or nil when there's none or it can't be used from here
-- (UnitCastingDuration is documented as possibly returning a secret one).
local function GetCastDuration(unit, channel)
	local getDuration = channel and UnitChannelDuration or UnitCastingDuration
	if not getDuration then
		return nil
	end
	local ok, duration = pcall(getDuration, unit)
	if not ok or IsSecret(duration) or not duration then
		return nil
	end
	if not pcall(duration.GetElapsedDuration, duration) then
		return nil
	end
	return duration
end

local function CastBarOnUpdate(cast)
	if not cast.active then
		return
	end
	local duration = cast.duration
	if duration then
		-- Seconds, possibly secret, passed straight on.
		if cast.channel then
			cast.Bar:SetValue(duration:GetRemainingDuration())
		else
			cast.Bar:SetValue(duration:GetElapsedDuration())
		end
		cast.TimeText:SetFormattedText("%.1f", duration:GetRemainingDuration())
		return
	end
	local now = GetTime() * 1000
	if cast.secret then
		cast.Bar:SetValue(now)
		return
	end
	if cast.channel then
		cast.Bar:SetValue(cast.endTime - now)
	else
		cast.Bar:SetValue(now - cast.startTime)
	end
	cast.TimeText:SetFormattedText("%.1f", math.max(cast.endTime - now, 0) / 1000)
end

-- who: "player" or "target"; kind: "cast", "channel" or "uninterruptible".
local function GetCastColor(who, kind)
	local color = UnitFrames.db.castColors[who][kind] or CAST_COLOR_DEFAULTS[kind]
	return color[1], color[2], color[3]
end

local function ShowCastPreview(cast, who)
	cast.active = false
	cast.Bar:SetMinMaxValues(0, 1)
	cast.Bar:SetValue(0.6)
	cast.Bar:SetStatusBarColor(GetCastColor(who, "cast"))
	cast.Icon:SetTexture(CAST_PREVIEW_ICON)
	cast.NameText:SetText("Cast bar")
	cast.TimeText:SetText("1.5")
	cast:Show()
end

local function UpdateCast(frame)
	local cast = frame.CastBar
	if not cast then
		return
	end
	local enabled = frame.unit == "player" and UnitFrames.db.playerCastBar or (frame.unit ~= "player" and UnitFrames.db.castBar)
	if not enabled then
		cast.active = false
		cast:Hide()
		return
	end

	-- isTradeskill is never secret and only nil when nothing is being cast.
	local unit = frame.unit
	local name, _, texture, startTime, endTime, isTradeskill, _, notInterruptible = UnitCastingInfo(unit)
	local channel = false
	if isTradeskill == nil then
		local channelNotInterruptible, isEmpowered
		name, _, texture, startTime, endTime, isTradeskill, channelNotInterruptible, _, isEmpowered = UnitChannelInfo(unit)
		notInterruptible = channelNotInterruptible
		-- Empowered spells (held casts) fill like a cast.
		channel = isTradeskill ~= nil and not isEmpowered
	end

	local who = unit == "player" and "player" or "target"
	if isTradeskill == nil then
		cast.active = false
		if IsCastPreview() then
			ShowCastPreview(cast, who)
		else
			cast:Hide()
		end
		return
	end

	cast.active = true
	cast.channel = channel
	cast.startTime, cast.endTime = startTime, endTime
	cast.secret = IsSecret(startTime) or IsSecret(endTime)

	local kind = channel and "channel" or "cast"
	if who == "target" and not IsSecret(notInterruptible) and notInterruptible then
		kind = "uninterruptible"
	end
	cast.Bar:SetStatusBarColor(GetCastColor(who, kind))
	cast.NameText:SetText(name)
	cast.Icon:SetTexture(texture)

	-- See the comment above CastBarOnUpdate for the three ways.
	cast.duration = nil
	if not cast.secret then
		cast.Bar:SetMinMaxValues(0, endTime - startTime)
	else
		cast.duration = GetCastDuration(unit, channel)
		if cast.duration then
			cast.Bar:SetMinMaxValues(0, cast.duration:GetTotalDuration())
		else
			cast.Bar:SetMinMaxValues(startTime, endTime)
			cast.TimeText:SetText("")
		end
	end
	cast:Show()
	CastBarOnUpdate(cast)
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
	UpdateCast(frame)
	if frame.AuraContainers then
		for _, auras in pairs(frame.AuraContainers) do
			auras:UpdateAllAuras()
		end
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

-- A status bar on a background, inside a black border.
local function CreateBox(frame)
	local box = CreateFrame("Frame", nil, frame)
	box.Background = box:CreateTexture(nil, "BACKGROUND")
	box.Background:SetAllPoints()

	box.Bar = CreateFrame("StatusBar", nil, box)
	box.Bar:SetStatusBarTexture(GetBarTexturePath(UnitFrames.db.barTexture))

	local borderFrame = CreateFrame("Frame", nil, box)
	borderFrame:SetAllPoints()
	borderFrame:SetFrameLevel(box.Bar:GetFrameLevel() + 1)
	box.BorderFrame = borderFrame
	box.Border = {
		TOP = CreateLine(borderFrame),
		BOTTOM = CreateLine(borderFrame),
		LEFT = CreateLine(borderFrame),
		RIGHT = CreateLine(borderFrame),
	}

	table.insert(frame.Boxes, box)
	return box
end

-- opacity: 0-100, the shared background setting when nil.
local function LayoutBox(box, border, opacity)
	box.Background:SetColorTexture(0, 0, 0, (opacity or UnitFrames.db.backgroundOpacity) / 100)

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

-- The time-left countdown and the stack count of the buttons in one list (kept per
-- container, so a text size change reaches buttons that already exist). Blizzard may lock
-- them while auras are secret; those keep their old size until the next /reload.
local function SetAuraTextSize(texts, size)
	local fontPath, outline = GetFont()
	for _, text in ipairs(texts) do
		-- SetFont returns false when the file can't be loaded (e.g. a shared media font
		-- that's gone); fall back so the text always has a font.
		local ok, loaded = pcall(text.SetFont, text, fontPath, size, outline)
		if ok and not loaded then
			pcall(text.SetFont, text, DEFAULT_FONT, size, outline)
		end
	end
end

-- Called once per buff or debuff button by Blizzard's aura container. Its buttons have no
-- size of their own (the layout's element size only spaces them), so it's set here.
-- texts collects its countdown and stack count font strings.
local function InitializeAuraButton(button, size, textSize, texts)
	button:SetSize(size, size)
	local edge = math.max(UnitFrames.db.borderSize, 1)

	-- Border: black, and on debuffs coloured by dispel type over it (red: none, blue:
	-- magic, green: poison, purple: curse, ...). The container colours that texture
	-- itself with Blizzard's debuff colours, so it works while aura data is secret;
	-- on buffs it stays hidden and the black shows.
	local background = button:CreateTexture(nil, "BACKGROUND", nil, -1)
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 1)
	local dispelBorder = button:CreateTexture(nil, "BACKGROUND", nil, 0)
	dispelBorder:SetAllPoints()
	dispelBorder:SetColorTexture(1, 1, 1, 1)
	button:AddDispelTypeTexture(dispelBorder, {
		style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
		showWithoutDispelType = true,
	})

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", edge, -edge)
	icon:SetPoint("BOTTOMRIGHT", -edge, edge)
	icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
	button:SetIcon(icon)

	-- The countdown numbers show the time left.
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
	-- The font must be set before SetApplicationCount: the container writes to the
	-- font string straight away, and a font string without a font can't take text.
	local count = textLayer:CreateFontString(nil, "OVERLAY")
	count:SetPoint("BOTTOMRIGHT", 1, 0)
	local newTexts = { count, cooldown:GetCountdownFontString() }
	SetAuraTextSize(newTexts, textSize)
	button:SetApplicationCount(count)

	for _, text in ipairs(newTexts) do
		table.insert(texts, text)
	end
end

-- Buffs and debuffs each get their own aura container (one group, "auras"), so each can
-- sit above the health bar (growing up) or below the target frame (growing down). On the
-- same side they stack: buffs nearest the bar, debuffs on the rows beyond.
-- Settings per kind: <prefix>Show, Position ("above"/"below"), Size, TextSize, Max, X, Y.
local AURA_KINDS = {
	{ key = "buffs", prefix = "buff", filter = "HELPFUL" },
	{ key = "debuffs", prefix = "debuff", filter = "HARMFUL" },
}
local AURA_POSITIONS = {
	{ key = "above", name = "Above the health bar (grows up)" },
	{ key = "below", name = "Below the target frame (grows down)" },
}
local AURA_ROW_GAP = 2

local function GetAuraFilter(kind)
	if kind.key == "debuffs" and UnitFrames.db.debuffOnlyMine then
		return kind.filter .. "|PLAYER"
	end
	return kind.filter
end

local function CreateAuras(frame)
	frame.AuraContainers = {}
	frame.AuraTexts = {}
	for _, kind in ipairs(AURA_KINDS) do
		local auras = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
		local texts = {}
		auras:AddAuraGroup("auras", GetAuraFilter(kind), {
			maxFrameCount = MAX_AURAS,
			initializeFrame = function(button)
				local db = UnitFrames.db
				InitializeAuraButton(button, db[kind.prefix .. "Size"], db[kind.prefix .. "TextSize"], texts)
			end,
		})
		auras:SetUnit(frame.unit)
		frame.AuraContainers[kind.key] = auras
		frame.AuraTexts[kind.key] = texts
	end
end

-- Buttons made before the size changed. Blizzard may lock them while auras are secret;
-- those keep their old size until the next /reload.
local function ResizeAuraButtons(auras, size)
	pcall(function()
		for index = 1, auras:GetAuraGroupFrameCount("auras") do
			local button = auras:GetAuraGroupFrame("auras", index)
			if button then
				button:SetSize(size, size)
			end
		end
	end)
end

-- Rows are as wide as the health bar outside the portrait, from its far (left) end.
-- Above: clear of the name on the top border. Below: under the cast bar's spot (it's
-- only there while casting, so the icons don't jump when a cast starts).
local function LayoutAuras(frame, box, visibleWidth, textSize)
	local db = UnitFrames.db
	local aboveY = math.ceil(textSize / 2) + 1
	local belowY = -aboveY
	if db.castBar then
		belowY = math.min(belowY, db.castY - db.castHeight - 3)
	end

	local placed = {} -- [true = below, false = above] = the container already on that side
	for _, kind in ipairs(AURA_KINDS) do
		local auras = frame.AuraContainers[kind.key]
		local prefix = kind.prefix
		local shown = db[prefix .. "Show"]
		local size = db[prefix .. "Size"]
		local below = db[prefix .. "Position"] == "below"
		local x, y = db[prefix .. "X"], db[prefix .. "Y"]

		-- Switching the group off empties it; the container frame itself is left alone.
		auras:SetAuraGroupEnabled("auras", shown == true)
		auras:SetAuraGroupFilterString("auras", GetAuraFilter(kind))
		auras:SetAuraGroupMaxFrameCount("auras", db[prefix .. "Max"])
		auras:SetFlowLayoutMaximumLineSize(visibleWidth)
		auras:SetAuraGroupLayout("auras", {
			elementWidth = size,
			elementHeight = size,
			elementSpacing = 2,
			lineSpacing = 2,
		})

		local stackOn = placed[below]
		auras:ClearAllPoints()
		if below then
			auras:SetFlowLayoutAnchorPoint("TOPLEFT")
			auras:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
			if stackOn then
				auras:SetPoint("TOPLEFT", stackOn, "BOTTOMLEFT", x, -AURA_ROW_GAP + y)
			else
				auras:SetPoint("TOPLEFT", box, "BOTTOMLEFT", x, belowY + y)
			end
		else
			auras:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
			auras:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
			if stackOn then
				auras:SetPoint("BOTTOMLEFT", stackOn, "TOPLEFT", x, AURA_ROW_GAP + y)
			else
				auras:SetPoint("BOTTOMLEFT", box, "TOPLEFT", x, aboveY + y)
			end
		end
		ResizeAuraButtons(auras, size)
		SetAuraTextSize(frame.AuraTexts[kind.key], db[prefix .. "TextSize"])

		if shown then
			placed[below] = auras
		end
	end
end

-- Called by Layout (dragging, snapping, the X/Y sliders) with the frame's centre offset
-- from the screen centre. The frames are secure, so in combat they move when it ends.
local function SetPosition(key, x, y)
	UnitFrames.db.positions[key] = { "CENTER", "CENTER", x, y }
	local frame = frames[key]
	if not frame then
		return
	end
	if InCombatLockdown() then
		pendingApply = true
		return
	end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
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
		if ns.IsUnlocked and ns.IsUnlocked() and not InCombatLockdown() and not self.info.anchorTo then
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
		ns.MoverDropped(self.key) -- snaps, saves, and moves the mirrored partner
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

	-- Incoming heals (player and target): a clipped child of the health bar, between
	-- its fill and the border. See UpdateHealPrediction.
	if not info.compact then
		local calculator = CreateUnitHealPredictionCalculator()
		calculator:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
		calculator:SetIncomingHealOverflowPercent(1) -- not past maximum health
		frame.HealCalculator = calculator

		frame.HealthBar:SetClipsChildren(true)
		local heal = CreateFrame("StatusBar", nil, frame.HealthBar)
		heal:SetFrameLevel(frame.HealthBar:GetFrameLevel() + 1)
		frame.HealthBox.BorderFrame:SetFrameLevel(heal:GetFrameLevel() + 1)
		heal:SetStatusBarTexture(GetBarTexturePath(UnitFrames.db.barTexture))
		heal:SetStatusBarColor(unpack(HEAL_COLOR))
		heal:Hide()
		frame.HealBar = heal
	end

	-- Texts sit on a layer above the health bar; the portrait above that, its level text
	-- on top. The power bar sits on the health bar's bottom border, so it's above too.
	frame.Overlay = CreateFrame("Frame", nil, frame)
	frame.Overlay:SetAllPoints()
	frame.Overlay:SetFrameLevel(baseLevel + 5)

	if info.showPower then
		frame.PowerPrefix = info.powerPrefix
		frame.PowerBox = CreateBox(frame)
		frame.PowerBox:SetFrameLevel(baseLevel + 6)
		-- Its value on a layer above the bar and its border, so it shows when on the bar.
		local powerTextLayer = CreateFrame("Frame", nil, frame.PowerBox)
		powerTextLayer:SetAllPoints()
		powerTextLayer:SetFrameLevel(baseLevel + 9)
		frame.PowerText = CreateText(powerTextLayer, "LEFT")
	end

	frame.NameText = CreateText(frame.Overlay, info.portraitSide == "RIGHT" and "RIGHT" or "LEFT")
	if not info.compact then
		frame.HealthText = CreateText(frame.Overlay, info.percentFirst and "LEFT" or "RIGHT")
	end
	if info.showCombat then
		-- Above the power bar and its value, so nothing covers it.
		local combatLayer = CreateFrame("Frame", nil, frame)
		combatLayer:SetAllPoints()
		combatLayer:SetFrameLevel(baseLevel + 10)
		frame.CombatIcon = combatLayer:CreateTexture(nil, "OVERLAY")
		frame.CombatIcon:SetAtlas(COMBAT_ICON_ATLAS)
		frame.CombatIcon:Hide()
	end

	if info.portraitSide then
		-- Black edge, coloured ring, black edge, picture.
		local portraitFrame = CreateFrame("Frame", nil, frame)
		portraitFrame:SetFrameLevel(baseLevel + 8)
		frame.PortraitFrame = portraitFrame
		frame.RingEdge = CreateCircle(portraitFrame, "BACKGROUND", 0)
		frame.RingEdge:SetColorTexture(0, 0, 0, 1)
		frame.Ring = CreateCircle(portraitFrame, "BACKGROUND", 1)
		frame.RingInnerEdge = CreateCircle(portraitFrame, "BACKGROUND", 2)
		frame.RingInnerEdge:SetColorTexture(0, 0, 0, 1)
		frame.Portrait = CreateCircle(portraitFrame, "ARTWORK", 0)
		if info.showClassification then
			frame.Dragon = portraitFrame:CreateTexture(nil, "OVERLAY")
			frame.Dragon:Hide()
		end

		local levelLayer = CreateFrame("Frame", nil, frame)
		levelLayer:SetAllPoints(portraitFrame)
		levelLayer:SetFrameLevel(baseLevel + 10)
		frame.LevelText = CreateText(levelLayer, "CENTER")
	end

	if info.showAuras then
		CreateAuras(frame)
	end

	if info.showCastBar then
		-- A plain (not secure) child, so it can show and hide in combat.
		-- Frame levels are set in LayoutFrame: in front of or behind the portrait.
		local cast = CreateBox(frame)
		cast.Icon = cast:CreateTexture(nil, "ARTWORK")
		cast.Icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
		local textLayer = CreateFrame("Frame", nil, cast)
		textLayer:SetAllPoints()
		cast.TextLayer = textLayer
		cast.NameText = CreateText(textLayer, "LEFT")
		cast.TimeText = CreateText(textLayer, "RIGHT")
		cast:SetScript("OnUpdate", CastBarOnUpdate)
		cast:Hide()
		frame.CastBar = cast

		-- The player's, when separated, is dragged on its own while unlocked (the mouse
		-- is only on then, see LayoutFrame).
		if key == "player" then
			cast:SetMovable(true)
			cast:SetClampedToScreen(true)
			cast:RegisterForDrag("LeftButton")
			cast:SetScript("OnDragStart", function(self)
				if UnitFrames.db.playerCastDetached and ns.IsUnlocked and ns.IsUnlocked() then
					self:StartMoving()
					self.moving = true
				end
			end)
			cast:SetScript("OnDragStop", function(self)
				if not self.moving then
					return
				end
				self.moving = false
				self:StopMovingOrSizing()
				ns.MoverDropped("playercast") -- snaps and saves
			end)
		end
	end

	frames[key] = frame
	return frame
end

local function LayoutCompact(frame, border, fontPath, outline, smallSize)
	local db = UnitFrames.db
	frame:SetSize(db.totWidth, db.totHeight)

	local box = frame.HealthBox
	box:ClearAllPoints()
	box:SetAllPoints()
	LayoutBox(box, border)

	-- Name on the top border, left, like the big frames.
	frame.NameText:ClearAllPoints()
	frame.NameText:SetPoint("LEFT", box, "TOPLEFT", 4, db.nameOffsetY)
	frame.NameText:SetWidth(frame:GetWidth() - 8)
	frame.NameText:SetFont(fontPath, smallSize, outline)
end

local function LayoutPortrait(frame, side, size, border)
	local portraitFrame = frame.PortraitFrame
	portraitFrame:ClearAllPoints()
	portraitFrame:SetPoint(side, frame, side, 0, 0)
	portraitFrame:SetSize(size, size)

	local ringWidth = math.max(2, math.floor(size * 0.06 + 0.5))
	local function Inset(texture, inset)
		texture:ClearAllPoints()
		texture:SetPoint("TOPLEFT", inset, -inset)
		texture:SetPoint("BOTTOMRIGHT", -inset, inset)
	end
	Inset(frame.RingEdge, 0)
	Inset(frame.Ring, border)
	Inset(frame.RingInnerEdge, border + ringWidth)
	Inset(frame.Portrait, 2 * border + ringWidth)
	frame.RingEdge:SetShown(border > 0)
	frame.RingInnerEdge:SetShown(border > 0)
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
		local side = info.portraitSide           -- the portrait's end
		local otherSide = mirrored and "LEFT" or "RIGHT" -- the bar's free end
		local direction = mirrored and -1 or 1   -- x pointing away from the portrait
		-- The bar starts this far in from the portrait's outer edge: the portrait's centre,
		-- moved by portraitX (not past the portrait's outer edge).
		local barStart = half + math.max(db.portraitX, -half)
		local covered = math.max(size - barStart, 0) -- the bar under the portrait
		local visibleWidth = db.width - covered      -- the bar outside the portrait
		frame:SetSize(barStart + db.width, size)

		LayoutPortrait(frame, side, size, border)

		-- Health bar from barStart to the far end, centred on the portrait vertically.
		local box = frame.HealthBox
		box:ClearAllPoints()
		box:SetPoint(side, frame, side, barStart * direction, 0)
		box:SetPoint(otherSide, frame, otherSide, 0, 0)
		box:SetHeight(db.barHeight)
		LayoutBox(box, border)

		-- Incoming heals from the end of the health fill, as long as the whole bar (only
		-- the heal amount of it is filled, and that's clamped to the missing health).
		if frame.HealBar then
			local fill = frame.HealthBar:GetStatusBarTexture()
			frame.HealBar:ClearAllPoints()
			frame.HealBar:SetPoint("TOPLEFT", fill, "TOPRIGHT")
			frame.HealBar:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
			frame.HealBar:SetWidth(db.width - 2 * border)
		end

		-- Name on the top border next to the portrait; health text on the bottom border
		-- at the far end. Both are centred on the border line.
		frame.NameText:ClearAllPoints()
		frame.NameText:SetPoint(side, box, "TOP" .. side, (covered + 4) * direction, db.nameOffsetY)
		-- The whole bar outside the portrait; the debuffs sit above the name's line.
		frame.NameText:SetWidth(visibleWidth - 8)
		frame.NameText:SetFont(fontPath, textSize, outline)
		frame.NameText:SetShown(not info.hideName)

		frame.HealthText:ClearAllPoints()
		frame.HealthText:SetPoint(otherSide, box, "BOTTOM" .. otherSide, -4 * direction, db.healthOffsetY)
		frame.HealthText:SetFont(fontPath, textSize, outline)

		-- Combat icon: a fixed spot X in from the bar's far end, centred on the bottom
		-- border at Y 0, so it doesn't move with the health text.
		if frame.CombatIcon then
			local prefix = frame.key == "player" and "combatPlayer" or "combatTarget"
			frame.CombatIcon:SetSize(db.combatIconSize, db.combatIconSize)
			frame.CombatIcon:ClearAllPoints()
			frame.CombatIcon:SetPoint("CENTER", box, "BOTTOM" .. otherSide,
				-db[prefix .. "X"] * direction, db[prefix .. "Y"])
		end

		-- Level centred on the portrait's bottom edge.
		frame.LevelText:ClearAllPoints()
		frame.LevelText:SetPoint("CENTER", frame.PortraitFrame, "BOTTOM", 0, db.levelOffsetY)
		frame.LevelText:SetFont(fontPath, textSize + 1, outline)

		-- Power (target) or druid mana (player): a short bar on the bottom border, X in
		-- from the far end (so it doesn't move with the health text), centred on the line
		-- at Y 0.
		if frame.PowerBox then
			local function Setting(name)
				return GetPowerSetting(frame, name)
			end
			local powerBox = frame.PowerBox
			powerBox:ClearAllPoints()
			powerBox:SetPoint(otherSide, box, "BOTTOM" .. otherSide, -Setting("X") * direction, Setting("Y"))
			powerBox:SetSize(Setting("Width"), Setting("Height") + 2 * border)
			LayoutBox(powerBox, border, Setting("BackgroundOpacity"))

			local powerText = frame.PowerText
			local anchor = POWER_TEXT_ANCHORS[Setting("TextPosition")] or POWER_TEXT_ANCHORS.right
			local fixedPoint = POWER_TEXT_FIXED_POINT[Setting("TextGrowth")] or anchor.grow
			powerText:ClearAllPoints()
			powerText:SetPoint(fixedPoint, powerBox, anchor.point, anchor.x + Setting("TextX"), Setting("TextY"))
			powerText:SetJustifyH(fixedPoint)
			powerText:SetFont(fontPath, smallSize, outline)
		end

		-- On its own: an error in the buffs and debuffs is reported but doesn't stop the
		-- rest of the frame (and the frames after it) from being laid out.
		if frame.AuraContainers then
			xpcall(function()
				LayoutAuras(frame, box, visibleWidth, textSize)
			end, geterrorhandler())
		end

		-- Cast bar under the health bar, lined up with its far end (so it covers the part
		-- outside the portrait). Player and target look the same and share the settings:
		-- icon on the left, name next to it, timer on the right, filling left to right.
		if frame.CastBar then
			local cast = frame.CastBar
			-- The player's can be separated: its own size, at its own place on the screen
			-- (moved with Unlock frames / the Layout page), in front of everything.
			local detached = frame.unit == "player" and db.playerCastDetached
			local castWidth = db.castMatchWidth and visibleWidth or db.castWidth
			local castHeight = db.castHeight
			if detached then
				castWidth, castHeight = db.playerCastWidth, db.playerCastHeight
			end
			-- Where it overlaps the portrait it's drawn behind it (portrait: base + 8) or
			-- in front of it and the level text (base + 10). Every layer of the bar is set,
			-- so its text and icon go the same way.
			local behind = db.castBehindPortrait and not detached
			local castLevel = frame:GetFrameLevel() + (behind and 2 or 11)
			cast:SetFrameLevel(castLevel)
			cast.Bar:SetFrameLevel(castLevel + 1)
			cast.BorderFrame:SetFrameLevel(castLevel + 2)
			cast.TextLayer:SetFrameLevel(castLevel + 3)
			cast:ClearAllPoints()
			if detached then
				local position = db.playerCastPosition
				cast:SetPoint("CENTER", UIParent, "CENTER", position[1], position[2])
			else
				cast:SetPoint("TOP" .. otherSide, box, "BOTTOM" .. otherSide, db.castX, db.castY)
			end
			cast:EnableMouse(detached and ns.IsUnlocked ~= nil and ns.IsUnlocked())
			cast:SetSize(castWidth, castHeight)
			LayoutBox(cast, border)
			cast.Bar:SetReverseFill(false)

			local inner = castHeight - 2 * border
			cast.Icon:ClearAllPoints()
			cast.Icon:SetShown(db.castIcon)
			if db.castIcon then
				cast.Icon:SetPoint("TOPLEFT", border, -border)
				cast.Icon:SetSize(inner, inner)
				-- The bar starts after the icon and a border-wide gap.
				cast.Bar:ClearAllPoints()
				cast.Bar:SetPoint("TOPLEFT", 2 * border + inner, -border)
				cast.Bar:SetPoint("BOTTOMRIGHT", -border, border)
			end

			cast.NameText:ClearAllPoints()
			cast.NameText:SetPoint("LEFT", cast.Bar, "LEFT", 3, 0)
			cast.NameText:SetPoint("RIGHT", cast.TimeText, "LEFT", -4, 0)
			cast.NameText:SetFont(fontPath, smallSize, outline)
			cast.TimeText:ClearAllPoints()
			cast.TimeText:SetPoint("RIGHT", cast.Bar, "RIGHT", -3, 0)
			cast.TimeText:SetFont(fontPath, smallSize, outline)
		end
	end

	frame:ClearAllPoints()
	local anchorFrame = info.anchorTo and frames[info.anchorTo]
	if anchorFrame then
		-- Right of the target's portrait, level with its health bar, plus the chosen offset.
		frame:SetPoint("LEFT", anchorFrame, "RIGHT", COMPACT_GAP + db.totX, db.totY)
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

-- Blizzard's player cast bar, off while ours is on. It's an Edit Mode managed frame that
-- Blizzard re-parents and re-shows itself, so it's switched off the way Blizzard does
-- (SetAndUpdateShowCastbar, as when a profession window shows its own cast bar), and
-- hidden again if Blizzard turns it back on (it does after such a window closes).
local blizzardCastBarOff = false
local blizzardCastBarHooked = false

local function SetBlizzardPlayerCastBarOff(off)
	local castBar = _G[BLIZZARD_PLAYER_CAST_BAR]
	if not castBar then
		return
	end
	if not blizzardCastBarHooked then
		blizzardCastBarHooked = true
		castBar:HookScript("OnShow", function(self)
			if blizzardCastBarOff and not self.isInEditMode then
				self:Hide()
			end
		end)
	end
	if blizzardCastBarOff == off then
		return
	end
	blizzardCastBarOff = off
	if castBar.SetAndUpdateShowCastbar then
		castBar:SetAndUpdateShowCastbar(not off)
	end
	if off then
		castBar:Hide()
	end
end

---------------------------------------------------------------------------
-- Applying settings
---------------------------------------------------------------------------

local function ShowFrame(frame)
	if frame.unit == "player" then
		frame:Show()
		return
	end

	-- The target frame follows the target, except while unlocked so it can be placed.
	if not (ns.IsUnlocked and ns.IsUnlocked()) then
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

	-- Our player cast bar replaces Blizzard's.
	SetBlizzardPlayerCastBarOff(self.db.enabled and self.db.playerCastBar)
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
		if frame.HealBar then
			frame.HealBar:SetStatusBarTexture(path)
			frame.HealBar:SetStatusBarColor(unpack(HEAL_COLOR))
		end
		UpdateColor(frame)
		UpdatePower(frame)
	end
end

-- After an NPC or power colour changed; works in combat too.
function UnitFrames:RefreshColors()
	for _, frame in pairs(frames) do
		UpdateColor(frame)
		UpdatePower(frame)
	end
end

-- The Fonts page changed the font or outline.
function UnitFrames:OnFontChanged()
	self:Apply()
end

-- The Unlock frames checkbox (Layout): the target shows a preview while unlocked.
function UnitFrames:OnUnlockChanged(unlocked)
	self:Apply()
end

if ns.RegisterMover then
	ns:RegisterMover("player", {
		title = "Player frame",
		getFrame = function()
			return frames.player
		end,
		save = function(x, y)
			SetPosition("player", x, y)
		end,
	})
	ns:RegisterMover("target", {
		title = "Target frame",
		getFrame = function()
			return frames.target
		end,
		save = function(x, y)
			SetPosition("target", x, y)
		end,
	})
	-- Only movable while separated from the player frame; nil otherwise.
	ns:RegisterMover("playercast", {
		title = "Player cast bar (when separated)",
		getFrame = function()
			if UnitFrames.db.playerCastDetached and frames.player then
				return frames.player.CastBar
			end
		end,
		save = function(x, y)
			UnitFrames.db.playerCastPosition = { x, y }
			local cast = frames.player and frames.player.CastBar
			if cast and UnitFrames.db.playerCastDetached then
				cast:ClearAllPoints()
				cast:SetPoint("CENTER", UIParent, "CENTER", x, y)
			end
		end,
	})
end

function UnitFrames:ResetPositions()
	self.db.positions.player = nil
	self.db.positions.target = nil
	self.db.totX = 0
	self.db.totY = 0
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
	-- Locking is the window's Unlock frames checkbox now, for all frames at once.
	self.db.locked = nil
	-- Short-lived cast bar option that made it longer; replaced by castBehindPortrait.
	self.db.castTuck = nil
	-- Buffs and debuffs shared one size (debuffSize) before they were split.
	if not self.db.aurasSplit then
		self.db.buffSize = self.db.debuffSize
		self.db.aurasSplit = true
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

-- Entering or leaving cat or bear form: the player's druid mana bar shows or hides.
function UnitFrames:OnShapeshift()
	if frames.player then
		UpdatePower(frames.player)
	end
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

-- Any UNIT_SPELLCAST_* event: start, stop, delay, interruptible changes. The cast bar
-- reads the cast again each time, so one handler covers them all.
function UnitFrames:OnUnitCast(event, unit)
	ForUnit(unit, UpdateCast)
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
UnitFrames:RegisterEvent("UNIT_HEAL_PREDICTION", "OnUnitHealth")
UnitFrames:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "OnShapeshift")
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
for _, event in ipairs({
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}) do
	UnitFrames:RegisterEvent(event, "OnUnitCast")
end
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
	label:SetWidth(120)

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
	ns.MakeSliderEditable(slider)
	return slider, label
end

-- setup(rootDescription) fills the menu.
local function CreateDropdown(parent, anchor, labelText, setup)
	local label = CreateLabel(parent, labelText)
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
	label:SetWidth(120)

	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)
	dropdown:SetWidth(200)
	dropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetScrollMode(300)
		setup(rootDescription)
	end)
	return dropdown, label
end

local function UpdateSwatch(swatch)
	swatch.Color:SetColorTexture(GetNPCColor(swatch.colorType))
end

local function SetNPCColor(key, r, g, b)
	UnitFrames.db.npcColors[key] = { r, g, b }
	UnitFrames:RefreshColors()
end

local function OpenColorPicker(swatch)
	local key = swatch.colorType.key
	local r, g, b = GetNPCColor(swatch.colorType)
	local hadCustom = UnitFrames.db.npcColors[key] ~= nil

	ColorPickerFrame:SetupColorPickerAndShow({
		r = r,
		g = g,
		b = b,
		-- Called on every change, so the frames update while you drag.
		swatchFunc = function()
			local newR, newG, newB = ColorPickerFrame:GetColorRGB()
			SetNPCColor(key, newR, newG, newB)
			UpdateSwatch(swatch)
		end,
		cancelFunc = function()
			if hadCustom then
				SetNPCColor(key, r, g, b)
			else
				UnitFrames.db.npcColors[key] = nil
				UnitFrames:RefreshColors()
			end
			UpdateSwatch(swatch)
		end,
	})
end

local function CreateSwatch(parent, colorType)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetSize(18, 18)
	swatch.colorType = colorType

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

-- The settings are split over pages: Unit Frames itself (general), and Sizes, Text,
-- Colours and Target of Target listed under it in the window. All use UnitFrames.db.
local function RegisterSubPage(name, title, order)
	return ns:RegisterModule(name, { title = title, order = order, navParent = "UnitFrames" })
end

-- Title, an optional grey line under it, and an anchor for the first slider.
local function CreatePageHeader(page, titleText, introText)
	local title = CreateLabel(page, titleText, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)
	local below = title
	if introText then
		local intro = CreateLabel(page, introText, "GameFontDisableSmall")
		intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
		intro:SetPoint("RIGHT", page, "RIGHT", -4, 0)
		below = intro
	end
	return title, below
end

-- General

function UnitFrames:CreatePage(page)
	local module = self

	local title = CreatePageHeader(page, "Unit Frames")

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

	local healCheck = CreateCheck(page, "Show incoming heals on the health bars", self.db.incomingHeals, function(checked)
		module.db.incomingHeals = checked
		for _, frame in pairs(frames) do
			UpdateHealPrediction(frame)
		end
	end)
	healCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, 2)

	local sliderAnchor = CreateFrame("Frame", nil, page)
	sliderAnchor:SetPoint("TOPLEFT", healCheck, "BOTTOMLEFT", 4, 0)
	sliderAnchor:SetSize(1, 1)

	local _, borderLabel = CreateSlider(self, page, sliderAnchor, "Border thickness", "borderSize", { 0, 5, 5 })
	local _, backgroundLabel = CreateSlider(self, page, borderLabel, "Background opacity", "backgroundOpacity", { 0, 100, 20 })

	local textureDropdown, textureLabel = CreateDropdown(page, backgroundLabel, "Bar texture", function(rootDescription)
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
	note:SetPoint("TOPLEFT", textureLabel, "BOTTOMLEFT", 0, -20)
	note:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	note:SetJustifyV("TOP")
	note:SetText("Sizes, text and colours are on the pages under Unit Frames in the list on the left. "
		.. "To move the frames, tick |cffffd100Unlock frames|r at the top of this window; the Layout page has exact positions. "
		.. "Changes made in combat are applied when combat ends. "
		.. "Type |cffffd100/adam framestyle|r to switch the frames on or off.")
end

function UnitFrames:OnPageShown(page)
	self.enableCheck:SetChecked(self.db.enabled)
	-- The shared media list can grow after login.
	self.textureDropdown:GenerateMenu()
end

-- Sizes

local SizesPage = RegisterSubPage("UnitFramesSizes", "Sizes", 21)

function SizesPage:CreatePage(page)
	local _, below = CreatePageHeader(page, "Unit Frame Sizes")

	local _, widthLabel = CreateSlider(UnitFrames, page, below, "Bar width", "width", { 120, 400, 280 })
	local _, heightLabel = CreateSlider(UnitFrames, page, widthLabel, "Bar height", "barHeight", { 10, 50, 40 })
	local _, portraitSizeLabel = CreateSlider(UnitFrames, page, heightLabel, "Portrait size", "portraitSize", { 30, 90, 60 })
	CreateSlider(UnitFrames, page, portraitSizeLabel, "Portrait X", "portraitX", { -40, 60, 100 })
end

-- Target power

local PowerPage = RegisterSubPage("UnitFramesPower", "Target Power", 22.5)

function PowerPage:CreatePage(page)
	local _, below = CreatePageHeader(page, "Target Power Bar",
		"The small bar on the target's bottom border. X is measured from the bar's far end; Y 0 centres it on the border line.")

	local _, widthLabel = CreateSlider(UnitFrames, page, below, "Width", "powerWidth", { 10, 200, 190 })
	local _, heightLabel = CreateSlider(UnitFrames, page, widthLabel, "Height", "powerHeight", { 2, 16, 14 })
	local _, xLabel = CreateSlider(UnitFrames, page, heightLabel, "X", "powerX", { 0, 400, 400 })
	local _, positionYLabel = CreateSlider(UnitFrames, page, xLabel, "Y", "powerY", { -30, 30, 60 })
	local _, yLabel = CreateSlider(UnitFrames, page, positionYLabel, "Background opacity", "powerBackgroundOpacity", { 0, 100, 20 })

	local textHeader = CreateLabel(page, "Power value", "GameFontNormal")
	textHeader:SetPoint("TOPLEFT", yLabel, "BOTTOMLEFT", 0, -24)

	local _, positionLabel = CreateDropdown(page, textHeader, "Position", function(rootDescription)
		local function IsSelected(key)
			return UnitFrames.db.powerTextPosition == key
		end
		local function SetSelected(key)
			UnitFrames.db.powerTextPosition = key
			UnitFrames:Apply()
		end
		for _, position in ipairs(POWER_TEXT_POSITIONS) do
			rootDescription:CreateRadio(position.name, IsSelected, SetSelected, position.key)
		end
	end)

	local _, growthLabel = CreateDropdown(page, positionLabel, "Grows", function(rootDescription)
		local function IsSelected(key)
			return UnitFrames.db.powerTextGrowth == key
		end
		local function SetSelected(key)
			UnitFrames.db.powerTextGrowth = key
			UnitFrames:Apply()
		end
		for _, growth in ipairs(POWER_TEXT_GROWTH) do
			rootDescription:CreateRadio(growth.name, IsSelected, SetSelected, growth.key)
		end
	end)

	local _, textXLabel = CreateSlider(UnitFrames, page, growthLabel, "Text X", "powerTextX", { -80, 80, 160 })
	CreateSlider(UnitFrames, page, textXLabel, "Text Y", "powerTextY", { -20, 20, 40 })
end

-- Combat icon

local AurasPage = RegisterSubPage("UnitFramesAuras", "Buffs & Debuffs", 22.6)

-- One kind's settings: show, (only mine), position, size, max, X, Y. Returns the last
-- label to anchor the next section below.
local function CreateAuraSection(page, anchor, kind, titleText)
	local prefix = kind.prefix
	local db = UnitFrames.db

	local header = CreateLabel(page, titleText, "GameFontNormal")
	header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -18)

	local showCheck = CreateCheck(page, "Show", db[prefix .. "Show"], function(checked)
		db[prefix .. "Show"] = checked
		UnitFrames:Apply()
	end)
	showCheck:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -4, -2)

	if kind.key == "debuffs" then
		local mineCheck = CreateCheck(page, "Only my debuffs", db.debuffOnlyMine, function(checked)
			db.debuffOnlyMine = checked
			UnitFrames:Apply()
		end)
		mineCheck:SetPoint("LEFT", showCheck, "LEFT", 160, 0)
	end

	local checkAnchor = CreateFrame("Frame", nil, page)
	checkAnchor:SetPoint("TOPLEFT", showCheck, "BOTTOMLEFT", 4, 4)
	checkAnchor:SetSize(1, 1)

	local _, positionLabel = CreateDropdown(page, checkAnchor, "Position", function(rootDescription)
		local function IsSelected(key)
			return db[prefix .. "Position"] == key
		end
		local function SetSelected(key)
			db[prefix .. "Position"] = key
			UnitFrames:Apply()
		end
		for _, position in ipairs(AURA_POSITIONS) do
			rootDescription:CreateRadio(position.name, IsSelected, SetSelected, position.key)
		end
	end)

	local _, sizeLabel = CreateSlider(UnitFrames, page, positionLabel, "Icon size", prefix .. "Size", { 12, 40, 28 })
	local _, textSizeLabel = CreateSlider(UnitFrames, page, sizeLabel, "Text size", prefix .. "TextSize", { 6, 24, 18 })
	local _, maxLabel = CreateSlider(UnitFrames, page, textSizeLabel, "Max shown", prefix .. "Max", { 1, MAX_AURAS, MAX_AURAS - 1 })
	local _, xLabel = CreateSlider(UnitFrames, page, maxLabel, "X", prefix .. "X", { -100, 100, 200 })
	local _, yLabel = CreateSlider(UnitFrames, page, xLabel, "Y", prefix .. "Y", { -60, 60, 120 })
	return yLabel
end

function AurasPage:CreatePage(page)
	local _, below = CreatePageHeader(page, "Target Buffs & Debuffs",
		"Rows start at the health bar's left end and are as wide as the bar. "
		.. "On the same side, debuffs come after the buffs; X and Y then move them from there. "
		.. "Debuff borders show the dispel type (blue magic, green poison, ...).")

	local buffsEnd = CreateAuraSection(page, below, AURA_KINDS[1], "Buffs")
	CreateAuraSection(page, buffsEnd, AURA_KINDS[2], "Debuffs")
end

local CombatPage = RegisterSubPage("UnitFramesCombat", "Combat Icon", 22.7)

function CombatPage:CreatePage(page)
	local _, below = CreatePageHeader(page, "Combat Icon",
		"The crossed swords shown while the unit is in combat. X is measured from the far end of the health bar; Y 0 centres it on the bottom border.")

	local _, sizeLabel = CreateSlider(UnitFrames, page, below, "Size", "combatIconSize", { 6, 40, 34 })

	local playerHeader = CreateLabel(page, "Player", "GameFontNormal")
	playerHeader:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -24)
	local _, playerXLabel = CreateSlider(UnitFrames, page, playerHeader, "X", "combatPlayerX", { 0, 400, 400 })
	local _, playerYLabel = CreateSlider(UnitFrames, page, playerXLabel, "Y", "combatPlayerY", { -40, 40, 80 })

	local targetHeader = CreateLabel(page, "Target", "GameFontNormal")
	targetHeader:SetPoint("TOPLEFT", playerYLabel, "BOTTOMLEFT", 0, -24)
	local _, targetXLabel = CreateSlider(UnitFrames, page, targetHeader, "X", "combatTargetX", { 0, 400, 400 })
	CreateSlider(UnitFrames, page, targetXLabel, "Y", "combatTargetY", { -40, 40, 80 })

	page:HookScript("OnHide", function()
		previewCombatIcon = false
		for _, frame in pairs(frames) do
			UpdateCombat(frame)
		end
	end)
end

function CombatPage:OnPageShown(page)
	previewCombatIcon = true
	for _, frame in pairs(frames) do
		UpdateCombat(frame)
	end
end

-- Cast bar

local CastPage = RegisterSubPage("UnitFramesCast", "Cast Bar", 22.8)

local function RefreshCastBar()
	for _, key in ipairs({ "player", "target" }) do
		if frames[key] then
			UpdateCast(frames[key])
		end
	end
end

-- One colour picker for castColors[who][kind]: click to change (the bars update while
-- you drag), Cancel puts the old colour back.
local function CreateCastColorSwatch(parent, who, colorKind)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetSize(18, 18)

	local edge = swatch:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(0, 0, 0, 1)
	swatch.Color = swatch:CreateTexture(nil, "ARTWORK")
	swatch.Color:SetPoint("TOPLEFT", 1, -1)
	swatch.Color:SetPoint("BOTTOMRIGHT", -1, 1)

	swatch.Label = CreateLabel(parent, colorKind.name)
	swatch.Label:SetPoint("LEFT", swatch, "RIGHT", 6, 0)

	function swatch.Update()
		swatch.Color:SetColorTexture(GetCastColor(who, colorKind.key))
	end

	local colors = UnitFrames.db.castColors[who]
	local function SetColor(r, g, b)
		colors[colorKind.key] = { r, g, b }
		RefreshCastBar()
		swatch.Update()
	end

	swatch:SetScript("OnClick", function()
		local r, g, b = GetCastColor(who, colorKind.key)
		local hadCustom = colors[colorKind.key] ~= nil
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r,
			g = g,
			b = b,
			swatchFunc = function()
				SetColor(ColorPickerFrame:GetColorRGB())
			end,
			cancelFunc = function()
				if hadCustom then
					SetColor(r, g, b)
				else
					colors[colorKind.key] = nil
					RefreshCastBar()
					swatch.Update()
				end
			end,
		})
	end)
	swatch:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(colorKind.name .. " colour")
		GameTooltip:AddLine("Click to change.", 1, 1, 1)
		GameTooltip:Show()
	end)
	swatch:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	swatch.Update()
	return swatch
end

function CastPage:CreatePage(page)
	local _, below = CreatePageHeader(page, "Cast Bars",
		"Under the health bars. The player's looks like the target's and uses the same settings. "
		.. "X and Y move them from the health bar's far bottom corner. A sample cast shows while this page is open. "
		.. "Yellow: cast, blue: channel, grey: can't be interrupted.")

	local showCheck = CreateCheck(page, "Show the target's cast bar", UnitFrames.db.castBar, function(checked)
		UnitFrames.db.castBar = checked
		RefreshCastBar()
	end)
	showCheck:SetPoint("TOPLEFT", below, "BOTTOMLEFT", -4, -6)

	local playerCheck = CreateCheck(page, "Show the player's cast bar (hides Blizzard's)", UnitFrames.db.playerCastBar, function(checked)
		UnitFrames.db.playerCastBar = checked
		UnitFrames:Apply() -- also hides or gives back Blizzard's cast bar
	end)
	playerCheck:SetPoint("TOPLEFT", showCheck, "BOTTOMLEFT", 0, 2)

	local iconCheck = CreateCheck(page, "Show the spell icon", UnitFrames.db.castIcon, function(checked)
		UnitFrames.db.castIcon = checked
		UnitFrames:Apply()
	end)
	iconCheck:SetPoint("TOPLEFT", playerCheck, "BOTTOMLEFT", 0, 2)

	-- Width only applies with this unticked, so the slider is greyed out while it's ticked.
	local widthSlider, widthLabel
	local function UpdateWidthEnabled()
		local usable = not UnitFrames.db.castMatchWidth
		widthSlider:SetEnabled(usable)
		widthLabel:SetFontObject(usable and "GameFontHighlight" or "GameFontDisable")
	end

	local matchCheck = CreateCheck(page, "Same width as the target's health bar", UnitFrames.db.castMatchWidth, function(checked)
		UnitFrames.db.castMatchWidth = checked
		UpdateWidthEnabled()
		UnitFrames:Apply()
	end)
	matchCheck:SetPoint("TOPLEFT", iconCheck, "BOTTOMLEFT", 0, 2)

	local behindCheck = CreateCheck(page, "Go behind the portrait where they overlap", UnitFrames.db.castBehindPortrait, function(checked)
		UnitFrames.db.castBehindPortrait = checked
		UnitFrames:Apply()
	end)
	behindCheck:SetPoint("TOPLEFT", matchCheck, "BOTTOMLEFT", 0, 2)

	local anchor = CreateFrame("Frame", nil, page)
	anchor:SetPoint("TOPLEFT", behindCheck, "BOTTOMLEFT", 4, 0)
	anchor:SetSize(1, 1)

	widthSlider, widthLabel = CreateSlider(UnitFrames, page, anchor, "Width", "castWidth", { 40, 400, 360 })
	UpdateWidthEnabled()
	local _, heightLabel = CreateSlider(UnitFrames, page, widthLabel, "Height", "castHeight", { 6, 40, 34 })
	local _, xLabel = CreateSlider(UnitFrames, page, heightLabel, "X", "castX", { -200, 200, 400 })
	local _, yLabel = CreateSlider(UnitFrames, page, xLabel, "Y", "castY", { -100, 100, 200 })

	-- Separating the player's: its own width and height (greyed out until ticked); its
	-- place is set by dragging with Unlock frames, or on the Layout page.
	local detachedSliders = {}
	local function UpdateDetachedEnabled()
		local usable = UnitFrames.db.playerCastDetached
		for _, entry in ipairs(detachedSliders) do
			entry.slider:SetEnabled(usable)
			entry.label:SetFontObject(usable and "GameFontHighlight" or "GameFontDisable")
		end
	end

	local detachCheck = CreateCheck(page, "Separate the player's cast bar from the player frame", UnitFrames.db.playerCastDetached, function(checked)
		UnitFrames.db.playerCastDetached = checked
		UpdateDetachedEnabled()
		UnitFrames:Apply()
	end)
	detachCheck:SetPoint("TOPLEFT", yLabel, "BOTTOMLEFT", -4, -14)
	local detachNote = CreateLabel(page, "Own size and place. Move it with |cffffd100Unlock frames|r at the top of the window, or on the Layout page.", "GameFontDisableSmall")
	detachNote:SetPoint("TOPLEFT", detachCheck, "BOTTOMLEFT", 4, 0)
	detachNote:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local playerWidthSlider, playerWidthLabel = CreateSlider(UnitFrames, page, detachNote, "Width", "playerCastWidth", { 40, 500, 460 })
	local playerHeightSlider, playerHeightLabel = CreateSlider(UnitFrames, page, playerWidthLabel, "Height", "playerCastHeight", { 6, 40, 34 })
	table.insert(detachedSliders, { slider = playerWidthSlider, label = playerWidthLabel })
	table.insert(detachedSliders, { slider = playerHeightSlider, label = playerHeightLabel })
	UpdateDetachedEnabled()

	-- Colours: a row of pickers for the target, one for the player.
	local swatches = {}
	local previousRow = playerHeightLabel
	for _, who in ipairs({ "target", "player" }) do
		local rowLabel = CreateLabel(page, who == "target" and "Target colours" or "Player colours")
		rowLabel:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, -16)
		rowLabel:SetWidth(120)
		local previousSwatch
		for _, colorKind in ipairs(CAST_COLOR_KINDS[who]) do
			local swatch = CreateCastColorSwatch(page, who, colorKind)
			if previousSwatch then
				swatch:SetPoint("LEFT", previousSwatch.Label, "RIGHT", 14, 0)
			else
				swatch:SetPoint("LEFT", rowLabel, "RIGHT", 8, 0)
			end
			table.insert(swatches, swatch)
			previousSwatch = swatch
		end
		previousRow = rowLabel
	end

	local resetColors = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	resetColors:SetPoint("TOPLEFT", previousRow, "BOTTOMLEFT", 0, -12)
	resetColors:SetSize(130, 22)
	resetColors:SetText("Reset colours")
	resetColors:SetScript("OnClick", function()
		wipe(UnitFrames.db.castColors.target)
		wipe(UnitFrames.db.castColors.player)
		RefreshCastBar()
		for _, swatch in ipairs(swatches) do
			swatch.Update()
		end
	end)

	page:HookScript("OnHide", function()
		previewCastBar = false
		RefreshCastBar()
	end)
end

function CastPage:OnPageShown(page)
	previewCastBar = true
	RefreshCastBar()
end

-- Text

local TextPage = RegisterSubPage("UnitFramesText", "Text", 22)

function TextPage:CreatePage(page)
	local _, below = CreatePageHeader(page, "Unit Frame Text", "The font and outline are on the Fonts page.")

	local _, sizeLabel = CreateSlider(UnitFrames, page, below, "Text size", "textSize", { 8, 24, 16 })

	local positionHeader = CreateLabel(page, "Position on the border", "GameFontNormal")
	positionHeader:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -24)
	local positionIntro = CreateLabel(page, "0 centres the text on the border line; + moves it up, - down.", "GameFontDisableSmall")
	positionIntro:SetPoint("TOPLEFT", positionHeader, "BOTTOMLEFT", 0, -6)

	local OFFSET_RANGE = { -15, 15, 30 }
	local _, levelLabel = CreateSlider(UnitFrames, page, positionIntro, "Level", "levelOffsetY", OFFSET_RANGE)
	local _, nameLabel = CreateSlider(UnitFrames, page, levelLabel, "Name", "nameOffsetY", OFFSET_RANGE)
	CreateSlider(UnitFrames, page, nameLabel, "Health", "healthOffsetY", OFFSET_RANGE)
end

-- Colours

local ColoursPage = RegisterSubPage("UnitFramesColours", "Colours", 23)

function ColoursPage:CreatePage(page)
	local _, below = CreatePageHeader(page, "NPC Colours",
		"Health bar and portrait ring colours for NPCs. Players keep their class colour.")

	self.swatches = {}
	local previous = below
	for _, colorType in ipairs(NPC_COLOR_TYPES) do
		local swatch = CreateSwatch(page, colorType)
		swatch:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -10)
		table.insert(self.swatches, swatch)
		previous = swatch
	end

	local module = self
	local resetColors = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	resetColors:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -16)
	resetColors:SetSize(140, 22)
	resetColors:SetText("Reset colours")
	resetColors:SetScript("OnClick", function()
		wipe(UnitFrames.db.npcColors)
		UnitFrames:RefreshColors()
		for _, swatch in ipairs(module.swatches) do
			UpdateSwatch(swatch)
		end
	end)
end

function ColoursPage:OnPageShown(page)
	for _, swatch in ipairs(self.swatches) do
		UpdateSwatch(swatch)
	end
end

-- Target of target

local TargetOfTarget = RegisterSubPage("TargetOfTarget", "Target of Target", 24)

function TargetOfTarget:CreatePage(page)
	local _, below = CreatePageHeader(page, "Target of Target",
		"The small bar right of the target frame. X and Y move it from that spot.")

	local _, widthLabel = CreateSlider(UnitFrames, page, below, "Width", "totWidth", { 40, 300, 260 })
	local _, heightLabel = CreateSlider(UnitFrames, page, widthLabel, "Height", "totHeight", { 6, 40, 34 })
	local _, xLabel = CreateSlider(UnitFrames, page, heightLabel, "X", "totX", { -200, 200, 400 })
	CreateSlider(UnitFrames, page, xLabel, "Y", "totY", { -150, 150, 300 })
end
