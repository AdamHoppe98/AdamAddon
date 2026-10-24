local addonName, ns = ...

-- One font and outline for the whole addon: action button texts, unit frames and the
-- power bar. Features read it with ns.GetFont() and keep their own text sizes.
-- "Blizzard default" has no path: the action bars then keep Blizzard's own face, the
-- other features fall back to Friz Quadrata.
-- When the font or outline changes, every module with OnFontChanged is told.

local Fonts = ns:RegisterModule("Fonts", {
	title = "Fonts",
	order = 5,
	defaults = {
		font = "default",   -- key in FONTS, or a LibSharedMedia font name
		outline = "OUTLINE",
	},
})

-- The ones in Media\Fonts come from ElvUI.
local FONT_MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\Fonts\\"
local FONTS = {
	{ key = "default", name = "Blizzard default" },
	{ key = "friz", name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
	{ key = "arialn", name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
	{ key = "morpheus", name = "Morpheus", path = "Fonts\\MORPHEUS.ttf" },
	{ key = "skurri", name = "Skurri", path = "Fonts\\skurri.ttf" },
	{ key = "expressway", name = "Expressway", path = FONT_MEDIA .. "Expressway.ttf" },
	{ key = "ptsansnarrow", name = "PT Sans Narrow", path = FONT_MEDIA .. "PTSansNarrow.ttf" },
	{ key = "continuum", name = "Continuum Medium", path = FONT_MEDIA .. "ContinuumMedium.ttf" },
	{ key = "actionman", name = "Action Man", path = FONT_MEDIA .. "ActionMan.ttf" },
	{ key = "diediedie", name = "Die Die Die!", path = FONT_MEDIA .. "DieDieDie.ttf" },
	{ key = "homespun", name = "Homespun (pixel)", path = FONT_MEDIA .. "Homespun.ttf" },
}

local OUTLINES = {
	{ key = "", name = "None" },
	{ key = "OUTLINE", name = "Outline" },
	{ key = "THICKOUTLINE", name = "Thick outline" },
	{ key = "MONOCHROME, OUTLINE", name = "Monochrome outline" },
}

local PREVIEW_TEXT = "The quick brown fox 0123456789"

-- LibSharedMedia is optional; other addons (e.g. Plater) often load it.
local function GetSharedMedia()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- nil for "default" or a shared media font that isn't there (any more).
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

-- path (nil = Blizzard's), outline. Can be called before the settings are loaded.
function ns.GetFont()
	local db = Fonts.db
	if not db then
		return nil, "OUTLINE"
	end
	return GetFontPath(db.font), db.outline
end

local function NotifyFontChanged()
	for _, module in ipairs(ns.modules) do
		if module.OnFontChanged and module.db then
			module:OnFontChanged()
		end
	end
end

-- Takes over the font each feature had before there was one for all: the unit frames'
-- own pick if it had one, otherwise the action bars' font, and their outline.
function Fonts:OnInit()
	if self.db.migrated then
		return
	end
	local modules = ns.db.modules
	local actionBars = modules.ActionBars
	local unitFrames = modules.UnitFrames
	local font = unitFrames and unitFrames.font
	if font == nil or font == "actionbars" then
		font = actionBars and actionBars.font
	end
	if font then
		self.db.font = font
	end
	if actionBars and actionBars.outline then
		self.db.outline = actionBars.outline
	end
	if actionBars then
		actionBars.font = nil
		actionBars.outline = nil
	end
	if unitFrames then
		unitFrames.font = nil
	end
	self.db.migrated = true
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

-- setup(rootDescription) fills the menu.
local function CreateDropdown(parent, anchor, labelText, setup)
	local label = CreateLabel(parent, labelText)
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
	label:SetWidth(100)

	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("LEFT", label, "RIGHT", 8, 0)
	dropdown:SetWidth(220)
	dropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetScrollMode(300)
		setup(rootDescription)
	end)
	return dropdown, label
end

function Fonts:UpdatePreview()
	if not self.preview then
		return
	end
	local path, outline = ns.GetFont()
	if not path then
		path = GameFontHighlightLarge:GetFont()
	end
	self.preview:SetFont(path, 16, outline)
	self.preview:SetText(PREVIEW_TEXT)
end

function Fonts:SetFont(key)
	self.db.font = key
	self:UpdatePreview()
	NotifyFontChanged()
end

function Fonts:SetOutline(key)
	self.db.outline = key
	self:UpdatePreview()
	NotifyFontChanged()
end

function Fonts:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Fonts", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)

	local intro = CreateLabel(page, "Used by the action bar texts, the unit frames and the power bar. "
		.. "Text sizes are set on each feature's own page.", "GameFontDisableSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local fontDropdown, fontLabel = CreateDropdown(page, intro, "Font", function(rootDescription)
		local function IsSelected(key)
			return module.db.font == key
		end
		local function SetSelected(key)
			module:SetFont(key)
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
	self.fontDropdown = fontDropdown

	local _, outlineLabel = CreateDropdown(page, fontLabel, "Outline", function(rootDescription)
		local function IsSelected(key)
			return module.db.outline == key
		end
		local function SetSelected(key)
			module:SetOutline(key)
		end
		for _, outline in ipairs(OUTLINES) do
			rootDescription:CreateRadio(outline.name, IsSelected, SetSelected, outline.key)
		end
	end)

	self.preview = page:CreateFontString(nil, "OVERLAY")
	self.preview:SetPoint("TOPLEFT", outlineLabel, "BOTTOMLEFT", 0, -24)
	self.preview:SetJustifyH("LEFT")
	self:UpdatePreview()
end

function Fonts:OnPageShown(page)
	-- The shared media list can grow after login.
	self.fontDropdown:GenerateMenu()
	self:UpdatePreview()
end
