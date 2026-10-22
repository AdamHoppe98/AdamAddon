local addonName, ns = ...

-- The main window: a menu on the left with one entry per feature that has a page,
-- and a content area on the right where the selected feature's page is shown.

local MainWindow = {}
ns.MainWindow = MainWindow

local WINDOW_WIDTH = 640
local WINDOW_HEIGHT = 420
local NAV_WIDTH = 150
local NAV_BUTTON_HEIGHT = 22

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

local function CreateNavButton(parent, module, index)
	local button = CreateFrame("Button", nil, parent)
	button:SetHeight(NAV_BUTTON_HEIGHT)
	button:SetPoint("TOPLEFT", 0, -(index - 1) * NAV_BUTTON_HEIGHT)
	button:SetPoint("TOPRIGHT", 0, -(index - 1) * NAV_BUTTON_HEIGHT)
	button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	button.Selected = button:CreateTexture(nil, "BACKGROUND")
	button.Selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	button.Selected:SetBlendMode("ADD")
	button.Selected:SetAllPoints()
	button.Selected:Hide()

	button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	button.Text:SetPoint("LEFT", 8, 0)
	button.Text:SetPoint("RIGHT", -4, 0)
	button.Text:SetJustifyH("LEFT")
	button.Text:SetText(module.title)

	button:SetScript("OnClick", function()
		MainWindow:ShowPage(module.name)
	end)

	navButtons[module.name] = button
	return button
end

local function BuildFrame()
	frame = CreateFrame("Frame", "AdamAddonMainWindow", UIParent, "BasicFrameTemplateWithInset")
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

	frame.TitleText:SetText(ns.title .. "  |cff808080v" .. ns.version .. "|r")

	-- ESC closes the window.
	table.insert(UISpecialFrames, frame:GetName())

	local nav = CreateFrame("Frame", nil, frame)
	nav:SetPoint("TOPLEFT", 10, -32)
	nav:SetPoint("BOTTOMLEFT", 10, 10)
	nav:SetWidth(NAV_WIDTH)

	local divider = frame:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(1, 1, 1, 0.15)
	divider:SetWidth(1)
	divider:SetPoint("TOPLEFT", nav, "TOPRIGHT", 6, 0)
	divider:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT", 6, 0)

	content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", nav, "TOPRIGHT", 16, 0)
	content:SetPoint("BOTTOMRIGHT", -14, 12)

	emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
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
