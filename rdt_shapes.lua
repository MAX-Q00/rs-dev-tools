--[[ rdt_shapes.lua (0.3.0) Shapes & Canvas tab (Debug): a playground for
  ShapeList.Draw / DrawLine, ShapeData registration, AABB maths and a
  ui.Canvas. Shapes are drawn around your own position, client-side only,
  off by default and removed when the plugin unloads. ]]
-- 0.5.10: this client's require returns nil, so the module also registers itself in RDT_MODS.
RDT_MODS = RDT_MODS or {}
RDT_MODS["rdt_shapes"] = function(ctx)
    local H = ctx.H
    local S = { shape = 1, on = false, depth = 1, width = 3, spin = true, t = 0, canvas = nil, canvasOn = false, res = {}, drawOk = nil, reg = nil }
    local SHAPES = { "Tile", "3x3 tiles", "Box", "Cross", "Registered ShapeData", "Line to camera focus" }
    local COL = 0x33DDFFFF
    local function V(x, y, z) return Vector3.new(x, y, z) end
    local function tilePts(r) return { V(-r, 0, -r), V(r, 0, -r), V(r, 0, r), V(-r, 0, r) }, { 0, 1, 1, 2, 2, 3, 3, 0 } end
    local function boxPts(r, h)
        return { V(-r, 0, -r), V(r, 0, -r), V(r, 0, r), V(-r, 0, r), V(-r, h, -r), V(r, h, -r), V(r, h, r), V(-r, h, r) },
            { 0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7 }
    end
    local function ensureReg()
        if S.reg ~= nil then return S.reg end
        S.reg = false
        pcall(function()
            local d = ShapeData.new()
            local p, l = boxPts(200, 400)
            d.positions = p; d.lines = l
            S.reg = ShapeData.Register("rdtBox", d) == true or ShapeData.IsRegistered("rdtBox")
        end)
        return S.reg
    end
    local function draw(dt)
        if not S.on then return end
        local pos
        pcall(function() if Player.IsAvailable() then pos = Player.GetEntity().position end end)
        if pos == nil then return end
        S.t = S.t + (dt or 0.02)
        local yaw = S.spin and (S.t * 90) % 360 or 0
        local base = { translation = V(pos.x, pos.y + 4, pos.z), rotation = V(yaw, 0, 0), ignoreDepth = S.depth == 2, colour = COL, lineWidth = S.width }
        local ok, err = pcall(function()
            if S.shape == 1 then base.shapePositions, base.shapeLines = tilePts(256); ShapeList.Draw(base)
            elseif S.shape == 2 then base.shapePositions, base.shapeLines = tilePts(768); ShapeList.Draw(base)
            elseif S.shape == 3 then base.shapePositions, base.shapeLines = boxPts(256, 600); ShapeList.Draw(base)
            elseif S.shape == 4 then
                ShapeList.DrawLine({ positions = { V(pos.x - 400, pos.y + 20, pos.z), V(pos.x + 400, pos.y + 20, pos.z) }, colour = COL, lineWidth = S.width, ignoreDepth = S.depth == 2 })
                ShapeList.DrawLine({ positions = { V(pos.x, pos.y + 20, pos.z - 400), V(pos.x, pos.y + 20, pos.z + 400) }, colour = COL, lineWidth = S.width, ignoreDepth = S.depth == 2 })
            elseif S.shape == 5 then
                if ensureReg() then base.shapeDataName = "rdtBox"; ShapeList.Draw(base) end
            else
                local f = Camera.GetFocusPosition()
                ShapeList.DrawLine({ positions = { V(pos.x, pos.y + 20, pos.z), V(f.x, f.y, f.z) }, colour = COL, lineWidth = S.width, ignoreDepth = true })
            end
        end)
        S.drawOk = ok
        if not ok then S.err = tostring(err) end
    end
    local subOk = pcall(function() Event.Draw.Subscribe("rdtShapesDraw", function(e) local dt = 0.02; pcall(function() dt = e.timeDeltaSecs end); pcall(draw, dt) end) end)
    local function canvas(show)
        local root = ctx.root()
        if root == nil then return end
        if S.canvas == nil and show then
            pcall(function()
                local c = ui.Canvas.new(root)
                c:SetSize(160, 80)
                c:AddOutline(0, 0, 160, 80, 2, 0xE0B040FF)
                c:AddLine(8, 72, 152, 8, 2, 0x33DDFFFF)
                c:AddGradientH(8, 8, 60, 24, 0x00000000, 0xFFCC33FF)
                c:AddGradientV(92, 40, 60, 32, 0x55FF33FF, 0x00000000)
                S.canvas = c
            end)
        end
        pcall(function()
            if S.canvas then
                S.canvas.hidden = not show
                if show then S.canvas:SetPos(-170, -120, 1.0, 1.0); S.canvas:MoveToFront() end
            end
        end)
    end
    local function aabbTests()
        local r = {}
        local ok = pcall(function()
            local a = AABB.new(V(0, 0, 0), V(512, 512, 512))
            r[#r + 1] = { "AABB:IsInside(256,256,256)", tostring(a:IsInside(V(256, 256, 256))) }
            r[#r + 1] = { "AABB:Intersects(line through)", tostring(a:Intersects(V(-100, 256, 256), V(600, 256, 256))) }
            r[#r + 1] = { "AABB:GetDistanceToPosition(1024,0,0)", string.format("%.0f", a:GetDistanceToPosition(V(1024, 0, 0))) }
            local c = a:GetClosestPosition(V(1024, 0, 0)); r[#r + 1] = { "AABB:GetClosestPosition", string.format("%.0f, %.0f, %.0f", c.x, c.y, c.z) }
            local rc = Rect.new(); rc:Grow(10, 10); r[#r + 1] = { "Rect.new():Grow(10,10):Contains(5,5)", tostring(rc:Contains(5, 5)) }
            local q = Quaternion.fromYawPitchRoll(90, 0, 0); local v = V(1, 0, 0):Rotate(q); r[#r + 1] = { "Vector3:Rotate(yaw 90)", string.format("%.2f, %.2f, %.2f", v.x, v.y, v.z) }
        end)
        if not ok then r[#r + 1] = { "maths", "error" } end
        S.res = r
    end
    local spec = { name = "Shapes & Canvas", cat = "Debug" }
    function spec.shutdown()
        S.on = false
        pcall(function() Event.Draw.Unsubscribe("rdtShapesDraw") end)
        pcall(function() if S.reg then ShapeData.Unregister("rdtBox") end end)
        pcall(function() if S.canvas then S.canvas:Destroy() end end)
    end
    function spec.tick(active) if not active then if S.canvasOn then canvas(false) end else canvas(S.canvasOn) end end
    function spec.build(ui)
        ui.dd(100, { "Shapes: Off", "Shapes: On" }, function() return S.on and 2 or 1 end, function(i) S.on = i == 2 end, nil, "shapes on", "Draw the chosen test shape around you (client-side only).")
        local names = {}
        for i, n in ipairs(SHAPES) do names[i] = n end
        ui.dd(170, names, function() return S.shape end, function(i) S.shape = i end, nil, "shape", "Which test shape to draw.")
        ui.dd(140, { "Depth: hidden by walls", "Depth: always on top" }, function() return S.depth end, function(i) S.depth = i end, nil, "shape depth", "ignoreDepth false or true.")
        ui.dd(90, { "Width 1", "Width 3", "Width 6", "Width 10" }, function() return ({ [1] = 1, [3] = 2, [6] = 3, [10] = 4 })[S.width] end,
            function(i) S.width = ({ 1, 3, 6, 10 })[i] end, nil, "shape width", "Line width (maximum 10).")
        ui.dd(90, { "Spin: Off", "Spin: On" }, function() return S.spin and 2 or 1 end, function(i) S.spin = i == 2 end, nil, "shape spin", "Rotate the shape once every 4 seconds.")
        ui.dd(110, { "Canvas: Off", "Canvas: On" }, function() return S.canvasOn and 2 or 1 end, function(i) S.canvasOn = i == 2 end, nil, "canvas", "Show a ui.Canvas test card (outline, line, gradients) in the panel corner.")
        ui.btn("Maths tests", 84, function() aabbTests(); ctx.refresh() end, nil, "Run AABB, Rect, Quaternion and Vector3 checks.")
    end
    function spec.view()
        local rows = {
            { ctx.H.val("Draw subscription"), ctx.H.lbl(subOk and "ok" or "failed") },
            { ctx.H.val("Last draw"), ctx.H.lbl(S.drawOk == nil and "not drawn yet" or (S.drawOk and "ok" or ("error: " .. ctx.plain(S.err or ""):sub(1, 60)))) },
            { ctx.H.val("ShapeData registered"), ctx.H.lbl(S.reg == nil and "not tried" or tostring(S.reg)) },
        }
        pcall(function() rows[#rows + 1] = { ctx.H.val("ShapeData.GetAllRegistered"), ctx.H.lbl(table.concat(ShapeData.GetAllRegistered() or {}, ", ")) } end)
        pcall(function() rows[#rows + 1] = { ctx.H.val("ShapeList.GetAllInstances"), ctx.H.lbl(tostring(#(ShapeList.GetAllInstances() or {}))) } end)
        for _, r in ipairs(S.res) do rows[#rows + 1] = { ctx.H.val(r[1]), ctx.H.lbl(r[2]) } end
        return { cols = { { title = "Check", flex = 2, min = 120 }, { title = "Result", flex = 2, min = 80 } }, data = ctx.arr(rows),
            detail = function() return { lines = { H.lbl("Shapes are drawn on your own position only. All off on load and when the plugin unloads.") } } end }
    end
    return spec
end
return RDT_MODS["rdt_shapes"]
