--[[ rdt_perms.lua (0.3.0) Permissions tab (Plugins): live status of every
  documented PluginPermissions value for this plugin, what each unlocks,
  change events, and how to grant one on a dev world. Read only: it never
  requests or grants a permission itself. ]]
return function(ctx)
    local H = ctx.H
    local P = {
        { "httpAccess", "HTTPRequest (Get, Post, AddHeader, Cancel) to the URLs in plugin.json" },
        { "chatAccess", "Event.ChatMessage and Chat.AddMessage" },
        { "trackingAccess", "Player.GetTrackingID" },
    }
    local S = { changes = {} }
    local spec = { name = "Permissions", cat = "Plugins" }
    function spec.onEvent() end
    pcall(function()
        Event.OptionalPermissionChanged.Subscribe("rdtPerms", function(e)
            pcall(function() table.insert(S.changes, 1, { ctx.secs(), tostring(e.permissionName), tostring(e.enabled) }) end)
            if #S.changes > 5 then S.changes[#S.changes] = nil end
        end)
    end)
    function spec.shutdown() pcall(function() Event.OptionalPermissionChanged.Unsubscribe("rdtPerms") end) end
    function spec.view()
        local rows = {}
        for _, p in ipairs(P) do
            local st, ok = "unknown", pcall(function() end)
            local okc, has = pcall(function() return Plugin.HasPermission(PluginPermissions[p[1]]) end)
            st = okc and (has and H.col(H.C_GOOD, "granted") or H.col(H.C_WARN, "not granted")) or H.col(H.C_BAD, "check failed")
            rows[#rows + 1] = { H.val(p[1]), st, H.lbl(p[2]), tip = "Grant on a dev world in the console: ppr " .. ctx.SLUG .. " then ppe " .. ctx.SLUG .. " " .. p[1] .. " then prl " .. ctx.SLUG .. "." }
        end
        rows[#rows + 1] = { H.val("Console commands"), H.lbl("no permission"), H.lbl("ExecuteConsoleCommand (Commands tab; runs only on a click)") }
        local nu = 0
        pcall(function() for _ in pairs(Plugin.urls or {}) do nu = nu + 1 end end)
        rows[#rows + 1] = { H.val("Plugin.urls"), H.lbl(nu .. " URLs"), H.lbl("base URLs from plugin.json (none in RS Dev Tools)") }
        local nr = 0
        pcall(function() for _ in pairs(Plugin.resources or {}) do nr = nr + 1 end end)
        rows[#rows + 1] = { H.val("Plugin.resources"), H.lbl(nr .. " files"), H.lbl("images and sounds in the resources folder") }
        return { cols = { { title = "Permission", w = 120 }, { title = "Status", w = 90 }, { title = "Unlocks", flex = 1, min = 120 } }, data = ctx.arr(rows),
            detail = function()
                local L = { H.lbl("RS Dev Tools asks for no permissions. Hover a row for the dev-world console steps (ppr, ppe, prl).") }
                for _, c in ipairs(S.changes) do L[#L + 1] = H.lbl(string.format("%.0f s: ", c[1])) .. H.val(ctx.plain(c[2]) .. " -> " .. c[3]) end
                return { lines = L }
            end }
    end
    return spec
end
