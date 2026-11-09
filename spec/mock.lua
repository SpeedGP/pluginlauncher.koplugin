-- Minimal stand-ins for the KOReader modules PluginLauncher uses, faithful to
-- the behaviour it relies on, so the plugin can be tested without KOReader.
local M = { log = {} }

local function class(base)
    local c = {}
    c.__index = c
    if base then setmetatable(c, base) end
    c.extend = function(self, sub)
        sub = sub or {}
        sub.__index = sub
        return setmetatable(sub, self)
    end
    c.new = function(self, o)
        o = setmetatable(o or {}, self)
        if o._init then o:_init() end
        if o.init then o:init() end
        return o
    end
    return c
end

-- EventListener / WidgetContainer
local EventListener = class()
function EventListener:handleEvent(event)
    if self[event.handler] then
        return self[event.handler](self, unpack(event.args))
    end
end
local WidgetContainer = class(EventListener)
WidgetContainer.extend = EventListener.extend
WidgetContainer.new = EventListener.new
function WidgetContainer:propagateEvent(event)
    for _, w in ipairs(self) do
        if w:handleEvent(event) then return true end
    end
    return false
end
function WidgetContainer:handleEvent(event)
    if not self:propagateEvent(event) then
        return EventListener.handleEvent(self, event)
    end
    return true
end
function WidgetContainer:getSize()
    if self[1] then return self[1]:getSize() end
    return self.dimen or { w = 0, h = 0 }
end
function WidgetContainer:paintTo(bb, x, y)
    M.painted = (M.painted or 0) + 1
    if self[1] and self[1].paintTo then self[1]:paintTo(bb, x, y) end
end

local InputContainer = WidgetContainer:extend{}
function InputContainer:_init() self.key_events = self.key_events or {}; self.ges_events = self.ges_events or {} end

-- Geometry
local Geom = class()
function Geom:copy() return Geom:new{ x = self.x, y = self.y, w = self.w, h = self.h } end

-- Layout widgets with real-ish sizing
local VerticalGroup = WidgetContainer:extend{}
function VerticalGroup:getSize()
    local w, h = 0, 0
    for _, c in ipairs(self) do local s = c:getSize(); w = math.max(w, s.w); h = h + s.h end
    return { w = w, h = h }
end
local HorizontalGroup = WidgetContainer:extend{}
function HorizontalGroup:getSize()
    local w, h = 0, 0
    for _, c in ipairs(self) do local s = c:getSize(); h = math.max(h, s.h); w = w + s.w end
    return { w = w, h = h }
end
local VerticalSpan = WidgetContainer:extend{ width = 0 }
function VerticalSpan:getSize() assert(self.width >= 0, "negative VerticalSpan"); return { w = 0, h = self.width } end
local HorizontalSpan = WidgetContainer:extend{ width = 0 }
function HorizontalSpan:getSize() assert(self.width >= 0, "negative HorizontalSpan"); return { w = self.width, h = 0 } end
local CenterContainer = WidgetContainer:extend{}
function CenterContainer:getSize() return { w = self.dimen.w, h = self.dimen.h } end
local FrameContainer = WidgetContainer:extend{ padding = 0, bordersize = 0, margin = 0 }
function FrameContainer:getSize()
    local s = self[1]:getSize()
    local extra = 2 * (self.padding + self.bordersize + self.margin)
    return { w = self.width or (s.w + extra), h = self.height or (s.h + extra), content = s }
end
local LineWidget = WidgetContainer:extend{}
function LineWidget:getSize() return { w = self.dimen.w, h = self.dimen.h } end
local TextWidget = WidgetContainer:extend{}
function TextWidget:getSize() return { w = 10 * #self.text, h = 30 } end
function TextWidget:setText(t) self.text = t end
local TextBoxWidget = WidgetContainer:extend{}
function TextBoxWidget:getSize()
    local lines = 1
    for _ in self.text:gmatch("\n") do lines = lines + 1 end
    return { w = self.width, h = self.height or 30 * lines }
end
function TextBoxWidget:free() end
local IconWidget = WidgetContainer:extend{ name = "icon" }
function IconWidget:getSize() return { w = self.width, h = self.height } end
local GestureRange = class()

local Button = WidgetContainer:extend{ enabled = true, bordersize = 2, padding = 5, margin = 0 }
function Button:init()
    M.buttons = M.buttons or {}
    table.insert(M.buttons, self)
end
function Button:getSize()
    local extra = 2 * (self.padding + self.bordersize + self.margin)
    return { w = self.width, h = self.height + extra }
end
function Button:tap()
    if self.enabled and self.callback then self.callback() end
end
function Button:hold()
    if (self.enabled or self.allow_hold_when_disabled) and self.hold_callback then self.hold_callback() end
end

-- Event
local Event = class()
function Event:new(name, ...)
    return setmetatable({ name = name, handler = "on" .. name, args = { ... } }, self)
end

-- UIManager
local UIManager = { _window_stack = {}, _ticks = {}, dirty = {} }
function UIManager:show(w, refresh) table.insert(self._window_stack, { widget = w }); table.insert(M.log, "show " .. (w.name or "?") .. " " .. tostring(refresh)) end
function UIManager:close(w, refresh)
    for i = #self._window_stack, 1, -1 do
        if self._window_stack[i].widget == w then
            table.remove(self._window_stack, i)
            table.insert(M.log, "close " .. (w.name or "?") .. " " .. tostring(refresh))
            w:handleEvent(Event:new("CloseWidget"))
            return
        end
    end
end
function UIManager:isWidgetShown(w) for _, e in ipairs(self._window_stack) do if e.widget == w then return true end end return false end
function UIManager:top() local e = self._window_stack[#self._window_stack]; return e and e.widget end
function UIManager:nextTick(f) table.insert(self._ticks, f) end
function UIManager:scheduleIn(s, f) table.insert(M.log, "scheduleIn " .. s); table.insert(self._ticks, f) end
function UIManager:runTicks()
    local n = 0
    while #self._ticks > 0 do local f = table.remove(self._ticks, 1); f(); n = n + 1; assert(n < 100) end
end
function UIManager:setDirty(w, r, region) table.insert(self.dirty, { w = w, r = r, region = region }) end
function UIManager:widgetRepaint() end
function UIManager:forceRePaint() end
function UIManager:sendEvent(ev)
    local top = self:top()
    if top then return top:handleEvent(ev) end
end
function UIManager:broadcastEvent(ev)
    for i = #self._window_stack, 1, -1 do self._window_stack[i].widget:handleEvent(ev) end
end
function UIManager:paintAll()
    for _, e in ipairs(self._window_stack) do e.widget:paintTo({}, 0, 0) end
end

-- Dispatcher (same shape as the real one: a local settingsList upvalue)
local settingsList = {
    toggle_frontlight = { category = "none", event = "ToggleFrontlight", screen = true },
    toggle_wifi = { category = "none", event = "ToggleWifi", device = true },
    terminal = nil,
}
local Dispatcher = {}
function Dispatcher:registerAction(name, value) if settingsList[name] == nil then settingsList[name] = value end return true end
function Dispatcher:getNameFromItem(item) if settingsList[item] == nil then return "Unknown item" end return settingsList[item].title end
function Dispatcher:isActionEnabled(action)
    if action.condition == false then return false end
    return not (action.reader or action.rolling or action.paging) -- FM context
end
function Dispatcher:execute(settings)
    for k, v in pairs(settings) do
        local a = settingsList[k]
        if a and self:isActionEnabled(a) then
            table.insert(M.log, "dispatch " .. k)
            UIManager:sendEvent(Event:new(a.event))
        end
    end
end
M.settingsList = settingsList

-- Settings
local Settings = { data = {}, flushes = 0 }
function Settings:readSetting(k) return self.data[k] end
function Settings:saveSetting(k, v) self.data[k] = v end
function Settings:has(k) return self.data[k] ~= nil end
function Settings:delSetting(k) self.data[k] = nil end
function Settings:isTrue(k) return self.data[k] == true end
function Settings:isFalse(k) return self.data[k] == false end
function Settings:nilOrTrue(k) return self.data[k] == nil or self.data[k] == true end
function Settings:flipNilOrTrue(k) if self:nilOrTrue(k) then self.data[k] = false else self.data[k] = nil end end
function Settings:flipTrue(k) if self:isTrue(k) then self.data[k] = nil else self.data[k] = true end end
function Settings:makeTrue(k) self.data[k] = true end
function Settings:flush() self.flushes = self.flushes + 1 end
G_reader_settings = Settings -- luacheck: ignore

-- Device
M.fl_on = false
M.wifi_on = false
local powerd = {
    getCapacity = function() return 87 end,
    isCharging = function() return false end,
    isFrontlightOn = function() return M.fl_on end,
    toggleFrontlight = function() M.fl_on = not M.fl_on; return true end,
}
local Device = {
    screen = { getWidth = function() return 1860 end, getHeight = function() return 2480 end,
               scaleBySize = function(_, n) return math.floor(n * 1.875 + 0.5) end,
               getSize = function() return { w = 1860, h = 2480 } end },
    hasKeys = function() return false end,
    hasBattery = function() return true end,
    hasWifiToggle = function() return true end,
    hasFrontlight = function() return true end,
    canRestart = function() return true end,
    getPowerDevice = function() return powerd end,
    input = { group = { Back = {} } },
}
local NetworkMgr = {
    isWifiOn = function() return M.wifi_on end,
    isConnected = function() return M.wifi_on end,
}

local logger = {}
for _, lvl in ipairs{ "dbg", "info", "warn", "err" } do
    logger[lvl] = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
        table.insert(M.log, lvl .. ": " .. table.concat(t, " "))
    end
end

local InfoMessage = WidgetContainer:extend{ name = "infomessage" }
local ConfirmBox = WidgetContainer:extend{ name = "confirmbox" }
local MultiConfirmBox = WidgetContainer:extend{ name = "multiconfirmbox" }

local ButtonDialog = WidgetContainer:extend{ name = "buttondialog" }
local TouchMenu = WidgetContainer:extend{ name = "touchmenu" }
function TouchMenu:init() M.touchmenus = M.touchmenus or {}; table.insert(M.touchmenus, self) end

-- PluginLoader: enabled_plugins list + a local BUILTIN_PLUGINS table, like the real one.
local BUILTIN_PLUGINS = { terminal = true, statistics = true, hello = true }
local PluginLoader = { enabled_plugins = {} }
function PluginLoader:loadPlugins() return self.enabled_plugins end
function PluginLoader:_discover(name) return BUILTIN_PLUGINS[name] end
M.PluginLoader = PluginLoader

local mods = {
    ["ui/widget/buttondialog"] = ButtonDialog,
    ["ui/widget/touchmenu"] = TouchMenu,
    ["pluginloader"] = PluginLoader,
    ["ffi/blitbuffer"] = { COLOR_BLACK = 0, COLOR_WHITE = 255, COLOR_DARK_GRAY = 136 },
    ["ui/widget/button"] = Button,
    ["ui/widget/container/centercontainer"] = CenterContainer,
    ["ui/widget/confirmbox"] = ConfirmBox,
    ["ui/widget/multiconfirmbox"] = MultiConfirmBox,
    ["device"] = Device,
    ["dispatcher"] = Dispatcher,
    ["ui/event"] = Event,
    ["ui/font"] = { getFace = function(_, n, s) return { n, s } end },
    ["ui/widget/container/framecontainer"] = FrameContainer,
    ["ui/geometry"] = Geom,
    ["ui/widget/horizontalgroup"] = HorizontalGroup,
    ["ui/widget/horizontalspan"] = HorizontalSpan,
    ["ui/widget/infomessage"] = InfoMessage,
    ["ui/widget/container/inputcontainer"] = InputContainer,
    ["ui/widget/linewidget"] = LineWidget,
    ["ui/size"] = { border = { thick = 4 }, padding = { default = 9 }, radius = { window = 13 }, line = { thick = 3, medium = 2 } },
    ["ui/widget/textboxwidget"] = TextBoxWidget,
    ["ui/widget/textwidget"] = TextWidget,
    ["ui/uimanager"] = UIManager,
    ["ui/widget/verticalgroup"] = VerticalGroup,
    ["ui/widget/verticalspan"] = VerticalSpan,
    ["ui/widget/container/widgetcontainer"] = WidgetContainer,
    ["logger"] = logger,
    ["gettext"] = function(s) return s end,
    ["ui/network/manager"] = NetworkMgr,
    ["ui/widget/iconwidget"] = IconWidget,
    ["ui/gesturerange"] = GestureRange,
    ["datastorage"] = { getDataDir = function() return M.data_dir or "/nonexistent" end },
    ["libs/libkoreader-lfs"] = { attributes = function(path, what)
        local f = io.open(path, "r")
        if not f then return nil end
        f:close()
        return what == "mode" and "file" or {}
    end },
}
for k, v in pairs(mods) do package.loaded[k] = v end

M.UIManager, M.Dispatcher, M.Event, M.WidgetContainer, M.Settings = UIManager, Dispatcher, Event, WidgetContainer, Settings

-- A fake FileManager: modules are children, like registerModule() does.
function M.newFileManager(plugins)
    local fm = WidgetContainer:new{ name = "filemanager", active_widgets = {} }
    local menu = { registered = {} }
    function menu:registerToMainMenu(p) table.insert(self.registered, p) end
    fm.menu = menu
    local devicelistener = WidgetContainer:new{}
    function devicelistener:onToggleFrontlight() M.fl_on = not M.fl_on; table.insert(M.log, "DeviceListener:onToggleFrontlight"); return true end
    function devicelistener:onExit() table.insert(M.log, "DeviceListener:onExit"); return true end
    function devicelistener:onRestart() table.insert(M.log, "DeviceListener:onRestart"); return true end
    table.insert(fm, devicelistener)
    local netlistener = WidgetContainer:new{}
    function netlistener:onToggleWifi() M.wifi_on = not M.wifi_on; table.insert(M.log, "NetworkListener:onToggleWifi"); return true end
    table.insert(fm, netlistener)
    for name, p in pairs(plugins or {}) do
        table.insert(PluginLoader.enabled_plugins, { name = name, fullname = p.fullname, path = "/plugins/" .. name .. ".koplugin" })
        p.ui = fm
        fm[name] = p
        table.insert(fm, p)
    end
    return fm
end

function M.reset()
    M.touchmenus = {}
    PluginLoader.enabled_plugins = {}
    M.log = {}
    M.buttons = {}
    M.painted = 0
    UIManager._window_stack, UIManager._ticks, UIManager.dirty = {}, {}, {}
end

return M
