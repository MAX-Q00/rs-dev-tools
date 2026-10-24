--[[ rdt_sandbox.lua (0.5.0) Model Sandbox tab (Assets): client-side 3D
  models of NPCs, items or raw model IDs drawn in the game view, the same
  documented approach as Rotten Potato (ui.Model + SetModel, ScreenConvert.
  Vector3ToScreen, Camera pitch tilt, NPCType.bas.overlayHeight, id.Seq).
  Visual only: no console commands, no game input, nothing sent to the game.
  Safety (lessons from Rotten Potato 0.2.2/0.2.3):
  * model boxes are small (sized to the model, max 900px), marked
    click-through and disabled; whenever a box overlaps the panel the panel is
    re-raised above it, so panel buttons keep working;
  * only a 14px drag handle per model takes clicks, and it hides while it
    overlaps the panel;
  * every per-tick step and every button callback is pcall-guarded;
  * nothing is restored at load. A scene is only saved/loaded by its buttons.]]
-- 0.5.10: this client's require returns nil, so the module also registers itself in RDT_MODS.
RDT_MODS = RDT_MODS or {}
RDT_MODS["rdt_sandbox"] = function(ctx)
    local H, helpers = ctx.H, ctx.helpers
    local MAX = 20
    local SCENE_KEY = "rdt_sandbox_scene"
    local S = { objs = {}, sel = nil, mode = 1, q = "", res = {}, rsel = nil, kind = 1, drag = nil, err = nil, note = "", seq = nil, raiseT = 0 }
    local MODES = { "Show: Spawned", "Show: NPC search", "Show: Item search" }
    local KINDS = { "ID kind: NPC", "ID kind: Item", "ID kind: Model" }
    local KIND_OF = { "npc", "item", "model" }
    local scan = { npc = { next = nil, max = 40000, items = {} }, item = { next = nil, max = 65000, items = {} } }
    local function derr(w, e) S.err = w .. ": " .. tostring(e) end
    local function guard(name, f) return function(...) local ok, e = pcall(f, ...); if not ok then derr(name, e); pcall(ctx.logError, "sandbox " .. name, tostring(e)) end; pcall(ctx.refresh) end end
    local MC = require("model_core")   -- shared with Rotten Potato (0.5.1)
    local top, sc, screenWH, camYaw, camPitch, mouse = MC.top, MC.sc, MC.screenWH, MC.camYaw, MC.camPitch, MC.mouse
    local seqList, npcInfo, animName = MC.seqList, MC.npcInfo, MC.animName
    local function animsFor(o) return MC.animsFor(o, 40) end
    local function idleOf(o) return MC.idleOf(o, 40) end
    -- model objects
    local function setAnim(o) pcall(function() o.mdl.animID = o.play and o.anim or -1 end) end
    local function assign(o) MC.assign(o, function(e) derr("SetModel", e) end); setAnim(o) end
    local function destroy(o)
        pcall(function() o.mdl.hidden = true end); pcall(function() o.handle.hidden = true end)
        pcall(function() o.mdl:Destroy() end); pcall(function() o.handle:Destroy() end)
    end
    local function selIdx() for i, o in ipairs(S.objs) do if o == S.sel then return i end end; return nil end
    local function make(kind, nid, name, pos, opts)
        if #S.objs >= MAX then S.note = "Limit is " .. MAX .. " models. Delete one or Clear all."; return nil end
        local t = top(); if t == nil then S.note = "Plugin top layer not available."; return nil end
        nid = math.floor(tonumber(nid) or -1); if nid < 0 then S.note = "Pick an entry or type an ID first."; return nil end
        local o = { kind = kind, id = nid, name = name, yaw = 0, scale = 100, anim = -1, play = true, pin = false, h = 0 }
        if kind == "npc" then local n, h, tok = npcInfo(nid); o.name = name or n; o.h = h; o.tok = tok
        elseif kind == "item" then pcall(function() o.name = name or tostring(config.Obj.FromID(nid).name) end) end
        o.name = o.name or (kind .. " " .. nid)
        local e; o.mdl, e = MC.newBox(t)
        if o.mdl == nil then derr("ui.Model.new", e); S.note = "ui.Model could not be created."; return nil end
        pcall(function()
            o.handle = helpers.button(t, 0, 0, 14, 14, "+", function() end)
            o.handle.hidden = true
            o.handle:Subscribe(ui.Hook.ONCLICK, "sbDrag", function() pcall(function() S.sel = o; S.drag = { o = o, idle = 0 } end) end)
            o.handle:Subscribe(ui.Hook.ONHOLD, "sbHold", function() if S.drag then S.drag.idle = 0 end end)
            o.handle:Subscribe(ui.Hook.ONRELEASE, "sbRel", function() S.drag = nil; pcall(ctx.refresh) end)
            helpers.setTip(o.handle, "Drag to move " .. ctx.plain(o.name) .. ". Click to select it.")
        end)
        if opts then for k, v in pairs(opts) do o[k] = v end end
        if o.anim == -1 and kind == "npc" and not (opts and opts.anim) then o.anim = idleOf(o) end
        if pos then o.pos = pos
        elseif not o.pin then
            pcall(function() local p = Player.GetEntity().position; local n = #S.objs; o.pos = Vector3.new(p.x + 512 * ((n % 5) - 2), p.y, p.z + 512 * (1 + math.floor(n / 5))) end)
            if o.pos == nil then o.pin = true end
        end
        if o.pin and o.sx == nil then local w, h = screenWH(); o.sx, o.sy = w / 2 + 30 * (#S.objs % 5), h / 2 end
        assign(o)
        S.objs[#S.objs + 1] = o; S.sel = o
        S.note = "Spawned " .. ctx.plain(o.name) .. "."
        helpers.raiseFront()
        return o
    end
    ctx.sandbox = { spawn = function(kind, nid, name) local o = nil; pcall(function() o = make(kind, nid, name) end); pcall(ctx.refresh); return o ~= nil end }
    local function hideAll() for _, o in ipairs(S.objs) do pcall(function() o.mdl.hidden = true; o.handle.hidden = true end) end end
    local overlaps = MC.overlaps
    local function place(o, pr)
        local s = sc()
        local fx, fy, sz
        if o.pin then fx, fy = o.sx, o.sy; sz = math.floor(160 * o.scale / 100)
        else
            local feet, head
            pcall(function()
                feet = ScreenConvert.Vector3ToScreen(o.pos)
                local hh = (o.h and o.h > 100) and o.h or MC.HUMAN_H
                head = ScreenConvert.Vector3ToScreen(Vector3.new(o.pos.x, o.pos.y + hh * o.scale / 100, o.pos.z))
            end)
            if feet == nil or head == nil or feet.x ~= feet.x then pcall(function() o.mdl.hidden = true; o.handle.hidden = true end); o.off = true; return end
            o.off = false
            fx, fy = feet.x / s, feet.y / s
            sz = math.floor(math.abs(feet.y - head.y) / s * 1.6)
        end
        sz = MC.clamp(sz)   -- 24..900 px
        local w, h = screenWH()
        if fx < -sz or fy < -sz or fx > w + sz or fy > h + sz then pcall(function() o.mdl.hidden = true; o.handle.hidden = true end); o.off = true; return end
        local bx, by = math.floor(fx - sz / 2), math.floor(fy - sz * 0.8)
        pcall(function() o.mdl:SetSize(sz, sz); o.mdl:SetPos(bx, by); o.mdl.hidden = false end)
        pcall(function()
            local yaw = o.pin and o.yaw or (o.yaw - camYaw())
            local rotV = Vector3.new(math.rad(yaw), o.pin and 0 or camPitch(), 0); if not pcall(function() o.mdl.rotation = rotV end) then o.mdl:SetTransform(Vector3.new(0, 0, 0), rotV, Vector3.new(1, 1, 1), 0) end
        end)
        local hx, hy = math.floor(fx - 7), math.floor(fy + 2)
        local hideH = overlaps(pr, hx, hy, 14, 14)
        pcall(function() o.handle:SetPos(hx, hy); o.handle.hidden = hideH; o.handle.label = (o == S.sel) and "*" or "+" end)
        return overlaps(pr, bx, by, sz, sz)
    end
    local function dragStep()
        local d = S.drag; if d == nil then return end
        d.idle = d.idle + 1
        if d.idle > 8 then S.drag = nil; pcall(ctx.refresh); return end
        local m = mouse(); if m == nil then return end
        local o = d.o
        if o.pin then local s = sc(); o.sx, o.sy = m.x / s, m.y / s + 10
        else pcall(function() local c = ScreenConvert.ScreenToCoordFine(m); if c and c.position then o.pos = c.position end end) end
    end
    local function scanStep(k)
        local L = scan[k]; if L.next == nil then return end
        local stop = math.min(L.max, L.next + 600)
        for i = L.next, stop do
            pcall(function()
                local c = (k == "npc") and config.NPC.FromID(i) or config.Obj.FromID(i)
                local n = c and c.name
                if type(n) == "string" and n ~= "" and n ~= "null" then L.items[#L.items + 1] = { id = i, name = n, lower = n:lower() } end
            end)
        end
        L.next = stop + 1
        if L.next > L.max then L.next = nil end
    end
    local function filter()
        local k = S.mode == 2 and "npc" or "item"
        local L = scan[k]
        if #L.items == 0 and L.next == nil and not L.done then L.next = 0; L.done = true end
        local q, out = S.q:lower(), {}
        for _, e in ipairs(L.items) do if q == "" or tostring(e.id) == q or e.lower:find(q, 1, true) then out[#out + 1] = e; if #out >= 2000 then break end end end
        S.res = out
    end
    local spec = { name = "Model Sandbox", cat = "Assets" }
    function spec.tick(active, t)
        if S.mode > 1 and active then local k = S.mode == 2 and "npc" or "item"; if scan[k].next ~= nil then pcall(scanStep, k); if t % 25 == 0 then pcall(filter); pcall(ctx.refresh) end end end
        if #S.objs == 0 then return end
        pcall(dragStep)
        local pr = nil
        pcall(function() pr = helpers.panelRect() end)
        local over = false
        for _, o in ipairs(S.objs) do local ok, r = pcall(place, o, pr); if ok and r then over = true elseif not ok then derr("place", r) end end
        S.raiseT = S.raiseT + 1
        if over and S.raiseT >= 10 then S.raiseT = 0; helpers.raiseFront() end
        if active and S.drag and t % 10 == 0 then pcall(ctx.refresh) end
    end
    function spec.shutdown() for _, o in ipairs(S.objs) do destroy(o) end; S.objs = {}; S.sel = nil; S.drag = nil end
    local function cur() return S.sel end
    local function hasSel() return S.mode == 1 and S.sel ~= nil end
    local function onList() return S.mode == 1 end
    local function onSearch() return S.mode > 1 end
    local function num(f, lo, hi) local v = tonumber(ctx.readField(f, 10)); if v == nil then return nil end; return math.max(lo, math.min(hi, v)) end
    function spec.build(ui)
        ui.dd(130, MODES, function() return S.mode end, function(i) S.mode = i; S.rsel = nil; if i > 1 then pcall(filter) end end, nil, "sb mode", "Spawned models, or search NPCs / items to spawn.")
        S.fq = ui.field(140, "Search name or id", "sb search", onSearch, "Part of a name, or an exact ID.")
        ui.btn("Find", 40, guard("find", function() S.q = ctx.readField(S.fq, 40); filter() end), onSearch, "Filter the list (the scan fills in while this tab is open).")
        ui.btn("Spawn on screen", 110, guard("spawn", function() local e = S.rsel; if e then make(S.mode == 2 and "npc" or "item", e.id, e.name) else S.note = "Click a row first." end end), onSearch, "Place the picked NPC or item model in the game view near you.")
        ui.dd(110, KINDS, function() return S.kind end, function(i) S.kind = i end, nil, "sb kind", "What a typed ID means.")
        S.fid = ui.field(70, "ID", "sb id", nil, "NPC, item (Obj) or model ID.")
        ui.btn("Spawn ID", 70, guard("spawn id", function() make(KIND_OF[S.kind], num(S.fid, 0, 9999999)) end), nil, "Spawn the typed ID as the chosen kind.")
        -- selected model
        ui.btn("Yaw -45", 60, guard("yaw", function() local o = cur(); if o then o.yaw = (o.yaw - 45) % 360 end end), hasSel, "Turn the selected model left.")
        ui.btn("Yaw +45", 60, guard("yaw", function() local o = cur(); if o then o.yaw = (o.yaw + 45) % 360 end end), hasSel, "Turn the selected model right.")
        S.fdeg = ui.field(50, "deg", "sb deg", hasSel, "Facing in degrees (0-359).")
        ui.btn("Set yaw", 60, guard("yaw", function() local o, v = cur(), num(S.fdeg, -720, 720); if o and v then o.yaw = v % 360 end end), hasSel, "Use the typed degrees.")
        ui.btn("Size -", 50, guard("scale", function() local o = cur(); if o then o.scale = math.max(10, o.scale - 10) end end), hasSel, "Smaller (10% steps).")
        ui.btn("Size +", 50, guard("scale", function() local o = cur(); if o then o.scale = math.min(500, o.scale + 10) end end), hasSel, "Bigger (10% steps).")
        S.fsc = ui.field(50, "%", "sb scale", hasSel, "Size in percent (10-500).")
        ui.btn("Set size", 60, guard("scale", function() local o, v = cur(), num(S.fsc, 10, 500); if o and v then o.scale = math.floor(v) end end), hasSel, "Use the typed size.")
        ui.dd(170, function()
            local o = cur(); local L = { "Anim: none" }
            if o then for _, it in ipairs(animsFor(o)) do L[#L + 1] = it.name .. " (" .. it.id .. ")" end end
            return L
        end, function() local o = cur(); if o then for i, it in ipairs(animsFor(o)) do if it.id == o.anim then return i + 1 end end end; return 1 end,
        function(i) local o = cur(); if o then local it = animsFor(o)[i - 1]; o.anim = it and it.id or -1; o.play = true; setAnim(o) end end, hasSel, "sb anim",
        "Animations whose id.Seq name matches this NPC. NPCs start on their idle (ready/stand) animation.")
        S.fan = ui.field(60, "anim id", "sb animid", hasSel, "Any SeqType ID. -1 = none.")
        ui.btn("Set anim", 64, guard("anim", function() local o, v = cur(), num(S.fan, -1, 999999); if o and v then o.anim = math.floor(v); o.play = true; setAnim(o) end end), hasSel, "Use the typed animation ID.")
        ui.btn("Play/Stop", 70, guard("play", function() local o = cur(); if o then o.play = not o.play; setAnim(o) end end), hasSel, "Start or stop the selected model's animation.")
        ui.btn("Pin/World", 70, guard("pin", function()
            local o = cur(); if not o then return end
            if o.pin then pcall(function() local c = ScreenConvert.ScreenToCoordFine(Vector2.new(o.sx * sc(), o.sy * sc())); if c and c.position then o.pos = c.position; o.pin = false end end)
                if o.pin then S.note = "No ground under the pinned spot; drag it over the ground and try again." end
            else local s = sc(); local p = nil; pcall(function() p = ScreenConvert.Vector3ToScreen(o.pos) end)
                local w, h = screenWH(); o.sx, o.sy = p and p.x / s or w / 2, p and p.y / s or h / 2; o.pin = true end
        end), hasSel, "Pin to screen (stays put on screen) or anchor to the world tile under it (stays put as the camera moves).")
        ui.btn("Duplicate", 70, guard("dup", function() local o = cur(); if o then make(o.kind, o.id, o.name, o.pos and Vector3.new(o.pos.x + 512, o.pos.y, o.pos.z) or nil,
            { yaw = o.yaw, scale = o.scale, anim = o.anim, play = o.play, pin = o.pin, sx = o.sx and o.sx + 30, sy = o.sy }) end end), hasSel, "Copy the selected model one tile over.")
        ui.btn("Delete", 56, guard("delete", function() local i = selIdx(); if i then destroy(S.objs[i]); table.remove(S.objs, i); S.sel = S.objs[math.min(i, #S.objs)]; if S.drag and S.drag.o and selIdx() == nil then S.drag = nil end end end), hasSel, "Remove the selected model.")
        ui.btn("Clear all", 64, guard("clear", function() spec.shutdown(); S.note = "Cleared." end), onList, "Remove every spawned model.")
        ui.btn("Save scene", 76, guard("save", function()
            local out = {}
            for _, o in ipairs(S.objs) do out[#out + 1] = { kind = o.kind, id = o.id, name = o.name, yaw = o.yaw, scale = o.scale, anim = o.anim, play = o.play, pin = o.pin, sx = o.sx, sy = o.sy,
                px = o.pos and o.pos.x, py = o.pos and o.pos.y, pz = o.pos and o.pos.z } end
            PersistentDB:SetStructuredData(SCENE_KEY, { objs = out }); S.note = "Saved " .. #out .. " models. Load scene brings them back; nothing loads on its own."
        end), onList, "Save the current models to this plugin's PersistentDB (rdt_sandbox_scene).")
        ui.btn("Load scene", 76, guard("load", function()
            local d = PersistentDB:GetStructuredData(SCENE_KEY)
            if type(d) ~= "table" or type(d.objs) ~= "table" then S.note = "No saved scene."; return end
            spec.shutdown()
            for _, r in ipairs(d.objs) do
                local pos = (r.px and r.pz) and Vector3.new(r.px, r.py or 0, r.pz) or nil
                make(r.kind, r.id, r.name, pos, { yaw = r.yaw or 0, scale = r.scale or 100, anim = r.anim or -1, play = r.play ~= false, pin = r.pin == true or pos == nil, sx = r.sx, sy = r.sy })
            end
            S.note = "Loaded " .. #S.objs .. " models."
        end), onList, "Replace the current models with the saved scene.")
    end
    local function tile(o)
        if o.pin then return "pinned " .. math.floor(o.sx or 0) .. "," .. math.floor(o.sy or 0) end
        local s = "-"
        pcall(function() local c = CoordGrid.new(0, o.pos); s = string.format("%d, %d, %d", c.level or 0, c.x or 0, c.z or 0) end)
        return s
    end
    function spec.view(active)
        if S.mode > 1 then
            local k = S.mode == 2 and "npc" or "item"
            local L = scan[k]
            return { key = k, cols = { { title = "Name", flex = 3, min = 110 }, { title = "ID", w = 64 } },
                data = { count = #S.res, get = function(i) local e = S.res[i]; return { H.val(ctx.plain(e.name)), H.lbl(e.id) } end },
                onRow = function(i) S.rsel = S.res[i] end,
                detail = function()
                    local head = H.lbl("Matches ") .. H.val(#S.res) .. H.lbl(" of ") .. H.val(#L.items) .. (L.next and H.lbl("  (scanning " .. math.floor(100 * L.next / L.max) .. "%)") or "")
                    local e = S.rsel
                    return { lines = { head, e and (H.gold(ctx.plain(e.name)) .. H.lbl("  id ") .. H.val(e.id) .. H.lbl("  press Spawn on screen")) or H.lbl("Click a row, then Spawn on screen. Models: " .. #S.objs .. "/" .. MAX), H.lbl(S.note) } }
                end }
        end
        return { key = "spawned", cols = { { title = "#", w = 26 }, { title = "Name", flex = 3, min = 90 }, { title = "ID", w = 60 }, { title = "Kind", w = 46 }, { title = "Tile", flex = 2, min = 80 }, { title = "Anim", flex = 2, min = 70 } },
            data = { count = #S.objs, get = function(i) local o = S.objs[i]
                return { (o == S.sel) and H.gold(i) or H.lbl(i), H.val(ctx.plain(o.name)), H.lbl(o.id), H.lbl(o.kind), H.lbl(tile(o) .. (o.off and " (off screen)" or "")), H.lbl(animName(o.play and o.anim or -1)) } end },
            onRow = function(i) S.sel = S.objs[i] end,
            detail = function()
                local o = S.sel
                local lines = { H.lbl("Models ") .. H.val(#S.objs .. "/" .. MAX) .. H.lbl(". Drag a model's small + handle to move it. Client side only: nobody else sees these.") }
                if o then lines[#lines + 1] = H.gold(ctx.plain(o.name)) .. H.lbl("  yaw ") .. H.val(o.yaw) .. H.lbl("  size ") .. H.val(o.scale .. "%") .. H.lbl("  ") .. H.val(o.pin and "pinned to screen" or "anchored to world") .. H.lbl(o.play and "  playing" or "  stopped") end
                if S.note ~= "" then lines[#lines + 1] = H.lbl(S.note) end
                if S.err then lines[#lines + 1] = H.col(H.C_WARN or "ff9040", ctx.plain(S.err)) end
                return { lines = lines }
            end }
    end
    return spec
end
return RDT_MODS["rdt_sandbox"]
