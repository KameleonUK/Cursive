if not Cursive.nampower then
	return
end
local L = AceLibrary("AceLocale-2.2"):new("Cursive")

local _, playerClassName = UnitClass("player")

local curses = {
	trackedCurseIds = {},
	-- debuff name -> icon. Not used by Cursive itself any more, but other addons rely on it:
	-- SuperCleveRoidMacros writes its custom spells into it, Kui_Nameplates_Auras reads icons from it
	trackedCurseNamesToTextures = {},
	darkHarvestSpellIds = {
		[52550] = true,
		[52551] = true,
		[52552] = true,
	},
  travelTimeSpellIds = {},
	darkHarvestData = {},
	guids = {},
	isChanneling = false,
	pendingCast = {},
	resistSoundGuids = {},
	expiringSoundGuids = {},
	requestedExpiringSoundGuids = {}, -- guid added on spellcast, moved to expiringSoundGuids once rendered by ui
	previousComboPoints = 0,
	comboPoints = 0,

	sharedDebuffs = {
		faeriefire = {},
	},

	-- Whitelist of mobs that can bleed (for rake tracking at client debuff cap)
	mobsThatBleed = {
		["0xF13000F1F3276A33"] = true, -- Keeper Gnarlmoon
		["0xF13000F1FA276A32"] = true, -- Ley-Watcher Incantagos
		["0xF13000EA3F276C05"] = true, -- King
		["0xF13000EA31279058"] = true, -- Queen
		["0xF13000EA43276C06"] = true, -- Bishop
		["0xF13000EA44279044"] = true, -- Pawn
		["0xF13000EA42276C07"] = true, -- Rook
		["0xF13000EA4D05DA44"] = true, -- Sanv Tas'dal
		["0xF13000EA57276C04"] = true, -- Kruul
		["0xF130016C95276DAF"] = true, -- Mephistroth

		["0xF130003E5401591A"] = true, --Anub'Rekhan
		["0xF130003E510159B0"] = true, --Grand Widow Faerlina
		["0xF130003E500159A3"] = true, --Maexxna
		["0xF130003EBD01598C"] = true, --Razuvious
		["0xF130003EBC01599F"] = true, --Gothik
		["0xF130003EBF015AB2"] = true, --Zeliek
		["0xF130003EBE015AB3"] = true, --Mograine
		["0xF130003EC1015AB1"] = true, --Blaumeux
		["0xF130003EC0015AB0"] = true, --Thane
		["0xF130003E52015824"] = true, --Noth
		["0xF130003E4001588D"] = true, --Heigan
		["0xF130003E8B0158A2"] = true, --Loatheb
		["0xF130003E9C0158EA"] = true, --Patchwerk
		["0xF130003E3B0158EF"] = true, --Grobbulus
		["0xF130003E3C0158F0"] = true, --Gluth
		["0xF130003E380159A0"] = true, --Thaddius
		["0xF130003E75015AB4"] = true, --Sapphiron
		["0xF130003E76015AED"] = true, --Kel'Thuzad
	},
  bleedImmuneMobs = { -- populated with mob names that fail VerifyMeleeBleedApplied to allow skipping future bleed checks
  }
}

-- returns the curse record for guid/name only while it exists and hasn't run out
-- (HasCurse can also answer true for a pending cast, which has no record to modify)
local function GetActiveCurse(guid, curseName)
	local curseData = curses.guids[guid] and curses.guids[guid][curseName]
	if curseData and curses:TimeLeft(curseData) >= 0 then
		return curseData
	end
	return nil
end

-- Other players' Faerie Fire comes from the combat log (see the COMBAT_LOG_EVENT_UNFILTERED
-- handler), which checks the setting on every event, so the toggle works without a reload.
-- Turning it off only has to clear the ones already shown.
function curses:UpdateSharedDebuffEvents()
	if Cursive.db.profile.shareddebuffs.faeriefire then
		return
	end
	local faerieFire = L["faerie fire"]
	for guid, guidCurses in pairs(curses.guids) do
		if guidCurses[faerieFire] and guidCurses[faerieFire].currentPlayer == false then
			guidCurses[faerieFire] = nil
		end
	end
end

-- I think depending on ping the combo point used event can fire either before or after your ability cast
function curses:GetComboPointsUsed()
	if curses.comboPoints == 0 then
		return curses.previousComboPoints
	else
		return curses.comboPoints
	end
end


function curses:LoadCurses()
	-- reset dicts
	curses.trackedCurseIds = {}
	curses.trackedCurseNamesToTextures = {}

	curses.isWarlock = playerClassName == "WARLOCK"
	curses.isPriest = playerClassName == "PRIEST"
	curses.isMage = playerClassName == "MAGE"
	curses.isDruid = playerClassName == "DRUID"
	curses.isHunter = playerClassName == "HUNTER"
	curses.isRogue = playerClassName == "ROGUE"
	curses.isShaman = playerClassName == "SHAMAN"
	curses.isWarrior = playerClassName == "WARRIOR"

	-- curses to track
	local spells = Cursive.spells
	if curses.isWarlock then
		curses.trackedCurseIds = spells.getWarlockSpells()
	elseif curses.isPriest then
		curses.trackedCurseIds = spells.getPriestSpells()
	elseif curses.isMage then
		curses.trackedCurseIds = spells.getMageSpells()
	elseif curses.isDruid then
		curses.trackedCurseIds = spells.getDruidSpells()
	elseif curses.isHunter then
		curses.trackedCurseIds = spells.getHunterSpells()
	elseif curses.isRogue then
		curses.trackedCurseIds = spells.getRogueSpells()
	elseif curses.isShaman then
		curses.trackedCurseIds = spells.getShamanSpells()
	elseif curses.isWarrior then
		curses.trackedCurseIds = spells.getWarriorSpells()
	end

  -- build travelTimeSpellIds from spell data
  -- travelTime spells must have a damage component otherwise it won't work
  curses.travelTimeSpellIds = {}
  for id, data in pairs(curses.trackedCurseIds) do
    if data.travelTime then
      curses.travelTimeSpellIds[id] = true
    end
  end

  -- register travel time spell tracking
  if next(curses.travelTimeSpellIds) and not Cursive:IsEventRegistered("SPELL_DAMAGE_EVENT_SELF") then
    Cursive:RegisterEvent("SPELL_DAMAGE_EVENT_SELF", function(targetGuid, casterGuid, spellID, amount, mitigationStr, hitInfo, spellSchool, effectAuraStr)
      if curses.travelTimeSpellIds[spellID] and curses.trackedCurseIds[spellID] then
        local duration = curses:GetCurseDuration(spellID)
        curses:ApplyCurse(spellID, targetGuid, GetTime(), duration)
      end
    end)
  end

	-- load shared debuffs
	curses.sharedDebuffs = spells.getSharedDebuffs()

	-- faerie fire tracking from other players
	curses:UpdateSharedDebuffEvents()

	for id, data in pairs(curses.trackedCurseIds) do
		data.texture = C_Spell.GetSpellTexture(id)
		curses.trackedCurseNamesToTextures[data.name] = data.texture
	end

	-- combo points feed the fallback durations of Rip, Rupture and Kidney Shot
	if curses.isDruid or curses.isRogue then
		Cursive:RegisterEvent("PLAYER_COMBO_POINTS", function()
			curses.previousComboPoints = curses.comboPoints
			curses.comboPoints = GetComboPoints()
		end)
	end
end

-- First guess at a duration, used until the real one is read from the mob's aura
-- (see SyncFromAura): the spell table's value, or its calculateDuration function.
function curses:GetCurseDuration(curseSpellID)
	if curses.trackedCurseIds[curseSpellID].calculateDuration then
		return curses.trackedCurseIds[curseSpellID].calculateDuration()
	end

	return curses.trackedCurseIds[curseSpellID].duration
end

---------------------------------------------------------------------------------------------
-- Real timers from ClassicAPI.
-- C_UnitAuras reports duration and expirationTime for the player's debuffs on any unit. It
-- takes them from the server's cast packet (talents included), snapshots combo points, knows
-- Turtle's Rip, and mirrors Conflagrate (-3s Immolate), Molten Blast (refreshes Flame Shock)
-- and Carnage (Ferocious Bite refreshing Rip/Rake). This replaces Cursive's spellbook tooltip
-- scan and its own adjustments for those three. Dark Harvest is not modelled by ClassicAPI,
-- so TimeLeft still subtracts it.
-- Each record is read for AURA_SYNC_WINDOW seconds after the player's last cast at that mob,
-- at most every AURA_SYNC_INTERVAL. If nothing comes back the first guess stays.
---------------------------------------------------------------------------------------------
local AURA_SYNC_WINDOW = 2
local AURA_SYNC_INTERVAL = 0.1

-- spells whose real duration can differ from the table: talents, combo points, or a later
-- change by another spell. syncAura in the spell table (true/false or a function) overrides.
local function ShouldSyncAura(spellID)
	local data = curses.trackedCurseIds[spellID]
	if not data then
		return false
	end
	if type(data.syncAura) == "function" then
		return data.syncAura()
	elseif data.syncAura ~= nil then
		return data.syncAura
	end
	return (data.variableDuration or data.calculateDuration) and true or false
end

-- read every own synced record on guid again for a while (after a cast that may change them)
local function RequestAuraSync(guid)
	local guidCurses = curses.guids[guid]
	if not guidCurses then
		return
	end
	local syncUntil = GetTime() + AURA_SYNC_WINDOW
	for _, curseData in pairs(guidCurses) do
		if curseData.currentPlayer and ShouldSyncAura(curseData.spellID) then
			curseData.syncUntil = syncUntil
		end
	end
end

local function SyncFromAura(curseData)
	local now = GetTime()
	if not curseData.syncUntil or now > curseData.syncUntil then
		return
	end
	if curseData.lastSync and now - curseData.lastSync < AURA_SYNC_INTERVAL then
		return
	end
	curseData.lastSync = now

	local guid = curseData.targetGuid
	if not guid or not UnitExists(guid) then
		return
	end

	local aura = C_UnitAuras.GetUnitAuraBySpellID(guid, curseData.appliedSpellID or curseData.spellID, "HARMFUL|PLAYER")
	if aura and aura.expirationTime and aura.expirationTime > 0 and aura.duration and aura.duration > 0 then
		curseData.duration = aura.duration
		curseData.start = aura.expirationTime - aura.duration
	end
end

-- does the mob carry this aura (anyone's)? nil when it doesn't, or isn't loaded
function curses:ScanGuidForCurse(guid, curseSpellID)
	if not guid or not UnitExists(guid) then
		return nil
	end
	if C_UnitAuras.GetUnitAuraBySpellID(guid, curseSpellID) then
		return true
	end
	return nil
end

Cursive:RegisterEvent("LEARNED_SPELL_IN_TAB", function()
	-- reload curses in case spell slots changed
	curses:LoadCurses()
end)

local function StopChanneling()
	curses.isChanneling = false
end

local function GetAppliedCurseSpellID(spellID)
	local curseData = curses.trackedCurseIds[spellID]
	if curseData and curseData.debuffSpellId then
		return curseData.debuffSpellId
	end

	return spellID
end

local MAX_AURA_SLOTS = 48 -- 32 buff + 16 debuff slots (Turtle spills extra debuffs into free buff slots)

local function VerifyMeleeBleedApplied(targetGuid, spellID)
	local curseData = curses.trackedCurseIds[spellID]
	if not curseData or not curseData.meleeBleed then
		return
	end

	if not curses.guids[targetGuid] or not curses.guids[targetGuid][curseData.name] then
		return
	end

  if not UnitExists(targetGuid) then
    return
  end

	local appliedSpellID = GetAppliedCurseSpellID(spellID)
	local auras = C_UnitAuras.GetUnitAuras(targetGuid)
	for _, aura in ipairs(auras) do
		if aura.spellId == appliedSpellID then
			return
		end
	end

	-- with every aura slot taken the bleed may simply not have fit, so only then
	-- don't conclude the mob is bleed-immune
	local hasFullBuffsAndDebuffs = table.getn(auras) >= MAX_AURA_SLOTS

  if not hasFullBuffsAndDebuffs then
    local mobName = UnitName(targetGuid)
    if mobName then
      curses.bleedImmuneMobs[mobName] = true
    end
  end

	curses:RemoveCurse(targetGuid, curseData.name)
end

Cursive:RegisterEvent("SPELLCAST_CHANNEL_START", function()
	curses.isChanneling = true
end);

Cursive:RegisterEvent("SPELLCAST_CHANNEL_STOP", StopChanneling);
Cursive:RegisterEvent("SPELLCAST_INTERRUPTED", StopChanneling);

-- player spell completions
Cursive:RegisterEvent("SPELL_GO_SELF", function(itemId, spellID, casterGuid, targetGuid, castFlags, numTargetsHit, numTargetsMissed)
  if curses.travelTimeSpellIds[spellID] and numTargetsMissed == 0 then
			curses.pendingCast = {
				spellID = spellID,
				targetGuid = targetGuid,
			}
  end

  if numTargetsHit > 0 then
    -- any cast that lands can change our debuffs on that mob (Conflagrate, Molten Blast,
    -- Ferocious Bite...); ClassicAPI applies those changes, so read the timers again
    RequestAuraSync(targetGuid)
  end

  if numTargetsHit > 0 and numTargetsMissed == 0 and curses.trackedCurseIds[spellID] then
    -- the spell landed, so a resist sound requested for this cast no longer applies
    curses.resistSoundGuids[targetGuid] = nil
  end

  if numTargetsHit > 0 then
    if curses.trackedCurseIds[spellID] and not curses.travelTimeSpellIds[spellID] then
      local curseData = curses.trackedCurseIds[spellID]
      if curseData.meleeBleed then
        if numTargetsMissed > 0 then
          -- I think this will always mean the bleed missed and we can skip the extra bleed immunity logic
          return
        end
        local mobName = UnitName(targetGuid)
        local isBleedImmuneMob = mobName and mobName ~= "" and curses.bleedImmuneMobs[mobName]
        if not isBleedImmuneMob then
          local duration = curses:GetCurseDuration(spellID)
          curses:ApplyCurse(spellID, targetGuid, GetTime(), duration)
          if not curses.mobsThatBleed[targetGuid] then
            Cursive:ScheduleEvent(VerifyMeleeBleedApplied, 1, targetGuid, spellID)
          end
        end
      else
        local duration = curses:GetCurseDuration(spellID)
        curses:ApplyCurse(spellID, targetGuid, GetTime(), duration)
      end
		end
  end
end)

-- player spell start (cast time spells)
Cursive:RegisterEvent("SPELL_START_SELF", function(itemId, spellID, casterGuid, targetGuid, castFlags, castTime)
  if curses.trackedCurseIds[spellID] then
    curses.pendingCast = {
      spellID = spellID,
      targetGuid = targetGuid,
    }
  end
end)

-- player spell failure
Cursive:RegisterEvent("SPELL_FAILED_SELF", function(spellID, spellResult, failedByServer)
  if curses.trackedCurseIds[spellID] then
    curses.pendingCast = {}
  end
end)

-- player channel start (dark harvest)
Cursive:RegisterEvent("SPELL_CHANNEL_START", function(spellID, targetGuid, durationMs)
  if curses.darkHarvestSpellIds[spellID] then
    curses.darkHarvestData = {
      spellID = spellID,
      targetGuid = targetGuid,
      castDuration = durationMs / 1000,
      start = GetTime()
    }
	end
end)

Cursive:RegisterEvent("SPELL_MISS_SELF", function(casterGuid, targetGuid, spellID, missInfo)
  curses.pendingCast = {}

  -- use the mob that resisted, not the last mob a curse landed on
  if curses.trackedCurseIds[spellID] and targetGuid then
    if curses:ShouldPlayResistSound(targetGuid) then
      PlaySoundFile("Interface\\AddOns\\Cursive\\Sounds\\resist.mp3")
    end
  end
end)

-- After an aura on a tracked mob goes away, drop the matching record once the mob really
-- no longer has that spell. Checked a moment later because another player's copy of the same
-- spell can be the one that went (the mob still has ours), and so the aura list is up to date.
local function VerifyAuraRemoved(guid, spellID)
	local guidCurses = curses.guids[guid]
	if not guidCurses then
		return
	end
	for curseName, curseData in pairs(guidCurses) do
		if (curseData.appliedSpellID or curseData.spellID) == spellID and
				not curses:ScanGuidForCurse(guid, spellID) then
			curses:RemoveCurse(guid, curseName)
		end
	end
end

-- Forget a dead mob straight away instead of waiting for the display's cleanup pass.
local function ForgetGuid(guid)
	Cursive.core.remove(guid)
	curses:RemoveGuid(guid)
end

-- Another player's Faerie Fire landed on (or was refreshed on) a tracked mob. The combat log only
-- reports an aura that actually landed, so a resisted refresh no longer restarts the timer the way
-- the old cast-based tracking (nampower SPELL_GO_OTHER) did.
local function OnOtherPlayersAura(sourceGUID, destGUID, spellID)
	if not Cursive.db.profile.shareddebuffs.faeriefire then
		return
	end
	if not (curses.sharedDebuffs.faeriefire and curses.sharedDebuffs.faeriefire[spellID]) then
		return
	end
	if not destGUID or not Cursive.core.guids[destGUID] then
		return
	end
	if sourceGUID and sourceGUID == UnitGUID("player") then
		return -- our own cast is tracked through SPELL_GO_SELF
	end
	curses:ApplySharedCurse("faeriefire", spellID, destGUID)
end

-- The combat log names the mob by GUID and the aura by spell id, so this replaces parsing the
-- localized "X fades from Y" chat text and re-scanning every mob with a debuff of that name.
Cursive:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
	local _, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellID = CombatLogGetCurrentEventInfo()

	if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
		OnOtherPlayersAura(sourceGUID, destGUID, spellID)
	elseif subevent == "SPELL_AURA_REMOVED" then
		local guidCurses = destGUID and curses.guids[destGUID]
		if guidCurses then
			for _, curseData in pairs(guidCurses) do
				if (curseData.appliedSpellID or curseData.spellID) == spellID then
					Cursive:ScheduleEvent(VerifyAuraRemoved, 0.2, destGUID, spellID)
					return
				end
			end
		end
	elseif subevent == "UNIT_DIED" then
		if destGUID and (Cursive.core.guids[destGUID] or curses.guids[destGUID]) then
			ForgetGuid(destGUID)
		end
	end
end)

function curses:GetLastTickTime(curseData)
	local ticks = curses.trackedCurseIds[curseData.spellID].numTicks
	if not ticks then
		return GetTime()
	end

	local tickTime = curseData.duration / ticks
	local currentTime = GetTime()

	return math.floor((currentTime - curseData.start) / tickTime) * tickTime + curseData.start
end

function curses:TrackDarkHarvest(curseData)
	if curses.darkHarvestData["targetGuid"] and curses.darkHarvestData["targetGuid"] == curseData["targetGuid"] then
		local dhActive = false
		-- check if still channeling
		if curses.isChanneling then
			local dhTimeRemaining = curses.darkHarvestData.castDuration - (GetTime() - curses.darkHarvestData.start)
			-- check if dh still active based on cast duration
			if dhTimeRemaining > 0 then
				dhActive = true
				-- dh is active
				if not curseData["dhStartTime"] then
					curseData["dhStartTime"] = curses:GetLastTickTime(curseData) -- dh will reduce full tick duration
				end
			end
		end
		if curseData["dhStartTime"] and dhActive == false and not curseData["dhEndTime"] then
			-- if dh no longer active, store end time if not already stored
			curseData["dhEndTime"] = GetTime()
		end
	end
end

function curses:GetDarkHarvestReduction(curseData)
	if curseData["dhStartTime"] then
		local endTime = curseData["dhEndTime"] or GetTime()
		local dhActiveTime = endTime - curseData["dhStartTime"]
		if dhActiveTime > 0 then
			return dhActiveTime * .3 -- 30% reduction
		end
	end
	return 0
end

-- exact seconds left (Dark Harvest included); use this for decisions
function curses:TimeLeft(curseData)
	if curseData.currentPlayer then
		SyncFromAura(curseData)
	end

	local dhReduction = 0

	if curses.trackedCurseIds[curseData.spellID] and curses.trackedCurseIds[curseData.spellID].darkHarvest then
		curses:TrackDarkHarvest(curseData)

		dhReduction = curses:GetDarkHarvestReduction(curseData)
	end

	return curseData.duration - (GetTime() - curseData.start) - dhReduction
end

-- seconds left rounded for display (whole seconds, or tenths under 10s with Decimal Duration)
function curses:TimeRemaining(curseData)
	local remaining = curses:TimeLeft(curseData)
	if Cursive.db.profile.curseshowdecimals and remaining < 10 then
		-- round to 1 decimal point
		remaining = math.floor(remaining * 10) / 10
	else
		remaining = math.ceil(remaining)
	end

	return remaining
end

function curses:EnableResistSound(guid)
	curses.resistSoundGuids[guid] = true
end

function curses:EnableExpiringSound(lowercaseSpellNameNoRank, guid)
	if curses.requestedExpiringSoundGuids[guid] and curses.requestedExpiringSoundGuids[guid][lowercaseSpellNameNoRank] then
		curses.requestedExpiringSoundGuids[guid][lowercaseSpellNameNoRank] = nil
	end

	if not curses.expiringSoundGuids[guid] then
		curses.expiringSoundGuids[guid] = {}
	end
	curses.expiringSoundGuids[guid][lowercaseSpellNameNoRank] = true
end

function curses:RequestExpiringSound(lowercaseSpellNameNoRank, guid)
	if not curses.requestedExpiringSoundGuids[guid] then
		curses.requestedExpiringSoundGuids[guid] = {}
	end
	curses.requestedExpiringSoundGuids[guid][lowercaseSpellNameNoRank] = true
end

function curses:HasRequestedExpiringSound(lowercaseSpellNameNoRank, guid)
	return curses.requestedExpiringSoundGuids[guid] and curses.requestedExpiringSoundGuids[guid][lowercaseSpellNameNoRank]
end

function curses:ShouldPlayExpiringSound(lowercaseSpellNameNoRank, guid)
	if curses.expiringSoundGuids[guid] and curses.expiringSoundGuids[guid][lowercaseSpellNameNoRank] then
		curses.expiringSoundGuids[guid][lowercaseSpellNameNoRank] = nil -- remove entry to avoid playing sound multiple times
		return true
	end

	return false
end

function curses:ShouldPlayResistSound(guid)
	if curses.resistSoundGuids[guid] then
		curses.resistSoundGuids[guid] = nil -- remove entry to avoid playing sound multiple times
		return true
	end

	return false
end

function curses:HasAnyCurse(guid)
	if curses.guids[guid] and next(curses.guids[guid]) then
		return true
	end
	return nil
end

function curses:GetCurseData(spellName, guid)
	-- convert to lowercase and remove rank
	local lowercaseSpellNameNoRank = Cursive.utils.GetLowercaseSpellNameNoRank(spellName)

	if curses.guids[guid] and curses.guids[guid][lowercaseSpellNameNoRank] then
		return curses.guids[guid][lowercaseSpellNameNoRank]
	end

	return nil
end

function curses:HasCurse(lowercaseSpellNameNoRank, targetGuid, minRemaining, malediction)
	if not minRemaining then
		minRemaining = 0 -- default to 0
	end

	if malediction == nil then
		-- no malediction= option given: use the saved setting (on by default)
		malediction = Cursive.db.profile.malediction == false and 0 or 1
	end

	-- handle faerie fire special case
	if curses.isDruid and string.find(lowercaseSpellNameNoRank, L["faerie fire"]) then
		-- remove (feral) or (bear) from spell name
		lowercaseSpellNameNoRank = L["faerie fire"]
	end

	-- handle malediction for warlocks
	if curses.isWarlock and malediction ~= 0 and (
			lowercaseSpellNameNoRank == L["curse of recklessness"] or
			lowercaseSpellNameNoRank == L["curse of the elements"] or
			lowercaseSpellNameNoRank == L["curse of shadow"]) then
		local _, _, _, _, hasMalediction = GetTalentInfo(1, 17)
		if hasMalediction > 0 then
			lowercaseSpellNameNoRank = L["curse of agony"]
		end
	end

	if curses.guids[targetGuid] and curses.guids[targetGuid][lowercaseSpellNameNoRank] then
		-- exact time, not the rounded display value, so refreshtime doesn't depend on display settings
		local remaining = curses:TimeLeft(curses.guids[targetGuid][lowercaseSpellNameNoRank])

		if remaining >= minRemaining then
			return true
		end
	end

	-- check pending cast
	if curses.pendingCast and
			curses.pendingCast.targetGuid == targetGuid and
			curses.pendingCast.spellID and
			curses.trackedCurseIds[curses.pendingCast.spellID] and
			curses.trackedCurseIds[curses.pendingCast.spellID].name == lowercaseSpellNameNoRank then
		return true
	end

	return nil
end

-- Apply shared curse from another player
-- startTime is optional: without it, the timer is read from the other player's aura on the mob
-- (C_UnitAuras), falling back to "now" and the table's duration
function curses:ApplySharedCurse(sharedDebuffKey, spellID, targetGuid, startTime)
	local name = curses.sharedDebuffs[sharedDebuffKey][spellID].name
	local rank = curses.sharedDebuffs[sharedDebuffKey][spellID].rank
	local duration = curses.sharedDebuffs[sharedDebuffKey][spellID].duration

	if not startTime then
		startTime = GetTime()
		local aura = UnitExists(targetGuid) and C_UnitAuras.GetUnitAuraBySpellID(targetGuid, spellID, "HARMFUL|!PLAYER")
		if aura and aura.expirationTime and aura.expirationTime > 0 and aura.duration and aura.duration > 0 then
			duration = aura.duration
			startTime = aura.expirationTime - aura.duration
		end
	end

	if not curses.guids[targetGuid] then
		curses.guids[targetGuid] = {}
	end

	-- never replace the player's own active debuff with another player's
	local existing = GetActiveCurse(targetGuid, name)
	if existing and existing.currentPlayer then
		return
	end

	curses.guids[targetGuid][name] = {
		rank = rank,
		duration = duration,
		start = startTime,
		spellID = spellID,
		targetGuid = targetGuid,
		currentPlayer = false,
	}
end

-- Apply curse from player
function curses:ApplyCurse(spellID, targetGuid, startTime, duration)
	-- clear pending cast
	curses.pendingCast = {}

  local curseData = curses.trackedCurseIds[spellID]
  local name = curseData.name
  local rank = curseData.rank

	if not curses.guids[targetGuid] then
		curses.guids[targetGuid] = {}
	end

	curses.guids[targetGuid][name] = {
		rank = rank,
		duration = duration,
		start = startTime,
		spellID = spellID,
		appliedSpellID = GetAppliedCurseSpellID(spellID),
		targetGuid = targetGuid,
		currentPlayer = true,
		-- read the real timer from the mob's aura once it lands (see SyncFromAura)
		syncUntil = ShouldSyncAura(spellID) and (GetTime() + AURA_SYNC_WINDOW) or nil,
	}
end

function curses:RemoveCurse(guid, curseName)
	if curses.guids[guid] and curses.guids[guid][curseName] then
		curses.guids[guid][curseName] = nil
	end
	if curses.expiringSoundGuids[guid] and curses.expiringSoundGuids[guid][curseName] then
		curses.expiringSoundGuids[guid][curseName] = nil
	end
end

function curses:RemoveGuid(guid)
	curses.guids[guid] = nil
	curses.resistSoundGuids[guid] = nil
	curses.expiringSoundGuids[guid] = nil
	curses.requestedExpiringSoundGuids[guid] = nil
end

Cursive.curses = curses
