# RS Dev Tools

One panel of tools for RuneScape plugin makers. Every list is a table (one shared helper, dt_table.lua).

Tabs: UI Inspector, Plugin Analyser, Event Monitor, Sprite Browser, Audio, Settings, Perf Meter, Layout Grid, Text Fit, Reload Helper, Help/FAQ, Diagnostics, Error Log, API Explorer.

## Permissions
None. Display only: no input, no console commands, no settings changes. Nothing is drawn at the mouse. Browsing sounds plays on the MASTER bus; the Audio "Bus test" mode plays one sound on the bus you click so MASTER and SFX can be compared.

## Analysing other plugins
- Possible: a read-only scan of the shared plugin layer (TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP), which every plugin panel is built on: type, position, size, shown state and visible text of each component, plus a count against the 4096 dynamic ID limit.
- Not possible: knowing which plugin owns a panel, reading other plugins' settings (PersistentDB is isolated), files, timings or errors, or listing installed plugins.
- Opt-in hook: a plugin can end its main.lua with `return { devInfo = function() return { key = value } end }`. Without RS Dev Tools this does nothing. RS Dev Tools only sees it if that plugin's folder name is added to its plugin.json `optionalDependencies` (e.g. `"world_event_timers": "world-event-timers"` locally; mod.io ID for submission). None are listed in 0.2.0: whether a dependency's main.lua runs a second time when loaded as a dependency is untested, so test with one plugin first.

## Help/FAQ and Diagnostics
faq_data.lua is generated from the plugin developer Discord research by `release/build_faq.py`. Do not edit it by hand. `release/validate_plugin_json.py <folder>` checks manifests (trailing commas, contact email, requiredPermissions, dependency IDs, resource sizes), because plugins cannot read plugin.json at runtime.

## First load
Open the console (Alt and backtick), then `prf` and `pon rs-dev-tools`. After edits: `prl rs-dev-tools`.

## 0.2.1
- Commands tab: runs documented console commands with ExecuteConsoleCommand when you click Run. No permission is needed (the documented permissions are httpAccess, chatAccess and trackingAccess only), so plugin.json still requests none and no ppe command is needed. Works only in the developer environment.
- Help/FAQ answers open in their own window (faq_dialog.lua).
- Tooltips come from tips_data.lua through helpers.setTip in ui_helpers.lua (shared with the ellipsis hover box).
