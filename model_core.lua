--[[ model_core.lua (2026-10-23) Shared client-side model helpers for
  Rotten Potato (rp_npcs.lua) and RS Dev Tools (rdt_sandbox.lua). The same
  file ships in both plugins (canonical copy: rs-dev-tools\model_core.lua,
  synced by devtabs\tools\sync_shared.ps1). Documented API only: ui.Model + SetModel,
  ScreenConvert, Camera, Mouse, config.NPC/Obj, id.Seq. Visual only.
  Rules kept here so both plugins follow them:
  * model boxes clamp to 24..MAX_BOX (900) px;
  * new boxes are hidden, click-through and disabled;
  * every engine call is pcall-guarded;
  * nothing is restored at load (no state here at all except the Seq list). ]]
local helpers = require("ui_helpers")
local M = { MAX_BOX = 900, MIN_BOX = 24, HUMAN_H = 1000 }
function M.top() return helpers.ensureHoverLayer() end
function M.sc() local s = 1; pcall(function() s = helpers.uiScale() or 1 end); if type(s) ~= "number" or s <= 0 then s = 1 end; return s end
function M.screenWH() local w, h = 1280, 720; pcall(function() local t = M.top(); if t.width > 0 then w, h = t.width, t.height end end); return w, h end
function M.camYaw() local y = 0; pcall(function() local c, f = Camera.GetPosition(), Camera.GetFocusPosition(); y = math.deg(math.atan(f.x - c.x, f.z - c.z)) end); return y end
function M.camPitch() local p = 0; pcall(function() local c, f = Camera.GetPosition(), Camera.GetFocusPosition(); p = math.atan(c.y - f.y, math.sqrt((f.x - c.x) ^ 2 + (f.z - c.z) ^ 2)) end); return p end
function M.mouse() local m = nil; pcall(function() if Mouse.IsAvailable() then m = Mouse.GetPosition() end end); return m end
local seq = nil
function M.seqList()
    if seq then return seq end
    seq = {}
    pcall(function() for k, v in pairs(id.Seq) do if type(k) == "string" and type(v) == "number" then seq[#seq + 1] = { id = v, name = k, lower = k:lower() } end end end)
    table.sort(seq, function(a, b) return a.id < b.id end)
    return seq
end
function M.npcInfo(nid)
    local name, h, tok = "NPC " .. nid, 0, nil
    pcall(function() local c = config.NPC.FromID(nid); name = tostring(c.name or name)
        tok = string.lower(tostring(c.configName or "")):match("^([a-z]+)")
        if tok == nil or #tok < 3 then tok = string.lower(tostring(c.name or "")):match("^([a-z]+)") end end)
    pcall(function() h = tonumber(config.NPC.FromID(nid).bas.overlayHeight) or 0 end)
    return name, h, tok
end
function M.animsFor(o, limit)
    if o.anims then return o.anims end
    local out = {}
    if o.tok and #o.tok >= 3 then
        for _, it in ipairs(M.seqList()) do
            if it.lower:find(o.tok, 1, true) == 1 or it.lower:find("_" .. o.tok, 1, true) then out[#out + 1] = it; if #out >= (limit or 40) then break end end
        end
    end
    o.anims = out
    return out
end
function M.idleOf(o, limit)
    local best = nil
    for _, it in ipairs(M.animsFor(o, limit)) do
        local l = it.lower
        if (l:find("ready", 1, true) or l:find("stand", 1, true) or l:find("idle", 1, true)) and (best == nil or #l < #best.lower) then best = it end
    end
    return best and best.id or -1
end
function M.animName(a) if a == nil or a < 0 then return "none" end; for _, it in ipairs(M.seqList()) do if it.id == a then return it.name end end; return tostring(a) end
--- SetModel for o.kind ("npc" | "item" | "model") on o.mdl; errors go to onErr(e).
function M.assign(o, onErr)
    local ok, e = pcall(function()
        if o.kind == "npc" then o.mdl:SetModel(ui.ModelType.NPC_MODEL, o.id)
        elseif o.kind == "item" then if not pcall(function() o.mdl:SetModel(ui.ModelType.OBJECT, o.id) end) then o.mdl:SetAssociatedObject(o.id) end
        else o.mdl:SetModel(ui.ModelType.MODEL, o.id) end
    end)
    if not ok and onErr then pcall(onErr, e) end
    pcall(function() o.mdl.orthographic = false end)
    return ok
end
--- New hidden, click-through, disabled ui.Model on layer t (pcall-guarded).
function M.newBox(t)
    local m = nil
    local ok, e = pcall(function()
        m = ui.Model.new(t); m:SetSize(120, 120); m.hidden = true
        pcall(function() m.clickthrough = true end); pcall(function() m.enabled = false end)
    end)
    if not ok then return nil, e end
    return m
end
function M.clamp(sz) if sz ~= sz or sz < M.MIN_BOX then return M.MIN_BOX elseif sz > M.MAX_BOX then return M.MAX_BOX end; return sz end
function M.overlaps(r, x, y, w, h) return r ~= nil and x < r.x + r.w and x + w > r.x and y < r.y + r.h and y + h > r.y end
return M
