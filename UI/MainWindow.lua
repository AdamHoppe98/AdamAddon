local addonName, ns = ...

-- The main window: a menu on the left with one entry per feature that has a page,
-- and a content area on the right where the selected feature's page is shown.
-- Drawn by hand (flat dark panels, violet-to-cyan accent) rather than with a Blizzard frame template.

local MainWindow = {}
ns.MainWindow = MainWindow

local WINDOW_WIDTH = 640
local WINDOW_HEIGHT = 610
local NAV_WIDTH = 150
local NAV_BUTTON_HEIGHT = 22
local TITLE_HEIGHT = 34
local SIDEBAR_WIDTH = NAV_WIDTH + 14

local FONT = "Interface\\AddOns\\" .. addonName .. "\\Media\\Fonts\\Expressway.ttf"

local COLORS = {
	background = { 0.055, 0.06, 0.075, 0.97 },
	sidebar = { 0.035, 0.04, 0.05, 1 },
	titleTop = { 0.10, 0.11, 0.145, 1 },
	titleBottom = { 0.06, 0.065, 0.085, 1 },
	border = { 0.18, 0.2, 0.26, 1 },
	accentA = { 0.58, 0.36, 1 },  -- violet
	accentB = { 0.2, 0.85, 1 },   -- cyan
	text = { 0.78, 0.8, 0.86 },
	textDim = { 0.5, 0.53, 0.6 },
	textSelected = { 1, 1, 1 },
	close = { 1, 0.35, 0.42 },
}

local frame
local content
local emptyText
local navButtons = {}
local pages = {}
local currentPage

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	ns.db.window.point = { point, relativePoint, x, y }
end

local function RestorePosition()
	frame:ClearAllPoints()
	local saved = ns.db.window.point
	if saved then
		frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
	else
		frame:SetPoint("CENTER")
	end
end

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------

local function Color(c, alpha)
	return CreateColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

local function SolidTexture(parent, layer, c, alpha, subLevel)
	local tex = parent:CreateTexture(nil, layer, nil, subLevel)
	tex:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
	return tex
end

-- Gradient from c1 to c2: left to right for "HORIZONTAL", bottom to top for "VERTICAL".
local function GradientTexture(parent, layer, orientation, c1, a1, c2, a2, subLevel)
	local tex = parent:CreateTexture(nil, layer, nil, subLevel)
	tex:SetColorTexture(1, 1, 1, 1)
	tex:SetGradient(orientation, Color(c1, a1), Color(c2, a2))
	return tex
end

local function SetFont(fontString, size, c)
	fontString:SetFont(FONT, size, "")
	fontString:SetShadowOffset(1, -1)
	fontString:SetShadowColor(0, 0, 0, 0.8)
	if c then
		fontString:SetTextColor(c[1], c[2], c[3])
	end
end

-- A one-pixel line around `region`, inside its edges.
local function AddBorder(parent, region, c, alpha)
	local top = SolidTexture(parent, "BORDER", c, alpha)
	top:SetPoint("TOPLEFT", region, "TOPLEFT")
	top:SetPoint("TOPRIGHT", region, "TOPRIGHT")
	PixelUtil.SetHeight(top, 1, 1)

	local bottom = SolidTexture(parent, "BORDER", c, alpha)
	bottom:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT")
	PixelUtil.SetHeight(bottom, 1, 1)

	local left = SolidTexture(parent, "BORDER", c, alpha)
	left:SetPoint("TOPLEFT", region, "TOPLEFT")
	left:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT")
	PixelUtil.SetWidth(left, 1, 1)

	local right = SolidTexture(parent, "BORDER", c, alpha)
	right:SetPoint("TOPRIGHT", region, "TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT")
	PixelUtil.SetWidth(right, 1, 1)
end

-- A soft shadow: stacked black rings, each a little wider and fainter.
local function AddShadow(target)
	for i = 1, 8 do
		local shadow = target:CreateTexture(nil, "BACKGROUND", nil, -8)
		shadow:SetColorTexture(0, 0, 0, 0.07)
		shadow:SetPoint("TOPLEFT", -i, i)
		shadow:SetPoint("BOTTOMRIGHT", i, -i)
	end
end

---------------------------------------------------------------------------
-- Pieces of the window
---------------------------------------------------------------------------

local function CreateNavButton(parent, module, index)
	local button = CreateFrame("Button", nil, parent)
	button:SetHeight(NAV_BUTTON_HEIGHT)
	button:SetPoint("TOPLEFT", 0, -(index - 1) * NAV_BUTTON_HEIGHT)
	button:SetPoint("TOPRIGHT", 0, -(index - 1) * NAV_BUTTON_HEIGHT)

	local hover = SolidTexture(button, "HIGHLIGHT", { 1, 1, 1 }, 0.05)
	hover:SetAllPoints()

	-- Pages with a navParent are listed indented and smaller, under that page.
	local isChild = module.navParent ~= nil
	local normalColor = isChild and COLORS.textDim or COLORS.text

	-- Shown by ShowPage for the current page: an accent bar on the left and a glow fading right.
	local selected = CreateFrame("Frame", nil, button)
	selected:SetAllPoints()
	selected:SetFrameLevel(button:GetFrameLevel() + 1)
	local glow = GradientTexture(selected, "BACKGROUND", "HORIZONTAL", COLORS.accentA, 0.3, COLORS.accentA, 0)
	glow:SetAllPoints()
	local bar = GradientTexture(selected, "ARTWORK", "VERTICAL", COLORS.accentA, 1, COLORS.accentB, 1)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("BOTTOMLEFT")
	bar:SetWidth(2)
	selected:Hide()
	button.Selected = selected

	-- The label sits above the selection glow.
	local textHolder = CreateFrame("Frame", nil, button)
	textHolder:SetAllPoints()
	textHolder:SetFrameLevel(button:GetFrameLevel() + 2)

	button.Text = textHolder:CreateFontString(nil, "OVERLAY")
	SetFont(button.Text, isChild and 12 or 14, normalColor)
	button.Text:SetPoint("LEFT", isChild and 22 or 10, 0)
	button.Text:SetPoint("RIGHT", -4, 0)
	button.Text:SetJustifyH("LEFT")
	button.Text:SetWordWrap(false)
	button.Text:SetText(module.title)

	selected:SetScript("OnShow", function()
		button.Text:SetTextColor(unpack(COLORS.textSelected))
	end)
	selected:SetScript("OnHide", function()
		button.Text:SetTextColor(unpack(normalColor))
	end)

	button:SetScript("OnClick", function()
		MainWindow:ShowPage(module.name)
	end)

	navButtons[module.name] = button
	return button
end

local function CreateCloseButton(parent)
	local close = CreateFrame("Button", nil, parent)
	close:SetSize(TITLE_HEIGHT, TITLE_HEIGHT)
	close:SetPoint("TOPRIGHT")

	local hover = SolidTexture(close, "BACKGROUND", COLORS.close, 0.15)
	hover:SetAllPoints()
	hover:Hide()

	-- An X from two thin rotated lines.
	local lines = {}
	for i, angle in ipairs({ 45, -45 }) do
		local line = SolidTexture(close, "ARTWORK", COLORS.textDim)
		line:SetSize(14, 2)
		line:SetPoint("CENTER")
		line:SetRotation(math.rad(angle))
		lines[i] = line
	end

	local function Paint(c)
		for _, line in ipairs(lines) do
			line:SetColorTexture(c[1], c[2], c[3], 1)
		end
	end

	close:SetScript("OnEnter", function()
		hover:Show()
		Paint(COLORS.close)
	end)
	close:SetScript("OnLeave", function()
		hover:Hide()
		Paint(COLORS.textDim)
	end)
	close:SetScript("OnClick", function()
		parent:Hide()
	end)
	return close
end

-- Flat button in the accent colour.
local function CreateAccentButton(parent, width, height)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, height)

	local bg = GradientTexture(button, "BACKGROUND", "HORIZONTAL", COLORS.accentA, 0.35, COLORS.accentB, 0.25)
	bg:SetAllPoints()
	AddBorder(button, button, COLORS.accentA, 0.8)

	local hover = SolidTexture(button, "HIGHLIGHT", { 1, 1, 1 }, 0.1)
	hover:SetAllPoints()

	local text = button:CreateFontString(nil, "OVERLAY")
	SetFont(text, 12, COLORS.textSelected)
	text:SetPoint("CENTER")
	button:SetFontString(text)
	button:SetPushedTextOffset(1, -1)
	return button
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function BuildFrame()
	frame = CreateFrame("Frame", "AdamAddonMainWindow", UIParent)
	frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	frame:Hide()

	-- Body
	AddShadow(frame)
	local background = SolidTexture(frame, "BACKGROUND", COLORS.background)
	background:SetAllPoints()

	-- Title bar: gradient strip, accent line under it, and a faint glow below the line.
	local titleBar = GradientTexture(frame, "BACKGROUND", "VERTICAL", COLORS.titleBottom, nil, COLORS.titleTop, nil, 1)
	titleBar:SetPoint("TOPLEFT")
	titleBar:SetPoint("TOPRIGHT")
	titleBar:SetHeight(TITLE_HEIGHT)

	local accentLine = GradientTexture(frame, "ARTWORK", "HORIZONTAL", COLORS.accentA, 1, COLORS.accentB, 1)
	accentLine:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT")
	accentLine:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT")
	PixelUtil.SetHeight(accentLine, 2, 1)

	local accentGlow = GradientTexture(frame, "ARTWORK", "VERTICAL", COLORS.accentA, 0, COLORS.accentA, 0.18)
	accentGlow:SetPoint("TOPLEFT", accentLine, "BOTTOMLEFT")
	accentGlow:SetPoint("TOPRIGHT", accentLine, "BOTTOMRIGHT")
	accentGlow:SetHeight(6)

	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ns.icon)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetSize(20, 20)
	icon:SetPoint("LEFT", titleBar, "LEFT", 10, 0)

	frame.TitleText = frame:CreateFontString(nil, "OVERLAY")
	SetFont(frame.TitleText, 16, COLORS.textSelected)
	frame.TitleText:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	frame.TitleText:SetText(ns.title:upper() .. "  |cff7f8799v" .. ns.version .. "|r")

	frame.CloseButton = CreateCloseButton(frame)

	-- ESC closes the window.
	table.insert(UISpecialFrames, frame:GetName())

	-- Unlock for all movable frames (Features/Layout.lua), in the title bar so it's there
	-- on every page. Closing the window locks them again.
	local unlockCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	unlockCheck:SetSize(22, 22)
	SetFont(unlockCheck.Text, 12, COLORS.text)
	unlockCheck.Text:SetText("Unlock frames")
	unlockCheck:SetPoint("RIGHT", frame.CloseButton, "LEFT", -(unlockCheck.Text:GetStringWidth() + 12), 0)
	unlockCheck:SetScript("OnClick", function(button)
		if ns.SetUnlocked then
			ns.SetUnlocked(button:GetChecked())
		end
	end)
	frame.UnlockCheck = unlockCheck

	-- The action bars are placed in Blizzard's Edit Mode; this opens it while unlocked.
	local editModeButton = CreateAccentButton(frame, 110, 20)
	editModeButton:SetPoint("RIGHT", unlockCheck, "LEFT", -10, 0)
	editModeButton:SetText("Edit action bars")
	editModeButton:SetScript("OnClick", function()
		if ns.OpenEditMode then
			ns.OpenEditMode()
		end
	end)
	editModeButton:Hide()
	frame.EditModeButton = editModeButton

	-- Closing locks the frames, except when the window only steps aside for Edit Mode.
	frame:HookScript("OnHide", function()
		if ns.IsInEditModeFromUnlock and ns.IsInEditModeFromUnlock() then
			return
		end
		if ns.SetUnlocked then
			ns.SetUnlocked(false)
		end
	end)

	-- Sidebar
	local sidebar = SolidTexture(frame, "BACKGROUND", COLORS.sidebar, nil, 2)
	sidebar:SetPoint("TOPLEFT", 0, -(TITLE_HEIGHT + 2))
	sidebar:SetPoint("BOTTOMLEFT")
	sidebar:SetWidth(SIDEBAR_WIDTH)

	local divider = SolidTexture(frame, "BORDER", COLORS.border)
	divider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT")
	divider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT")
	PixelUtil.SetWidth(divider, 1, 1)

	local nav = CreateFrame("Frame", nil, frame)
	nav:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -10)
	nav:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 0, 10)
	nav:SetWidth(SIDEBAR_WIDTH)

	-- Outline last, so it sits on top of the title bar and sidebar edges.
	AddBorder(frame, frame, COLORS.border)

	content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 12, -8)
	content:SetPoint("BOTTOMRIGHT", -14, 12)

	emptyText = content:CreateFontString(nil, "OVERLAY")
	SetFont(emptyText, 14, COLORS.textDim)
	emptyText:SetPoint("CENTER")
	emptyText:SetText("No features yet.")

	local index = 0
	for _, module in ipairs(ns:GetSortedModules()) do
		if module.CreatePage then
			index = index + 1
			CreateNavButton(nav, module, index)
		end
	end
	emptyText:SetShown(index == 0)

	RestorePosition()
end

function MainWindow:Init()
	BuildFrame()
end

-- Called by Layout when frames are locked or unlocked.
function MainWindow:SetUnlockChecked(checked)
	if frame then
		frame.UnlockCheck:SetChecked(checked)
		frame.EditModeButton:SetShown(checked)
	end
end

function MainWindow:ShowPage(name)
	local module = ns:GetModule(name)
	if not module or not module.CreatePage then
		return
	end

	if currentPage and currentPage ~= name then
		pages[currentPage]:Hide()
		navButtons[currentPage].Selected:Hide()
	end

	local page = pages[name]
	if not page then
		page = CreateFrame("Frame", nil, content)
		page:SetAllPoints()
		page:Hide()
		module:CreatePage(page)
		-- OnShow fires both when switching to this page and when the window is reopened on it.
		if module.OnPageShown then
			page:SetScript("OnShow", function(self)
				module:OnPageShown(self)
			end)
		end
		pages[name] = page
	end

	navButtons[name].Selected:Show()
	currentPage = name
	ns.db.window.page = name

	page:Show()
	frame:Show()
end

local function FirstPageName()
	for _, module in ipairs(ns:GetSortedModules()) do
		if module.CreatePage then
			return module.name
		end
	end
end

function MainWindow:Show()
	if currentPage then
		frame:Show()
		return
	end

	local saved = ns.db.window.page
	local savedModule = saved and ns:GetModule(saved)
	local name = (savedModule and savedModule.CreatePage and saved) or FirstPageName()
	if name then
		self:ShowPage(name)
	else
		frame:Show()
	end
end

function MainWindow:Hide()
	frame:Hide()
end

function MainWindow:Toggle()
	if frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

function MainWindow:ResetPosition()
	ns.db.window.point = nil
	RestorePosition()
	frame:Show()
end
