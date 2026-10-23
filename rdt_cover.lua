--[[ rdt_cover.lua (0.3.0) API Coverage tab (Help): every documented API
  entry and event, whether this build of RS Dev Tools uses it (generated
  into rdt_api_data.lua by release/gen_api_data.py), and a live check that
  the name exists in this client. Read only. ]]
return function(ctx)
    local H = ctx.H
    local D = { rows = {} }
    pcall(function() D = require("rdt_api_data") end)
    local S = { f = 1 }
    local FILT = { "Show: all", "Show: used", "Show: not used", "Show: missing in client" }
    local live = {}
    local function present(kind, k)
        if live[k] ~= nil then return live[k] end
        local r = "?"
        pcall(function()
            if kind == "event" then r = (Event[k] ~= nil) and "yes" or "no"
            elseif k:find(":") then local t = k:match("^[^:]+"); r = (_G[t] ~= nil) and "yes" or "type"
            elseif k:find("%.") then local t, m = k:match("^([^.]+)%.(.+)$"); local g = _G[t]; r = (g ~= nil and g[m] ~= nil) and "yes" or "no"
            else r = (_G[k] ~= nil) and "yes" or "no" end
        end)
        live[k] = r
        return r
    end
    local function used(r) return r[3] ~= "" or (ctx.unl and r[4] ~= "") end
    local spec = { name = "API Coverage", cat = "Help" }
    function spec.build(ui)
        ui.dd(150, FILT, function() return S.f end, function(i) S.f = i end, nil, "cover filter", "Filter the list.")
        ui.btn("Recheck", 64, function() live = {}; ctx.refresh() end, nil, "Check the client again.")
    end
    function spec.view()
        local rows, nu = {}, 0
        for _, r in ipairs(D.rows or {}) do
            local u = used(r)
            if u then nu = nu + 1 end
            local p = present(r[1], r[2])
            if S.f == 1 or (S.f == 2 and u) or (S.f == 3 and not u) or (S.f == 4 and p == "no") then rows[#rows + 1] = r end
        end
        local total = #(D.rows or {})
        return { cols = { { title = "Name", flex = 3, min = 140 }, { title = "Kind", w = 44 }, { title = "Used", w = 44 }, { title = "Client", w = 50 }, { title = "Where", flex = 2, min = 60 } },
            data = { count = #rows, get = function(i) local r = rows[i]; local u = used(r); local p = present(r[1], r[2])
                local w = r[3]; if ctx.unl and r[4] ~= "" then w = (w ~= "" and (w .. ",") or "") .. r[4] end
                return { H.val(r[2]), H.lbl(r[1]), u and H.col(H.C_GOOD, "yes") or H.col(H.C_WARN, "no"),
                    p == "yes" and H.lbl("yes") or (p == "type" and H.lbl("type") or H.col(H.C_BAD, p)), H.lbl(w:gsub(",", ", ")), tip = w ~= "" and ("Used in " .. w:gsub(",", ", ")) or nil } end },
            detail = function() return { lines = { H.lbl(nu .. " of " .. total .. " documented entries are used by this build. Client: yes = the name exists now; type = a method on objects of that type (checked when one exists)."), H.lbl("The full matrix is in release/coverage-matrix.md.") } } end }
    end
    return spec
end
