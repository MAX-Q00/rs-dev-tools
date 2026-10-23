--[[ rdt_auto.lua Automation tab (Debug): console macros.
  A macro is a list of console commands separated by ';'. Start runs them in
  order through ExecuteConsoleCommand, one every step delay, only after a
  click. If any step is destructive (the same list the Commands tab uses),
  Start asks for Confirm first. Never sends game input or types in game.
  Saved macros live in this plugin's PersistentDB (key rdtu_macros). ]]
return function(ctx)
    local H = ctx.H
    local KEY = "rdtu_macros"
    local PRESETS = {
        { "Permission setup (http)", "prf; pon PLUGIN; ppr PLUGIN; ppe PLUGIN httpAccess; prl PLUGIN" },
        { "Permission setup (chat)", "prf; pon PLUGIN; ppr PLUGIN; ppe PLUGIN chatAccess; prl PLUGIN" },
        { "Reload a plugin", "prf; prl PLUGIN" },
        { "Plugin off and on", "poff PLUGIN; pon PLUGIN" },
        { "Dev test kit", "!godmode; !maxhp; !bank" },
        { "Save spot, then return", "!coordsave; !getcoord" },
        { "Return to saved spot", "!coordtele" },
        { "Where am I", "!getcoord; !listnpcs 10; !listlocs 10" },
        { "Hide / show interface", "!tlihide; !tlishow" },
        { "Max Invention materials", "!inventgivemats" },
        { "Fresh backpack (destructive)", "!clearinv" },
        { "Complete everything (destructive)", "!allinone" },
    }
    local S = { list = {}, sel = nil, run = nil, pending = nil, note = nil, delay = 2, rep = 1, log = {} }
    local DELAYS = { 10, 25, 50, 150 }
    pcall(function() local t = PersistentDB:GetStructuredData(KEY); if type(t) == "table" then S.saved = t end end)
    S.saved = S.saved or {}
    local function rebuild()
        S.list = {}
        for _, p in ipairs(PRESETS) do S.list[#S.list + 1] = { name = p[1], text = p[2], preset = true } end
        for i, m in ipairs(S.saved) do if type(m) == "table" then S.list[#S.list + 1] = { name = tostring(m.name or ("Macro " .. i)), text = tostring(m.text or ""), idx = i } end end
    end
    rebuild()
    local function steps(m)
        local plug = ctx.readField(S.plugF, 48):lower():gsub("[%s_]+", "-"):gsub("[^a-z0-9%-]", "")
        if plug == "" then plug = ctx.SLUG end
        local out = {}
        for part in tostring(m.text):gmatch("[^;]+") do
            local s = part:gsub("^%s+", ""):gsub("%s+$", ""):gsub("PLUGIN", plug)
            if s ~= "" then out[#out + 1] = s end
        end
        local all = {}
        for _ = 1, S.rep do for _, s in ipairs(out) do all[#all + 1] = s end end
        return all
    end
    local function start(confirmed)
        local m = S.sel
        if m == nil then S.note = "Pick a macro."; return end
        if ctx.cmdFn() == nil then S.note = "ExecuteConsoleCommand is not available in this client."; return end
        local st = steps(m)
        if #st == 0 then S.note = "This macro has no commands."; return end
        if not confirmed then
            local why = {}
            for _, s in ipairs(st) do local w = ctx.needsConfirm(s); if w then why[#why + 1] = w end end
            if #why > 0 then S.pending = st; S.note = "Confirm needed: " .. table.concat(why, "; "); return end
        end
        S.pending = nil
        S.run = { steps = st, i = 1, wait = 0, name = m.name }
        S.note = "Running " .. m.name .. " (" .. #st .. " steps)."
    end
    local spec = { name = "Automation", cat = "Debug" }
    function spec.tick(active, t)
        local r = S.run
        if r == nil then return end
        r.wait = r.wait - 1
        if r.wait > 0 then return end
        local s = r.steps[r.i]
        local ok, err = pcall(ctx.cmdFn(), s)
        table.insert(S.log, 1, { ctx.secs(), s, ok and "sent" or ctx.untag(tostring(err)) })
        if #S.log > 40 then S.log[#S.log] = nil end
        r.i = r.i + 1
        r.wait = DELAYS[S.delay]
        if r.i > #r.steps then S.run = nil; S.note = "Finished " .. r.name .. "." end
        ctx.refresh()
    end
    function spec.shutdown() S.run = nil end
    function spec.build(ui)
        S.plugF = ui.field(120, "PLUGIN folder", "auto plugin", nil, "Folder name that replaces PLUGIN in a macro (default: this plugin).")
        ui.dd(110, { "Step 0.2 s", "Step 0.5 s", "Step 1 s", "Step 3 s" }, function() return S.delay end, function(i) S.delay = i end, nil, "auto delay", "Wait between steps.")
        ui.dd(80, { "Run x1", "Run x3", "Run x10" }, function() return ({ [1] = 1, [3] = 2, [10] = 3 })[S.rep] end, function(i) S.rep = ({ 1, 3, 10 })[i] end, nil, "auto repeat", "Repeat the whole macro.")
        ui.btn("Start", 48, function() start(false); ctx.refresh() end, function() return S.run == nil and S.pending == nil end, "Run the selected macro (destructive steps ask for Confirm).")
        ui.btn("Confirm", 64, function() start(true); ctx.refresh() end, function() return S.pending ~= nil end, "Run it, including the destructive steps listed.")
        ui.btn("Cancel", 56, function() S.pending = nil; S.note = "Cancelled."; ctx.refresh() end, function() return S.pending ~= nil end)
        ui.btn("Stop", 44, function() S.run = nil; S.note = "Stopped."; ctx.refresh() end, function() return S.run ~= nil end, "Stop the running macro.")
        S.nameF = ui.field(110, "Macro name", "auto name", nil, "Name for a new macro.")
        S.textF = ui.field(220, "cmd one; cmd two; ...", "auto text", nil, "Console commands separated by ';'. PLUGIN is replaced by the folder box.")
        ui.btn("Save", 44, function()
            local n, t = ctx.readField(S.nameF, 40), ctx.readField(S.textF, 400)
            if t == "" then S.note = "Type the commands first."; ctx.refresh(); return end
            if #S.saved >= 20 then S.note = "20 saved macros at most; delete one."; ctx.refresh(); return end
            S.saved[#S.saved + 1] = { name = n ~= "" and n or ("Macro " .. (#S.saved + 1)), text = t }
            pcall(function() PersistentDB:SetStructuredData(KEY, S.saved) end)
            rebuild(); S.note = "Saved."; ctx.refresh()
        end, nil, "Save the typed macro.")
        ui.btn("Delete", 52, function()
            if S.sel and S.sel.idx then table.remove(S.saved, S.sel.idx); pcall(function() PersistentDB:SetStructuredData(KEY, S.saved) end); S.sel = nil; rebuild() end
            ctx.refresh()
        end, function() return S.sel ~= nil and S.sel.idx ~= nil end, "Delete the selected saved macro.")
    end
    function spec.view()
        local rows = S.list
        return { cols = { { title = "Macro", flex = 2, min = 120 }, { title = "Commands", flex = 3, min = 120 }, { title = "Kind", w = 54 } },
            data = { count = #rows, get = function(i) local m = rows[i]
                return { H.val(ctx.plain(m.name)), H.lbl(ctx.plain(m.text)), H.lbl(m.preset and "preset" or "saved"), tip = ctx.plain(m.text) } end },
            onRow = function(i) S.sel = rows[i]; S.pending = nil end,
            detail = function()
                local L = { H.lbl(S.note or "Pick a macro, set PLUGIN if needed, then Start. Steps run through ExecuteConsoleCommand only.") }
                if S.run then L[#L + 1] = H.gold("Step " .. S.run.i .. " of " .. #S.run.steps) .. H.lbl("  next: " .. ctx.plain(S.run.steps[S.run.i] or "")) end
                for _, l in ipairs(S.log) do if #L < 8 then L[#L + 1] = H.lbl(string.format("%.0f s  ", l[1])) .. H.val(ctx.plain(l[2])) .. H.lbl("  " .. ctx.plain(l[3])) end end
                return { lines = L }
            end }
    end
    return spec
end
