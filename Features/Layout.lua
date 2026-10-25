local addonName, ns = ...

-- Moving and lining up the addon's frames (player, target, power bar, cheapest items list).
--
-- Unlocking is one switch for all of them: the "Unlock frames" checkbox in the main
-- window's title bar. It isn't saved; closing the window locks everything again.
-- While unlocked a grid is shown, and a dragged frame snaps (when let go) to the screen
-- centre, to the edges and centres of the other frames, and to the grid; holding Shift
-- when letting go skips the snapping. The target can
-- mirror the player around the screen centre. The page shows each frame's exact X/Y.
--
-- Features hand their frames over with ns:RegisterMover(key, mover):
--   mover.title       name on the page
--   mover.getFrame()  the frame, or nil before it's built
--   mover.save(x, y)  store the centre offset from the screen centre and move the frame
-- and implement module:OnUnlockChanged(unlocked) to show/hide what unlocking changes.
-- Positions are always the frame's centre relative to the screen centre.

local Layout = ns:RegisterModule("Layout", {
	title = "Layout",
	order = 6,
	defaults = {
		showGrid = true,
		snap = true,
		gridSize = 32,
		mirror = false, -- target mirrors the player around the screen centre
	},
})

local SNAP_DISTANCE = 10 -- how close (in UI units) a frame must be to snap
local MIRROR_PAIR = { player = "target", target = "player" }

local movers = {}     -- [key] = mover
local moverOrder = {} -- keys in registration order
local unlocked = false
local grid

---------------------------------------------------------------------------
-- Registry and unlocking
---------------------------------------------------------------------------

function ns:RegisterMover(key, mover)
	movers[key] = mover
	table.insert(moverOrder, key)
end

function ns.IsUnlocked()
	return unlocked
end

local ShowGrid -- defined with the grid code
local HookMoverFrames, HideNudgeBox, RefreshNudgeBox -- defined with the nudge box code

function ns.SetUnlocked(value)
	value = value and true or false
	if unlocked == value then
		return
	end
	unlocked = value
	for _, module in ipairs(ns.modules) do
		if module.OnUnlockChanged and module.db then
			module:OnUnlockChanged(unlocked)
		end
	end
	ShowGrid(unlocked and Layout.db.showGrid)
	if unlocked then
		HookMoverFrames() -- after the modules above, so their frames exist
	else
		HideNudgeBox()
	end
	if ns.MainWindow.SetUnlockChecked then
		ns.MainWindow:SetUnlockChecked(unlocked)
	end
end

-- Centre offset from the screen centre, and the size, of a mover's frame. A hidden frame
-- (the target with nothing targeted) still has its place, except with onlyShown.
local function GetFrameBox(mover, onlyShown)
	local frame = mover.getFrame()
	if not frame or (onlyShown and not frame:IsShown()) then
		return nil
	end
	local centerX, centerY = frame:GetCenter()
	local screenX, screenY = UIParent:GetCenter()
	if not centerX then
		return nil
	end
	return centerX - screenX, centerY - screenY, frame:GetWidth(), frame:GetHeight()
end

function ns.GetMoverPosition(key)
	local mover = movers[key]
	if not mover then
		return 0, 0
	end
	local x, y = GetFrameBox(mover)
	return math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
end

local RefreshSliders -- defined with the page code

-- Moves a frame and, with mirroring on, its partner.
local function SetMoverPosition(key, x, y)
	x, y = math.floor(x + 0.5), math.floor(y + 0.5)
	movers[key].save(x, y)
	local partner = Layout.db.mirror and MIRROR_PAIR[key]
	if partner and movers[partner] then
		movers[partner].save(-x, y)
	end
	RefreshSliders()
	RefreshNudgeBox()
end
ns.SetMoverPosition = SetMoverPosition

---------------------------------------------------------------------------
-- Action bars: Blizzard's Edit Mode
---------------------------------------------------------------------------

-- The action bars stay Blizzard's (secure, owned by Edit Mode), so they're placed in
-- Edit Mode. The window's "Edit action bars" button opens it the way /editmode does,
-- hiding the window without locking (the frames and grid stay up), and brings the
-- window back when Edit Mode closes.

local editModeFromUnlock = false
local editModeHooked = false

-- True while the window is hidden for Edit Mode; the window doesn't lock on hide then.
function ns.IsInEditModeFromUnlock()
	return editModeFromUnlock
end

function ns.OpenEditMode()
	local manager = EditModeManagerFrame
	if InCombatLockdown() or not manager or not manager:CanEnterEditMode() then
		Layout:Print("Edit Mode can't be opened right now (it isn't available in combat).")
		return
	end
	if not editModeHooked then
		editModeHooked = true
		manager:HookScript("OnHide", function()
			if editModeFromUnlock then
				editModeFromUnlock = false
				ns.MainWindow:Show()
			end
		end)
	end
	editModeFromUnlock = true
	ns.MainWindow:Hide()
	ShowUIPanel(manager)
	if not manager:IsShown() then
		-- Didn't open after all: put the window back.
		editModeFromUnlock = false
		ns.MainWindow:Show()
	end
end

---------------------------------------------------------------------------
-- Nudge box: double-click a frame while unlocked
---------------------------------------------------------------------------

-- A small box above the frame with its X and Y: - and + move it 1 (10 with Shift),
-- or type a number and press Enter. The frames are of different kinds (secure unit
-- buttons, plain frames), so a double-click is two left-button releases close together.

local DOUBLE_CLICK_TIME = 0.35
local nudgeBox
local hookedFrames = {} -- [frame] = true once its double-click is hooked

local function NudgeTo(x, y)
	if nudgeBox and nudgeBox.key then
		SetMoverPosition(nudgeBox.key, x, y)
	end
end

local function CreateNudgeRow(box, anchor, axis)
	local label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
	label:SetWidth(16)
	label:SetText(axis == "x" and "X" or "Y")

	local function Step(delta)
		local x, y = ns.GetMoverPosition(nudgeBox.key)
		if IsShiftKeyDown() then
			delta = delta * 10
		end
		if axis == "x" then
			NudgeTo(x + delta, y)
		else
			NudgeTo(x, y + delta)
		end
	end

	local minus = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
	minus:SetSize(26, 22)
	minus:SetPoint("LEFT", label, "RIGHT", 4, 0)
	minus:SetText("-")
	minus:SetScript("OnClick", function()
		Step(-1)
	end)

	local edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
	edit:SetSize(60, 20)
	edit:SetPoint("LEFT", minus, "RIGHT", 10, 0)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(6)
	edit:SetJustifyH("CENTER")
	edit:SetScript("OnEnterPressed", function(self)
		local value = tonumber(self:GetText())
		if value then
			local x, y = ns.GetMoverPosition(nudgeBox.key)
			if axis == "x" then
				NudgeTo(value, y)
			else
				NudgeTo(x, value)
			end
		end
		self:ClearFocus()
	end)
	edit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	edit:SetScript("OnEditFocusLost", function()
		RefreshNudgeBox()
	end)

	local plus = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
	plus:SetSize(26, 22)
	plus:SetPoint("LEFT", edit, "RIGHT", 4, 0)
	plus:SetText("+")
	plus:SetScript("OnClick", function()
		Step(1)
	end)

	return edit, label
end

local function BuildNudgeBox()
	nudgeBox = CreateFrame("Frame", "AdamAddonNudgeBox", UIParent, "BasicFrameTemplateWithInset")
	nudgeBox:SetSize(190, 104)
	nudgeBox:SetFrameStrata("DIALOG")
	nudgeBox:SetClampedToScreen(true)
	nudgeBox:EnableMouse(true)
	nudgeBox:Hide()

	local top = CreateFrame("Frame", nil, nudgeBox)
	top:SetPoint("TOPLEFT", 14, -26)
	top:SetSize(1, 1)
	local xLabel
	nudgeBox.XEdit, xLabel = CreateNudgeRow(nudgeBox, top, "x")
	nudgeBox.YEdit = CreateNudgeRow(nudgeBox, xLabel, "y")
end

RefreshNudgeBox = function()
	if not nudgeBox or not nudgeBox:IsShown() or not nudgeBox.key then
		return
	end
	local x, y = ns.GetMoverPosition(nudgeBox.key)
	if not nudgeBox.XEdit:HasFocus() then
		nudgeBox.XEdit:SetText(tostring(x))
	end
	if not nudgeBox.YEdit:HasFocus() then
		nudgeBox.YEdit:SetText(tostring(y))
	end
end

HideNudgeBox = function()
	if nudgeBox then
		nudgeBox:Hide()
	end
end

local function ShowNudgeBox(key, frame)
	if not nudgeBox then
		BuildNudgeBox()
	end
	nudgeBox.key = key
	nudgeBox.TitleText:SetText(movers[key].title)
	nudgeBox:ClearAllPoints()
	nudgeBox:SetPoint("BOTTOM", frame, "TOP", 0, 12)
	nudgeBox:Show()
	RefreshNudgeBox()
end

-- Frames are hooked the first time the frames are unlocked after they exist.
HookMoverFrames = function()
	for key, mover in pairs(movers) do
		local frame = mover.getFrame()
		if frame and not hookedFrames[frame] then
			hookedFrames[frame] = true
			local lastRelease = 0
			frame:HookScript("OnMouseUp", function(self, button)
				if not unlocked or button ~= "LeftButton" then
					return
				end
				local now = GetTime()
				if now - lastRelease <= DOUBLE_CLICK_TIME then
					lastRelease = 0
					ShowNudgeBox(key, self)
				else
					lastRelease = now
				end
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Snapping
---------------------------------------------------------------------------

-- The offset that moves one of values onto the nearest of targets, if within reach.
local function FindSnap(values, targets)
	local best
	for _, value in ipairs(values) do
		for _, target in ipairs(targets) do
			local offset = target - value
			if math.abs(offset) <= SNAP_DISTANCE and (not best or math.abs(offset) < math.abs(best)) then
				best = offset
			end
		end
	end
	return best
end

local function SnapToGrid(value)
	local size = Layout.db.gridSize
	local nearest = math.floor(value / size + 0.5) * size
	if math.abs(nearest - value) <= SNAP_DISTANCE then
		return nearest - value
	end
end

-- x, y: the dropped frame's centre. Frame edges and centres snap first, then the grid.
local function Snap(key, x, y, width, height)
	local targetsX, targetsY = { 0 }, { 0 } -- the screen centre lines
	for otherKey, mover in pairs(movers) do
		if otherKey ~= key then
			local otherX, otherY, otherWidth, otherHeight = GetFrameBox(mover, true)
			if otherX then
				table.insert(targetsX, otherX - otherWidth / 2)
				table.insert(targetsX, otherX)
				table.insert(targetsX, otherX + otherWidth / 2)
				table.insert(targetsY, otherY - otherHeight / 2)
				table.insert(targetsY, otherY)
				table.insert(targetsY, otherY + otherHeight / 2)
			end
		end
	end

	local offsetX = FindSnap({ x - width / 2, x, x + width / 2 }, targetsX) or SnapToGrid(x) or 0
	local offsetY = FindSnap({ y - height / 2, y, y + height / 2 }, targetsY) or SnapToGrid(y) or 0
	return x + offsetX, y + offsetY
end

-- Called by a feature's OnDragStop, after StopMovingOrSizing.
function ns.MoverDropped(key)
	local mover = movers[key]
	if not mover then
		return
	end
	local x, y, width, height = GetFrameBox(mover)
	if not x then
		return
	end
	-- Holding Shift when letting go places the frame exactly where it was dropped.
	if Layout.db.snap and not IsShiftKeyDown() then
		x, y = Snap(key, x, y, width, height)
	end
	SetMoverPosition(key, x, y)
end

---------------------------------------------------------------------------
-- Grid
---------------------------------------------------------------------------

local function BuildGrid()
	grid = CreateFrame("Frame", nil, UIParent)
	grid:SetAllPoints()
	grid:SetFrameStrata("BACKGROUND")
	grid.lines = {}
	grid:Hide()
end

-- Lines every gridSize from the screen centre outwards; the centre lines in red.
local function LayoutGrid()
	local size = Layout.db.gridSize
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local thickness = PixelUtil.GetNearestPixelSize(1, UIParent:GetEffectiveScale(), 1)
	local used = 0

	local function Line(vertical, offset)
		used = used + 1
		local line = grid.lines[used]
		if not line then
			line = grid:CreateTexture(nil, "BACKGROUND")
			grid.lines[used] = line
		end
		line:ClearAllPoints()
		if vertical then
			line:SetPoint("TOP", grid, "TOP", offset, 0)
			line:SetSize(thickness, height)
		else
			line:SetPoint("LEFT", grid, "LEFT", 0, offset)
			line:SetSize(width, thickness)
		end
		if offset == 0 then
			line:SetColorTexture(1, 0.2, 0.2, 0.7)
		else
			line:SetColorTexture(0, 0, 0, 0.4)
		end
		line:Show()
	end

	for offset = 0, width / 2, size do
		Line(true, offset)
		if offset > 0 then
			Line(true, -offset)
		end
	end
	for offset = 0, height / 2, size do
		Line(false, offset)
		if offset > 0 then
			Line(false, -offset)
		end
	end
	for index = used + 1, #grid.lines do
		grid.lines[index]:Hide()
	end
end

ShowGrid = function(shown)
	if not shown then
		if grid then
			grid:Hide()
		end
		return
	end
	if not grid then
		BuildGrid()
	end
	LayoutGrid()
	grid:Show()
end

function Layout:OnScaleChanged()
	if grid and grid:IsShown() then
		LayoutGrid()
	end
end

Layout:RegisterEvent("UI_SCALE_CHANGED", "OnScaleChanged")
Layout:RegisterEvent("DISPLAY_SIZE_CHANGED", "OnScaleChanged")

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

-- onChange(value) runs when the user moves it, not when RefreshSliders sets it.
-- A short "X" or "Y" slider; the caller places the label (the slider follows it).
local function CreateSlider(parent, labelText, minValue, maxValue, value, onChange)
	local label = CreateLabel(parent, labelText)
	label:SetWidth(14)

	local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("LEFT", label, "RIGHT", 20, 0) -- room for its left stepper
	slider:SetSize(80, 20)
	slider:Init(value, minValue, maxValue, maxValue - minValue, {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(sliderValue)
			return string.format("%d", sliderValue)
		end,
	})
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, sliderValue)
		if not slider.refreshing then
			onChange(math.floor(sliderValue + 0.5))
		end
	end, slider)
	ns.MakeSliderEditable(slider)
	return slider, label
end

local positionSliders = {} -- [key] = { x = slider, y = slider }

RefreshSliders = function()
	for key, sliders in pairs(positionSliders) do
		local x, y = ns.GetMoverPosition(key)
		sliders.x.refreshing = true
		sliders.x:SetValue(x)
		sliders.x.refreshing = false
		sliders.y.refreshing = true
		sliders.y:SetValue(y)
		sliders.y.refreshing = false
	end
end

function Layout:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Layout", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)

	local intro = CreateLabel(page, "Tick |cffffd100Unlock frames|r at the top of this window to drag the frames "
		.. "below (and the blue boxes for your buffs and debuffs). Closing the window locks them again. "
		.. "Hold Shift when letting go to place a frame without snapping. Double-click a frame for a box "
		.. "to move it 1 pixel at a time or type its position. X and Y are the frame's centre, "
		.. "measured from the middle of the screen.", "GameFontDisableSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local gridCheck = CreateCheck(page, "Show grid while unlocked", self.db.showGrid, function(checked)
		module.db.showGrid = checked
		ShowGrid(unlocked and checked)
	end)
	gridCheck:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -4, -6)

	local snapCheck = CreateCheck(page, "Snap when letting go", self.db.snap, function(checked)
		module.db.snap = checked
	end)
	snapCheck:SetPoint("LEFT", gridCheck, "LEFT", 220, 0)

	local mirrorCheck = CreateCheck(page, "Target mirrors the player (same height, same distance from the centre)", self.db.mirror, function(checked)
		module.db.mirror = checked
		if checked and movers.player then
			local x, y = ns.GetMoverPosition("player")
			SetMoverPosition("player", x, y)
		end
	end)
	mirrorCheck:SetPoint("TOPLEFT", gridCheck, "BOTTOMLEFT", 0, 2)

	local gridAnchor = CreateFrame("Frame", nil, page)
	gridAnchor:SetPoint("TOPLEFT", mirrorCheck, "BOTTOMLEFT", 4, 0)
	gridAnchor:SetSize(1, 1)
	local gridLabel = CreateLabel(page, "Grid size")
	gridLabel:SetPoint("TOPLEFT", gridAnchor, "BOTTOMLEFT", 0, -10)
	gridLabel:SetWidth(90)
	local gridSlider = CreateFrame("Frame", nil, page, "MinimalSliderWithSteppersTemplate")
	gridSlider:SetPoint("LEFT", gridLabel, "RIGHT", 8, 0)
	gridSlider:SetSize(210, 20)
	gridSlider:Init(self.db.gridSize, 8, 128, 15, {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(value)
			return string.format("%d", value)
		end,
	})
	gridSlider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		module.db.gridSize = math.floor(value + 0.5)
		if grid and grid:IsShown() then
			LayoutGrid()
		end
	end, gridSlider)
	ns.MakeSliderEditable(gridSlider)

	-- One line per frame (name, X, Y), in the order the features registered them.
	local halfWidth = math.floor(UIParent:GetWidth() / 2)
	local halfHeight = math.floor(UIParent:GetHeight() / 2)
	local previous = gridLabel
	for _, key in ipairs(moverOrder) do
		local mover = movers[key]
		local header = CreateLabel(page, mover.title, "GameFontNormalSmall")
		header:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -14)
		header:SetWidth(120)
		header:SetWordWrap(false)
		local x, y = ns.GetMoverPosition(key)
		local xSlider, xLabel = CreateSlider(page, "X", -halfWidth, halfWidth, x, function(value)
			local _, currentY = ns.GetMoverPosition(key)
			SetMoverPosition(key, value, currentY)
		end)
		xLabel:SetPoint("LEFT", header, "RIGHT", 0, 0)
		local ySlider, yLabel = CreateSlider(page, "Y", -halfHeight, halfHeight, y, function(value)
			local currentX = ns.GetMoverPosition(key)
			SetMoverPosition(key, currentX, value)
		end)
		yLabel:SetPoint("LEFT", xSlider, "RIGHT", 60, 0) -- past X's value
		positionSliders[key] = { x = xSlider, y = ySlider }
		previous = header
	end
end

function Layout:OnPageShown(page)
	RefreshSliders()
end
