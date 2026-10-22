local addonName, ns = ...

-- A round button on the edge of the minimap. Click toggles the main window,
-- drag moves it around the minimap. Position is saved as an angle.

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local button

local function UpdatePosition()
	local angle = math.rad(ns.db.minimap.angle)
	local radius = (Minimap:GetWidth() / 2) + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
	local centerX, centerY = Minimap:GetCenter()
	local cursorX, cursorY = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cursorX, cursorY = cursorX / scale, cursorY / scale
	ns.db.minimap.angle = math.deg(math.atan2(cursorY - centerY, cursorX - centerX)) % 360
	UpdatePosition()
end

local function BuildButton()
	button = CreateFrame("Button", "AdamAddonMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ns.icon)
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	button.Icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "LeftButton" then
			ns.MainWindow:Toggle()
		end
	end)

	button:SetScript("OnDragStart", function(self)
		self:LockHighlight()
		self:SetScript("OnUpdate", OnDragUpdate)
		GameTooltip:Hide()
	end)

	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
	end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(ns.title)
		GameTooltip:AddLine("Click to open or close the window.", 1, 1, 1)
		GameTooltip:AddLine("Drag to move this icon.", 1, 1, 1)
		GameTooltip:Show()
	end)

	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

function MinimapButton:Init()
	BuildButton()
	UpdatePosition()
	button:SetShown(not ns.db.minimap.hide)
end

function MinimapButton:SetHidden(hidden)
	ns.db.minimap.hide = hidden
	button:SetShown(not hidden)
	if hidden then
		ns:Print("minimap icon hidden. Type /adam minimap to bring it back.")
	end
end

-- Named in the TOC (AddonCompartmentFunc): the entry in Blizzard's addon menu on the minimap.
function AdamAddon_OnAddonCompartmentClick()
	ns.MainWindow:Toggle()
end
