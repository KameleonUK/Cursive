-- First file in Cursive_ClassicAPI.toc.
-- ClassicAPI selects that TOC, so the DLL is loaded; this checks the DLL is new enough to provide
-- every function the addon calls. If anything is missing, global.lua sees CURSIVE_CLASSICAPI_MISSING
-- and turns the addon off through the same early return every file already uses.
-- Keep REQUIRED in sync with the code: grep the addon for C_ namespaces and other ClassicAPI globals.

local REQUIRED = {
	-- filled in as each area is ported to ClassicAPI
}

local function resolve(path)
	local value = getfenv(0)
	for part in string.gfind(path, '[^%.]+') do
		if type(value) ~= 'table' then return nil end
		value = value[part]
	end
	return value
end

local missing = {}
if not CLASSIC_API_VERSION then
	tinsert(missing, 'CLASSIC_API_VERSION')
end
for _, path in ipairs(REQUIRED) do
	if type(resolve(path)) ~= 'function' then
		tinsert(missing, path)
	end
end

if getn(missing) > 0 then
	CURSIVE_CLASSICAPI_MISSING = missing
	local f = CreateFrame('Frame')
	f:RegisterEvent('PLAYER_LOGIN')
	f:SetScript('OnEvent', function()
		DEFAULT_CHAT_FRAME:AddMessage('|cffff4040Cursive: your ClassicAPI is too old. Missing: '
			.. table.concat(missing, ', ') .. '. The addon is disabled.|r')
		this:UnregisterAllEvents()
	end)
end
