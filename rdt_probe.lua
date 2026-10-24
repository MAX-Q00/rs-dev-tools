--[[ rdt_probe.lua (0.4.0) Deep Probe tab (Debug).
   Two views:
   - Samples: members of sample objects (your PlayerEntity, an NPC, Vector3 ...).
   - Deep scan: walks _G and every reachable table/userdata (cycle-safe,
     depth and time limited, spread over ticks), reads metatables
     (__index/__name/__call), lists enum tables, records arity hints
     (debug.getinfo when present) and flags names the docs never mention.
  Read only: no function is ever called. Only plain reads inside pcall.
  Results are saved to PersistentDB key rdt_probe (+ rdt_probe_1..N chunks). ]]
-- 0.5.10: this client's require returns nil, so the module also registers itself in RDT_MODS.
RDT_MODS = RDT_MODS or {}
RDT_MODS["rdt_probe"] = function(ctx)
    local H = ctx.H
    -- documented names: full api paths + every identifier in the docs
    local DOCP, DOCN = {}, {}
    pcall(function() for _, n in ipairs(require("rdt_api_data").api) do DOCP[n:gsub(":", ".")] = true; DOCN[n:gsub("^.*[.:]", "")] = true end end)
    pcall(function() for w in require("rdt_docnames"):gmatch("[%w_]+") do DOCN[w] = true end end)
    local MAXD, BUDGET, MAXROWS, CHUNK = 6, 0.004, 20000, 30000
    local clock = (os and os.clock) or function() return 0 end
    local dbg = type(debug) == "table" and debug or nil
    local SAMPLES = {
        { "Deep scan (_G)", nil },
        { "Your PlayerEntity", function() return Player.GetEntity() end },
        { "First NPC", function() return (NPCList.All() or {})[1] end },
        { "First loc", function() return (LocList.All() or {})[1] end },
        { "First ground stack", function() return (ObjStackList.All() or {})[1] end },
        { "Vector3", function() return Vector3.new(1, 2, 3) end },
        { "UI root", function() return ctx.root() end },
        { "PersistentDB", function() return PersistentDB end },
        { "Camera", function() return Camera end },
        { "World", function() return World end },
    }
    local S = { sel = 1, rows = {}, shown = nil, filt = "", only = 1, note = nil, job = nil, stats = nil }
    local ONLY = { "Show: all", "Show: undocumented", "Show: functions", "Show: enums" }

    local function sig(f)
        if not dbg or not dbg.getinfo then return "fn" end
        local ok, i = pcall(dbg.getinfo, f, "Su")
        if not ok or type(i) ~= "table" then return "fn" end
        if i.what == "C" then return "C fn" end
        local p = {}
        for n = 1, (i.nparams or 0) do
            local okn, nm = pcall(dbg.getlocal, f, n); p[#p + 1] = (okn and nm) or ("a" .. n)
        end
        if i.isvararg then p[#p + 1] = "..." end
        return "fn(" .. table.concat(p, ", ") .. ")"
    end
    local function isEnum(t)
        local n, num = 0, 0
        for k, v in pairs(t) do
            n = n + 1
            if type(k) == "string" and k:match("^[%u%d_]+$") and type(v) == "number" then num = num + 1 end
            if n > 400 then break end
        end
        return n >= 2 and num == n
    end
    local function documented(path, leaf)
        if DOCP[path] then return "yes" end
        if DOCN[leaf] then return "name" end
        return "NO"
    end

    -- incremental BFS over the reachable graph
    local function startDeep()
        local seen = setmetatable({}, { __mode = "k" })
        local job = { q = { { _G, "_G", 0 } }, h = 1, seen = seen, rows = {}, t0 = clock(), n = { tables = 0, ud = 0, fns = 0, enums = 0, undoc = 0, probed = 0 } }
        seen[_G] = true
        seen[S] = true
        S.job, S.rows, S.shown = job, job.rows, nil
        S.note = "Deep scan running..."
    end
    local function addRow(job, path, v, from)
        local t = type(v)
        local leaf = path:match("([^%.]+)$") or path
        local r = { k = path, t = t, from = from, d = documented(path, leaf) }
        if t == "function" then r.s = sig(v); job.n.fns = job.n.fns + 1
        elseif t == "table" then
            local okE, e = pcall(isEnum, v); if okE and e then r.t = "enum"; job.n.enums = job.n.enums + 1 end
        elseif t ~= "userdata" then local okv, sv = pcall(tostring, v); r.s = okv and ctx.plain(sv):sub(1, 40) or "?" end
        if r.d == "NO" then job.n.undoc = job.n.undoc + 1 end
        if #job.rows < MAXROWS then job.rows[#job.rows + 1] = r end
        return r
    end
    local function visit(job, o, path, depth)
        local function child(k, v, from)
            if type(k) ~= "string" then return end
            local p = (path == "_G") and k or (path .. "." .. k)
            local r = addRow(job, p, v, from)
            local tv = type(v)
            if (tv == "table" or tv == "userdata") and not job.seen[v] and depth + 1 < MAXD then
                job.seen[v] = true
                job.q[#job.q + 1] = { v, p, depth + 1 }
            elseif (tv == "table" or tv == "userdata") and job.seen[v] then r.from = from .. " (seen)" end
        end
        if type(o) == "table" then
            job.n.tables = job.n.tables + 1
            pcall(function() for k, v in pairs(o) do child(k, v, "field") end end)
        else job.n.ud = job.n.ud + 1 end
        local okm, mt = pcall(getmetatable, o)
        if okm and type(mt) == "table" then
            local nm = rawget(mt, "__name"); if nm ~= nil then addRow(job, path .. ".__name", nm, "meta") end
            if rawget(mt, "__call") ~= nil then addRow(job, path .. ".__call", rawget(mt, "__call"), "meta") end
            pcall(function() for k, v in pairs(mt) do if type(k) == "string" and k ~= "__index" and k ~= "__name" and k ~= "__call" then addRow(job, path .. "." .. k, v, "meta") end end end)
            local idx = rawget(mt, "__index")
            if type(idx) == "table" and idx ~= o then
                pcall(function() for k, v in pairs(idx) do child(k, v, "__index") end end)
            elseif type(idx) == "function" or type(o) == "userdata" then
                -- opaque getter: try every documented identifier as a key (plain reads only)
                local hits = 0
                for w in pairs(DOCN) do
                    local okr, v = pcall(function() return o[w] end)
                    job.n.probed = job.n.probed + 1
                    if okr and v ~= nil and (type(o) ~= "table" or rawget(o, w) == nil) then hits = hits + 1; child(w, v, "probe") end
                end
            end
        end
    end
    local function encode(rows)
        local b = {}
        for _, r in ipairs(rows) do b[#b + 1] = table.concat({ r.k, r.t, r.d, r.from or "", (r.s or ""):gsub("[\t\n]", " ") }, "\t") end
        return table.concat(b, "\n")
    end
    local function save(job)
        pcall(function()
            local s = encode(job.rows)
            local old = PersistentDB:GetStructuredData("rdt_probe")
            local n = 0
            for i = 1, #s, CHUNK do n = n + 1; PersistentDB:SetString("rdt_probe_" .. n, s:sub(i, i + CHUNK - 1)) end
            if type(old) == "table" and type(old.chunks) == "number" then for i = n + 1, old.chunks do PersistentDB:Delete("rdt_probe_" .. i) end end
            local st = { chunks = n, rows = #job.rows, format = "path\\ttype\\tdocumented\\tfrom\\tsignature, newline separated", version = ctx.VERSION,
                tables = job.n.tables, userdata = job.n.ud, functions = job.n.fns, enums = job.n.enums, undocumented = job.n.undoc,
                probed = job.n.probed, seconds = math.floor((clock() - job.t0) * 100) / 100, debug = dbg ~= nil }
            PersistentDB:SetStructuredData("rdt_probe", st)
        end)
    end
    local function stepDeep()
        local job = S.job
        if not job then return end
        local t = clock()
        while job.h <= #job.q do
            local it = job.q[job.h]; job.q[job.h] = nil; job.h = job.h + 1
            pcall(visit, job, it[1], it[2], it[3])
            if clock() - t > BUDGET then break end
        end
        if job.h > #job.q then
            table.sort(job.rows, function(a, b) return a.k < b.k end)
            save(job)
            local n = job.n
            S.stats = n
            S.note = #job.rows .. " names (" .. n.undoc .. " undocumented, " .. n.fns .. " functions, " .. n.enums .. " enums, " .. n.tables .. " tables, " .. n.ud .. " userdata). Saved to rdt_probe."
            S.job = nil
        else S.note = "Deep scan running: " .. #job.rows .. " names, " .. (#job.q - job.h + 1) .. " objects queued..." end
        S.shown = nil
        ctx.refresh()
    end
    local function scanSample()
        local ok, o = pcall(SAMPLES[S.sel][2])
        if not ok or o == nil then S.rows = {}; S.note = "No sample: " .. SAMPLES[S.sel][1] .. " is not available now."; return end
        local job = { q = {}, h = 1, seen = {}, rows = {}, n = { tables = 0, ud = 0, fns = 0, enums = 0, undoc = 0, probed = 0 } }
        pcall(visit, job, o, SAMPLES[S.sel][1]:gsub(" ", "_"), MAXD - 1)
        table.sort(job.rows, function(a, b) return a.k < b.k end)
        S.rows, S.shown = job.rows, nil
        S.note = #job.rows .. " members on " .. SAMPLES[S.sel][1] .. " (" .. job.n.undoc .. " undocumented)."
    end
    local function filtered()
        if S.shown then return S.shown end
        local f, out = S.filt:lower(), {}
        for _, r in ipairs(S.rows) do
            local ok = (f == "" or r.k:lower():find(f, 1, true) ~= nil)
            if ok and S.only == 2 then ok = r.d == "NO" elseif ok and S.only == 3 then ok = r.t == "function" elseif ok and S.only == 4 then ok = r.t == "enum" end
            if ok then out[#out + 1] = r end
        end
        S.shown = out
        return out
    end
    local spec = { name = "Deep Probe", cat = "Debug" }
    function spec.build(ui)
        local opts = {}
        for i, s in ipairs(SAMPLES) do opts[i] = s[1] end
        ui.dd(140, opts, function() return S.sel end, function(i) S.sel = i; S.rows = {}; S.shown = nil; S.note = nil; if i > 1 then scanSample() end end, nil, "deep sample",
            "Deep scan walks everything reachable from _G. The others list one sample object's members.")
        ui.btn("Deep scan", 72, function() S.sel = 1; startDeep(); ctx.refresh() end, function() return S.job == nil end,
            "Walk _G and everything reachable, flag undocumented names and save to PersistentDB key rdt_probe. Read only, runs over a few seconds.")
        ui.btn("Rescan", 60, function() if S.sel > 1 then scanSample() end; ctx.refresh() end, nil, "Read the sample members again.")
        S.field = ui.field(130, "Search names", "probe search", nil, "Type part of a name, then press Apply.")
        ui.btn("Apply", 48, function() S.filt = ctx.readField(S.field, 60) or ""; S.shown = nil; ctx.refresh() end, nil, "Filter the list by the search text.")
        ui.dd(130, ONLY, function() return S.only end, function(i) S.only = i; S.shown = nil end, nil, "probe show", "Limit the list.")
    end
    function spec.tick(active) if S.job then stepDeep() end end
    function spec.view()
        if S.sel > 1 and #S.rows == 0 and S.note == nil then scanSample() end
        if S.sel == 1 and #S.rows == 0 and S.job == nil and S.note == nil then
            local ok, st = pcall(function() return PersistentDB:GetStructuredData("rdt_probe") end)
            S.note = (ok and type(st) == "table") and ("Last saved scan: " .. tostring(st.rows) .. " names, " .. tostring(st.undocumented) .. " undocumented. Press Deep scan to run again.") or "Press Deep scan to walk the whole API."
        end
        local rows = filtered()
        return { cols = { { title = "Name", flex = 3, min = 140 }, { title = "Type", w = 60 }, { title = "Documented?", w = 76 }, { title = "Signature", flex = 2, min = 80 } },
            data = { count = #rows, get = function(i) local r = rows[i]
                local d = r.d == "yes" and H.col(H.C_GOOD, "yes") or (r.d == "name" and H.lbl("name only") or H.col(H.C_WARN, "UNDOCUMENTED"))
                return { H.val(r.k), H.lbl(r.t), d, H.lbl(r.s or ""), tip = "Found via " .. tostring(r.from) } end },
            detail = function() return { lines = { H.lbl(S.note or ""), H.lbl("Read only: nothing is called. yes = documented path, name only = the name appears in the docs elsewhere, UNDOCUMENTED = never in the docs. Undocumented names may change or vanish.") } } end }
    end
    function spec.shutdown() S.job = nil end
    return spec
end
return RDT_MODS["rdt_probe"]
