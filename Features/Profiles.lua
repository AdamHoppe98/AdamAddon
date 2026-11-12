local addonName, ns = ...

-- Profiles: named sets of settings. Each character uses one profile (stored per character),
-- and several characters can share the same one. Storage lives in Core.lua; this page picks,
-- creates and deletes profiles, and exports/imports the active profile as a text string.
--
-- Export packs the active profile's settings the same way Blizzard's Cooldown Manager does
-- its layouts: CBOR -> Deflate -> Base64, behind a short prefix. Import either replaces the
-- active profile or makes a new profile from the string. Both reload the UI, because every
-- feature holds on to its settings table.
--
-- Shared modules (def.shared = true, e.g. Welcome and this page) are not part of a profile.

local PREFIX = "ADAM1:"
local MAX_NAME_LENGTH = 32
local DELETE_CONFIRM_SECONDS = 4

local Profiles = ns:RegisterModule("Profiles", {
	title = "Profiles",
	order = 90,
	shared = true,
	defaults = {},
	commands = {
		export = {
			desc = "open the export page for the active profile",
			func = function(module)
				ns.MainWindow:ShowPage(module.name)
				module:FillExport()
			end,
		},
		profile = {
			desc = "list profiles, or switch with /adam profile <name>",
			func = function(module, args)
				module:HandleProfileCommand(args)
			end,
		},
	},
})

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Red(text)
	return "|cffff4040" .. text .. "|r"
end

local function Gold(text)
	return "|cffffd100" .. text .. "|r"
end

-- `name` if it is free, otherwise "name 2", "name 3", ...
local function UniqueProfileName(name)
	if not ns:ProfileExists(name) then
		return name
	end
	local i = 2
	while ns:ProfileExists(name .. " " .. i) do
		i = i + 1
	end
	return name .. " " .. i
end

-- Cleans up a typed or imported profile name. Returns nil if nothing usable is left.
local function CleanName(name)
	if type(name) ~= "string" then
		return nil
	end
	name = strtrim(name)
	if name == "" then
		return nil
	end
	return name:sub(1, MAX_NAME_LENGTH)
end

-- The profile a character falls back to when its profile is deleted.
local function FallbackProfile(deleted)
	if deleted ~= ns.DEFAULT_PROFILE and ns:ProfileExists(ns.DEFAULT_PROFILE) then
		return ns.DEFAULT_PROFILE
	end
	for _, name in ipairs(ns:GetProfileNames()) do
		if name ~= deleted then
			return name
		end
	end
end

---------------------------------------------------------------------------
-- Encoding
---------------------------------------------------------------------------

function Profiles:Export()
	local payload = {
		addon = addonName,
		version = ns.version,
		profile = ns.profileName,
		modules = ns:GetProfileModules(),
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

-- The payload's feature settings that belong in a profile, and how many there are.
-- Older strings (from before profiles) work the same way.
local function ProfileModulesFrom(payload)
	local modules, count = {}, 0
	for name, settings in pairs(payload.modules) do
		if type(name) == "string" and type(settings) == "table" then
			local module = ns:GetModule(name)
			if not (module and module.shared) then
				modules[name] = settings
				count = count + 1
			end
		end
	end
	return modules, count
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

function Profiles:SetProfileStatus(text)
	if self.profileStatus then
		self.profileStatus:SetText(text or "")
	end
end

-- Makes a new profile (empty = all defaults, or a copy of the active one) and switches to it.
function Profiles:CreateFromBox(copyCurrent)
	local name = CleanName(self.nameBox:GetText())
	if not name then
		self:SetProfileStatus(Red("Type a name for the new profile first."))
		return
	end
	if ns:ProfileExists(name) then
		self:SetProfileStatus(Red("There is already a profile called \"" .. name .. "\"."))
		return
	end
	local modules = copyCurrent and CopyTable(ns:GetProfileModules()) or nil
	ns:CreateProfile(name, modules)
	self:Print("created profile \"" .. name .. "\". Reloading the UI to switch to it.")
	ns:SwitchProfile(name)
end

-- First click arms the button, a second click within a few seconds deletes.
function Profiles:DeleteCurrent()
	local fallback = FallbackProfile(ns.profileName)
	if not fallback then
		self:SetProfileStatus(Red("This is the only profile, so it can't be deleted."))
		return
	end

	local button = self.deleteButton
	if not button.armed then
		button.armed = true
		button:SetText("Really delete?")
		self:SetProfileStatus("Click again to delete \"" .. ns.profileName .. "\". This character switches to \""
			.. fallback .. "\".")
		local token = {}
		button.armToken = token
		C_Timer.After(DELETE_CONFIRM_SECONDS, function()
			if button.armToken == token then
				self:DisarmDelete()
				self:SetProfileStatus("")
			end
		end)
		return
	end

	local deleted = ns.profileName
	ns:DeleteProfile(deleted)
	self:Print("deleted profile \"" .. deleted .. "\". Reloading the UI with \"" .. fallback .. "\".")
	ns:SwitchProfile(fallback)
end

function Profiles:DisarmDelete()
	local button = self.deleteButton
	if button then
		button.armed = false
		button.armToken = nil
		button:SetText("Delete")
	end
end

function Profiles:FillExport()
	if not self.exportBox then
		return
	end
	local text = self:Export()
	if not text then
		self.exportStatus:SetText(Red("Could not build the export string."))
		return
	end
	self.exportText = text
	self.exportBox:SetText(text)
	self.exportBox:SetFocus()
	self.exportBox:HighlightText()
	self.exportStatus:SetText("\"" .. ns.profileName .. "\" selected. Press " .. Gold("Ctrl+C") .. " to copy it.")
end

-- asNew: make a new profile from the string; otherwise replace the active profile.
function Profiles:Import(asNew)
	local payload, err = Decode(self.importBox:GetText())
	if not payload then
		self.importStatus:SetText(Red(err))
		return
	end
	local modules, count = ProfileModulesFrom(payload)
	if count == 0 then
		self.importStatus:SetText(Red("The string has no settings in it."))
		return
	end

	if asNew then
		-- A name typed in the profile box wins, then the name stored in the string.
		local name = CleanName(self.nameBox:GetText()) or CleanName(payload.profile) or "Imported"
		name = UniqueProfileName(name)
		ns:CreateProfile(name, modules)
		self:Print("imported " .. count .. " features as new profile \"" .. name .. "\". Reloading the UI.")
		ns:SwitchProfile(name)
	else
		ns.db.profiles[ns.profileName].modules = modules
		self:Print("imported " .. count .. " features into profile \"" .. ns.profileName .. "\". Reloading the UI.")
		ReloadUI()
	end
end

-- /adam profile [name]
function Profiles:HandleProfileCommand(args)
	args = strtrim(args or "")
	local names = ns:GetProfileNames()
	if args == "" then
		self:Print("active profile: " .. Gold(ns.profileName))
		print("  profiles: " .. table.concat(names, ", "))
		print("  switch with /adam profile <name>")
		return
	end

	for _, name in ipairs(names) do
		if name:lower() == args:lower() then
			if name == ns.profileName then
				self:Print("already using profile \"" .. name .. "\".")
			else
				ns:SwitchProfile(name)
			end
			return
		end
	end
	self:Print("no profile called \"" .. args .. "\". Profiles: " .. table.concat(names, ", "))
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

local function CreateButton(parent, text, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	return button
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

function Profiles:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Profiles", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)

	local intro = CreateLabel(page, "Each character uses one profile; characters can share one. "
		.. "Switching reloads the UI.", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	intro:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	-- Active profile
	local profileLabel = CreateLabel(page, "Profile")
	profileLabel:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -20)
	profileLabel:SetWidth(84)

	local dropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("LEFT", profileLabel, "RIGHT", 8, 0)
	dropdown:SetWidth(200)
	dropdown:SetupMenu(function(_, rootDescription)
		rootDescription:SetScrollMode(300)
		local function IsSelected(name)
			return name == ns.profileName
		end
		local function SetSelected(name)
			if name ~= ns.profileName then
				ns:SwitchProfile(name)
			end
		end
		for _, name in ipairs(ns:GetProfileNames()) do
			rootDescription:CreateRadio(name, IsSelected, SetSelected, name)
		end
	end)

	local deleteButton = CreateButton(page, "Delete", 110)
	deleteButton:SetPoint("LEFT", dropdown, "RIGHT", 10, 0)
	deleteButton:SetScript("OnClick", function()
		module:DeleteCurrent()
	end)
	self.deleteButton = deleteButton

	-- New profile
	local nameLabel = CreateLabel(page, "New profile")
	nameLabel:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -20)
	nameLabel:SetWidth(84)

	local nameBox = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
	nameBox:SetSize(150, 20)
	nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 14, 0)
	nameBox:SetAutoFocus(false)
	nameBox:SetMaxLetters(MAX_NAME_LENGTH)
	nameBox:SetScript("OnEnterPressed", function(box)
		box:ClearFocus()
	end)
	nameBox:SetScript("OnEscapePressed", function(box)
		box:ClearFocus()
	end)
	self.nameBox = nameBox

	local createButton = CreateButton(page, "Empty", 70)
	createButton:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
	createButton:SetScript("OnClick", function()
		module:CreateFromBox(false)
	end)
	createButton:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		GameTooltip:SetText("New profile with default settings")
		GameTooltip:Show()
	end)
	createButton:SetScript("OnLeave", GameTooltip_Hide)

	local copyButton = CreateButton(page, "Copy current", 100)
	copyButton:SetPoint("LEFT", createButton, "RIGHT", 4, 0)
	copyButton:SetScript("OnClick", function()
		module:CreateFromBox(true)
	end)
	copyButton:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		GameTooltip:SetText("New profile starting from \"" .. ns.profileName .. "\"")
		GameTooltip:Show()
	end)
	copyButton:SetScript("OnLeave", GameTooltip_Hide)

	local profileStatus = CreateLabel(page, "", "GameFontHighlightSmall")
	profileStatus:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -10)
	profileStatus:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	profileStatus:SetHeight(12)
	self.profileStatus = profileStatus

	-- Export
	local exportHeader = CreateLabel(page, "Export", "GameFontNormal")
	exportHeader:SetPoint("TOPLEFT", profileStatus, "BOTTOMLEFT", 0, -14)

	local exportButton = CreateButton(page, "Copy profile", 140)
	exportButton:SetPoint("TOPLEFT", exportHeader, "BOTTOMLEFT", 0, -8)
	exportButton:SetScript("OnClick", function()
		module:FillExport()
	end)

	self.exportStatus = CreateLabel(page, "", "GameFontHighlightSmall")
	self.exportStatus:SetPoint("LEFT", exportButton, "RIGHT", 10, 0)
	self.exportStatus:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local exportScroll, exportBox = CreateTextBox(page, 70)
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
	importHeader:SetPoint("TOPLEFT", exportScroll, "BOTTOMLEFT", -6, -20)

	local importHint = CreateLabel(page, "paste with " .. Gold("Ctrl+V"), "GameFontHighlightSmall")
	importHint:SetPoint("LEFT", importHeader, "RIGHT", 8, 0)

	local importScroll, importBox = CreateTextBox(page, 70)
	importScroll:SetPoint("TOPLEFT", importHeader, "BOTTOMLEFT", 6, -12)
	importScroll:SetPoint("RIGHT", page, "RIGHT", -10, 0)
	self.importBox = importBox
	importBox:SetScript("OnEscapePressed", function(box)
		box:ClearFocus()
	end)

	local importButton = CreateButton(page, "Replace current", 120)
	importButton:SetPoint("TOPLEFT", importScroll, "BOTTOMLEFT", -6, -12)
	importButton:SetScript("OnClick", function()
		module:Import(false)
	end)
	importButton:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		GameTooltip:SetText("Overwrite \"" .. ns.profileName .. "\" with the pasted settings")
		GameTooltip:Show()
	end)
	importButton:SetScript("OnLeave", GameTooltip_Hide)

	local importNewButton = CreateButton(page, "As new profile", 120)
	importNewButton:SetPoint("LEFT", importButton, "RIGHT", 4, 0)
	importNewButton:SetScript("OnClick", function()
		module:Import(true)
	end)
	importNewButton:SetScript("OnEnter", function(button)
		GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
		GameTooltip:SetText("Make a new profile from the pasted settings")
		GameTooltip:AddLine("Named after the New profile box if you typed a name there, "
			.. "otherwise after the profile in the string.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	importNewButton:SetScript("OnLeave", GameTooltip_Hide)

	local importStatus = CreateLabel(page, "", "GameFontHighlightSmall")
	importStatus:SetPoint("LEFT", importNewButton, "RIGHT", 10, 0)
	importStatus:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	self.importStatus = importStatus
end

function Profiles:OnPageShown(page)
	self:DisarmDelete()
	self:SetProfileStatus("Active profile: " .. Gold(ns.profileName) .. " ("
		.. #ns:GetProfileNames() .. " in total)")
	self.exportStatus:SetText("")
	self.importStatus:SetText("")
end
