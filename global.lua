local L = AceLibrary("AceLocale-2.2"):new("Cursive")
Cursive = AceLibrary("AceAddon-2.0"):new("AceEvent-2.0", "AceDebug-2.0", "AceModuleCore-2.0", "AceConsole-2.0", "AceDB-2.0", "AceHook-2.1")
local function HasMinimumNampowerVersion(major, minor, patch)
  if GetNampowerVersion then
    local installedMajor, installedMinor, installedPatch = GetNampowerVersion()

    if installedMajor > major then
      return true
    elseif installedMajor == major and installedMinor > minor then
      return true
    elseif installedMajor == major and installedMinor == minor and installedPatch >= patch then
      return true
    end
  end

  return false
end

-- ClassicAPI too old (classicapi_check.lua prints what is missing): stay off.
-- Every file returns early when Cursive.nampower is false, so this disables the whole addon.
if CURSIVE_CLASSICAPI_MISSING then
  Cursive.nampower = false
  return
end

Cursive.nampower = HasMinimumNampowerVersion(2, 40, 0)

if not Cursive.nampower then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff6060Cursive:|r could not detect nampower >= v2.40.0")
  return
end

Cursive:RegisterEvent("ADDON_LOADED", function(name)
  if GetCVar("NP_EnableSpellStartEvents") ~= "1" then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff6060Cursive:|r Another addon disabled nampower spell start events.  Re-enabling as they are required.")
    SetCVar("NP_EnableSpellStartEvents", 1)
  end

  if GetCVar("NP_EnableSpellGoEvents") ~= "1" then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff6060Cursive:|r Another addon disabled nampower spell go events.  Re-enabling as they are required.")
    SetCVar("NP_EnableSpellGoEvents", 1)
  end

  if GetCVar("NP_EnableUnitEventsGuid") ~= "1" then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff6060Cursive:|r Another addon disabled nampower guid events.  Re-enabling as they are required.")
    SetCVar("NP_EnableUnitEventsGuid", 1)
  end
end)

function Cursive:OnEnable()
	if not Cursive.nampower then
		return
	end

	SetCVar("NP_EnableSpellStartEvents", 1)
	SetCVar("NP_EnableSpellGoEvents", 1)
	SetCVar("NP_EnableUnitEventsGuid", 1)

	DEFAULT_CHAT_FRAME:AddMessage(L["|cffffcc00Cursive:|cffffaaaa Loaded.  /cursive opens the options, /cursive help lists the commands."])

	Cursive.curses:LoadCurses()
	if Cursive.db.profile.enabled then
		Cursive.core.enable()
	end

	-- AddOn Options pages last, in a pcall: an error there must not stop Cursive working.
	-- The error is passed on unchanged so BugSack keeps its file:line.
	local ok, err = pcall(Cursive.BuildOptionsPanel, Cursive)
	if not ok then
		geterrorhandler()(err)
	end
end
