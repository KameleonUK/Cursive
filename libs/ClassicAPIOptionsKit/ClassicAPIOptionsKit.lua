--[[
ClassicAPIOptionsKit - native "AddOn Options" pages for WoW 1.12.1 addons on ClassicAPI

ClassicAPI adds InterfaceOptionsFrame and InterfaceOptions_AddCategory to the 1.12 client, so an addon can
list its settings under Game Menu > AddOn Options, the same way later clients do. This kit builds those
pages from short declarative calls:

	local Kit = ClassicAPIOptionsKit
	local bind = Kit.Binder(function() return MyAddonDB end, MyAddonDefaults, Kit.Defer(MyAddon_Apply))
	local root = Kit:NewPage({name = "MyAddon", title = "MyAddon", subtitle = "What it does.", bind = bind})
	root:Checkbox({key = "enabled", label = "Enable", tooltip = "Turns it on."})
	local look = Kit:NewPage({name = "Appearance", parent = "MyAddon", bind = bind})
	look:Slider({key = "scale", label = "Scale", min = 0.5, max = 2, step = 0.05})
	look:Color({key = "barcolor", label = "Bar colour", enabledIf = function() return MyAddonDB.enabled end})

Every control reads and writes through a setting {get, set, reset}. With a page bind, `key` is enough.
Changes apply at once; the window's Cancel puts back what each page had when it was opened, and Defaults
resets the page that's shown.

Lua 5.0 (WoW 1.12): scripts use the `this` and `arg1` globals, and there is no # or select().

Embedding: copy this file into the addon (libs\ClassicAPIOptionsKit\) and list it in the .toc before the file
that builds the pages. Several addons can embed it; the newest version loaded wins.
]]

local VERSION = 4
if ClassicAPIOptionsKit and (ClassicAPIOptionsKit.version or 0) >= VERSION then return end
local Kit = ClassicAPIOptionsKit or {}
ClassicAPIOptionsKit = Kit
Kit.version = VERSION

local INDENT = 20 -- extra left margin for a control that depends on the one above it
local CONTENT_WIDTH = 500 -- the scroll child's widest width; ContentWidth() narrows it to fit the container

-- Usable page width. InterfaceOptionsFramePanelContainer can be narrower than CONTENT_WIDTH (about 470 on
-- Turtle WoW + ClassicAPI), and text wrapped at a wider width ran past the panel's right edge (aux, 2026-11).
-- 22 = the scroll frame's 18px right inset plus a small margin.
local function ContentWidth()
	local container = InterfaceOptionsFramePanelContainer
	local width = container and container:GetWidth()
	if width and width > 100 then
		return math.min(CONTENT_WIDTH, width - 22)
	end
	return CONTENT_WIDTH
end

Kit.count = Kit.count or 0
local function NextName()
	Kit.count = Kit.count + 1
	return "ClassicAPIOptionsKitControl"..Kit.count -- the option templates need named frames ($parentText etc)
end

-----------------
-- Settings --
-----------------

-- deep copy, so a default or a Cancel snapshot never shares a table with the saved settings
function Kit.Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = Kit.Copy(v)
	end
	return copy
end

-- Wraps fn so that however many times it's called in one frame, it runs once, on the next frame. Use it for
-- the addon's "apply settings" function: dragging a slider or pressing Defaults then redraws once, not per change.
-- It waits on a plain OnUpdate frame, not C_Timer: C_Timer callbacks run inside ClassicAPI's per-frame tick,
-- and changing nameplate frames from there has crashed the client (Kui_Nameplates)
function Kit.Defer(fn)
	local frame = CreateFrame("Frame")
	frame:Hide()
	frame:SetScript("OnUpdate", function()
		this:Hide()
		fn()
	end)
	return function()
		frame:Show()
	end
end

-- Returns bind(key) -> setting for one saved-variables table.
--   db: the table, or a function returning it. Prefer a function: WoW replaces a SavedVariables global when
--       it loads the file, so a table captured before ADDON_LOADED is the wrong one.
--   defaults: a table of default values, or a function(key) returning one. Defaults are copied on reset.
--   onChange: optional function(key, value), called after every write (wrap it in Kit.Defer)
function Kit.Binder(db, defaults, onChange)
	local function Table()
		if type(db) == "function" then return db() end
		return db
	end
	local function Default(key)
		if type(defaults) == "function" then return defaults(key) end
		return defaults and defaults[key]
	end
	return function(key)
		return {
			get = function() return Table()[key] end,
			set = function(value)
				Table()[key] = value
				if onChange then onChange(key, value) end
			end,
			reset = function()
				Table()[key] = Kit.Copy(Default(key))
				if onChange then onChange(key) end
			end,
		}
	end
end

-----------
-- Pages --
-----------

local PageMethods = {}

local function IsListed(page)
	for _, panel in ipairs(INTERFACEOPTIONS_ADDONCATEGORIES or {}) do
		if panel == page then return true end
	end
end

-- Some addons ship an old Ace3 AceConfigDialog-3.0 that replaces the global InterfaceOptions_AddCategory with
-- one that only accepts its own widgets, and errors on anything else (Kui_Nameplates does). The window lists
-- whatever is in INTERFACEOPTIONS_ADDONCATEGORIES, and adding to that table is all the real function does, so
-- when the call fails do it directly.
local function AddCategory(page, position)
	if pcall(InterfaceOptions_AddCategory, page, nil, position) and IsListed(page) then
		return
	end
	local categories = INTERFACEOPTIONS_ADDONCATEGORIES
	if not categories then
		error("ClassicAPIOptionsKit: no AddOn Options window (needs ClassicAPI)", 3)
	end
	if not IsListed(page) then
		if position then
			table.insert(categories, position, page)
		else
			table.insert(categories, page)
		end
	end
end

local function RefreshControls(page)
	page.updating = true -- sliders fire OnValueChanged when Update sets them; this stops that writing back
	for _, control in ipairs(page.controls) do
		if control.Update then
			control:Update()
		end
	end
	page.updating = nil
end

-- The panel container is a fixed-size, non-scrolling frame, and a page taller than it just runs off the
-- bottom. So every page scrolls with the mouse wheel (no scrollbar), and controls go on page.scrollChild.
--   o.name     the entry in the AddOns list (required, unique)
--   o.parent   the name of the parent entry, for a child page
--   o.title    the heading on the page (defaults to name)
--   o.subtitle a line of text under the heading
--   o.bind     a Kit.Binder result, so controls can use key = "..."
--   o.position index in the AddOns list (InterfaceOptions_AddCategory lists children in add order)
--   o.onShow   called each time the page is shown, before the controls refresh
function Kit:NewPage(o)
	local page = CreateFrame("Frame")
	page.name = o.name
	page.parent = o.parent
	page.controls = {}
	page.bind = o.bind
	page.y = 0

	local heading = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	heading:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -16)
	heading:SetText(o.title or o.name)

	local bodyTop = -40
	if o.subtitle then
		local text = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		text:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
		text:SetPoint("RIGHT", page, "RIGHT", -32, 0)
		text:SetJustifyH("LEFT")
		text:SetText(o.subtitle)
		bodyTop = -64
	end

	local scroll = CreateFrame("ScrollFrame", nil, page)
	scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, bodyTop)
	scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -18, 4)
	scroll:EnableMouseWheel(true)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetWidth(ContentWidth())
	child:SetHeight(1)
	scroll:SetScrollChild(child)
	page.scroll = scroll
	page.scrollChild = child
	scroll:SetScript("OnMouseWheel", function()
		local target = this:GetVerticalScroll() - arg1 * 40
		local range = this:GetVerticalScrollRange()
		if target < 0 then target = 0 end
		if target > range then target = range end
		this:SetVerticalScroll(target)
	end)

	-- the window calls these. refresh runs inside a pcall, so an error there silently skips later controls
	page.refresh = function()
		if o.onShow then o.onShow(page) end
		if not page.saved then -- first showing since Okay/Cancel: remember the values Cancel goes back to
			page.saved = {}
			for i, control in ipairs(page.controls) do
				if control.setting then
					page.saved[i] = Kit.Copy(control.setting.get())
				end
			end
		end
		RefreshControls(page)
	end
	page.okay = function()
		page.saved = nil
	end
	page.cancel = function() -- called for every page, including ones never shown (no snapshot, nothing to undo)
		if not page.saved then return end
		for i, control in ipairs(page.controls) do
			if control.setting and control.setting.get() ~= page.saved[i] then
				control.setting.set(Kit.Copy(page.saved[i]))
			end
		end
		page.saved = nil
	end
	page.default = function()
		for _, control in ipairs(page.controls) do
			if control.setting and control.setting.reset then
				control.setting.reset()
			end
		end
		RefreshControls(page)
	end

	for name, fn in pairs(PageMethods) do
		page[name] = fn
	end
	AddCategory(page, o.position)
	return page
end

-- Opens the window at a page (the page frame or its name). Prefers ClassicAPI's own copy of the function: an
-- old Ace3 AceConfigDialog-3.0 replaces the global with one that opens its own window instead
function Kit:Open(page)
	local open = (ClassicAPI and ClassicAPI.InterfaceOptionsFrame_OpenToCategory) or InterfaceOptionsFrame_OpenToCategory
	open(page)
end

-- redraw every control on a page, e.g. after the addon changed a setting itself
function PageMethods:Refresh()
	RefreshControls(self)
end

--------------
-- Helpers --
--------------

local function SettingFor(page, o)
	local setting = o.setting or (o.key and page.bind and page.bind(o.key))
	if not setting then
		error("ClassicAPIOptionsKit: '"..tostring(o.label).."' needs a key (on a page with bind) or a setting", 3)
	end
	if o.onSet then -- runs after the write, e.g. to switch off an option that conflicts with this one
		local set = setting.set
		setting = {get = setting.get, reset = setting.reset, set = function(value)
			set(value)
			o.onSet(value)
		end}
	end
	return setting
end

local function IndentOf(o)
	if type(o.indent) == "number" then return o.indent end
	if o.indent == true or (o.indent == nil and o.enabledIf) then return INDENT end
	return 0
end

local function IsEnabled(o)
	return not o.enabledIf or o.enabledIf()
end

local function Colorize(fontstring, enabled, normal)
	local c = enabled and (normal or NORMAL_FONT_COLOR) or GRAY_FONT_COLOR
	fontstring:SetTextColor(c.r, c.g, c.b)
end

local function SetTooltip(frame, text)
	if not text then return end
	frame:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText(text, nil, nil, nil, nil, 1)
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

local function Label(o)
	if o.reload then
		return o.label.." |cff808080(reload)|r"
	end
	return o.label
end

-- registers a control and moves the cursor down. The scroll child has to grow with its content: a
-- ScrollFrame works out its range from the child's size, not from what's drawn
local function AddControl(page, control, setting, height)
	control.setting = setting
	table.insert(page.controls, control)
	page.y = page.y - height
	page.scrollChild:SetHeight(-page.y)
end

local function Advance(page, height)
	page.y = page.y - height
	page.scrollChild:SetHeight(-page.y)
end

--------------
-- Controls --
--------------

function PageMethods:Header(text)
	local header = self.scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	header:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 16, self.y - 10)
	header:SetText(text)
	Advance(self, 30)
	return header
end

-- a paragraph of small text that wraps
function PageMethods:Text(text)
	local fs = self.scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 16, self.y - 2)
	fs:SetWidth(ContentWidth() - 40)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	Advance(self, fs:GetHeight() + 10)
	return fs
end

function PageMethods:Spacer(height)
	Advance(self, height or 10)
end

-- o: key/setting, label, tooltip, enabledIf, indent, onSet, reload
function PageMethods:Checkbox(o)
	local page = self
	local setting = SettingFor(page, o)
	local check = CreateFrame("CheckButton", NextName(), page.scrollChild, "OptionsCheckButtonTemplate")
	check:SetPoint("TOPLEFT", page.scrollChild, "TOPLEFT", 16 + IndentOf(o), page.y)
	local text = getglobal(check:GetName().."Text")
	text:SetText(Label(o))
	check.tooltipText = o.tooltip -- the template shows this on mouseover
	check:SetScript("OnClick", function()
		setting.set(this:GetChecked() and true or false)
		RefreshControls(page) -- controls that depend on this one grey out or come back
	end)
	check.Update = function(self)
		self:SetChecked(setting.get())
		if IsEnabled(o) then
			self:Enable()
		else
			self:Disable()
		end
		Colorize(text, IsEnabled(o))
	end
	AddControl(page, check, setting, 28)
	return check
end

-- o: key/setting, label, tooltip, min, max, step, format(value) -> text, enabledIf, indent, onSet
function PageMethods:Slider(o)
	local page = self
	local setting = SettingFor(page, o)
	local step = o.step or 1
	local slider = CreateFrame("Slider", NextName(), page.scrollChild, "OptionsSliderTemplate")
	slider:SetPoint("TOPLEFT", page.scrollChild, "TOPLEFT", 24 + IndentOf(o), page.y - 20)
	slider:SetWidth(200)
	slider:SetMinMaxValues(o.min, o.max)
	slider:SetValueStep(step)
	slider.tooltipText = o.tooltip

	-- the template centres its label over the slider, so a long one runs off the panel's left edge
	local name = slider:GetName()
	local label = getglobal(name.."Text")
	label:ClearAllPoints()
	label:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 2)
	label:SetJustifyH("LEFT")
	label:SetText(Label(o))
	local low, high = getglobal(name.."Low"), getglobal(name.."High")
	local value = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	value:SetPoint("LEFT", slider, "RIGHT", 8, 0)

	-- GetValue on a fractional step returns float noise (0.20000000298), so round to the step's decimals
	local decimals = 0
	if step < 1 then
		local s = tostring(step)
		local dot = string.find(s, "%.")
		decimals = dot and (string.len(s) - dot) or 0
	end
	local function Format(v)
		if o.format then return o.format(v) end
		if decimals > 0 then return string.format("%."..decimals.."f", v) end
		return string.format("%d", v)
	end
	local function Snap(v) -- store the rounded value, not the float noise
		if decimals > 0 then return tonumber(string.format("%."..decimals.."f", v)) end
		return math.floor(v + 0.5)
	end
	low:SetText(Format(o.min))
	high:SetText(Format(o.max))

	slider:SetScript("OnValueChanged", function()
		local v = Snap(this:GetValue())
		value:SetText(Format(v))
		if not page.updating and v ~= setting.get() then
			setting.set(v)
		end
	end)
	slider.Update = function(self)
		local v = setting.get() or o.min
		self:SetValue(v)
		value:SetText(Format(v))
		-- a disabled slider stops dragging but doesn't look different, so grey the text ourselves
		local enabled = IsEnabled(o)
		if enabled then
			self:Enable()
		else
			self:Disable()
		end
		Colorize(label, enabled)
		Colorize(low, enabled, HIGHLIGHT_FONT_COLOR)
		Colorize(high, enabled, HIGHLIGHT_FONT_COLOR)
		Colorize(value, enabled, HIGHLIGHT_FONT_COLOR)
	end
	AddControl(page, slider, setting, 52)
	return slider
end

-- A dropdown list holds 32 entries (UIDROPDOWNMENU_MAXBUTTONS), so a longer list is split into submenus of
-- GROUP_SIZE, each labelled with its first and last entry
local MAX_FLAT, GROUP_SIZE = 30, 25

-- o: key/setting, label, tooltip, options = {{value = v, text = "Shown"}, ...} or a function returning that
-- list (read each time the menu opens, e.g. for LibSharedMedia lists that grow), width, enabledIf, indent, onSet
-- A saved value that isn't in the list (a custom font path, say) shows as itself.
function PageMethods:Dropdown(o)
	local page = self
	local setting = SettingFor(page, o)
	local function Options()
		if type(o.options) == "function" then return o.options() or {} end
		return o.options
	end
	local indent = IndentOf(o)
	local title = page.scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", page.scrollChild, "TOPLEFT", 20 + indent, page.y - 4)
	title:SetText(Label(o))

	local dropdown = CreateFrame("Frame", NextName(), page.scrollChild, "UIDropDownMenuTemplate")
	dropdown:SetPoint("TOPLEFT", page.scrollChild, "TOPLEFT", indent, page.y - 18)
	UIDropDownMenu_SetWidth(o.width or 180, dropdown) -- 1.12 argument order: width first
	local name = dropdown:GetName()
	local boxText = getglobal(name.."Text")
	local button = getglobal(name.."Button") -- the template's real clickable part, which has Enable/Disable
	SetTooltip(dropdown, o.tooltip)
	if button and o.tooltip then
		SetTooltip(button, o.tooltip)
	end

	-- DropDownList1 is one popup shared by every dropdown in the game. Only fill it when this dropdown is
	-- being opened (ToggleDropDownMenu calls .initialize then), never from a page refresh
	dropdown.initialize = function()
		local level = UIDROPDOWNMENU_MENU_LEVEL or 1
		local selected = setting.get()
		local options = Options()
		local count = table.getn(options)
		local first, last = 1, count
		if count > MAX_FLAT then
			if level == 1 then -- the groups; each opens a submenu with its entries
				for g = 1, math.ceil(count / GROUP_SIZE) do
					local a = (g - 1) * GROUP_SIZE + 1
					local b = math.min(g * GROUP_SIZE, count)
					local info = {}
					info.text = options[a].text.."  -  "..options[b].text
					info.value = g
					info.hasArrow = 1
					UIDropDownMenu_AddButton(info, 1)
				end
				return
			end
			local g = UIDROPDOWNMENU_MENU_VALUE or 1
			first = (g - 1) * GROUP_SIZE + 1
			last = math.min(g * GROUP_SIZE, count)
		end
		for i = first, last do
			local option = options[i]
			local info = {}
			info.text = option.text
			info.value = option.value
			info.checked = option.value == selected and 1 or nil
			info.func = function()
				setting.set(this.value)
				CloseDropDownMenus()
				RefreshControls(page) -- other controls may show the same setting or depend on it
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end
	dropdown.Update = function(self)
		local current = setting.get()
		local shown = current and tostring(current) or ""
		for _, option in ipairs(Options()) do
			if option.value == current then
				shown = option.text
			end
		end
		self.selectedValue = current
		boxText:SetText(shown)
		-- there's no UIDropDownMenu_EnableDropDown in 1.12 FrameXML, so switch the button itself
		local enabled = IsEnabled(o)
		if button then
			if enabled then button:Enable() else button:Disable() end
		end
		Colorize(title, enabled, HIGHLIGHT_FONT_COLOR)
		Colorize(boxText, enabled, HIGHLIGHT_FONT_COLOR)
	end
	AddControl(page, dropdown, setting, 52)
	return dropdown
end

-- o: key/setting, label, tooltip, hasAlpha, enabledIf, indent, onSet
-- The value is a table {r, g, b} or {r, g, b, a}. With hasAlpha nil, the picker offers opacity when the
-- saved colour has a 4th value.
function PageMethods:Color(o)
	local page = self
	local setting = SettingFor(page, o)
	local indent = IndentOf(o)

	local swatch = CreateFrame("Button", NextName(), page.scrollChild)
	swatch:SetWidth(20)
	swatch:SetHeight(20)
	swatch:SetPoint("TOPLEFT", page.scrollChild, "TOPLEFT", 20 + indent, page.y - 2)
	local border = swatch:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints(swatch)
	border:SetTexture(1, 1, 1, 1)
	local inner = swatch:CreateTexture(nil, "ARTWORK")
	inner:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
	inner:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)

	local text = page.scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	text:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
	text:SetText(Label(o))
	SetTooltip(swatch, o.tooltip)

	local function Apply(r, g, b, a)
		if a then
			setting.set({r, g, b, a})
		else
			setting.set({r, g, b})
		end
		swatch:Update()
	end
	swatch:SetScript("OnClick", function()
		local c = setting.get() or {1, 1, 1}
		local hasAlpha = o.hasAlpha
		if hasAlpha == nil then hasAlpha = c[4] ~= nil end
		-- the picker calls these with no useful `this`, so they use the swatch's own upvalues
		ColorPickerFrame.func = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			Apply(r, g, b, hasAlpha and (1 - OpacitySliderFrame:GetValue()) or nil) -- the slider holds opacity, 1 - alpha
		end
		ColorPickerFrame.opacityFunc = ColorPickerFrame.func
		ColorPickerFrame.cancelFunc = function(previous)
			Apply(previous[1], previous[2], previous[3], previous[4])
		end
		ColorPickerFrame.previousValues = {c[1], c[2], c[3], hasAlpha and (c[4] or 1) or nil}
		ColorPickerFrame.hasOpacity = hasAlpha
		ColorPickerFrame.opacity = hasAlpha and (1 - (c[4] or 1)) or 0
		ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
		ColorPickerFrame:Show()
	end)
	swatch.Update = function(self)
		local c = setting.get() or {1, 1, 1}
		inner:SetTexture(c[1], c[2], c[3], 1)
		local enabled = IsEnabled(o)
		if enabled then self:Enable() else self:Disable() end
		Colorize(text, enabled, HIGHLIGHT_FONT_COLOR)
		border:SetTexture(enabled and 1 or 0.4, enabled and 1 or 0.4, enabled and 1 or 0.4, 1)
	end
	AddControl(page, swatch, setting, 26)
	return swatch
end

-- o: key/setting, label, tooltip, width, format(value) -> text, parse(text) -> value, enabledIf, indent, onSet
-- Saves on Enter or when the box loses focus; Escape puts the saved text back.
function PageMethods:EditBox(o)
	local page = self
	local setting = SettingFor(page, o)
	local indent = IndentOf(o)
	local title = page.scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", page.scrollChild, "TOPLEFT", 20 + indent, page.y - 4)
	title:SetText(Label(o))

	local box = CreateFrame("EditBox", NextName(), page.scrollChild, "InputBoxTemplate")
	box:SetWidth(o.width or 300)
	box:SetHeight(20)
	box:SetPoint("TOPLEFT", page.scrollChild, "TOPLEFT", 26 + indent, page.y - 18)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal)
	SetTooltip(box, o.tooltip)

	local function TextOf(value)
		if o.format then return o.format(value) end
		return value and tostring(value) or ""
	end
	local function Commit()
		local text = box:GetText()
		if text == TextOf(setting.get()) then return end
		local value = text
		if o.parse then value = o.parse(text) end
		if value ~= nil then
			setting.set(value)
		end
		box:SetText(TextOf(setting.get()))
	end
	box:SetScript("OnEnterPressed", function()
		Commit()
		this:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function()
		this:SetText(TextOf(setting.get()))
		this:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", function()
		this.editing = true
	end)
	box:SetScript("OnEditFocusLost", function()
		this.editing = nil
		Commit()
	end)
	box.Update = function(self)
		if not self.editing then
			self:SetText(TextOf(setting.get()))
		end
		local enabled = IsEnabled(o)
		if enabled then self:EnableMouse(true) else self:ClearFocus() self:EnableMouse(false) end
		Colorize(title, enabled, HIGHLIGHT_FONT_COLOR)
	end
	AddControl(page, box, setting, 46)
	return box
end

-- a number box with - and + buttons (Shift x10, Ctrl+Shift x100), placed at x on the current row
local function NumberBox(page, x, y, caption, setting, o)
	local minus = CreateFrame("Button", NextName(), page.scrollChild, "UIPanelButtonTemplate")
	minus:SetWidth(20)
	minus:SetHeight(20)
	minus:SetText("-")
	local box = CreateFrame("EditBox", NextName(), page.scrollChild, "InputBoxTemplate")
	box:SetWidth(50)
	box:SetHeight(20)
	box:SetAutoFocus(false) -- not SetNumeric: that refuses the minus sign
	box:SetFontObject(ChatFontNormal)
	local plus = CreateFrame("Button", NextName(), page.scrollChild, "UIPanelButtonTemplate")
	plus:SetWidth(20)
	plus:SetHeight(20)
	plus:SetText("+")
	local label = page.scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	label:SetText(caption)

	label:SetPoint("TOPLEFT", page.scrollChild, "TOPLEFT", x, y - 4)
	minus:SetPoint("LEFT", label, "RIGHT", 6, 0)
	box:SetPoint("LEFT", minus, "RIGHT", 8, 0)
	plus:SetPoint("LEFT", box, "RIGHT", 2, 0)

	local step = o.step or 1
	local function Nudge(direction)
		local amount = step
		if IsShiftKeyDown() and IsControlKeyDown() then
			amount = step * 100
		elseif IsShiftKeyDown() then
			amount = step * 10
		end
		local v = (setting.get() or 0) + direction * amount
		if o.min and v < o.min then v = o.min end
		if o.max and v > o.max then v = o.max end
		setting.set(v)
		box:SetText(v)
	end
	minus:SetScript("OnClick", function() Nudge(-1) end)
	plus:SetScript("OnClick", function() Nudge(1) end)
	local nudgeTip = "Shift: x10\nCtrl+Shift: x100"
	SetTooltip(minus, nudgeTip)
	SetTooltip(plus, nudgeTip)

	local function Commit()
		local v = tonumber(box:GetText())
		if v and v ~= setting.get() then
			if o.min and v < o.min then v = o.min end
			if o.max and v > o.max then v = o.max end
			setting.set(v)
		end
		box:SetText(setting.get() or 0)
	end
	box:SetScript("OnEnterPressed", function() Commit() this:ClearFocus() end)
	box:SetScript("OnEscapePressed", function() this:SetText(setting.get() or 0) this:ClearFocus() end)
	box:SetScript("OnEditFocusGained", function() this.editing = true end)
	box:SetScript("OnEditFocusLost", function() this.editing = nil Commit() end)

	return function(enabled) -- Update
		if not box.editing then box:SetText(setting.get() or 0) end
		if enabled then minus:Enable() plus:Enable() box:EnableMouse(true)
		else minus:Disable() plus:Disable() box:ClearFocus() box:EnableMouse(false) end
		Colorize(label, enabled, HIGHLIGHT_FONT_COLOR)
	end
end

-- o: key/setting, label, tooltip, step, min, max, enabledIf, indent, onSet
function PageMethods:Number(o)
	local page = self
	local setting = SettingFor(page, o)
	local row = CreateFrame("Frame", nil, page.scrollChild) -- holds the setting for Cancel/Defaults
	local update = NumberBox(page, 20 + IndentOf(o), page.y, Label(o), setting, o)
	row.Update = function() update(IsEnabled(o)) end
	AddControl(page, row, setting, 28)
	return row
end

-- An X and a Y number on one row. o: xKey, yKey (or xSetting, ySetting), label, step, min, max, enabledIf
function PageMethods:Position(o)
	local page = self
	local xs = o.xSetting or SettingFor(page, {key = o.xKey, label = o.label})
	local ys = o.ySetting or SettingFor(page, {key = o.yKey, label = o.label})
	-- one setting for both, so Cancel and Defaults treat the pair as one control
	local setting = {
		get = function() return {xs.get(), ys.get()} end,
		set = function(v) xs.set(v[1]) ys.set(v[2]) end,
		reset = function() xs.reset() ys.reset() end,
	}
	local indent = IndentOf(o)
	local title = page.scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", page.scrollChild, "TOPLEFT", 20 + indent, page.y - 4)
	title:SetText(Label(o))
	local updateX = NumberBox(page, 30 + indent, page.y - 20, "X", xs, o)
	local updateY = NumberBox(page, 200 + indent, page.y - 20, "Y", ys, o)
	local row = CreateFrame("Frame", nil, page.scrollChild)
	row.Update = function()
		local enabled = IsEnabled(o)
		updateX(enabled)
		updateY(enabled)
		Colorize(title, enabled, HIGHLIGHT_FONT_COLOR)
	end
	AddControl(page, row, setting, 48)
	return row
end

-- o: label, onClick, width, tooltip
function PageMethods:Button(o)
	local button = CreateFrame("Button", NextName(), self.scrollChild, "UIPanelButtonTemplate")
	button:SetWidth(o.width or 160)
	button:SetHeight(22)
	button:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 16 + IndentOf(o), self.y - 4)
	button:SetText(o.label)
	button:SetScript("OnClick", function() o.onClick() end)
	SetTooltip(button, o.tooltip)
	Advance(self, 32)
	return button
end
