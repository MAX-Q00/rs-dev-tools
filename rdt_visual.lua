--[[ rdt_visual.lua Visual Overrides tab (Debug): client
  side draw filters through Event.EntityDraw (return false = not drawn).
  Nothing is removed from the game; turning an option off draws it again.
  Hides ground items, yourself, or NPCs by name (hide matching / show only
  matching). Subscribed directly, never through helpers.subscribe, so the
  return value is kept. ]]
-- 0.5.10: this client's require returns nil, so the module also registers itself in RDT_MODS.
RDT_MODS = RDT_MODS or {}
RDT_MODS["rdt_visual"] = function(ctx)
    local H = ctx.H
    local S = { items = false, self = false, mode = 1, filt = "", hidden = 0, me = nil }
    local MODES = { "NPC name: off", "Hide matching", "Show only matching" }
    local ET = {}
    pcall(function() ET.NPC, ET.PLAYER, ET.OBJ = EntityType.NPC, EntityType.PLAYER, EntityType.OBJSTACK end)
    local function any() return S.items or S.self or (S.mode > 1 and S.filt ~= "") end
    local function draw(ev)
        if not any() then return true end
        local keep = true
        pcall(function()
            local t = ev.entityType
            if t == ET.OBJ and S.items then keep = false
            elseif t == ET.PLAYER and S.self then
                if S.me and ev.playerEntity and ev.playerEntity.name == S.me then keep = false end
            elseif t == ET.NPC and S.mode > 1 and S.filt ~= "" then
                local n = tostring(ev.npcEntity and ev.npcEntity.name or ""):lower()
                local hit = n:find(S.filt, 1, true) ~= nil
                if S.mode == 2 then keep = not hit else keep = hit end
            end
        end)
        if not keep then S.hidden = S.hidden + 1 end
        return keep
    end
    local subbed = false
    local function sync()
        if any() and not subbed then subbed = pcall(function() Event.EntityDraw.Subscribe("rdtuVisual", draw) end)
        elseif not any() and subbed then pcall(function() Event.EntityDraw.Unsubscribe("rdtuVisual") end); subbed = false end
    end
    local spec = { name = "Visual Overrides", cat = "Debug" }
    function spec.tick(active, t)
        if t % 50 == 0 then pcall(function() local e = Player.GetEntity(); S.me = e and e.name or S.me end); if active then S.rate = S.hidden; S.hidden = 0; ctx.refresh() end end
    end
    function spec.shutdown() pcall(function() Event.EntityDraw.Unsubscribe("rdtuVisual") end); subbed = false end
    function spec.build(ui)
        ui.dd(110, { "Items: shown", "Items: hidden" }, function() return S.items and 2 or 1 end, function(i) S.items = i == 2; sync() end, nil, "vis items", "Hide ground items (client side).")
        ui.dd(100, { "Self: shown", "Self: hidden" }, function() return S.self and 2 or 1 end, function(i) S.self = i == 2; sync() end, nil, "vis self", "Hide your own character (client side).")
        ui.dd(130, MODES, function() return S.mode end, function(i) S.mode = i; sync() end, nil, "vis mode", "Filter NPCs by name.")
        S.f = ui.field(120, "NPC name contains", "vis filter", nil, "Part of an NPC name, any case.")
        ui.btn("Apply", 48, function() S.filt = ctx.readField(S.f, 40):lower(); sync(); ctx.refresh() end, nil, "Use the typed NPC name.")
        ui.btn("All off", 56, function() S.items, S.self, S.mode = false, false, 1; sync(); ctx.refresh() end, nil, "Draw everything again.")
    end
    local function onOff(v) return v and H.col(H.C_GOOD, "On") or H.lbl("Off") end
    function spec.view()
        local rows = {
            { H.val("Hide ground items"), onOff(S.items), H.lbl("ObjStack entities skip drawing") },
            { H.val("Hide self"), onOff(S.self), H.lbl("your PlayerEntity skips drawing" .. (S.me and "" or " (name not read yet)")) },
            { H.val("NPC name filter"), onOff(S.mode > 1 and S.filt ~= ""), H.lbl(MODES[S.mode] .. (S.filt ~= "" and (": " .. ctx.plain(S.filt)) or "")) },
            { H.val("Draw calls skipped"), H.lbl(tostring(S.rate or 0)), H.lbl("in the last second") },
            { H.val("Hooked"), onOff(subbed), H.lbl("Event.EntityDraw subscriber rdtuVisual") },
        }
        return { cols = { { title = "Option", flex = 2, min = 100 }, { title = "State", w = 60 }, { title = "Note", flex = 3, min = 80 } }, data = ctx.arr(rows),
            detail = function() return { lines = { H.lbl("Client side only. Guidelines allow hiding entities; recolouring player models is not allowed and is not offered.") } } end }
    end
    return spec
end
return RDT_MODS["rdt_visual"]
