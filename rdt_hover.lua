--[[ rdt_hover.lua (0.4.1): two read-only world helpers, both ON by default
  (Settings tab toggles, saved in this plugin's PersistentDB state).

  1. Menu tile coords: on Event.MiniMenuReady the tile under the mouse
     (ScreenConvert.ScreenToCoordGrid(Mouse.GetPosition())) is added as one
     informational MiniMenu entry via the documented MiniMenu:Add, with a
     do-nothing action. It is then moved with MiniMenu:Swap to index 1, the
     lowest priority (shown at the bottom of the open menu), so it is never
     the left-click default.
  2. Item hover info: the highest priority entry (last in entries) is read;
     if it is a ground item (objData.config) or an interface item
     (componentData.objConfig: inventory, bank, equipment) its
     "Name (id)" is shown in the shared cursor tooltip box.
  Everything is pcall-wrapped and fails silently. ]]
return function(ctx)
    local helpers, state = ctx.helpers, ctx.state
    local cur, curAt = nil, 0
    local function noop() end
    local function coordLabel(mm)
        local g
        pcall(function() if Mouse.IsAvailable() then g = ScreenConvert.ScreenToCoordGrid(Mouse.GetPosition()) end end)
        if g ~= nil then
            return string.format("Tile %d, %d, %d  (square %d,%d  local %d,%d)",
                g.level, g.x, g.z, g.mapSquareX, g.mapSquareZ, g.localX, g.localZ)
        end
        -- fallback: the Walk entry's ground tile (no level)
        for _, e in ipairs(mm.entries) do
            local gd = e.groundData
            if gd ~= nil and not gd.fromMiniMap then
                return string.format("Tile %d, %d", gd.coordGridX, gd.coordGridZ)
            end
        end
        return nil
    end
    local function onReady(ev)
        local mm = ev.miniMenu
        if mm == nil then return end
        if state.itemHover ~= false then
            local txt = nil
            pcall(function()
                local es = mm.entries
                local top = es[#es]
                if top == nil then return end
                local cfg = nil
                if top.objData ~= nil then cfg = top.objData.config
                elseif top.componentData ~= nil then cfg = top.componentData.objConfig end
                if cfg ~= nil then txt = tostring(cfg.name) .. " (" .. tostring(cfg.id) .. ")" end
            end)
            cur, curAt = txt, os.clock()
        else cur = nil end
        if state.menuCoords ~= false then
            pcall(function()
                local label = coordLabel(mm)
                if label == nil then return end
                mm:Add(label, noop)
                local es = mm.entries
                local n = #es
                local last = es[n]
                -- only reorder once our entry is confirmed at the end
                if last == nil or (last.overrideText ~= label and last.fullText ~= label
                    and last.actionEntryType ~= MiniMenuEntryType.PLUGIN) then return end
                for i = n, 2, -1 do mm:Swap(i, i - 1) end
            end)
        end
    end
    helpers.subscribe("rdt_hover", "MiniMenuReady", "rdtHoverReady", function(ev) pcall(onReady, ev) end)
    helpers.worldHover = function()
        if state.itemHover == false or cur == nil then return nil end
        if os.clock() - curAt > 0.5 then return nil end
        local open = false
        pcall(function() open = MiniMenu.IsOpen() end)
        if open then return nil end
        return cur
    end
    return true
end
