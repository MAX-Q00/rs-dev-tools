--[[ rdt_db.lua (0.3.0) PersistentDB tab (Plugins): browse and edit this
  plugin's own saved data (PersistentDB is isolated per plugin, so other
  plugins' data cannot be reached). Set writes a typed value; Delete and
  Clear all need a Confirm click. ]]
return function(ctx)
    local H = ctx.H
    local S = { rows = {}, sel = nil, pending = nil, note = nil, typ = 1 }
    local TYPES = { "Type: auto", "Type: string", "Type: number", "Type: bool" }
    local function short(v)
        if type(v) == "table" then local n = 0; for _ in pairs(v) do n = n + 1 end; return "table, " .. n .. " keys" end
        return ctx.plain(tostring(v)):sub(1, 80)
    end
    local function scan()
        local rows = {}
        pcall(function() PersistentDB:IterateEntries(function(k, v) rows[#rows + 1] = { k = tostring(k), v = v }; return false end) end)
        table.sort(rows, function(a, b) return a.k < b.k end)
        S.rows = rows
    end
    local function parse(txt)
        if S.typ == 2 then return txt end
        if S.typ == 3 then return tonumber(txt) end
        if S.typ == 4 then return txt == "true" or txt == "1" or txt == "on" end
        if txt == "true" then return true elseif txt == "false" then return false end
        return tonumber(txt) or txt
    end
    local spec = { name = "PersistentDB", cat = "Plugins" }
    function spec.build(ui)
        S.keyF = ui.field(120, "Key", "db key", nil, "Key to set (letters, digits, _ and -).")
        S.valF = ui.field(140, "Value", "db value", nil, "Value to store. Tables are not edited here.")
        ui.dd(110, TYPES, function() return S.typ end, function(i) S.typ = i end, nil, "db type", "How to store the value: auto guesses number/bool/string.")
        ui.btn("Set", 40, function()
            local k = ctx.readField(S.keyF, 48):gsub("[^%w_%-]", "")
            local raw = ctx.readField(S.valF, 200)
            if k == "" then S.note = "Type a key first."; ctx.refresh(); return end
            local v = parse(raw)
            if v == nil then S.note = "Not a number."; ctx.refresh(); return end
            local ok, r = pcall(function()
                if type(v) == "boolean" then return PersistentDB:SetBool(k, v)
                elseif type(v) == "number" then if math.type(v) == "float" then return PersistentDB:SetFloat(k, v) else return PersistentDB:SetInt(k, v) end
                else return PersistentDB:Set(k, v) end
            end)
            S.note = ok and ("Set " .. k .. " = " .. tostring(v) .. " (" .. tostring(r) .. ")") or "Error setting " .. k
            scan(); ctx.refresh()
        end, nil, "Save the value under the key in this plugin's PersistentDB.")
        ui.btn("Delete", 52, function() if S.sel then S.pending = { "delete", S.sel.k }; S.note = "Confirm to delete " .. S.sel.k .. "." end; ctx.refresh() end,
            function() return S.sel ~= nil and S.pending == nil end, "Delete the selected key (needs Confirm).")
        ui.btn("Clear all", 64, function() S.pending = { "clear" }; S.note = "Confirm to delete EVERY entry of this plugin (its settings reset)."; ctx.refresh() end,
            function() return S.pending == nil end, "Delete every entry this plugin saved (needs Confirm).")
        ui.btn("Confirm", 64, function()
            local p = S.pending; S.pending = nil
            if p and p[1] == "delete" then local ok, r = pcall(function() return PersistentDB:Delete(p[2]) end); S.note = "Delete " .. p[2] .. ": " .. tostring(ok and r) ; S.sel = nil
            elseif p and p[1] == "clear" then local ok, r = pcall(function() return PersistentDB:Clear() end); S.note = "Clear: " .. tostring(ok and r) .. ". Settings return on next save." ; S.sel = nil end
            scan(); ctx.refresh()
        end, function() return S.pending ~= nil end, "Do the pending delete.")
        ui.btn("Cancel", 56, function() S.pending = nil; S.note = "Cancelled."; ctx.refresh() end, function() return S.pending ~= nil end, "Cancel the pending delete.")
        ui.btn("Rescan", 60, function() scan(); ctx.refresh() end, nil, "Read the entries again.")
    end
    function spec.view()
        if #S.rows == 0 then scan() end
        local rows = S.rows
        return { cols = { { title = "Key", flex = 2, min = 100 }, { title = "Type", w = 60 }, { title = "Value", flex = 3, min = 80 } },
            data = { count = #rows, get = function(i) local r = rows[i]; return { H.val(ctx.plain(r.k)), H.lbl(type(r.v)), H.lbl(short(r.v)) } end },
            onRow = function(i) S.sel = rows[i]; S.pending = nil; S.note = nil
                pcall(function() S.keyF.content = rows[i].k; if type(rows[i].v) ~= "table" then S.valF.content = tostring(rows[i].v) end end) end,
            detail = function()
                local L = { H.lbl(S.note or (#rows .. " entries for this plugin. Click one to load it into the Key and Value boxes.")) }
                if S.sel then
                    local k = S.sel.k
                    local t = {}
                    pcall(function()
                        for _, ty in ipairs({ "BOOL", "INT", "FLOAT", "STRING", "STRUCTURED_DATA" }) do
                            if PersistentDBType and PersistentDBType[ty] and PersistentDB:CheckExistsTyped(k, PersistentDBType[ty]) then t[#t + 1] = ty end
                        end
                    end)
                    L[#L + 1] = H.gold(ctx.plain(k)) .. H.lbl("  exists: " .. tostring(pcall(function() return PersistentDB:CheckExists(k) end) and PersistentDB:CheckExists(k)) .. (#t > 0 and ("  typed: " .. table.concat(t, ", ")) or ""))
                    if type(S.sel.v) == "table" then
                        local n = 0
                        for kk, vv in pairs(S.sel.v) do n = n + 1; if n <= 5 then L[#L + 1] = H.lbl("  " .. ctx.plain(tostring(kk)) .. " = ") .. H.val(short(vv)) end end
                    end
                end
                return { lines = L }
            end }
    end
    return spec
end
