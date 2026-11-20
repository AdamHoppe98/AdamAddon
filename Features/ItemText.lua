local addonName, ns = ...

-- Shortens the long spell power "Equip:" lines on item tooltips:
--
--   Equip: Increases damage and healing done by magical spells and effects by up to 12.
--     -> +12 Spell Power / +12 Healing Power
--   Equip: Increases healing done by spells and effects by up to 22.
--     -> +22 Healing Power
--   Equip: Increases healing done by up to 48 and damage done by up to 16 for all magical spells and effects.
--     -> +16 Spell Power / +48 Healing Power
--   Equip: Increases damage done by Fire spells and effects by up to 12.
--     -> +12 Fire Spell Power (also Holy, Nature, Frost, Shadow, Arcane)
--
-- Works through TooltipDataProcessor, so bag, character, comparison and chat link tooltips
-- all change. A line is only replaced when the whole line matches one of the patterns;
-- anything else is left exactly as Blizzard wrote it. The text is the item spell's own
-- description, so the patterns are English only.

local SpellPowerText = ns:RegisterModule("SpellPowerText", {
	title = "Spell Power Text",
	order = 29,
	defaults = {
		enabled = true,
		debug = false, -- print "Equip:" lines about spells that no pattern matched
	},
	commands = {
		spdebug = {
			desc = "print spell power tooltip lines that were not shortened",
			func = function(module)
				module.db.debug = not module.db.debug
				module:Print("Spell power text debug " .. (module.db.debug and "on" or "off") .. ".")
				if module.debugCheck then
					module.debugCheck:SetChecked(module.db.debug)
				end
			end,
		},
	},
})

local EQUIP_PREFIX = "^Equip: "

local SCHOOLS = {
	holy = "Holy",
	fire = "Fire",
	nature = "Nature",
	frost = "Frost",
	shadow = "Shadow",
	arcane = "Arcane",
}

-- Each rule gets the line body (prefix removed, lowercased, trailing period removed) and
-- returns the replacement lines, or nil when it doesn't match.
local RULES = {
	function(body)
		local amount = body:match("^increases damage and healing done by magical spells and effects by up to (%d+)$")
		if amount then
			return { "+" .. amount .. " Spell Power", "+" .. amount .. " Healing Power" }
		end
	end,
	function(body)
		local healing, damage = body:match("^increases healing done by up to (%d+) and damage done by up to (%d+) for all magical spells and effects$")
		if healing then
			return { "+" .. damage .. " Spell Power", "+" .. healing .. " Healing Power" }
		end
	end,
	function(body)
		local amount = body:match("^increases healing done by spells and effects by up to (%d+)$")
		if amount then
			return { "+" .. amount .. " Healing Power" }
		end
	end,
	function(body)
		local school, amount = body:match("^increases damage done by (%a+) spells and effects by up to (%d+)$")
		if school and SCHOOLS[school] then
			return { "+" .. amount .. " " .. SCHOOLS[school] .. " Spell Power" }
		end
	end,
}

local reported = {} -- debug lines already printed this session; tooltips rebuild often

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function GetReplacement(text)
	if not text:find(EQUIP_PREFIX) then
		return nil
	end
	local body = text:gsub(EQUIP_PREFIX, ""):gsub("%.%s*$", ""):lower()
	for _, rule in ipairs(RULES) do
		local lines = rule(body)
		if lines then
			return lines
		end
	end
	if SpellPowerText.db.debug and body:find("spell") and not reported[text] then
		reported[text] = true
		SpellPowerText:Print("Not shortened: " .. text)
	end
	return nil
end

-- Returning true tells Blizzard's tooltip code the line is handled, so its own text is
-- skipped and ours goes in its place, in the same position.
local function OnTooltipLine(tooltip, lineData)
	if not SpellPowerText.db or not SpellPowerText.db.enabled then
		return
	end
	local text = lineData.leftText
	if text == nil or IsSecret(text) or type(text) ~= "string" or lineData.rightText then
		return
	end
	local lines = GetReplacement(text)
	if not lines then
		return
	end
	local color = lineData.leftColor or GREEN_FONT_COLOR
	for _, line in ipairs(lines) do
		GameTooltip_AddColoredLine(tooltip, line, color, false, lineData.leftOffset)
	end
	return true
end

function SpellPowerText:OnInit()
	TooltipDataProcessor.AddLinePreCall(TooltipDataProcessor.AllTypes, OnTooltipLine)
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

function SpellPowerText:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Spell Power Text", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)

	local help = CreateLabel(page, "Shortens the long spell power lines on item tooltips. "
		.. "Hover an item again after changing a setting.", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	help:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local enableCheck = CreateCheck(page, "Shorten spell power lines", self.db.enabled, function(checked)
		module.db.enabled = checked
	end)
	enableCheck:SetPoint("TOPLEFT", help, "BOTTOMLEFT", -4, -6)
	self.enableCheck = enableCheck

	local debugCheck = CreateCheck(page, "Print lines that were not shortened", self.db.debug, function(checked)
		module.db.debug = checked
	end)
	debugCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, -2)
	self.debugCheck = debugCheck

	local examples = CreateLabel(page, "", "GameFontHighlightSmall")
	examples:SetPoint("TOPLEFT", debugCheck, "BOTTOMLEFT", 4, -12)
	examples:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	examples:SetJustifyV("TOP")
	examples:SetText("|cffffd100Damage and healing|r  ->  +12 Spell Power, +12 Healing Power\n\n"
		.. "|cffffd100Healing|r  ->  +22 Healing Power\n\n"
		.. "|cffffd100Healing and damage|r  ->  +16 Spell Power, +48 Healing Power\n\n"
		.. "|cffffd100One school|r  ->  +12 Fire Spell Power (Holy, Fire, Nature, Frost, Shadow, Arcane)\n\n"
		.. "Only English tooltips are recognised. Lines that don't match stay as they are; "
		.. "turn on the debug option and paste what it prints so the patterns can be fixed.")
end

function SpellPowerText:OnPageShown(page)
	self.enableCheck:SetChecked(self.db.enabled)
	self.debugCheck:SetChecked(self.db.debug)
end
