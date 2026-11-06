-- Loaded only by the plain Cursive.toc, i.e. on a client WITHOUT ClassicAPI.
-- With ClassicAPI present, Cursive_ClassicAPI.toc is loaded instead and this file never runs.
-- This build has no stock-client code path, so all it does is explain why nothing happens.
-- The plain TOC lists no SavedVariables, so a stock client never touches the user's saved data.

local f = CreateFrame('Frame')
f:RegisterEvent('PLAYER_LOGIN')
f:SetScript('OnEvent', function()
	DEFAULT_CHAT_FRAME:AddMessage('|cffff4040Cursive requires the ClassicAPI DLL. The addon is disabled.|r')
	this:UnregisterAllEvents()
end)
