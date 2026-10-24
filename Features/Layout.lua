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
end
ns.SetMoverPosition = SetMoverPosition

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
local function CreateSlider(parent, anchor, labelText, minValue, maxValue, value, onChange)
	local label = CreateLabel(parent, labelText)
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
	label:SetWidth(40)

	local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("LEFT", label, "RIGHT", 8, 0)
	slider:SetSize(260, 20)
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

	local intro = CreateLabel(page, "Tick |cffffd100Unlock frames|r at the top of this window to drag the player, "
		.. "target, power bar and cheapest items list. Closing the window locks them again. "
		.. "Hold Shift when letting go to place a frame without snapping. X and Y are the frame's centre, "
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

	-- One X and Y pair per frame, in the order the features registered them.
	local halfWidth = math.floor(UIParent:GetWidth() / 2)
	local halfHeight = math.floor(UIParent:GetHeight() / 2)
	local previous = gridLabel
	for _, key in ipairs(moverOrder) do
		local mover = movers[key]
		local header = CreateLabel(page, mover.title, "GameFontNormal")
		header:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -16)
		local x, y = ns.GetMoverPosition(key)
		local xSlider, xLabel = CreateSlider(page, header, "X", -halfWidth, halfWidth, x, function(value)
			local _, currentY = ns.GetMoverPosition(key)
			SetMoverPosition(key, value, currentY)
		end)
		local ySlider, yLabel = CreateSlider(page, xLabel, "Y", -halfHeight, halfHeight, y, function(value)
			local currentX = ns.GetMoverPosition(key)
			SetMoverPosition(key, currentX, value)
		end)
		positionSliders[key] = { x = xSlider, y = ySlider }
		previous = yLabel
	end
end

function Layout:OnPageShown(page)
	RefreshSliders()
end
