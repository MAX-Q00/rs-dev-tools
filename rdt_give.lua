--[[ rdt_give.lua (0.5.4) Give by ID (Debug, next to Commands).
  Type an item ID -> config name from config.Obj.FromID(id).configName (the
  same source as the item browser and hover). Shows config + display name,
  or "not found". Count (typed or -/+), Inv (inv, bank; "Scan invs" adds
  more from config.Inv in small steps, only after a click and only while
  this tab is open). Preview = the exact command. Run sends it only on
  click; Copy puts it in a selectable box (plugins have no clipboard API).
  A numeric ID is never sent to !give: Run is off unless a config name was
  found. The Sprite Browser's "Give" button pre-fills this tab (ctx.give). ]]
return function(ctx)
    local H = ctx.H
    local S = { id = nil, cfg = nil, disp = nil, count = 1, inv = 1, invs = { "inv", "bank" }, scan = nil, note = nil, lastId = nil }
    local spec = { name = "Give by ID", cat = "Debug" }
    local function okName(s) return type(s) == "string" and s ~= "" and s:match("^[%w_]+$") ~= nil and s:match("^%d+$") == nil end
    local function lookup(n)
        S.id, S.cfg, S.disp = n, nil, nil
        if n == nil then return end
        pcall(function()
            local o = config.Obj.FromID(n)
            if o == nil then return end
            pcall(function() S.disp = o.name end)
            local c = nil
            pcall(function() c = o.configName end)
            if okName(c) then S.cfg = c end
        end)
    end
    local function setField(f, s) pcall(function() f.content = s end) end
    local function readId()
        local n = ctx.helpers.cleanInt(ctx.readField(S.idF, 9), 0, 99999999)
        if n ~= S.lastId then S.lastId = n; lookup(n) end
    end
    local function readCount()
        local n = ctx.helpers.cleanInt(ctx.readField(S.cntF, 10), 1, 2147483647)
        if n then S.count = n end
    end
    local function line()
        if not S.cfg then return nil end
        return "!give " .. S.cfg .. " " .. tostring(S.count) .. " " .. (S.invs[S.inv] or "inv")
    end
    local function canRun() return ctx.cmdFn() ~= nil end
    ctx.give = function(n)
        pcall(function() setField(S.idF, tostring(n)); S.lastId = n; lookup(n); S.note = nil end)
    end
    function spec.build(ui)
        S.idF = ui.field(80, "Item ID", "give id", nil, "Item ID. The config name is looked up from config.Obj; numeric IDs are never sent.")
        ui.btn("Look up", 60, function() S.lastId = -1; readId(); ctx.refresh() end, nil, "Look up the config name for the typed ID.")
        S.cntF = ui.field(70, "Count", "give count", nil, "How many (1 or more).")
        ui.btn("-", 20, function() readCount(); S.count = math.max(1, S.count - 1); setField(S.cntF, tostring(S.count)); ctx.refresh() end, nil, "One less.")
        ui.btn("+", 20, function() readCount(); S.count = math.min(2147483647, S.count + 1); setField(S.cntF, tostring(S.count)); ctx.refresh() end, nil, "One more.")
        ui.dd(110, function() return S.invs end, function() return S.inv end, function(i) S.inv = i end, nil, "give inv", "Inventory config name: inv (backpack), bank, or one found by Scan invs.")
        ui.btn("Scan invs", 70, function() if S.scan == nil then S.scan = 0; S.note = "Scanning config.Inv..." end; ctx.refresh() end,
            function() return S.scan == nil end, "Add inventory config names from config.Inv (small steps, only while this tab is open).")
        ui.btn(canRun() and "Run" or "Run (unavailable)", canRun() and 44 or 120, function()
            readId(); readCount()
            local l = line()
            if not l then S.note = "Not found: no config name for this ID, so nothing was run."; ctx.refresh(); return end
            local f = ctx.cmdFn()
            if f == nil then S.note = "ExecuteConsoleCommand is not available in this client; nothing was run."; ctx.refresh(); return end
            local ok, e = pcall(f, l)
            S.note = ok and ("Sent: " .. l) or ("Failed: " .. ctx.untag(tostring(e)))
            ctx.refresh()
        end, function() return S.cfg ~= nil and canRun() end, "Send the previewed !give once.")
        ui.btn("Copy", 48, function()
            readId(); readCount()
            local l = line()
            if l then setField(S.copyF, l); S.note = "Copied into the box: select it and press Ctrl+C." else S.note = "Nothing to copy: no config name." end
            ctx.refresh()
        end, function() return S.cfg ~= nil end, "Put the command in a selectable box (plugins have no clipboard).")
        S.copyF = ui.field(200, "", "give copy", function() return S.cfg ~= nil end, "Select the text and press Ctrl+C.")
    end
    function spec.tick(open)
        if S.scan == nil or not open then return end
        local seen = {}
        for _, v in ipairs(S.invs) do seen[v] = true end
        local stop = S.scan + 40
        for i = S.scan, stop do
            pcall(function()
                local o = config.Inv.FromID(i)
                local c = o and o.configName
                if okName(c) and not seen[c] then S.invs[#S.invs + 1] = c; seen[c] = true end
            end)
        end
        S.scan = stop + 1
        if S.scan > 2000 then S.scan = nil; S.note = "Inventories: " .. #S.invs .. " (inv, bank + config.Inv)."; ctx.refresh() end
    end
    function spec.shutdown() S.scan = nil; ctx.give = nil end
    function spec.view(open)
        if open then readId(); readCount() end
        local rows = {
            { H.val("Item ID"), H.lbl(S.id and tostring(S.id) or "(type one)") },
            { H.val("Config name"), S.cfg and H.val(S.cfg) or H.col(H.C_BAD, S.id and "not found" or "-") },
            { H.val("Display name"), H.lbl(ctx.plain(tostring(S.disp or "-"))) },
            { H.val("Count"), H.lbl(tostring(S.count)) },
            { H.val("Inventory"), H.lbl(S.invs[S.inv] or "inv") },
        }
        return { cols = { { title = "Field", w = 100 }, { title = "Value", flex = 1, min = 120 } }, data = ctx.arr(rows),
            detail = function()
                local l = line()
                local L = { H.lbl("Preview: ") .. (l and H.val(ctx.plain(l)) or H.col(H.C_BAD, "not found (no config name; Run is off)")) }
                if not canRun() then L[#L + 1] = H.lbl("ExecuteConsoleCommand is not available: type the preview in the console.") end
                L[#L + 1] = H.lbl(S.note or "Config names only: a numeric ID is never sent to !give. Nothing runs until you click Run. Cheats are logged.")
                if S.scan then L[#L + 1] = H.lbl("Scanning config.Inv: " .. S.scan .. " / 2000") end
                return { lines = L }
            end }
    end
    return spec
end