local addonName, ns = ...

-- Restyles Blizzard's chat windows to match the addon's window: flat dark background,
-- one-pixel border in the window's border color, and the addon font with a soft shadow
-- instead of a black outline. Open the page with /adam chat.
-- Blizzard's own background and border art is hidden, not removed: switching the restyle
-- off brings it back; the font needs a /reload to go back.

local Chat = ns:RegisterModule("Chat", {
	title = "Chat",
	order = 12,
	defaults = {
		enabled = true,
		backgroundOpacity = 90, -- percent
	},
})

-- Same colors as UI/MainWindow.lua.
local BACKGROUND = { 0.055, 0.06, 0.075 }
local BORDER = { 0.18, 0.2, 0.26, 1 }
local FALLBACK_FONT = "Interface\\AddOns\\" .. addonName .. "\\Media\\Fonts\\Expressway.ttf"

-- Blizzard's frame art, by name suffix after ChatFrameN.
local ART = { "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }

local function GetChatFrames()
	local frames = {}
	for _, name in ipairs(CHAT_FRAMES or {}) do
		local chatFrame = _G[name]
		if chatFrame then
			table.insert(frames, chatFrame)
		end
	end
	return frames
end

-- Our background and border, created once per chat frame.
local function GetSkin(chatFrame)
	if chatFrame.AdamSkin then
		return chatFrame.AdamSkin
	end
	local skin = {}

	skin.background = chatFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
	skin.background:SetColorTexture(BACKGROUND[1], BACKGROUND[2], BACKGROUND[3], 1)

	skin.lines = {}
	for i = 1, 4 do
		local line = chatFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
		line:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
		skin.lines[i] = line
	end
	local top, bottom, left, right = unpack(skin.lines)
	top:SetPoint("TOPLEFT", skin.background, "TOPLEFT")
	top:SetPoint("TOPRIGHT", skin.background, "TOPRIGHT")
	PixelUtil.SetHeight(top, 1, 1)
	bottom:SetPoint("BOTTOMLEFT", skin.background, "BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT", skin.background, "BOTTOMRIGHT")
	PixelUtil.SetHeight(bottom, 1, 1)
	left:SetPoint("TOPLEFT", skin.background, "TOPLEFT")
	left:SetPoint("BOTTOMLEFT", skin.background, "BOTTOMLEFT")
	PixelUtil.SetWidth(left, 1, 1)
	right:SetPoint("TOPRIGHT", skin.background, "TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT", skin.background, "BOTTOMRIGHT")
	PixelUtil.SetWidth(right, 1, 1)

	chatFrame.AdamSkin = skin
	return skin
end

local function SetSkinShown(skin, shown)
	skin.background:SetShown(shown)
	for _, line in ipairs(skin.lines) do
		line:SetShown(shown)
	end
end

local function StyleFrame(chatFrame, db)
	local name = chatFrame:GetName()
	local blizzardBackground = chatFrame.Background or _G[name .. "Background"]
	local skin = GetSkin(chatFrame)

	if db.enabled and blizzardBackground then
		-- Sit exactly where Blizzard's background is, so resizing the window still works.
		skin.background:ClearAllPoints()
		skin.background:SetPoint("TOPLEFT", blizzardBackground, "TOPLEFT")
		skin.background:SetPoint("BOTTOMRIGHT", blizzardBackground, "BOTTOMRIGHT")
		skin.background:SetAlpha(db.backgroundOpacity / 100)
		SetSkinShown(skin, true)
		blizzardBackground:SetAlpha(0)
		for _, suffix in ipairs(ART) do
			local art = _G[name .. suffix]
			if art then
				art:Hide()
			end
		end

		-- The addon's font, with a shadow instead of the black outline. Size is the
		-- player's own (chat window settings).
		local path = ns.GetFont()
		local currentPath, size = chatFrame:GetFont()
		path = path or currentPath or FALLBACK_FONT
		if size then
			chatFrame:SetFont(path, size, "")
			chatFrame:SetShadowOffset(1, -1)
			chatFrame:SetShadowColor(0, 0, 0, 0.8)
		end
	else
		SetSkinShown(skin, false)
		if blizzardBackground then
			blizzardBackground:SetAlpha(1)
		end
		for _, suffix in ipairs(ART) do
			local art = _G[name .. suffix]
			if art then
				art:Show()
			end
		end
	end
end

function Chat:Refresh()
	for _, chatFrame in ipairs(GetChatFrames()) do
		StyleFrame(chatFrame, self.db)
	end
end

function Chat:SetEnabled(enabled)
	self.db.enabled = enabled
	self:Refresh()
	if not enabled then
		self:Print("chat font goes back to Blizzard's after /reload.")
	end
end

function Chat:OnLogin()
	self:Refresh()
	-- Temporary windows (whispers, pop-outs) are created later.
	hooksecurefunc("FCF_OpenTemporaryWindow", function()
		Chat:Refresh()
	end)
end

-- The Fonts page changed the font.
function Chat:OnFontChanged()
	self:Refresh()
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

function Chat:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Chat", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)

	local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	check:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -4, -10)
	check.Text:SetFontObject("GameFontHighlight")
	check.Text:SetText("Restyle the chat windows to match the addon")
	check:SetChecked(self.db.enabled)
	check:SetScript("OnClick", function(button)
		module:SetEnabled(button:GetChecked())
	end)
	self.enableCheck = check

	local label = CreateLabel(page, "Background")
	label:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 4, -18)
	label:SetWidth(110)

	local slider = CreateFrame("Frame", nil, page, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("LEFT", label, "RIGHT", 8, 0)
	slider:SetSize(200, 20)
	slider:Init(self.db.backgroundOpacity, 0, 100, 20, {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(value)
			return string.format("%d%%", value)
		end,
	})
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		value = math.floor(value + 0.5)
		if module.db.backgroundOpacity ~= value then
			module.db.backgroundOpacity = value
			module:Refresh()
		end
	end, slider)
	ns.MakeSliderEditable(slider)

	local note = CreateLabel(page, "Uses the window's colors and the font from the Fonts page, "
		.. "with a shadow instead of the black outline. Chat text size is still set in Blizzard's "
		.. "chat window settings.", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -20)
	note:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	note:SetJustifyV("TOP")
end

function Chat:OnPageShown(page)
	self.enableCheck:SetChecked(self.db.enabled)
end
