# Features merged from the old Unlimited edition (0.4.0)

RS Dev Tools has a single edition since 0.4.0. RS Dev Tools Unlimited is retired. These rows were Unlimited-only and now ship in the normal build. The status column shows what mod.io review is likely to say about each one, so decide before uploading.

Status: **Safe to promote** (could go into the public build now), **Needs review** (allowed on the hub in some form, needs a careful listing), **Would fail review** (keep it private).

| Feature | Where | Status | Rule it hits |
|---|---|---|---|
| Hide NPCs (EntityDraw returns false) | Inspect > World Render | Needs review | Prohibited list: "click-zone changes" and visual advantage. A similar entity hider is already listed on the hub, so this could be promoted with a clear listing. |
| Hide other players (you stay visible) | Inspect > World Render | Needs review | Same as above. Also watch "no info about other players" (it exports nothing). |
| Probe: walks every global table, including undocumented members | Debug > Probe | Would fail review | Use of undocumented functions; the code-review/AI policy expects documented APIs only. |
| Probe: Call () a selected function with no arguments (Confirm) | Debug > Probe | Would fail review | Calling undocumented functions could send actions to the game (Prohibited: automation / sending input). |
| Automation: console macros (presets: permission setup, reload, dev kit, saved macros; step delay, repeat x1/x3/x10, Stop) | Debug > Automation | Would fail review | Prohibited: automation. It only sends console commands after a click (never game input or typing), and destructive steps need Confirm, but repeated cheat sending is still automation. Dev worlds only. |
| Visual Overrides: hide ground items | Debug > Visual Overrides | Needs review | Hiding is allowed, but hiding ground items can read as a click-zone change or advantage. A clear listing is needed. |
| Visual Overrides: hide yourself | Debug > Visual Overrides | Safe to promote | Guidelines allow hiding player models entirely (no recolour). |
| Visual Overrides: NPC name filter (hide matching / show only matching) | Debug > Visual Overrides | Needs review | Same as Hide NPCs: an entity hider is listed on the hub; show-only can give a combat advantage. |
| Deep Probe: Deep scan walks _G and every reachable table/userdata, reads metatables, lists enums, gives arity hints and flags UNDOCUMENTED names; saved to PersistentDB rdt_probe (read only, calls nothing) | Debug > Deep Probe | Would fail review | Use of undocumented functions; reveals hidden API surface. |
| Deep Probe: metatable members of sample objects (PlayerEntity, NPC, loc, ground stack, Vector3, UI root, PersistentDB, Camera, World, Player), marked documented or not | Debug > Deep Probe | Would fail review | Use of undocumented functions (read only here, but publishing it encourages relying on them). |

Already in the normal build before 0.4.0: Event Payloads, Camera & World, Component Tree, Profiler, Shapes & Canvas, PersistentDB (own data, Confirm on delete), Permissions, API Coverage, Commands More info and per-argument dropdowns, adjustable columns; plus World Render position ring, path trail and sky beam (client-side ShapeList.DrawLine debug markers, off by default), and the Commands tab with Confirm on risky cheats.

## Added in 0.4.1

| Feature | Where | Status | Rule it hits |
|---|---|---|---|
| Right-click menu tile coords (MiniMenu:Add info entry, do-nothing action, swapped to lowest priority) | World (on by default; Settings toggle) | Needs review | Menu customisation. It adds an entry but never removes, hides or reorders the game's own entries relative to each other, and the entry sends nothing. List it as an info line. |
| Item hover info: Item Name (ID) by the pointer (read from the top MiniMenu entry) | World (on by default; Settings toggle) | Likely safe | Read-only display of the item already under the pointer, similar to the game's own tooltip. |
