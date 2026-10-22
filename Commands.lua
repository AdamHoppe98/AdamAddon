local addonName, ns = ...

-- /adam            toggle the window
-- /adam <command>  run a registered command (see /adam help)
-- /adam <feature>  open the window on that feature's page

local commands = {}

function ns:RegisterCommand(command, desc, func)
	command = command:lower()
	if commands[command] then
		ns:Print("command '" .. command .. "' is registered twice; the last one wins.")
	end
	commands[command] = { desc = desc or "", func = func }
end

local function PrintHelp()
	ns:Print("commands:")
	print("  /adam - open or close the window")

	local names = {}
	for command in pairs(commands) do
		table.insert(names, command)
	end
	table.sort(names)
	for _, command in ipairs(names) do
		print("  /adam " .. command .. " - " .. commands[command].desc)
	end
end

local function HandleSlash(msg)
	msg = strtrim(msg or "")
	if msg == "" then
		ns.MainWindow:Toggle()
		return
	end

	local command, args = msg:match("^(%S+)%s*(.-)$")
	command = command:lower()

	local entry = commands[command]
	if entry then
		entry.func(args)
		return
	end

	for _, module in ipairs(ns.modules) do
		if module.CreatePage and module.name:lower() == command then
			ns.MainWindow:ShowPage(module.name)
			return
		end
	end

	ns:Print("unknown command '" .. command .. "'.")
	PrintHelp()
end

ns:RegisterCommand("help", "list commands", PrintHelp)

ns:RegisterCommand("minimap", "show or hide the minimap icon", function()
	ns.MinimapButton:SetHidden(not ns.db.minimap.hide)
end)

ns:RegisterCommand("reset", "move the window back to the center of the screen", function()
	ns.MainWindow:ResetPosition()
end)

SLASH_ADAMADDON1 = "/adam"
SlashCmdList.ADAMADDON = HandleSlash
