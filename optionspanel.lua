if not Cursive.nampower then
	return
end

-- Cursive's pages in Game Menu > AddOn Options (ClassicAPI's InterfaceOptionsFrame), built with
-- ClassicAPIOptionsKit. The minimap / FuBar menu in settings.lua still works: both edit
-- Cursive.db.profile, so they always show the same values.

local L = AceLibrary("AceLocale-2.2"):new("Cursive")
local Kit = ClassicAPIOptionsKit

local function Profile()
	return Cursive.db.profile
end

local function Option(key)
	return function() return Cursive.db.profile[key] end
end

-- the frames are rebuilt from the profile; run once per frame however many settings changed
local function ApplyDisplay()
	if Cursive.UpdateFramesFromConfig then
		Cursive.UpdateFramesFromConfig()
	end
end

function Cursive:OpenOptionsPanel()
	if self.optionsRoot then
		Kit:Open(self.optionsRoot)
	end
end

-- Called last in Cursive:OnEnable, once the saved variables are loaded (AceDB replaces the profile table).
function Cursive:BuildOptionsPanel()
	if not Kit or self.optionsRoot then
		return
	end

	local bind = Kit.Binder(Profile, Cursive.defaults, Kit.Defer(ApplyDisplay))

	-- settings that need more than a write: starting/stopping the scanner, nested tables, the ignore list
	local enabledSetting = {
		get = function() return Cursive.db.profile.enabled end,
		set = function(v)
			Cursive.db.profile.enabled = v
			if v then Cursive.core.enable() else Cursive.core.disable() end
		end,
		reset = function()
			Cursive.db.profile.enabled = true
			Cursive.core.enable()
		end,
	}
	local faerieFireSetting = {
		get = function() return Cursive.db.profile.shareddebuffs.faeriefire end,
		set = function(v)
			Cursive.db.profile.shareddebuffs.faeriefire = v
			Cursive.curses:UpdateSharedDebuffEvents()
		end,
		reset = function()
			Cursive.db.profile.shareddebuffs.faeriefire = false
			Cursive.curses:UpdateSharedDebuffEvents()
		end,
	}
	local ignoreListSetting = {
		get = function() return Cursive:GetIgnoreListText() end,
		set = function(text) Cursive:SetIgnoreListText(text) end,
		reset = function() Cursive:SetIgnoreListText("") end,
	}

	-- root page: general switches
	local root = Kit:NewPage({name = "Cursive", title = "Cursive", bind = bind,
		subtitle = "Shows mobs in combat with your debuff timers. /cursive help lists the casting commands."})
	self.optionsRoot = root
	root:Checkbox({label = L["Enabled"], tooltip = L["Enable/Disable Cursive"], setting = enabledSetting})
	root:Checkbox({key = "showtitle", label = L["Show Title"], tooltip = L["Show the title of the frame"]})
	root:Checkbox({key = "clickthrough", label = L["Allow clickthrough"], tooltip = "Click through the frame; it can't be dragged"})
	root:Checkbox({key = "showbackdrop", label = L["Show Frame Background"], tooltip = "Helps with positioning the frame"})
	root:Button({label = L["Reset Frame"], tooltip = L["Move the frame back to the default position"], onClick = function()
		local profile = Cursive.db.profile
		profile.anchor = Cursive.defaults.anchor
		profile.x = Cursive.defaults.x
		profile.y = Cursive.defaults.y
		ApplyDisplay()
	end})
	root:Header("Mobs and debuffs")
	root:Slider({key = "maxrow", label = L["Max Rows"], min = 1, max = 20})
	root:Slider({key = "maxcol", label = L["Max Columns"], min = 1, max = 20})
	root:Slider({key = "maxcurses", label = L["Max Curses"], tooltip = "Debuff icons shown per mob", min = 1, max = 8})
	root:Checkbox({key = "malediction", label = "Malediction", tooltip = "Check Curse of Agony for CoR/CoE/CoS"})
	root:Text("Malediction: for warlocks with the talent. When a command checks whether Curse of Recklessness, "
		.. "the Elements or Shadow is on a target, it checks for Curse of Agony instead. A command's "
		.. "malediction=0 or malediction=1 option overrides this.")
	root:Spacer(6)
	root:Button({label = "Quick menu", tooltip = "The minimap icon's right-click menu", onClick = function()
		if CursiveOptions and CursiveOptions.OpenMenu then
			CursiveOptions:OpenMenu(this)
		end
	end})

	-- bars: layout, sections and sizes
	local bars = Kit:NewPage({name = "Bars", parent = "Cursive", title = L["Bar Display Settings"], bind = bind})
	bars:Header("Layout")
	bars:Checkbox({key = "invertbars", label = "Invert Bar Display", tooltip = "Sections in order 3-2-1"})
	bars:Checkbox({key = "expandupwards", label = "Expand Bars Upwards"})
	bars:Header("Sections")
	bars:Checkbox({key = "showtargetindicator", label = L["Show Targeting Arrow"]})
	bars:Checkbox({key = "showraidicons", label = L["Show Raid Icons"]})
	bars:Slider({key = "raidiconsize", label = L["Raid Icon Size"], min = 10, max = 30, enabledIf = Option("showraidicons")})
	bars:Checkbox({key = "showhealthbar", label = L["Show Health Bar"]})
	bars:EditBox({key = "bartexture", label = L["Health Bar Texture"], tooltip = "Full texture path", width = 320,
		enabledIf = Option("showhealthbar")})
	bars:Checkbox({key = "showunitname", label = L["Show Unit Name"]})
	bars:Checkbox({key = "alwaysshowcurrenttarget", label = "Always Show Current Target", tooltip = "Last row, if not already shown"})
	bars:Header("Size")
	bars:Slider({key = "healthwidth", label = L["Health Bar/Unit Name Width"], min = 30, max = 150, step = 5})
	bars:Slider({key = "height", label = L["Health Bar/Unit Name Height"], min = 10, max = 30, step = 2})
	bars:Slider({key = "curseiconsize", label = L["Curse Icon Size"], min = 10, max = 30})
	bars:Slider({key = "spacing", label = L["Spacing"], min = 0, max = 10})
	bars:Slider({key = "textsize", label = L["Name/Hp Text Size"], min = 8, max = 20})
	bars:Slider({key = "cursetimersize", label = L["Curse Timer Text Size"], min = 6, max = 20})
	bars:Slider({key = "scale", label = L["Scale"], min = 0.5, max = 2, step = 0.1})
	bars:Header("Debuff timers")
	bars:Dropdown({key = "curseordering", label = L["Curse Ordering"], width = 200, options = {
		{value = L["Order applied"], text = L["Order applied"]},
		{value = L["Expiring soonest -> latest"], text = L["Expiring soonest -> latest"]},
		{value = L["Expiring latest -> soonest"], text = L["Expiring latest -> soonest"]},
	}})
	bars:Checkbox({key = "curseshowdecimals", label = L["Decimal Duration"], tooltip = "Tenths of a second under 10 s"})

	-- mob filters
	local filters = Kit:NewPage({name = "Mob Filters", parent = "Cursive", title = L["Mob filters"], bind = bind,
		subtitle = L["Target and Raid Marks always shown"]})
	filters:Checkbox({key = "filterincombat", label = L["In Combat"]})
	filters:Checkbox({key = "filterhostile", label = L["Hostile"]})
	filters:Checkbox({key = "filterattackable", label = L["Attackable"]})
	filters:Checkbox({key = "filterplayer", label = L["Player"], tooltip = L["Player Desc"]})
	filters:Checkbox({key = "filternotplayer", label = L["Not Player"], tooltip = L["Not Player Desc"]})
	filters:Checkbox({key = "filterrange", label = L["Within 45 Range"]})
	filters:Checkbox({key = "filterraidmark", label = L["Has Raid Mark"]})
	filters:Checkbox({key = "filterhascurse", label = L["Has Curse"], tooltip = L["Only show units you have cursed"]})
	filters:Checkbox({key = "filteruntagged", label = "Untagged", tooltip = "Untagged or tagged by you"})
	filters:Checkbox({key = "filterignored", label = L["Not ignored"], tooltip = "Hide mobs on the ignore list"})
	filters:EditBox({label = L["Ignored Mobs List (Enter to save)"], tooltip = "Comma separated, e.g. whelp,scarab",
		width = 320, setting = ignoreListSetting, enabledIf = Option("filterignored")})
	filters:Text(L["Ignored Mobs Desc"])

	-- shared debuffs
	local shared = Kit:NewPage({name = "Shared Debuffs", parent = "Cursive", title = L["Shared Debuffs"], bind = bind})
	shared:Checkbox({label = L["Shared Faerie Fire"], tooltip = "Show other players' Faerie Fire",
		setting = faerieFireSetting})
	shared:Text(L["This will show other player's Faerie Fires and avoid trying to cast Faerie Fire on those mobs"])
end
