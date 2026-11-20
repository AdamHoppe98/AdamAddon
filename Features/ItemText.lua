local addonName, ns = ...

-- Shortens the long "Equip:" stat lines on item tooltips:
--
--   Equip: Increases damage and healing done by magical spells and effects by up to 12.
--     -> +12 Spell Power / +12 Healing Power
--   Equip: Increases healing done by spells and effects by up to 22.
--     -> +22 Healing Power
--   Equip: Increases healing done by up to 48 and damage done by up to 16 for all magical spells and effects.
--     -> +16 Spell Power / +48 Healing Power
--   Equip: Increases damage done by magical spells and effects by up to 9.
--     -> +9 Spell Power
--   Equip: Increases damage done by Fire spells and effects by up to 12.
--     -> +12 Fire Spell Power (also Holy, Nature, Frost, Shadow, Arcane)
--   Equip: +14 Attack Power.                                           -> +14 Attack Power
--   Equip: +24 Ranged Attack Power.                                    -> +24 Ranged Attack Power
--   Equip: Increases your chance to dodge an attack by 1%.             -> +1% Dodge
--     (also parry, and "block attacks with a shield" -> +1% Block)
--   Equip: Restores 5 mana per 5 sec.                                -> +5 MP5
--   Equip: Restores 4 health per 5 sec.                                -> +4 HP5
--   Equip: Improves your chance to get a critical strike by 1%.        -> +1% Crit
--   Equip: Improves your chance to get a critical strike with spells by 1%.  -> +1% Spell Crit
--   Equip: Improves your chance to hit by 1%.                          -> +1% Hit
--   Equip: Improves your chance to hit with spells by 1%.              -> +1% Spell Hit
--
-- Works through TooltipDataProcessor, so bag, character, comparison and chat link tooltips
-- all change. A line is only replaced when the whole line matches one of the patterns;
-- anything else is left exactly as Blizzard wrote it. The text is the item spell's own
-- description, so the patterns are English only.

local ItemText = ns:RegisterModule("ItemText", {
	title = "Item Text",
	order = 29,
	defaults = {
		enabled = true,
		debug = false, -- print "Equip:" lines that look like stats but no pattern matched
	},
	commands = {
		itemdebug = {
			desc = "print item tooltip lines that were not shortened",
			func = function(module)
				module.db.debug = not module.db.debug
				module:Print("Item text debug " .. (module.db.debug and "on" or "off") .. ".")
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

local NUMBER = "(%d+%.?%d*)" -- 12, 0.5, 1.

-- Each rule gets the line body (prefix removed, lowercased, trailing period removed) and
-- returns the replacement lines, or nil when it doesn't match.
local RULES = {
	-- Spell power
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
		local amount = body:match("^increases damage done by magical spells and effects by up to (%d+)$")
			or body:match("^increases damage done by spells and effects by up to (%d+)$")
			or body:match("^increases spell damage by up to (%d+)$")
		if amount then
			return { "+" .. amount .. " Spell Power" }
		end
	end,
	function(body)
		local school, amount = body:match("^increases damage done by (%a+) spells and effects by up to (%d+)$")
		if school and SCHOOLS[school] then
			return { "+" .. amount .. " " .. SCHOOLS[school] .. " Spell Power" }
		end
	end,

	-- Attack power ("+14 Attack Power" or "Increases attack power by 14")
	function(body)
		local ranged = body:match("^%+%s*(%d+) ranged attack power$")
			or body:match("^increases ranged attack power by (%d+)$")
		if ranged then
			return { "+" .. ranged .. " Ranged Attack Power" }
		end
		local amount = body:match("^%+%s*(%d+) attack power$")
			or body:match("^increases attack power by (%d+)$")
		if amount then
			return { "+" .. amount .. " Attack Power" }
		end
	end,

	-- Avoidance ("Increases your chance to dodge an attack by 1%")
	function(body)
		local amount = body:match("^increases your chance to dodge an attack by " .. NUMBER .. "%%$")
		if amount then
			return { "+" .. amount .. "% Dodge" }
		end
		amount = body:match("^increases your chance to parry an attack by " .. NUMBER .. "%%$")
		if amount then
			return { "+" .. amount .. "% Parry" }
		end
		amount = body:match("^increases your chance to block attacks with a shield by " .. NUMBER .. "%%$")
		if amount then
			return { "+" .. amount .. "% Block" }
		end
	end,

	-- Regeneration
	function(body)
		local amount = body:match("^restores (%d+) mana per 5 sec$")
		if amount then
			return { "+" .. amount .. " MP5" }
		end
	end,
	function(body)
		local amount = body:match("^restores (%d+) health per 5 sec$")
		if amount then
			return { "+" .. amount .. " HP5" }
		end
	end,

	-- Crit and hit
	function(body)
		local amount = body:match("^improves your chance to get a critical strike with spells by " .. NUMBER .. "%%$")
		if amount then
			return { "+" .. amount .. "% Spell Crit" }
		end
	end,
	function(body)
		local amount = body:match("^improves your chance to get a critical strike by " .. NUMBER .. "%%$")
		if amount then
			return { "+" .. amount .. "% Crit" }
		end
	end,
	function(body)
		local amount = body:match("^improves your chance to hit with spells by " .. NUMBER .. "%%$")
		if amount then
			return { "+" .. amount .. "% Spell Hit" }
		end
	end,
	function(body)
		local amount = body:match("^improves your chance to hit by " .. NUMBER .. "%%$")
		if amount then
			return { "+" .. amount .. "% Hit" }
		end
	end,
}

-- Words that mark an unmatched "Equip:" line as one these rules probably should handle.
local DEBUG_WORDS = { "spell", "restores", "chance", "attack" }

local reported = {} -- debug lines already printed this session; tooltips rebuild often

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

local function ReportUnmatched(text, body)
	if not ItemText.db.debug or reported[text] then
		return
	end
	for _, word in ipairs(DEBUG_WORDS) do
		if body:find(word, 1, true) then
			reported[text] = true
			ItemText:Print("Not shortened: " .. text)
			return
		end
	end
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
	ReportUnmatched(text, body)
	return nil
end

-- Returning true tells Blizzard's tooltip code the line is handled, so its own text is
-- skipped and ours goes in its place, in the same position.
local function OnTooltipLine(tooltip, lineData)
	if not ItemText.db or not ItemText.db.enabled then
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

function ItemText:OnInit()
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

function ItemText:CreatePage(page)
	local module = self

	local title = CreateLabel(page, "Item Text", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)

	local help = CreateLabel(page, "Shortens the long \"Equip:\" stat lines on item tooltips. "
		.. "Hover an item again after changing a setting.", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	help:SetPoint("RIGHT", page, "RIGHT", -4, 0)

	local enableCheck = CreateCheck(page, "Shorten item stat lines", self.db.enabled, function(checked)
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
		.. "|cffffd100Damage only|r  ->  +9 Spell Power\n\n"
		.. "|cffffd100Healing|r  ->  +22 Healing Power\n\n"
		.. "|cffffd100Healing and damage|r  ->  +16 Spell Power, +48 Healing Power\n\n"
		.. "|cffffd100One school|r  ->  +12 Fire Spell Power (Holy, Fire, Nature, Frost, Shadow, Arcane)\n\n"
		.. "|cffffd100Attack power|r  ->  +14 Attack Power, +24 Ranged Attack Power\n\n"
		.. "|cffffd100Dodge / parry / block|r  ->  +1% Dodge, +1% Parry, +1% Block\n\n"
		.. "|cffffd100Mana / health regen|r  ->  +5 MP5, +4 HP5\n\n"
		.. "|cffffd100Crit / hit|r  ->  +1% Crit, +1% Hit, +1% Spell Crit, +1% Spell Hit\n\n"
		.. "Only English tooltips are recognised. Lines that don't match stay as they are; "
		.. "turn on the debug option and paste what it prints so the patterns can be fixed.")
end

function ItemText:OnPageShown(page)
	self.enableCheck:SetChecked(self.db.enabled)
	self.debugCheck:SetChecked(self.db.debug)
end
