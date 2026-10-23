--[[ rdt_world.lua (0.3.0) Camera & World tab (Inspect): live read-only
  readouts from Camera, Player, World, ScreenConvert, Mouse, Keyboard and the
  entity lists (counts only; no other player's details are shown). ]]
return function(ctx)
    local H = ctx.H
    local S = { rows = {} }
    local function v3(v) if v == nil then return "-" end; return string.format("%.0f, %.0f, %.0f", v.x or 0, v.y or 0, v.z or 0) end
    local function cg(c) if c == nil then return "-" end
        local s = "-"
        pcall(function() s = string.format("level %d  x %d  z %d", c.level or 0, c.x or 0, c.z or 0) end)
        return s end
    local function try(label, fn, api)
        local ok, v = pcall(fn)
        S.rows[#S.rows + 1] = { H.val(label), ok and H.lbl(ctx.plain(tostring(v == nil and "nil" or v))) or H.col(H.C_BAD, "error"), H.lbl(api) }
    end
    local function sample()
        S.rows = {}
        try("Camera available", function() return Camera.IsAvailable() end, "Camera.IsAvailable")
        try("Camera position", function() return v3(Camera.GetPosition()) end, "Camera.GetPosition")
        try("Camera focus", function() return v3(Camera.GetFocusPosition()) end, "Camera.GetFocusPosition")
        try("Camera distance", function()
            local a, b = Camera.GetPosition(), Camera.GetFocusPosition()
            return string.format("%.0f units", math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)) end, "Camera (computed)")
        try("Player available", function() return Player.IsAvailable() end, "Player.IsAvailable")
        try("Your position", function() return v3(Player.GetEntity().position) end, "PlayerEntity.position")
        try("Your tile", function() return cg(CoordGrid.new(0, Player.GetEntity().position)) end, "CoordGrid.new(level, Vector3)")
        try("Combat level", function() return Player.GetCombatLevel() end, "Player.GetCombatLevel")
        try("Run energy", function() return Player.GetRunEnergy() end, "Player.GetRunEnergy")
        try("Weight", function() return Player.GetWeight() end, "Player.GetWeight")
        try("World available", function() return World.IsAvailable() end, "World.IsAvailable")
        try("Members world", function() return World.IsMembers() end, "World.IsMembers")
        try("Ping", function() return World.GetPing() .. " ms" end, "World.GetPing")
        try("Reboot timer", function() return World.GetRebootTimer() end, "World.GetRebootTimer")
        try("Region (instance)", function() return World.IsRegion() end, "World.IsRegion")
        try("Map square bounds", function() local r = World.GetMapSquareBounds(); return r and string.format("%s, %s  %s x %s", r.x, r.y, r.width or r.w, r.height or r.h) or "nil" end, "World.GetMapSquareBounds")
        try("Ground height here", function()
            local p = Player.GetEntity().position
            local h, ok = World.GetGroundHeight(0, math.floor(p.x), math.floor(p.z))
            return tostring(h) .. (ok and "" or " (not available)") end, "World.GetGroundHeight")
        try("Mouse (window px)", function() local p = Mouse.GetPosition(); return p and (math.floor(p.x) .. ", " .. math.floor(p.y)) or "nil" end, "Mouse.GetPosition")
        try("Tile under mouse", function() return cg(ScreenConvert.ScreenToCoordGrid(Mouse.GetPosition())) end, "ScreenConvert.ScreenToCoordGrid")
        try("Fine coord under mouse", function() local c = ScreenConvert.ScreenToCoordFine(Mouse.GetPosition()); return c and v3(c.position) or "nil" end, "ScreenConvert.ScreenToCoordFine")
        try("You on screen", function() local s = ScreenConvert.Vector3ToScreen(Player.GetEntity().position); return s and (math.floor(s.x) .. ", " .. math.floor(s.y)) or "off screen" end, "ScreenConvert.Vector3ToScreen")
        try("Modifier keys", function()
            local t = {}
            if Keyboard.IsShiftDown() then t[#t + 1] = "Shift" end
            if Keyboard.IsControlDown() then t[#t + 1] = "Ctrl" end
            if Keyboard.IsAltDown() then t[#t + 1] = "Alt" end
            if Keyboard.IsMetaDown() then t[#t + 1] = "Meta" end
            return #t > 0 and table.concat(t, "+") or "none" end, "Keyboard.Is*Down")
        try("Keyboard blocked", function() return Keyboard.IsBlocked() end, "Keyboard.IsBlocked")
        try("Game keys down", function() return #(Keyboard.GetGameKeysDown() or {}) end, "Keyboard.GetGameKeysDown")
        try("NPCs loaded", function() return #NPCList.All() end, "NPCList.All")
        try("NPCs within 10 tiles", function() return #NPCList.ByDistance(CoordGrid.new(0, Player.GetEntity().position), 10) end, "NPCList.ByDistance")
        try("Players loaded (count)", function() return #PlayerList.All() end, "PlayerList.All")
        try("Locs loaded", function() return #LocList.All() end, "LocList.All")
        try("Ground item stacks", function() return #ObjStackList.All() end, "ObjStackList.All")
        try("Mini menu open", function() return MiniMenu.IsOpen() end, "MiniMenu.IsOpen")
    end
    local spec = { name = "Camera & World", cat = "Inspect" }
    function spec.tick(active, t) if active and t % 25 == 0 then sample(); ctx.refresh() end end
    function spec.build(ui)
        ui.btn("Copy all", 64, function() S.copy = true; ctx.refresh() end, nil, "Put every readout in the copy box.")
    end
    function spec.view()
        if #S.rows == 0 then pcall(sample) end
        local rows = S.rows
        return { cols = { { title = "Readout", flex = 2, min = 110 }, { title = "Value", flex = 2, min = 90 }, { title = "API", flex = 2, min = 90 } },
            data = ctx.arr(rows),
            detail = function()
                local copy = nil
                if S.copy then
                    S.copy = false
                    local t = {}
                    for _, r in ipairs(rows) do t[#t + 1] = ctx.untag(r[1]) .. ": " .. ctx.untag(r[2]) end
                    copy = table.concat(t, "; ")
                end
                return { lines = { H.lbl("Updates twice a second while this tab is open. 512 fine units = 1 tile.") }, copy = copy }
            end }
    end
    return spec
end
