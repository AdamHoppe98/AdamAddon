local addonName, ns = ...

-- PvP flag icon: a small faction badge that shows while you are PvP flagged, so you
-- notice before the other faction does.
--
-- Until you move it, it sits on the top-left corner of the player frame. Unlock frames
-- (or the Layout page) moves it anywhere; the position is then saved as an offset from
-- the screen centre, like the other movable frames. While unlocked it is always shown,
-- with a blue background, so it can be found and dragged.

local PvPFlag = ns:RegisterModule("PvPFlag", {
	title = "PvP Flag",
	order = 28,
	defaults = {
		enabled = true,
		size = 32,
		position = nil, -- { x, y } icon centre from the screen centre; nil = on the player frame
	},
})

local PLAYER_FRAME = "AdamAddonPlayerFrame" -- built by UnitFrames
local FALLBACK_POSITION = { -250, -150 }    -- when the player frame doesn't exist

local ICONS = {
	Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
	Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
}
local ICON_OTHER = "Interface\\TargetingFrame\\UI-PVP-FFA"

local icon
local isTest = false

local function IsUnlocked()
	return ns.IsUnlocked ~= nil and ns.IsUnlocked()
end

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function IsFlagged()
	local flagged = UnitIsPVP("player")
	if IsSecret(flagged) then
		return false
	end
	return flagged and true or false
end

---------------------------------------------------------------------------
-- The icon
---------------------------------------------------------------------------

local function Build()
	icon = CreateFrame("Frame", "AdamAddonPvPFlagFrame", UIParent)
	icon:SetFrameStrata("MEDIUM")
	icon:SetClampedToScreen(true)
	icon:SetMovable(true)
	icon:RegisterForDrag("LeftButton")
	icon:SetScript("OnDragStart", function(self)
		if IsUnlocked() then
			self:StartMoving()
			self.moving = true
		end
	end)
	icon:SetScript("OnDragStop", function(self)
		if not self.moving then
			return
		end
		self.moving = false
		self:StopMovingOrSizing()
		ns.MoverDropped("pvpflag") -- snaps and saves
	end)

	icon.Background = icon:CreateTexture(nil, "BACKGROUND")
	icon.Background:SetAllPoints()
	icon.Background:SetColorTexture(0.2, 0.6, 1, 0.25)

	icon.Texture = icon:CreateTexture(nil, "ARTWORK")
	icon.Texture:SetAllPoints()

	icon.Label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	icon.Label:SetPoint("BOTTOM", icon, "TOP", 0, 2)
	icon.Label:SetText("PvP flag")
end

local function PlaceIcon()
	icon:ClearAllPoints()
	local position = PvPFlag.db.position
	if position then
		icon:SetPoint("CENTER", UIParent, "CENTER", position[1], position[2])
		return
	end
	local playerFrame = _G[PLAYER_FRAME]
	if playerFrame then
		icon:SetPoint("CENTER", playerFrame, "TOPLEFT", 0, 0)
	else
		icon:SetPoint("CENTER", UIParent, "CENTER", FALLBACK_POSITION[1], FALLBACK_POSITION[2])
	end
end

local function UpdateTexture()
	local faction = UnitFactionGroup("player")
	if IsSecret(faction) then
		faction = nil
	end
	icon.Texture:SetTexture(ICONS[faction] or ICON_OTHER)
end

function PvPFlag:Refresh()
	if not icon then
		return
	end
	local db = self.db
	local unlocked = IsUnlocked()
	icon:SetSize(db.size, db.size)
	PlaceIcon()
	UpdateTexture()
	icon:EnableMouse(unlocked)
	icon.Background:SetShown(unlocked)
	icon.Label:SetShown(unlocked)
	icon:SetShown(db.enabled and (unlocked or isTest or IsFlagged()))
end

function PvPFlag:SetTest(test)
	isTest = test
	self:Refresh()
end

function PvPFlag:ResetPosition()
	self.db.position = nil
	self:Refresh()
end

if ns.RegisterMover then
	ns:RegisterMover("pvpflag", {
		title = "PvP flag icon",
		getFrame = function()
			if PvPFlag.db and PvPFlag.db.enabled then
				return icon
			end
		end,
		save = function(x, y)
			PvPFlag.db.position = { x, y }
			if icon then
				PlaceIcon()
			end
		end,
	})
end

function PvPFlag:OnLogin()
	Build()
	self:Refresh()
end

-- The Unlock frames checkbox: the icon is shown and takes the mouse.
function PvPFlag:OnUnlockChanged()
	self:Refresh()
end

function PvPFlag:OnFlagChanged(event, unit)
	if unit == nil or unit == "player" then
		self:Refresh()
	end
end

PvPFlag:RegisterEvent("PLAYER_FLAGS_CHANGED", "OnFlagChanged")
PvPFlag:RegisterEvent("UNIT_FACTION", "OnFlagChanged")
PvPFlag:RegisterEvent("PLAYER_ENTERING_WORLD", "OnFlagChanged")

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------

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

function PvPFlag:CreatePage(page)
	local module = self

	local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)
	title:SetText("PvP Flag")

	local help = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	help:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	help:SetJustifyH("LEFT")
	help:SetText("Shows an icon while you are PvP flagged. It starts on the top-left corner of the "
		.. "player frame. To move it, tick Unlock frames in the window's title bar and drag it "
		.. "(or set X/Y on the Layout page).")

	local enableCheck = CreateCheck(page, "Show the icon when PvP flagged", self.db.enabled, function(checked)
		module.db.enabled = checked
		module:Refresh()
	end)
	enableCheck:SetPoint("TOPLEFT", help, "BOTTOMLEFT", -4, -10)
	self.enableCheck = enableCheck

	local testCheck = CreateCheck(page, "Preview (show it even when not flagged)", isTest, function(checked)
		module:SetTest(checked)
	end)
	testCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, 2)

	local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	reset:SetPoint("TOPLEFT", testCheck, "BOTTOMLEFT", 4, -10)
	reset:SetSize(140, 22)
	reset:SetText("Reset position")
	reset:SetScript("OnClick", function()
		module:ResetPosition()
	end)
end

function PvPFlag:OnPageShown(page)
	self.enableCheck:SetChecked(self.db.enabled)
end
