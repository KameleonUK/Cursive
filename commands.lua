if not Cursive.nampower then
	return
end

local L = AceLibrary("AceLocale-2.2"):new("Cursive")
local curseCommands = L["|cffffcc00Cursive:|cffffaaaa Commands:"]
local priorityChoices = L["|cffffcc00Priority choices:"]
local curseOptions = L["|cffffcc00Options (separate with ,):"]

local commandOptions = {
	warnings = L["Display text warnings when a curse fails to cast."],
	resistsound = L["Play a sound when a curse is resisted."],
	expiringsound = L["Play a sound when a curse is about to expire."],
	allowooc = L["Allow out of combat targets to be multicursed.  Would only consider using this solo to avoid potentially griefing raids/dungeons by pulling unintended mobs."],
	minhp = L["Minimum HP for a target to be considered.  Example usage minhp=10000. "],
	refreshtime = L["Time threshold at which to allow refreshing a curse.  Default is 0 seconds."],
	priotarget = L["Always prioritize current target when choosing target for multicurse.  Does not affect 'curse' command."],
	ignoretarget = L["Ignore the current target when choosing target for multicurse.  Does not affect 'curse' command."],
	playeronly = L["Only choose players and ignore npcs when choosing target for multicurse.  Does not affect 'curse' command."],
	istapped = L["Only choose mobs tagged by other players when choosing target for multicurse.  Does not affect 'curse' command."],
	name = L["Filter targets by name. Can be a partial match.  If no match is found, the command will do nothing."],
	ignorespellid = L["Ignore targets with the specified spell id already on them. Useful for ignoring targets that already have a shared debuff."],
	ignorespelltexture = L["Ignore targets with the specified spell texture already on them. Useful for ignoring targets that already have a shared debuff."],
	malediction = L["For Warlocks with the Malediction talent: when checking if Curse of Recklessness, Curse of the Elements, or Curse of Shadow is already on a target, check for Curse of Agony instead. Default is 1 (enabled). Set malediction=0 to disable and check for the original curse."],
}

local commands = {
	["curse"] = L["/cursive curse <spellName:str>|<guid?:str>|<options?:List<str>>: Casts spell if not already on target/guid"],
	["multicurse"] = L["/cursive multicurse <spellName:str>|<priority?:str>|<options?:List<str>>: Picks target based on priority and casts spell if not already on target"],
	["target"] = L["/cursive target <spellName:str>|<priority?:str>|<options?:List<str>>: Targets unit based on priority if spell in range and not already on target"],
}

local PRIORITY_HIGHEST_HP = "HIGHEST_HP"
local PRIORITY_LOWEST_HP = "LOWEST_HP"
local PRIORITY_RAID_MARK = "RAID_MARK"
local PRIORITY_RAID_MARK_SQUARE = "RAID_MARK_SQUARE"
local PRIORITY_INVERSE_RAID_MARK = "INVERSE_RAID_MARK"
local PRIORITY_HIGHEST_HP_RAID_MARK = "HIGHEST_HP_RAID_MARK"
local PRIORITY_HIGHEST_HP_RAID_MARK_SQUARE = "HIGHEST_HP_RAID_MARK_SQUARE"
local PRIORITY_HIGHEST_HP_INVERSE_RAID_MARK = "HIGHEST_HP_INVERSE_RAID_MARK"

local priorities = {
	[PRIORITY_HIGHEST_HP] = L["Target with the highest HP."],
	[PRIORITY_LOWEST_HP] = L["Target with the lowest HP."],
	[PRIORITY_RAID_MARK] = L["Target with the highest raid mark."],
	[PRIORITY_RAID_MARK_SQUARE] = L["Target with the highest raid mark, with Cross set to 0, Skull to -1 and no mark to -2 (Square highest prio at 6)."],
	[PRIORITY_INVERSE_RAID_MARK] = L["Target with the lowest raid mark."],
	[PRIORITY_HIGHEST_HP_RAID_MARK] = L["Target with the highest HP and raid mark."],
	[PRIORITY_HIGHEST_HP_RAID_MARK_SQUARE] = L["Same as HIGHEST_HP_RAID_MARK but with RAID_MARK_SQUARE mark prio."],
	[PRIORITY_HIGHEST_HP_INVERSE_RAID_MARK] = L["Same as HIGHEST_HP_RAID_MARK but with INVERSE_RAID_MARK mark prio."]
}

local curseNoTarget = L["|cffffcc00Cursive:|cffffaaaa Couldn't find a target to curse."]

local function trim(str)
	local _, _, trimmed = string.find(str, "^%s*(.-)%s*$")
	return trimmed
end

-- options that take a value, and how to convert it
local valueOptions = {
	minhp = tonumber,
	refreshtime = tonumber, -- accepts decimals, e.g. refreshtime=1.5
	ignorespellid = tonumber,
	malediction = tonumber,
	name = function(v) return v end, -- may contain spaces, apostrophes and hyphens (name=Kel'Thuzad)
	ignorespelltexture = function(v) return v end,
}

-- Parses "warnings,minhp=10000,name=Touched Warrior" into a table.
-- Options are matched as whole comma-separated tokens, so a value (such as a mob name)
-- can no longer switch on a flag by containing its text.
local function parseOptions(optionsStr)
	local options = {}

	if not optionsStr then
		return options
	end

	for token in string.gfind(optionsStr, "[^,]+") do
		local _, _, key, value = string.find(token, "^%s*([%a]+)%s*=(.*)$")
		if key then
			key = string.lower(key)
			local convert = valueOptions[key]
			value = trim(value)
			if convert and value ~= "" then
				options[key] = convert(value)
			end
		else
			-- plain flags; also accept flags separated by spaces instead of commas
			for word in string.gfind(token, "%S+") do
				local flag = string.lower(word)
				if commandOptions[flag] and not valueOptions[flag] then
					options[flag] = true
				end
			end
		end
	end

	return options
end

local function handleSlashCommands(msg, editbox)
	if not msg or msg == "" then
		DEFAULT_CHAT_FRAME:AddMessage(curseCommands)
		for _, description in pairs(commands) do
			DEFAULT_CHAT_FRAME:AddMessage(description)
		end
		DEFAULT_CHAT_FRAME:AddMessage(priorityChoices)
		for priority, description in pairs(priorities) do
			DEFAULT_CHAT_FRAME:AddMessage("|CFFFFFF00" .. priority .. "|R: " .. description)
		end

		DEFAULT_CHAT_FRAME:AddMessage(curseOptions)
		for option, description in pairs(commandOptions) do
			DEFAULT_CHAT_FRAME:AddMessage("|CFFFFFF00" .. option .. "|R: " .. description)
		end
		return
	end
	-- get first word in string
	local _, _, command, args = string.find(msg, "(%w+) (.*)")
	if command == "curse" then
		local spellName, targetedGuid, optionsStr = Cursive.utils.strsplit("|", args)
		local options = parseOptions(optionsStr)
		Cursive:Curse(spellName, targetedGuid, options)
	elseif command == "multicurse" then
		local spellName, priority, optionsStr = Cursive.utils.strsplit("|", args)
		local options = parseOptions(optionsStr)
		Cursive:Multicurse(spellName, priority, options)
	elseif command == "target" then
		local spellName, priority, optionsStr = Cursive.utils.strsplit("|", args)
		local options = parseOptions(optionsStr)
		Cursive:Target(spellName, priority, options)
	else
		DEFAULT_CHAT_FRAME:AddMessage(L["|cffffcc00Cursive:|cffffaaaa Unknown command."])
		DEFAULT_CHAT_FRAME:AddMessage(curseCommands)
		for _, description in pairs(commands) do
			DEFAULT_CHAT_FRAME:AddMessage(description)
		end
	end
end

local crowdControlledSpellIds = {
	[700] = { name = L["sleep"], rank = 1, duration = 20 },
	[1090] = { name = L["sleep"], rank = 2, duration = 30 },
	[2937] = { name = L["sleep"], rank = 3, duration = 40 },

	[339] = { name = L["entangling roots"], rank = 1, duration = 12 },
	[1062] = { name = L["entangling roots"], rank = 2, duration = 15 },
	[5195] = { name = L["entangling roots"], rank = 3, duration = 18 },
	[5196] = { name = L["entangling roots"], rank = 4, duration = 21 },
	[9852] = { name = L["entangling roots"], rank = 5, duration = 24 },
	[9853] = { name = L["entangling roots"], rank = 6, duration = 27 },

	[2637] = { name = L["hibernate"], rank = 1, duration = 20 },
	[18657] = { name = L["hibernate"], rank = 2, duration = 30 },
	[18658] = { name = L["hibernate"], rank = 3, duration = 40 },

	-- real Shackle Undead ids (spells/priest.lua was corrected to these in 70b71b6)
	[9484] = { name = L["shackle undead"], rank = 1, duration = 30 },
	[9485] = { name = L["shackle undead"], rank = 2, duration = 40 },
	[10955] = { name = L["shackle undead"], rank = 3, duration = 50 },
	-- older ids, kept in case they are still used as aura ids
	[1425] = { name = L["shackle undead"], rank = 1, duration = 30 },
	[9486] = { name = L["shackle undead"], rank = 2, duration = 40 },
	[10956] = { name = L["shackle undead"], rank = 3, duration = 50 },

	-- polymorph
	[118] = { name = L["polymorph"], rank = L["Rank 1"], duration = 20 },
	[12824] = { name = L["polymorph"], rank = L["Rank 2"], duration = 30 },
	[12825] = { name = L["polymorph"], rank = L["Rank 3"], duration = 40 },
	[12826] = { name = L["polymorph"], rank = L["Rank 4"], duration = 50 },

	[28270] = { name = L["polymorph: cow"], rank = L["Rank 1"], duration = 50 },
	[28271] = { name = L["polymorph: turtle"], rank = L["Rank 1"], duration = 50 },
	[28272] = { name = L["polymorph: pig"], rank = L["Rank 1"], duration = 50 },

	[2878] = { name = L["turn undead"], rank = 1, duration = 10 },
	[5627] = { name = L["turn undead"], rank = 2, duration = 15 },
	[10326] = { name = L["turn undead"], rank = 3, duration = 20 },

	[2094] = { name = L["blind"], rank = 1, duration = 10 },
	[21060] = { name = L["blind"], rank = 1, duration = 10 },

	[6770] = { name = L["sap"], rank = 1, duration = 25 },
	[2070] = { name = L["sap"], rank = 2, duration = 35 },
	[11297] = { name = L["sap"], rank = 3, duration = 45 },

	[1776] = { name = L["gouge"], rank = 1, duration = 4 },
	[1777] = { name = L["gouge"], rank = 2, duration = 4 },
	[8629] = { name = L["gouge"], rank = 3, duration = 4 },
	[11285] = { name = L["gouge"], rank = 4, duration = 4 },
	[11286] = { name = L["gouge"], rank = 5, duration = 4 },

	[3355] = { name = L["freezing trap"], rank = 1, duration = 10 },
	[14308] = { name = L["freezing trap"], rank = 2, duration = 15 },
	[14309] = { name = L["freezing trap"], rank = 3, duration = 20 },

	[710] = { name = L["banish"], rank = 1, duration = 30 },
	[18647] = { name = L["banish"], rank = 2, duration = 30 },

	-- mind control effects
	[28410] = { name = "Chains of Kel'Thuzad" }, -- we aren't casting these, name doesn't matter
	[7621] = { name = "Arugal's Curse" },
	[24261] = { name = "Brain Wash" },
	[12888] = { name = "Cause Insanity" },
	[24327] = { name = "Cause Insanity" },
	[26079] = { name = "Cause Insanity" },
	[23174] = { name = "Chromatic Mutation" },
	[25806] = { name = "Creature of Nightmare" },
	[23298] = { name = "Demonic Doom" },
	[7645] = { name = "Dominate Mind" },
	[14515] = { name = "Dominate Mind" },
	[15859] = { name = "Dominate Mind" },
	[20604] = { name = "Dominate Mind" },
	[20740] = { name = "Dominate Mind" },
	[17405] = { name = "Domination" },
	[3442] = { name = "Enslave" },
	[13181] = { name = "Gnomish Mind Control Cap" },
	[26740] = { name = "Gnomish Mind Control Cap" },
	[12483] = { name = "Hex of Jammal'an" },
	[25772] = { name = "Mental Domination" },
	[7967] = { name = "Naralex's Nightmare" },
	[19469] = { name = "Poison Mind" },
	[17244] = { name = "Possess" },
	[22667] = { name = "Shadow Command" },
	[20668] = { name = "Sleepwalk" },
	[785] = { name = "True Fulfillment" },
	[26195] = { name = "Whisperings of C'Thun" },
	[26197] = { name = "Whisperings of C'Thun" },
	[26198] = { name = "Whisperings of C'Thun" },
	[26258] = { name = "Whisperings of C'Thun" },
	[26259] = { name = "Whisperings of C'Thun" },
	[24178] = { name = "Will of Hakkar" },

	-- immunity effects
	[642] = { name = "Divine Shield" },
	[1020] = { name = "Divine Shield" },
	[13874] = { name = "Divine Shield" },
	[5573] = { name = "Divine Protection" },
	[13007] = { name = "Divine Protection" },
	[6356] = { name = "Spell Immunity" },
	[6724] = { name = "Light of Elune" },
	[7121] = { name = "Anti-Magic Shield" },
	[19645] = { name = "Anti-Magic Shield" },
	[24021] = { name = "Anti-Magic Shield" },
	[8361] = { name = "Purity" },
	[8611] = { name = "Phase Shift" },
	[45713] = { name = "Phase Shift" },
	[9438] = { name = "Arcane Bubble" },
	[11958] = { name = "Ice Block" },
	[12843] = { name = "Mordresh's Shield" },
	[21892] = { name = "Arcane Protection" },
	[51096] = { name = "Worgen Dimension" },
	[51228] = { name = "Invulnerability" },
	[52010] = { name = "Pending Detonation" },
	[53225] = { name = "Ward of Vorgendor" },
	[57644] = { name = "Veil of Vorgendor" },
}

local spellImmuneGuids = {
  ["0xF1300030A9014A44"] = true, -- Blackwing Spellbinder
  ["0xF1300030A911F78C"] = true, -- Blackwing Spellbinder
  ["0xF1300030A911F78D"] = true, -- Blackwing Spellbinder
  ["0xF1300030A9014EFE"] = true, -- Blackwing Spellbinder
  ["0xF1300030A9014F08"] = true, -- Blackwing Spellbinder
  ["0xF1300030A9014E75"] = true, -- Blackwing Spellbinder
  ["0xF1300030A9014E6D"] = true, -- Blackwing Spellbinder
}

local function isMobCrowdControlled(guid)
	local auras = GetUnitField(guid, "aura") or {}
	for i, spellId in pairs(auras) do
		if crowdControlledSpellIds[spellId] then
			return true
		end
	end
	return false
end

local function isMobSpellImmune(guid)
	return spellImmuneGuids[guid] and true or false
end

local function GetSquarePrioRaidTargetIndex(guid)
	local index = GetRaidTargetIndex(guid)
	if index == 7 then
		return 0 -- cross becomes 0
	elseif index == 8 then
		return -1 -- skull becomes -1
	elseif index == 0 then
		return -2 -- nomark becomes -2
	end
	return index or -2
end

local function hasSpellId(guid, ignoreSpellId)
	local auras = GetUnitField(guid, "aura") or {}
	for i, spellId in pairs(auras) do
		if spellId == ignoreSpellId then
			return true
		end
	end
	return false
end

local function hasSpellTexture(guid, ignoreTexture)
	for i = 1, 16 do
		local texture = UnitDebuff(guid, i);
		if not texture then
			break
		end
		if string.find(texture, ignoreTexture) then
			return true
		end
	end

	for i = 1, 32 do
		local texture = UnitBuff(guid, i);
		if not texture then
			break
		end
		if string.find(texture, ignoreTexture) then
			return true
		end
	end

	return false
end

local function passedOptionFilters(guid, options)
	if options["name"] then
		local name = UnitName(guid)
		-- plain-text match: names can contain magic characters such as "-"
		if not name or not string.find(name, options["name"], 1, true) then
			return false
		end
	end
	if options["ignorespellid"] then
		if hasSpellId(guid, options["ignorespellid"]) then
			return false
		end
	end
	if options["ignorespelltexture"] then
		if hasSpellTexture(guid, options["ignorespelltexture"]) then
			return false
		end
	end
	if options["playeronly"] and not UnitIsPlayer(guid) then
		return false
	end
	if options["istapped"] and not UnitIsTapped(guid) then
		return false
	end
	return true
end

local NO_HP = 999999999999 -- bigger than any mob hp

-- Scores a candidate as (tier, primary, secondary); higher is better, compared in that order.
-- tier 2: current target with priotarget, whatever the priority direction
-- tier 1: marked mob for the HIGHEST_HP_*RAID_MARK* priorities, so any marked mob beats any unmarked one
local function scoreTarget(selectedPriority, guid, isPrioTarget)
	local tier, primary, secondary = 0, 0, 0
	local hp = UnitHealth(guid)

	if isPrioTarget then
		tier = 2
	end

	if selectedPriority == PRIORITY_HIGHEST_HP then
		primary = hp or 0
	elseif selectedPriority == PRIORITY_LOWEST_HP then
		primary = -(hp or NO_HP)
	elseif selectedPriority == PRIORITY_RAID_MARK then
		primary = GetRaidTargetIndex(guid) or 0
	elseif selectedPriority == PRIORITY_RAID_MARK_SQUARE then
		primary = GetSquarePrioRaidTargetIndex(guid)
	elseif selectedPriority == PRIORITY_INVERSE_RAID_MARK then
		primary = -1 * (GetRaidTargetIndex(guid) or 9)
	elseif selectedPriority == PRIORITY_HIGHEST_HP_RAID_MARK then
		local mark = GetRaidTargetIndex(guid)
		if mark and tier < 1 then tier = 1 end
		primary = hp or 0
		secondary = mark or 0
	elseif selectedPriority == PRIORITY_HIGHEST_HP_RAID_MARK_SQUARE then
		secondary = GetSquarePrioRaidTargetIndex(guid)
		if secondary > -2 and tier < 1 then tier = 1 end
		primary = hp or 0
	elseif selectedPriority == PRIORITY_HIGHEST_HP_INVERSE_RAID_MARK then
		local mark = GetRaidTargetIndex(guid)
		if mark and tier < 1 then tier = 1 end
		primary = hp or 0
		secondary = -1 * (mark or 9)
	end

	return tier, primary, secondary
end

-- C_Spell.IsSpellInRange uses the engine's own range check (target size and melee range included).
-- It returns nil when the check doesn't apply (spell not in the spellbook, wrong target type);
-- then fall back to 28 yards.
local function isSpellInRange(spellNameNoRank, lowercaseSpellNameNoRank, guid)
	local result = C_Spell.IsSpellInRange(spellNameNoRank, guid)
	if result == nil and Cursive.curses.isDruid and string.find(lowercaseSpellNameNoRank, "faerie fire %(feral%)") then
		result = C_Spell.IsSpellInRange(17392, guid) -- Faerie Fire (Feral) by spell id
	end
	if result == nil then
		return CheckInteractDistance(guid, 4) and true or false
	end
	return result
end

local function pickTarget(selectedPriority, spellNameNoRank, lowercaseSpellNameNoRank, options)
	-- Curse the target that best matches the selected priority
	local bestTier, bestPrimary, bestSecondary
	local targetedGuid = nil

	local minHp = options["minhp"]
	local ignoreInFight = options["allowooc"]
	local refreshTime = options["refreshtime"]

	local currentTargetGuid = UnitGUID("target")

	for guid, time in pairs(Cursive.core.guids) do
		-- apply filters
		local shouldDisplay = Cursive:ShouldDisplayGuid(guid)
		-- check if target displayed
		if shouldDisplay then
			if not options["ignoretarget"] or guid ~= currentTargetGuid then
				-- check if in combat already or player is actively targeting the mob
				if ignoreInFight or Cursive.filter.infight(guid) or guid == currentTargetGuid then
					if passedOptionFilters(guid, options) then
						if isSpellInRange(spellNameNoRank, lowercaseSpellNameNoRank, guid) then
							-- check if the target has the curse
              if not Cursive.curses:HasCurse(lowercaseSpellNameNoRank, guid, refreshTime, options["malediction"]) and
                  not isMobCrowdControlled(guid) and
                  not isMobSpellImmune(guid) then
								local mobHp = UnitHealth(guid)
								if not minHp or (mobHp and mobHp >= minHp) then
									local isPrioTarget = options["priotarget"] and guid == currentTargetGuid
									local tier, primary, secondary = scoreTarget(selectedPriority, guid, isPrioTarget)

									if not bestTier or
											tier > bestTier or
											(tier == bestTier and primary > bestPrimary) or
											(tier == bestTier and primary == bestPrimary and secondary > bestSecondary) then
										bestTier, bestPrimary, bestSecondary = tier, primary, secondary
										targetedGuid = guid
									end
								end
							end
						end
					end
				end
			end
		end
	end

	return targetedGuid
end

-- C_Spell.CastAtUnit casts on the GUID whatever the current target is (it replaces SuperWoW's
-- two-argument CastSpellByName). Returns false when the cast didn't go out, so Curse and
-- Multicurse can report that and a macro chain can move on to its next spell.
local function castSpellWithOptions(spellName, lowercaseSpellNameNoRank, targetedGuid, options)
	if not C_Spell.CastAtUnit(spellName, targetedGuid) then
		return false
	end

	if options["resistsound"] then
		Cursive.curses:EnableResistSound(targetedGuid)
	end
	if options["expiringsound"] then
		Cursive.curses:RequestExpiringSound(lowercaseSpellNameNoRank, targetedGuid)
	end
	return true
end

function Cursive:Curse(spellName, targetedGuid, options)
	options = options or {} -- /script callers may leave the options table out

	if not spellName or not targetedGuid then
		DEFAULT_CHAT_FRAME:AddMessage(commands["curse"])
		return false
	end

	if targetedGuid and string.sub(targetedGuid, 1, 2) ~= "0x" then
		-- "target", "mouseover", "mark8", ...; UnitGUID raises an error on text that isn't a unit token
		if IsUnitToken(targetedGuid) then
			targetedGuid = UnitGUID(targetedGuid)
		else
			targetedGuid = nil
		end

		if not targetedGuid then
			if options["warnings"] then
				DEFAULT_CHAT_FRAME:AddMessage(curseNoTarget)
			end
			return false
		end
	end

	if targetedGuid then
		-- check for options
		if not passedOptionFilters(targetedGuid, options) then
			if options["warnings"] then
				DEFAULT_CHAT_FRAME:AddMessage(curseNoTarget)
			end
			return false
		end
	end

	-- remove (Rank x) from spellName if it exists
	local lowercaseSpellNameNoRank = Cursive.utils.GetLowercaseSpellNameNoRank(spellName)

	if targetedGuid and
			not Cursive.curses:HasCurse(lowercaseSpellNameNoRank, targetedGuid, options["refreshtime"], options["malediction"]) and
			not isMobCrowdControlled(targetedGuid) and
			not isMobSpellImmune(targetedGuid) and
			castSpellWithOptions(spellName, lowercaseSpellNameNoRank, targetedGuid, options) then
		return true
	elseif options["warnings"] then
		DEFAULT_CHAT_FRAME:AddMessage(curseNoTarget)
	end

	return false
end

local function getSpellTarget(spellName, priority, options)
	options = options or {} -- /script callers may leave the options table out

	if not spellName then
		DEFAULT_CHAT_FRAME:AddMessage(commands["multicurse"])
		return
	end

	if priority and not priorities[priority] then
		DEFAULT_CHAT_FRAME:AddMessage(priorityChoices)
		for choice, description in pairs(priorities) do
			DEFAULT_CHAT_FRAME:AddMessage("|CFFFFFF00" .. choice .. "|R: " .. description)
		end
		return
	end

	local selectedPriority = priority or PRIORITY_HIGHEST_HP

	-- remove (Rank x) from spellName if it exists
	local spellNameNoRank = Cursive.utils.GetSpellNameNoRank(spellName)
	local lowercaseSpellNameNoRank = Cursive.utils.GetLowercaseSpellNameNoRank(spellName)

	return pickTarget(selectedPriority, spellNameNoRank, lowercaseSpellNameNoRank, options)
end

function Cursive:Multicurse(spellName, priority, options)
	options = options or {}
	local targetedGuid = getSpellTarget(spellName, priority, options)
	local lowercaseSpellNameNoRank = spellName and Cursive.utils.GetLowercaseSpellNameNoRank(spellName)
	if targetedGuid and castSpellWithOptions(spellName, lowercaseSpellNameNoRank, targetedGuid, options) then
		return true
	elseif options["warnings"] then
		DEFAULT_CHAT_FRAME:AddMessage(curseNoTarget)
	end
	return false
end

function Cursive:GetTarget(spellName, priority, options)
	return getSpellTarget(spellName, priority, options)
end

function Cursive:Target(spellName, priority, options)
	local targetedGuid = getSpellTarget(spellName, priority, options)
	if targetedGuid then
		TargetUnit(targetedGuid)
		return true
	end
	return false
end

SLASH_CURSIVE1 = "/cursive" --creating the slash command
SlashCmdList["CURSIVE"] = handleSlashCommands --associating the function with the slash command
