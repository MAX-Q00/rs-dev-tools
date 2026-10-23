# RS3 Plugin Dev FAQ - from the RuneScape Plugin Portal Discord

Source for rs-dev-tools/faq_data.lua (built by release/build_faq.py).
Collected read-only from the RuneScape Plugin Portal Discord, Oct 19-23, 2026.
Nothing was posted, reacted to, or joined.

Format: each "### N. title" is one question. Each "- **Post:** ROLE | user | tag | date"
line starts one post in the conversation, in order. ROLE is Q (question or
follow-up question) or A (reply). tag is "Jagex staff", "community" or empty.
Indented "  - " lines under a post are separate lines of that post.
Text in backticks goes to the code block (Copy button). "Unknown user" means the
poster's name was not recorded in the research notes; no name is guessed.

---
## A. plugin.json, permissions, reloading, debugging

### 1. requiredPermissions isn't working (trackingAccess, httpAccess, chatAccess)
- **Frequency:** Often (4+ askers on Oct 19, again Oct 20). Also a known issue.
- **Where / when:** #plugin-support, Oct 19; #api-launch-known-issues, Oct 19.
- **Post:** Q | Unknown user | | Oct 19
  - requiredPermissions in plugin.json doesn't seem to do anything (trackingAccess, httpAccess, chatAccess). The permission is never granted.
- **Post:** A | Zippilipy | community | Oct 19
  - Leave requiredPermissions empty and list the permission under optionalPermissions instead, then grant it from the console:
  - `"requiredPermissions": [ ], "optionalPermissions": [ "trackingAccess" ],`
- **Post:** A | Friendliness | community | Oct 19
  - Known issue: "requiredPermissions" doesn't currently work. If you need something like chatAccess, put it in "optionalPermissions".

### 2. How do I grant a permission such as httpAccess in dev? `ppe` prints nothing.
- **Frequency:** Several (Oct 19, Oct 19 evening).
- **Where / when:** #plugin-support, Oct 19.
- **Post:** Q | Unknown user | | Oct 19
  - How do I grant a permission such as httpAccess in dev? Running ppe prints nothing.
- **Post:** A | Ceren | community | Oct 19
  - Run prf (or restart the client) after editing the manifest, then run these in order:
  - `ppr <pluginname>`
  - `ppe <pluginname> httpAccess`
  - `prl <pluginname>`
- **Post:** A | Unknown user | community | Oct 19
  - prl depends on what the plugin needs, but it's a good habit. ppr is needed to set up the permissions until the permission pop-ups are live.
- **Post:** A | Unknown user | community | Oct 19
  - A permissions prompt is coming in the future, which will remove the need for ppr and ppe in the console.

### 3. How do I stop re-typing the permission commands every reload?
- **Frequency:** Once.
- **Where / when:** #plugin-support, Oct 19.
- **Post:** Q | Unknown user | | Oct 19
  - Is there a way to stop re-typing the permission commands every time I reload?
- **Post:** A | Zippilipy | community | Oct 19
  - Put them in main.lua so they run on each load (dev only):
  - `ExecuteConsoleCommand("ppr <pluginname>")`
  - `ExecuteConsoleCommand("ppe <pluginname> trackingAccess")`

### 4. plugin.json changes aren't picked up / permissions still failing
- **Frequency:** Several.
- **Where / when:** #plugin-support, Oct 19; Oct 19 evening.
- **Post:** Q | Unknown user | | Oct 19
  - I changed plugin.json but nothing changed and permissions still fail.
- **Post:** A | Unknown user | community | Oct 19
  - Run `prf` if you change the plugin manifest at all. Some people restart the client instead.

### 5. Manifest won't load because of a JSON syntax error
- **Frequency:** Once, but a common cause.
- **Where / when:** #plugin-support, Oct 19, 10:31 AM.
- **Post:** Q | Unknown user | | Oct 19
  - My manifest won't load. It ends with: "urls": { "discord" : "https://discord.com" }, }
- **Post:** A | JosTheFarmer | community | Oct 19
  - Remove the last comma after urls. JSON does not like trailing commas.

### 6. Can I reload my plugin without restarting the client? What do `prf` and `prl` do?
- **Frequency:** Often.
- **Where / when:** #general-technical, Oct 19; #plugin-support, Oct 19.
- **Post:** Q | Unknown user | | Oct 19
  - Can I reload my plugin without restarting the client? What do prf and prl do?
- **Post:** A | Unknown user | community | Oct 19
  - Just save the file, run `prl <pluginname>` and it reloads. Double-clicking the plugin's checkbox in the plugin menu also reloads it.
  - Use `prf` after manifest changes.
  - Up arrow in the console recalls earlier commands. Open the console with Alt + ` (backtick).
  - `displayfps` shows FPS for performance testing.

### 7. Is there an event for the plugin enable/disable button? I need to clean up when it's disabled.
- **Frequency:** Once.
- **Where / when:** #general-technical, Oct 20.
- **Post:** Q | Unknown user | | Oct 20
  - Is there an event for the plugin enable/disable button? I need to clean up when it's disabled.
- **Post:** A | Unknown user | community | Oct 20
  - The button only runs the startup and shutdown lifecycle, so clean up in `PluginShutdown`.
  - Docs: https://developer.runescape.com/rs/core/clientoptions.html?h=pluginShutdown#example
  - Example: turn login-screen music off while the plugin is active and restore it on shutdown.

### 8. Dependency error: "Failed to resolve dependencies. Missing dependency rsprite for plugin"
- **Frequency:** Once.
- **Where / when:** #plugin-support, Oct 21.
- **Post:** Q | Elling | community | Oct 21
  - Getting "Failed to resolve dependencies. Missing dependency rsprite for plugin".
- **Post:** A | Pavy | community | Oct 21
  - Check the manifest structure: https://developer.runescape.com/rs/structure.html#manifest. Also make sure you used the rsprite release, not the whole repo.
- **Post:** Q | Elling | community | Oct 21
  - That didn't help.
- **Post:** A | Grynjolf | community | Oct 21
  - Pointed out the manifest is not a package.json (fields from npm don't apply). No definitive fix was posted.

### 9. Can I depend on another plugin by name, or only by mod.io ID?
- **Frequency:** Several (zyklib thread).
- **Where / when:** #general-technical, Oct 20; #dev-questions, Oct 21.
- **Post:** Q | Unknown user | | Oct 20
  - Can I depend on another plugin by name, or only by its mod.io ID?
- **Post:** A | Unknown user | community | Oct 20
  - A string name works only for local dev, with the plugin in your plugins folder: `{ "zyklib": "zyklib" }`
  - For submission it must be the mod.io ID: `{ "zyklib": 123456 }`
  - Dependencies are globals named by the dependency key, so you don't require them.
- **Post:** A | Grynjolf | community | Oct 21
  - Local dependencies work locally only; mod.io dependencies work both locally and live. You access them by the key name you gave.

### 10. Does contactEmailAddress have to be in plugin.json? Can I keep it out of the public listing?
- **Frequency:** Once.
- **Where / when:** #general-technical, Oct 21.
- **Post:** Q | Aerrek | community | Oct 21
  - Can contactEmailAddress in plugin.json be left out? I'd like to keep my email out of the public listing.
- **Post:** A | TheJoshJ | community | Oct 21
  - It's mostly used if you go AWOL and Jagex needs you to update or fix something. I made a new email just for plugin things and forward it.
  - The docs say it is a legal requirement, and recommend a different address from the one you use for mod.io. Not confirmed by staff whether it's shown publicly.

### 11. My plugin turns itself off when I lobby, change world or log in. How do I test re-enable on login?
- **Frequency:** Several (also Job Gauges disabling on login).
- **Where / when:** #plugin-support, Oct 19-22.
- **Post:** Q | Wildefires | community | Oct 21
  - My plugin gets turned off when I lobby and re-enter the game. Is there a way to keep it enabled?
- **Post:** A | Grynjolf | community | Oct 22
  - Not in dev. Only plugins installed through mod.io re-enable on login.
- **Post:** Q | ☠PIO☠ | community | Oct 21
  - Anyone know why Job Gauges is disabled every time you log in?
- **Post:** A | Ceren | community | Oct 21
  - A bug with the equipped ammo sprite causes an error on first load, so the plugin doesn't enable. Fixed in an upcoming version.

### 12. Dev client and main client share installed plugins and settings. Is there a fix?
- **Frequency:** Several.
- **Where / when:** #plugin-support, Oct 19-23; #general-technical, Oct 21.
- **Post:** Q | Unknown user | | Oct 19
  - My dev client and main client share the same installed plugins and settings. Is there a fix?
- **Post:** A | Unknown user | community | Oct 19
  - No fix yet. Hopefully a solution will come eventually.
- **Post:** Q | Mental Demon | community | Oct 21
  - My two accounts share the same tile markers and menu swaps. Can settings be per account?
- **Post:** A | Sudo Bash | community | Oct 21
  - That's up to each plugin's developer. Early plugins were built around one shared set of settings or preset import and export. Settings are stored locally.
- **Post:** A | Grynjolf | community | Oct 21
  - Plugins can request permission to an account identifier (`Player.GetTrackingID()`, needs trackingAccess) and use it to save settings per account.
- **Post:** Q | Kazter | community | Oct 23
  - Manually updating plugins while running several accounts at once made all the other clients crash.
- **Post:** A | Mod Jewel | Jagex staff | Oct 23
  - Plugin files are shared between all clients, but this is an important issue, so thanks for raising it.

### 42. Can a plugin have more than one .lua file?
- **Frequency:** Once.
- **Where / when:** #dev-questions, Oct 23.
- **Post:** Q | 4D Oranges | community | Oct 23
  - Is a plugin allowed to have more than one .lua file? I want to move my constants to a separate file and import them in main.lua.
- **Post:** A | Astrect | community | Oct 23
  - Yes, several plugins already do this. Example layout: https://codeberg.org/QuestHelper/QuestHelper/src/branch/main/src

## B. UI and PrettyUI

### 13. Error: "Failed to Create Layer (category=0 ID=4096) - invalid dynamic ID, expected a value between 0 and 4096"
- **Frequency:** Several (noted as seen before).
- **Where / when:** #general-technical, Oct 21.
- **Post:** Q | Siesta | community | Oct 21
  - Getting "Failed to create Layer (category=0 ID=4096) - invalid dynamic ID" after creating lots of sprites and tooltips with PrettyUI and running prl often.
- **Post:** A | Unknown user | community | Oct 21
  - Components aren't being cleaned up. See "Valid ID Ranges": https://developer.runescape.com/rs/ui/index.html?h=4096#components
  - Call `layer:DeleteAll()` before a rebuild.
  - The game destroys components your plugin creates on reload or shutdown, but not ones PrettyUI creates. Make your own empty layer, pass it to PrettyUI as the root, and call `mainWindow:Destroy()` in `PluginShutdown`.
  - Prefer `TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP` or `TOPLEVEL_V2__PLUGIN_BUILD_LAYER_BOTTOM` over `TOPLEVEL_V2__GAME_AREA`.
- **Post:** A | Siesta | community | Oct 21
  - Fixed it by destroying the SimpleView in PluginShutdown.

### 14. How do I create a headerless group box? `SetHeaderLayout(0,0,0,0,0)` still shows a header.
- **Frequency:** Several (3 reports incl. at 1440p, so not a resolution issue).
- **Where / when:** #plugin-support, Oct 19.
- **Post:** Q | Unknown user | | Oct 19
  - How do I make a group box with no header? `SetHeaderLayout(0,0,0,0,0)` still shows one.
- **Post:** A | Unknown user | community | Oct 19
  - Same here, also at 1440p. Looks like an API or tutorial issue; no fix posted.
- **Post:** Q | Unknown user | | Oct 19
  - The tutorial uses strayDogName in one place and strayDogConfig.name in another. Which is right?
- **Post:** A | Unknown user | community | Oct 19
  - Probably just a mistake, no reason not to use either.

### 15. Drag/move and drag-and-drop break on 2K/4K/QHD or high-DPI monitors (Job Gauges)
- **Frequency:** Several.
- **Where / when:** #plugin-support, Oct 19; #general-technical, Oct 22.
- **Post:** Q | Unknown user | | Oct 19
  - Moving Job Gauges and drag-and-drop don't follow the mouse on my 2K/4K monitor.
- **Post:** A | Unknown user | community | Oct 22
  - Reported coordinates scale by 2x or 4x pixel density, so components don't follow the mouse 1:1. PrettyUI fixed this: look at its `InterfaceMouse`, which works out how far something moved once dragging starts.
- **Post:** A | TheJoshJ | community | Oct 22
  - My workaround: track the hovered component at drop instead of using the native drag start and stop positions.

### 16. Can I auto-focus a text input after a hotkey press?
- **Frequency:** Once.
- **Where / when:** #general-technical, Oct 22.
- **Post:** Q | Unknown user | | Oct 22
  - Can I focus a text input automatically after a hotkey press?
- **Post:** A | Unknown user | community | Oct 22
  - Not possible right now. I have a feature request in.

### 17. What is the "value" param for PrettyUI CheckboxButton?
- **Frequency:** Several.
- **Where / when:** #plugin-support, Oct 20-21.
- **Post:** Q | 4D Oranges | community | Oct 21
  - Can someone explain the purpose of the "value" parameter for a PrettyUI CheckboxButton?
- **Post:** A | Polar | community | Oct 21
  - It's the value you receive in the changedValue variable, basically a label for the checkbox, so when several checkboxes share a callback you know which one changed.
- **Post:** A | Sudo Bash | community | Oct 21
  - Instead of a plain true/false: if a value is set it is passed when ticked, otherwise you read its selected state. It's mostly for defaults, and lets a group act like radio buttons that allow more than one choice.

### 18. Can I make a PrettyUI window transparent but still movable (show only sprites)?
- **Frequency:** Once.
- **Where / when:** #plugin-support, Oct 22.
- **Post:** Q | Elling | community | Oct 22
  - Can I make a PrettyUI window transparent but keep a small point to move it, and only show sprites?
- **Post:** A | Grynjolf | community | Oct 22
  - You can grab the PrettyUI window's root prop and modify it. Or use native sprites in a native panel.
- **Post:** A | draconis imp | community | Oct 22
  - If all you care about is sprites, you could use rsprite.

### 19. ui.Interfaces:GetComponent() returns the previous clue-scroll text, not the current text
- **Frequency:** Once, long thread.
- **Where / when:** #general-technical, Oct 21.
- **Post:** Q | Siesta | community | Oct 21
  - Why does ui.Interfaces:GetComponent() not get the current value when reading the clue scroll reward UI? It shows the previous value. I'm reading it in InventoryAdded.
- **Post:** A | Polar | community | Oct 21
  - The inventory update fires before the server sets the text. Workaround:
  - 1. In InventoryAdded / InventoryUpdated, set a flag.
  - 2. Subscribe to the modal's `ui.Hook.ONSUBCHANGE` and mark the interface ready there.
  - 3. On the next `Event.Logic` tick, read `id.Component.TRAIL_REWARD__CURRENT_VALUE` and `Inventory.Find(id.Inv.TRAIL_REWARDINV)`.
- **Post:** A | Siesta | community | Oct 21
  - It did work.
- **Post:** A | TheJoshJ | community | Oct 21
  - For prices, a GE price library gives more accurate values.

### 20. Why are chat event fields read-only? Can I modify chat?
- **Frequency:** Once.
- **Where / when:** #general-technical, Oct 19.
- **Post:** Q | Unknown user | | Oct 19
  - Why are chat event fields read-only? Can I modify chat messages?
- **Post:** A | Unknown user | community | Oct 19
  - Chat isn't writable. You can hide messages and re-post them through the plugin chat type, which needs `chatAccess`.
  - Setting content to an empty string leaves a blank line, and nil doesn't work.

## C. API usage and events

### 21. Two listeners on Event.NPCEntityAdded: only the first gets usable data (isValid=false, name nil)
- **Frequency:** Once, with multiple confirmers.
- **Where / when:** #plugin-support, Oct 20.
- **Post:** Q | Unknown user | | Oct 20
  - With two listeners on `Event.NPCEntityAdded`, only the first gets usable data; the second sees isValid=false and name nil.
- **Post:** A | Unknown user | community | Oct 20
  - Try returning a value from the handler.
- **Post:** A | Unknown user | community | Oct 20
  - Most events don't care about return values. EntityDraw docs require one, and the docs should say for the others. Reported in game as a bug; not resolved.

### 22. No `os` library. How do I time something (stopwatch)?
- **Frequency:** Once.
- **Where / when:** #general-technical, Oct 22.
- **Post:** Q | Unknown user | | Oct 22
  - There's no os library. How do I time something, like a stopwatch?
- **Post:** A | Friendliness | community | Oct 22
  - There's no os at the moment, so you'd need to use the logic tick (`Event.Logic`).

### 23. Property named `valid` in the docs is actually `isValid`
- **Frequency:** Once (docs bug).
- **Where / when:** #plugin-support, Oct 19.
- **Post:** Q | Unknown user | | Oct 19
  - The inventory docs say the property is valid, but that's nil. Is it something else?
- **Post:** A | Unknown user | community | Oct 19
  - It's `isValid`; the docs are wrong (https://developer.runescape.com/rs/game/inventory.html#properties). Report it as a documentation issue.

### 24. What the API can't do yet (feature-gap questions)
- **Frequency:** Often.
- **Where / when:** #plugin-support / #general-technical, Oct 19-22.
- **Post:** Q | Unknown user | | Oct 19-22
  - Several people asked whether the API can do things like swap animations, read drop tables, read gizmo perks, detect Rockertunities or read walls.
- **Post:** A | Unknown user | community | Oct 19-22
  - Player animations can't be swapped yet.
  - Drop tables are server-side; use wiki data in a static Lua file. There's no direct kill-to-drop link.
  - Item perks on gizmos and augmented gear aren't exposed.
  - `LocList.All()` returns only scenery, not walls, roofs or ground decorations. Collision data isn't reliably exposed.
  - Friends and FC lists are only readable while their window is open.
  - Action bars can't be changed (moving or resizing click zones is restricted). Menu Entry Swapper limits are intentional: no Buy All, no default left-click Teleport or Drop.
- **Post:** A | Kris | community | Oct 22
  - Rockertunity spawns aren't detectable: the sparkle is spotanim 7165, which plays over every rock, and spotanim support in the API is incomplete.

### 25. Is there Lua IntelliSense / SDK support in VS Code?
- **Frequency:** Several.
- **Where / when:** #plugin-support, Oct 19-20.
- **Post:** Q | Unknown user | | Oct 19
  - Is there Lua IntelliSense or an SDK for VS Code?
- **Post:** A | Unknown user | community | Oct 19-20
  - Use the community stubs: https://github.com/FriendlyDevelopment/runescape-api-stubs/ with a Lua extension (LuaLS).
  - Put a .luarc.json in the opened plugin folder (adjust the stub path), and open the plugin's folder as the workspace:
  - `{ "workspace.library": [ "../runescape-api-stubs/types.lua", "../runescape-api-stubs/generated/" ], "workspace.checkThirdParty": false }`

### 26. Is there a base64 / shared utility library? How do I share libraries between plugins?
- **Frequency:** Several.
- **Where / when:** #general-technical, Oct 20-21.
- **Post:** Q | Unknown user | | Oct 20
  - Is there a base64 or shared utility library? How do I share code between plugins?
- **Post:** A | Zyklop Marco | community | Oct 20
  - zyklib (https://codeberg.org/ZyklopMarco/runescape-api-zyklib, docs at zyklib.readthedocs.io) is in review.
  - Copying it into your plugin is safer than a dynamic dependency, because a dynamic dependency can never break backward compatibility. See #9 for how to depend on it.
  - Note (Oct 21): zyklib.async can crash the client; that bug is waiting on a Jagex fix.

### 27. Which components are allowed in the API vs. cheat commands (getVar, getvarc)?
- **Frequency:** Several.
- **Where / when:** #general-technical, Oct 20-22.
- **Post:** Q | Unknown user | | Oct 20
  - Which things are allowed through the API versus cheat commands like getVar and getvarc?
- **Post:** A | Unknown user | community | Oct 20
  - Cheats don't work on live (https://developer.runescape.com/rs/cheats.html?h=getVar#getvar).
  - Reading hidden client information (for example herb patch state when you're not nearby) wouldn't be approved. Reading loc data is allowed.
- **Post:** A | Friendliness | community | Oct 22
  - `!getvarc` never worked.

### 41. Messages added with Chat.AddMessage disappear when a friend logs in or out
- **Frequency:** Once.
- **Where / when:** #plugin-support, Oct 21.
- **Post:** Q | 4D Oranges | community | Oct 21
  - Messages I add with `Chat.AddMessage` disappear when a friend logs in or out.
- **Post:** A | Friendliness | community | Oct 21
  - They were aware of it, I think, but not sure if it's intended.
- **Post:** A | Grynjolf | community | Oct 21
  - Haven't heard of that. (No fix found; re-add messages that must stay visible.)

### 43. How do I link a Construction furniture item to its object (loc), e.g. Trellis?
- **Frequency:** Once.
- **Where / when:** #dev-questions, Oct 21.
- **Post:** Q | laundrymat [BUN] | community | Oct 21
  - How do I map a Construction furniture item to its loc/config, for example Trellis?
- **Post:** A | Polar, micha, Kris | community | Oct 21
  - The link is a DBRow: find the row in the construction_house_furniture table whose column 4 is the item, then read column 2 for the loc. The loc also links back to the row.
  - Column numbers aren't stable across updates; the docs example uses plain numbers: `config.DBRow.INVENT_PERK_LOOTING:GetColumnValues(2)`
  - Docs: https://developer.runescape.com/rs/game/config/dbrowtype.html

### 44. What is DBTableType for, if I already have DBRows?
- **Frequency:** Once.
- **Where / when:** #dev-questions, Oct 21, 9:39 PM.
- **Post:** Q | laundrymat [BUN] | community | Oct 21
  - What's the point of DBTableType?
- **Post:** A | Polar | community | Oct 21
  - A DBTable defines the structure; DBRows are the entries in it. You only need DBRows unless you want default values for columns a row doesn't set, or the column types.

## D. Sound

### 28. Sound alert volume below 1 is rounded and the sound doesn't play
- **Frequency:** Once.
- **Where / when:** #plugin-support, Oct 19-20; #general-technical, Oct 20.
- **Post:** Q | Unknown user | | Oct 19
  - For sound alerts, any float value below 1 seems to be rounded down, which disables the sound, so it only works at 1.
- **Post:** A | Unknown user | community | Oct 20
  - No official fix. Audio sliders live in `game.options`; a sample was shared that mutes login-screen music while a plugin runs.

## E. Packaging, mod.io, submission, directory

### 29. How do I register my plugin / reserve its name and mod.io ID in the directory?
- **Frequency:** Once (pinned how-to).
- **Where / when:** #plugin-directory-how-to, Oct 19.
- **Post:** Q | Unknown user | | Oct 19
  - How do I register my plugin and reserve its name and mod.io ID?
- **Post:** A | Friendlybot | community | Oct 19
  - Pinned how-to. Signing up reserves the plugin name and mod.io ID for you:
  - `/plugin signup` adds your plugin to the directory.
  - `/plugin team add` adds a team member. `/plugin modio set` sets your mod.io ID.
  - Also: /plugin rename, /plugin transfer, /plugin list, /plugin delete, /plugin modio remove, /plugin team leave, /plugin team remove.

### 30. mod.io / Plugin Hub activation code email never arrives
- **Frequency:** Several (2+ users; one on a 4th attempt).
- **Where / when:** #general-technical, Oct 19-21; #api-launch-known-issues, Oct 19.
- **Post:** Q | Numbers | community | Oct 21
  - I'm not receiving the authentication email.
- **Post:** A | Friendliness | community | Oct 21
  - Try again, or try a different mail provider. It doesn't have to be the email on your RS account.
- **Post:** A | Numbers | community | Oct 21
  - Another email worked straight away.
- **Post:** A | Mod Light | Jagex staff | Oct 19
  - Known issue: using an email with a + sign can cause the Plugin Hub to crash.

### 31. How do I test a plugin before it's on mod.io? Can plugin info be user-configured (e.g. self-hosted API base URL)?
- **Frequency:** Once (self-host); the other is covered in #9.
- **Where / when:** #general-technical, Oct 20; #plugin-support, Oct 19.
- **Post:** Q | Unknown user | | Oct 20
  - Can users configure plugin info, like a self-hosted API base URL?
- **Post:** A | Unknown user | community | Oct 20
  - Probably not allowed, but that's one for Mod Jewel. I use a fixed base URL in the manifest.
- **Post:** A | Unknown user | community | Oct 19
  - Submitted plugins and plugin updates wait for Jagex review.

### 32. AI / LLM policy: can LLMs be given the docs?
- **Frequency:** Several (many participants).
- **Where / when:** #plugin-support, Oct 19; #api-updates, Oct 20.
- **Post:** Q | Unknown user | | Oct 19
  - The docs say not to give them to an AI. Is that still the rule?
- **Post:** A | Grynjolf | community | Oct 19
  - That might be a holdover from before we went public. Policy will be updated.
- **Post:** A | Mod Jewel | Jagex staff | Oct 20
  - The restriction on the official docs was removed: official API docs and examples are OK. Don't upload code or docs you aren't licensed to, including other developers' plugins without their permission.

### 45. Will plugins that store data on a shared server be approved?
- **Frequency:** Once.
- **Where / when:** #dev-questions, Oct 21, 9:30 PM.
- **Post:** Q | butter | community | Oct 21
  - What's the status on getting plugins accepted that use a shared server to store data?
- **Post:** A | TheJoshJ | community | Oct 21
  - They haven't announced a plan yet; still working out some kinks.
- **Post:** A | Grynjolf | community | Oct 21
  - I don't see why not. You'd probably be subject to this: https://developer.runescape.com/rs/submission/adequacy.html (not an official answer).

## F. Cheats and the dev environment

### 33. Cheat commands (!give, teleport, getvar) don't work on dev/beta worlds
- **Frequency:** Often (6+).
- **Where / when:** #api-launch-known-issues, Oct 19; #plugin-support, #general-technical, Oct 19-22.
- **Post:** Q | Unknown user | | Oct 19
  - Cheat commands like !give, teleport and getvar don't work on the dev world.
- **Post:** A | Mod Light | Jagex staff | Oct 19
  - Known issue: cheat commands on developer worlds are not working as intended. We're investigating (no ETA).
- **Post:** A | Unknown user | community | Oct 19-22
  - The docs warn cheats are logged and abuse can lead to bans: don't spawn hidden or future items or spam items. When working, `!setgroupironman 1` sets the account type for testing a shared bank.
- **Post:** A | Polar | community | Oct 22
  - Shared a dev script that prints the cheat commands needed to complete an achievement.

### 34. Beta client won't launch from the news-post link / can't log in
- **Frequency:** Several.
- **Where / when:** #plugin-support, #general-technical, Oct 19-20.
- **Post:** Q | Unknown user | | Oct 19
  - The beta client won't launch from the news-post link.
- **Post:** A | Unknown user | community | Oct 19
  - That link is broken; launch the beta from the docs link instead. To go back to live, close the game and launcher and relaunch normally.

## G. Crashes and known issues

### 35. Game crashes after installing/updating plugins (Oct 21)
- **Frequency:** Often.
- **Where / when:** #api-launch-known-issues, Oct 21; #plugin-support, Oct 21-23.
- **Post:** Q | Laidback LT | community | Oct 21
  - When I click Install on any plugin my game just crashes.
- **Post:** A | Rcm37 | community | Oct 21
  - Really bad timing: they're having issues with plugins right now and are working on a fix.
- **Post:** A | Mod Light | Jagex staff | Oct 21
  - A hotfix was reverted. If you updated plugins between 15:00 and 16:00 BST, delete all folders (for example 6398181) under `C:\ProgramData\Jagex\RuneScape\plugins` and reinstall. Settings are kept. On other systems use the plugins folder of your Jagex cache.
- **Post:** Q | Sector | community | Oct 23
  - All my installed plugins have vanished. Is there a way to force a refresh of the hub or uninstall?
- **Post:** A | Mod Jewel | Jagex staff | Oct 23
  - Go to C:\ProgramData\Jagex\RuneScape\plugins and delete all the folders, which uninstalls all plugins, then reinstall. Saved settings stay.
- **Post:** A | Sector | community | Oct 23
  - That solved it, thank you!

### 36. Tile Markers: preset limits and crashes
- **Frequency:** Often (5+).
- **Where / when:** #plugin-support, Oct 19-21; #api-launch-known-issues, Oct 19-21.
- **Post:** Q | Zac | community | Oct 21
  - Is there a tile pack limit? Importing tile packs won't work unless I delete some.
- **Post:** A | Grynjolf | community | Oct 21
  - 200 highlighted tiles in total, yes. Already expanded in a version that isn't released yet.
- **Post:** Q | Dracyn | community | Oct 21
  - What's the max tiles for agility presets?
- **Post:** A | Grynjolf | community | Oct 21
  - Yes, 200. The Agility Helper would be enough, wouldn't it?
- **Post:** A | Unknown user | community | Oct 19-20
  - Import strings have a size cap, so split big imports into smaller chunks. The shapes API also adds client memory over time.
- **Post:** A | Mod Light | Jagex staff | Oct 19
  - Known issue: some Tilemarkers preset names (the img text tag) can crash the client. Fixed Oct 21.

### 37. FPS loss and lag with plugins (e.g. Entity Hider, MES)
- **Frequency:** Several.
- **Where / when:** #api-launch-known-issues, Oct 20; #plugin-support, Oct 19.
- **Post:** Q | Unknown user | | Oct 19
  - Plugins are dropping my FPS and making the game lag.
- **Post:** A | Mod Light | Jagex staff | Oct 20
  - Known issue: some plugins are causing FPS to decrease. A hotfix is planned.
- **Post:** A | Unknown user | community | Oct 19
  - Test with `displayfps`, with and without the plugin and with players hidden. In one case hiding entities with Entity Hider fixed the lag from Menu Entry Swapper.

### 38. MiniMenu / left-click problems, Menu Entry Swapper limits
- **Frequency:** Several.
- **Where / when:** #api-launch-known-issues, Oct 19-20.
- **Post:** Q | Unknown user | | Oct 19
  - Left-click options are wrong with plugins on, and Menu Entry Swapper can't swap some options.
- **Post:** A | Mod Light | Jagex staff | Oct 20
  - Known issue: several left-click issues with the MiniMenu. Menu Entry Swapper limits are an API restriction by design (see #24); a fix is planned with no ETA.

### 39. Debug Menu plugin sent hit commands to every NPC
- **Frequency:** Once.
- **Where / when:** #plugin-support, Oct 21.
- **Post:** Q | Kogasa | community | Oct 21
  - The Debug Menu plugin started sending hit commands to every NPC around me.
- **Post:** A | Friendliness | community | Oct 21
  - Old bug, it defaulted to on for some reason. Just pushed the update.

### 40. Where's plugin X? Mobile? Release cadence?
- **Frequency:** Often.
- **Where / when:** #faq, Oct 19; #plugin-support, Oct 22.
- **Post:** Q | Unknown user | | Oct 19
  - Where's plugin X? Are plugins on mobile? How often do new plugins come out?
- **Post:** A | Mod Light | Jagex staff | Oct 19
  - More plugins are in moderation (Clue Trainer, Ground Items and others) and will come in batches over the coming weeks; cadence to be confirmed. Plugins aren't on mobile yet.
- **Post:** Q | Hiraku Hiro | community | Oct 22
  - Can we look into equipment setups?
- **Post:** A | Friendliness | community | Oct 22
  - The Bank Utils plugin (in development-resources) will have that, compatible with PVME's preset maker.
- **Post:** Q | SWITCHED | community | Oct 22
  - Is there a loot tracker that plays a sound for a specific drop?
- **Post:** A | wandernaut | community | Oct 22
  - The Watchdog plugin should let you set that up.
- **Post:** Q | Doodel | community | Oct 22
  - Is there a way to replay Broken Home with Quest Helper?
- **Post:** A | Aaron | community | Oct 22
  - Not currently, but a dev said on stream that if you just start it again the log updates. They're aware of the request.
