local addonName, ns = ...

-- Export and import settings as a text string. Export packs every feature's saved
-- settings (ns.db.modules) the same way Blizzard's Cooldown Manager does its layouts:
-- CBOR -> Deflate -> Base64, behind a short prefix. Import replaces the settings of each
-- feature found in the string (features missing from it keep their current settings)
-- and reloads the UI, so every feature starts again from the new values.

local PREFIX = "ADAM1:"

-- Settings that are not part of a profile.
local SKIPPED_MODULES = {
	Profiles = true,
	Welcome = true,
}

local Profiles = ns:RegisterModule("Profiles", {
	title = "Import / Export",
	order = 90,
	defaults = {},
	commands = {
		export = {
			desc = "open the settings export page",
			func = function(module)
				ns.MainWindow:ShowPage(module.name)
				module:FillExport()
			end,
		},
	},
})

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------

function Profiles:Export()
	local modules = {}
	for name, settings in pairs(ns.db.modules) do
		if not SKIPPED_MODULES[name] and type(settings) == "table" then
			modules[name] = settings
		end
	end

	local payload = {
		addon = addonName,
		version = ns.version,
		modules = modules,
	}

	local serialized = C_EncodingUtil.SerializeCBOR(payload)
	local compressed = serialized and C_EncodingUtil.CompressString(serialized, Enum.CompressionMethod.Deflate)
	local encoded = compressed and C_EncodingUtil.EncodeBase64(compressed)
	if not encoded then
		return nil
	end
	return PREFIX .. encoded
end

-- Returns the decoded payload, or nil and a message saying what is wrong with the text.
local function Decode(text)
	text = (text or ""):gsub("%s", "")
	if text == "" then
		return nil, "Paste an export string first."
	end
	if text:sub(1, #PREFIX) ~= PREFIX then
		return nil, "That is not an " .. addonName .. " export string."
	end

	local ok, payload = pcall(function()
		local decoded = C_EncodingUtil.DecodeBase64(text:sub(#PREFIX + 1))
		local inflated = decoded and C_EncodingUtil.DecompressString(decoded, Enum.CompressionMethod.Deflate)
		return inflated and C_EncodingUtil.DeserializeCBOR(inflated)
	end)
	if not ok or type(payload) ~= "table" or type(payload.modules) ~= "table" then
		return nil, "The string is damaged or incomplete. Copy it again, all of it."
	end
	return payload
end

-- Writes the payload's settings into the saved variables. Returns how many features changed.
local function Apply(payload)
	local count = 0
	for name, settings in pairs(payload.modules) do
		if type(name) == "string" and type(settings) == "table" and not SKIPPED_MODULES[name] then
			ns.db.modules[name] = settings
			count = count + 1
		end
	end
	return count
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

-- A multi-line text box with a scroll bar (Blizzard's InputScrollFrameTemplate).
local function CreateTextBox(parent, height)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "InputScrollFrameTemplate")
	scroll:SetHeight(height)
	scroll.CharCount:Hide()
	local editBox = scroll.EditBox
	editBox:SetFontObject("ChatFontSmall")
	editBox:SetMaxLetters(0)
	-- The template sizes the edit box once on load, before we have a width; keep it in step.
	scroll:SetScript("OnSizeChanged", function(self, width)
		editBox:SetWidth(width - 18)
		editBox.Instructions:SetWidth(width - 18)
	end)
	return scroll, editBox
end

function Profiles:FillExport()
	if not self.exportBox then
		return
	end
	local text = self:Export()
	if not text then
		self.exportStatus:SetText("|cffff4040Could not build the export string.|r")
		return
	end
	self.exportText = text
	self.exportBox:SetText(text)
	self.exportBox:SetFocus()
	self.exportBox:HighlightText()
	self.exportStatus:SetText("Selected. Press |cffffd100Ctrl+C|r to copy it.")
end

function Profiles:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Import / Export", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)

	local intro = CreateLabel(page, "Share your settings between characters or computers. "
		.. "The string holds the settings of every feature (positions, sizes, fonts and so on).")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	intro:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	-- Export
	local exportHeader = CreateLabel(page, "Export", "GameFontNormal")
	exportHeader:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -18)

	local exportButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	exportButton:SetSize(140, 22)
	exportButton:SetPoint("TOPLEFT", exportHeader, "BOTTOMLEFT", 0, -8)
	exportButton:SetText("Copy settings")
	exportButton:SetScript("OnClick", function()
		module:FillExport()
	end)

	self.exportStatus = CreateLabel(page, "", "GameFontHighlightSmall")
	self.exportStatus:SetPoint("LEFT", exportButton, "RIGHT", 10, 0)

	local exportScroll, exportBox = CreateTextBox(page, 110)
	exportScroll:SetPoint("TOPLEFT", exportButton, "BOTTOMLEFT", 6, -12)
	exportScroll:SetPoint("RIGHT", page, "RIGHT", -10, 0)
	self.exportBox = exportBox
	-- Read-only: typing puts the export string back. Clicking selects all of it again.
	exportBox:HookScript("OnTextChanged", function(box, userInput)
		if userInput then
			box:SetText(module.exportText or "")
			box:HighlightText()
		end
	end)
	exportBox:HookScript("OnEditFocusGained", function(box)
		box:HighlightText()
	end)
	exportBox:SetScript("OnEscapePressed", function(box)
		box:ClearFocus()
	end)

	-- Import
	local importHeader = CreateLabel(page, "Import", "GameFontNormal")
	importHeader:SetPoint("TOPLEFT", exportScroll, "BOTTOMLEFT", -6, -22)

	local importHint = CreateLabel(page, "Paste a string with |cffffd100Ctrl+V|r, then press Import. "
		.. "The UI reloads to apply it.", "GameFontHighlightSmall")
	importHint:SetPoint("TOPLEFT", importHeader, "BOTTOMLEFT", 0, -6)
	importHint:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local importScroll, importBox = CreateTextBox(page, 110)
	importScroll:SetPoint("TOPLEFT", importHint, "BOTTOMLEFT", 6, -12)
	importScroll:SetPoint("RIGHT", page, "RIGHT", -10, 0)
	self.importBox = importBox
	importBox:SetScript("OnEscapePressed", function(box)
		box:ClearFocus()
	end)

	local importButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	importButton:SetSize(140, 22)
	importButton:SetPoint("TOPLEFT", importScroll, "BOTTOMLEFT", -6, -12)
	importButton:SetText("Import")

	local importStatus = CreateLabel(page, "", "GameFontHighlightSmall")
	importStatus:SetPoint("LEFT", importButton, "RIGHT", 10, 0)
	importStatus:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	self.importStatus = importStatus

	importButton:SetScript("OnClick", function()
		local payload, err = Decode(importBox:GetText())
		if not payload then
			importStatus:SetText("|cffff4040" .. err .. "|r")
			return
		end
		local count = Apply(payload)
		if count == 0 then
			importStatus:SetText("|cffff4040The string has no settings in it.|r")
			return
		end
		module:Print("imported settings for " .. count .. " features. Reloading the UI.")
		ReloadUI()
	end)
end

function Profiles:OnPageShown(page)
	self.exportStatus:SetText("")
	self.importStatus:SetText("")
end
