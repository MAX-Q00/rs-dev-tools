## RS Dev Tools 0.5.3 (2026-10-23)
- Tooltips no longer flicker or flip between two layouts: one owner per check (innermost control wins over its row), a short show delay, re-layout only when the text changes, offset from the pointer and clamped on screen, and the tooltip never takes hover.
- Dropdowns open on one click and stay open until you pick an item or click outside: the opening click is ignored by the list, the box toggles once per click, the panel is raised before the list is built and the list is re-raised after any window raise, and small layout jitter no longer closes it.
- Tooltips size to their text: measured once per text change at a fixed 260 px wrap (long text grows taller), cached, and only moved (never resized) while the text is unchanged.
- Diagnostics cleaned up: sandbox limits (debug.traceback, os.clock, os library, id.Sprite, game.options) and not-yet states (Draw, ServerLogic, Mouse, config before login, high DPI) are neutral notes; PluginShutdown check fixed (it looked in _G, but plugin globals live in the plugin environment); layer growth is shown as information (shared layer, all plugins) and the 4096 total stays the real limit.
- Error Log without debug.traceback records the source:line from the error message.
- Event subscriptions made through RDT are recorded so they are all unsubscribed at shutdown.
- Permissions tab with 6 sub-tabs: Run (command, plugin and permission pickers, a preview of the exact command, runs only on a click; ppd and poff ask for Confirm; Grant runs ppr, ppe, prl; Run is disabled if ExecuteConsoleCommand is missing), Status (this plugin's 3 permissions plus a change log), Permissions, Commands, Manifest and FAQ/Review. Claims from Discord are labelled unverified.
- Frame cost: the panel refreshes only when something changed (or every 30 ticks on live tabs, 250 on Diagnostics, never on static tabs), and does nothing while collapsed or hidden. Tooltips skip the hit test while the mouse is still.
- Resize grip: keeps the drag while the mouse moves off the grip, applies the size live, clamps it on screen, saves on release, and no longer fights the content-fit height.

## RS Dev Tools 0.5.2 (2026-10-23)
- Model Sandbox uses the shared model_core.lua (same file as Rotten Potato): one copy of SetModel, box creation (hidden, click-through, disabled), the 24..900px clamp, camera and Seq helpers.
- Shutdown: ui_helpers now also closes an open dropdown and the toast, and unsubscribes every helpers.subscribe event when the plugin unloads.

## RS Dev Tools 0.5.1 (2026-10-23)
- X in the title bar now backs out of a sub-view first (Edit/settings, Commands More info and value list, Plugin Analyser window detail); X on the main view still closes the panel.
- Static tables (hooks, limits, volume and game options, API namespaces, API tries, known gaps) moved to rdt_data.lua: main.lua top-level locals 111 -> 105 (Lua limit 200).
- ui_helpers synced with the shared canonical copy: Settings gets the Column resize (Drag/Buttons) and Column widths: Reset rows; Rotten Potato short title is RP.

## RS Dev Tools 0.5.0 (2026-10-23)
- New Assets > Model Sandbox tab: spawn client-side 3D models of NPCs, items or raw model IDs in the game view (up to 20 at once), using documented ui.Model/SetModel, ScreenConvert.Vector3ToScreen, Camera pitch and NPCType.bas.overlayHeight.
- Search NPCs or items (Show dropdown), or type an ID, then Spawn on screen. The Item browser also has Spawn on screen for the picked item.
- Each model: drag its small + handle to move it (anchored to a world tile, or Pin/World to pin it to the screen), Yaw -45/+45 or typed degrees, Size -/+ or typed %, animation dropdown (id.Seq names matching the NPC; NPCs start on idle) or typed anim ID, Play/Stop, Duplicate, Delete, and Clear all. The Spawned list shows name, ID, kind, tile and anim with adjustable columns.
- Safety: model boxes are capped at 900px, click-through and disabled; the panel is re-raised whenever a model overlaps it and handles hide over the panel; every per-tick step and button is pcall-guarded. Nothing is restored at load; Save scene / Load scene only run when clicked.
- Visual only: sends nothing to the game.

## RS Dev Tools 0.4.1 (2026-10-23)
- Right-click menu tile coords (on by default): the open menu gets an info line at the bottom with the tile under the mouse, as level, x, z, map square and local tile. It uses the documented MiniMenu:Add with an action that does nothing, and is swapped to the lowest priority so it is never the left-click default.
- Item hover info (on by default): hovering an item on the ground, or in the inventory, bank or equipment, shows Item Name (ID) next to the pointer in the plugin's tooltip box.
- Settings tab: Menu tile coords on/off and Item hover info on/off (saved).

## RS Dev Tools 0.4.0 (2026-10-23)
- Single edition: everything that was in RS Dev Tools Unlimited is now in RS Dev Tools, and the Unlimited edition is retired.
- Debug tabs merged in: Automation (console macros with presets, step delay, repeat and Stop; destructive steps still need Confirm), Visual Overrides (hide ground items, hide yourself, NPC name filter), Deep Probe with Deep scan (read-only walk of the whole API, flags undocumented names and saves to PersistentDB rdt_probe), and the Probe tab (Call () needs Confirm).
- Inspect > World Render: Hide NPCs and Hide other players.
- Removed edition.lua, release/build_unlimited.py and release/unlimited_modules.
- Settings saved by the old Unlimited plugin (its macros, rdt_probe) stay with that plugin and are not carried over.

## RS Dev Tools 0.3.0 (2026-10-23)
- Developer harness tabs in their own module files: Event Payloads (all 43 events with counts, per second, subscribed by and a payload viewer; chat text hidden), Camera & World readouts, Component Tree, Profiler (timed API calls, layout and frame cost), Shapes & Canvas playground, PersistentDB browser/editor for this plugin's own data (Delete and Clear all need Confirm), Permissions status, and API Coverage (every documented entry and event, used or not, plus a live client check).
- Commands tab: per-argument controls (ID and fixed-value arguments are dropdowns shown as 'ID - Name', counts/levels/XP are number boxes with - and +), a More info view explaining every argument in order (type, required or optional, default, meaning, valid values, example; unconfirmed items are labelled) with paged value lists (item and var names read from this client) that insert a value on click, and a Back button.
- !pouchadd hint is now CURRENCY COUNT 0|1.
- All tables: adjustable columns via the shared helpers.columns (drag a header border, or < > buttons in Settings), saved per table, Reset widths.

## RS Dev Tools 0.2.14 (2026-10-23)
- World Render tab (Inspect): client-side position and path debug markers, ported from Rotten Potato. Ring around your position (radius 200 to 3200 units plus a half-tile ring), path trail (last 60 points while moving) and sky beam, drawn with ShapeList.DrawLine. Colour and radius dropdowns and an All off button. Everything is off on load, is not saved, and is turned off when the plugin unloads. Nothing is sent to the game. Adds edition.lua (public build: unlimited = false).

## RS Dev Tools 0.2.13 (2026-10-23)
- Option pickers are RuneScape-style dropdowns (shared helpers.dropdown in ui_helpers.lua): a stone box with a gold edge shows the current value and a down arrow; click it to open the list, click an option to pick it, click the box again or anywhere outside to close. Long lists scroll with up/down buttons. Saved choices are unchanged. Dropdowns replace the click-to-cycle view switchers on every tab, Letter, Bus, Grid step, Box width, Submission Check target and Resource Monitor graph set, plus the Edit settings rows.

## RS Dev Tools 0.2.12 (2026-10-23)
- Commands tab: removed the Source / verified column and the source text from tooltips. Columns are now Command, Syntax / args and Description; tooltips show the full syntax and description. Risky commands still need a Confirm click.

## RS Dev Tools 0.2.11 (2026-10-23)
- Commands tab: all 46 documented dev-world cheat commands in a separate Cheat (!) category (was 4), with argument hints, descriptions and a Source / verified column (docs only, reported by Dylan, or Discord: broken). Risky cheats (!clearworn, !clearinv, !hitall, !allinone, account-type changes, !pouchdel, !inventwipemats, !resetsave) need a Confirm click. Added pan (config lists, used to find !give names) and commands. Nothing runs without a Run click.

## RS Dev Tools 0.2.10 (2026-10-23)
- New 64x64 icon and mod.io logo in the same style as the other plugins: the shared gold rounded frame on a dark background, with a gold wrench between code brackets.

## RS Dev Tools 0.2.9 (2026-10-23)
- Help/FAQ shows the real conversations. Clicking a question now shows it with its main answer at the top of the Help tab, with the Discord names of who asked and who answered, plus a More info button. More info opens the full conversation: the question first, then every reply as its own block with a header band (poster's Discord name, Jagex staff or community tag, date) and a divider between posts. Fixes: answers from several people were merged into one paragraph with line breaks lost, the source line ran off the window, and long questions were cut. Names not recorded in the research show as Unknown user.

## RS Dev Tools 0.2.8 (2026-10-23)
- Help/FAQ updated from the latest developer Discord questions (now 45). New: more than one .lua file per plugin, Chat.AddMessage lines vanishing on friend login/logout, linking Construction furniture to its object through DBRows, what DBTableType is for, and plugins that store data on a shared server. Better answers for CheckboxButton value, transparent PrettyUI windows, the clue-scroll text timing workaround, shared plugin files across clients and per-account settings, missing activation emails, vanished installed plugins, the 200-tile limit and plugin requests. Answers note when they come from the community rather than Jagex staff.

## RS Dev Tools 0.2.7 (2026-10-23)
- New Submission Check tab (Plugins): every rule that gets plugins sent back by moderation, from the Jagex Submission process and Plugin guidelines pages, the developer Discord and our checklist. Each rule is marked Live (tested now in the client: version format, PluginShutdown, component leak and the 4096 ID limit, callback errors, event subscriptions, chat use, console commands, frame cost), Script (needs the files; run release/check_submission.py) or Manual, with pass/warn/fail, the reason and the fix. Other plugins' panels found on the plugin layer get the layer checks. New Resource Monitor tab (Inspect): FPS, frame time, worst frame, logic tick rate, server tick interval, Lua heap, refresh and Draw handler cost, layer and own component counts and events per second, sampled once a second; two live line graphs at a time (Frames, Ticks, Memory, Cost) with axis labels and now/min/avg/max, a typed 10-120 s window, and a table of every value plus what the API cannot provide. Its own overhead is shown.

## RS Dev Tools 0.2.6 (2026-10-23)
- Fix: Sounds tab is audible again (the saved Vol setting was below 100%, and the client mutes any volume under 1.0; previews now always play at 1.0 and the Vol button is gone). New Bus picker for sound previews (every bus in audio.AudioBus) and copy snippets that include the bus. Tabs grouped into categories (Inspect, Plugins, Assets, Debug, Help) with a filled selected state. Commands no longer overflow: rows per page fit the screen, fixed 3-line detail, narrow Source column. One standard pager on every tab (-100 -10 Prev Page [typed] of N Next +10 +100). Empty states (Error Log: No errors since load). Perf Meter shows plugin layer components out of 4,096. Event Monitor: copy the last 20 events. FAQ detail fixed (a missing constant). Shared style: labels #A8A090, explanation tooltips, standard -/+ number box (20px buttons, 48px typed field), 8px footer clearance.

## Sound Browser 0.1.19 (2026-10-23)
- Fix: previews always play at volume 1.0 (the client mutes anything lower). Bus picker, Type filter (Emote, Teleport, Quest, Combat, Interface, Skilling), sentence-case names (raw name on hover), star favourites, play marker and gold row while playing, Copy field with ready-made audio.Play code, standard one-row pager with a typed page box. Shared style: labels #A8A090, explanation tooltips, standard -/+ number box (20px buttons, 48px typed field), 8px footer clearance.

## World Event Timers 0.12.11 (2026-10-23)
- Bell has its own 28px column and times are right-aligned against it; unarmed bells dimmed to 40%. Every event tied for soonest is highlighted. Amber Starting-soon state inside the notice lead time. Footer buttons evenly spaced. Compact mode (Edit: next event only). Alarm sound always plays at volume 1.0 (the client mutes lower values), so the Alarm volume option is gone; use the game's Master slider. Fresh installs still start with Alarms Off and Sound Off. Shared style: labels #A8A090, explanation tooltips, standard -/+ number box (20px buttons, 48px typed field), 8px footer clearance.

## Slayer Task Tracker 0.11.21 (2026-10-23)
- Left reads 195 left of 195 with a 4px gold progress bar on a visible track (replaces the blank gap). 10px bottom padding; minimum width fits the task name and count. ETA line adds kills per hour and Slayer xp gained this session. Task history (last 10, toggle in Edit). Streak shows the next bonus and next big milestone. Shared style: labels #A8A090, explanation tooltips, standard -/+ number box (20px buttons, 48px typed field), 8px footer clearance.

## Cursor Sprite 0.1.23 (2026-10-23)
- Controls grouped under Look (Set, Size, Rotation) and Position (Offset X/Y, D-pad, Step, Reset, Save position, presets); all number boxes on one column grid. Plus-shaped D-pad. Framed 40px Preview box. Standard pager (-100 -10 Prev Page [typed] of N Next +10 +100) replaces the ID jump row. 24px icons on slot tiles. Recent list (last 8 picks). 4 presets of size, rotation and offset (Store / Load). Red crosshair on the pointer tip for 3 s after an edit. On-point unchanged (image top-left on the pointer, no Tip row); favourites still auto-save offset and size. Shared style: labels #A8A090, explanation tooltips, standard -/+ number box (20px buttons, 48px typed field), 8px footer clearance.

## Gear Preset Checker 0.11.25 (2026-10-23)
- Shared style: labels #A8A090, explanation tooltips, standard -/+ number box (20px buttons, 48px typed field), 8px footer clearance.

## RS Dev Tools 0.2.5 (2026-10-23)
- Fix: the title-bar Edit, _ and X buttons work again (the full-width drag strip added in an earlier build covered them and swallowed clicks; it now stops short of the buttons). Help/FAQ window taller and opaque, with one code block and a Copy button (no duplicate box). Commands: inner view button renamed All, developer cheats grouped in red under a Dev cheats divider, one-line header and a fixed-height detail so the table no longer jumps, shorter descriptions (sources moved to the tooltip). Diagnostics: expected off states in grey and a summary line (ok, warnings, failures), wider Notes. Sprite Browser: status reads Showing N of M sprites, the ID -1000..+1000 row is gone (Go to ID covers it), 64px preview.

## Cursor Sprite 0.1.22 (2026-10-23)
- Fix: the title-bar Edit, _ and X buttons work again (the full-width drag strip added in an earlier build covered them and swallowed clicks; it now stops short of the buttons). One merged Search name or id box (Use item / Enter / Keypad use it as an item ID); the search clears when switching Set (fixes No cursors available); list height follows the rows (minimum 5).

## Sound Browser 0.1.18 (2026-10-23)
- Fix: the title-bar Edit, _ and X buttons work again (the full-width drag strip added in an earlier build covered them and swallowed clicks; it now stops short of the buttons).

## World Event Timers 0.12.10 (2026-10-23)
- Fix: the title-bar Edit, _ and X buttons work again (the full-width drag strip added in an earlier build covered them and swallowed clicks; it now stops short of the buttons).

## Slayer Task Tracker 0.11.20 (2026-10-23)
- Fix: the title-bar Edit, _ and X buttons work again (the full-width drag strip added in an earlier build covered them and swallowed clicks; it now stops short of the buttons).

## Gear Preset Checker 0.11.24 (2026-10-23)
- Fix: the title-bar Edit, _ and X buttons work again (the full-width drag strip added in an earlier build covered them and swallowed clicks; it now stops short of the buttons).

## RS Dev Tools 0.2.4 (2026-10-22)
- Review pass: solid opaque tooltip (12px below-right of the pointer, flips at edges, wraps at 240px); more opaque panels with a body fill; typed text vertically centred in input boxes; title-bar Edit/_/X presses no longer start a window drag; panel always opens on load. Pager reads 'Page 1 of 4,352' and is measured so it never overlaps Next; ID/# columns right-aligned; gold bar + #5A4A2A fill on the selected row; tabs balanced into two rows; Error Log shows an empty-state row.

## Cursor Sprite 0.1.21 (2026-10-22)
- Review pass: solid opaque tooltip (12px below-right of the pointer, flips at edges, wraps at 240px); more opaque panels with a body fill; typed text vertically centred in input boxes; title-bar Edit/_/X presses no longer start a window drag; panel always opens on load. Nudge buttons on two rows so Favorites is never clipped.

## Sound Browser 0.1.17 (2026-10-22)
- Review pass: solid opaque tooltip (12px below-right of the pointer, flips at edges, wraps at 240px); more opaque panels with a body fill; typed text vertically centred in input boxes; title-bar Edit/_/X presses no longer start a window drag; panel always opens on load.

## World Event Timers 0.12.9 (2026-10-22)
- Review pass: solid opaque tooltip (12px below-right of the pointer, flips at edges, wraps at 240px); more opaque panels with a body fill; typed text vertically centred in input boxes; title-bar Edit/_/X presses no longer start a window drag; panel always opens on load.

## Slayer Task Tracker 0.11.19 (2026-10-22)
- Review pass: solid opaque tooltip (12px below-right of the pointer, flips at edges, wraps at 240px); more opaque panels with a body fill; typed text vertically centred in input boxes; title-bar Edit/_/X presses no longer start a window drag; panel always opens on load.

## Gear Preset Checker 0.11.23 (2026-10-22)
- Review pass: solid opaque tooltip (12px below-right of the pointer, flips at edges, wraps at 240px); more opaque panels with a body fill; typed text vertically centred in input boxes; title-bar Edit/_/X presses no longer start a window drag; panel always opens on load.

## Cursor Sprite 0.1.20 (2026-10-22)
- Fix: the panel stayed hidden after reload because X saved closed=true in windowState; the flag is now cleared on load.

## Sound Browser 0.1.16 / RS Dev Tools 0.2.3 (2026-10-22)
- Fix: panels stayed hidden after reload because the X button saved closed=true in windowState; the flag is now cleared on load.

## Sound Browser 0.1.15 / RS Dev Tools 0.2.2 (2026-10-22)
- Reverted the typed page box (Page [N] of M); Dylan reported both plugins stopped working after it. Page jump buttons unchanged.

## RS Dev Tools 0.2.1 (2026-10-22)
- Audio: playback ported exactly from Sound Browser 0.1.13 (no StopSoundsUsingResource before Play, 100% default volume, finished sounds swept in the tick). The Bus test no longer stops the resource before playing.
- Copy row: created hidden (0.2.0 created it visible at 0,0 over the title and tab bar until the first layout), now full width at the panel's left edge under the detail and preview, same height as the other controls, text shortened with an ellipsis and shown in full on hover, Select swaps in a text box for copying.
- New Commands tab: documented console commands with argument boxes and Run (ExecuteConsoleCommand, no permission needed), free-text box with sanitised input, history with result or error, Copy field, Confirm for poff/prl of RS Dev Tools and !resetsave, Run disabled when ExecuteConsoleCommand is missing.
- Help/FAQ: clicking a question opens a draggable answer window (full question, wrapped answer with scrollbar, code block with Copy, source and date, Prev/Next, Close and X; destroyed on close and in PluginShutdown).
- Tables: the page number is a typed box (Page [N] of M), numbers only, clamped, applied on Enter or focus loss; jumps kept.
- Tooltips: every column header, table cell, Diagnostics and Perf row, control and copy field explains itself in the shared hover box, kept on screen at the window edges.

## Cursor Sprite 0.1.19 (2026-10-22)
- Manual offset with Up/Down/Left/Right buttons and typed Offset X/Y boxes (step 1, 5, 10, 15 or 90), Reset to 0,0, Rotation 0-359 (On-point keeps the image's top-left corner on the pointer), Size/Rotation/Offset are typed boxes with - and + buttons. Favorites: nudging or Save position stores the sprite with its offset, size and rotation; picking it restores them; Remove per row; saved across reloads. Page number is a typed box (Page [N] of M).

## Sound Browser 0.1.14 (2026-10-22)
- The page number is now a typed box (Page [N] of M): numbers only, clamped, applied on Enter or when the box loses focus. Page jump buttons kept.

## RS Dev Tools 0.2.0 (2026-10-22)
- Every list is a table from one shared helper (header, aligned width-adaptive columns, alternating rows, ellipsis with hover).
- New tabs: Plugin Analyser, Sprite Browser (from Cursor Sprite, view only), Help/FAQ (40 entries from the plugin developer Discord), Diagnostics (permissions, resources, layer ID usage vs 4096, PluginShutdown, high-DPI scale), Error Log with stack traces, API Explorer (members, events, live read-only calls, known gaps).
- Audio: Sound Browser's full list with search and page jumps on MASTER, client volume readout, and a Bus test mode.
- Tools: release/build_zips.py (flat zips), release/build_faq.py, release/validate_plugin_json.py.

## RS Dev Tools 0.1.0 (2026-10-22)
- First version.

## World Event Timers 0.12.8 (2026-10-22)
- Removed leftover dead code: the unused HTTP clock fallback, the no-op chat permission check and the old permissions debug line. No behaviour change; still requests no permissions.

## Sound Browser 0.1.13 (2026-10-22)
- Page jumps: -100, -60, -10, -5, +5, +10, +60, +100 page buttons under Prev/Next, clamped to the first and last page (no wrap). One centred row when the panel is wide enough, otherwise back jumps on one row and forward jumps on the next.

## Cursor Sprite 0.1.18 (2026-10-22)
- On-point back to 0.1.15 behaviour: image top-left drawn at the mouse position, no trim. The 0.1.16 Tip trim row is removed and saved trims are dropped. Whole-title-bar drag kept.

## Cursor Sprite 0.1.17 (2026-10-22)
- Whole title bar drags the panel: a full-width drag handle now covers the empty space and the area around the icon, not just the title text. Edit, minimise and close still click; click-to-front unchanged.

## Gear Preset Checker 0.11.22 (2026-10-22)
- Whole title bar drags the panel: a full-width drag handle now covers the empty space and the area around the icon, not just the title text. Edit, minimise and close still click; click-to-front unchanged.

## Slayer Task Tracker 0.11.18 (2026-10-22)
- Whole title bar drags the panel: a full-width drag handle now covers the empty space and the area around the icon, not just the title text. Edit, minimise and close still click; click-to-front unchanged.

## Sound Browser 0.1.12 (2026-10-22)
- Whole title bar drags the panel: a full-width drag handle now covers the empty space and the area around the icon, not just the title text. Edit, minimise and close still click; click-to-front unchanged.

## World Event Timers 0.12.7 (2026-10-22)
- Whole title bar drags the panel: a full-width drag handle now covers the empty space and the area around the icon, not just the title text. Edit, minimise and close still click; click-to-front unchanged.

## Cursor Sprite 0.1.16 (2026-10-22)
- On-point tip trim: new Tip row (X-, X+, Y-, Y+, Reset, readout) shifts the image up/left by its transparent padding, saved per image and scaled with size, so the first visible pixel can sit exactly on the pointer tip at 50-400%. The client API exposes no sprite pixel data or native size, so padding cannot be measured automatically.

## Cursor Sprite 0.1.15 (2026-10-22)
- On-point: the pointer tip now sits exactly on the image's top-left corner for items, sprites and game cursors at every size (50-400%); centre/hotspot anchors removed. Offset unchanged.

## Cursor Sprite 0.1.14 (2026-10-22)
- On-point fix: the image's anchor now lands exactly on the pointer at every size (centre for sprites and items, the cursor's own hotspot for game cursors; offset subtracted, scale applied once). Previously the image grew away from the pointer as the size went up.

## Cursor Sprite 0.1.13 (2026-10-22)
- Size control: scale the cursor image from 50% to 400% (default 100%) with - and + buttons in 25% steps, a % readout, or a typed value (digits only, clamped 50-400; Enter or Set). Saved across reloads; the old px size choice is migrated once. Offset still clears the pointer; game cursors keep their hotspot on the pointer at any size.

## Cursor Sprite 0.1.12 (2026-10-22)
- Cursor image always in front again: raised every tick (also over its own panel) and right after a selection change, redraw, panel click-to-front, drag or restore, so the panel can never end up above it. Reverts the 0.1.7 throttle.

## Cursor Sprite 0.1.11 (2026-10-22)
- Input hardening: text boxes trimmed, control characters and < > removed, lengths capped (names 24); number boxes digits-only and clamped; saved names sanitised on save and on load; search is plain-text and parse/filter paths are crash-proof.

## Gear Preset Checker 0.11.21 (2026-10-22)
- Input hardening: text boxes trimmed, control characters and < > removed, lengths capped (names 24); number boxes digits-only and clamped; saved names sanitised on save and on load; search is plain-text and parse/filter paths are crash-proof.

## Slayer Task Tracker 0.11.17 (2026-10-22)
- Input hardening: text boxes trimmed, control characters and < > removed, lengths capped (names 24); number boxes digits-only and clamped; saved names sanitised on save and on load; search is plain-text and parse/filter paths are crash-proof.

## Sound Browser 0.1.11 (2026-10-22)
- Input hardening: text boxes trimmed, control characters and < > removed, lengths capped (names 24); number boxes digits-only and clamped; saved names sanitised on save and on load; search is plain-text and parse/filter paths are crash-proof.

## World Event Timers 0.12.6 (2026-10-22)
- Input hardening: text boxes trimmed, control characters and < > removed, lengths capped (names 24); number boxes digits-only and clamped; saved names sanitised on save and on load; search is plain-text and parse/filter paths are crash-proof.

## Cursor Sprite 0.1.10 (2026-10-22)
- Fix: panels could not be dragged (the click-to-front hook added to the title bar, grip and icon displaced their drag-start click hook). Those now raise through the drag start only; body, buttons, text boxes and rows still raise on click. Title-bar Edit, minimise and close buttons are back on the right; icon left, title centred.

## Gear Preset Checker 0.11.20 (2026-10-22)
- Fix: panels could not be dragged (the click-to-front hook added to the title bar, grip and icon displaced their drag-start click hook). Those now raise through the drag start only; body, buttons, text boxes and rows still raise on click. Title-bar Edit, minimise and close buttons are back on the right; icon left, title centred.

## Slayer Task Tracker 0.11.16 (2026-10-22)
- Fix: panels could not be dragged (the click-to-front hook added to the title bar, grip and icon displaced their drag-start click hook). Those now raise through the drag start only; body, buttons, text boxes and rows still raise on click. Title-bar Edit, minimise and close buttons are back on the right; icon left, title centred.

## Sound Browser 0.1.10 (2026-10-22)
- Fix: panels could not be dragged (the click-to-front hook added to the title bar, grip and icon displaced their drag-start click hook). Those now raise through the drag start only; body, buttons, text boxes and rows still raise on click. Title-bar Edit, minimise and close buttons are back on the right; icon left, title centred.

## World Event Timers 0.12.5 (2026-10-22)
- Fix: panels could not be dragged (the click-to-front hook added to the title bar, grip and icon displaced their drag-start click hook). Those now raise through the drag start only; body, buttons, text boxes and rows still raise on click. Title-bar Edit, minimise and close buttons are back on the right; icon left, title centred.

## Cursor Sprite 0.1.9 (2026-10-22)
- Click-to-front: a single click anywhere on the panel (title, body, buttons, rows, text boxes) brings it above other plugin panels; child clicks still run; raised once per visit so text-box focus is kept.

## Gear Preset Checker 0.11.19 (2026-10-22)
- Click-to-front: a single click anywhere on the panel (title, body, buttons, rows, text boxes) brings it above other plugin panels; child clicks still run; raised once per visit so text-box focus is kept.

## Slayer Task Tracker 0.11.15 (2026-10-22)
- Click-to-front: a single click anywhere on the panel (title, body, buttons, rows, text boxes) brings it above other plugin panels; child clicks still run; raised once per visit so text-box focus is kept.

## Sound Browser 0.1.9 (2026-10-22)
- Click-to-front: a single click anywhere on the panel (title, body, buttons, rows, text boxes) brings it above other plugin panels; child clicks still run; raised once per visit so text-box focus is kept.

## World Event Timers 0.12.4 (2026-10-22)
- Click-to-front: a single click anywhere on the panel (title, body, buttons, rows, text boxes) brings it above other plugin panels; child clicks still run; raised once per visit so text-box focus is kept.

## Cursor Sprite 0.1.8 (2026-10-22)
- Names show underscores as spaces (list, hover box, selection/preview). Search treats '_' and spaces alike (collapsed, case-insensitive); ID search unchanged; IDs untouched.

## Sound Browser 0.1.8 (2026-10-22)
- Names show underscores as spaces (list, hover box, selection/preview). Search treats '_' and spaces alike (collapsed, case-insensitive); ID search unchanged; IDs untouched.

## Cursor Sprite 0.1.7 (2026-10-22)
- Revert: text input restored to the original (pre-0.12.1) input code; the Setup/styling 'fixes' were the regression. Image re-raised twice a second (not every tick) and never while over the panel, so it cannot steal focus from the boxes. Keypad and filters kept.

## Gear Preset Checker 0.11.18 (2026-10-22)
- Revert: text input restored to the original (pre-0.12.1) input code; the Setup/styling 'fixes' were the regression.

## Slayer Task Tracker 0.11.14 (2026-10-22)
- Revert: text input restored to the original (pre-0.12.1) input code; the Setup/styling 'fixes' were the regression.

## Sound Browser 0.1.7 (2026-10-22)
- Revert: text input restored to the original (pre-0.12.1) input code; the Setup/styling 'fixes' were the regression.

## World Event Timers 0.12.3 (2026-10-22)
- Revert: text input restored to the original (pre-0.12.1) input code; the Setup/styling 'fixes' were the regression. Custom timer Minutes box no longer calls Setup (Save still validates 1-9999).

## Cursor Sprite 0.1.6 (2026-10-22)
- Fix: text boxes took no typing. Input fields now follow the docs order (stylesheet, content, Setup, size, pos), use a slim inner content margin (INPUT_DEFAULT's default margins left no text area at our 20-unit height), stay enabled/solid and sit in front of other panel parts.
- Typing-free fallback: Keypad (0-9, Del, Clear, Use) for the item ID; Letter filter (All, A-Z, 0-9) and ID jumps -1000/-100/+100/+1000 for the list.

## Gear Preset Checker 0.11.17 (2026-10-22)
- Fix: text boxes took no typing. Input fields now follow the docs order (stylesheet, content, Setup, size, pos), use a slim inner content margin (INPUT_DEFAULT's default margins left no text area at our 20-unit height), stay enabled/solid and sit in front of other panel parts.

## Slayer Task Tracker 0.11.13 (2026-10-22)
- Fix: text boxes took no typing. Input fields now follow the docs order (stylesheet, content, Setup, size, pos), use a slim inner content margin (INPUT_DEFAULT's default margins left no text area at our 20-unit height), stay enabled/solid and sit in front of other panel parts.

## Sound Browser 0.1.6 (2026-10-22)
- Fix: text boxes took no typing. Input fields now follow the docs order (stylesheet, content, Setup, size, pos), use a slim inner content margin (INPUT_DEFAULT's default margins left no text area at our 20-unit height), stay enabled/solid and sit in front of other panel parts.

## World Event Timers 0.12.2 (2026-10-22)
- Fix: text boxes took no typing. Input fields now follow the docs order (stylesheet, content, Setup, size, pos), use a slim inner content margin (INPUT_DEFAULT's default margins left no text area at our 20-unit height), stay enabled/solid and sit in front of other panel parts.

## Cursor Sprite 0.1.5 (2026-10-22)
- Image drawn over everything incl. own panel (MoveToFront each tick, last); hide-over-panel removed; nudged off the pointer only over the two input boxes.

## Cursor Sprite 0.1.4 (2026-10-22)
- Fix: image never shown (0.1.2 over-panel test used isMouseOver on the content layer/box, true outside the panel); now a strict panel-rectangle test in mouseUI units. Clamped size/opacity/position; NaN/huge position guard.

## Cursor Sprite 0.1.3 (2026-10-22)
- Position: On-point (default) / Offset (one arrow down-right, cursor-scale aware), in Edit and on the panel; replaces the offset list.

## Cursor Sprite 0.1.2 (2026-10-22)
- Fix: search/item ID boxes unclickable (overlay under the pointer took clicks); overlay hidden over the panel. Search on content change; Enter submits item ID.

## Cursor Sprite 0.1.1 (2026-10-22)
- Default: image drawn on top of the pointer (offset None, 32 px, 100%), anchored at the pointer tip / cursor hotspot.

## Cursor Sprite 0.1.0 (2026-10-22)
- New plugin: a sprite, item icon or game cursor image follows the mouse (click-through overlay, no permissions).
- Browse Sprites, Items or Cursors (Icon, ID, Name columns, search, Prev/Next); quick item ID box; preview, on/off, size, offset, opacity.
- Added to the Also by lists of the other four descriptions.


## 0.8.1
- World Event Timers: Alarm mode, per-event Alarm buttons, flashing rows, optional Sound toggle (off by default).

## 0.8.2
- World Event Timers: "Alarm mode: Off/On" button in its own row at the top of the panel.
- All plugins: removed hover tips; panels that were resized smaller earlier now grow so no rows are cut off.

## 0.8.3
- World Event Timers: removed the gray footer lines (Sinkhole Talsar hint and "Resets 00:00 UTC" note); panel is shorter.

## 0.9.0
- All: bevelled 9-slice RS-style buttons (falls back to the default style), 8px margins, 20px rows, 82% panel opacity, 1px dark text shadow, panels always fit their content height.
- World Event Timers: bells are now the alarm arm toggles (gold = armed, grey = off); per-row Alarm buttons removed; a ringing row flashes red until you click the row or its bell. Compact "Alarms / Sound" toggle row, 1px bronze rule under the column labels, narrower panel. Sound stays off by default.
- Slayer Task Tracker: values share one left edge, "195 / 195 left" counter with a thin progress bar, manual entry behind an Edit toggle, Source line only in debug builds.
- Gear Preset Checker: preset items shown as a compact 2-row icon grid with a green check / amber / red X badge on each; Save/Delete behind an Edit toggle.

## 0.9.1
- Gear Preset Checker: per-preset "Inv: On/Off" toggle in the Edit row. Off = only worn equipment is saved and checked; the header shows "worn only". Existing presets keep including the backpack.

## 0.10.0
- Fix: the Edit button did nothing. The title bar's drag handle covered it; the title is now kept clear of the right-hand buttons and Edit is raised above it.
- All: Edit (title bar) opens a settings section under the panel: panel opacity (60/82/100%), text size (S/M/L), compact layout (after reload), lock position (no drag/resize), title bar icon shown/hidden. Saved per plugin.
- World Event Timers: show/hide each event, starting-soon notice on/off, lead time 1/5/10 min, alarms on/off, alarm sound on/off (still off by default). Settings page with < > paging.
- Slayer Task Tracker: show/hide Master, Streak, Points, Level rows and the progress bar; manual task entry shown/hidden (hidden by default); best-master hint on/off.
- Gear Preset Checker: grid shows All or only Missing items, icon size S/M/L, amber (bank / not worn) badges on/off; name/Save/Delete/Inv controls stay in the Edit row.

## 0.10.1
- All: buttons back on the game's own button style; the 0.9.0 9-slice image override drew a white streak through the labels.
- All: titles shorten to initials (W.E.T., S.T.T., G.P.C.) when the panel is too narrow, and switch back when widened.

## 0.10.2
- All: text that doesn't fit its column is shortened with "..." instead of overlapping (labels, values, event names, times, task/master/preset names, settings labels, button labels). Re-fitted on build, while resizing, and twice a second.
- World Event Timers: time column has a fixed width so times keep priority over event names.

## 0.10.3
- All: text is shortened before it is shown, so the full text no longer flashes; the twice-a-second re-fit pass is gone (re-fits on build, resize, width cap and text-size change).
- All: hovering a shortened text shows its full text in a small box next to the pointer.
- World Event Timers: the Time left column is never shortened; it is sized to the widest time string and the panel cannot be resized narrower than it. Only event names shorten.
- World Event Timers: with Sound on, a ringing alarm repeats its sound back-to-back with no timeout until you click the bell or row, which stops sound and flashing together.

## 0.10.4
- World Event Timers: "Test" button in the Alarms row (shown when Alarms is on) rings the top visible event like a real alarm: red flash, and repeating sound if Sound is on, until you click its bell or row. Armed events are not changed.

## 0.10.5
- World Event Timers: alarm sound fixed. It replays on a simple 1-second timer (same play call as 0.8.1) until you click the bell or row, or turn Alarms off; the Test button uses the same path.

## 0.11.0
- All: no permissions in any plugin (Slayer's optional chatAccess removed). Contact email Dylan@quspace.agency.
- All: Edit > Window position > Reset; panels and icons are clamped on-screen at load, after a drag and after a resolution change; drag uses the window-pixel/interface ratio (high-DPI fix, untested at 4K/150%).
- All: hidden in the lobby/login screen, re-read on login. Version number shown in Edit. Edit footer: < 1/2 > paging and Done at bottom-right.
- All: titles left-aligned next to the icon (initials W.E.T./S.T.T./G.P.C. when narrow), opacity 60/82/92%, body buttons 20px, red #E04A3A, hover box wraps at 240px. Compact layout still applies after reload.
- World Event Timers: alarm sound rebuilt: one sound instance, stopped before each replay (fixes the 0.10.x silence where new instances piled up), built-in game chime with alarm.ogg fallback ("Alarm tone" in Edit), off by default. Alternating row backgrounds in the tables.
- Slayer Task Tracker: no chat reading. Streak is set with +1/-1 in Edit; the task total shows "~N" if the plugin started mid-task. ETA line ("~14 min left - 410/h"). Task-complete notice (optional built-in sound, off). Zero rows (streak, points) hidden.
- Gear Preset Checker: have/need quantities on stackables and supplies (red when short); bank hint in the status line; Export/Import preset tokens (sanitised, capped at 1500 chars).

## 0.11.1
- World Event Timers: alarm sound restored to the 0.8.1 playback call (alarm.ogg, volume 0.8, Start, replay every 2 s) with a single live instance; the 0.11.0 built-in game sound (id 885) is removed. The resource is loaded explicitly. Edit shows "Last sound: ok/nil/error" for diagnosis.
- Gear Preset Checker: have/need numbers are hidden by default and shown only while the mouse is over that icon; click an icon to pin its quantity (saved in the preset), click again to unpin. Short or missing items keep the red tint and cross badge.

## 0.11.2
- World Event Timers: alarm audio is the exact 0.8.1 code (commit 4d89e8e): alarm.ogg, volume 0.8, Play then Start, no explicit load, no stop-before-play, no instance tracking. It now plays once when an armed event starts and once per Test press (no repeat loop for now). Edit still shows "Last sound: ok/nil/error".
- World Event Timers: default width is computed from the longest title, event, rotation and time strings so nothing is shortened at the default text size; an existing narrower saved width is grown once (you can still shrink it).
- All: hover box shows the full original text (stored when it is shortened) instead of "...", word-wrapped at 240 px and never itself shortened.

## 0.11.3
- All: a bottom strip the height of the resize grip (26 px) is always reserved in the main view and in Edit, so no button or text sits under the grip. Content-sized panels include it in their height, the resize minimum includes it, and the Edit footer (< 1/2 > and Done) now sits above it.

## 0.11.4
- All: Edit footer is now "Prev 1/2 Next" and Done ("<" starts an RS text tag and was not drawn). Typed preset and task names have "<" and ">" removed for the same reason.
- All: title-bar buttons are never shortened. Edit/Done is sized from its measured label (minimum 34 px) and its space is reserved before the title is fitted, so the title switches to initials first.

## 0.11.5
- World Event Timers: when an armed event's active window ends, its alarm resets to inactive. Ringing, flashing and sound stop, and that event's bell goes back to off (saved), so it does not fire again. Events with no active window ring for 60 s. Clicking the row or bell still stops it early.
- World Event Timers: the alarm flash is one full-row overlay (#E04A3A at 50%) above the row background and below the text and bell.
- Slayer Task Tracker, Gear Preset Checker: version bump only.

## 0.11.6
- World Event Timers: sound rebuilt from scratch using the 0.6.0 method (a6014a7). It plays chime.ogg (restored byte-for-byte) with SCRIPT type, SFX bus and volume 0.6, calls audio.Play with no Start(), and plays once per alarm or Test press. There is one playSound() function and no loop.
- World Event Timers: new "Test B" button for the alternate 0.8.1 method (volume 0.8, Play then Start). The "Last sound" line shows which method ran (A or B) and its result.
- Slayer Task Tracker, Gear Preset Checker: version bump only.

## 0.11.7
- World Event Timers: sound rewritten from the RS3 audio docs. alarm.ogg is a new loud two-tone chime (Ogg Vorbis, 44.1 kHz mono, peak -1.4 dB). playSound() sets every playback field explicitly (SCRIPT, SFX bus, volume 1.0, 0 loops, 0 delay, non-spatial) and calls audio.Play with no Start(). The "Last sound" line shows the resource load result and whether the sound is playing. Test B is removed; Test now goes through the same alarm path as a real alarm (flash and sound).
- All: rectangles meant to be solid now set `fill = true`. ui.Rectangle defaults to an outline, which is why the alarm flash only showed at the row edges. Also fixed: WET row backgrounds, the title band, the grip square, the Slayer progress bar and the dividers.
- Dev only: separate `sound-test` plugin (not in release zips).

## 0.11.8
- World Event Timers: the alarm now plays exactly what sound-test button 5 played, the only one Dylan heard. That is a loud 48 kHz stereo Ogg on the MASTER bus (SCRIPT type, volume 1.0, not spatial, no Start()). Test still goes through the real alarm path, and the "Last sound" line is kept.
- Slayer Task Tracker, Gear Preset Checker: version bump only.

## Sound Browser 0.1.0 (new)
- New plugin, which replaces the dev-only sound-test. It lists every built-in sound, read at runtime from the id.Sound table, with an id.Sound.FromID scan as a fallback.
- Search by name or id, a favourites-only view, and 14 rows that are reused while paging (Top, -10, Prev, Next, +10).
- Click a name to play it; the result (ok/nil) appears next to it. Also: a bus selector, a volume selector (25-100%), Stop all, and favourites. Standard title bar, Edit settings and grip.

## Sound Browser 0.1.1
- Clicking a name while its sound is playing now stops that sound; otherwise it plays it. Each sound's instance is kept, and the result column shows playing, stopped, done (finished on its own) or nil. Other sounds keep playing, and Stop all still stops everything.

## 0.11.9
- World Event Timers: the alarm sound now loops until you click the row or bell, turn Alarms or Sound off, or the event ends (auto-reset). It uses the same file and settings as 0.11.8 (alarm.ogg, 48 kHz stereo, MASTER bus) and replays every 44 logic ticks (0.68 s clip + 0.2 s). Only one copy ever plays: the previous one is stopped before each replay. Test loops the same way until clicked.
- Slayer Task Tracker, Gear Preset Checker: version bump only.

## Sound Browser 0.1.2
- Added a header row (Sound, ID, Status, Fav) that uses the same column constants as the list rows. A subtle divider sits under it.
- Columns: 8 px padding, 8 px gaps, right-aligned ID (44 px), Status at 56 px, a 44 px Fav button, and a Sound column that fills the rest and ellipsizes (full name on hover).
- List rows are 20 px high (matching the other plugins), with filled alternating backgrounds.
- Controls: search and filter on line 1; Bus, Volume and Stop all on line 2. All gaps are 8 px, and the pager sits above the grip strip.

## 0.11.10
- World Event Timers: New Alarm volume setting in Edit (25%, 50%, 75%, 100%; default 75%). It applies to the alarm sound and Test; a change while ringing takes effect on the next replay.; Rotation times line up with the Time left column; rotation labels are a softer colour.; Armed bells are bright and unarmed bells are dim.; Fresh installs start with Alarms and Alarm sound off.
- Slayer Task Tracker: The kill count now has its own line under the task name. Long task names are shortened, with the full name on hover.
- Gear Preset Checker: The panel width follows the icon grid (7 columns by default).; Each icon sits on a subtle slot tile.
- All descriptions: added Jagex's current EULA statement; 'Also by this author' lists only the other plugins.

## Sound Browser 0.1.3
- Removed the bus selector; sounds play on the master bus.
- The ID column and header are right-aligned by measuring the text.
- Alternating row backgrounds and an opaque list area; a clearer divider under the header.
- Wider Sound column; Fav buttons are vertically centred.
- Pager is Prev, page, Next, centred.
- Status line reads e.g. '1-14 of 60,921 sounds'. A small green marker shows sounds that are playing.
- New gold-framed icon matching the other plugins.

## Gear Preset Checker 0.11.11
- Icon grid reflows live as the panel is resized: width sets columns, dragged height sets rows (one row by default).
- If not every icon fits, the last slot shows +N; hover the icons or +N for a cursor box with all hidden icons.

## Gear Preset Checker 0.11.12
- Fix: the grid was stuck at one row. Drag height now sets rows (height is no longer snapped back during the drag), width sets columns.
- Default shows equipped items plus a +N slot for inventory items; equipped icons come first.
- +N expands to show all items; Less collapses back. Expanded state and row count persist.

## Gear Preset Checker 0.11.13
- Icon order: main hand, off hand, body, legs, head, other equipped slots, then inventory. Applies to the grid and the hidden-icons hover box. Presets now save each worn item slot; older presets use the slot the item is worn in now.

## Gear Preset Checker 0.11.14
- Equipped only setting (On/Off, saved): grid shows worn equipment in slot order, then +N for all inventory items (hover +N for the box). Off keeps the resizable grid.

## 0.12.0 round (WET 0.12.0, Slayer 0.11.11, Gear 0.11.15, Sound Browser 0.1.4)
- All: title centred; close / minimise / Edit on the left of the title bar. Short titles (Presets, Timers, Tasks) only when the full title does not fit, then ellipsis + hover box. Collapsed fallback label uses the short title instead of initials.
- World Event Timers: custom timers (up to 8; name, minutes, repeat, alarm; edit/delete by clicking the row; saved). Alarm sound plays Repeat times (default 3), Repeat every (default 10 sec) instead of looping until clicked.

## 0.12.1
- World Event Timers: custom timer Name box now accepts typing (input fields were created without Setup, so their max length was 0).

## Gear 0.11.16 / Slayer 0.11.12 / Sound Browser 0.1.5
- Preset name, Monster and search boxes now accept typing (helpers.input now calls Setup with a max length).
