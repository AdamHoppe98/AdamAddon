local addonName, ns = ...

-- Example feature. Copy this file as the starting point for a new feature,
-- then add the new file to AdamAddon.toc under "# Features".

local Welcome = ns:RegisterModule("Welcome", {
	title = "Welcome",
	order = 0,
	defaults = {
		timesOpened = 0,
	},
	commands = {
		hello = {
			desc = "say hello (example command)",
			func = function(module, args)
				if args ~= "" then
					module:Print("Hello, " .. args .. "!")
				else
					module:Print("Hello!")
				end
			end,
		},
	},
})

function Welcome:CreatePage(page)
	local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)
	title:SetText("Welcome to " .. ns.title)

	local body = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	body:SetPoint("RIGHT", page, "RIGHT", -4, 0)
	body:SetJustifyH("LEFT")
	body:SetJustifyV("TOP")
	body:SetText("The template is ready. Each new feature gets its own entry in the menu on the left.\n\n"
		.. "Type |cffffd100/adam help|r to see all commands.")

	self.counterText = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.counterText:SetPoint("BOTTOMLEFT", 4, 4)
end

function Welcome:OnPageShown(page)
	self.db.timesOpened = self.db.timesOpened + 1
	self.counterText:SetText("You have opened this page " .. self.db.timesOpened .. " times.")
end
