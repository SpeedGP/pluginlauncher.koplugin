# PluginLauncher for KOReader

A home screen for your **plugins and apps** instead of your books.

PluginLauncher opens when KOReader starts and shows a tile, with an icon, for
every installed plugin. It's handy on devices you use for more than reading:
chatting with an AI assistant, playing games, or running tools.

- **Apps** tab: your shortcuts, a thin divider, then every plugin you installed, A–Z.
- **Built-in** tab: the plugins that ship with KOReader.
- **Hidden** tab: only appears once you've hidden something.
- Header: a title, plus Wi-Fi, frontlight, battery and the time.
- Bottom row: **Light**, **Wi-Fi**, **Files** (the normal file browser) and **Exit** (restart or exit KOReader).

Tap a tile to open that plugin's menu, the same one it has under Tools. If a
plugin has just one action, tapping runs it straight away.

**Long-press any tile** to move it between Apps and Built-in, or to hide it.

Designed for e-ink: there are no animations and no timers. The header redraws
only its own strip, and only when something changes (Wi-Fi, frontlight,
charging, waking up).

## Install

1. Download `pluginlauncher.koplugin.zip` from the
   [latest release](../../releases/latest) and unzip it.
2. Copy the `pluginlauncher.koplugin` folder into KOReader's `plugins/` folder.
   On a Kindle that's `koreader/plugins/` on the USB drive; on a Kobo it's
   `.adds/koreader/plugins/`.
3. Restart KOReader.

If you use GitHub's green **Code → Download ZIP** button instead, the folder is
called `pluginlauncher.koplugin-main`. Rename it to `pluginlauncher.koplugin`
or KOReader won't load it.

If KOReader won't start after installing, rename the folder to
`pluginlauncher.koplugin.disabled` and look in `koreader/crash.log`.
PluginLauncher also protects itself: if it fails to appear during startup, it
skips autostart on the next launch so it can't trap KOReader in a crash loop.

### Upgrading from "Launcher"

PluginLauncher used to be called Launcher (`launcher.koplugin`). Delete the old
`launcher.koplugin` folder. Your settings and moved or hidden tiles carry over
automatically. If you had bound "Show launcher" to a gesture, bind
**Show PluginLauncher** instead.

## Getting back to PluginLauncher

PluginLauncher stays open underneath anything you open from it, so closing a
plugin or game puts you back on it. To get back from anywhere else, open
Gesture manager, choose a gesture, then General → **Show PluginLauncher**.

## Settings

Tools → PluginLauncher:

- **Open PluginLauncher**
- **Open at startup** is on by default.
- **Reopen after closing a book** is off by default.
- **Reset moved and hidden tiles**

## Configuration

Edit `config.lua` in the plugin folder; the instructions are at the top of the
file. You can set:

- **Shortcuts**: tiles that jump straight to one action, such as starting a
  chat in [KOAssistant](https://github.com/zeeyado/koassistant.koplugin),
  instead of opening a plugin's menu. They can run a Dispatcher action (the
  same actions Gesture manager offers), call a plugin method, send an event, or
  run any Lua.
- **Columns** (default 3), **label size** and the **title**.
- **Icons** for any plugin or shortcut.
- **Default tab** for specific plugins (`apps`, `builtin` or `hidden`).

Changes apply the next time PluginLauncher opens. If `config.lua` has a
mistake, PluginLauncher still opens (without your shortcuts) and writes the
error to `crash.log`.

### Icons

Plugins KOReader ships with, and some popular ones, have icons already. Other
plugins get one picked from their name ("chess" gets a chess knight, "sudoku"
a grid, and so on), or a puzzle piece.

To change an icon, set it in `config.lua` by name or file path. Icon names are
looked up in `koreader/icons/` first, then this plugin's `icons/` folder, then
KOReader's own icons. To add one, download an SVG from
[Material Design Icons](https://pictogrammers.com/library/mdi/) into `icons/`.
Putting a file with the same name in `koreader/icons/` replaces a bundled icon.

## Works with

- Zen UI, SimpleUI and other file-browser themes. PluginLauncher draws on top of
  the file browser and doesn't patch it.
- Any plugin that adds an entry to KOReader's menu.

## Development

The tests run without KOReader, against stand-ins for the KOReader modules
PluginLauncher uses:

```bash
luajit spec/run.lua
```

```bash
luacheck .
```

## Credits and licence

PluginLauncher is licensed under the GNU General Public License v3.0; see
[LICENSE](LICENSE).

The icons in `icons/` are from
[Material Design Icons](https://pictogrammers.com/library/mdi/) by
Pictogrammers, licensed under the Apache License 2.0; see
[icons/LICENSE](icons/LICENSE).
