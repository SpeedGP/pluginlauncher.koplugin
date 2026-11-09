--[[
PluginLauncher configuration.

You don't need to list your plugins here: every installed plugin that has a
menu entry gets a tile automatically. Plugins you installed go on the Apps tab
and plugins that ship with KOReader go on the Built-in tab. Long-press any tile
to move it to the other tab or hide it.

This file is for SHORTCUTS (tiles that jump straight to one action, such as
opening a chat, instead of opening a plugin's menu), plus a few display
options. Shortcuts are shown at the top of the Apps tab, above a thin divider.

Changes are picked up the next time PluginLauncher opens; no restart needed.
If this file has a mistake in it, PluginLauncher still opens (without your
shortcuts) and the error is written to koreader/crash.log.

ICONS
  An icon is a name or a file path:
    "chat-outline"          a file named chat-outline.svg (or .png), looked
                            for in koreader/icons/, then this plugin's icons/
                            folder, then KOReader's own icons.
    "icons/mine.svg"        a path inside this plugin's folder.
    "/mnt/us/my/icon.png"   an absolute path.
  The bundled icons are from Material Design Icons (pictogrammers.com/library/mdi).
  To add one, download its SVG from there and put it in the icons/ folder.
  Putting a file with the same name in koreader/icons/ replaces a bundled one.

SHORTCUTS
  Each shortcut needs a `label` and one way to run something. If you give more
  than one, the first one that's available is used, in this order:

    dispatcher = "action_id"   A Dispatcher action, the same list Gesture
                               manager uses. Add `value = ...` for actions
                               that take one.
    plugin = "name",           Call a method on a loaded plugin directly, e.g.
    method = "onSomething",    plugin = "koassistant", method = "onKOAssistantGeneralChat".
    args = { ... }             `args` is optional.
    event = "EventName",       Send a KOReader event to the file manager or
    args = { ... }             reader. `args` is optional.
    callback = function(ui, launcher) ... end
                               Any Lua you like. `ui` is the FileManager or ReaderUI.

  Optional per shortcut:
    icon = "name"              See ICONS above.
    requires = "pluginname"    Grey the tile out unless this plugin is loaded.
    close = true               Close PluginLauncher before running the action.
                               By default it stays open underneath, so closing
                               the chat or game puts you back here.

  To find Dispatcher action ids, look for Dispatcher:registerAction("...") in
  a plugin's main.lua, or in koreader/frontend/dispatcher.lua for built-in ones.
]]

return {
    -- Text at the top left.
    title = "PluginLauncher",

    -- Number of columns in the grid (1 to 6).
    columns = 3,

    -- Label size. KOReader scales this to the screen.
    font_size = 20,

    -- Show a tile for every installed plugin. Set to false to show only the
    -- shortcuts below.
    show_plugins = true,

    -- Where the Light / Wi-Fi / Files / Exit row goes: "top" (under the
    -- header, harder to tap by accident) or "bottom".
    system_row = "top",

    -- Seconds to wait after startup before PluginLauncher appears. Leave at 0
    -- unless another plugin draws over it when KOReader starts. Then try 1.
    startup_delay = 0,

    -- Optional: default tab for specific plugins or shortcuts. Keys are plugin
    -- folder names without ".koplugin" (a tile's long-press menu shows it), or
    -- shortcut labels. Values: "apps", "builtin" or "hidden".
    -- Long-pressing a tile on the launcher overrides what's set here.
    place = {
        -- terminal = "apps",
        -- hello = "hidden",
    },

    -- Optional: icons for plugins, by plugin folder name (or shortcut label).
    -- Plugins without one get an icon picked from their name, or a puzzle piece.
    icons = {
        -- terminal = "console",
        -- mygame = "gamepad-variant-outline",
    },

    shortcuts = {
        -- KOAssistant (github.com/zeeyado/koassistant.koplugin). These action
        -- ids are taken from KOAssistant's main.lua. The KOAssistant plugin
        -- also gets its own tile, which opens its full menu.
        { label = "Chat",           icon = "chat-outline",            dispatcher = "koassistant_general_chat",         requires = "koassistant" },
        { label = "Continue Chat",  icon = "chat-processing-outline", dispatcher = "koassistant_continue_last_opened", requires = "koassistant" },
        { label = "Chat History",   icon = "history",                 dispatcher = "koassistant_chat_history",         requires = "koassistant" },
        { label = "AI Settings",    icon = "tune-variant",            dispatcher = "koassistant_ai_settings",          requires = "koassistant" },

        -- More examples:
        -- { label = "Brightness", icon = "brightness-6",      dispatcher = "show_frontlight_dialog" },
        -- { label = "Sleep",      icon = "power-sleep",       dispatcher = "suspend" },
        -- { label = "Terminal",   icon = "console",           dispatcher = "terminal" },
    },
}
