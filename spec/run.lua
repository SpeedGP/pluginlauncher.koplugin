--[[
Tests for PluginLauncher, run without KOReader against stand-ins for the
KOReader modules it uses (spec/mock.lua).

    luajit spec/run.lua        (from the plugin folder)
--]]

local SPEC = (arg and arg[0] or "spec/run.lua"):match("^(.*)/[^/]*$") or "."
local PLUGIN = SPEC .. "/.."
local TMP = os.tmpname()
os.remove(TMP)
os.execute("mkdir -p " .. TMP)
package.path = SPEC .. "/?.lua;" .. package.path
local M = require("mock")
local UIManager, Dispatcher = M.UIManager, M.Dispatcher

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1 else fail = fail + 1; print("  FAIL: " .. msg) end
end
local function logHas(pat)
    for _, l in ipairs(M.log) do if l:find(pat, 1, true) then return true end end
    return false
end

-- A copy of the plugin, optionally with a different config.lua.
local n = 0
local function pluginDir(config_src)
    n = n + 1
    local dir = TMP .. "/p" .. n
    os.execute(("mkdir -p %s && cp %s/*.lua %s && cp -r %s/icons %s/"):format(dir, PLUGIN, dir, PLUGIN, dir))
    if config_src then
        local f = assert(io.open(dir .. "/config.lua", "w")); f:write(config_src); f:close()
    end
    return dir
end

local function loadPlugin(dir)
    local Launcher = dofile(dir .. "/main.lua")
    Launcher.path = dir
    return Launcher
end

local sandbox_mt = { __call = function(t, mod, ...) return t.f(mod, ...) end }

-- Fake installed plugins covering the menu shapes seen in the wild.
local function fakePlugins()
    local P = {}
    -- KOAssistant: third-party, lazy sub-menu (must not be built during scan)
    local koa = M.WidgetContainer:new{ fullname = "KOAssistant", chats = 0, submenu_builds = 0 }
    koa.onKOAssistantGeneralChat = setmetatable({ f = function(self)
        self.chats = self.chats + 1; return true end }, sandbox_mt)
    function koa:addToMainMenu(mi)
        mi.koassistant = { text = "KOAssistant", sorting_hint = "tools", sub_item_table_func = function()
            self.submenu_builds = self.submenu_builds + 1
            return { { text = "General chat" }, { text = "Settings" } }
        end }
    end
    Dispatcher:registerAction("koassistant_general_chat", { category = "none", event = "KOAssistantGeneralChat", general = true })
    Dispatcher:registerAction("koassistant_quick_actions", { category = "none", event = "KOAssistantQuickActions", reader = true })
    P.koassistant = koa
    -- Terminal: built-in, plain callback entry that uses the touchmenu instance
    local term = M.WidgetContainer:new{ fullname = "Terminal emulator", opened = 0 }
    function term:addToMainMenu(mi)
        mi.terminal = { text = "Terminal emulator", callback = function(tm) tm:closeMenu(); self.opened = self.opened + 1 end }
    end
    P.terminal = term
    -- Statistics: built-in, static sub menu
    local stats = M.WidgetContainer:new{ fullname = "Reading statistics" }
    function stats:addToMainMenu(mi) mi.statistics = { text = "Reading statistics", sub_item_table = { { text = "Progress" } } } end
    P.statistics = stats
    -- Zen UI: third-party, several entries -> one tile opening a menu of all of them
    local zen = M.WidgetContainer:new{ fullname = "Zen UI" }
    function zen:addToMainMenu(mi)
        mi.zen_ui = { text = "Zen UI settings", sub_item_table = {} }
        mi.zen_ui_quick = { text_func = function() return "Zen quick settings" end, callback = function() end }
    end
    P.zen_ui = zen
    -- hello: built-in, addToMainMenu throws
    local hello = M.WidgetContainer:new{ fullname = "Hello" }
    function hello:addToMainMenu() error("boom") end
    P.hello = hello
    -- a plugin with no menu at all
    P.nomenu = M.WidgetContainer:new{ fullname = "No menu" }
    -- a game whose entry is disabled right now
    local chess = M.WidgetContainer:new{ fullname = "Chess" }
    function chess:addToMainMenu(mi) mi.chess = { text = "Chess", enabled_func = function() return false end, callback = function() end } end
    P.chess = chess
    -- an unknown plugin: gets the fallback icon
    local misc = M.WidgetContainer:new{ fullname = "Widgetizer" }
    function misc:addToMainMenu(mi) mi.widgetizer = { text = "Widgetizer", callback = function() end } end
    P.widgetizer = misc
    return P
end

local current_fm
local function boot(dir, plugins, extra)
    M.reset()
    local Launcher = loadPlugin(dir)
    local fm = M.newFileManager(plugins)
    for name, p in pairs(extra or {}) do fm[name] = p; table.insert(fm, p) end
    table.insert(M.PluginLoader.enabled_plugins, { name = "pluginlauncher", path = dir })
    local inst = Launcher:new{ ui = fm }
    fm.pluginlauncher = inst
    table.insert(fm, inst)
    UIManager:show(fm)
    UIManager:runTicks()
    UIManager:paintAll()
    UIManager:runTicks()
    current_fm = fm
    return fm, inst, Launcher
end

local function launcher()
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "pluginlauncher_widget" then return w end
    end
end
local function launcherShown()
    local top = UIManager:top()
    return top and top.name == "pluginlauncher_widget"
end
-- Re-render and return every tile on screen, in layout order.
local function tiles()
    local out = {}
    local function walk(x)
        if type(x) ~= "table" then return end
        if x.onTapTile and x.text then table.insert(out, x) return end
        for _, c in ipairs(x) do walk(c) end
    end
    local w = launcher()
    w:buildLayout()
    walk(w[1])
    return out
end
local function find(label, exact)
    for _, t in ipairs(tiles()) do
        if (exact and t.text == label) or (not exact and t.text:sub(1, #label) == label) then return t end
    end
end
local function labels()
    local t = {}
    for _, tile in ipairs(tiles()) do t[#t + 1] = tile.text:gsub("\n", " ") end
    return table.concat(t, " | ")
end
local function tap(label, exact) local t = find(label, exact); assert(t, "no tile " .. label); t:onTapTile() end
local function hold(label, exact) local t = find(label, exact); assert(t, "no tile " .. label); t:onHoldTile() end
local function iconOf(label) local t = find(label, true); return t and t.icon_file and t.icon_file:match("([^/]+)%.svg$") end
local function contentHeight(w)
    local frame = w[1]
    return frame[1]:getSize().h + 2 * frame.padding
end
local function hasDivider(w)
    local function walk(x)
        if type(x) ~= "table" then return false end
        if x.background == 136 then return true end
        for _, c in ipairs(x) do if walk(c) then return true end end
        return false
    end
    return walk(w[1])
end
local function choose(text)
    for _, row in ipairs(UIManager:top().buttons or {}) do
        if row[1].text == text then row[1].callback(); return true end
    end
    return false
end

-----------------------------------------------------------------------------
print("1. Clean KOReader, only PluginLauncher")
M.Settings.data = {}
local fm = boot(pluginDir())
check(launcherShown(), "autostarts on top of the file manager")
check(logHas("show pluginlauncher_widget full"), "opens with one full refresh")
check(find("Chat\n(not installed)") and not find("Chat\n(not installed)").enabled, "KOAssistant shortcuts greyed when not installed")
for _, label in ipairs{ "Light", "Wi-Fi", "Files", "Exit", "Apps", "Built-in" } do
    check(find(label) ~= nil, "tile present: " .. label)
end
check(contentHeight(launcher()) == 2480, "layout fills the screen exactly")
check(not M.Settings:has("pluginlauncher_autostart_in_progress"), "boot guard cleared after first paint")
check(M.settingsList.pluginlauncher_show and M.settingsList.pluginlauncher_show.event == "ShowPluginLauncher", "Dispatcher action registered")

-----------------------------------------------------------------------------
print("2. Plugin library")
local P = fakePlugins()
fm = boot(pluginDir(), P)
local w = launcher()
local apps = labels()
check(apps:find("KOAssistant", 1, true) and apps:find("Zen UI", 1, true), "third-party plugins on Apps: " .. apps)
check(not apps:find("Terminal", 1, true) and not apps:find("statistics", 1, true), "built-ins not on Apps")
check(not apps:find("PluginLauncher |", 1, true), "doesn't list itself")
check(not apps:find("Hello", 1, true) and not apps:find("No menu", 1, true), "broken / menu-less plugins skipped")
check(logHas("couldn't read the menu of plugin hello"), "broken plugin logged")
check(P.koassistant.submenu_builds == 0, "KOAssistant's sub-menu not built while scanning")
check(hasDivider(w), "divider between shortcuts and plugins")
check(find("Chess\n(not available here)") and not find("Chess\n(not available here)").enabled, "disabled menu entry greyed")
local t_apps = tiles()
-- layout order (system row at the top by default): system (4), tabs (2), shortcuts (4), plugins A-Z
check(t_apps[1].text == "Light" and t_apps[4].text == "Exit" and t_apps[5].text == "Apps"
      and t_apps[7].text == "Chat" and t_apps[11].text:find("^Chess") and t_apps[12].text == "KOAssistant"
      and t_apps[13].text == "Widgetizer" and t_apps[14].text == "Zen UI", "controls, tabs, shortcuts, then plugins A-Z: " .. apps)
tap("KOAssistant", true)
local tm = M.touchmenus[#M.touchmenus]
check(tm and tm.tab_item_table[1][1].text == "General chat" and P.koassistant.submenu_builds == 1, "tap opens plugin menu in TouchMenu")
check(tm and tm.tab_item_table[1].icon ~= nil, "TouchMenu tab has an icon")
tm.close_callback()
check(launcherShown(), "closing the plugin menu returns to the launcher")
tap("Zen UI", true)
tm = M.touchmenus[#M.touchmenus]
check(tm and #tm.tab_item_table[1] == 2, "multi-entry plugin opens a menu with all its entries")
tm.close_callback()
tap("Built-in")
check(w.tab == "builtin", "switched to Built-in tab")
check(find("Terminal emulator") and find("Reading statistics"), "built-ins listed: " .. labels())
tap("Terminal emulator")
check(P.terminal.opened == 1, "plain-callback plugin runs directly (with a touchmenu stub)")
check(launcherShown(), "launcher stays underneath")
check(not find("Apps", true).selected and find("Built-in").selected, "selected tab highlighted")

-----------------------------------------------------------------------------
print("3. Icons")
fm = boot(pluginDir(), fakePlugins())
check(iconOf("KOAssistant") == "robot-outline", "known plugin icon: " .. tostring(iconOf("KOAssistant")))
check(iconOf("Zen UI") == "meditation", "Zen UI icon")
check(iconOf("Chat") == "chat-outline", "shortcut icon from config.lua")
check(find("Chess\n(not available here)").icon_file:find("chess%-knight"), "keyword icon for a game")
check(iconOf("Widgetizer") == "puzzle-outline", "unknown plugin gets the puzzle piece")
for _, label in ipairs{ "Light", "Wi-Fi", "Files", "Exit" } do
    check(find(label).icon_file ~= nil and find(label).style == "row", "system tile has an icon: " .. label)
end
check(find("Apps", true).icon_file == nil and find("Apps", true).style == "pill", "tabs are text pills")
-- every icon the code can ask for is bundled
local src = io.open(PLUGIN .. "/main.lua"):read("*a") .. io.open(PLUGIN .. "/config.lua"):read("*a")
local missing = {}
for name in src:gmatch('"([%w%-]+%-outline)"') do
    if not io.open(PLUGIN .. "/icons/" .. name .. ".svg") then missing[#missing + 1] = name end
end
for name in src:gmatch('icon%(?"([%w%-]+)"') do
    if not io.open(PLUGIN .. "/icons/" .. name .. ".svg") then missing[#missing + 1] = name end
end
for _, list in ipairs{ "PLUGIN_ICONS", "KEYWORD_ICONS" } do
    local body = src:match(list .. " = (%b{})")
    for name in body:gmatch('"([%w%-]+)"') do
        if name:find("%-") and not io.open(PLUGIN .. "/icons/" .. name .. ".svg") then missing[#missing + 1] = name end
    end
end
check(#missing == 0, "all referenced icons bundled; missing: " .. table.concat(missing, ", "))
-- config overrides and the user icon folder
fm = boot(pluginDir([[return { icons = { koassistant = "sync", widgetizer = "icons/console.svg", zen_ui = "no-such-icon" } }]]), fakePlugins())
check(iconOf("KOAssistant") == "sync", "config icons override")
check(iconOf("Widgetizer") == "console", "icon given as a path in the plugin folder")
check(iconOf("Zen UI") == "meditation", "missing configured icon falls back to the default")
M.data_dir = TMP .. "/data"
os.execute("mkdir -p " .. M.data_dir .. "/icons && cp " .. PLUGIN .. "/icons/power.svg " .. M.data_dir .. "/icons/robot-outline.svg")
fm = boot(pluginDir(), fakePlugins())
check(find("KOAssistant", true).icon_file:find(M.data_dir, 1, true), "koreader/icons/ overrides a bundled icon")
M.data_dir = nil

-----------------------------------------------------------------------------
print("4. Long-press to move and hide")
fm = boot(pluginDir(), fakePlugins())
w = launcher()
tap("Built-in")
hold("Terminal emulator")
local dlg = UIManager:top()
check(dlg.name == "buttondialog" and dlg.title:find("terminal.koplugin", 1, true), "long-press shows options with folder name")
check(choose("Move to Apps"), "Move to Apps offered")
check(launcherShown(), "dialog closed")
check(not find("Terminal emulator"), "Terminal left Built-in")
check(M.Settings.data.pluginlauncher_placement["plugin:terminal"] == "apps", "placement saved")
tap("Apps", true)
check(find("Terminal emulator") ~= nil, "Terminal now on Apps")
check(find("Hidden") == nil, "no Hidden tab while nothing is hidden")
hold("Zen UI", true); choose("Hide")
check(find("Zen UI", true) == nil, "Zen UI hidden from Apps")
check(find("Hidden (1)") ~= nil, "Hidden tab appears with count")
tap("Hidden (1)")
check(find("Zen UI", true) ~= nil, "hidden item listed on Hidden tab")
hold("Zen UI", true); choose("Move to Apps")
check(w.tab == "apps" and find("Hidden") == nil, "unhiding the last item closes the Hidden tab")
hold("AI Settings"); choose("Hide")
check(find("AI Settings") == nil, "greyed shortcut can be hidden")
fm = boot(pluginDir(), fakePlugins())
check(find("Terminal emulator") ~= nil and find("AI Settings") == nil, "placements persist across restarts")
M.Settings.data = {}

-----------------------------------------------------------------------------
print("5. place = {} in config.lua")
fm = boot(pluginDir([[return { place = { terminal = "apps", koassistant = "hidden", ["Chat History"] = "builtin", bad = "nowhere" },
  shortcuts = { { label = "Chat History", dispatcher = "koassistant_chat_history" } } }]]), fakePlugins())
local a = labels()
check(a:find("Terminal", 1, true) and not a:find("| KOAssistant |", 1, true), "config placement applied: " .. a)
check(logHas("ignoring place entry bad"), "invalid place entry ignored with a warning")
tap("Built-in")
check(find("Chat History") ~= nil, "shortcut placed on Built-in by label")
tap("Hidden")
check(find("KOAssistant", true) ~= nil, "koassistant hidden by config")
hold("KOAssistant", true); choose("Move to Apps")
check(launcher().tab == "apps" and find("KOAssistant", true) ~= nil, "long-press overrides config.lua")
M.Settings.data = {}

-----------------------------------------------------------------------------
print("6. Shortcuts")
P = fakePlugins()
fm = boot(pluginDir(), P)
tap("Chat", true)
check(P.koassistant.chats == 1, "Chat reaches KOAssistant through Dispatcher + forwarding")
check(launcherShown() and launcher().forward_events == false, "launcher stays; forwarding off again")
fm = boot(pluginDir([[return { shortcuts = {
    { label = "QA", dispatcher = "koassistant_quick_actions" },
    { label = "Direct", plugin = "koassistant", method = "onKOAssistantGeneralChat" },
    { label = "Fallback", dispatcher = "nope", plugin = "koassistant", method = "onKOAssistantGeneralChat" },
    { label = "Ghost", plugin = "ghost", method = "onGo" },
    { label = "Boom", callback = function() error("kaboom") end },
} }]]), P)
check(find("QA\n(not available here)") ~= nil, "reader-only action marked not available here")
local before = P.koassistant.chats
tap("Direct", true); tap("Fallback", true)
check(P.koassistant.chats == before + 2, "plugin+method and fallback work with sandboxed handlers")
check(find("Ghost\n(not installed)") ~= nil, "missing plugin greyed")
local ok = pcall(function() tap("Boom", true) end)
check(ok and UIManager:top().name == "infomessage", "throwing shortcut shows an error, doesn't crash")
fm = boot(pluginDir([[return { buttons = { { label = "OldName", event = "Foo" } } }]]))
check(find("OldName", true) ~= nil, "'buttons' still accepted as the old name for 'shortcuts'")

-----------------------------------------------------------------------------
print("7. Broken config.lua")
for _, src in ipairs{ "return { shortcuts = { { label = 'x' dispatcher = 'y' } }", "error('boom')", "return 42" } do
    fm = boot(pluginDir(src), fakePlugins())
    local l = labels()
    check(launcherShown() and l:find("KOAssistant", 1, true) and not l:find("Chat History", 1, true),
          "plugins still listed, shortcuts missing: " .. src)
end
check(logHas("err: PluginLauncher"), "error logged")
os.execute("rm " .. TMP .. "/p" .. n .. "/config.lua")
fm = boot(TMP .. "/p" .. n, fakePlugins())
check(launcherShown() and find("KOAssistant", true), "missing config.lua: still opens")
fm = boot(pluginDir("return { shortcuts = { 'junk', { label = 'NoAction' }, { label = 'ok', event = 'Foo' } } }"))
check(find("ok", true) ~= nil and find("NoAction") == nil, "invalid entries skipped")
fm = boot(pluginDir("return { show_plugins = false, title = 'My Scribe', shortcuts = { { label = 'only', event = 'Foo' } } }"), fakePlugins())
check(find("only", true) and not find("KOAssistant", true), "show_plugins = false lists shortcuts only")
local function hasText(x, text)
    if type(x) ~= "table" then return false end
    if x.text == text then return true end
    for _, c in ipairs(x) do if hasText(c, text) then return true end end
    return false
end
check(hasText(launcher()[1], "My Scribe"), "custom title shown")

-----------------------------------------------------------------------------
print("8. System row and header")
M.fl_on, M.wifi_on = false, false
fm = boot(pluginDir())
w = launcher()
check(w.status_sig:find("87%", 1, true) and w.status_sig:find("wifi:off") and w.status_sig:find("light:off"), "status: " .. w.status_sig)
tap("Light"); UIManager:runTicks()
check(M.fl_on and w.status_sig:find("light:on"), "frontlight toggled, header updated")
local d = UIManager.dirty[#UIManager.dirty]
check(d and d.r == "ui" and d.region and d.region.h < 250, "header refresh is a small non-flashing region")
tap("Wi-Fi")
w:handleEvent(M.Event:new("NetworkConnected"))
check(M.wifi_on and w.status_sig:find("wifi:connected"), "Wi-Fi toggled, header updated")
local nd = #UIManager.dirty
w:refreshStatus()
check(#UIManager.dirty == nd, "no refresh when nothing changed")
tap("Files")
check(not launcherShown() and UIManager:top() == fm, "Files reveals the file manager")
fm = boot(pluginDir())
tap("Exit")
check(UIManager:top().name == "multiconfirmbox", "exit asks first")
UIManager:top().choice2_callback(); UIManager:runTicks()
check(logHas("DeviceListener:onRestart") and not launcher(), "restart closes the launcher first")

-----------------------------------------------------------------------------
print("9. Autostart, gesture action, crash guard, reshow")
M.Settings.data = { pluginlauncher_autostart = false }
fm = boot(pluginDir())
check(not launcherShown(), "autostart off -> file manager")
Dispatcher:execute({ pluginlauncher_show = true })
check(launcherShown(), "Show PluginLauncher action opens it")
current_fm.pluginlauncher:onShowPluginLauncher()
local count = 0
for _, e in ipairs(UIManager._window_stack) do if e.widget.name == "pluginlauncher_widget" then count = count + 1 end end
check(count == 1, "never two launchers")
M.Settings.data = {}
M.reset(); local L9 = loadPlugin(pluginDir()); local fm9 = M.newFileManager()
table.insert(fm9, L9:new{ ui = fm9 }); UIManager:show(fm9); UIManager:runTicks()
check(M.Settings:isTrue("pluginlauncher_autostart_in_progress"), "guard set before first paint")
fm = boot(pluginDir())
check(not launcherShown() and UIManager:top().name == "infomessage", "boot after a crash skips autostart once")
fm = boot(pluginDir())
check(launcherShown(), "following boot autostarts again")
M.Settings.data = { pluginlauncher_reshow_on_filemanager = true }
local dir = pluginDir()
M.reset()
local L = loadPlugin(dir)
local fm1 = M.newFileManager(); table.insert(fm1, L:new{ ui = fm1 }); UIManager:show(fm1); UIManager:runTicks(); UIManager:paintAll(); UIManager:runTicks()
UIManager:close(fm1)
check(#UIManager._window_stack == 0, "launcher closes with its file manager")
local fm2 = M.newFileManager(); table.insert(fm2, L:new{ ui = fm2 }); UIManager:show(fm2); UIManager:runTicks()
check(launcherShown() and launcher().ui == fm2, "reshown after closing a book when enabled")
M.Settings.data = {}

-----------------------------------------------------------------------------
print("10. Upgrading from the old Launcher plugin")
M.Settings.data = { launcher_autostart = false, launcher_placement = { ["plugin:terminal"] = "apps" }, launcher_autostart_in_progress = true }
fm = boot(pluginDir(), fakePlugins())
check(M.Settings.data.pluginlauncher_autostart == false and M.Settings.data.launcher_autostart == nil, "autostart setting carried over")
check(M.Settings.data.pluginlauncher_placement["plugin:terminal"] == "apps", "moved/hidden tiles carried over")
check(M.Settings.data.launcher_autostart_in_progress == nil, "old crash guard dropped")
M.Settings.data = { launcher_placement = { x = "apps" } }
local old = M.WidgetContainer:new{}
function old:showLauncher() end
fm = boot(pluginDir(), fakePlugins(), { launcher = old })
check(M.Settings.data.launcher_placement ~= nil, "old settings untouched while the old plugin is installed")
local warned = false
for _, e in ipairs(UIManager._window_stack) do
    if e.widget.name == "infomessage" and e.widget.text:find("launcher.koplugin", 1, true) then warned = true end
end
check(warned, "warns that the old plugin is still installed")
M.Settings.data = {}

-----------------------------------------------------------------------------
print("11. Layout: every tab and page fills the screen; many plugins paginate")
local function manyPlugins(count)
    local t = {}
    for i = 1, count do
        local name = ("plug%02d"):format(i)
        local p = M.WidgetContainer:new{ fullname = name }
        function p:addToMainMenu(mi) mi[name] = { text = ("Plugin %02d"):format(i), callback = function() end } end
        t[name] = p
    end
    return t
end
fm = boot(pluginDir(), manyPlugins(40))
w = launcher()
check(find("Next") and find("Next").enabled, "pager shown for 40 plugins")
local seen, pages = {}, 0
repeat
    pages = pages + 1
    for _, t in ipairs(tiles()) do if t.text:find("^Plugin") then seen[t.text] = true end end
    check(contentHeight(w) == 2480, "page " .. pages .. " height " .. contentHeight(w))
    local nxt = find("Next")
    if nxt.enabled then nxt:onTapTile() end
until not nxt.enabled or pages > 10
local total = 0; for _ in pairs(seen) do total = total + 1 end
check(total == 40, "every plugin reachable across pages (" .. total .. " over " .. pages .. " pages)")
local bad = 0
for cols = 1, 6 do
    for count = 0, 30, 3 do
        for _, err in ipairs{ false, true } do
            fm = boot(pluginDir(("return { columns = %d %s }"):format(cols, err and ", shortcuts = 5" or "")), manyPlugins(count))
            w = launcher()
            for _, tab in ipairs{ "apps", "builtin" } do
                w.tab = tab
                for page = 1, 4 do
                    w.page = page
                    w:buildLayout()
                    local hh = contentHeight(w)
                    if hh ~= 2480 then
                        bad = bad + 1
                        if bad < 5 then print(("    cols=%d n=%d tab=%s page=%d h=%d"):format(cols, count, tab, page, hh)) end
                    end
                end
            end
        end
    end
end
check(bad == 0, "layout sweep: " .. bad .. " bad layouts")

-----------------------------------------------------------------------------
print("12. Names, icons from names, and where the device controls go")
local function simplePlugin(name, text)
    local p = M.WidgetContainer:new{ fullname = text }
    function p:addToMainMenu(mi) mi[name] = { text = text, callback = function() end } end
    return p
end
fm = boot(pluginDir(), {
    webbrowser = simplePlugin("webbrowser", "Web Browser"),
    storefront = simplePlugin("storefront", "Storefront"),
    backuptool = simplePlugin("backuptool", "Restore backups"),
    inkaway = simplePlugin("inkaway", "Ink Away…"),
    dots = simplePlugin("dots", "Dots..."),
    longname = simplePlugin("longname", "Extraordinarily Long Plugin Name Here"),
})
check(iconOf("Web Browser") == "web", "browser gets the globe: " .. tostring(iconOf("Web Browser")))
check(iconOf("Storefront") == "storefront-outline", "store gets a storefront: " .. tostring(iconOf("Storefront")))
check(iconOf("Restore backups") == "puzzle-outline", "'restore' doesn't match 'store': " .. tostring(iconOf("Restore backups")))
check(find("Ink Away", true) ~= nil and find("Dots", true) ~= nil, "trailing … and ... dropped from menu names: " .. labels())
local long = find("Extraordinarily Long Plugin Name Here", true)
local function partsOf(tile)
    local group = tile[1][1][1] -- frame > center > vertical group
    return group[1], group[3] -- icon, label
end
local icon, label = partsOf(long)
local _, short_label = partsOf(find("Storefront", true))
local short_icon = partsOf(find("Storefront", true))
label:getSize()
check((label.lines or 0) >= 2 and label.height == nil, "long name wraps onto more lines without being cut off")
check(icon.width < short_icon.width, ("icon shrinks to make room (%d < %d)"):format(icon.width, short_icon.width))
local inner_h = long.height - 2 * (4 + math.floor(6 * 1.875 + 0.5))
check(icon.height + math.floor(6 * 1.875 + 0.5) + label:getSize().h <= inner_h, "icon and two-line name fit inside the tile")
short_label:getSize()
check(short_label.lines == 1, "short names stay on one line")
-- system row position
fm = boot(pluginDir([[return { system_row = "bottom" }]]))
local tl = tiles()
check(tl[1].text == "Apps" and tl[#tl].text == "Exit" and tl[#tl - 3].text == "Light", "system_row = \"bottom\" puts the controls last")
check(contentHeight(launcher()) == 2480, "bottom layout fills the screen")
fm = boot(pluginDir([[return { system_row = "sideways" }]]))
check(tiles()[1].text == "Light" and logHas("system_row must be"), "invalid system_row warns and keeps the top")
bad = 0
for _, pos in ipairs{ "top", "bottom" } do
    for cols = 1, 6 do
        for count = 0, 30, 5 do
            fm = boot(pluginDir(("return { columns = %d, system_row = %q }"):format(cols, pos)), manyPlugins(count))
            if contentHeight(launcher()) ~= 2480 then bad = bad + 1 end
        end
    end
end
check(bad == 0, "both positions fill the screen at every size: " .. bad .. " bad")

print(("\n%d passed, %d failed"):format(pass, fail))
os.execute("rm -rf " .. TMP)
os.exit(fail == 0 and 0 or 1)
