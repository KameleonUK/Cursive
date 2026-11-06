if not Cursive.nampower then
	return
end

Cursive.core = CreateFrame("Frame", "Cursive", UIParent)

Cursive.core.guids = {}

Cursive.core.add = function(unit)
	local guid = UnitGUID(unit)

	if guid and not UnitIsDead(unit) then
		Cursive.core.guids[guid] = GetTime()
	end
end

Cursive.core.addGuid = function(guid)
	if UnitExists(guid) and not UnitIsDead(guid) then
		Cursive.core.guids[guid] = GetTime()
	end
end

Cursive.core.remove = function(guid)
	Cursive.core.guids[guid] = nil
end

Cursive.core.enable = function()
	-- unitstr
	Cursive.core:RegisterEvent("PLAYER_TARGET_CHANGED")
	-- arg1
  Cursive.core:RegisterEvent("UNIT_COMBAT_GUID") -- this can get called with player/target/raid1 etc
  Cursive.core:RegisterEvent("UNIT_MODEL_CHANGED_GUID")
end

Cursive.core.disable = function()
	Cursive.core:UnregisterAllEvents()
	Cursive.core.guids = {}
end

Cursive.core:SetScript("OnEvent", function()
	if event == "PLAYER_TARGET_CHANGED" then
		this.add("target")
	else
		-- arg1 is guid
		this.addGuid(arg1)
	end
end)
