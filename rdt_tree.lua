--[[ rdt_tree.lua (0.3.0) Component Tree tab (Inspect): walks this plugin's
  own panel with ComponentCollection:IterateStaticComponents and
  IterateDynamicComponents and lists every component with depth, type,
  position, size and visibility. Read only; other plugins are untouched. ]]
-- 0.5.10: this client's require returns nil, so the module also registers itself in RDT_MODS.
RDT_MODS = RDT_MODS or {}
RDT_MODS["rdt_tree"] = function(ctx)
    local H = ctx.H
    local S = { rows = {}, sel = nil, maxDepth = 3 }
    local function kind(c)
        local s = "component"
        pcall(function() s = tostring(c):match("^([%w_%.]+)") or s end)
        return ctx.plain(s)
    end
    local function walk(c, depth, out, how)
        if #out > 400 then return end
        local r = { depth = depth, how = how, c = c }
        pcall(function() local p = c.xyGlobal; r.x, r.y = math.floor(p.x), math.floor(p.y) end)
        pcall(function() r.w, r.h = math.floor(c.width), math.floor(c.height) end)
        pcall(function() r.hidden = c.hidden == true end)
        pcall(function() r.text = c.content or c.label end)
        out[#out + 1] = r
        if depth >= S.maxDepth then return end
        pcall(function() c:IterateStaticComponents(function(ch, vis) walk(ch, depth + 1, out, "static"); return false end) end)
        pcall(function() c:IterateDynamicComponents(function(ch, vis) walk(ch, depth + 1, out, "dynamic"); return false end) end)
    end
    local function scan() local out = {}; local root = ctx.root(); if root then walk(root, 0, out, "root") end; S.rows = out end
    local spec = { name = "Component Tree", cat = "Inspect" }
    function spec.build(ui)
        ui.btn("Rescan", 60, function() scan(); ctx.refresh() end, nil, "Walk this panel's components again.")
        ui.dd(96, { "Depth 1", "Depth 2", "Depth 3", "Depth 4", "Depth 6" }, function() return ({ [1] = 1, [2] = 2, [3] = 3, [4] = 4, [6] = 5 })[S.maxDepth] or 3 end,
            function(i) S.maxDepth = ({ 1, 2, 3, 4, 6 })[i]; scan() end, nil, "tree depth", "How many levels below the panel root to walk.")
    end
    function spec.view()
        if #S.rows == 0 then pcall(scan) end
        local rows = S.rows
        return { cols = { { title = "Component", flex = 2, min = 110 }, { title = "Child of", w = 60 }, { title = "Position", w = 80 },
                { title = "Size", w = 70 }, { title = "State", w = 52 } },
            data = { count = #rows, get = function(i)
                local r = rows[i]
                return { H.val(string.rep("  ", r.depth) .. kind(r.c)), H.lbl(r.how), H.lbl(r.x and (r.x .. ", " .. r.y) or "-"),
                    H.lbl(r.w and (r.w .. " x " .. r.h) or "-"), H.lbl(r.hidden and "hidden" or "shown"),
                    tip = r.text and ("Text: " .. ctx.plain(tostring(r.text)):sub(1, 120)) or nil }
            end },
            onRow = function(i) S.sel = rows[i] end,
            detail = function()
                local r = S.sel
                if r == nil then return { lines = { H.lbl(#rows .. " components in this panel. Click one for details.") } } end
                return { lines = { H.gold(kind(r.c)) .. H.lbl("  depth " .. r.depth .. ", " .. r.how),
                    H.lbl("Position ") .. H.val(r.x and (r.x .. ", " .. r.y) or "-") .. H.lbl("  size ") .. H.val(r.w and (r.w .. " x " .. r.h) or "-"),
                    H.lbl("Text: ") .. H.val(r.text and ctx.plain(tostring(r.text)):sub(1, 80) or "-") } }
            end }
    end
    return spec
end
return RDT_MODS["rdt_tree"]
