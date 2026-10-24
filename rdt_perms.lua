--[[ rdt_perms.lua (0.5.3) Permissions tab (Plugins), 6 sub-tabs:
  Run, Status, Permissions, Commands, Manifest, FAQ/Review.
  To add a sub-tab: append { name, tip, view } to SUBS (controls take a
  show function that checks S.sub). Console commands run through
  ExecuteConsoleCommand only on a click (Run / Confirm / Grant); ppd and
  poff ask for Confirm. Sanctioned dev console commands only. Nothing here
  runs per frame except the Grant sequence step (one command per 0.5 s while
  it runs). Plugin.HasPermission reports only this plugin; no API lists
  plugins or reads another plugin's permissions, so the plugin list is this
  suite plus a typed name. ]]
return function(ctx)
    local H = ctx.H
    local UNV = " (unverified)"
    local PERMS = {
        { "httpAccess", "Web requests (HTTPRequest) only to the base URLs listed in plugin.json \"urls\"", "HTTPRequest calls fail or are refused" },
        { "chatAccess", "Chat.AddMessage and the Event.ChatMessage event", "no ChatMessage events arrive; Chat.AddMessage does nothing" },
        { "trackingAccess", "Player.GetTrackingID()", "Player.GetTrackingID() returns nil" },
    }
    -- short, full name, args in order, what it does, needs Confirm
    local CMDS = {
        { "ppr", "plugins_permissions_request", { "PLUGIN" }, "Request the permissions plugin.json lists", false },
        { "ppe", "plugins_permissions_enable", { "PLUGIN", "PERMISSION" }, "Grant one permission (prints nothing when it works)", false },
        { "ppd", "plugins_permissions_disable", { "PLUGIN", "PERMISSION" }, "Revoke one permission", true },
        { "prl", "plugins_reload", { "PLUGIN" }, "Reload the plugin so changes apply", false },
        { "pon", "plugins_enable", { "PLUGIN" }, "Turn a plugin on", false },
        { "poff", "plugins_disable", { "PLUGIN" }, "Turn a plugin off", true },
        { "prf", "plugins_refresh", {}, "Refresh the plugin list (after plugin.json edits)", false },
        { "plist", "plugins_list", {}, "List plugins in the console", false },
    }
    local PLUGS = { "rs-dev-tools", "pinger", "sound-browser", "world-event-timers", "slayer-task-tracker",
        "cursor-sprite", "gear-preset-checker", "rotten-potato", "idl-npcs", "(type a folder name)" }
    local S = { sub = 1, cmd = 2, plug = 2, perm = 2, pending = nil, note = nil, log = {}, changes = {}, seq = nil }
    local spec = { name = "Permissions", cat = "Plugins" }
    function spec.onEvent() end
    pcall(function()
        Event.OptionalPermissionChanged.Subscribe("rdtPerms", function(e)
            pcall(function() table.insert(S.changes, 1, { ctx.secs(), tostring(e.permissionName), tostring(e.enabled) }) end)
            if #S.changes > 10 then S.changes[#S.changes] = nil end
        end)
    end)
    function spec.shutdown()
        pcall(function() Event.OptionalPermissionChanged.Unsubscribe("rdtPerms") end)
        S.pending, S.seq = nil, nil
    end
    local function plugName()
        if S.plug == #PLUGS then return ((ctx.readField(S.plugF, 60) or ""):gsub("[^%w%-_%.]", "")) end
        return PLUGS[S.plug]
    end
    local function lineFor(ci)
        local c = CMDS[ci]
        local parts = { c[1] }
        for _, a in ipairs(c[3]) do
            local v = (a == "PLUGIN") and plugName() or PERMS[S.perm][1]
            if v == nil or v == "" then return nil, "Type a plugin folder name first." end
            parts[#parts + 1] = v
        end
        return table.concat(parts, " ")
    end
    local function canRun() return ctx.cmdFn() ~= nil end
    local function send(line)
        local f = ctx.cmdFn()
        if f == nil then S.note = "ExecuteConsoleCommand is not available in this client; nothing was run."; return false end
        local ok, e = pcall(f, line)
        table.insert(S.log, 1, { ctx.secs(), line, ok and "sent" or ("failed: " .. ctx.untag(tostring(e))) })
        if #S.log > 20 then S.log[#S.log] = nil end
        S.note = ok and ("Sent: " .. line) or ("Failed: " .. line)
        return ok
    end
    local function run(confirmed)
        local line, err = lineFor(S.cmd)
        if not line then S.note = err; return end
        if CMDS[S.cmd][5] and not confirmed then S.pending = line; S.note = "Confirm to run: " .. line; return end
        S.pending = nil
        send(line)
    end
    local function grant()
        local p = plugName()
        if p == nil or p == "" then S.note = "Type a plugin folder name first."; return end
        local perm = PERMS[S.perm][1]
        S.seq = { steps = { "ppr " .. p, "ppe " .. p .. " " .. perm, "prl " .. p }, i = 1, wait = 0 }
        S.note = "Granting " .. perm .. " to " .. p .. ": ppr, ppe, prl."
    end
    function spec.tick()
        local q = S.seq
        if q == nil then return end
        q.wait = q.wait - 1
        if q.wait > 0 then return end
        local ok = send(q.steps[q.i])
        q.i, q.wait = q.i + 1, 25
        if not ok or q.i > #q.steps then S.seq = nil; if ok then S.note = "Grant sequence sent. Check Status (this plugin) or the plugin itself." end end
        ctx.refresh()
    end
    local function tbl(cols, rows, detail, onRow) return { cols = cols, data = ctx.arr(rows), detail = detail, onRow = onRow } end
    local function lines(L) return function() return { lines = L } end end
    local function runView()
        local rows = {}
        for _, c in ipairs(CMDS) do
            rows[#rows + 1] = { H.val(c[1]), H.lbl(#c[3] > 0 and table.concat(c[3], " ") or "(none)"), H.lbl(c[4]), H.lbl(c[5] and "Confirm" or "-"), tip = c[2] .. ": " .. c[4] }
        end
        return tbl({ { title = "Command", w = 60 }, { title = "Arguments (in order)", w = 150 }, { title = "What it does", flex = 1, min = 120 }, { title = "Asks", w = 60 } }, rows,
            function()
                local line = lineFor(S.cmd)
                local L = { H.lbl("Preview: ") .. H.val(ctx.plain(line or "(type a plugin name)")) }
                if not canRun() then L[#L + 1] = H.col(H.C_LABEL, "ExecuteConsoleCommand is not available in this client: Run is off. Type the preview in the console instead.") end
                L[#L + 1] = H.lbl(S.note or "Pick command, plugin, permission. Nothing runs until you click. Grant = ppr, ppe, prl.")
                for _, l in ipairs(S.log) do if #L < 9 then L[#L + 1] = H.lbl(string.format("%.0f s  ", l[1])) .. H.val(ctx.plain(l[2])) .. H.lbl("  " .. ctx.plain(l[3])) end end
                return { lines = L }
            end,
            function(i) S.cmd = i; S.pending = nil end)
    end
    local function statusView()
        local rows = {}
        for _, p in ipairs(PERMS) do
            local okc, has = pcall(function() return Plugin.HasPermission(PluginPermissions[p[1]]) end)
            rows[#rows + 1] = { H.val(p[1]), okc and (has and H.col(H.C_GOOD, "granted") or H.col(H.C_LABEL, "not granted")) or H.col(H.C_LABEL, "not reported"), H.lbl(p[2]) }
        end
        local L = { H.lbl("Plugin.HasPermission reports this plugin (" .. ctx.SLUG .. ") only. Changes seen this session:") }
        if #S.changes == 0 then L[#L + 1] = H.lbl("  none yet (OptionalPermissionChanged)") end
        for _, c in ipairs(S.changes) do L[#L + 1] = H.lbl(string.format("%.0f s  ", c[1])) .. H.val(ctx.plain(c[2]) .. " -> " .. c[3]) end
        return tbl({ { title = "Permission", w = 120 }, { title = "Status", w = 100 }, { title = "Unlocks", flex = 1, min = 120 } }, rows, lines(L))
    end
    local function permsView()
        local rows = {}
        for _, p in ipairs(PERMS) do rows[#rows + 1] = { H.val(p[1]), H.lbl(p[2]), H.lbl(p[3]) } end
        return tbl({ { title = "Permission", w = 110 }, { title = "Grants", flex = 1, min = 120 }, { title = "Without it", flex = 1, min = 120 } }, rows,
            lines({ H.lbl("Only these three exist. Console commands (ExecuteConsoleCommand) need no permission.") }))
    end
    local function cmdsView()
        local rows = {}
        for _, c in ipairs(CMDS) do rows[#rows + 1] = { H.val(c[1]), H.lbl(c[2]), H.lbl(c[1] .. (#c[3] > 0 and (" " .. table.concat(c[3], " ")) or "")) } end
        rows[#rows + 1] = { H.val("-"), H.lbl("plugins_setenabled, plugins_setpath"), H.lbl("related; not run from here") }
        return tbl({ { title = "Short", w = 50 }, { title = "Full name", flex = 1, min = 150 }, { title = "Syntax", flex = 1, min = 120 } }, rows,
            lines({ H.lbl("Order: prf, then ppr, then ppe, then prl. PLUGIN is the folder name in dev_plugins."),
                H.lbl("No list-permissions, reset or grant-all command exists.") }))
    end
    local function manifestView()
        local rows = {
            { H.val("optionalPermissions"), H.lbl("[ \"chatAccess\" ]"), H.lbl("use this one") },
            { H.val("requiredPermissions"), H.lbl("[ ]"), H.lbl("known bug: not applied; keep it empty") },
            { H.val("urls"), H.lbl("[ \"https://api.example.com/\" ]"), H.lbl("httpAccess only reaches these base URLs") },
        }
        return tbl({ { title = "plugin.json key", w = 140 }, { title = "Example", flex = 1, min = 140 }, { title = "Note", flex = 1, min = 120 } }, rows,
            lines({ H.lbl("After editing plugin.json run prf (or restart the client), then ppr, ppe, prl.") }))
    end
    local function faqView()
        local rows = {
            { H.val("ppe printed nothing"), H.lbl("normal: it prints nothing when it works; check Status or the plugin") },
            { H.val("still not granted"), H.lbl("run ppr first, then ppe, then prl; folder name must match") },
            { H.val("lost after restart"), H.lbl("grants may reset on every client restart" .. UNV) },
            { H.val("checkboxes"), H.lbl("newer clients may let you tick permissions after ppr" .. UNV) },
            { H.val("prompt"), H.lbl("a permission prompt for players is promised" .. UNV) },
            { H.val("Run is off"), H.lbl("ExecuteConsoleCommand may be missing on live" .. UNV .. "; type the command") },
            { H.val("mod.io review"), H.lbl("plugins that request permissions get extra review") },
            { H.val("mod.io description"), H.lbl("justify each permission, and add a Data Protection section") },
        }
        return tbl({ { title = "Problem / rule", w = 150 }, { title = "Fix / note", flex = 1, min = 160 } }, rows,
            lines({ H.lbl("Rows marked unverified come from Discord reports, not docs.") }))
    end
    local SUBS = {
        { name = "Run", tip = "Build and run a permission command (only on click).", view = runView },
        { name = "Status", tip = "This plugin's permissions and change log.", view = statusView },
        { name = "Permissions", tip = "What each permission grants and what fails without it.", view = permsView },
        { name = "Commands", tip = "Full names, shorthands and order.", view = cmdsView },
        { name = "Manifest", tip = "plugin.json keys and the requiredPermissions bug.", view = manifestView },
        { name = "FAQ/Review", tip = "Common problems and the mod.io rules.", view = faqView },
    }
    function spec.build(ui)
        for i, s in ipairs(SUBS) do
            ui.btn(s.name, #s.name * 7 + 16, function() S.sub = i; S.pending = nil; ctx.refresh() end, nil, s.tip)
        end
        local R = function() return S.sub == 1 end
        local cl = {}; for _, c in ipairs(CMDS) do cl[#cl + 1] = c[1] end
        ui.dd(70, cl, function() return S.cmd end, function(i) S.cmd = i; S.pending = nil end, R, "perm cmd", "Console command.")
        ui.dd(160, PLUGS, function() return S.plug end, function(i) S.plug = i; S.pending = nil end, R, "perm plugin", "Plugin folder in dev_plugins (last entry: type it).")
        S.plugF = ui.field(130, "folder name", "perm plugin typed", function() return S.sub == 1 and S.plug == #PLUGS end, "Plugin folder name inside dev_plugins.")
        local pl = {}; for _, p in ipairs(PERMS) do pl[#pl + 1] = p[1] end
        ui.dd(120, pl, function() return S.perm end, function(i) S.perm = i; S.pending = nil end, R, "perm name", "Permission (used by ppe, ppd and Grant).")
        ui.btn("Run", 44, function() run(false); ctx.refresh() end, function() return S.sub == 1 and S.pending == nil and S.seq == nil and canRun() end, "Run the previewed command once.")
        ui.btn("Confirm", 64, function() run(true); ctx.refresh() end, function() return S.sub == 1 and S.pending ~= nil and canRun() end, "Run the pending ppd / poff.")
        ui.btn("Cancel", 56, function() S.pending = nil; S.note = "Cancelled."; ctx.refresh() end, function() return S.sub == 1 and S.pending ~= nil end)
        ui.btn("Grant", 56, function() grant(); ctx.refresh() end, function() return S.sub == 1 and S.seq == nil and S.pending == nil and canRun() end, "Run ppr, ppe, prl in that order for the chosen plugin and permission.")
    end
    function spec.view() return SUBS[S.sub].view() end
    return spec
end