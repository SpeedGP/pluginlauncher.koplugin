--[[--
PluginLauncher: a home screen for your plugins and apps instead of your books.

Every installed plugin that has a menu entry gets an icon tile, sorted onto
two tabs:

  Apps      your shortcuts from config.lua, then plugins you installed
  Built-in  plugins that ship with KOReader

Long-press any tile to move it to the other tab or hide it. Hidden tiles go to
a third tab, which only appears when something is hidden.

A row of device controls (Light, Wi-Fi, Files, Exit) sits under the header,
or at the bottom if config.lua says so. PluginLauncher opens
when KOReader starts, and the "Show PluginLauncher" Dispatcher action reopens
it (bind it to a gesture in Gesture manager).

It's drawn on top of the file manager and doesn't patch any KOReader
component, so it coexists with UI plugins such as Zen UI.

@module koplugin.PluginLauncher
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

local PLUGIN_NAME = "pluginlauncher"
local SETTING_AUTOSTART = "pluginlauncher_autostart"            -- default: on
local SETTING_RESHOW = "pluginlauncher_reshow_on_filemanager"   -- default: off
local SETTING_BOOT_GUARD = "pluginlauncher_autostart_in_progress" -- crash-loop breaker
local SETTING_PLACEMENT = "pluginlauncher_placement"            -- { [item id] = tab }

-- Settings saved by this plugin's earlier version, when it was called "Launcher".
local OLD_SETTINGS = {
    launcher_autostart = SETTING_AUTOSTART,
    launcher_reshow_on_filemanager = SETTING_RESHOW,
    launcher_placement = SETTING_PLACEMENT,
    launcher_autostart_in_progress = false, -- just drop it
}

local TABS = { "apps", "builtin", "hidden" }
local VALID_TAB = { apps = true, builtin = true, hidden = true }

local COLOR_BLACK = Blitbuffer.COLOR_BLACK
local COLOR_WHITE = Blitbuffer.COLOR_WHITE
local COLOR_GRAY = Blitbuffer.COLOR_DARK_GRAY

-- Module-level state. PluginLoader loads main.lua once per KOReader run, so
-- this survives the FileManager being torn down and recreated.
local state = {
    autostart_done = false, -- autostart happens at most once per run
    widget = nil,           -- the LauncherWidget currently shown, if any
    warned_old = false,     -- told the user about the old "Launcher" plugin
}

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------

-- Icons for plugins, by plugin folder name (without ".koplugin").
local PLUGIN_ICONS = {
    koassistant = "robot-outline",
    zen_ui = "meditation",
    simpleui = "view-dashboard-outline",
    archiveviewer = "folder-zip-outline",
    autodim = "brightness-6",
    autostandby = "sleep",
    autosuspend = "power-sleep",
    autoturn = "book-arrow-right-outline",
    autowarmth = "weather-sunset",
    batterystat = "battery-charging-outline",
    bookshortcuts = "star-outline",
    calibre = "bookshelf",
    cloudstorage = "cloud-outline",
    coverbrowser = "view-grid-outline",
    coverimage = "image-outline",
    docsettingtweak = "file-cog-outline",
    exporter = "export-variant",
    externalkeyboard = "keyboard-variant",
    gestures = "gesture-tap",
    hello = "hand-wave-outline",
    hotkeys = "keyboard-outline",
    httpinspector = "web",
    japanese = "translate",
    keepalive = "coffee-outline",
    kosync = "sync",
    movetoarchive = "archive-arrow-down-outline",
    newsdownloader = "newspaper-variant-outline",
    opds = "book-open-page-variant-outline",
    perceptionexpander = "eye-outline",
    profiles = "account-cog-outline",
    qrclipboard = "qrcode",
    readtimer = "timer-outline",
    SSH = "lan-connect",
    statistics = "chart-box-outline",
    systemstat = "chip",
    terminal = "console",
    texteditor = "file-document-edit-outline",
    timesync = "clock-check-outline",
    vocabbuilder = "alphabetical-variant",
    wallabag = "bookmark-box-multiple-outline",
}

-- For plugins not listed above: the first keyword that starts a word in the
-- plugin's name or label wins ("Web Browser" -> web, but "restore" isn't "store").
local KEYWORD_ICONS = {
    { "chess", "chess-knight" },
    { "sudoku", "grid" },
    { "solitaire", "cards-playing-outline" },
    { "card", "cards-playing-outline" },
    { "mine", "bomb" },
    { "2048", "numeric-2-box-outline" },
    { "snake", "snake" },
    { "dice", "dice-multiple-outline" },
    { "puzzle", "puzzle-outline" },
    { "crossword", "puzzle-outline" },
    { "quiz", "brain" },
    { "trivia", "brain" },
    { "game", "gamepad-variant-outline" },
    { "browser", "web" },
    { "internet", "web" },
    { "web", "web" },
    { "store", "storefront-outline" },
    { "shop", "storefront-outline" },
    { "market", "storefront-outline" },
    { "mail", "email-outline" },
    { "map", "map-outline" },
    { "wiki", "wikipedia" },
    { "photo", "image-multiple-outline" },
    { "gallery", "image-multiple-outline" },
    { "image", "image-outline" },
    { "podcast", "podcast" },
    { "download", "download-outline" },
    { "claude", "creation" },
    { "assistant", "robot-outline" },
    { "chat", "chat-outline" },
    { "history", "history" },
    { "setting", "cog-outline" },
    { "calc", "calculator-variant-outline" },
    { "calendar", "calendar-month-outline" },
    { "weather", "weather-partly-cloudy" },
    { "rss", "rss" },
    { "feed", "rss" },
    { "news", "newspaper-variant-outline" },
    { "music", "music-note-outline" },
    { "journal", "notebook-outline" },
    { "diary", "notebook-outline" },
    { "note", "note-text-outline" },
    { "draw", "palette-outline" },
    { "paint", "palette-outline" },
    { "sketch", "palette-outline" },
    { "todo", "format-list-checks" },
    { "task", "format-list-checks" },
    { "dictionar", "text-box-search-outline" },
    { "search", "magnify" },
    { "sync", "sync" },
    { "terminal", "console" },
    { "timer", "timer-outline" },
    { "clock", "clock-check-outline" },
    { "translat", "translate" },
}
local FALLBACK_ICON = "puzzle-outline"

-- name -> file path, or false if not found. Shared by all launcher instances.
local icon_paths = {}

local function fileExists(path)
    return lfs.attributes(path, "mode") == "file"
end

-- Find an icon by name or path. Looks in koreader/icons/ first (so you can
-- override any icon with your own), then this plugin's icons/ folder, then
-- KOReader's own icons. Returns a file path or nil.
local function findIcon(name, plugin_dir)
    if type(name) ~= "string" or name == "" then return nil end
    local key = plugin_dir .. "\0" .. name
    if icon_paths[key] ~= nil then return icon_paths[key] or nil end

    local found
    if name:find("/", 1, true) then
        local path = name:sub(1, 1) == "/" and name or (plugin_dir .. "/" .. name)
        if fileExists(path) then found = path end
    else
        local dirs = { DataStorage:getDataDir() .. "/icons", plugin_dir .. "/icons", "resources/icons/mdlight" }
        for _i, dir in ipairs(dirs) do
            for _j, ext in ipairs({ ".svg", ".png" }) do
                if fileExists(dir .. "/" .. name .. ext) then
                    found = dir .. "/" .. name .. ext
                    break
                end
            end
            if found then break end
        end
    end
    icon_paths[key] = found or false
    return found
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Run fn(...) and log any error with a traceback. Returns ok, result.
local function safeCall(what, fn, ...)
    local ok, res = xpcall(fn, debug.traceback, ...)
    if not ok then
        logger.err("PluginLauncher:", what, "failed:", res)
    end
    return ok, res
end

local function showError(text)
    UIManager:show(InfoMessage:new{
        text = text,
        icon = "notice-warning",
    })
end

-- KOReader wraps plugin `on*` handlers in callable tables (HandlerSandbox),
-- so a plain type() == "function" check isn't enough.
local function isCallable(v)
    if type(v) == "function" then return true end
    if type(v) == "table" then
        local mt = getmetatable(v)
        return mt ~= nil and mt.__call ~= nil
    end
    return false
end

-- Find a local table that one of `module`'s functions closes over.
local function findUpvalue(module, wanted)
    local found
    pcall(function()
        for _k, fn in pairs(module) do
            if type(fn) == "function" then
                local i = 1
                while true do
                    local name, value = debug.getupvalue(fn, i)
                    if name == nil then break end
                    if name == wanted and type(value) == "table" then
                        found = value
                        return
                    end
                    i = i + 1
                end
            end
        end
    end)
    return found
end

-- Dispatcher keeps its action table in a local `settingsList`. Reading it lets
-- us tell "not registered" apart from "registered but unavailable here" (e.g.
-- actions that need an open book). If KOReader ever renames it, we fall back
-- to getNameFromItem(), which only detects "not registered".
local dispatcher_actions -- nil: not looked up yet; false: lookup failed
local function getDispatcherActions()
    if dispatcher_actions == nil then
        dispatcher_actions = findUpvalue({ Dispatcher.registerAction }, "settingsList") or false
        if not dispatcher_actions then
            logger.info("PluginLauncher: Dispatcher action list not reachable; using fallback lookup")
        end
    end
    return dispatcher_actions or nil
end

-- Returns "ok", "missing" (no such action) or "unavailable" (exists, but its
-- condition is false or it needs a different context, e.g. an open book).
local function dispatcherActionStatus(id)
    local actions = getDispatcherActions()
    if actions then
        local action = actions[id]
        if action == nil then return "missing" end
        local ok, enabled = pcall(Dispatcher.isActionEnabled, Dispatcher, action)
        if ok and not enabled then return "unavailable" end
        return "ok"
    end
    local ok, name = pcall(Dispatcher.getNameFromItem, Dispatcher, id)
    if ok and name == _("Unknown item") then return "missing" end
    return "ok"
end

-- Plugins that ship with KOReader. The authoritative list is a local table in
-- pluginloader.lua; this copy (plus a few older names) is used if that can't
-- be read, and merged with it otherwise.
local KNOWN_BUILTIN = {
    archiveviewer = true, autodim = true, autofrontlight = true, autostandby = true,
    autosuspend = true, autoturn = true, autowarmth = true, backgroundrunner = true,
    batterystat = true, bookshortcuts = true, calibre = true, cloudstorage = true,
    coverbrowser = true, coverimage = true, docsettingtweak = true, evernote = true,
    exporter = true, externalkeyboard = true, gestures = true, goodreads = true,
    hello = true, hotkeys = true, httpinspector = true, japanese = true,
    keepalive = true, kobolight = true, kosync = true, movetoarchive = true,
    newsdownloader = true, opds = true, perceptionexpander = true, profiles = true,
    qrclipboard = true, readtimer = true, send2ebook = true, SSH = true,
    statistics = true, storagestat = true, systemstat = true, terminal = true,
    texteditor = true, timesync = true, vocabbuilder = true, wallabag = true,
    zsync = true,
}
local builtin_set
local function getBuiltinSet()
    if not builtin_set then
        builtin_set = {}
        for k in pairs(KNOWN_BUILTIN) do builtin_set[k] = true end
        local ok, PluginLoader = pcall(require, "pluginloader")
        local list = ok and findUpvalue(PluginLoader, "BUILTIN_PLUGINS")
        if list then
            for k, v in pairs(list) do
                if v then builtin_set[k] = true end
            end
        end
    end
    return builtin_set
end

local function getPluginDir(plugin)
    if plugin and type(plugin.path) == "string" then
        return plugin.path
    end
    local source = debug.getinfo(1, "S").source or ""
    return source:match("^@(.*)/[^/]*$") or "plugins/pluginlauncher.koplugin"
end

local function defaultConfig()
    return {
        title = _("PluginLauncher"),
        columns = 3,
        font_size = 20,
        startup_delay = 0,
        show_plugins = true,
        system_row = "top",
        place = {},
        icons = {},
        shortcuts = {},
    }
end

-- Load and validate config.lua. Never throws.
-- Returns config, error_message. config is always usable; when the file is
-- broken it just has no shortcuts.
local function loadConfig(dir)
    local config = defaultConfig()
    local path = dir .. "/config.lua"

    local chunk, load_err = loadfile(path)
    if not chunk then
        logger.err("PluginLauncher: could not load", path, ":", load_err)
        return config, _("config.lua could not be loaded, so your shortcuts are missing. Check it for typos; the details are in crash.log.")
    end
    local ok, user = pcall(chunk)
    if not ok then
        logger.err("PluginLauncher: error while running", path, ":", user)
        return config, _("config.lua raised an error, so your shortcuts are missing. The details are in crash.log.")
    end
    if type(user) ~= "table" then
        logger.err("PluginLauncher:", path, "must return a table, got", type(user))
        return config, _("config.lua must return a table, so your shortcuts are missing.")
    end

    if type(user.title) == "string" then
        config.title = user.title
    end
    local columns = tonumber(user.columns)
    if columns and columns >= 1 and columns <= 6 then
        config.columns = math.floor(columns)
    end
    local font_size = tonumber(user.font_size)
    if font_size and font_size >= 10 and font_size <= 60 then
        config.font_size = font_size
    end
    local delay = tonumber(user.startup_delay)
    if delay and delay >= 0 and delay <= 30 then
        config.startup_delay = delay
    end
    if user.show_plugins == false then
        config.show_plugins = false
    end
    if user.system_row == "top" or user.system_row == "bottom" then
        config.system_row = user.system_row
    elseif user.system_row ~= nil then
        logger.warn("PluginLauncher: system_row must be \"top\" or \"bottom\"")
    end
    if type(user.place) == "table" then
        for k, v in pairs(user.place) do
            if type(k) == "string" and VALID_TAB[v] then
                config.place[k] = v
            else
                logger.warn("PluginLauncher: ignoring place entry", tostring(k), "=", tostring(v))
            end
        end
    end
    if type(user.icons) == "table" then
        for k, v in pairs(user.icons) do
            if type(k) == "string" and type(v) == "string" then
                config.icons[k] = v
            end
        end
    end

    local shortcuts = user.shortcuts
    if shortcuts == nil then shortcuts = user.buttons end -- older name
    if shortcuts ~= nil and type(shortcuts) ~= "table" then
        logger.warn("PluginLauncher:", path, ": 'shortcuts' must be a list")
        return config
    end
    for i, b in ipairs(shortcuts or {}) do
        if type(b) ~= "table" or type(b.label) ~= "string" or b.label == "" then
            logger.warn("PluginLauncher: skipping shortcut", i, "in config.lua: it needs a label")
        elseif type(b.dispatcher) ~= "string"
                and not (type(b.plugin) == "string" and type(b.method) == "string")
                and type(b.event) ~= "string"
                and type(b.callback) ~= "function" then
            logger.warn("PluginLauncher: skipping shortcut", i, b.label, ": no dispatcher, plugin+method, event or callback")
        else
            table.insert(config.shortcuts, b)
        end
    end
    return config
end

local function clearBootGuard()
    if G_reader_settings:has(SETTING_BOOT_GUARD) then
        G_reader_settings:delSetting(SETTING_BOOT_GUARD)
        G_reader_settings:flush()
    end
end

---------------------------------------------------------------------------
-- Plugin discovery: one tile per plugin with a main-menu entry
---------------------------------------------------------------------------

-- Passed to menu callbacks run outside a menu. They sometimes call
-- touchmenu_instance:closeMenu() or :updateItems(); any method is a no-op.
local TOUCHMENU_STUB = setmetatable({ item_table = {} }, {
    __index = function() return function() end end,
})

-- Show menu items in KOReader's own TouchMenu, exactly as in Tools.
local function showMenuItems(items)
    local TouchMenu = require("ui/widget/touchmenu")
    local container = CenterContainer:new{
        ignore = "height",
        dimen = Screen:getSize(),
    }
    local tab = { icon = "appbar.tools" }
    for i, item in ipairs(items) do tab[i] = item end
    container[1] = TouchMenu:new{
        width = Screen:getWidth(),
        tab_item_table = { tab },
        show_parent = container,
        close_callback = function()
            UIManager:close(container)
        end,
    }
    UIManager:show(container)
end

local function menuText(entry)
    local text = entry.text
    if type(entry.text_func) == "function" then
        local ok, t = pcall(entry.text_func)
        if ok then text = t end
    end
    if type(text) ~= "string" then return nil end
    -- Menu entries that open a dialog end in "…" by KOReader convention;
    -- that reads as "cut off" on a tile, so drop it.
    text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s*…$", ""):gsub("%s*%.%.%.$", "")
    return text ~= "" and text or nil
end

-- Turn a plugin's main-menu entries into a launcher item, or nil if there's
-- nothing to launch. Sub-menus are only built when tapped: some plugins do
-- real work (loading settings, initialising) in sub_item_table_func.
local function makePluginItem(name, module, entries, is_builtin)
    if #entries == 0 then return nil end
    local label, run, enabled = nil, nil, true

    if #entries == 1 then
        local e = entries[1]
        label = menuText(e)
        if e.sub_item_table or e.sub_item_table_func then
            run = function()
                local sub = e.sub_item_table
                if not sub and type(e.sub_item_table_func) == "function" then
                    sub = e.sub_item_table_func()
                end
                if type(sub) ~= "table" then error("plugin menu returned no items") end
                showMenuItems(sub)
            end
        elseif e.checked ~= nil or e.checked_func ~= nil then
            -- A toggle: show it in a menu so its state is visible.
            run = function() showMenuItems({ e }) end
        elseif type(e.callback) == "function" then
            run = function() e.callback(TOUCHMENU_STUB) end
        end
        if type(e.enabled_func) == "function" then
            local ok, en = pcall(e.enabled_func)
            if ok and not en then enabled = false end
        elseif e.enabled == false then
            enabled = false
        end
    else
        run = function() showMenuItems(entries) end
    end

    if not run then return nil end
    label = label or (type(module.fullname) == "string" and module.fullname) or name
    return {
        id = "plugin:" .. name,
        plugin_name = name,
        label = label,
        kind = "plugin",
        default_place = is_builtin and "builtin" or "apps",
        enabled = enabled,
        suffix = not enabled and _("(not available here)") or nil,
        run = run,
    }
end

-- True for this plugin and its predecessor, so neither lists itself.
local function isLauncherPlugin(name, instance)
    if name == PLUGIN_NAME then return true end
    return name == "launcher" and type(instance) == "table" and isCallable(instance.showLauncher)
end

local function scanPlugins(ui)
    local items = {}
    local ok, PluginLoader = pcall(require, "pluginloader")
    if not ok then return items end
    local ok_list, modules = pcall(PluginLoader.loadPlugins, PluginLoader)
    if not ok_list or type(modules) ~= "table" then return items end
    local builtin = getBuiltinSet()

    for _i, module in ipairs(modules) do
        local name = module.name
        local instance = type(name) == "string" and ui[name]
        if type(instance) == "table" and not isLauncherPlugin(name, instance)
                and isCallable(instance.addToMainMenu) then
            local probe = {}
            local ok_menu, err = pcall(instance.addToMainMenu, instance, probe)
            if ok_menu then
                local keys = {}
                for key, entry in pairs(probe) do
                    if type(entry) == "table" and (entry.text or entry.text_func) then
                        table.insert(keys, tostring(key))
                    end
                end
                table.sort(keys)
                local entries = {}
                for _j, key in ipairs(keys) do table.insert(entries, probe[key]) end
                local ok_item, item = pcall(makePluginItem, name, module, entries, builtin[name])
                if ok_item and item then
                    table.insert(items, item)
                end
            else
                logger.warn("PluginLauncher: couldn't read the menu of plugin", name, ":", err)
            end
        end
    end

    table.sort(items, function(a, b) return a.label:lower() < b.label:lower() end)
    return items
end

---------------------------------------------------------------------------
-- Tile: a rounded, tappable card with an icon and a label
---------------------------------------------------------------------------

--[[
Styles:
  "tile"   icon above a label (the grid)
  "row"    icon left of a label (the system row)
  "pill"   label only (tabs, pager)
  "plain"  label only, no border, not tappable (pager page number)
--]]
local Tile = InputContainer:extend{
    width = nil,
    height = nil,
    style = "tile",
    text = "",
    icon_file = nil,
    font_size = 20,
    enabled = true,
    selected = false,
    callback = nil,
    hold_callback = nil,
    show_parent = nil,
}

function Tile:init()
    local plain = self.style == "plain"
    local border = plain and 0 or Size.border.thick
    local padding = Screen:scaleBySize(6)
    local inner_w = self.width - 2 * (border + padding)
    local inner_h = self.height - 2 * (border + padding)
    local fg = self.enabled and COLOR_BLACK or COLOR_GRAY
    local face = Font:getFace("cfont", self.font_size)

    local content
    if self.style == "tile" and self.icon_file then
        local gap = Screen:scaleBySize(6)
        local icon_size = math.floor(math.min(inner_h * 0.5, inner_w * 0.45))
        local label = TextBoxWidget:new{
            text = self.text,
            face = face,
            bold = true,
            width = inner_w,
            alignment = "center",
            fgcolor = fg,
        }
        local label_h = label:getSize().h
        -- A long name wraps: shrink the icon to make room before cutting it off.
        if label_h + gap + icon_size > inner_h then
            icon_size = math.max(math.floor(inner_h * 0.28), inner_h - gap - label_h)
        end
        local text_h = inner_h - icon_size - gap
        if label_h > text_h then
            label:free()
            label = TextBoxWidget:new{
                text = self.text,
                face = face,
                bold = true,
                width = inner_w,
                height = text_h,
                height_overflow_show_ellipsis = true,
                alignment = "center",
                fgcolor = fg,
            }
        end
        content = VerticalGroup:new{
            align = "center",
            IconWidget:new{
                file = self.icon_file,
                width = icon_size,
                height = icon_size,
                dim = not self.enabled,
            },
            VerticalSpan:new{ width = gap },
            label,
        }
    elseif self.style == "row" and self.icon_file then
        local icon_size = math.floor(inner_h * 0.6)
        local gap = Screen:scaleBySize(8)
        content = HorizontalGroup:new{
            align = "center",
            IconWidget:new{
                file = self.icon_file,
                width = icon_size,
                height = icon_size,
                dim = not self.enabled,
            },
            HorizontalSpan:new{ width = gap },
            TextWidget:new{
                text = self.text,
                face = face,
                bold = true,
                fgcolor = fg,
                max_width = math.max(1, inner_w - icon_size - gap),
            },
        }
    else
        content = TextWidget:new{
            text = self.text,
            face = face,
            bold = not plain,
            fgcolor = fg,
            max_width = inner_w,
        }
    end

    self[1] = FrameContainer:new{
        bordersize = border,
        color = self.enabled and COLOR_BLACK or COLOR_GRAY,
        radius = plain and 0 or Screen:scaleBySize(14),
        padding = padding,
        margin = 0,
        background = COLOR_WHITE,
        invert = self.selected,
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = inner_h },
            content,
        },
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }

    if not plain then
        self.ges_events = {
            TapTile = { GestureRange:new{ ges = "tap", range = self.dimen } },
            HoldTile = { GestureRange:new{ ges = "hold", range = self.dimen } },
        }
    end
end

-- Briefly invert the tile, like KOReader's buttons, then run the callback.
function Tile:onTapTile()
    if not (self.enabled and self.callback) then return true end
    local frame = self[1]
    if not G_reader_settings:isFalse("flash_ui") and frame.dimen then
        local was = frame.invert
        frame.invert = not was
        UIManager:widgetRepaint(frame, frame.dimen.x, frame.dimen.y)
        UIManager:setDirty(nil, "fast", frame.dimen)
        UIManager:forceRePaint()
        frame.invert = was
        UIManager:widgetRepaint(frame, frame.dimen.x, frame.dimen.y)
        UIManager:setDirty(nil, "ui", frame.dimen)
    end
    self.callback()
    return true
end

function Tile:onHoldTile()
    if self.hold_callback then
        self.hold_callback()
    end
    return true
end

---------------------------------------------------------------------------
-- The full-screen launcher widget
---------------------------------------------------------------------------

local LauncherWidget = InputContainer:extend{
    name = "pluginlauncher_widget",
    covers_fullscreen = true, -- lets UIManager skip repainting what's under us
    ui = nil,                 -- FileManager or ReaderUI that opened us
    plugin_dir = nil,
    tab = "apps",
    page = 1,
    boot_guard = false,       -- true when opened by autostart
}

function LauncherWidget:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self.config, self.config_error = loadConfig(self.plugin_dir)
    self:collectItems()
    local ok = safeCall("building the layout", self.buildLayout, self)
    if not ok then
        -- Last resort: system row only.
        self.items = {}
        self.config_error = _("PluginLauncher hit an error. The details are in crash.log.")
        self:buildLayout()
    end
end

-- Build self.items: shortcuts from config.lua, then discovered plugins.
function LauncherWidget:collectItems()
    self.items = {}
    local seen = {}
    for _i, b in ipairs(self.config.shortcuts) do
        local ok, item = safeCall("resolving shortcut " .. tostring(b.label), self.resolveShortcut, self, b)
        if ok and item and not seen[item.id] then
            seen[item.id] = true
            table.insert(self.items, item)
        end
    end
    if self.config.show_plugins then
        local ok, plugins = safeCall("scanning plugins", scanPlugins, self.ui)
        if ok then
            for _i, item in ipairs(plugins) do table.insert(self.items, item) end
        end
    end
    for _i, item in ipairs(self.items) do
        item.icon_file = self:iconFor(item)
    end
end

function LauncherWidget:icon(name)
    return findIcon(name, self.plugin_dir)
end

-- Pick an icon: config.lua, then our map, then a keyword, then a puzzle piece.
function LauncherWidget:iconFor(item)
    local key = item.plugin_name or item.label
    local candidates = {}
    local function add(name)
        if type(name) == "string" then table.insert(candidates, name) end
    end
    add(item.icon)
    add(self.config.icons[key])
    add(item.plugin_name and PLUGIN_ICONS[item.plugin_name])
    local haystack = ((item.plugin_name or "") .. " " .. item.label):lower()
    for _i, pair in ipairs(KEYWORD_ICONS) do
        if haystack:find("%f[%w]" .. pair[1]) then
            add(pair[2])
            break
        end
    end
    add(FALLBACK_ICON)
    for _i, name in ipairs(candidates) do
        local file = self:icon(name)
        if file then return file end
    end
end

-- Dispatcher:execute() delivers actions with UIManager:sendEvent(), which only
-- reaches the topmost window: us. While running an action, pass anything we
-- don't handle ourselves to the FileManager/ReaderUI underneath, where the
-- plugins and device listeners live. Touch input is never forwarded.
function LauncherWidget:handleEvent(event)
    if InputContainer.handleEvent(self, event) then
        return true
    end
    if self.forward_events and self.ui then
        return self.ui:handleEvent(event)
    end
end

function LauncherWidget:paintTo(bb, x, y)
    local ok = safeCall("painting", InputContainer.paintTo, self, bb, x, y)
    if not ok then
        UIManager:nextTick(function()
            UIManager:close(self, "full")
            showError(_("PluginLauncher couldn't be drawn and was closed. The details are in crash.log."))
        end)
        return
    end
    if self.boot_guard then
        self.boot_guard = false
        UIManager:nextTick(clearBootGuard)
    end
end

---- Placement (which tab an item is on) --------------------------------------

function LauncherWidget:placementOf(item)
    local saved = G_reader_settings:readSetting(SETTING_PLACEMENT)
    if type(saved) == "table" and VALID_TAB[saved[item.id]] then
        return saved[item.id]
    end
    local from_config = self.config.place[item.plugin_name or item.label]
    if from_config then return from_config end
    return item.default_place
end

function LauncherWidget:setPlacement(item, tab)
    local saved = G_reader_settings:readSetting(SETTING_PLACEMENT)
    if type(saved) ~= "table" then saved = {} end
    saved[item.id] = tab
    G_reader_settings:saveSetting(SETTING_PLACEMENT, saved)
    self:rebuild()
end

function LauncherWidget:itemsOn(tab)
    local shortcuts, plugins = {}, {}
    for _i, item in ipairs(self.items) do
        if self:placementOf(item) == tab then
            table.insert(item.kind == "shortcut" and shortcuts or plugins, item)
        end
    end
    return shortcuts, plugins
end

function LauncherWidget:showItemOptions(item)
    local ButtonDialog = require("ui/widget/buttondialog")
    local current = self:placementOf(item)
    local dialog
    local function choice(text, tab)
        return {{
            text = text,
            callback = function()
                UIManager:close(dialog)
                self:setPlacement(item, tab)
            end,
        }}
    end
    local buttons = {}
    if current ~= "apps" then table.insert(buttons, choice(_("Move to Apps"), "apps")) end
    if current ~= "builtin" then table.insert(buttons, choice(_("Move to Built-in"), "builtin")) end
    if current ~= "hidden" then table.insert(buttons, choice(_("Hide"), "hidden")) end
    table.insert(buttons, {{
        text = _("Cancel"),
        callback = function() UIManager:close(dialog) end,
    }})
    local title = item.label
    if item.plugin_name then
        title = title .. "\n(" .. item.plugin_name .. ".koplugin)"
    end
    dialog = ButtonDialog:new{
        title = title,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(dialog)
end

---- Status (top right) -------------------------------------------------------

-- Everything the status area shows, as plain values.
function LauncherWidget:getStatus()
    local status = {}
    local twelve = G_reader_settings:isTrue("twelve_hour_clock")
    status.time = os.date(twelve and "%I:%M %p" or "%H:%M")
    if twelve then status.time = status.time:gsub("^0", "") end

    pcall(function()
        if Device:hasBattery() then
            local powerd = Device:getPowerDevice()
            status.battery = powerd:getCapacity()
            status.charging = powerd:isCharging() and true or false
        end
    end)
    pcall(function()
        if Device:hasWifiToggle() then
            local NetworkMgr = require("ui/network/manager")
            if not NetworkMgr:isWifiOn() then
                status.wifi = "off"
            elseif NetworkMgr:isConnected() then
                status.wifi = "connected"
            else
                status.wifi = "on"
            end
        end
    end)
    pcall(function()
        if Device:hasFrontlight() then
            status.light = Device:getPowerDevice():isFrontlightOn() and "on" or "off"
        end
    end)
    return status
end

local function statusSignature(s)
    return table.concat({
        s.time or "",
        s.battery and (s.battery .. "%") or "",
        s.charging and "charging" or "",
        "wifi:" .. (s.wifi or "-"),
        "light:" .. (s.light or "-"),
    }, "|")
end

function LauncherWidget:makeStatus(status, text_h)
    local face = Font:getFace("cfont", 18)
    local icon_size = text_h
    local space = Screen:scaleBySize(14)
    local group = HorizontalGroup:new{ align = "center" }
    local function add(widget)
        if #group > 0 then table.insert(group, HorizontalSpan:new{ width = space }) end
        table.insert(group, widget)
    end
    local function icon(name)
        local file = self:icon(name)
        return file and IconWidget:new{ file = file, width = icon_size, height = icon_size } or nil
    end

    if status.wifi then
        local w = icon(status.wifi == "off" and "wifi-off"
            or status.wifi == "connected" and "wifi" or "wifi-strength-alert-outline")
        if w then add(w) end
    end
    if status.light then
        local w = icon(status.light == "on" and "lightbulb-on-outline" or "lightbulb-off-outline")
        if w then add(w) end
    end
    if status.battery then
        local name
        if status.charging then
            name = "battery-charging"
        else
            local level = math.floor((tonumber(status.battery) or 0) / 20 + 0.5) * 20
            name = level >= 100 and "battery" or level <= 0 and "battery-outline" or ("battery-" .. level)
        end
        local battery = HorizontalGroup:new{ align = "center" }
        local w = icon(name)
        if w then table.insert(battery, w) end
        table.insert(battery, TextWidget:new{ text = status.battery .. "%", face = face })
        add(battery)
    end
    add(TextWidget:new{ text = status.time, face = face, bold = true })
    return group
end

function LauncherWidget:makeHeader(width)
    local status = self:getStatus()
    self.status_sig = statusSignature(status)
    local title = TextWidget:new{
        text = self.config.title,
        face = Font:getFace("cfont", 28),
        bold = true,
        max_width = math.floor(width * 0.55),
    }
    local text_h = TextWidget:new{ text = "0", face = Font:getFace("cfont", 18) }:getSize().h
    local right = self:makeStatus(status, text_h)
    local filler = math.max(0, width - title:getSize().w - right:getSize().w)
    return HorizontalGroup:new{
        align = "center",
        title,
        HorizontalSpan:new{ width = filler },
        right,
    }
end

-- Update just the header, with a non-flashing refresh of its own area.
-- Called on events (resume, Wi-Fi, frontlight, charging), never on a timer.
function LauncherWidget:refreshStatus()
    if not self.header_slot then return end
    if statusSignature(self:getStatus()) == self.status_sig then return end
    self.header_slot[1] = self:makeHeader(self.header_region.w)
    UIManager:setDirty(self, "ui", self.header_region)
end

---- Layout -------------------------------------------------------------------

function LauncherWidget:rebuild()
    safeCall("rebuilding", self.buildLayout, self)
    UIManager:setDirty(self, "ui")
end

function LauncherWidget:buildLayout()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local margin = Screen:scaleBySize(18)
    local gap = Screen:scaleBySize(10)
    local inner_w = sw - 2 * margin
    local inner_h = sh - 2 * margin
    local font_size = self.config.font_size

    -- Header: title on the left, status icons and clock on the right.
    local header = self:makeHeader(inner_w)
    local header_h = header:getSize().h + 2 * Screen:scaleBySize(8)
    self.header_region = Geom:new{ x = margin, y = margin, w = inner_w, h = header_h }
    self.header_slot = CenterContainer:new{
        dimen = Geom:new{ w = inner_w, h = header_h },
        header,
    }

    local line_h = Size.line.thick
    local function separator()
        return LineWidget:new{
            dimen = Geom:new{ w = inner_w, h = line_h },
            background = COLOR_BLACK,
        }
    end

    local tab_h = Screen:scaleBySize(50)
    local tabs = self:makeTabs(inner_w, tab_h, gap)

    local sys_h = Screen:scaleBySize(70)
    local system_row = self:makeTileRow(self:getSystemItems(), 4, inner_w, sys_h, gap, "row", math.max(14, font_size - 2))

    -- Both arrangements use the same pieces, so the grid gets the same height.
    local grid_h = inner_h - header_h - line_h - gap - tab_h - gap - gap - line_h - gap - sys_h
    local grid = self:makeGrid(inner_w, grid_h, gap, font_size)

    local content = VerticalGroup:new{ align = "center" }
    local function add(widget) table.insert(content, widget) end
    local function space() add(VerticalSpan:new{ width = gap }) end
    add(self.header_slot)
    add(separator())
    space()
    if self.config.system_row == "top" then
        -- Default: the device controls sit under the header, away from the
        -- bottom edge where a resting palm or pen can tap them by accident.
        add(system_row)
        space()
        add(separator())
        space()
        add(tabs)
        space()
        add(grid)
    else
        add(tabs)
        space()
        add(grid)
        space()
        add(separator())
        space()
        add(system_row)
    end

    self[1] = FrameContainer:new{
        width = sw,
        height = sh,
        padding = margin,
        bordersize = 0,
        margin = 0,
        background = COLOR_WHITE,
        content,
    }
end

function LauncherWidget:makeTabs(width, height, gap)
    local s_b, p_b = self:itemsOn("builtin")
    local s_h, p_h = self:itemsOn("hidden")
    local n_builtin, n_hidden = #s_b + #p_b, #s_h + #p_h
    if self.tab == "hidden" and n_hidden == 0 then self.tab = "apps" end

    local labels = {
        apps = _("Apps"),
        builtin = n_builtin > 0 and string.format("%s (%d)", _("Built-in"), n_builtin) or _("Built-in"),
        hidden = string.format("%s (%d)", _("Hidden"), n_hidden),
    }
    local items = {}
    for _i, tab in ipairs(TABS) do
        if tab ~= "hidden" or n_hidden > 0 then
            table.insert(items, {
                text = labels[tab],
                selected = self.tab == tab,
                callback = function() self:switchTab(tab) end,
            })
        end
    end
    return self:makeTileRow(items, #items, width, height, gap, "pill", 18)
end

function LauncherWidget:switchTab(tab)
    if self.tab == tab then return end
    self.tab = tab
    self.page = 1
    self:rebuild()
end

-- Rows for the current tab: shortcuts, a thin divider, then plugins.
function LauncherWidget:tabRows(width, cols)
    local shortcuts, plugins = self:itemsOn(self.tab)
    local rows = {}
    local function message(text)
        table.insert(rows, {
            kind = "message",
            widget = TextBoxWidget:new{
                text = text,
                face = Font:getFace("infofont", 20),
                width = math.floor(width * 0.85),
                alignment = "center",
            },
        })
    end
    local function addTiles(list)
        for i = 1, #list, cols do
            local row = { kind = "tiles", items = {} }
            for c = 0, cols - 1 do row.items[c + 1] = list[i + c] end
            table.insert(rows, row)
        end
    end

    if self.tab == "apps" and self.config_error then
        message(self.config_error)
    end
    addTiles(shortcuts)
    if #shortcuts > 0 and #plugins > 0 then
        table.insert(rows, { kind = "divider" })
    end
    addTiles(plugins)

    if #shortcuts + #plugins == 0 then
        if self.tab == "apps" then
            message(_("Nothing here yet. Install plugins, add shortcuts to config.lua, or long-press a tile on Built-in to move it here."))
        elseif self.tab == "builtin" then
            message(_("No built-in plugins to show."))
        end
    elseif self.tab == "apps" then
        -- Discreet hint, only while nothing has been customised.
        local saved = G_reader_settings:readSetting(SETTING_PLACEMENT)
        if type(saved) ~= "table" or next(saved) == nil then
            table.insert(rows, { kind = "hint" })
        end
    end
    return rows
end

-- Split rows into pages that fit `area_h`. Dividers never start or end a page.
local function paginate(rows, heights, area_h, gap)
    local pages, cur, used = {}, {}, 0
    for i, row in ipairs(rows) do
        local h = heights[i]
        local add = (#cur > 0 and gap or 0) + h
        if #cur > 0 and used + add > area_h then
            table.insert(pages, cur)
            cur, used, add = {}, 0, h
        end
        if not (row.kind == "divider" and #cur == 0) then
            table.insert(cur, i)
            used = used + add
        end
    end
    if #cur > 0 then table.insert(pages, cur) end
    for _i, page in ipairs(pages) do
        while #page > 0 and rows[page[#page]].kind == "divider" do table.remove(page) end
    end
    return pages
end

-- The tile grid for the current tab, paginated if needed.
-- Always returns a widget exactly `height` tall.
function LauncherWidget:makeGrid(width, height, gap, font_size)
    local cols = self.config.columns
    local rows = self:tabRows(width, cols)
    local tile_w = math.floor((width - (cols - 1) * gap) / cols)
    -- Tiles are roughly square-ish when wide, never shorter than a fingertip.
    local min_row_h = Screen:scaleBySize(100)
    local max_row_h = math.max(min_row_h, math.min(Screen:scaleBySize(190), tile_w))
    local divider_h = Screen:scaleBySize(14)
    local hint_h = Screen:scaleBySize(28)
    local pager_h = Screen:scaleBySize(50)

    local function fixedHeight(row)
        if row.kind == "message" then return row.widget:getSize().h end
        if row.kind == "divider" then return divider_h end
        if row.kind == "hint" then return hint_h end
    end

    -- Try one page with rows as tall as fit (up to max_row_h).
    local n_tiles, fixed = 0, 0
    for _i, row in ipairs(rows) do
        if row.kind == "tiles" then n_tiles = n_tiles + 1 else fixed = fixed + fixedHeight(row) end
    end
    fixed = fixed + gap * math.max(0, #rows - 1)
    local row_h = n_tiles > 0 and math.min(max_row_h, math.floor((height - fixed) / n_tiles)) or 0

    local heights, pages, area_h = {}, nil, height
    if n_tiles == 0 or row_h >= min_row_h then
        local all = {}
        for i = 1, #rows do all[i] = i end
        pages = { all }
    else
        row_h = min_row_h
        area_h = height - pager_h - gap
        -- The hint only belongs at the end of a single page.
        if rows[#rows].kind == "hint" then table.remove(rows) end
    end
    for i, row in ipairs(rows) do
        heights[i] = row.kind == "tiles" and row_h or fixedHeight(row)
    end
    pages = pages or paginate(rows, heights, area_h, gap)
    self.page = math.max(1, math.min(self.page, #pages))

    local group = VerticalGroup:new{ align = "center" }
    local used = 0
    for n, i in ipairs(pages[self.page] or {}) do
        if n > 1 then
            table.insert(group, VerticalSpan:new{ width = gap })
            used = used + gap
        end
        table.insert(group, self:makeRowWidget(rows[i], width, heights[i], gap, cols, font_size))
        used = used + heights[i]
    end
    if #pages > 1 then
        table.insert(group, VerticalSpan:new{ width = math.max(0, area_h - used + gap) })
        table.insert(group, self:makePager(width, pager_h, gap, #pages))
    else
        table.insert(group, VerticalSpan:new{ width = math.max(0, height - used) })
    end
    return group
end

function LauncherWidget:makeRowWidget(row, width, height, gap, cols, font_size)
    if row.kind == "tiles" then
        local items = {}
        for c = 1, cols do
            local item = row.items[c]
            if item then items[c] = self:displayItem(item) end
        end
        return self:makeTileRow(items, cols, width, height, gap, "tile", font_size)
    end
    local inner
    if row.kind == "message" then
        inner = row.widget
    elseif row.kind == "divider" then
        inner = LineWidget:new{
            dimen = Geom:new{ w = math.floor(width * 0.6), h = Size.line.medium },
            background = COLOR_GRAY,
        }
    else -- hint
        inner = TextWidget:new{
            text = _("Long-press a tile to move or hide it."),
            face = Font:getFace("infofont", 16),
            fgcolor = COLOR_GRAY,
            max_width = width,
        }
    end
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        inner,
    }
end

-- Item (shortcut or plugin) -> tile description.
function LauncherWidget:displayItem(item)
    local text = item.label
    if item.suffix then text = text .. "\n" .. item.suffix end
    return {
        text = text,
        icon_file = item.icon_file,
        enabled = item.enabled,
        callback = function() self:runItem(item) end,
        hold_callback = function() self:showItemOptions(item) end,
    }
end

function LauncherWidget:runItem(item)
    if not item.enabled or not item.run then return end
    if item.close then
        self:onClose()
    end
    local ok = safeCall("running '" .. item.label .. "'", item.run)
    if not ok then
        showError(_("That tile's action failed. The details are in crash.log."))
    end
end

function LauncherWidget:makePager(width, height, gap, pages)
    local items = {
        {
            text = "‹ " .. _("Previous"),
            enabled = self.page > 1,
            callback = function() self:goToPage(self.page - 1) end,
        },
        {
            text = string.format(_("%d of %d"), self.page, pages),
            plain = true,
        },
        {
            text = _("Next") .. " ›",
            enabled = self.page < pages,
            callback = function() self:goToPage(self.page + 1) end,
        },
    }
    return self:makeTileRow(items, 3, width, height, gap, "pill", 18)
end

function LauncherWidget:goToPage(page)
    self.page = page
    self:rebuild()
end

-- One row of `cols` equal-width tiles. Missing items leave a blank slot.
function LauncherWidget:makeTileRow(items, cols, width, height, gap, style, font_size)
    local tile_w = math.floor((width - (cols - 1) * gap) / cols)
    local row = HorizontalGroup:new{ align = "center" }
    for c = 1, cols do
        if c > 1 then
            table.insert(row, HorizontalSpan:new{ width = gap })
        end
        local item = items[c]
        if item then
            table.insert(row, self:makeTile(item, tile_w, height, item.plain and "plain" or style, font_size))
        else
            table.insert(row, HorizontalSpan:new{ width = tile_w })
        end
    end
    return row
end

function LauncherWidget:makeTile(item, width, height, style, font_size)
    local hold = item.hold_callback
    return Tile:new{
        width = width,
        height = height,
        style = style,
        text = item.text,
        icon_file = item.icon_file,
        font_size = font_size,
        enabled = item.enabled ~= false,
        selected = item.selected or false,
        show_parent = self,
        callback = item.callback and function()
            safeCall("tile '" .. tostring(item.text) .. "'", item.callback)
        end or nil,
        hold_callback = hold and function()
            safeCall("long-press on '" .. tostring(item.text) .. "'", hold)
        end or nil,
    }
end

---- Shortcuts from config.lua ------------------------------------------------

-- Pick how to run a configured shortcut: the first available of dispatcher,
-- plugin method, event, callback.
function LauncherWidget:resolveShortcut(b)
    local reason -- why it can't run, from the first option tried
    local function note(r) reason = reason or r end

    local run
    if b.requires and not self.ui[b.requires] then
        note("missing")
    else
        if type(b.dispatcher) == "string" then
            local status = dispatcherActionStatus(b.dispatcher)
            if status == "ok" then
                run = function() self:runDispatcher(b.dispatcher, b.value) end
            else
                note(status)
            end
        end
        if not run and type(b.plugin) == "string" and type(b.method) == "string" then
            local plugin = self.ui[b.plugin]
            if plugin and isCallable(plugin[b.method]) then
                run = function()
                    plugin[b.method](plugin, unpack(b.args or {}))
                end
            else
                note("missing")
            end
        end
        if not run and type(b.event) == "string" then
            run = function()
                self.ui:handleEvent(Event:new(b.event, unpack(b.args or {})))
            end
        end
        if not run and type(b.callback) == "function" then
            run = function() b.callback(self.ui, self) end
        end
    end

    return {
        id = "shortcut:" .. b.label,
        label = b.label,
        icon = type(b.icon) == "string" and b.icon or nil,
        kind = "shortcut",
        default_place = "apps",
        enabled = run ~= nil,
        suffix = not run and (reason == "unavailable" and _("(not available here)") or _("(not installed)")) or nil,
        close = b.close,
        run = run,
    }
end

function LauncherWidget:runDispatcher(id, value)
    local settings = { [id] = value == nil and true or value }
    self.forward_events = true
    local ok, err = pcall(Dispatcher.execute, Dispatcher, settings)
    self.forward_events = false
    if not ok then error(err, 0) end
end

---- System row ---------------------------------------------------------------

function LauncherWidget:getSystemItems()
    return {
        {
            text = _("Light"),
            icon_file = self:icon("lightbulb-outline"),
            enabled = Device:hasFrontlight(),
            callback = function() self:toggleFrontlight() end,
        },
        {
            text = _("Wi-Fi"),
            icon_file = self:icon("wifi"),
            enabled = Device:hasWifiToggle(),
            callback = function() self:toggleWifi() end,
        },
        {
            text = _("Files"),
            icon_file = self:icon("folder-outline"),
            callback = function() self:openFileBrowser() end,
        },
        {
            text = _("Exit"),
            icon_file = self:icon("power"),
            callback = function() self:confirmExit() end,
        },
    }
end

function LauncherWidget:toggleFrontlight()
    if dispatcherActionStatus("toggle_frontlight") == "ok" then
        self:runDispatcher("toggle_frontlight")
    else
        Device:getPowerDevice():toggleFrontlight()
    end
    -- FrontlightStateChanged normally updates the header; this covers
    -- devices or versions that don't send it.
    UIManager:nextTick(function() self:refreshStatus() end)
end

function LauncherWidget:toggleWifi()
    if dispatcherActionStatus("toggle_wifi") == "ok" then
        self:runDispatcher("toggle_wifi")
    else
        local NetworkMgr = require("ui/network/manager")
        local done = function() self:refreshStatus() end
        if NetworkMgr:isWifiOn() then
            NetworkMgr:toggleWifiOff(done, true)
        else
            NetworkMgr:toggleWifiOn(done, false, true)
        end
    end
    UIManager:nextTick(function() self:refreshStatus() end)
end

function LauncherWidget:openFileBrowser()
    local ui = self.ui
    self:onClose()
    -- From a book, go to the file manager. From the file manager, closing
    -- the launcher is enough.
    if ui and ui.document then
        ui:handleEvent(Event:new("Home"))
    end
end

function LauncherWidget:confirmExit()
    local ui = self.ui
    local function run(event_name)
        self:onClose()
        UIManager:nextTick(function()
            safeCall(event_name, ui.handleEvent, ui, Event:new(event_name))
        end)
    end
    if Device:canRestart() then
        local MultiConfirmBox = require("ui/widget/multiconfirmbox")
        UIManager:show(MultiConfirmBox:new{
            text = _("Restart or exit KOReader?"),
            choice1_text = _("Exit"),
            choice1_callback = function() run("Exit") end,
            choice2_text = _("Restart"),
            choice2_callback = function() run("Restart") end,
        })
    else
        UIManager:show(ConfirmBox:new{
            text = _("Exit KOReader?"),
            ok_text = _("Exit"),
            ok_callback = function() run("Exit") end,
        })
    end
end

---- Events -------------------------------------------------------------------

function LauncherWidget:onClose()
    UIManager:close(self, "flashui")
    return true
end

function LauncherWidget:onCloseWidget()
    if state.widget == self then
        state.widget = nil
    end
end

-- A book is opening: the FileManager we belong to is going away.
function LauncherWidget:onShowingReader()
    UIManager:close(self)
end

-- Rotation or other size change: rebuild for the new geometry.
function LauncherWidget:onSetDimensions()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    safeCall("rebuilding after resize", self.buildLayout, self)
    UIManager:setDirty(self, "full")
end

-- Header updates: event driven, no timers. These are broadcasts, so return
-- nothing and let everyone else see them too.
function LauncherWidget:onResume() self:refreshStatus() end
function LauncherWidget:onNetworkConnected() self:refreshStatus() end
function LauncherWidget:onNetworkDisconnected() self:refreshStatus() end
function LauncherWidget:onFrontlightStateChanged() self:refreshStatus() end
function LauncherWidget:onCharging() self:refreshStatus() end
function LauncherWidget:onNotCharging() self:refreshStatus() end

---------------------------------------------------------------------------
-- The plugin
---------------------------------------------------------------------------

local PluginLauncher = WidgetContainer:extend{
    name = PLUGIN_NAME,
    is_doc_only = false,
}

function PluginLauncher:init()
    -- Never let the launcher stop KOReader from starting.
    safeCall("init", self.setup, self)
end

-- The old "Launcher" plugin (launcher.koplugin) is this plugin's earlier name.
function PluginLauncher:oldLauncherLoaded()
    return self.ui and isLauncherPlugin("launcher", self.ui.launcher)
end

function PluginLauncher:migrateSettings()
    if self:oldLauncherLoaded() then return end -- leave its settings alone while it's installed
    for old, new in pairs(OLD_SETTINGS) do
        if G_reader_settings:has(old) then
            if new and not G_reader_settings:has(new) then
                G_reader_settings:saveSetting(new, G_reader_settings:readSetting(old))
            end
            G_reader_settings:delSetting(old)
        end
    end
end

function PluginLauncher:setup()
    self:migrateSettings()
    self:onDispatcherRegisterActions()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end

    if self:oldLauncherLoaded() and not state.warned_old then
        state.warned_old = true
        UIManager:nextTick(function()
            UIManager:show(InfoMessage:new{
                text = _("The old Launcher plugin is still installed, so it will open too. Delete the folder koreader/plugins/launcher.koplugin to keep only PluginLauncher."),
            })
        end)
    end

    local in_reader = self.ui and self.ui.document ~= nil
    if not state.autostart_done then
        state.autostart_done = true
        if G_reader_settings:nilOrTrue(SETTING_AUTOSTART) then
            self:autostart()
        end
    elseif not in_reader and G_reader_settings:isTrue(SETTING_RESHOW) then
        -- A new FileManager means we've come back from a book.
        UIManager:nextTick(function()
            safeCall("reshow", self.showLauncher, self)
        end)
    end
end

function PluginLauncher:autostart()
    -- If the last autostart never got as far as drawing the launcher,
    -- KOReader probably crashed. Skip it once so it can't loop.
    if G_reader_settings:isTrue(SETTING_BOOT_GUARD) then
        logger.warn("PluginLauncher: the previous autostart didn't finish; skipping it this time")
        clearBootGuard()
        UIManager:nextTick(function()
            showError(_("PluginLauncher didn't open at startup because it failed last time. The details are in crash.log. You can open it from Tools › PluginLauncher."))
        end)
        return
    end

    local config = loadConfig(getPluginDir(self))
    local open = function()
        local ok = safeCall("autostart", self.showLauncher, self, true)
        if not ok then
            -- It failed without crashing: no need to skip it next time.
            clearBootGuard()
            showError(_("PluginLauncher couldn't open. The details are in crash.log."))
        end
    end
    -- nextTick: the FileManager is shown right after plugins are created, so
    -- this puts the launcher on top of it.
    if config.startup_delay > 0 then
        UIManager:scheduleIn(config.startup_delay, open)
    else
        UIManager:nextTick(open)
    end
end

function PluginLauncher:showLauncher(from_autostart)
    local old = state.widget
    if old then
        -- Reopening (e.g. from a gesture while something else is on top):
        -- replace the old one so the new one is on top.
        state.widget = nil
        UIManager:close(old)
    end

    if from_autostart then
        G_reader_settings:makeTrue(SETTING_BOOT_GUARD)
        G_reader_settings:flush()
    end

    local widget = LauncherWidget:new{
        ui = self.ui,
        plugin_dir = getPluginDir(self),
        boot_guard = from_autostart or false,
    }
    state.widget = widget
    UIManager:show(widget, "full")
end

function PluginLauncher:onDispatcherRegisterActions()
    Dispatcher:registerAction("pluginlauncher_show", {
        category = "none",
        event = "ShowPluginLauncher",
        title = _("Show PluginLauncher"),
        general = true,
    })
end

function PluginLauncher:onShowPluginLauncher()
    safeCall("show", self.showLauncher, self)
    return true
end

-- Our FileManager/ReaderUI is closing: don't leave a launcher pointing at it.
function PluginLauncher:onCloseWidget()
    local widget = state.widget
    if widget and widget.ui == self.ui then
        state.widget = nil
        UIManager:close(widget)
    end
end

function PluginLauncher:addToMainMenu(menu_items)
    menu_items.pluginlauncher = {
        text = _("PluginLauncher"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Open PluginLauncher"),
                callback = function()
                    -- The menu closes after this callback; open on the next tick.
                    UIManager:nextTick(function()
                        safeCall("open from menu", self.showLauncher, self)
                    end)
                end,
            },
            {
                text = _("Open at startup"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue(SETTING_AUTOSTART)
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue(SETTING_AUTOSTART)
                end,
            },
            {
                text = _("Reopen after closing a book"),
                checked_func = function()
                    return G_reader_settings:isTrue(SETTING_RESHOW)
                end,
                callback = function()
                    G_reader_settings:flipTrue(SETTING_RESHOW)
                end,
            },
            {
                text = _("Reset moved and hidden tiles"),
                keep_menu_open = true,
                enabled_func = function()
                    local saved = G_reader_settings:readSetting(SETTING_PLACEMENT)
                    return type(saved) == "table" and next(saved) ~= nil
                end,
                callback = function(touchmenu_instance)
                    UIManager:show(ConfirmBox:new{
                        text = _("Put every tile back on its default tab?"),
                        ok_text = _("Reset"),
                        ok_callback = function()
                            G_reader_settings:delSetting(SETTING_PLACEMENT)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })
                end,
            },
            {
                text = _("About PluginLauncher"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _("Every installed plugin with a menu gets a tile. Long-press a tile to move it between Apps and Built-in, or to hide it.") .. "\n\n"
                            .. _("Shortcuts, icons and the number of columns are set in:") .. "\n" .. getPluginDir(self) .. "/config.lua\n\n"
                            .. _("To get back here from anywhere, bind \"Show PluginLauncher\" to a gesture in Gesture manager (it's under General)."),
                    })
                end,
            },
        },
    }
end

return PluginLauncher
