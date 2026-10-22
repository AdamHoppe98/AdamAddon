local addonName, ns = ...

ns.name = addonName
ns.title = C_AddOns.GetAddOnMetadata(addonName, "Title") or addonName
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"
ns.icon = "Interface\\Icons\\INV_Scroll_04"

-- Defaults for AdamAddonDB. Missing keys are filled in on load, existing values are kept.
ns.defaults = {
	minimap = {
		hide = false,
		angle = 225,
	},
	window = {
		point = nil, -- { point, relativePoint, x, y }; nil = centered
		page = nil,  -- name of the last opened feature page
	},
	modules = {},
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local CHAT_PREFIX = "|cff33ff99" .. addonName .. "|r:"

function ns:Print(...)
	print(CHAT_PREFIX, ...)
end

local function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			ApplyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
	return target
end
ns.ApplyDefaults = ApplyDefaults

---------------------------------------------------------------------------
-- Events: any file can listen with ns:RegisterEvent(event, func)
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function ns:RegisterEvent(event, func)
	local handlers = eventHandlers[event]
	if not handlers then
		handlers = {}
		eventHandlers[event] = handlers
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers, func)
end

function ns:UnregisterEvent(event, func)
	local handlers = eventHandlers[event]
	if not handlers then
		return
	end
	for i = #handlers, 1, -1 do
		if handlers[i] == func then
			table.remove(handlers, i)
		end
	end
	if #handlers == 0 then
		eventHandlers[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local handlers = eventHandlers[event]
	if not handlers then
		return
	end
	-- Copy so a handler can unregister itself while we loop.
	local snapshot = { unpack(handlers) }
	for _, func in ipairs(snapshot) do
		func(event, ...)
	end
end)

---------------------------------------------------------------------------
-- Modules (features)
--
-- ns:RegisterModule(name, def) where def may contain:
--   title         label in the window's menu (defaults to name)
--   order         sort order in the menu (lower first, default 100)
--   defaults      table of saved settings; available as module.db
--   commands      { sub = { desc = "...", func = function(module, args) end } }
--   OnInit()      called once saved variables are loaded
--   OnLogin()     called on PLAYER_LOGIN (player data is available)
--   CreatePage(page)    builds the feature's page; called the first time it is shown
--   OnPageShown(page)   called every time the page is shown
--
-- Every module also gets :Print(...) and :RegisterEvent(event, methodOrFunc).
---------------------------------------------------------------------------

ns.modules = {}
ns.modulesByName = {}

local ModuleMethods = {}

function ModuleMethods:Print(...)
	ns:Print(...)
end

function ModuleMethods:RegisterEvent(event, handler)
	handler = handler or event
	local module = self
	ns:RegisterEvent(event, function(...)
		if type(handler) == "string" then
			module[handler](module, ...)
		else
			handler(module, ...)
		end
	end)
end

function ns:RegisterModule(name, def)
	if ns.modulesByName[name] then
		error(addonName .. ": module '" .. name .. "' is registered twice", 2)
	end

	local module = def or {}
	module.name = name
	module.title = module.title or name
	module.order = module.order or 100
	for key, func in pairs(ModuleMethods) do
		if module[key] == nil then
			module[key] = func
		end
	end

	table.insert(ns.modules, module)
	ns.modulesByName[name] = module

	if module.commands then
		for command, info in pairs(module.commands) do
			ns:RegisterCommand(command, info.desc, function(args)
				info.func(module, args)
			end)
		end
	end

	return module
end

function ns:GetModule(name)
	return ns.modulesByName[name]
end

function ns:GetSortedModules()
	local sorted = { unpack(ns.modules) }
	table.sort(sorted, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.title < b.title
	end)
	return sorted
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

local function OnAddonLoaded(event, loadedName)
	if loadedName ~= addonName then
		return
	end
	ns:UnregisterEvent("ADDON_LOADED", OnAddonLoaded)

	AdamAddonDB = ApplyDefaults(AdamAddonDB or {}, ns.defaults)
	ns.db = AdamAddonDB

	for _, module in ipairs(ns.modules) do
		ns.db.modules[module.name] = ApplyDefaults(ns.db.modules[module.name] or {}, module.defaults or {})
		module.db = ns.db.modules[module.name]
		if module.OnInit then
			module:OnInit()
		end
	end

	ns.MainWindow:Init()
	ns.MinimapButton:Init()
end

local function OnPlayerLogin()
	for _, module in ipairs(ns.modules) do
		if module.OnLogin then
			module:OnLogin()
		end
	end
end

ns:RegisterEvent("ADDON_LOADED", OnAddonLoaded)
ns:RegisterEvent("PLAYER_LOGIN", OnPlayerLogin)
