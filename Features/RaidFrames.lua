local addonName, ns = ...

-- Bar textures on Blizzard's own party and raid frames (the compact unit frames).
-- No frames of our own: only the texture of their health and power bars is swapped.
--
-- Blizzard sets those textures once, in XML (Blizzard_UnitFrame\Shared\CompactUnitFrame.xml),
-- and never again from Lua. Every party, raid and pet frame goes through
-- DefaultCompactUnitFrameSetup or DefaultCompactMiniFrameSetup when it is set up, gets a new
-- unit or Edit Mode changes the layout, so a hook on those two keeps our texture on. Nameplates
-- use other setup functions and are left alone.
--
-- The health and power bars are plain StatusBars, not secure frames: changing their texture
-- is safe in combat. Health colours stay Blizzard's (class colours etc.); our textures are
-- grey levels that take that colour.

local RaidFrames = ns:RegisterModule("RaidFrames", {
	title = "Party & Raid",
	order = 24.5,
	navParent = "UnitFrames",
	defaults = {
		enabled = true,
		healthTexture = "melli", -- key from the Unit Frames texture list, or shared media
		powerTexture = "melli",
	},
})

-- Blizzard's own look, from CompactUnitFrame.xml, for switching the feature off.
local BLIZZARD_HEALTH_ATLAS = "RaidFrame-Hp-Fill"
local BLIZZARD_POWER_ATLAS = "_RaidFrame-Resource-Fill"

local MAX_RAID_GROUPS = 8
local MEMBERS_PER_GROUP = 5

-- Frames we have changed, so switching off only touches those.
local changed = setmetatable({}, { __mode = "k" })

local function GetTexturePath(key)
	return ns.GetBarTexturePath and ns.GetBarTexturePath(key)
end

-- Our textures are made to stretch over the bar; Blizzard's atlas tiles.
local function SetBarTexture(bar, path)
	bar:SetStatusBarTexture(path)
	local texture = bar:GetStatusBarTexture()
	texture:SetHorizTile(false)
	texture:SetVertTile(false)
	-- Blizzard puts the fill on BORDER so heal prediction and absorbs draw over it.
	texture:SetDrawLayer("BORDER")
end

local function RestoreBarTexture(bar, atlas, tiled)
	bar:SetStatusBarTexture(atlas)
	local texture = bar:GetStatusBarTexture()
	texture:SetHorizTile(tiled)
	texture:SetVertTile(tiled)
	texture:SetDrawLayer("BORDER")
end

local function StyleFrame(frame)
	if not frame or not frame.healthBar then
		return
	end
	local db = RaidFrames.db
	if db.enabled then
		SetBarTexture(frame.healthBar, GetTexturePath(db.healthTexture))
		if frame.powerBar then
			SetBarTexture(frame.powerBar, GetTexturePath(db.powerTexture))
		end
		changed[frame] = true
	elseif changed[frame] then
		RestoreBarTexture(frame.healthBar, BLIZZARD_HEALTH_ATLAS, true)
		if frame.powerBar then
			RestoreBarTexture(frame.powerBar, BLIZZARD_POWER_ATLAS, false)
		end
		changed[frame] = nil
	end
end

-- Every compact frame that exists right now, by the names Blizzard gives them:
-- CompactPartyFrame.lua / .xml, CompactRaidGroup.lua and Blizzard_CompactRaidFrameContainer.lua.
local function ForEachFrame(func)
	for i = 1, MEMBERS_PER_GROUP do
		func(_G["CompactPartyFrameMember" .. i])
		func(_G["CompactPartyFramePet" .. i])
	end
	for group = 1, MAX_RAID_GROUPS do
		for i = 1, MEMBERS_PER_GROUP do
			func(_G["CompactRaidGroup" .. group .. "Member" .. i])
		end
	end
	local i = 1
	while _G["CompactRaidFrame" .. i] do
		func(_G["CompactRaidFrame" .. i])
		i = i + 1
	end
end

function RaidFrames:Apply()
	ForEachFrame(StyleFrame)
end

function RaidFrames:OnInit()
	-- Blizzard_UnitFrame loads before any addon, so both functions exist by now.
	if DefaultCompactUnitFrameSetup then
		hooksecurefunc("DefaultCompactUnitFrameSetup", StyleFrame)
	end
	if DefaultCompactMiniFrameSetup then
		hooksecurefunc("DefaultCompactMiniFrameSetup", StyleFrame)
	end
end

function RaidFrames:OnLogin()
	-- Frames built before our hooks were in place.
	self:Apply()
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

-- A texture picker for RaidFrames.db[key]: the Unit Frames list, then shared media if loaded.
local function CreateTextureDropdown(parent, key)
	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(200)
	dropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetScrollMode(300)
		local function IsSelected(value)
			return RaidFrames.db[key] == value
		end
		local function SetSelected(value)
			RaidFrames.db[key] = value
			RaidFrames:Apply()
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
	return dropdown
end

function RaidFrames:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Party & Raid Frames", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)
	local intro = CreateLabel(page, "Changes only the bar textures of Blizzard's own party and raid frames. "
		.. "Size, layout and colours stay as set in Edit Mode.", "GameFontDisableSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local enableCheck = CreateCheck(page, "Use these textures", self.db.enabled, function(checked)
		module.db.enabled = checked
		module:Apply()
	end)
	enableCheck:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -4, -6)

	local healthLabel = CreateLabel(page, "Health bar")
	healthLabel:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 4, -10)
	healthLabel:SetWidth(120)
	self.healthDropdown = CreateTextureDropdown(page, "healthTexture")
	self.healthDropdown:SetPoint("LEFT", healthLabel, "RIGHT", 8, 0)

	local powerLabel = CreateLabel(page, "Power bar")
	powerLabel:SetPoint("TOPLEFT", healthLabel, "BOTTOMLEFT", 0, -14)
	powerLabel:SetWidth(120)
	self.powerDropdown = CreateTextureDropdown(page, "powerTexture")
	self.powerDropdown:SetPoint("LEFT", powerLabel, "RIGHT", 8, 0)
end

function RaidFrames:OnPageShown(page)
	-- The shared media list can grow after login.
	self.healthDropdown:GenerateMenu()
	self.powerDropdown:GenerateMenu()
end
