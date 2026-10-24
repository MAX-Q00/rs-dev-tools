--[[ rdt_prof.lua (0.3.0) Profiler tab (Inspect): times documented API calls
  with os.clock (N calls each, on a Run click), plus this panel's own layout
  cost and frame times from the Perf Meter data. Read-only calls only. ]]
-- 0.5.10: this client's require returns nil, so the module also registers itself in RDT_MODS.
RDT_MODS = RDT_MODS or {}
RDT_MODS["rdt_prof"] = function(ctx)
    local H = ctx.H
    local S = { res = {}, n = 200, running = false }
    local function V() return Vector3.new(1, 2, 3) end
    local BENCH = {
        { "Player.GetEntity", function() return Player.GetEntity() end },
        { "Player.GetEntity().position", function() return Player.GetEntity().position end },
        { "Camera.GetPosition", function() return Camera.GetPosition() end },
        { "World.GetPing", function() return World.GetPing() end },
        { "Mouse.GetPosition", function() return Mouse.GetPosition() end },
        { "ScreenConvert.Vector3ToScreen", function() return ScreenConvert.Vector3ToScreen(V()) end },
        { "NPCList.All", function() return NPCList.All() end },
        { "LocList.All", function() return LocList.All() end },
        { "PlayerList.All (count only)", function() return #PlayerList.All() end },
        { "ObjStackList.All", function() return ObjStackList.All() end },
        { "PersistentDB:CheckExists", function() return PersistentDB:CheckExists("rs_dev_tools") end },
        { "Vector3.new", function() return Vector3.new(1, 2, 3) end },
        { "string.format", function() return string.format("%d %s", 1, "a") end },
        { "Lua table insert x10", function() local t = {}; for i = 1, 10 do t[i] = i end; return t end },
    }
    local function run()
        local res = {}
        if not (os and os.clock) then S.res = { { "os.clock", "not available" } }; return end
        for _, b in ipairs(BENCH) do
            local ok = pcall(b[2])
            if not ok then res[#res + 1] = { b[1], "error", "-", "-" }
            else
                local t0 = os.clock()
                for _ = 1, S.n do b[2]() end
                local dt = os.clock() - t0
                res[#res + 1] = { b[1], tostring(S.n), string.format("%.2f", dt * 1000), string.format("%.1f", dt * 1e6 / S.n) }
            end
        end
        table.sort(res, function(a, b) return (tonumber(a[4]) or 1e9) > (tonumber(b[4]) or 1e9) end)
        S.res = res
    end
    local function stats(list)
        if type(list) ~= "table" or #list == 0 then return nil end
        local s, mx = 0, 0
        for _, v in ipairs(list) do s = s + v; if v > mx then mx = v end end
        return s / #list, mx
    end
    local spec = { name = "Profiler", cat = "Inspect" }
    function spec.build(ui)
        ui.dd(96, { "N = 50", "N = 200", "N = 1000" }, function() return ({ [50] = 1, [200] = 2, [1000] = 3 })[S.n] end,
            function(i) S.n = ({ 50, 200, 1000 })[i] end, nil, "prof n", "How many times each call is timed.")
        ui.btn("Run", 44, function() run(); ctx.refresh() end, nil, "Time every listed API call now (may hitch one frame).")
    end
    function spec.view()
        local rows = {}
        local a, m = stats(ctx.perf.cost)
        rows[#rows + 1] = { H.val("This panel layout"), H.lbl(#(ctx.perf.cost or {}) .. " samples"), H.lbl(a and string.format("%.2f", m * 1000) or "-"), H.lbl(a and string.format("%.0f", a * 1e6) or "-") }
        local fa, fm = stats(ctx.perf.frames)
        rows[#rows + 1] = { H.val("Frame time (Draw)"), H.lbl(#(ctx.perf.frames or {}) .. " frames"), H.lbl(fa and string.format("%.2f", fm * 1000) or "-"), H.lbl(fa and string.format("%.0f", fa * 1e6) or "-") }
        for _, r in ipairs(S.res) do rows[#rows + 1] = { H.val(r[1]), H.lbl(r[2]), H.lbl(r[3]), H.lbl(r[4]) } end
        return { cols = { { title = "Call", flex = 3, min = 130 }, { title = "Calls", w = 70, align = "right" }, { title = "Total / max ms", w = 90, align = "right" }, { title = "Per call us", w = 80, align = "right" } },
            data = ctx.arr(rows),
            detail = function() return { lines = { H.lbl("Run times each call N times with os.clock, slowest first. Layout and frame rows show max ms and average us.") } } end }
    end
    return spec
end
return RDT_MODS["rdt_prof"]
