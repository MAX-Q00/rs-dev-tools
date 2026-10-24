--[[ rdt_vars.lua (0.5.13) Vars tab (Inspect): find which variables store
  something by changing it by hand in game and watching what changes.
  Read only: no var is ever set and no command is sent.
  APIs used (all documented, all read only):
    var.VarPlayer.FromID(id) / var.VarClient.FromID(id) -> VarType
      (.value .valueType .configName .typeName .isVarBit .baseVar .varBitMask)
    VarBits live in the VarPlayer domain with negative IDs (docs: id.VarPlayer
      FRIEND_SORT_MODE = -30174); typed VarBit N is read as FromID(-N)
      (var.VarBit.FromID(N) is tried first in case the client has it).
    Event.VarTransmit (var, oldValue, newValue) via the shared event hook.
    Inventory.Find(id) -> Inv (:GetSlots(), .slotCount, .isValid) and the
      InventoryAdded / InventoryUpdated / InventoryRemoved events.
  Cost: nothing runs until Start watch. While watching, at most CHUNK reads
  per logic tick (50 ticks per second); no os.clock, no objects in draw. ]]
RDT_MODS = RDT_MODS or {}
RDT_MODS["rdt_vars"] = function(ctx)
    local H = ctx.H
    local TYPES = { "VarPlayer", "VarBit", "VarClient" }
    local PFX = { "P", "B", "C" }
    local TOFS = { P = 1, B = 2, C = 3 }
    local MAXW, CHUNK, MAXLOG, MAXMARKS, MAXINV, MAXRANGE = 30000, 200, 400, 16, 64, 20000
    local MODES = { "Mode: Read + pinned", "Mode: Change log", "Mode: Snapshot A/B diff", "Mode: Step isolation", "Mode: Inventories" }
    local S = {
        mode = 1, ty = 1, watch = false, keys = {}, inSet = {}, obj = {}, bad = {}, cur = {}, pos = 1, pass = 0,
        log = {}, pins = {}, pinSet = {}, readRes = nil, sel = nil, note = nil,
        noisy = {}, ignore = true, chg = {}, learnUntil = nil, autoAdd = true, revert = true,
        A = nil, B = nil, diff = {}, pend = nil, marks = {}, cands = {}, expect = nil,
        inv = {}, invQ = {}, invQs = {}, invN = 0, invRows = {},
    }
    local spec = { name = "Vars", cat = "Inspect" }
    local function now() return ctx.ticks() end
    local function keyOf(t, n) return PFX[t] .. ":" .. n end
    local function split(k) local p, n = k:match("^(%a):(%-?%d+)$"); return TOFS[p] or 1, tonumber(n) end
    local function str(v)
        if v == nil then return "nil" end
        local ok, s = pcall(tostring, v)
        return ok and ctx.plain(s):sub(1, 40) or "?"
    end
    local function resolve(t, n)
        local o = nil
        pcall(function()
            if t == 1 then o = var.VarPlayer.FromID(n)
            elseif t == 3 then o = var.VarClient.FromID(n)
            else
                pcall(function() if rawget(var, "VarBit") ~= nil or var.VarBit then o = var.VarBit.FromID(n) end end)
                if o == nil then o = var.VarPlayer.FromID(-n) end
            end
        end)
        return o
    end
    local function getObj(k)
        local o = S.obj[k]
        if o ~= nil or S.bad[k] then return o end
        local t, n = split(k)
        o = resolve(t, n)
        if o == nil then S.bad[k] = true else S.obj[k] = o end
        return o
    end
    local function readKey(k)
        local o = getObj(k)
        if o == nil then return nil, false end
        local ok, v = pcall(function() return o.value end)
        if not ok then return nil, false end
        if type(v) ~= "number" and type(v) ~= "string" and type(v) ~= "boolean" and v ~= nil then v = str(v) end
        return v, true
    end
    local function nameOf(k)
        local o = S.obj[k]
        if o == nil then return "" end
        local ok, s = pcall(function() return o.configName end)
        return (ok and s) and ctx.plain(tostring(s)) or ""
    end
    local function delta(a, b)
        if type(a) == "number" and type(b) == "number" then return b - a end
        return nil
    end
    local function dstr(d) if d == nil then return "" end; return (d > 0 and "+" or "") .. tostring(d) end
    local function matchExp(d)
        local e = S.expect
        if d == nil or e == nil or e == 0 then return "" end
        local ad, ae = math.abs(d), math.abs(e)
        if ad == ae then return "match" end
        local m = ae
        for s = 1, 30 do m = m * 2; if ad == m then return "match <<" .. s end; if m > ad then break end end
        if ad % ae == 0 then return "x" .. math.floor(ad / ae) end
        return ""
    end
    local function quiet(k) return S.ignore and S.noisy[k] end
    local function addLog(k, old, new, src)
        S.chg[k] = (S.chg[k] or 0) + 1
        if S.learnUntil and now() <= S.learnUntil then S.noisy[k] = "learned" end
        if S.chg[k] > 3 and not S.noisy[k] then S.noisy[k] = "auto" end
        if quiet(k) then return end
        table.insert(S.log, 1, { t = now(), k = k, old = old, new = new, src = src })
        if #S.log > MAXLOG then S.log[#S.log] = nil end
    end
    local function addKey(k)
        if S.inSet[k] or #S.keys >= MAXW then return false end
        S.inSet[k] = true; S.keys[#S.keys + 1] = k
        return true
    end
    -- snapshots copy the values from the last finished pass
    local function snap()
        local c = {}
        for k, v in pairs(S.cur) do c[k] = v end
        return c
    end
    local function computeDiff()
        local out = {}
        if S.A and S.B then
            for k, b in pairs(S.B) do local a = S.A[k]; if a ~= nil and a ~= b and not quiet(k) then out[#out + 1] = k end end
            table.sort(out)
        end
        S.diff = out
    end
    local function computeCands()
        local M, out = S.marks, {}
        if #M >= 2 then
            for k in pairs(M[#M].v) do
                local ok = not quiet(k)
                for i = 2, #M do
                    if not ok then break end
                    local a, b = M[i - 1].v[k], M[i].v[k]
                    if a == nil or b == nil or a == b then ok = false
                    elseif S.revert and i >= 3 and M[i - 2].v[k] ~= b then ok = false end
                end
                if ok then out[#out + 1] = k end
            end
            table.sort(out)
        end
        S.cands = out
    end
    local function finishPass()
        S.pass = S.pass + 1
        local p = S.pend
        if p == nil then return end
        S.pend = nil
        if p.kind == "A" then S.A = snap(); S.B = nil; S.diff = {}; S.note = "Snapshot A taken (" .. #S.keys .. " vars). Change something, then press Snapshot B."
        elseif p.kind == "B" then S.B = snap(); computeDiff(); S.note = "Snapshot B taken: " .. #S.diff .. " vars differ from A."
        elseif p.kind == "mark" then
            if #S.marks >= MAXMARKS then table.remove(S.marks, 2) end
            S.marks[#S.marks + 1] = { v = snap(), label = p.label, t = now() }
            S.chg = {}
            computeCands()
            S.note = (#S.marks == 1) and "Mark 1 (start) saved. Do the action, then press Mark again."
                or ("Mark " .. #S.marks .. " saved: " .. #S.cands .. " candidates left.")
        end
        ctx.refresh()
    end
    local function stepScan()
        local n = #S.keys
        if n == 0 then return end
        local stop = math.min(n, S.pos + CHUNK - 1)
        for i = S.pos, stop do
            local k = S.keys[i]
            local v, ok = readKey(k)
            if ok then
                local old = S.cur[k]
                if old ~= nil and old ~= v then addLog(k, old, v, "scan") end
                S.cur[k] = v
            end
        end
        S.pos = stop + 1
        if S.pos > n then S.pos = 1; finishPass() end
    end
    -- inventories: diff the slots of an inventory each time it updates
    local function invSlots(id)
        local m, used, cnt = {}, 0, 0
        local inv = Inventory.Find(id)
        if inv == nil then return nil end
        local okv, valid = pcall(function() return inv.isValid end)
        if okv and valid == false then return nil end
        pcall(function() cnt = inv.slotCount end)
        local slots = inv:GetSlots() or {}
        for i, s in pairs(slots) do
            local oid, c = nil, 0
            pcall(function() oid = s.obj and s.obj.id end)
            pcall(function() c = s.count or 0 end)
            if oid ~= nil and oid >= 0 and c > 0 then m[i] = { oid, c }; used = used + 1 end
        end
        return m, used, cnt
    end
    local function itemName(oid)
        local s = tostring(oid)
        pcall(function() local o = config.Obj.FromID(oid); if o and o.name then s = ctx.plain(tostring(o.name)) .. " (" .. oid .. ")" end end)
        return s
    end
    local function invStep()
        local done = 0
        while #S.invQ > 0 and done < 2 do
            local id = table.remove(S.invQ, 1); S.invQs[id] = nil; done = done + 1
            local ok, m, used, cnt = pcall(invSlots, id)
            local e = S.inv[id]
            if ok and m then
                if e == nil and S.invN < MAXINV then
                    local cn = ""
                    pcall(function() cn = config.Inv.FromID(id).configName or "" end)
                    e = { id = id, name = ctx.plain(tostring(cn)), ups = 0 }; S.inv[id] = e; S.invN = S.invN + 1
                    S.invRows[#S.invRows + 1] = e
                elseif e ~= nil and e.slots then
                    local seen = {}
                    for i, s in pairs(m) do
                        seen[i] = true
                        local o = e.slots[i]
                        if o == nil or o[1] ~= s[1] or o[2] ~= s[2] then
                            local k = "I:" .. id
                            local ov = o and (itemName(o[1]) .. " x" .. o[2]) or "empty"
                            table.insert(S.log, 1, { t = now(), k = k, slot = i, old = ov, new = itemName(s[1]) .. " x" .. s[2],
                                d = (o and o[1] == s[1]) and (s[2] - o[2]) or nil, src = "inv" })
                        end
                    end
                    for i, o in pairs(e.slots) do
                        if not seen[i] then
                            table.insert(S.log, 1, { t = now(), k = "I:" .. id, slot = i, old = itemName(o[1]) .. " x" .. o[2], new = "empty", src = "inv" })
                        end
                    end
                    while #S.log > MAXLOG do S.log[#S.log] = nil end
                end
                if e then e.slots, e.used, e.cnt, e.ups, e.t = m, used, cnt, e.ups + 1, now() end
            end
        end
    end
    function spec.onEvent(name, e)
        if not S.watch then return end
        if name == "VarTransmit" then
            pcall(function()
                local v = e.var
                local tn, idn, isb = tostring(v.typeName), v.id, false
                pcall(function() isb = v.isVarBit == true end)
                local k
                if tn == "VarClient" then k = "C:" .. idn
                elseif isb or idn < 0 then k = "B:" .. math.abs(idn)
                else k = "P:" .. idn end
                if S.obj[k] == nil then S.obj[k] = v; S.bad[k] = nil end
                if S.autoAdd then addKey(k) end
                local old, new = e.oldValue, e.newValue
                if old ~= new then
                    if S.inSet[k] then S.cur[k] = new end
                    addLog(k, old, new, "event")
                end
            end)
        elseif name == "InventoryAdded" or name == "InventoryUpdated" or name == "InventoryRemoved" then
            pcall(function()
                local id = nil
                pcall(function() id = e.invID end)
                if id == nil then pcall(function() id = e.inv.id end) end
                if type(id) == "number" and not S.invQs[id] and #S.invQ < 32 then S.invQs[id] = true; S.invQ[#S.invQ + 1] = id end
            end)
        end
    end
    function spec.tick(open, t)
        if not S.watch then return end
        if t % 500 == 0 then S.chg = {} end
        stepScan()
        if #S.invQ > 0 then invStep() end
        if S.learnUntil and now() > S.learnUntil then S.learnUntil = nil; S.note = "Noise learned: " .. ctx.commas(spec.noisyCount()) .. " noisy vars."; ctx.refresh() end
        if open and t % 25 == 0 then ctx.refresh() end
    end
    function spec.noisyCount() local c = 0; for _ in pairs(S.noisy) do c = c + 1 end; return c end
    function spec.shutdown() S.watch = false; S.invQ = {}; S.invQs = {} end
    local function stopWatch() S.watch = false; S.pend = nil; S.learnUntil = nil end
    local function resetValues() S.cur = {}; S.pos = 1; S.pass = 0 end
    local function readInt(f, lo, hi) return ctx.helpers.cleanInt(ctx.readField(f, 12), lo, hi) end
    local function signedInt(f)
        local s = tostring(ctx.readField(f, 14) or ""):gsub("[^%d%-]", "")
        local n = tonumber(s)
        return n and math.floor(n) or nil
    end
    local function needWatch(what)
        if #S.keys == 0 then S.note = "Add a range (or All named) first, then " .. what .. "."; return false end
        if not S.watch then S.watch = true; resetValues() end
        return true
    end
    local function show(m) return function() return S.mode == m end end
    local function showAny(a, b) return function() return S.mode == a or S.mode == b end end
    function spec.build(ui)
        ui.dd(170, MODES, function() return S.mode end, function(i) S.mode = i; S.sel = nil end, nil, "vars mode",
            "Read + pinned: read one var. Change log: every change while watching. Snapshot A/B: diff two moments. Step isolation: narrow down with Marks. Inventories: slot changes.")
        ui.dd(96, TYPES, function() return S.ty end, function(i) S.ty = i end, nil, "vars type",
            "Variable type for Read and Add range. VarBit IDs are read through VarPlayer (negative ID), as the docs describe.")
        S.idF = ui.field(70, "ID", "vars id", show(1), "Var ID to read (a whole number).")
        ui.btn("Read", 44, function()
            local n = readInt(S.idF, 0, 999999)
            if n == nil then S.readRes = "Type an ID first."; ctx.refresh(); return end
            local k = keyOf(S.ty, n)
            S.bad[k] = nil
            local v, ok = readKey(k)
            if not ok then S.readRes = TYPES[S.ty] .. " " .. n .. ": not readable (no such var, or not sent to the client)."
            else
                local vt = ""
                pcall(function() vt = " valueType " .. tostring(S.obj[k].valueType) end)
                pcall(function() if S.obj[k].isVarBit then vt = vt .. " mask " .. tostring(S.obj[k].varBitMask) .. " base " .. tostring(S.obj[k].baseVar.id) end end)
                S.readRes = TYPES[S.ty] .. " " .. n .. " " .. nameOf(k) .. " = " .. str(v) .. vt
            end
            S.sel = k
            ctx.refresh()
        end, show(1), "Read the typed var once and show its value.")
        ui.btn("Pin", 36, function()
            local k = S.sel
            if k == nil then local n = readInt(S.idF, 0, 999999); if n then k = keyOf(S.ty, n) end end
            if k and not S.pinSet[k] and #S.pins < 100 then S.pinSet[k] = true; S.pins[#S.pins + 1] = k end
            ctx.refresh()
        end, nil, "Pin the selected row (or the typed ID) to the Read + pinned list. Up to 100.")
        ui.btn("Unpin all", 64, function() S.pins, S.pinSet = {}, {}; ctx.refresh() end, show(1), "Clear the pinned list.")
        S.fromF = ui.field(64, "From ID", "vars from", nil, "First ID of the range to watch.")
        S.toF = ui.field(64, "To ID", "vars to", nil, "Last ID of the range (up to 20,000 IDs per range, 30,000 watched in total).")
        ui.btn("Add range", 70, function()
            local a, b = readInt(S.fromF, 0, 999999), readInt(S.toF, 0, 999999)
            if a == nil then S.note = "Type From (and To) first."; ctx.refresh(); return end
            b = b or a
            if b < a then a, b = b, a end
            if b - a + 1 > MAXRANGE then b = a + MAXRANGE - 1 end
            local added = 0
            for n = a, b do if addKey(keyOf(S.ty, n)) then added = added + 1 end end
            S.note = "Added " .. added .. " " .. TYPES[S.ty] .. " IDs (" .. a .. "-" .. b .. "). Watching " .. #S.keys .. " of max " .. MAXW .. "."
            ctx.refresh()
        end, nil, "Add the From-To range of the chosen type to the watch list.")
        ui.btn("All named", 70, function()
            local added = 0
            pcall(function()
                local dom = (S.ty == 3) and id.VarClient or id.VarPlayer
                for _, v in pairs(dom) do
                    if type(v) == "number" then
                        local k
                        if S.ty == 3 then k = "C:" .. v elseif v < 0 then k = "B:" .. (-v) else k = "P:" .. v end
                        if (S.ty == 2) == (k:sub(1, 1) == "B") or S.ty == 3 then if addKey(k) then added = added + 1 end end
                    end
                end
            end)
            S.note = "Added " .. added .. " named " .. TYPES[S.ty] .. " IDs from the id table. Watching " .. #S.keys .. "."
            ctx.refresh()
        end, nil, "Add every ID of the chosen type that has a name in the client's id table (these are the vars the client knows by name).")
        ui.btn("Clear watch", 76, function() stopWatch(); S.keys, S.inSet, S.obj, S.bad = {}, {}, {}, {}; resetValues(); S.note = "Watch list cleared."; ctx.refresh() end,
            nil, "Stop watching and empty the watch list (pins, log and noise list are kept).")
        ui.btn("Start watch", 76, function()
            if S.watch then stopWatch(); S.note = "Watch stopped."
            elseif needWatch("start") then S.note = "Watching " .. #S.keys .. " vars. The first pass is the baseline." end
            ctx.refresh()
        end, nil, "Start or stop watching. Reads " .. CHUNK .. " vars per tick (a full pass of 10,000 vars takes 1 s) and logs every change. Nothing runs while stopped.")
        ui.dd(120, { "Ignore noisy: on", "Ignore noisy: off" }, function() return S.ignore and 1 or 2 end, function(i) S.ignore = i == 1; computeDiff(); computeCands() end, nil, "vars noisy",
            "Hide vars that change by themselves (timers, tick counters): changed more than 3 times within about 10 s, or during Learn noise.")
        ui.btn("Learn noise", 76, function()
            if needWatch("learn noise") then S.learnUntil = now() + 500; S.note = "Learning noise for 10 s: don't touch anything." end
            ctx.refresh()
        end, nil, "Watch for 10 seconds while you do nothing; every var that changes is marked noisy.")
        ui.btn("Forget noise", 80, function() S.noisy = {}; computeDiff(); computeCands(); ctx.refresh() end, nil, "Clear the noisy list.")
        ui.dd(120, { "Auto-add sent: on", "Auto-add sent: off" }, function() return S.autoAdd and 1 or 2 end, function(i) S.autoAdd = i == 1 end, nil, "vars autoadd",
            "While watching, any var the server sends (Event.VarTransmit) is added to the watch list automatically.")
        ui.btn("Clear log", 64, function() S.log = {}; ctx.refresh() end, show(2), "Empty the change log.")
        ui.btn("Snapshot A", 76, function() if needWatch("snapshot") then S.pend = { kind = "A" }; S.note = "Snapshot A: waiting for the current pass to finish..." end; ctx.refresh() end,
            show(3), "Save every watched value (at the end of the current pass).")
        ui.btn("Snapshot B", 76, function()
            if S.A == nil then S.note = "Take Snapshot A first."
            elseif needWatch("snapshot") then S.pend = { kind = "B" }; S.note = "Snapshot B: waiting for the current pass to finish..." end
            ctx.refresh()
        end, show(3), "Save the values again and list every var that differs from A.")
        S.labF = ui.field(90, "Label (+100 air)", "vars label", show(4), "Optional note for the next Mark, e.g. +100 air.")
        ui.btn("Mark", 44, function()
            if needWatch("mark") then
                local l = tostring(ctx.readField(S.labF, 30) or "")
                S.pend = { kind = "mark", label = ctx.plain(l) }
                S.note = "Mark: waiting for the current pass to finish..."
            end
            ctx.refresh()
        end, show(4), "Press once before acting, then after each action and each undo. Keeps vars that changed on every step.")
        ui.btn("Reset marks", 76, function() S.marks, S.cands = {}, {}; S.note = "Marks cleared."; ctx.refresh() end, show(4), "Start the step isolation over.")
        ui.dd(130, { "Must revert: on", "Must revert: off" }, function() return S.revert and 1 or 2 end, function(i) S.revert = i == 1; computeCands() end, show(4), "vars revert",
            "On: a candidate must also go back to its earlier value when you undo (add, remove, add...). Off: it only has to change on every step.")
        S.expF = ui.field(80, "Expected +/-", "vars expect", showAny(3, 4), "Expected change, e.g. 100 for 100 runes. Rows whose delta matches (or matches shifted left, as in packed values) are flagged.")
        ui.btn("Set expected", 80, function() S.expect = signedInt(S.expF); ctx.refresh() end, showAny(3, 4), "Use the typed amount for the Match column.")
    end
    local function tyName(k)
        local p = k:sub(1, 1)
        if p == "I" then return "Inv" end
        return TYPES[TOFS[p] or 1]
    end
    local function idOf(k) return k:match(":(%-?%d+)$") or "" end
    local function logRow(e)
        local d = e.d or delta(e.old, e.new)
        return { H.lbl(tostring(e.t)), H.lbl(tyName(e.k)), H.val(idOf(e.k)), H.lbl(e.slot and ("slot " .. e.slot) or nameOf(e.k)),
            H.lbl(str(e.old)), H.val(str(e.new)), H.lbl(dstr(d)), tip = "Source: " .. tostring(e.src) }
    end
    local function line(k, extra) return tyName(k) .. " " .. idOf(k) .. (nameOf(k) ~= "" and (" " .. nameOf(k)) or "") .. (extra or "") end
    local function status()
        local s = (S.watch and ("Watching " .. ctx.commas(#S.keys) .. " vars, pass " .. S.pass .. (S.pass == 0 and " (baseline)" or "")) or ("Stopped, " .. ctx.commas(#S.keys) .. " vars in the list"))
        return s .. ", noisy " .. spec.noisyCount() .. (S.ignore and " (hidden)" or " (shown)") .. (S.learnUntil and ", learning noise" or "")
    end
    function spec.view(open)
        local cols, rows, copy, onRow
        local L = {}
        if S.mode == 1 then
            cols = { { title = "Type", w = 70 }, { title = "ID", w = 60, align = "right" }, { title = "Name", flex = 2, min = 100 }, { title = "Value", flex = 1, min = 70 }, { title = "Value type", w = 70 } }
            rows = {}
            for _, k in ipairs(S.pins) do
                local v, ok = readKey(k)
                local vt = ""
                pcall(function() vt = tostring(S.obj[k].valueType) end)
                rows[#rows + 1] = { H.lbl(tyName(k)), H.val(idOf(k)), H.lbl(nameOf(k)), ok and H.val(str(v)) or H.col(H.C_BAD, "not readable"), H.lbl(vt), key = k }
            end
            L[1] = H.lbl(S.readRes or "Pick a type, type an ID and press Read. Pin keeps it in this list (values refresh while the tab is open).")
            local c = {}
            for _, r in ipairs(rows) do c[#c + 1] = line(r.key, " = " .. str((readKey(r.key)))) end
            copy = #c > 0 and table.concat(c, " | ") or S.readRes
            onRow = function(i) S.sel = rows[i] and rows[i].key end
        elseif S.mode == 2 then
            cols = { { title = "Tick", w = 54, align = "right" }, { title = "Type", w = 62 }, { title = "ID", w = 52, align = "right" }, { title = "Name / slot", flex = 2, min = 80 },
                { title = "Old", flex = 1, min = 50 }, { title = "New", flex = 1, min = 50 }, { title = "Delta", w = 60, align = "right" } }
            local c = {}
            for i = 1, math.min(40, #S.log) do local e = S.log[i]; c[#c + 1] = e.t .. " " .. line(e.k, (e.slot and (" slot " .. e.slot) or "") .. " " .. str(e.old) .. " -> " .. str(e.new)) end
            copy = #c > 0 and table.concat(c, " | ") or nil
            local log = S.log
            onRow = function(i) local e = log[i]; if e and e.k:sub(1, 1) ~= "I" then S.sel = e.k end end
            L[1] = H.lbl("Newest first, up to " .. MAXLOG .. ". Tick = logic ticks since load (50 per second). Copy holds the newest 40.")
            return { cols = cols, data = { count = #log, get = function(i) return logRow(log[i]) end }, onRow = onRow,
                detail = function() return { lines = { H.lbl(status()), L[1], H.lbl(S.note or "") }, copy = copy } end }
        elseif S.mode == 3 then
            cols = { { title = "Type", w = 70 }, { title = "ID", w = 60, align = "right" }, { title = "Name", flex = 2, min = 90 }, { title = "A", flex = 1, min = 50 },
                { title = "B", flex = 1, min = 50 }, { title = "Delta", w = 60, align = "right" }, { title = "Match", w = 64 } }
            rows = {}
            local c = {}
            for _, k in ipairs(S.diff) do
                local a, b = S.A[k], S.B[k]
                local d = delta(a, b)
                rows[#rows + 1] = { H.lbl(tyName(k)), H.val(idOf(k)), H.lbl(nameOf(k)), H.lbl(str(a)), H.val(str(b)), H.lbl(dstr(d)), H.col(H.C_GOOD, matchExp(d)), key = k }
                if #c < 60 then c[#c + 1] = line(k, " " .. str(a) .. " -> " .. str(b)) end
            end
            copy = #c > 0 and table.concat(c, " | ") or nil
            L[1] = H.lbl((S.A and "A taken" or "No A yet") .. (S.B and (", B taken: " .. #S.diff .. " differ") or "") .. (S.expect and (", expected " .. S.expect) or ""))
            onRow = function(i) S.sel = rows[i] and rows[i].key end
        elseif S.mode == 4 then
            cols = { { title = "Type", w = 70 }, { title = "ID", w = 60, align = "right" }, { title = "Name", flex = 2, min = 90 }, { title = "Values at each mark", flex = 3, min = 120 },
                { title = "Last delta", w = 70, align = "right" }, { title = "Match", w = 64 } }
            rows = {}
            local c = {}
            local M = S.marks
            for _, k in ipairs(S.cands) do
                local vs = {}
                for i = 1, #M do vs[#vs + 1] = str(M[i].v[k]) end
                local d = #M >= 2 and delta(M[#M - 1].v[k], M[#M].v[k]) or nil
                rows[#rows + 1] = { H.lbl(tyName(k)), H.val(idOf(k)), H.lbl(nameOf(k)), H.val(table.concat(vs, " > ")), H.lbl(dstr(d)), H.col(H.C_GOOD, matchExp(d)), key = k }
                if #c < 60 then c[#c + 1] = line(k, " " .. table.concat(vs, ">")) end
            end
            copy = #c > 0 and table.concat(c, " | ") or nil
            local labs = {}
            for i, m in ipairs(M) do labs[#labs + 1] = i .. (m.label ~= "" and (" " .. m.label) or "") end
            L[1] = H.lbl("Marks: ") .. H.val(#M > 0 and table.concat(labs, ", ") or "none") .. H.lbl("  candidates ") .. H.val(#M >= 2 and #S.cands or "-")
                .. H.lbl("  watched ") .. H.val(ctx.commas(#S.keys))
            L[2] = H.lbl("Mark, add the item, Mark, remove it, Mark ... Each step keeps only vars that changed" .. (S.revert and " and went back on undo." or "."))
            onRow = function(i) S.sel = rows[i] and rows[i].key end
        else
            cols = { { title = "Inv ID", w = 60, align = "right" }, { title = "Config name", flex = 2, min = 90 }, { title = "Used / slots", w = 84 }, { title = "Updates", w = 60, align = "right" }, { title = "Last tick", w = 64, align = "right" } }
            rows = {}
            for _, e in ipairs(S.invRows) do
                rows[#rows + 1] = { H.val(tostring(e.id)), H.lbl(e.name), H.lbl(tostring(e.used or 0) .. " / " .. tostring(e.cnt or 0)), H.lbl(tostring(e.ups)), H.lbl(tostring(e.t or "")), inv = e }
            end
            onRow = function(i) S.selInv = rows[i] and rows[i].inv end
            local e = S.selInv
            if e and e.slots then
                local c = {}
                for i, s in pairs(e.slots) do if #c < 40 then c[#c + 1] = "slot " .. i .. ": " .. itemName(s[1]) .. " x" .. s[2] end end
                copy = "Inv " .. e.id .. " " .. e.name .. " | " .. table.concat(c, " | ")
                L[1] = H.gold("Inv " .. e.id .. " " .. e.name) .. H.lbl("  " .. tostring(e.used) .. " used slots (Copy lists them)")
            else
                L[1] = H.lbl("While watching, every inventory the server updates is listed here and each slot change goes to the Change log (Type Inv).")
            end
        end
        local data = ctx.arr(rows)
        return { cols = cols, data = data, onRow = onRow,
            detail = function()
                local out = { H.lbl(status()) }
                for _, l in ipairs(L) do out[#out + 1] = l end
                if S.sel and S.mode ~= 5 then out[#out + 1] = H.lbl("Selected: ") .. H.val(line(S.sel)) .. H.lbl("  (Pin adds it to Read + pinned)") end
                out[#out + 1] = H.lbl(S.note or "Read only: nothing is ever set. Add a range or All named, then Start watch.")
                return { lines = out, copy = copy }
            end }
    end
    return spec
end
return RDT_MODS["rdt_vars"]
