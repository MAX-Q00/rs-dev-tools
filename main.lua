--[[
  RS Dev Tools
  ------------
  One panel with tabs of small tools for people writing RuneScape plugins.
  Every list is shown in one shared table (dt_table.lua).

  Guideline notes for moderators:
    * Display only, with one exception the user asked for: the Commands tab
      sends a console command with ExecuteConsoleCommand only when the user
      clicks Run (dev tools such as prl, plist, displayfps; poff / prl of RS
      Dev Tools itself and !resetsave need a second Confirm click). Nothing
      runs on its own or on a timer. Sends no other input, menu actions or
      packets and changes no client settings (game.options is read, never
      Set). Nothing is drawn at the mouse; the browser is view only.
    * No permissions. Uses only documented API: Event subscriptions (read
      only, payloads are never modified), Mouse position, ui components,
      id / config lookups, audio.Play (MASTER for browsing; the Bus test plays
      one sound on a bus the user clicks), and PersistentDB
      for this plugin's own data (records are isolated per plugin).
    * Key events are only counted; which key was pressed is never read,
      shown or stored.
    * Diagnostics, Known gaps and Help/FAQ use only the plugin developer
      Discord research (faq_data.lua, generated) and the official docs.
    * Plugin Analyser reads the shared plugin interface layer (the parent
      every plugin panel is built on) read only: component type, position,
      size, visibility and visible text. It never changes, clicks or moves
      another plugin's components. Optional opt-in hooks: a plugin may return
      a devInfo function from its main.lua; RS Dev Tools only calls it when
      that plugin is listed in optionalDependencies (none in this release).
]]

local PLUGIN_NAME = "RS Dev Tools"
local SLUG = "rs-dev-tools"
local helpers = require("ui_helpers")
helpers.VERSION = "0.5.6"
local H = helpers
local Table = require("dt_table")
local FaqDialog = require("faq_dialog")
local D = require("rdt_data")   -- 0.5.1: static tables (200-local headroom)
-- 0.4.0: single edition. The former Unlimited-only features are always on;
-- _RDT_UNL stays as a constant so the old branches keep working.
_RDT_UNL = true
_RDT_HOOK = {}   -- 0.3.0: module event hook (main chunk is at the 200-local limit)
local TIPS = {}
pcall(function() TIPS = require("tips_data") or {} end)
TIPS.cols, TIPS.tabcols, TIPS.rows, TIPS.ctrl = TIPS.cols or {}, TIPS.tabcols or {}, TIPS.rows or {}, TIPS.ctrl or {}
local FAQ = {}
pcall(function() FAQ = require("faq_data") or {} end)
if type(FAQ) ~= "table" then FAQ = {} end

-------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------
local KEY = "rs_dev_tools"
local state = {}
pcall(function() state = PersistentDB:GetStructuredData(KEY) or {} end)
if type(state) ~= "table" then state = {} end
state.tab = math.tointeger(state.tab) or 1
-- 0.2.6: sounds always play at volume 1.0. The client treats any
-- SoundPlaybackParams.volume below 1 as 0 (FAQ 28), and 0.2.0 saved 50% as
-- the default, so every Dev Tools sound was silent. The old setting is dropped.
state.vol = nil
state.bus = type(state.bus) == "string" and state.bus or "MASTER"
state.gridStep = math.tointeger(state.gridStep) or 2
state.fontIdx = math.tointeger(state.fontIdx) or 1
state.fitW = math.tointeger(state.fitW) or 3
state.set = (state.set == "item" or state.set == "cursor") and state.set or "sprite"
local function save() pcall(function() PersistentDB:SetStructuredData(KEY, state) end) end

-- Display form: '_' as space, spaces collapsed, trimmed. Search form: lower case.
local function nice(n) return (tostring(n or ""):gsub("_", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end
local function norm(q) return string.lower(nice(q)) end
local function plain(s) return (tostring(s or ""):gsub("[<>]", "")) end   -- labels never carry < or >
local function untag(s) return plain((tostring(s or ""):gsub("<[^>]*>", ""))) end
local function fmt(v, d)
    if type(v) ~= "number" then return "-" end
    return string.format("%." .. (d or 1) .. "f", v)
end
local function commas(n)
    local s2 = tostring(n); local k
    repeat s2, k = string.gsub(s2, "^(%d+)(%d%d%d)", "%1,%2") until k == 0
    return s2
end

-------------------------------------------------------------------------------
-- Error log with stack traces (this plugin's own callbacks; other plugins'
-- errors are not visible to plugins). Every subscription below goes
-- through xpcall so a failure is recorded with debug.traceback when the
-- client provides it.
-------------------------------------------------------------------------------
local ticks = 0
local errlog = {}
local subs = {}          -- event name -> true/false (subscribe succeeded)
local hasTrace = false
pcall(function() hasTrace = type(debug) == "table" and type(debug.traceback) == "function" end)
local function logError(where, msg, trace)
    table.insert(errlog, 1, { t = ticks, where = plain(where), msg = untag(msg), trace = trace and untag(trace) or nil })
    if #errlog > 60 then errlog[#errlog] = nil end
end
local function guarded(where, fn, ...)
    local trace = nil
    local ok, r = xpcall(fn, function(e)
        if hasTrace then pcall(function() trace = debug.traceback(tostring(e), 2) end) end
        -- sandbox has no debug library: keep the plain message, which already
        -- carries "source:line:" for runtime errors
        if trace == nil then trace = "at " .. (tostring(e):match("^([^:]+:%d+):") or "unknown source") end
        return e
    end, ...)
    if not ok then logError(where, r, trace) end
    return ok, r
end
helpers.subscribe = function(pluginName, eventName, refName, fn)
    local ok, err = pcall(function()
        Event[eventName].Subscribe(refName, function(...) guarded(eventName, fn, ...) end)
    end)
    -- 0.5.3: record it so helpers.unsubscribeAll() frees it at shutdown
    if ok and helpers.subs then helpers.subs[#helpers.subs + 1] = { eventName, refName } end
    subs[eventName] = ok
    if not ok then logError("subscribe " .. eventName, err) end
end
local baseLog = helpers.log
helpers.log = function(s)
    if type(s) == "string" and s:find("ERROR", 1, true) then logError("helpers.log", s) end
    if baseLog then pcall(baseLog, s) end
end

-------------------------------------------------------------------------------
-- Clock: logic ticks since load (50 per second, per the Events docs).
-------------------------------------------------------------------------------

local function secs() return ticks / 50 end

-------------------------------------------------------------------------------
-- Event Monitor: counts for every documented event that needs no permission.
-- ChatMessage needs chatAccess and is left out. Payloads are never modified.
-------------------------------------------------------------------------------
local EVENTS = { "Logic", "ServerLogic", "Draw", "KeyDown", "KeyUp", "KeyTyped",
    "VarTransmit", "GameStateChanged", "WindowFocusChanged", "WindowSizeChanged",
    "SkillTransmit", "RunEnergyTransmit", "RunWeightTransmit",
    "PlayerEntityAdded", "PlayerEntityRemoved", "NPCEntityAdded", "NPCEntityRemoved",
    "ObjStackEntityAdded", "ObjStackEntityRemoved", "ObjStackEntityChanged",
    "LocAdded", "LocRemoved", "InventoryAdded", "InventoryUpdated", "InventoryRemoved",
    "MiniMenuOpened", "MiniMenuClosed", "GrandExchangeOfferUpdated",
    "WorldCreated", "RegionCreated" }
local TICKY = { Logic = true, ServerLogic = true, Draw = true }
local ev = { counts = {}, last = {}, log = {}, paused = false, since = 0 }
local function evSummary(name, e)
    local s = ""
    pcall(function()
        if name == "GameStateChanged" then s = "state " .. tostring(e.newState)
        elseif name == "WindowSizeChanged" then s = tostring(e.newWidth) .. " x " .. tostring(e.newHeight)
        elseif name == "WindowFocusChanged" then s = "focus " .. tostring(e.focused or e.hasFocus or "?")
        end
    end)
    return plain(s)
end
local function onEvent(name, e)
    if _RDT_HOOK.event then _RDT_HOOK.event(name, e) end
    if ev.paused then return end
    ev.counts[name] = (ev.counts[name] or 0) + 1
    ev.last[name] = ticks
    if not TICKY[name] then
        table.insert(ev.log, 1, { t = ticks, name = name, info = evSummary(name, e) })
        if #ev.log > 40 then ev.log[#ev.log] = nil end
    end
end

-------------------------------------------------------------------------------
-- Perf Meter: frame times from Draw.timeDeltaSecs, logic and server tick rates.
-------------------------------------------------------------------------------
local perf = { frames = {}, drawTime = 0, logicAtSec = 0, logicRate = nil,
    srvLast = nil, srvGaps = {}, cost = {}, hasClock = false }
pcall(function() perf.hasClock = type(os) == "table" and type(os.clock) == "function" and type(os.clock()) == "number" end)
local function perfReset()
    perf.frames, perf.srvGaps, perf.cost = {}, {}, {}
    perf.drawTime, perf.logicAtSec, perf.logicRate, perf.srvLast = 0, ticks, nil, nil
    perf.secStart = 0
end
perfReset()
-- 0.2.7: the new tabs live in one table (the main chunk is at the 200-local
-- limit). hook holds the Resource Monitor draw / server / cost callbacks.
local NT = { T_SUB = 16, T_RES = 17, T_WORLD = 18, T_PROBE = 19, hook = {} }
local function onDraw(e)
    local dt = nil
    pcall(function() dt = e.timeDeltaSecs end)
    if type(dt) ~= "number" or dt <= 0 or dt > 5 then return end
    perf.drawTime = perf.drawTime + dt
    if NT.hook.draw then NT.hook.draw(dt) end
    local f = perf.frames
    f[#f + 1] = dt
    if #f > 300 then table.remove(f, 1) end
    if perf.drawTime - perf.secStart >= 1 then
        perf.logicRate = (ticks - perf.logicAtSec) / (perf.drawTime - perf.secStart)
        perf.logicAtSec, perf.secStart = ticks, perf.drawTime
    end
end
local function onServer()
    if perf.srvLast ~= nil then
        local g = perf.srvGaps
        g[#g + 1] = perf.drawTime - perf.srvLast
        if NT.hook.server then NT.hook.server(perf.drawTime - perf.srvLast) end
        if #g > 50 then table.remove(g, 1) end
    end
    perf.srvLast = perf.drawTime
end

for _, name in ipairs(EVENTS) do
    helpers.subscribe(PLUGIN_NAME, name, "rdtMon" .. name, function(e)
        onEvent(name, e)
        if name == "Draw" then
            local t0 = perf.hasClock and os.clock() or nil
            onDraw(e)
            if t0 and NT.hook.cost then NT.hook.cost(os.clock() - t0) end
        elseif name == "ServerLogic" then onServer() end
    end)
end

-------------------------------------------------------------------------------
-- Own component registry (UI Inspector).
-------------------------------------------------------------------------------
local reg = {}
local function R(name, kind, c) if c ~= nil then reg[#reg + 1] = { name = name, kind = kind, c = c } end; return c end

-------------------------------------------------------------------------------
-- Shared bits
-------------------------------------------------------------------------------
local TABS = { "UI Inspector", "Plugin Analyser", "Event Monitor", "Sprite Browser", "Audio",
    "Settings", "Perf Meter", "Layout Grid", "Text Fit", "Reload Helper", "Help/FAQ",
    "Diagnostics", "Error Log", "API Explorer", "Commands", "Submission Check", "Resource Monitor", "World Render", "Probe" }
local T_UI, T_PLUG, T_EV, T_BROWSE, T_AUDIO, T_SET, T_PERF, T_GRID, T_FIT, T_RELOAD, T_FAQ = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
local T_DIAG, T_ERR, T_API, T_CMD = 12, 13, 14, 15
-- 0.2.6 (review): 5 categories in one row, the category's tabs underneath.
local CATG = {}
CATG.CATS = {
    { name = "Inspect", tabs = { T_UI, T_EV, T_PERF, NT.T_RES, NT.T_WORLD, T_GRID, T_FIT } },
    { name = "Plugins", tabs = { T_PLUG, NT.T_SUB, T_SET, T_RELOAD } },
    { name = "Assets",  tabs = { T_BROWSE, T_AUDIO } },
    { name = "Debug",   tabs = _RDT_UNL and { T_DIAG, T_ERR, T_API, T_CMD, NT.T_PROBE } or { T_DIAG, T_ERR, T_API, T_CMD } },
    { name = "Help",    tabs = { T_FAQ } },
}
CATG.TIP = {
    Inspect = "Look at this panel and the client: UI Inspector, Event Monitor, Perf Meter, Resource Monitor (live graphs), World Render (position and path markers), Layout Grid, Text Fit, Event Payloads, Camera & World, Component Tree, Profiler.",
    Plugins = "Plugin tools: Plugin Analyser, Submission Check, Settings, Reload Helper, PersistentDB, Permissions.",
    Assets = "Game assets: Sprite Browser (sprites, items, cursors) and Audio.",
    Debug = "Diagnostics, Error Log, API Explorer, console Commands and Shapes & Canvas, Automation, Visual Overrides and Deep Probe.",
    Help = "Help, FAQ from the plugin developer Discord, and API Coverage.",
}
function CATG.of(t) for i, c in ipairs(CATG.CATS) do for _, x in ipairs(c.tabs) do if x == t then return i end end end; return 1 end
CATG.catBtns = {}
local tabBtns, tabHi = {}, nil
local ctrls = {}            -- tab index -> { { c = comp, w = width, show = fn|nil } ... }
local tbl = nil             -- the shared table
local sel = {}              -- tab index -> selected row data
local detail = {}           -- detail view pieces
local preview = {}          -- grid / text fit pieces
local settingsUI
local root = nil
local lastW = nil
local frozen = false
local layout, refresh
local DETAIL_N = 8   -- 0.2.6: declared before the FAQ views that use it

local function tw(s) return helpers.textWidthOf(H.FONT, s) or (#s * 7) end
local function newText(parent, w)
    local t = nil
    pcall(function()
        t = ui.Text.new(parent)
        t:SetSize(w, H.ROW_HEIGHT, w < 0 and 1.0 or 0.0, 0.0)
        t.font = H.FONT
        t.content = ""
        t:AlignTo(ui.AlignMode.TOPLEFT, ui.AlignMode.CENTRE)
        helpers.shadow(t)
    end)
    return t
end
local function addCtrl(tab, c, w, name, kind, show)
    ctrls[tab] = ctrls[tab] or {}
    ctrls[tab][#ctrls[tab] + 1] = { c = c, w = w, show = show }
    R(name or "control", kind or "Button", c)
    return c
end
local function ctrlTip(key)
    local t = TIPS.ctrl[key]
    if t == nil and type(key) == "string" then
        if key:find("^ID [%+%-]") then t = "Jump this many IDs forward or back."
        elseif key:find("^Grid ") then t = "Grid spacing in interface units. Click to change."
        elseif key:find("^Box ") then t = "Width of the test box in interface units. Click to change."
        elseif key:find("^Letter") then t = "Show only names starting with this letter. Click to change."
        elseif key:match("^%d$") then t = "Type this digit into the ID keypad." end
    end
    return t
end
local function btn(tab, label, w, fn, show, tipKey)
    w = w or (tw(label) + 16)
    local b = addCtrl(tab, helpers.button(root, 0, 0, w, H.BTN_H, label, fn), w, label, "Button", show)
    local tk = tipKey or label
    helpers.setTip(b, function() local l = nil; pcall(function() l = untag(b.label) end); return ctrlTip(tipKey or l or tk) end)
    return b
end
local function field(tab, w, placeholder, name, show)
    local f = addCtrl(tab, helpers.input(root, 0, 0, w, H.BTN_H, placeholder), w, name, "InputField", show)
    helpers.setTip(f, ctrlTip(name))
    return f
end
local function readField(f, maxLen)
    local t = ""
    pcall(function() t = tostring(f.content or "") end)
    return helpers.cleanText(t, maxLen or 64)
end
local function setLabel(b, s) helpers.setText(b, plain(s), "label") end
local function areaW() local w = 300; pcall(function() w = root.width - 2 * H.PAD end); return math.max(60, w) end
-- list data from a plain array of row arrays
local function arr(rows) return { count = #rows, get = function(i) return rows[i] end } end
local function kv(k, v) return { H.val(plain(k)), H.lbl(plain(v)) } end
local function wrap(s, width, maxLines)
    local out, line = {}, ""
    for word in tostring(s or ""):gmatch("%S+") do
        local t = line == "" and word or (line .. " " .. word)
        if line ~= "" and tw(t) > width then out[#out + 1] = line; line = word else line = t end
        if #out >= maxLines then break end
    end
    if line ~= "" and #out < maxLines then out[#out + 1] = line end
    return out
end
local function rectOf(c)
    local r = nil
    pcall(function()
        local p = c.xyGlobal
        r = { x = math.floor(p.x or 0), y = math.floor(p.y or 0), w = math.floor(c.width or 0), h = math.floor(c.height or 0), hidden = c.hidden == true }
    end)
    return r
end
local function rs(r) return r and (r.x .. ", " .. r.y) or "-" end
local function sz(r) return r and (r.w .. " x " .. r.h) or "-" end

-------------------------------------------------------------------------------
-- 1. UI Inspector (this plugin's components)
-------------------------------------------------------------------------------
local uiMode = "summary"
local function viewUI()
    if uiMode == "summary" then
        local L = {}
        local px, py = nil, nil
        pcall(function() if Mouse.IsAvailable() then local p = Mouse.GetPosition(); px, py = p.x, p.y end end)
        local ux, uy = helpers.mouseUI()
        L[#L + 1] = kv("Mouse (window px)", px and (math.floor(px) .. ", " .. math.floor(py)) or "not available")
        L[#L + 1] = kv("Mouse (UI units)", ux and (math.floor(ux) .. ", " .. math.floor(uy)) or "not available")
        local pr = helpers.panelRect()
        L[#L + 1] = kv("This panel position", pr and (pr.x .. ", " .. pr.y) or "-")
        L[#L + 1] = kv("This panel size", pr and (pr.w .. " x " .. pr.h) or "-")
        local over = {}
        if ux then for _, e in ipairs(reg) do if helpers.isOver(e.c, ux, uy) then over[#over + 1] = e.name end end end
        L[#L + 1] = kv("Under mouse", #over > 0 and table.concat(over, ", ") or "none of this plugin's components")
        L[#L + 1] = kv("Components", #reg)
        L[#L + 1] = kv("Other panels", "see the Plugin Analyser tab")
        return { cols = { { title = "Property", w = 150 }, { title = "Value", flex = 1, min = 80 } }, data = arr(L) }
    end
    return {
        cols = { { title = "Component", flex = 2, min = 80 }, { title = "Type", w = 90 }, { title = "Position", w = 80 },
            { title = "Size", w = 70 }, { title = "State", w = 52 } },
        data = { count = #reg, get = function(i)
            local e = reg[i]; local r = rectOf(e.c)
            return { H.val(plain(e.name)), H.lbl(e.kind), H.lbl(rs(r)), H.lbl(sz(r)), H.lbl((r and r.hidden) and "hidden" or "shown") }
        end },
        onRow = function(i) sel[T_UI] = reg[i] end,
        detail = function()
            local e = sel[T_UI]; if e == nil then return nil end
            local r = rectOf(e.c)
            return { lines = { H.gold(plain(e.name)) .. H.lbl("  " .. e.kind), H.lbl("Position ") .. H.val(rs(r)) .. H.lbl("  size ") .. H.val(sz(r)) },
                copy = plain(e.name) .. " " .. e.kind .. " pos " .. rs(r) .. " size " .. sz(r) }
        end,
    }
end

-------------------------------------------------------------------------------
-- 2. Plugin Analyser
--   Layer: read-only scan of the shared plugin interface layer
--     (TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP), which every plugin's panel is
--     built on. Type, position, size, visibility and visible text only.
--   Hooks: opt-in devInfo() from plugins listed in optionalDependencies.
--   Limits: what the API cannot give at all.
-------------------------------------------------------------------------------
local plug = { mode = "layer", wins = {}, at = nil, open = nil, err = nil }
local TYPE_NAMES = nil
local function typeName(c)
    if TYPE_NAMES == nil then
        TYPE_NAMES = {}
        pcall(function() for k, v in pairs(ui.ComponentType) do TYPE_NAMES[v] = k end end)
    end
    local t = nil
    pcall(function() t = c.type end)
    return nice(TYPE_NAMES[t] or (t ~= nil and tostring(t)) or "Component")
end
local function textOf(c)
    local s = nil
    pcall(function() s = c.content end)
    if type(s) ~= "string" or s == "" then pcall(function() s = c.label end) end
    if type(s) ~= "string" then return "" end
    return untag(s)
end
local function children(c)
    local out = {}
    for _, m in ipairs({ "IterateStaticComponents", "IterateDynamicComponents" }) do
        pcall(function()
            c[m](c, function(k, vis) out[#out + 1] = { c = k, vis = vis } end)
        end)
    end
    return out
end
local SCAN_CAP = 1500
local function plugScan()
    plug.wins, plug.err = {}, nil
    local top = helpers.ensureHoverLayer()
    if top == nil then plug.err = "plugin layer not available"; return end
    local total = 0
    local pr = helpers.panelRect()
    local tops = children(top)
    if #tops == 0 then plug.err = "the layer returned no components" end
    for i, k in ipairs(tops) do
        local w = { idx = i, c = k.c, vis = k.vis, r = rectOf(k.c), type = typeName(k.c), flat = {}, title = "" }
        local function walk(c, depth)
            for _, ch in ipairs(children(c)) do
                if total >= SCAN_CAP then return end
                total = total + 1
                local t = textOf(ch.c)
                w.flat[#w.flat + 1] = { depth = depth, c = ch.c, vis = ch.vis, type = typeName(ch.c), text = t, r = rectOf(ch.c) }
                if w.title == "" and t ~= "" then w.title = t end
                if depth < 6 then walk(ch.c, depth + 1) end
            end
        end
        walk(k.c, 1)
        w.own = pr ~= nil and w.r ~= nil and w.r.x == pr.x and w.r.y == pr.y and w.r.w == pr.w
        plug.wins[#plug.wins + 1] = w
    end
    plug.total = total
    plug.at = ticks
end
-- Opt-in hooks: a plugin listed in optionalDependencies is exposed as a global
-- named after it ('-' becomes '_'). Only these names are looked at.
local function hookRows()
    local rows = {}
    for _, g in ipairs(D.HOOK_NAMES) do
        local mod = rawget(_G, g)
        if type(mod) ~= "table" or type(mod.devInfo) ~= "function" then
            rows[#rows + 1] = { H.val(nice(g)), H.lbl("-"), H.lbl("not linked") }
        else
            local ok, info = pcall(mod.devInfo)
            if not ok or type(info) ~= "table" then
                rows[#rows + 1] = { H.val(nice(g)), H.lbl("devInfo"), H.col(H.C_BAD, "error: " .. untag(info)) }
            else
                local keys = {}
                for k in pairs(info) do keys[#keys + 1] = tostring(k) end
                table.sort(keys)
                for _, k in ipairs(keys) do
                    local v = info[k]
                    if type(v) == "table" then local n = 0; for _ in pairs(v) do n = n + 1 end; v = "{" .. n .. " entries}" end
                    rows[#rows + 1] = { H.val(nice(g)), H.lbl(nice(k)), H.lbl(untag(v)) }
                end
            end
        end
    end
    return rows
end
local function viewPlug()
    if plug.mode == "limits" then
        local rows = {}
        for _, l in ipairs(D.LIMITS) do rows[#rows + 1] = { H.val(l[1]), (l[2] == "no" or l[2] == "not used") and H.col(H.C_WARN, l[2]) or H.col(H.C_GOOD, l[2]), H.lbl(l[3]) } end
        return { cols = { { title = "What", flex = 2, min = 90 }, { title = "Possible", w = 70 }, { title = "How or why", flex = 3, min = 90 } }, data = arr(rows) }
    elseif plug.mode == "hooks" then
        return { cols = { { title = "Plugin", w = 130 }, { title = "Key", w = 100 }, { title = "Value", flex = 1, min = 80 } }, data = arr(hookRows()) }
    end
    if plug.at == nil then plugScan() end
    if plug.open ~= nil then
        local w = plug.open
        return {
            cols = { { title = "Component", w = 110 }, { title = "Text", flex = 2, min = 80 }, { title = "Position", w = 76 }, { title = "Size", w = 70 }, { title = "Shown", w = 46 } },
            data = { count = #w.flat, get = function(i)
                local e = w.flat[i]
                return { H.val(string.rep(". ", e.depth - 1) .. e.type), H.lbl(e.text), H.lbl(rs(e.r)), H.lbl(sz(e.r)), H.lbl(e.vis == false and "no" or "yes") }
            end },
            onRow = function(i) sel[T_PLUG] = w.flat[i] end,
            detail = function()
                local e = sel[T_PLUG] or w
                return { lines = { H.gold("Panel " .. w.idx .. ": ") .. H.val(w.title ~= "" and w.title or "(no text)") .. (w.own and H.lbl("  this plugin") or ""),
                    H.lbl("Selected ") .. H.val(e.type or "-") .. H.lbl("  at ") .. H.val(rs(e.r)) .. H.lbl("  size ") .. H.val(sz(e.r)),
                    H.lbl(#w.flat .. " components; read only, nothing is changed") },
                    copy = (e.type or "") .. " pos " .. rs(e.r) .. " size " .. sz(e.r) .. ((e.text and e.text ~= "") and (" text " .. e.text) or "") }
            end,
        }
    end
    return {
        cols = { { title = "#", w = 28 }, { title = "Panel (first text)", flex = 2, min = 90 }, { title = "Position", w = 76 }, { title = "Size", w = 70 }, { title = "Parts", w = 44 } },
        data = { count = #plug.wins, get = function(i)
            local w = plug.wins[i]
            local t = w.title ~= "" and w.title or "(no text)"
            return { H.lbl(w.idx), (w.own and H.gold(t .. " (this)") or H.val(t)), H.lbl(rs(w.r)), H.lbl(sz(w.r)), H.lbl(#w.flat) }
        end },
        onRow = function(i) plug.open = plug.wins[i]; sel[T_PLUG] = nil; tbl.page = 1 end,
        detail = function()
            return { lines = { H.lbl("Panels on the shared plugin layer: ") .. H.val(#plug.wins) .. H.lbl("  components ") .. H.val(plug.total or 0),
                plug.err and H.col(H.C_WARN, plug.err) or H.lbl("Click a panel to list its components. Owner names are not exposed.") } }
        end,
    }
end

-------------------------------------------------------------------------------
-- 3. Event Monitor
-------------------------------------------------------------------------------
local evMode = "counts"
local function viewEvents()
    local el = secs() - ev.since
    if evMode == "recent" then
        return { cols = { { title = "Time s", w = 64 }, { title = "Event", flex = 1, min = 90 }, { title = "Info", flex = 1, min = 70 } },
            empty = "No events yet",
            data = { count = #ev.log, get = function(i) local r = ev.log[i]; return { H.lbl(fmt(r.t / 50, 1)), H.val(nice(r.name)), H.lbl(r.info) } end },
            detail = function()
                -- 0.2.6: Pause freezes the list; Copy holds the last 20 events as text for bug reports
                local parts = {}
                for i = 1, math.min(20, #ev.log) do local r = ev.log[i]; parts[#parts + 1] = fmt(r.t / 50, 1) .. "s " .. r.name .. (r.info ~= "" and (" " .. plain(r.info)) or "") end
                return { lines = { H.lbl(ev.paused and "Paused: the list is frozen" or "Live") .. H.lbl("  events kept ") .. H.val(#ev.log) .. H.lbl("  Copy holds the last ") .. H.val(math.min(20, #ev.log)) },
                    copy = #parts > 0 and table.concat(parts, " | ") or nil }
            end }
    end
    local names = {}
    for _, n in ipairs(EVENTS) do names[#names + 1] = n end
    table.sort(names, function(a, b) return (ev.counts[a] or 0) > (ev.counts[b] or 0) end)
    return { cols = { { title = "Event", flex = 1, min = 100 }, { title = "Count", w = 64 }, { title = "Per s", w = 52 }, { title = "Last", w = 70 } },
        data = { count = #names, get = function(i)
            local n = names[i]; local c = ev.counts[n] or 0
            return { H.val(nice(n)), H.lbl(c), H.lbl(fmt(el > 0 and c / el or 0, 1)), H.lbl(ev.last[n] and (fmt((ticks - ev.last[n]) / 50, 1) .. " s") or "never") }
        end },
        detail = function()
            return { lines = { H.lbl(ev.paused and "Paused" or "Counting") .. H.lbl(" for ") .. H.val(fmt(el, 0) .. " s") ..
                H.lbl("  (key events are counted only, never read)") } }
        end }
end

-------------------------------------------------------------------------------
-- 4. Sprite Browser (from Cursor Sprite, view only: nothing is drawn at the
--    mouse and no cursor is set). Sprites / Items / Cursors.
-------------------------------------------------------------------------------
local SETS = { "sprite", "item", "cursor" }
local SET_LABEL = { sprite = "Sprites", item = "Items", cursor = "Cursors" }
local lists = {
    sprite = { items = {}, next = nil, max = 40000, step = 1500, source = "" },
    item   = { items = {}, next = nil, max = 65000, step = 800,  source = "" },
    cursor = { items = {}, next = nil, max = 0,     step = 0,    source = "" },
}
local function addE(L, e) e.raw = e.name; e.name = nice(e.name); e.lower = norm(e.raw); L.items[#L.items + 1] = e end
local function sortL(L) table.sort(L.items, function(a, b) return a.id < b.id end) end
local browserReady = false
local function initBrowser()
    if browserReady then return end
    browserReady = true
    local L = lists.sprite
    pcall(function()
        for k, v in pairs(id.Sprite) do
            if type(k) == "string" and type(v) == "number" then addE(L, { id = v, name = k, spr = v }) end
        end
    end)
    if #L.items > 0 then sortL(L); L.source = "id.Sprite table" else L.items = {}; L.next = 0 end
    lists.item.next = 0
    local C = lists.cursor
    pcall(function()
        for k, v in pairs(id.Cursor) do
            if type(k) == "string" and type(v) == "number" then
                local cfg = nil
                pcall(function() cfg = config.Cursor.FromID(v) end)
                if cfg ~= nil then
                    local e = { id = v, name = k }
                    pcall(function() e.spr = cfg.spriteID; e.hx = cfg.hotspotX; e.hy = cfg.hotspotY end)
                    if e.spr ~= nil and e.spr >= 0 then addE(C, e) end
                end
            end
        end
    end)
    sortL(C); C.source = #C.items > 0 and "id.Cursor table" or "not available"
end
local function scanStep(kind)
    local L = lists[kind]
    if L.next == nil then return true end
    local stop = math.min(L.max, L.next + L.step)
    for i = L.next, stop do
        local nm = nil
        if kind == "sprite" then
            pcall(function() nm = id.Sprite.FromID(i) end)
            if type(nm) == "string" and nm ~= "" then addE(L, { id = i, name = nm, spr = i }) end
        else
            pcall(function() local o = config.Obj.FromID(i); if o ~= nil then nm = o.name end end)
            if type(nm) == "string" and nm ~= "" and nm ~= "null" then addE(L, { id = i, name = nm }) end
        end
    end
    L.next = stop + 1
    if L.next > L.max then
        L.next = nil
        L.source = #L.items > 0 and (kind == "sprite" and "id.Sprite.FromID scan" or "config.Obj scan") or "not available"
        return true
    end
    return false
end
local LETTERS = { "All" }
for c = string.byte("A"), string.byte("Z") do LETTERS[#LETTERS + 1] = string.char(c) end
LETTERS[#LETTERS + 1] = "0-9"
local br = { filtered = {}, letter = 1, q = "", pad = false, padStr = "", lastQ = nil, lastN = -1 }
local brSearch, brLetter, brSet, brIdField
local function curList() return lists[state.set] or lists.sprite end
local function brFilter()
    local f = {}
    local q = norm(br.q)
    for i, e in ipairs(curList().items) do
        local ok = q == "" or tostring(e.id) == q or string.find(e.lower, q, 1, true) ~= nil
        if ok and br.letter > 1 then
            local c = string.upper(string.sub(e.name or "", 1, 1))
            if LETTERS[br.letter] == "0-9" then ok = not c:match("%a") else ok = c == LETTERS[br.letter] end
        end
        if ok then f[#f + 1] = i end
    end
    br.filtered = f
    br.lastN = #curList().items
end
local function brEntry(i) local idx = br.filtered[i]; return idx and curList().items[idx] or nil end
local function brGoId(n)
    local hit = #br.filtered
    for i, idx in ipairs(br.filtered) do if curList().items[idx].id >= n then hit = i; break end end
    if hit < 1 then return end
    tbl.selected = hit; sel[T_BROWSE] = brEntry(hit)
    tbl:go(math.ceil(hit / Table.ROWS))
end
local function brJump(n)
    local first = brEntry((tbl.page - 1) * Table.ROWS + 1)
    brGoId((first and first.id or 0) + n)
end
local function objInfo(n)
    local o, out = nil, {}
    pcall(function() o = config.Obj.FromID(n) end)
    if o == nil then return out end
    local function g(k) local v = nil; pcall(function() v = o[k] end); return v end
    out.configName = g("configName"); out.members = g("isMembers"); out.trade = g("isTradeable")
    out.ge = g("isStockmarket"); out.limit = g("stockmarketBuyLimit"); out.cost = g("cost"); out.cat = g("category")
    return out
end
local function viewBrowse()
    initBrowser()
    local L = curList()
    if br.lastN ~= #L.items then brFilter() end
    local kind = state.set
    return {
        icon = true,
        cols = { { title = "Name", flex = 1, min = 110 }, { title = "ID", w = 64 } },
        data = { count = #br.filtered, get = function(i)
            local e = brEntry(i)
            local cells = { H.val(e.name), H.lbl(e.id) }
            cells.icon = kind == "item" and { item = true, id = e.id } or { spr = e.spr }
            return cells
        end },
        onRow = function(i) sel[T_BROWSE] = brEntry(i); tbl.selected = i end,
        detail = function()
            local e = sel[T_BROWSE]
            local scan = L.next ~= nil and (" (scanning " .. math.floor(100 * L.next / math.max(1, L.max)) .. "%)") or ""
            local noun = kind == "item" and "items" or (kind == "cursor" and "cursors" or "sprites")
            local head = H.lbl("Showing ") .. H.val(commas(#br.filtered)) .. H.lbl(" of ") .. H.val(commas(#L.items)) .. H.lbl(" " .. noun .. scan)
            if e == nil then return { lines = { head, H.lbl("Click a row to see its ID, name and details.") } } end
            local lines, copy = { head }, ""
            if kind == "item" then
                local o = objInfo(e.id)
                lines[#lines + 1] = H.gold(e.name) .. H.lbl("  item ") .. H.val(e.id)
                lines[#lines + 1] = H.lbl("Config name ") .. H.val(nice(o.configName or "-")) .. H.lbl("  members ") .. H.val(tostring(o.members))
                lines[#lines + 1] = H.lbl("Tradeable ") .. H.val(tostring(o.trade)) .. H.lbl("  GE ") .. H.val(tostring(o.ge)) .. H.lbl("  limit ") .. H.val(tostring(o.limit))
                lines[#lines + 1] = H.lbl("Value ") .. H.val(tostring(o.cost)) .. H.lbl("  category ") .. H.val(tostring(o.cat))
                copy = "local s = ui.Sprite.new(parent); s:SetAssociatedObject(" .. e.id .. ")  -- " .. plain(e.name)
            elseif kind == "cursor" then
                lines[#lines + 1] = H.gold(e.name) .. H.lbl("  cursor ") .. H.val(e.id)
                lines[#lines + 1] = H.lbl("Sprite ") .. H.val(tostring(e.spr)) .. H.lbl("  hotspot ") .. H.val(tostring(e.hx) .. ", " .. tostring(e.hy))
                copy = "id.Cursor." .. plain(e.raw) .. " = " .. e.id .. "  -- sprite " .. tostring(e.spr)
            else
                lines[#lines + 1] = H.gold(e.name) .. H.lbl("  sprite ") .. H.val(e.id)
                lines[#lines + 1] = H.lbl("Draw with ui.Sprite: .sprite = ") .. H.val(e.id)
                copy = "local s = ui.Sprite.new(parent); s.sprite = " .. e.id .. "  -- " .. plain(e.raw)
            end
            return { lines = lines, copy = copy, preview = { item = kind == "item", id = e.id, spr = e.spr } }
        end,
    }
end

-------------------------------------------------------------------------------
-- 5. Audio (from Sound Browser). Browsing plays on MASTER only; the Bus test
--    mode plays one sound on the bus you click, to compare MASTER and SFX.
-------------------------------------------------------------------------------
-- Buses exposed by audio.AudioBus (developer.runescape.com, Audio page),
-- read at runtime and ordered by their enum value (MASTER 0, SFX 1, ...).
CATG.busList = function()
    local L = {}
    pcall(function() for k, v in pairs(audio.AudioBus) do if type(k) == "string" and type(v) == "number" then L[#L + 1] = { k = k, v = v } end end end)
    table.sort(L, function(a, b) return a.v < b.v end)
    local out = {}
    for _, b in ipairs(L) do out[#out + 1] = b.k end
    return out
end
CATG.BUS_TIP = {
    MASTER = "MASTER: the game's master volume only. The most reliable bus for previews.",
    SFX = "SFX: follows the Sound Effects slider.",
    MUSIC = "MUSIC: follows the Music slider.",
    AMBIENT = "AMBIENT: follows the Ambient / background sound slider.",
    VOICEOVER = "VOICEOVER: follows the Voice over slider.",
}
local snd = { all = {}, next = nil, source = "", filtered = {}, q = "", lastQ = nil, lastN = -1, insts = {}, mode = "sounds" }
local SND_MAX = 62000
local sndReady = false
local sndSearch, volBtn
local function initSounds()
    if sndReady then return end
    sndReady = true
    pcall(function()
        for k, v in pairs(id.Sound) do
            if type(k) == "string" and type(v) == "number" then snd.all[#snd.all + 1] = { id = v, raw = k, name = nice(k), lower = norm(k) } end
        end
    end)
    if #snd.all > 0 then table.sort(snd.all, function(a, b) return a.id < b.id end); snd.source = "id.Sound table"
    else snd.all = {}; snd.next = 1; snd.source = "scanning" end
end
local function sndScan()
    if snd.next == nil then return end
    local stop = math.min(SND_MAX, snd.next + 1500)
    for i = snd.next, stop do
        local nm = nil
        pcall(function() nm = id.Sound.FromID(i) end)
        if type(nm) == "string" and nm ~= "" then snd.all[#snd.all + 1] = { id = i, raw = nm, name = nice(nm), lower = norm(nm) } end
    end
    snd.next = stop + 1
    if snd.next > SND_MAX then snd.next = nil; snd.source = #snd.all > 0 and "id.Sound.FromID scan" or "not available" end
end
local function sndFilter()
    local f, q = {}, norm(snd.q)
    for i, s in ipairs(snd.all) do
        if q == "" or tostring(s.id) == q or string.find(s.lower, q, 1, true) then f[#f + 1] = i end
    end
    snd.filtered, snd.lastN = f, #snd.all
end
-- Playback ported verbatim from Sound Browser 0.1.13 (play / toggle / sweep /
-- stopAll). 0.2.0 played nothing in Dylan's test. Differences from Sound
-- Browser: it called audio.StopSoundsUsingResource(sid) right before
-- audio.Play(sid) on every click (the likely cause: the stop can cancel the
-- sound queued in the same frame), defaulted to 50% volume instead of 100%,
-- and dropped instances in the view instead of sweeping them in the tick.
local function isPlaying(inst)
    local v = false
    pcall(function() v = inst.isPlaying == true end)
    return v
end
snd.played, snd.results = {}, {}
local function sndPlay(sid, bus)
    local r = "err"
    pcall(function()
        local p = audio.SoundPlaybackParams.new()
        p.type = audio.SoundType.SCRIPT
        p.audioBus = audio.AudioBus[bus or state.bus] or audio.AudioBus.MASTER
        p.volume = 1.0   -- below 1.0 the client plays nothing (FAQ 28)
        p.numLoops = 0
        p.delayTick = 0
        p.emitterShape = audio.EmitterShape.NONE
        local inst = audio.Play(sid, p)
        snd.insts[sid] = inst
        r = inst ~= nil and "playing" or "nil"
    end)
    snd.results[sid] = r
    snd.played[sid] = true
    snd.result = r == "playing" and "playing" or ("audio.Play: " .. r)
end
local function sndToggle(sid)
    local inst = snd.insts[sid]
    if inst ~= nil and isPlaying(inst) then
        pcall(function() inst:Stop() end)
        snd.insts[sid] = nil
        snd.results[sid] = "stopped"
    else
        sndPlay(sid)
    end
end
local function sndSweep()
    local changed = false
    for sid, inst in pairs(snd.insts) do
        if not isPlaying(inst) then
            snd.insts[sid] = nil
            if snd.results[sid] == "playing" then snd.results[sid] = "done" end
            changed = true
        end
    end
    return changed
end
local function sndStopAll()
    for sid, _ in pairs(snd.played) do
        pcall(function() audio.StopSoundsUsingResource(sid) end)
    end
    for sid, inst in pairs(snd.insts) do
        pcall(function() inst:Stop() end)
        snd.results[sid] = "stopped"
    end
    snd.insts = {}
    snd.played = {}
end
local viewBusTest
local function viewAudio()
    initSounds()
    if snd.mode == "bus" then return viewBusTest() end
    local playing = 0
    for _ in pairs(snd.insts) do playing = playing + 1 end
    local head = H.lbl("Bus ") .. H.gold(state.bus) .. H.lbl("  volume ") .. H.val("100%") ..
        H.lbl("  playing ") .. H.val(playing)
    if snd.mode == "volumes" then
        local rows = {}
        for _, o in ipairs(D.VOL_OPTS) do
            local v, mx = nil, nil
            pcall(function() local op = game.options[o]; v, mx = op.setting, op.max end)
            rows[#rows + 1] = { H.val(nice(o)), H.lbl(tostring(v or "-")), H.lbl(tostring(mx or "-")) }
        end
        local buses = {}
        pcall(function() for k in pairs(audio.AudioBus) do if type(k) == "string" then buses[#buses + 1] = nice(k) end end end)
        table.sort(buses)
        rows[#rows + 1] = { H.val("Buses in the API"), H.lbl(#buses > 0 and table.concat(buses, ", ") or "not listed"), H.lbl("playing on: " .. state.bus) }
        return { cols = { { title = "Client option (read only)", flex = 1, min = 120 }, { title = "Value", w = 70 }, { title = "Max", flex = 1, min = 50 } },
            data = arr(rows), detail = function() return { lines = { head, H.lbl("Output levels cannot be metered by plugins.") } } end }
    end
    if snd.lastN ~= #snd.all then sndFilter() end
    return {
        cols = { { title = "ID", w = 60 }, { title = "Sound", flex = 1, min = 100 }, { title = "State", w = 60 } },
        data = { count = #snd.filtered, get = function(i)
            local s = snd.all[snd.filtered[i]]
            local on = snd.insts[s.id] ~= nil
            local r = snd.results[s.id]
            return { H.lbl(s.id), on and H.gold(s.name) or H.val(s.name), on and H.col(H.C_GOOD, "playing") or ((r == "nil" or r == "err") and H.col(H.C_BAD, r) or H.lbl(r or "-")) }
        end },
        onRow = function(i) local s = snd.all[snd.filtered[i]]; if s then sel[T_AUDIO] = s; tbl.selected = i; sndToggle(s.id) end end,
        detail = function()
            local s = sel[T_AUDIO]
            local scan = snd.next ~= nil and ("  scanning " .. math.floor(100 * snd.next / SND_MAX) .. "%") or ""
            local lines = { head, H.lbl("Sounds ") .. H.val(commas(#snd.all)) .. H.lbl("  shown ") .. H.val(commas(#snd.filtered)) .. H.lbl("  from " .. snd.source .. scan) }
            if s == nil then lines[#lines + 1] = H.lbl("Click a row to play it; click again to stop.") return { lines = lines } end
            lines[#lines + 1] = H.gold(s.name) .. H.lbl("  id ") .. H.val(s.id)
            return { lines = lines, copy = "local p = audio.SoundPlaybackParams.new(); p.audioBus = audio.AudioBus." .. state.bus .. "; audio.Play(" .. s.id .. ", p)  -- " .. plain(s.raw) }
        end,
    }
end

-------------------------------------------------------------------------------
-- 6. Settings (this plugin's PersistentDB entries and client options)
-------------------------------------------------------------------------------
local setField
local setMode = "plugin"
local function short(v, depth)
    depth = depth or 0
    if type(v) == "table" then
        if depth > 0 then local n = 0; for _ in pairs(v) do n = n + 1 end; return "{" .. n .. "}" end
        local parts, keys = {}, {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for i, k in ipairs(keys) do if i <= 8 then parts[#parts + 1] = tostring(k) .. "=" .. short(v[k], 1) end end
        return "{" .. table.concat(parts, ", ") .. (#keys > 8 and ", ..." or "") .. "}"
    end
    return plain(tostring(v))
end
local function viewSettings()
    local q = norm(readField(setField, 48))
    local function want(s) return q == "" or string.find(norm(s), q, 1, true) ~= nil end
    if setMode == "plugin" then
        local rows = {}
        pcall(function() PersistentDB:IterateEntries(function(k, v)
            if want(tostring(k)) then rows[#rows + 1] = { H.val(nice(k)), H.lbl(type(v)), H.lbl(short(v)), full = short(v) } end
            return false
        end) end)
        table.sort(rows, function(a, b) return a[1] < b[1] end)
        return { cols = { { title = "Key", w = 120 }, { title = "Type", w = 54 }, { title = "Value", flex = 1, min = 80 } }, data = arr(rows),
            onRow = function(i) sel[T_SET] = rows[i] end,
            detail = function()
                local r = sel[T_SET]
                return { lines = { H.lbl("This plugin's saved data. Other plugins' data is isolated and cannot be read.") }, copy = r and untag(r[1]) .. " = " .. r.full or nil }
            end }
    end
    local rows = {}
    for _, o in ipairs(D.OPTIONS) do
        if want(o) then
            local v, lbl, mn, mx = nil, nil, nil, nil
            pcall(function()
                local op = game.options[o]
                v, mn, mx = op.setting, op.min, op.max
                if op.hasLabels then lbl = op:GetLabel(v) end
            end)
            rows[#rows + 1] = { H.val(o), H.lbl(tostring(v or "n/a")), H.lbl(plain(lbl or "")), H.lbl((mn and mx) and (mn .. " to " .. mx) or "-") }
        end
    end
    return { cols = { { title = "Client option (read only)", flex = 2, min = 110 }, { title = "Value", w = 54 }, { title = "Label", flex = 1, min = 50 }, { title = "Range", w = 70 } },
        data = arr(rows),
        onRow = function(i) sel[T_SET] = rows[i] end,
        detail = function() local r = sel[T_SET]; return r and { lines = { H.lbl("game.options is read, never set.") }, copy = "game.options." .. untag(r[1]) .. ".setting  -- " .. untag(r[2]) } or nil end }
end

-------------------------------------------------------------------------------
-- 7. Perf Meter
-------------------------------------------------------------------------------
local function viewPerf()
    local f = perf.frames
    local n, sum, mn, mx = 0, 0, nil, nil
    for i = math.max(1, #f - 59), #f do
        local d = f[i]; n = n + 1; sum = sum + d
        mn = (mn == nil or d < mn) and d or mn
        mx = (mx == nil or d > mx) and d or mx
    end
    local avg = n > 0 and sum / n or nil
    local worst = nil
    for _, d in ipairs(f) do if worst == nil or d > worst then worst = d end end
    local g, gs = perf.srvGaps, 0
    for _, d in ipairs(g) do gs = gs + d end
    local rows = {
        { H.val("FPS"), H.lbl(avg and fmt(1 / avg, 1) or "waiting for Draw"), H.lbl("last 60 frames") },
        { H.val("Frame time avg"), H.lbl(avg and (fmt(avg * 1000, 2) .. " ms") or "-"), H.lbl("Draw.timeDeltaSecs") },
        { H.val("Frame time min"), H.lbl(mn and (fmt(mn * 1000, 2) .. " ms") or "-"), H.lbl("") },
        { H.val("Frame time max"), H.lbl(mx and (fmt(mx * 1000, 2) .. " ms") or "-"), H.lbl("") },
        { H.val("Worst frame"), H.lbl(worst and (fmt(worst * 1000, 1) .. " ms") or "-"), H.lbl("last " .. #f .. " frames") },
        { H.val("Logic ticks per second"), H.lbl(perf.logicRate and fmt(perf.logicRate, 1) or "-"), H.lbl("client target 50") },
        { H.val("Server tick interval"), H.lbl(#g > 0 and (fmt(gs / #g * 1000, 0) .. " ms") or "-"), H.lbl("game target 600") },
    }
    if perf.hasClock then
        local c, cs, cm = perf.cost, 0, 0
        for _, d in ipairs(c) do cs = cs + d; if d > cm then cm = d end end
        rows[#rows + 1] = { H.val("This plugin's refresh cost"), H.lbl(#c > 0 and (fmt(cs / #c * 1000, 2) .. " ms avg") or "-"), H.lbl(#c > 0 and (fmt(cm * 1000, 2) .. " ms max") or "") }
    else
        rows[#rows + 1] = { H.val("This plugin's refresh cost"), H.lbl("not measurable"), H.lbl("os.clock not available") }
    end
    rows[#rows + 1] = { H.val("Components in this plugin"), H.lbl(#reg), H.lbl("") }
    -- 0.2.6: live count on the shared plugin layer against the 4096 dynamic-ID
    -- limit (FAQ 13), warning from 80%.
    do
        local _, total = CATG.layerCount()
        local LIMIT = 4096
        if total then
            local pct = math.floor(total * 100 / LIMIT)
            local warn = total >= LIMIT * 0.8
            rows[#rows + 1] = { H.val("Plugin layer components"), warn and H.col(H.C_WARN, commas(total) .. " / 4,096") or H.lbl(commas(total) .. " / 4,096"),
                warn and H.col(H.C_WARN, pct .. "%: near the limit") or H.lbl(pct .. "% of the limit"),
                tip = "Components on the shared plugin layer (all plugins), counted to 8 levels deep. The client refuses new layers past 4096 dynamic IDs (FAQ 13). Amber from 80%." }
        else
            rows[#rows + 1] = { H.val("Plugin layer components"), H.lbl("not readable"), H.lbl("layer not found") }
        end
    end
    rows[#rows + 1] = { H.val("Other plugins"), H.lbl("not timed"), H.lbl("no profiler API") }
    return { cols = { { title = "Metric", flex = 2, min = 100 }, { title = "Value", w = 110 }, { title = "Note", flex = 1, min = 60 } }, data = arr(rows) }
end

-------------------------------------------------------------------------------
-- 8. Layout Grid (inside this panel's preview area)
-------------------------------------------------------------------------------
local STEPS = { 8, 10, 16, 20, 24, 32 }
local GRID_H = 140
local MAXV, MAXH = 60, 20
local gridRect = nil
local function placeGrid(y)
    local step = STEPS[state.gridStep] or 16
    local w = areaW()
    local show = state.tab == T_GRID and y ~= nil
    helpers.safe(function() preview.gridBg.hidden = not show; if show then preview.gridBg:SetPos(H.PAD, y); preview.gridBg:SetSize(w, GRID_H) end end)
    for i = 1, MAXV do
        local x = i * step
        local vis = show and x < w
        helpers.safe(function() local l = preview.gv[i]; l.hidden = not vis; if vis then l:SetPos(H.PAD + x, y); l:SetSize(1, GRID_H) end end)
    end
    for i = 1, MAXH do
        local yy = i * step
        local vis = show and yy < GRID_H
        helpers.safe(function() local l = preview.gh[i]; l.hidden = not vis; if vis then l:SetPos(H.PAD, y + yy); l:SetSize(w, 1) end end)
    end
    if not show then helpers.safe(function() preview.dot.hidden = true end) end
    gridRect = show and { y = y, w = w } or nil
end
local function viewGrid()
    local step = STEPS[state.gridStep] or 16
    local rows = { kv("Spacing", step .. " UI units"), kv("Area", (gridRect and gridRect.w or 0) .. " x " .. GRID_H) }
    local ux, uy = helpers.mouseUI()
    local pr = helpers.panelRect()
    local cross = false
    if ux and pr and gridRect then
        local rx, ry = ux - pr.x - H.PAD, uy - pr.y - gridRect.y
        if rx >= 0 and ry >= 0 and rx <= gridRect.w and ry <= GRID_H then
            cross = true
            local sx, sy = math.floor(rx / step + 0.5) * step, math.floor(ry / step + 0.5) * step
            rows[#rows + 1] = kv("Mouse in grid", math.floor(rx) .. ", " .. math.floor(ry))
            rows[#rows + 1] = kv("Snapped", sx .. ", " .. sy)
            helpers.safe(function() preview.dot.hidden = false; preview.dot:SetPos(H.PAD + sx - 2, gridRect.y + sy - 2) end)
        end
    end
    if not cross then
        helpers.safe(function() preview.dot.hidden = true end)
        rows[#rows + 1] = kv("Mouse in grid", "move the mouse over the grid")
    end
    if ux and pr then rows[#rows + 1] = kv("Mouse in panel", math.floor(ux - pr.x) .. ", " .. math.floor(uy - pr.y)) end
    rows[#rows + 1] = kv("Note", "the grid draws inside this panel only")
    return { cols = { { title = "Property", w = 130 }, { title = "Value", flex = 1, min = 80 } }, data = arr(rows) }
end

-------------------------------------------------------------------------------
-- 9. Text Fit
-------------------------------------------------------------------------------
local FIT_WS = { 60, 100, 140, 200, 260, 320 }
local fonts = nil
local fitField, fitWBtn
local function loadFonts()
    if fonts ~= nil then return end
    fonts = {}
    pcall(function()
        for k, v in pairs(id.Font) do
            if type(k) == "string" and type(v) == "number" then fonts[#fonts + 1] = { name = k, id = v } end
        end
    end)
    table.sort(fonts, function(a, b) return a.name < b.name end)
    if #fonts == 0 then fonts[1] = { name = "panel font", id = H.FONT } end
    if state.fontIdx > #fonts then state.fontIdx = 1 end
end
local function curFont() loadFonts(); return fonts[state.fontIdx] end
local function fitStr()
    local t = readField(fitField, 120)
    if t == "" then t = "The quick brown fox jumps over the lazy dog" end
    return t
end
local function placeFit(y)
    local show = state.tab == T_FIT and y ~= nil
    helpers.safe(function() preview.fitBg.hidden = not show; preview.fitT.hidden = not show end)
    if not show then return end
    local w = math.min(FIT_WS[state.fitW] or 140, areaW())
    local f = curFont()
    helpers.safe(function()
        preview.fitBg:SetPos(H.PAD, y); preview.fitBg:SetSize(w, H.ROW_HEIGHT + 4)
        preview.fitT.font = f.id
        preview.fitT:SetPos(H.PAD + 2, y + 2); preview.fitT:SetSize(w - 4, H.ROW_HEIGHT)
        preview.fitT.content = H.val(helpers.fitText(fitStr(), f.id, w - 4))
    end)
end
local function viewFit()
    local f = curFont()
    local t = fitStr()
    local boxW = math.min(FIT_WS[state.fitW] or 140, areaW())
    local full = helpers.textWidthOf(f.id, t)
    local fits = full ~= nil and full <= boxW - 4
    local rows = {}
    -- every font against this box: a table of results
    loadFonts()
    for i, fo in ipairs(fonts) do
        local wv = helpers.textWidthOf(fo.id, t)
        local ok = wv ~= nil and wv <= boxW - 4
        rows[#rows + 1] = { (i == state.fontIdx and H.gold or H.val)(nice(fo.name)), H.lbl(fo.id), H.lbl(wv and math.floor(wv) or "n/a"),
            wv == nil and H.lbl("-") or (ok and H.col(H.C_GOOD, "fits") or H.col(H.C_WARN, "ellipsis")), idx = i }
    end
    return { cols = { { title = "Font", flex = 1, min = 100 }, { title = "ID", w = 44 }, { title = "Width", w = 54 }, { title = "Box " .. (boxW - 4), w = 70 } },
        data = arr(rows),
        onRow = function(i) state.fontIdx = rows[i].idx; save(); layout() end,
        detail = function()
            return { lines = { H.lbl("Selected font ") .. H.val(nice(f.name)) .. H.lbl("  width ") .. H.val(full and math.floor(full) or "n/a") .. H.lbl("  chars ") .. H.val(#t),
                H.lbl("Fits: ") .. (fits and H.col(H.C_GOOD, "yes") or H.col(H.C_WARN, "no, shortened with an ellipsis")) .. H.lbl("  (widths from GetStringWidth)") },
                copy = "config.Font.FromID(" .. f.id .. "):GetStringWidth(text)  -- " .. (full and math.floor(full) or "n/a") }
        end }
end

-------------------------------------------------------------------------------
-- 10. Reload Helper (shows commands to copy; the Commands tab can run them)
-------------------------------------------------------------------------------
local slugField = nil
local function cleanSlug(s)
    local t = string.lower(helpers.cleanText(s, 48)):gsub("[%s_]+", "-"):gsub("[^a-z0-9%-]", "")
    return t ~= "" and t or SLUG
end
local function viewReload()
    local s = cleanSlug(readField(slugField, 48))
    local rows = {
        { H.val("prf"), H.lbl("refresh the plugin list (after adding a folder)"), cmd = "prf" },
        { H.val("plist"), H.lbl("list plugins and their state"), cmd = "plist" },
        { H.val("pon " .. s), H.lbl("first load / turn on"), cmd = "pon " .. s },
        { H.val("prl " .. s), H.lbl("reload after editing files"), cmd = "prl " .. s },
        { H.val("poff " .. s), H.lbl("turn off"), cmd = "poff " .. s },
        { H.val("ppr " .. s), H.lbl("set up permissions in dev, then ppe (FAQ 2)"), cmd = "ppr " .. s },
        { H.val("ppe " .. s .. " httpAccess"), H.lbl("grant a permission in dev, then prl (FAQ 2)"), cmd = "ppe " .. s .. " httpAccess" },
        { H.val("displayfps"), H.lbl("FPS readout for performance tests (FAQ 6, 37)"), cmd = "displayfps" },
        { H.val("prf after plugin.json edits"), H.lbl("manifest changes need prf or a client restart (FAQ 4)"), cmd = "prf" },
        { H.val("double-click checkbox"), H.lbl("in the plugin menu also reloads (FAQ 6)"), cmd = "prl " .. s },
        { H.val("dev re-enable"), H.lbl("dev plugins do not re-enable on login; only mod.io installs do (FAQ 11)"), cmd = "pon " .. s },
    }
    return { cols = { { title = "Command", w = 150 }, { title = "What it does", flex = 1, min = 80 } }, data = arr(rows),
        onRow = function(i) sel[T_RELOAD] = rows[i]; tbl.selected = i end,
        detail = function()
            local r = sel[T_RELOAD]
            return { lines = { H.lbl("Open the console (Alt and backtick), type or paste the command; Up arrow recalls the last one. The Commands tab can run them for you."),
                H.lbl("This plugin: ") .. H.val(PLUGIN_NAME .. " " .. H.VERSION) .. H.lbl("  loaded ") .. H.val(fmt(secs(), 0) .. " s ago") },
                copy = r and r.cmd or ("pon " .. s) }
        end }
end

-------------------------------------------------------------------------------
-- 11. Help/FAQ: only entries from faq_data.lua (generated from the Discord
--     research file by release/build_faq.py). Nothing is invented here.
-------------------------------------------------------------------------------
local faqField = nil
local function viewFaq()
    local q = norm(readField(faqField, 64))
    local rows = {}
    for _, e in ipairs(FAQ) do
        if type(e) == "table" and (q == "" or string.find(norm(e.q), q, 1, true) or string.find(norm(e.a), q, 1, true)) then
            rows[#rows + 1] = { H.lbl(e.n or ""), H.val(plain(e.q)), H.lbl(plain(e.a)), e = e }
        end
    end
    return { cols = { { title = "#", w = 28 }, { title = "Question", flex = 1, min = 90 }, { title = "Solution", flex = 2, min = 100 } }, data = arr(rows),
        onRow = function(i)
            -- 0.2.9: a click shows the question and its main answer here;
            -- only More info opens the whole conversation in the pop-up.
            sel[T_FAQ] = rows[i].e; tbl.selected = i
            local list = {}
            for k, r in ipairs(rows) do list[k] = r.e end
            NT.faqList, NT.faqIdx = list, i
        end,
        detail = function()
            if #FAQ == 0 then return { lines = { H.col(H.C_WARN, "No FAQ entries yet: the Discord research file has not been added to this build.") } } end
            local e = sel[T_FAQ]
            if e == nil then return { lines = { H.lbl(#FAQ .. " questions from the plugin developer Discord (Oct 19-23, 2026). Click a row to see the question and main answer; More info shows the whole conversation.") } } end
            return NT.faqSummary(e, areaW() - 8, wrap)
        end }
end
-- 0.2.9: inline summary for the selected FAQ entry (kept out of the main
-- chunk's locals: it is at Lua's 200-local limit).
NT.faqSummary = function(e, w, wrapf)
    local function who(p)
        if p == nil then return "" end
        local t = plain(p.user or "Unknown user")
        if (p.tag or "") ~= "" then t = t .. " [" .. plain(p.tag) .. "]" end
        if (p.date or "") ~= "" then t = t .. ", " .. plain(p.date) end
        return t
    end
    local posts = type(e.posts) == "table" and e.posts or {}
    local qp, ap, nrep = nil, nil, 0
    for _, p in ipairs(posts) do
        if p.role == "Q" then qp = qp or p else nrep = nrep + 1; if ap == nil or (p.tag == "Jagex staff" and ap.tag ~= "Jagex staff") then ap = p end end
    end
    local lines = {}
    for _, l in ipairs(wrapf("Q" .. (e.n or "") .. ": " .. plain(e.q), w, 2)) do lines[#lines + 1] = H.gold(l) end
    if qp then lines[#lines + 1] = H.lbl("Asked by ") .. H.col("ffcc44", who(qp)) end
    if ap then
        lines[#lines + 1] = H.lbl("Main answer by ") .. H.col(ap.tag == "Jagex staff" and "ff9a3c" or "9fd3ff", who(ap))
        local room = DETAIL_N - 1 - #lines
        for _, l in ipairs(wrapf(plain(table.concat(ap.lines or {}, " ")), w, room)) do lines[#lines + 1] = H.val(l) end
    end
    lines[#lines + 1] = H.lbl(nrep .. (nrep == 1 and " reply" or " replies") .. " in the conversation. More info shows every post.")
    return { lines = lines, more = true }
end

-- Audio bus test: one click plays the selected sound (or the first in the
-- list) once on that bus; the table shows what audio.Play returned and
-- whether the instance reports isPlaying. Audibility is for your ears.
local busRes = {}
viewBusTest = function()
    local buses = {}
    pcall(function() for k, v in pairs(audio.AudioBus) do if type(k) == "string" then buses[#buses + 1] = k end end end)
    table.sort(buses, function(a, b) if a == "MASTER" then return true elseif b == "MASTER" then return false end return a < b end)
    local s = sel[T_AUDIO] or snd.all[1]
    local rows = {}
    for _, b in ipairs(buses) do
        local r = busRes[b]
        local st = "-"
        if r then st = r.inst and (isPlaying(r.inst) and "playing" or "finished") or "Play returned nil" end
        rows[#rows + 1] = { H.val(nice(b)), H.lbl(r and r.sid or "-"), H.lbl(r and (r.inst and "instance" or "nil") or "not tried"), st == "playing" and H.col(H.C_GOOD, st) or H.lbl(st), bus = b }
    end
    return { cols = { { title = "Bus", flex = 1, min = 80 }, { title = "Sound", w = 60 }, { title = "Play result", w = 90 }, { title = "isPlaying", w = 90 } },
        data = arr(rows),
        onRow = function(i)
            local b = rows[i].bus
            if s == nil then return end
            pcall(function() if snd.insts[s.id] then snd.insts[s.id]:Stop() end end); snd.insts[s.id] = nil; sndPlay(s.id, b)
            busRes[b] = { sid = s.id, inst = snd.insts[s.id] }
        end,
        detail = function()
            return { lines = { H.lbl("Test sound: ") .. H.val(s and (s.name .. " (" .. s.id .. ")") or "none loaded") .. H.lbl("  pick one in Sounds mode"),
                H.lbl("Click a bus to play it once. A returned instance does not prove it is audible: listen."),
                H.lbl("Sounds mode plays on the bus chosen with the Bus button (now " .. state.bus .. ").") } }
        end }
end

-------------------------------------------------------------------------------
-- 12. Diagnostics: live checks for problems plugin developers report.
--     Each row is a real test run in this client right now.
-------------------------------------------------------------------------------
local diag = { rows = nil, dbTest = nil }
-- Layer / component leak detector (FAQ 13: "Failed to Create Layer ... invalid
-- dynamic ID, expected a value between 0 and 4096"). Counts what is on the
-- shared plugin layer now, against the first count taken this session.
local leak = { base = nil, last = nil, peak = 0 }
CATG.layerCount = function()
    local top = helpers.ensureHoverLayer()
    if top == nil then return nil end
    local direct, total = 0, 0
    local function walk(c, d)
        for _, ch in ipairs(children(c)) do
            if total >= 6000 then return end
            total = total + 1
            if d == 1 then direct = direct + 1 end
            if d < 8 then walk(ch.c, d + 1) end
        end
    end
    walk(top, 1)
    return direct, total
end
local function leakCheck()
    local d, t = CATG.layerCount()
    if d == nil then return end
    leak.last = { d = d, t = t }
    if leak.base == nil then leak.base = { d = d, t = t } end
    if t > leak.peak then leak.peak = t end
end
-- 0.5.3: PluginShutdown is a global of THIS plugin's environment; plugins do
-- not run with _G as their environment, so rawget(_G, ...) never saw it.
NT.hasShutdown = function()
    local ok, f = pcall(function() return PluginShutdown end)
    if ok and type(f) == "function" then return true end
    local ok2, g = pcall(function() return rawget(_G, "PluginShutdown") end)
    return ok2 and type(g) == "function"
end
local function yes(b, good, bad) return b and H.col(H.C_GOOD, good or "yes") or H.col(H.C_WARN, bad or "no") end
-- expected "off" states (e.g. a permission not granted) are neutral grey, not amber
local function neutral(b, good, bad) return b and H.col(H.C_GOOD, good or "yes") or H.col(H.C_LABEL, bad or "no") end
local function diagRun()
    local rows = {}
    local function add(area, check, result, how) rows[#rows + 1] = { H.val(area), H.lbl(check), result, H.lbl(how or "") } end
    -- permissions
    for _, p in ipairs({ "httpAccess", "chatAccess", "trackingAccess" }) do
        local ok, v = pcall(function() return Plugin.HasPermission(PluginPermissions[p]) end)
        add("Permission", p, ok and neutral(v == true, "granted", "not granted") or H.col(H.C_BAD, "error"), "Plugin.HasPermission")
    end
    -- resources
    local nres = 0
    pcall(function()
        for k, r in pairs(Plugin.resources) do
            nres = nres + 1
            local loaded, inUse = nil, nil
            pcall(function() loaded = r.loaded; inUse = r.inUse end)
            add("Resource", tostring(k), yes(loaded == true, "loaded", "not loaded"), "in use " .. tostring(inUse))
        end
    end)
    if nres == 0 then add("Resource", "Plugin.resources", H.lbl("none (this plugin ships no resources)"), "files go in resources/") end
    local nurl = 0
    pcall(function() for _ in pairs(Plugin.urls) do nurl = nurl + 1 end end)
    add("Manifest", "urls", H.lbl(nurl), "Plugin.urls (needs httpAccess to use)")
    add("Manifest", "plugin.json", H.lbl("not readable"), "no file API; run release/validate_plugin_json.py")
    -- events
    local nsub, nfail = 0, 0
    for _, n in ipairs(EVENTS) do if subs[n] then nsub = nsub + 1 elseif subs[n] == false then nfail = nfail + 1 end end
    add("Events", "subscribed", yes(nfail == 0, nsub .. " ok", nsub .. " ok, " .. nfail .. " failed"), "see Error Log for failures")
    add("Events", "Draw firing", neutral((ev.counts.Draw or 0) > 0, "yes", "not yet"), "frame events")
    add("Events", "ServerLogic firing", neutral((ev.counts.ServerLogic or 0) > 0, "yes", "not yet (log in)"), "needs to be logged in")
    -- core API
    local mouse = false
    pcall(function() mouse = Mouse.IsAvailable() == true end)
    add("Mouse", "IsAvailable", neutral(mouse, "yes", "not now"), "false while the game window is unfocused")
    add("Lua", "os.clock", neutral(perf.hasClock, "available", "not available in sandbox"), "timing falls back to Logic ticks")
    add("Lua", "debug.traceback", neutral(hasTrace, "available", "not available in sandbox"), "Error Log shows the message and source:line instead")
    add("Lua", "io library", neutral(type(rawget(_G, "io")) == "table", "present", "not present"), "plugins are sandboxed")
    add("Lua", "require", yes(type(require) == "function", "available", "missing"), "loads this plugin's own .lua files")
    add("UI", "plugin layer", yes(helpers.ensureHoverLayer() ~= nil, "reachable", "missing"), "TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP")
    local fw = helpers.textWidthOf(H.FONT, "Test")
    add("UI", "text width", yes(fw ~= nil, math.floor(fw or 0) .. " px", "not measurable"), "Font:GetStringWidth")
    local spr = 0
    pcall(function() for _ in pairs(id.Sprite) do spr = spr + 1 end end)
    add("IDs", "id.Sprite table", neutral(spr > 0, commas(spr) .. " names", "not exposed"), "otherwise FromID scan")
    local obj = nil
    pcall(function() obj = config.Obj.FromID(1).name end)
    add("Config", "config.Obj.FromID(1)", neutral(obj ~= nil, plain(obj or ""), "not loaded yet (log in)"), "item lookups")
    local opt = nil
    pcall(function() opt = game.options.VolumeMaster.setting end)
    add("Options", "game.options read", neutral(opt ~= nil, tostring(opt), "not reported"), "read only")
    add("Storage", "PersistentDB round trip", diag.dbTest or H.lbl("click to run"), "writes key rdt_selftest in this plugin")
    -- layer leak detector (FAQ 13)
    leakCheck()
    if leak.last then
        local L, B = leak.last, leak.base
        add("Layer IDs", "panels on plugin layer", H.lbl(L.d), "direct children, all plugins")
        add("Layer IDs", "components on plugin layer", yes(L.t < 3500, L.t .. " of 4096", L.t .. " of 4096, near the limit"), "dynamic ID limit (FAQ 13)")
        local grow = L.t - B.t
        -- 0.5.3: the plugin layer is shared by every plugin and the Plugin
        -- Hub, and the baseline is taken when this tab first runs, so panels
        -- opened afterwards count as growth. That is information, not a leak;
        -- the real limit is the 4096 total above (amber at 3500).
        add("Layer IDs", "growth this session", H.lbl((grow >= 0 and "+" or "") .. grow .. " (all plugins, since first check)"), "a real leak shows as the total nearing 4096")
        add("Layer IDs", "this plugin's components", H.lbl(#reg), "destroyed in PluginShutdown")
    else
        add("Layer IDs", "plugin layer", H.col(H.C_WARN, "not readable"), "")
    end
    add("Cleanup", "PluginShutdown defined", yes(NT.hasShutdown(), "yes", "missing"), "needed to destroy library-made UI (FAQ 7, 13)")
    -- high-DPI drag test (FAQ 15)
    local px, ux = nil, nil
    pcall(function() if Mouse.IsAvailable() then px = Mouse.GetPosition().x end end)
    ux = helpers.mouseUI()
    if px and ux and ux > 0 then
        local r = px / ux
        add("High DPI", "window px per UI unit", neutral(math.abs(r - 1) < 0.05, fmt(r, 2), fmt(r, 2) .. " (high DPI, drags are scaled)"), "raw coords not 1:1 on 2K/4K (FAQ 15)")
    else
        add("High DPI", "window px per UI unit", H.lbl("move the mouse over the game"), "FAQ 15")
    end
    add("Lua", "os library", neutral(type(rawget(_G, "os")) == "table" or type(os) == "table", "present", "not available in sandbox"), "Logic ticks used instead (FAQ 22)")
    add("Manifest", "requiredPermissions", H.lbl("use optionalPermissions"), "required does not work yet (FAQ 1)")
    add("Known issues", "Discord FAQ checks", #FAQ > 0 and H.lbl(#FAQ .. " FAQ entries") or H.col(H.C_WARN, "FAQ file not in build"), "see Help/FAQ")
    diag.rows = rows
end
local function dbRoundTrip()
    local ok = pcall(function()
        local v = tostring(ticks)
        PersistentDB:SetStructuredData("rdt_selftest", { v = v })
        local back = PersistentDB:GetStructuredData("rdt_selftest")
        if type(back) ~= "table" or back.v ~= v then error("read back differed") end
    end)
    diag.dbTest = yes(ok, "passed", "failed")
end
local function viewDiag()
    if diag.rows == nil then diagRun() end
    local rows = diag.rows
    return { cols = { { title = "Area", w = 72 }, { title = "Check", flex = 1, min = 80 }, { title = "Result", w = 100 }, { title = "Notes", flex = 1.6, min = 90 } },
        data = arr(rows),
        onRow = function(i)
            if untag(rows[i][2]) == "PersistentDB round trip" then dbRoundTrip() end
            sel[12] = rows[i]; diagRun()
        end,
        detail = function()
            local r = sel[12]
            local nOk, nWarn, nBad = 0, 0, 0
            for _, row in ipairs(rows) do
                local res = tostring(row[3] or "")
                if res:find(H.C_GOOD, 1, true) then nOk = nOk + 1
                elseif res:find(H.C_BAD, 1, true) then nBad = nBad + 1
                elseif res:find(H.C_WARN, 1, true) then nWarn = nWarn + 1 end
            end
            local sum = H.col(H.C_GOOD, nOk .. " ok") .. H.lbl(", ") .. H.col(nWarn > 0 and H.C_WARN or H.C_LABEL, nWarn .. (nWarn == 1 and " warning" or " warnings"))
                .. H.lbl(", ") .. H.col(nBad > 0 and H.C_BAD or H.C_LABEL, nBad .. (nBad == 1 and " failure" or " failures"))
            return { lines = { sum, H.lbl("Grey = expected off state. Click the PersistentDB row to test storage.") },
                copy = r and (untag(r[1]) .. " / " .. untag(r[2]) .. ": " .. untag(r[3])) or nil }
        end }
end

-------------------------------------------------------------------------------
-- 13. Error Log (this plugin's errors with stack traces, plus event log)
-------------------------------------------------------------------------------
local function viewErrors()
    return { cols = { { title = "Time s", w = 60 }, { title = "Where", w = 110 }, { title = "Error", flex = 1, min = 90 } },
        empty = "No errors since load (" .. fmt(secs(), 0) .. " s ago)",
        data = { count = #errlog, get = function(i)
            local e = errlog[i]; return { H.lbl(fmt(e.t / 50, 1)), H.val(e.where), H.col(H.C_BAD, e.msg) } end },
        onRow = function(i) if #errlog == 0 then return end; sel[13] = errlog[i]; tbl.selected = i end,
        detail = function()
            local e = sel[13]
            if e == nil then return { lines = { H.lbl(#errlog .. " errors caught in this plugin's callbacks. Other plugins' errors are not visible to plugins."),
                H.lbl("Stack traces: ") .. (hasTrace and H.val("debug.traceback") or H.col(H.C_WARN, "not available in this client")) } } end
            local lines = { H.col(H.C_BAD, e.msg) }
            local tr = e.trace or "no stack trace"
            for l in tr:gmatch("[^\n]+") do if #lines < 6 then lines[#lines + 1] = H.lbl(l) end end
            return { lines = lines, copy = e.msg .. " | " .. tr:gsub("\n", " | ") }
        end }
end

-------------------------------------------------------------------------------
-- 14. API Explorer: what the API exposes in this client, with live
--     read-only test calls. Missing namespaces are flagged, not hidden.
-------------------------------------------------------------------------------
local api = { mode = "members", rows = nil, tries = {} }
-- Known gaps and bugs reported in the plugin developer Discord (FAQ numbers).
-- "Live" runs a presence check where one is possible; otherwise "reported".
local function apiMembers()
    local rows = {}
    for _, ns in ipairs(D.API_NS) do
        local t = rawget(_G, ns)
        if t == nil then
            rows[#rows + 1] = { H.val(ns), H.lbl("-"), H.col(H.C_WARN, "missing") }
        else
            local keys = {}
            pcall(function() for k, v in pairs(t) do keys[#keys + 1] = { k = tostring(k), ty = type(v) } end end)
            table.sort(keys, function(a, b) return a.k < b.k end)
            if #keys == 0 then rows[#rows + 1] = { H.val(ns), H.lbl(type(t)), H.col(H.C_GOOD, "present (not listable)") } end
            for i, k in ipairs(keys) do
                if i > 400 then rows[#rows + 1] = { H.val(ns .. "..."), H.lbl(""), H.lbl((#keys - 400) .. " more") }; break end
                rows[#rows + 1] = { H.val(ns .. "." .. plain(k.k)), H.lbl(k.ty), H.col(H.C_GOOD, "present") }
            end
        end
    end
    return rows
end
local function viewApi()
    if api.mode == "gaps" then
        local rows = {}
        for _, g in ipairs(D.GAPS) do
            local live = "reported"
            if g[3] then local ok, v = pcall(g[3]); live = ok and tostring(v) or "check failed" end
            rows[#rows + 1] = { H.val(g[1]), H.lbl(g[2]), H.lbl(live), g = g }
        end
        return { cols = { { title = "Known gap or bug", flex = 2, min = 120 }, { title = "FAQ", w = 36 }, { title = "Live check", flex = 1, min = 80 } },
            data = arr(rows),
            onRow = function(i) sel[14.7] = rows[i].g; tbl.selected = i end,
            detail = function()
                local g = sel[14.7]
                if g == nil then return { lines = { H.lbl("From the plugin developer Discord. Click a row to see the FAQ answer.") } } end
                for _, e in ipairs(FAQ) do if e.n == g[2] then
                    local lines = { H.gold(plain(e.q)) }
                    for _, l in ipairs(wrap(plain(e.a), areaW() - 8, DETAIL_N - 1)) do lines[#lines + 1] = H.val(l) end
                    return { lines = lines, copy = plain(e.a) }
                end end
                return { lines = { H.val(g[1]) } }
            end }
    elseif api.mode == "events" then
        local rows = {}
        for _, n in ipairs(EVENTS) do
            local st = subs[n] == true and H.col(H.C_GOOD, "works") or (subs[n] == false and H.col(H.C_BAD, "subscribe failed") or H.lbl("-"))
            rows[#rows + 1] = { H.val("Event." .. n), st, H.lbl(ev.counts[n] or 0) }
        end
        rows[#rows + 1] = { H.val("Event.ChatMessage"), H.lbl("not tested"), H.lbl("needs chatAccess") }
        return { cols = { { title = "Event", flex = 1, min = 110 }, { title = "Subscribe", w = 110 }, { title = "Fired", w = 60 } }, data = arr(rows) }
    elseif api.mode == "try" then
        local rows = {}
        for i, t in ipairs(D.TRIES) do
            local r = api.tries[i]
            rows[#rows + 1] = { H.val(t[1]), r == nil and H.lbl("click to run") or (r.ok and H.col(H.C_GOOD, "ok") or H.col(H.C_BAD, "error")), H.lbl(r and r.v or "") }
        end
        return { cols = { { title = "Read-only call", flex = 2, min = 120 }, { title = "Status", w = 80 }, { title = "Result", flex = 1, min = 70 } },
            data = arr(rows),
            onRow = function(i)
                local trace = nil
                local ok, v = xpcall(D.TRIES[i][2], function(e) if hasTrace then pcall(function() trace = debug.traceback(tostring(e), 2) end) end; return e end)
                api.tries[i] = { ok = ok, v = untag(v), trace = trace }
                sel[14] = i; tbl.selected = i
            end,
            detail = function()
                local i = sel[14]
                if i == nil then return { lines = { H.lbl("Click a call to run it now. All calls are read only.") } } end
                local r = api.tries[i]
                return { lines = { H.gold(D.TRIES[i][1]), r.ok and H.val(r.v) or H.col(H.C_BAD, r.v), r.trace and H.lbl((r.trace:gsub("\n", "  "))) or nil },
                    copy = D.TRIES[i][1] .. "  -- " .. r.v }
            end }
    end
    api.rows = api.rows or apiMembers()
    local q = norm(readField(api.field, 64))
    local rows = {}
    for _, r in ipairs(api.rows) do if q == "" or string.find(norm(untag(r[1])), q, 1, true) then rows[#rows + 1] = r end end
    return { cols = { { title = "Name", flex = 2, min = 120 }, { title = "Type", w = 70 }, { title = "In this client", w = 110 } }, data = arr(rows),
        onRow = function(i) sel[14.5] = rows[i]; tbl.selected = i end,
        detail = function()
            local r = sel[14.5]
            return { lines = { H.lbl(#api.rows .. " entries read live from the API tables. Missing ones are marked.") }, copy = r and untag(r[1]) or nil }
        end }
end


-------------------------------------------------------------------------------
-- 15. Commands: run documented console commands with ExecuteConsoleCommand.
--     Only commands from the official docs (tutorial 1, Core, Developer
--     cheats) and the Discord FAQ are listed. Runs only on a Run click;
--     poff / prl of RS Dev Tools and !resetsave need a Confirm click.
--     ExecuteConsoleCommand needs no permission (the documented
--     PluginPermissions are httpAccess, chatAccess and trackingAccess only).
-------------------------------------------------------------------------------
local cmd, viewCmd, cmdFn, cmdBuild, cmdRun, cleanCmd
do
local CMDS = {
    { "help", {}, "List the console commands this client has", "API docs: Core, ExecuteConsoleCommand" },
    { "plist", {}, "List the plugins found in dev_plugins and which are enabled", "Tutorial 1" },
    { "prf", {}, "Refresh the plugin list; also needed after any plugin.json change", "Tutorial 1; FAQ 4, 6" },
    { "pon", { "plugin" }, "Turn a plugin on (enable it)", "Tutorial 1" },
    { "poff", { "plugin" }, "Turn a plugin off (disable it)", "Tutorial 1" },
    { "prl", { "plugin" }, "Reload a plugin (off and on again) to pick up edited Lua files", "Tutorial 1; FAQ 6" },
    { "ppr", { "plugin" }, "Set up a plugin's permissions in dev, before ppe", "FAQ 2, 3" },
    { "ppe", { "plugin", "permission" }, "Grant a permission in dev (httpAccess, chatAccess or trackingAccess), then prl", "FAQ 2, 3" },
    { "pan", { "text" }, "List every config of a type with IDs and config names, e.g. Obj (names for !give), VarPlayer, Enum", "Docs: Developer cheats; RS Wiki Vars Project", { "TYPE (Obj, VarPlayer, Enum)" } },
    { "commands", {}, "Same as help: list the console commands", "RS Wiki: Developer console" },
    { "displayfps", {}, "Show the FPS readout for performance tests", "FAQ 6" },
    { "!tele", { "rest" }, "Dev cheat: Teleport to a coordinate (0,50,50,32,32 or 0,50,50) or a named spot such as grandexchange. Logged on the server", "Docs: Cheat Commands", { "COORD or NAME" }, "docs only" },
    { "!getcoord", {}, "Dev cheat: Print your current coordinate (and the source region in instances). Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!give", { "rest" }, "Dev cheat: Add an item by config name (not item ID; find names with pan Obj) to your backpack or a named inventory, e.g. logs or coins 200000000 bank. Logged on the server", "Docs: Cheat Commands", { "OBJ [COUNT] [INV]" }, "reported by Dylan" },
    { "!objadd", { "rest" }, "Dev cheat: Drop an item by config name on the ground at your feet. Logged on the server", "Docs: Cheat Commands", { "OBJ [COUNT]" }, "docs only" },
    { "!listinv", { "text" }, "Dev cheat: Print an inventory (e.g. bank, inv, worn) and its VarObj values to the console. Logged on the server", "Docs: Cheat Commands", { "INV" }, "docs only" },
    { "!listlocs", { "text" }, "Dev cheat: Print nearby locs to the console (radius up to 32). Logged on the server", "Docs: Cheat Commands", { "RADIUS" }, "docs only" },
    { "!listnpcs", { "text" }, "Dev cheat: Print nearby NPCs to the console (radius up to 32). Logged on the server", "Docs: Cheat Commands", { "RADIUS" }, "docs only" },
    { "!listobjs", { "rest" }, "Dev cheat: Print nearby ground items, optionally filtered by ObjType. Logged on the server", "Docs: Cheat Commands", { "RADIUS [OBJ or null]" }, "docs only" },
    { "!skillsetlevel", { "rest" }, "Dev cheat: Set a skill level (no level-up checks; follow with skilladdlevel 1). Logged on the server", "Docs: Cheat Commands", { "SKILL LEVEL" }, "docs only" },
    { "!skilladdlevel", { "rest" }, "Dev cheat: Add levels to a skill (runs level-up checks). Logged on the server", "Docs: Cheat Commands", { "SKILL COUNT" }, "docs only" },
    { "!skillsetxp", { "rest" }, "Dev cheat: Set a skill's XP (no level-up checks). Logged on the server", "Docs: Cheat Commands", { "SKILL XP" }, "docs only" },
    { "!skilladdxp", { "rest" }, "Dev cheat: Add XP to a skill (runs level-up checks). Logged on the server", "Docs: Cheat Commands", { "SKILL XP" }, "docs only" },
    { "!getvar", { "text" }, "Dev cheat: Print a VarType's value by name. Logged on the server", "Docs: Cheat Commands", { "VAR" }, "docs only" },
    { "!setvar", { "rest" }, "Dev cheat: Set a VarType by name to a value. Logged on the server", "Docs: Cheat Commands", { "VAR VALUE" }, "docs only" },
    { "!getvarc", { "text" }, "Dev cheat: Print a VarClient value by name (Discord: never worked). Logged on the server", "Docs: Cheat Commands", { "VARC" }, "Discord: broken" },
    { "!setvarc", { "rest" }, "Dev cheat: Set a VarClient value by name. Logged on the server", "Docs: Cheat Commands", { "VARC VALUE" }, "docs only" },
    { "!resetsave", {}, "Dev cheat: Flag your dev account to reset to a fresh start at next relog. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!unresetsave", {}, "Dev cheat: Remove the reset flag set by !resetsave. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!godmode", {}, "Dev cheat: Toggle combat invulnerability. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!maxhp", {}, "Dev cheat: Toggle health constantly refilling to max. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!hitall", {}, "Dev cheat: Deal 5000 damage to every NPC within 50 tiles. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!allinone", {}, "Dev cheat: Complete all quests, tasks and more. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!bank", {}, "Dev cheat: Open your bank directly. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!clearworn", {}, "Dev cheat: Destroy everything you are wearing. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!clearinv", {}, "Dev cheat: Destroy everything in your backpack. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!coordsave", {}, "Dev cheat: Remember your current coordinate. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!coordtele", {}, "Dev cheat: Teleport to the coordinate saved by !coordsave. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!setgroupironman", { "text" }, "Dev cheat: Set group ironman status (FAQ: for shared bank tests). Logged on the server", "Docs: Cheat Commands", { "0 or 1" }, "docs only" },
    { "!sethardcore", { "text" }, "Dev cheat: Set hardcore status. Logged on the server", "Docs: Cheat Commands", { "0 or 1" }, "docs only" },
    { "!setironman", { "text" }, "Dev cheat: Set ironman status. Logged on the server", "Docs: Cheat Commands", { "0 or 1" }, "docs only" },
    { "!archcompletetutorial", {}, "Dev cheat: Complete the Archaeology tutorial. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!archgivemats", { "rest" }, "Dev cheat: Add a count of every Archaeology material to an inventory, e.g. 500 bank. Logged on the server", "Docs: Cheat Commands", { "COUNT INV" }, "docs only" },
    { "!inventgivemats", {}, "Dev cheat: Fill every Invention material to max storage. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!inventwipemats", {}, "Dev cheat: Clear all stored Invention materials. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!inventmachinerun", {}, "Dev cheat: Run Invention machines for 1 simulated hour. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!inventsetperks", { "rest" }, "Dev cheat: Set gizmo perks and ranks on a backpack item, e.g. 0 7 1 44 2 1. Logged on the server", "Docs: Cheat Commands", { "SLOT PERK RANK ..." }, "docs only" },
    { "!tlihide", {}, "Dev cheat: Hide the game interface. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!tlishow", {}, "Dev cheat: Show the game interface again. Logged on the server", "Docs: Cheat Commands", {}, "docs only" },
    { "!pouchadd", { "rest" }, "Dev cheat: Add currency to your pouch by currency ID, e.g. 44 100000 1 (last value: 1 = cap at max, 0 = add nothing on overflow). Logged on the server", "Docs: Cheat Commands", { "CURRENCY COUNT 0|1" }, "docs only" },
    { "!pouchdel", { "rest" }, "Dev cheat: Remove currency from your pouch by currency ID. Logged on the server", "Docs: Cheat Commands", { "CURRENCY COUNT" }, "docs only" },
    { "!pouchdeposit", { "rest" }, "Dev cheat: Move all of a currency from an inventory into your pouch. Logged on the server", "Docs: Cheat Commands", { "CURRENCY INV" }, "docs only" },
    { "!pouchwithdraw", { "text" }, "Dev cheat: Move as much of a currency as fits from your pouch to your backpack. Logged on the server", "Docs: Cheat Commands", { "CURRENCY" }, "docs only" },
    { "!pouchspace", { "text" }, "Dev cheat: Print the free pouch space for a currency. Logged on the server", "Docs: Cheat Commands", { "CURRENCY" }, "docs only" },
    { "!pouchtotal", { "text" }, "Dev cheat: Print the pouch total for a currency. Logged on the server", "Docs: Cheat Commands", { "CURRENCY" }, "docs only" },
    { "!testpouchadd", { "rest" }, "Dev cheat: Add the exact count only if it fits. Logged on the server", "Docs: Cheat Commands", { "CURRENCY COUNT" }, "docs only" },
    { "!testpouchdel", { "rest" }, "Dev cheat: Remove the exact count only if you have it. Logged on the server", "Docs: Cheat Commands", { "CURRENCY COUNT" }, "docs only" },
}
local ARG_HINT = { plugin = "PLUGIN folder", permission = "PERMISSION", coords = "COORDS", text = "VALUE", rest = "VALUES" }
local function hintOf(c, k) return (c[5] and c[5][k]) or ARG_HINT[c[2][k]] end
local PERMS = { httpaccess = "httpAccess", chataccess = "chatAccess", trackingaccess = "trackingAccess" }
cmd = { mode = "list", hist = {}, pending = nil, arg1 = nil, arg2 = nil, free = nil, runB = nil, sel = nil, note = nil }
cmdFn = function() local f = rawget(_G, "ExecuteConsoleCommand"); return type(f) == "function" and f or nil end
cleanCmd = function(s)
    local t = helpers.cleanText(s, 160)
    t = t:gsub("[^%w%s%-_%.,!:/=%+]", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return t
end
local function cleanArg(kind, s)
    local t = helpers.cleanText(s, 64)
    if kind == "plugin" then
        t = string.lower(t):gsub("[%s_]+", "-"):gsub("[^a-z0-9%-]", "")
        return t ~= "" and t or nil
    elseif kind == "permission" then
        return PERMS[string.lower(t):gsub("[^a-z]", "")]
    elseif kind == "coords" then
        t = t:gsub("[^%d,]", "")
        return t:match("^%d+,%d+,%d+,%d+,%d+$") and t or nil
    elseif kind == "text" then
        -- 0.2.11: one cheat token (config name, number, 0/1)
        t = t:gsub("[^%w_,%.%-]", "")
        return t ~= "" and t or nil
    elseif kind == "rest" then
        -- 0.2.11: several space-separated cheat tokens
        t = t:gsub("[^%w_,%.%- ]", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
        return t ~= "" and t or nil
    end
    return nil
end
--- true when the text would disable, reload or reset RS Dev Tools / the save
local function needsConfirm(text)
    local w = {}
    for word in string.lower(text):gmatch("%S+") do w[#w + 1] = word end
    for i, x in ipairs(w) do
        if x == "!resetsave" then return "!resetsave resets your dev character" end
        local DANGER = { ["!clearworn"] = "it destroys everything you wear", ["!clearinv"] = "it destroys your backpack", ["!inventwipemats"] = "it wipes your Invention materials",
            ["!hitall"] = "it hits every NPC within 50 tiles", ["!setironman"] = "it changes your account type", ["!sethardcore"] = "it changes your account type",
            ["!setgroupironman"] = "it changes your account type", ["!pouchdel"] = "it removes currency", ["!allinone"] = "it completes all quests and tasks" }
        if DANGER[x] then return x .. ": " .. DANGER[x] end
        if (x == "poff" or x == "prl") and w[i + 1] then
            local t = w[i + 1]:gsub("[%s_]+", "-")
            if t == SLUG or t == "rs-dev-tools" or t == "rsdevtools" then
                return x == "poff" and "this turns RS Dev Tools off" or "this reloads RS Dev Tools (its panel closes and reopens)"
            end
        end
    end
    return nil
end
cmdRun = function(text, confirmed)
    local f = cmdFn()
    if f == nil then cmd.note = "ExecuteConsoleCommand is not available in this client; nothing was run."; return end
    if text == nil or text == "" then cmd.note = "Nothing to run."; return end
    local why = needsConfirm(text)
    if why and not confirmed then cmd.pending = text; cmd.note = "Confirm needed: " .. why .. "."; return end
    cmd.pending = nil
    local ok, err = pcall(f, text)
    table.insert(cmd.hist, 1, { t = secs(), c = text, ok = ok, r = ok and "sent (output is shown in the console only)" or untag(tostring(err)) })
    if #cmd.hist > 100 then cmd.hist[#cmd.hist] = nil end
    if not ok then logError("ExecuteConsoleCommand", tostring(err)) end
    cmd.note = ok and ("Sent: " .. text) or ("Error: " .. untag(tostring(err)))
end
NT.cmdRun, NT.needsConfirm, NT.cmdFn, NT.cmd = cmdRun, needsConfirm, cmdFn, cmd
-- 0.3.0 per-argument controls for cheat commands with argument data
-- (rdt_cmd_args.lua): ID and fixed-value arguments get a dropdown shown as
-- "ID - Name"; counts, levels, XP and slots get a number box with - and +;
-- words get a text box (plus a dropdown when a partial list is known).
cmd.tokv, cmd.slots = {}, {}
cmd.info = function(c)
    if c == nil then return nil end
    if cmd.args == nil then local ok, d = pcall(require, "rdt_cmd_args"); cmd.args = (ok and type(d) == "table") and d or {} end
    return cmd.args[c[1]]
end
cmd.pool = function(c) local i = cmd.info(c); return i ~= nil and c[1]:sub(1, 1) == "!" and #i.args > 0 and #i.args <= 6 end
cmd.valsOf = function(c, pos)
    if cmd.vals == nil then local ok, d = pcall(require, "rdt_cmd_vals"); cmd.vals = (ok and type(d) == "table") and d or {} end
    return cmd.vals[c[1] .. "#" .. pos] or {}
end
-- item and var names are filled from the plugin API when first opened
-- (read only): id.Obj config names (fallback: the Item browser scan),
-- id.VarPlayer / id.VarBit, or id.VarClient.
cmd.liveCache = {}
cmd.live = function(a)
    local key = a.runtime .. (a.type:find("VarClient") and "c" or "")
    if cmd.liveCache[key] then return cmd.liveCache[key] end
    local out = {}
    local function from(t, note)
        pcall(function() for k, v in pairs(t) do if type(k) == "string" and type(v) == "number" then out[#out + 1] = { k, note .. " " .. v } end end end)
    end
    if a.runtime == "items" then
        from(rawget(_G, "id") and id.Obj or {}, "item")
        if #out == 0 then for _, e in ipairs(lists.item.items) do out[#out + 1] = { tostring(e.raw or e.name), "item " .. tostring(e.id) } end end
    elseif key == "varsc" then from(rawget(_G, "id") and id.VarClient or {}, "varclient")
    else from(rawget(_G, "id") and id.VarPlayer or {}, "varp"); from(rawget(_G, "id") and id.VarBit or {}, "varbit") end
    table.sort(out, function(x, y) return x[1] < y[1] end)
    if #out > 0 then cmd.liveCache[key] = out end
    return out
end
cmd.label = function(v)
    local n = v[2] or ""
    if n == "" then return v[1] end
    n = n:gsub("^%l", string.upper)
    if v[1]:match("^%-?%d+$") then return v[1] .. " - " .. n end
    return v[1] .. "  (" .. n .. ")"
end
-- slot kinds: "dd" = dropdown only, "ddtext" = dropdown + text box,
-- "num" = number box with - +, "text" = text box
cmd.kind = function(c, pos)
    local i = cmd.info(c); local a = i and i.args[pos]
    if a == nil then return nil end
    local nm, ty = a.name:lower(), a.type:lower()
    if (a.nvals or 0) > 0 and not a.runtime then
        if a.complete then return "dd" end
        return "ddtext"
    end
    if ty:find("integer") and not ty:find("string") then return "num" end
    if nm:find("count") or nm:find("amount") or nm:find("level") or nm:find("xp") or nm:find("radius") or nm:find("slot") then return "num" end
    return "text"
end
cmd.setTok = function(pos, v)
    local sl = cmd.slots[pos]
    local k = cmd.kind(cmd.sel, pos)
    if sl and (k == "num" or k == "text" or k == "ddtext") then pcall(function() sl.f.content = v end) end
    cmd.tokv[pos] = v
    if sl and sl.dd then pcall(function() sl.dd:refresh() end) end
end
cmd.clearToks = function()
    cmd.tokv = {}
    for _, sl in ipairs(cmd.slots) do pcall(function() sl.f.content = "" end); if sl.dd then pcall(function() sl.dd:refresh() end) end end
end
cmdBuild = function()
    local c = cmd.sel
    if c == nil then return nil, "Pick a command in the table." end
    if cmd.pool(c) then
        local info = cmd.info(c)
        local parts, gap = { c[1] }, nil
        for pos, a in ipairs(info.args) do
            local k = cmd.kind(c, pos)
            local v = cmd.tokv[pos]
            local sl = cmd.slots[pos]
            if k ~= "dd" and sl then v = readField(sl.f, 80) end
            v = tostring(v or ""):gsub("[^%w_%-%.,:]", "")
            if v == "" and a.default ~= "" and not a.required then v = nil end
            if v == "" or v == nil then
                if a.required then return nil, "Argument " .. pos .. " (" .. a.name .. ") is missing." end
                gap = gap or pos
            else
                if gap then return nil, "Argument " .. gap .. " (" .. info.args[gap].name .. ") must be set before argument " .. pos .. "." end
                parts[#parts + 1] = v
            end
        end
        return table.concat(parts, " "), nil
    end
    local parts = { c[1] }
    for k, kind in ipairs(c[2]) do
        local raw = readField(k == 1 and cmd.arg1 or cmd.arg2, 64)
        local v = cleanArg(kind, raw)
        if kind == "plugin" and v == nil then v = SLUG end
        if v == nil then return nil, "Argument " .. k .. " (" .. hintOf(c, k) .. ") is missing or not valid." end
        parts[#parts + 1] = v
    end
    return table.concat(parts, " "), nil
end
viewCmd = function()
    local f = cmdFn()
    local status = f and H.col(H.C_GOOD, "Console commands available") or H.col(H.C_BAD, "Console commands missing: Run disabled")
    local function lines(extra)
        -- one header line; fixed 4 lines so the table never jumps
        local L = { status .. H.lbl(" - no permission needed") }
        for _, x in ipairs(extra) do L[#L + 1] = x end
        if cmd.pending then L[#L + 1] = H.col(H.C_WARN, "Pending: " .. cmd.pending .. " - Confirm or Cancel")
        elseif cmd.note then L[#L + 1] = H.lbl(cmd.note) end
        while #L < 3 do L[#L + 1] = " " end
        while #L > 3 do table.remove(L) end
        return L
    end
    if cmd.mode == "history" then
        local rows = {}
        for _, h in ipairs(cmd.hist) do
            rows[#rows + 1] = { H.lbl(fmt(h.t, 0)), H.val(h.c), h.ok and H.col(H.C_GOOD, h.r) or H.col(H.C_BAD, h.r), h = h }
        end
        return { cols = { { title = "Ran", w = 50 }, { title = "Command", flex = 1, min = 90 }, { title = "Result", flex = 1, min = 90 } }, data = arr(rows),
            onRow = function(i) sel[T_CMD] = rows[i].h; tbl.selected = i end,
            detail = function()
                local h = sel[T_CMD]
                return { lines = lines({ H.lbl(#cmd.hist .. " commands run this session. Plugins cannot read console output.") }), copy = h and h.c or nil }
            end }
    end
    -- 0.3.0 More info: every argument of the picked command, in order
    -- (data in rdt_cmd_args.lua, generated by release/gen_cmd_args.py).
    if cmd.more and cmd.sel and cmd.mode == "list" then
        if cmd.args == nil then local ok, d = pcall(require, "rdt_cmd_args"); cmd.args = (ok and type(d) == "table") and d or {} end
        local c = cmd.sel
        local info = cmd.args[c[1]]
        local va = cmd.valArg and info and info.args[cmd.valArg]
        if va then
            -- every allowed value of one argument (paged); click inserts it
            if cmd.vals == nil then local ok, d = pcall(require, "rdt_cmd_vals"); cmd.vals = (ok and type(d) == "table") and d or {} end
            local pos = cmd.valArg
            local list = va.runtime and cmd.live(va) or cmd.valsOf(c, pos)
            local q = readField(cmd.valF, 40):lower()
            if q ~= "" then
                local key = tostring(list) .. "|" .. q
                if cmd.fKey ~= key then
                    local out = {}
                    for _, v in ipairs(list) do if v[1]:lower():find(q, 1, true) or v[2]:lower():find(q, 1, true) then out[#out + 1] = v end end
                    cmd.fKey, cmd.fList = key, out
                end
                list = cmd.fList
            end
            return { key = "vals", cols = { { title = "Value", flex = 2, min = 100 }, { title = "Meaning", flex = 3, min = 100 } },
                data = { count = #list, get = function(i) local v = list[i]; return { H.val(cmd.label(v)), H.lbl(v[2] ~= "" and v[2] or "-"), tip = "Click to put " .. v[1] .. " into the argument box." } end },
                onRow = function(i)
                    local v = list[i] and list[i][1]
                    if v == nil then return end
                    if cmd.pool(c) then cmd.setTok(pos, v)
                    elseif #c[2] == 1 and c[2][1] == "rest" then
                        local toks = {}
                        for t in readField(cmd.arg1, 200):gmatch("%S+") do toks[#toks + 1] = t end
                        for k = #toks + 1, pos - 1 do toks[k] = (info.args[k].default ~= "" and info.args[k].default) or info.args[k].name:upper() end
                        toks[pos] = v
                        pcall(function() cmd.arg1.content = table.concat(toks, " ") end)
                    else
                        local box = pos == 1 and cmd.arg1 or cmd.arg2
                        pcall(function() box.content = v end)
                    end
                    cmd.note = "Put " .. v .. " in as argument " .. pos .. " (" .. va.name .. ")."
                end,
                detail = function()
                    local L = { H.gold(c[1]) .. H.lbl("  argument " .. pos .. ": ") .. H.val(va.name),
                        H.lbl(#list .. " values" .. (q ~= "" and (" matching " .. q) or "") .. (va.runtime and ", read from this client" or "") .. ", ") .. (va.complete and H.col(H.C_GOOD, "complete list") or H.col(H.C_WARN, "partial list")),
                        H.lbl("Click a value to put it in the argument box. Use the pager for more. Back returns to the arguments.") }
                    if cmd.note then L[#L + 1] = H.lbl(cmd.note) end
                    return { lines = L }
                end }
        end
        local rows = {}
        for k, a in ipairs(info and info.args or {}) do
            local un = not a.confirmed
            local mean = (a.meaning ~= "" and a.meaning or "unconfirmed") .. (un and " (unconfirmed)" or "")
            rows[#rows + 1] = { H.lbl(tostring(k)), H.val(a.name), H.lbl(a.type), a.required and H.lbl("required") or H.lbl("optional"),
                H.lbl(a.default ~= "" and a.default or "-"), un and H.col(H.C_WARN, mean) or H.lbl(mean), H.lbl(a.values ~= "" and a.values or "-"),
                a.runtime and H.gold("live >") or ((a.nvals or 0) > 0 and H.gold(a.nvals .. (a.complete and " >" or " partial >")) or H.lbl("-")),
                tip = a.name .. ": " .. mean .. (a.values ~= "" and (" Valid: " .. a.values) or "") .. ((((a.nvals or 0) > 0) or a.runtime) and " Click to see every value." or "") }
        end
        if info == nil then
            for k in ipairs(c[2]) do rows[#rows + 1] = { H.lbl(tostring(k)), H.val(hintOf(c, k)), H.lbl("unconfirmed"), H.lbl("unconfirmed"), H.lbl("-"), H.col(H.C_WARN, "unconfirmed"), H.lbl("-"), H.lbl("-") } end
        end
        return { key = "args", cols = { { title = "#", w = 24 }, { title = "Argument", w = 96 }, { title = "Type", w = 80 }, { title = "Req", w = 60 },
                { title = "Default", w = 60 }, { title = "What it does", flex = 3, min = 120 }, { title = "Valid values", flex = 2, min = 80 }, { title = "List", w = 64 } },
            data = arr(rows),
            onRow = function(i) local a = info and info.args[i]; if a and ((a.nvals or 0) > 0 or a.runtime) then cmd.valArg = i; cmd.note = nil; tbl.page = 1; tbl.selected = nil end end,
            detail = function()
                local desc = c[3]:gsub("^Dev cheat: ", ""):gsub("%. Logged on the server$", "")
                local L = { H.gold(c[1]) .. H.lbl("  " .. desc) }
                L[#L + 1] = H.lbl("Syntax: ") .. H.val(info and info.syntax or c[1])
                if info and info.example ~= "" then L[#L + 1] = H.lbl("Example: ") .. H.val(info.example) end
                if #rows == 0 then L[#L + 1] = H.lbl("This command takes no arguments.") end
                if info and info.notes ~= "" then L[#L + 1] = H.lbl(info.notes) end
                L[#L + 1] = H.lbl("Click an argument with a List value to see every allowed value. Back returns to the command list.")
                return { lines = L, copy = info and info.example and info.example:match("^[^|]+"):gsub("%s+$", "") or c[1] }
            end }
    end
    local rows = {}
    local RED = "E04A3A"
    local dividerDone = false
    for _, c in ipairs(CMDS) do
        local cheat = c[1]:sub(1, 1) == "!"
        if cheat and not dividerDone then
            dividerDone = true
            rows[#rows + 1] = { H.col(RED, "Cheat (!)"), H.col(RED, "----------"), H.col(RED, "dev worlds only, logged on the server; risky ones ask to confirm"), divider = true }
        end
        local a = {}
        for k in ipairs(c[2]) do a[#a + 1] = hintOf(c, k) end
        local desc = c[3]:gsub("^Dev cheat: ", ""):gsub("%. Logged on the server$", "")
        rows[#rows + 1] = { cheat and H.col(RED, c[1]) or H.val(c[1]), H.lbl(#a > 0 and table.concat(a, " ") or "-"), cheat and H.col(RED, desc) or H.lbl(desc),
            c = c,
            tip = "Syntax: " .. c[1] .. (#a > 0 and (" " .. table.concat(a, " ")) or "") .. ". " .. desc .. "." }

    end
    return { cols = { { title = "Command", w = 84 }, { title = "Syntax / args", w = 150 }, { title = "Description", flex = 1, min = 120 } }, data = arr(rows),
        onRow = function(i) if rows[i].divider then return end; if cmd.sel ~= rows[i].c then cmd.clearToks() end; cmd.sel = rows[i].c; sel[T_CMD] = rows[i].c; tbl.selected = i; cmd.pending = nil; cmd.note = nil end,
        detail = function()
            local text, err = cmdBuild()
            local x = {}
            if cmd.sel then
                local a = {}
                for k, kind in ipairs(cmd.sel[2]) do a[#a + 1] = "box " .. k .. ": " .. hintOf(cmd.sel, k) .. (kind == "plugin" and (" (empty = " .. SLUG .. ")") or "") end
                x[#x + 1] = H.gold(cmd.sel[1]) .. H.lbl(#a > 0 and ("  - type " .. table.concat(a, ", ")) or "  - no arguments")
                x[#x + 1] = text and (H.lbl("Will run: ") .. H.val(text)) or H.col(H.C_WARN, err)
            else
                x[#x + 1] = H.lbl("Pick a command, fill its boxes and press Run.")
            end
            return { lines = lines(x), copy = text }
        end }
end
end

;(function()   -- own function scope: the main chunk is at the 200-local limit

-------------------------------------------------------------------------------
-- 16. Submission Check (0.2.7)
--     Rules that get plugins sent back by Jagex / mod.io moderation, from the
--     official Submission process and Plugin guidelines pages, the plugin
--     developer Discord research (Help/FAQ) and our release checklist.
--     Each rule says how it is checked:
--       Live   - tested right now in this client (only what the API exposes)
--       Script - needs the plugin's files; run release/check_submission.py
--                (plugins have no file API and cannot list or read other
--                plugins, so these are never guessed in game)
--       Manual - needs a person (behaviour, mod.io form fields)
--     Display only: nothing is changed, clicked or sent.
-------------------------------------------------------------------------------
local sub = { target = 1, sel = nil }
local SCRIPT_CMD = "python release/check_submission.py PLUGIN_FOLDER --desc DESCRIPTION.txt"
-- { area, rule, mode, fix, live check (returns "pass"|"warn"|"fail", reason) }
local SUB_RULES = {
    { "Manifest", "plugin.json is valid JSON (no trailing commas)", "Script", "Remove the comma before the closing } or ] (FAQ 5)." },
    { "Manifest", "name set, 1-50 ASCII characters", "Script", "Shorten the name or remove non-ASCII characters." },
    { "Manifest", "version uses digits and dots only", "Live", "Use a version like 1.2.3 in plugin.json and on mod.io.",
        function()
            local v = tostring(helpers.VERSION or "")
            if v:match("^%d+[%.%d]*$") and not v:find("%.%.") and not v:find("%.$") then return "pass", "code version " .. v .. " (plugin.json itself: Script)" end
            return "fail", "code version '" .. plain(v) .. "' is not digits and dots"
        end },
    { "Manifest", "contactEmailAddress present (legal requirement)", "Script", "Add a dedicated plugin email (FAQ 10)." },
    { "Manifest", "requiredPermissions empty; permissions are httpAccess / chatAccess / trackingAccess", "Script", "Move permissions to optionalPermissions (FAQ 1)." },
    { "Manifest", "dependencies are objects keyed to mod.io ID numbers", "Script", "Replace names with mod.io IDs before upload (FAQ 9)." },
    { "Files", "main.lua and plugin.json at the zip root", "Script", "Zip the folder's contents, not the folder." },
    { "Files", "no executables, scripts or hidden/system folders", "Script", "Remove .exe .dll .bat .sh .git __MACOSX .DS_Store and similar." },
    { "Files", "image resources at most 1024 x 1024", "Script", "Resize the PNG." },
    { "Files", "every .lua file compiles", "Script", "Fix the syntax error luac reports." },
    { "Code", "PluginShutdown cleans up", "Live", "Define PluginShutdown and destroy library-made components (FAQ 13).",
        function()
            if NT.hasShutdown() then return "pass", "PluginShutdown is defined" end
            return "fail", "no global PluginShutdown function"
        end },
    { "Code", "no component leak (4096 dynamic ID limit)", "Live", "Call layer:DeleteAll() before rebuilding; destroy in PluginShutdown (FAQ 13).",
        function()
            pcall(leakCheck)
            if leak.last == nil then return "warn", "plugin layer not readable" end
            local grew = leak.base and (leak.last.t - leak.base.t) or 0
            if leak.last.t >= 4096 * 0.8 then return "fail", commas(leak.last.t) .. " of 4,096 components on the shared layer" end
            if grew > 200 then return "warn", "layer grew by " .. grew .. " since load" end
            return "pass", commas(leak.last.t) .. " components on the shared layer, +" .. math.max(0, grew) .. " since load"
        end },
    { "Code", "no errors in this plugin's callbacks", "Live", "Open Error Log, fix each trace. Moderators run the plugin; errors read as broken.",
        function()
            if #errlog == 0 then return "pass", "no errors captured since load" end
            return "fail", #errlog .. " error(s) in the Error Log"
        end },
    { "Code", "every event subscription works", "Live", "Check event names against the Events docs.",
        function()
            local bad = 0
            for _, v in pairs(subs) do if v == false then bad = bad + 1 end end
            return bad == 0 and "pass" or "fail", bad == 0 and "all subscriptions succeeded" or (bad .. " subscription(s) failed")
        end },
    { "Code", "chat use declares chatAccess", "Live", "Add chatAccess to optionalPermissions, a permission tag and a Permissions paragraph.",
        function()
            if subs.ChatMessage ~= nil then return "warn", "ChatMessage is subscribed: needs chatAccess, tag and description" end
            return "pass", "ChatMessage not subscribed"
        end },
    { "Behaviour", "sends no actions or input to the game", "Live", "Remove anything that sends input, menu actions or commands (Prohibited).",
        function()
            if cmd and cmd.hist and #cmd.hist > 0 then return "warn", "Commands tab ran " .. #cmd.hist .. " console command(s) this session (user clicks only)" end
            return "warn", "Commands tab can send console commands on a click; flagged on JAGEX-CHECKLIST as a review risk"
        end },
    { "Behaviour", "frame cost stays small", "Live", "Refresh less often; cache rows; only lay out the visible tab.",
        function()
            if not perf.hasClock then return "warn", "os.clock missing: not measurable" end
            local c, s = perf.cost, 0
            if #c == 0 then return "warn", "no refresh timed yet" end
            for _, d in ipairs(c) do s = s + d end
            local ms = s / #c * 1000
            return ms < 4 and "pass" or "warn", fmt(ms, 2) .. " ms per refresh (advisory limit 4 ms; not an official number)"
        end },
    { "Code", "readable, commented, not obfuscated (AI policy)", "Script", "Comment intent; no load/loadstring/string.dump tricks or minified lines." },
    { "Code", "console commands, HTTP, chat, menu use flagged for review", "Script", "Explain each in the description; expect extra review." },
    { "Listing", "EULA statement word for word", "Script", "Paste the exact statement from the Submission process page." },
    { "Listing", "Email, Feedback and collaboration, Permissions, Data Protection sections", "Script", "Add each required section (Submission process page)." },
    { "Listing", "no angle brackets in the description; under 50,000 characters", "Script", "Remove the characters; shorten." },
    { "Listing", "summary 10-250 ASCII; listing image 16:9 at least 512 x 288", "Script", "Pass --summary and --logo to the script." },
    { "Listing", "mod.io file version matches plugin.json and is new", "Manual", "Bump version in plugin.json; enter the same on upload." },
    { "Listing", "contact email differs from your mod.io login email", "Manual", "Use a dedicated, forwarded address." },
    { "Listing", "all platforms ticked; submitted Hidden; permission tags added", "Manual", "Follow the upload form (Submission process, Step 4)." },
    { "Listing", "required dependency also set on mod.io; optional ones not", "Manual", "Match mod.io Dependencies to requiredDependencies." },
    { "Behaviour", "no automation, hidden or future info, combat prediction, click-zone changes", "Manual", "Compare every feature with the Prohibited list in the guidelines." },
    { "Behaviour", "no info exported about other players; not a copy of another plugin", "Manual", "Remove the feature; credit and ask permission." },
    { "Listing", "documentation clear to a brand new player", "Manual", "Rewrite the description step by step." },
}
local function subPanelRules(w)
    local rows = {}
    local n, off, zero = #w.flat, 0, 0
    local sw, sh = nil, helpers.screenH()
    pcall(function() sw = helpers.ensureHoverLayer().width end)
    for _, e in ipairs(w.flat) do
        if e.r and e.r.w == 0 and e.r.h == 0 then zero = zero + 1 end
        if e.r and sw and sh and (e.r.x + e.r.w < 0 or e.r.y + e.r.h < 0 or e.r.x > sw or e.r.y > sh) and not e.r.hidden then off = off + 1 end
    end
    rows[#rows + 1] = { "Layer", "panel share of the 4096 ID limit", "Live", "Reuse components instead of creating new ones each refresh.",
        function() local p = math.floor(n * 100 / 4096); return p < 25 and "pass" or "warn", n .. " components (" .. p .. "% of 4,096)" end }
    rows[#rows + 1] = { "Layer", "no shown components off screen", "Live", "Clamp the panel to the game window.",
        function() return off == 0 and "pass" or "warn", off .. " shown component(s) outside the window" end }
    rows[#rows + 1] = { "Layer", "panel inside the game window", "Live", "Clamp position on load and resize.",
        function()
            local r = w.r
            if r == nil or sw == nil or sh == nil then return "warn", "position not readable" end
            local inside = r.x >= 0 and r.y >= 0 and r.x + r.w <= sw and r.y + r.h <= sh
            return inside and "pass" or "warn", "at " .. r.x .. ", " .. r.y .. " size " .. r.w .. " x " .. r.h
        end }
    rows[#rows + 1] = { "Layer", "zero-size components (possible leftovers)", "Live", "Destroy unused components rather than shrinking them.",
        function() return zero < 20 and "pass" or "warn", zero .. " zero-size component(s)" end }
    rows[#rows + 1] = { "All", "files, manifest, code and listing", "Script", "This plugin's files cannot be read from inside the game." }
    rows[#rows + 1] = { "All", "behaviour and listing rules", "Manual", "See the rules under 'This plugin'." }
    return rows
end
local function subTargets()
    local L = { { name = PLUGIN_NAME .. " (this plugin)" } }
    for _, w in ipairs(plug.wins) do
        if not w.own then L[#L + 1] = { name = "Panel: " .. (w.title ~= "" and nice(w.title) or ("#" .. w.idx)), w = w } end
    end
    return L
end
local function viewSub()
    if plug.at == nil then pcall(plugScan) end
    local T = subTargets()
    if sub.target > #T then sub.target = 1 end
    local t = T[sub.target]
    local rules = t.w and subPanelRules(t.w) or SUB_RULES
    local rows, cnt = {}, { pass = 0, warn = 0, fail = 0, Script = 0, Manual = 0 }
    for _, r in ipairs(rules) do
        local res, why
        if r[3] == "Live" and r[5] then
            local ok, a, b = pcall(r[5])
            if ok then res, why = a, b else res, why = "warn", "check failed: " .. untag(a) end
            cnt[res] = (cnt[res] or 0) + 1
        else
            res = r[3]; why = r[3] == "Script" and "needs the files: run release/check_submission.py (command in Copy)" or "check by hand before upload"
            cnt[r[3]] = cnt[r[3]] + 1
        end
        local resC = res == "pass" and H.col(H.C_GOOD, "pass") or res == "fail" and H.col(H.C_BAD, "fail")
            or res == "warn" and H.col(H.C_WARN, "warn") or H.lbl(res == "Script" and "script" or "manual check")
        rows[#rows + 1] = { H.val(r[1]), H.val(r[2]), H.lbl(r[3]), resC, H.lbl(plain(why)),
            tip = r[2] .. ". " .. r[3] .. " check: " .. plain(why) .. ". Fix: " .. r[4], r = r, why = why, res = res }
    end
    return { cols = { { title = "Area", w = 64 }, { title = "Rule", flex = 3, min = 120 }, { title = "How", w = 52 },
            { title = "Result", w = 84 }, { title = "Reason", flex = 2, min = 80 } },
        data = arr(rows),
        onRow = function(i) sub.sel = rows[i]; tbl.selected = i end,
        detail = function()
            local s = sub.sel
            local head = H.gold(plain(t.name)) .. H.lbl("   live: ") .. H.col(H.C_GOOD, cnt.pass .. " pass ") .. H.col(H.C_WARN, cnt.warn .. " warn ")
                .. H.col(H.C_BAD, cnt.fail .. " fail") .. H.lbl("   script " .. cnt.Script .. ", manual " .. cnt.Manual)
            if s == nil then return { lines = { head, H.lbl("Click a rule for its reason and fix. Script rules: run the command in the Copy box on the plugin folder.") }, copy = SCRIPT_CMD } end
            local L = { head, H.val(plain(s.r[2])) }
            for _, l in ipairs(wrap("Reason: " .. plain(s.why), areaW() - 8, 2)) do L[#L + 1] = H.lbl(l) end
            for _, l in ipairs(wrap("Fix: " .. s.r[4], areaW() - 8, 2)) do L[#L + 1] = H.val(l) end
            return { lines = L, copy = s.r[3] == "Script" and SCRIPT_CMD or (s.r[2] .. ": " .. plain(s.why)) }
        end }
end

-------------------------------------------------------------------------------
-- 17. Resource Monitor (0.2.7)
--     Every performance value the plugin API exposes, sampled once a second
--     (every 50 logic ticks) into a rolling window and drawn as line graphs.
--     Sources (docs: Events page, Lua 5.4 manual):
--       Draw.timeDeltaSecs   -> FPS, frame time avg / worst per second
--       Logic events         -> logic ticks per second (target 50)
--       ServerLogic events   -> server tick interval (target 600 ms)
--       collectgarbage("count") -> this plugin's Lua heap (KB), if present
--       os.clock             -> this plugin's refresh and handler cost
--       shared plugin layer  -> component count vs the 4096 ID limit
--       Event counters       -> events per second
--       game.options         -> frame-rate caps and VSync (read only)
--     Not exposed by the API: GPU, process memory or CPU, other plugins'
--     timings, network ping, draw calls.
-------------------------------------------------------------------------------
local mon = { win = 60, set = 1, hist = {}, acc = { n = 0, sum = 0, worst = 0, logic = 0, srv = 0, srvGap = 0, srvN = 0, ev = 0, hcost = 0 },
    overhead = {}, drawn = nil, hasGC = false }
pcall(function() mon.hasGC = type(collectgarbage) == "function" and type(collectgarbage("count")) == "number" end)
-- { key, label, unit, decimals, source, tip }
local MON_METRICS = {
    { "fps", "FPS", "", 1, "Draw.timeDeltaSecs", "Frames drawn per second: 1 / average frame time over the last second." },
    { "ft", "Frame time avg", "ms", 2, "Draw.timeDeltaSecs", "Average time between Draw events in the last second." },
    { "ftmax", "Frame time worst", "ms", 1, "Draw.timeDeltaSecs", "Longest single frame in the last second: stutters show here." },
    { "logic", "Logic ticks / s", "", 1, "Event.Logic", "Logic events counted in the last second of Draw time. The client targets 50." },
    { "srv", "Server tick interval", "ms", 0, "Event.ServerLogic", "Average gap between ServerLogic events (game tick, target 600 ms). Not network ping." },
    { "mem", "Lua heap (this plugin)", "KB", 0, "collectgarbage('count')", "Memory used by this plugin's Lua state. Other plugins are separate and not visible." },
    { "cost", "Refresh cost (this plugin)", "ms", 2, "os.clock", "Average CPU time of this panel's refresh in the last second." },
    { "hcost", "Event handler cost (this plugin)", "ms/s", 2, "os.clock", "CPU time spent in this plugin's own Draw/Logic monitor code per second." },
    { "layer", "Plugin layer components", "", 0, "ui layer walk", "Components on the shared plugin layer (all plugins), against the 4096 ID limit." },
    { "own", "This plugin's components", "", 0, "own registry", "Components this plugin created." },
    { "evs", "Events / s (non-tick)", "", 0, "Event counters", "Events other than Logic, ServerLogic and Draw per second: entity, inventory, var changes." },
    { "ovh", "Monitor overhead", "ms", 3, "os.clock", "CPU time this tab's own sampling took last second (graphs drawn separately)." },
}
local MON_IDX = {}
for i, m in ipairs(MON_METRICS) do MON_IDX[m[1]] = i end
local MON_SETS = {
    { name = "Frames", keys = { "fps", "ftmax" } },
    { name = "Ticks", keys = { "logic", "srv" } },
    { name = "Memory", keys = { "mem", "layer" } },
    { name = "Cost", keys = { "cost", "hcost" } },
}
local MON_MAXWIN = 120
local GR_H = 52
local gr = { }   -- graph pieces, built in buildPanel
-- per-frame accumulation (called from the existing Draw handler; a few adds)
local function monDraw(dt)
    local a = mon.acc
    a.n = a.n + 1; a.sum = a.sum + dt
    if dt > a.worst then a.worst = dt end
end
local function monServer(gap) local a = mon.acc; a.srvGap = a.srvGap + gap; a.srvN = a.srvN + 1 end
local lastEvTotal = 0
local function monSample()
    local t0 = nil
    if perf.hasClock then pcall(function() t0 = os.clock() end) end
    local a, s = mon.acc, {}
    if a.n > 0 then s.fps = a.n / a.sum; s.ft = a.sum / a.n * 1000; s.ftmax = a.worst * 1000; s.logic = 50 / a.sum end
    if a.srvN > 0 then s.srv = a.srvGap / a.srvN * 1000 end
    if mon.hasGC then pcall(function() s.mem = collectgarbage("count") end) end
    if perf.hasClock then
        local c, cs, cn = perf.cost, 0, 0
        for i = math.max(1, #c - 4), #c do cs = cs + c[i]; cn = cn + 1 end
        if cn > 0 then s.cost = cs / cn * 1000 end
        s.hcost = a.hcost * 1000
    end
    if leak.last then s.layer = leak.last.t end
    s.own = #reg
    local tot = 0
    for k, v in pairs(ev.counts) do if not TICKY[k] then tot = tot + v end end
    s.evs = math.max(0, tot - lastEvTotal); lastEvTotal = tot
    s.ovh = mon.lastOvh
    local h = mon.hist
    h[#h + 1] = s
    if #h > MON_MAXWIN then table.remove(h, 1) end
    mon.acc = { n = 0, sum = 0, worst = 0, srvGap = 0, srvN = 0, hcost = 0 }
    if t0 then pcall(function() mon.lastOvh = (os.clock() - t0) * 1000 end) end
end
local function monStats(key)
    local h, mn, mx, sum, n = mon.hist, nil, nil, 0, 0
    for i = math.max(1, #h - mon.win + 1), #h do
        local v = h[i][key]
        if type(v) == "number" then n = n + 1; sum = sum + v; mn = (mn == nil or v < mn) and v or mn; mx = (mx == nil or v > mx) and v or mx end
    end
    local cur = #h > 0 and h[#h][key] or nil
    return cur, mn, n > 0 and sum / n or nil, mx, n
end
local function mfmt(m, v) if type(v) ~= "number" then return "-" end; return fmt(v, m[4]) .. (m[3] ~= "" and (" " .. m[3]) or "") end
local function placeGraphs(y)
    local show = state.tab == NT.T_RES and y ~= nil and gr.bg ~= nil
    if not show and mon.drawn == "hidden" then return 0 end   -- already hidden: no work
    for g = 1, 2 do
        local G = gr[g]
        if G then helpers.setHidden({ G.bg, G.title, G.ymax, G.ymin, G.x0, G.x1, G.mid }, not show)
            if not show then for i = 1, MON_MAXWIN do helpers.setHidden({ G.seg[i] }, true) end end
        end
    end
    if not show then mon.drawn = gr.bg and "hidden" or nil; return 0 end
    local w = areaW()
    local set = MON_SETS[mon.set]
    local AX = 40   -- room for the y-axis labels
    local key = mon.set .. ":" .. #mon.hist .. ":" .. y .. ":" .. w .. ":" .. mon.win .. ":" .. tostring(mon.hist[#mon.hist])
    local total = 2 * (GR_H + H.ROW_HEIGHT + 18)
    if mon.drawn == key then return total end
    mon.drawn = key
    for g = 1, 2 do
        local G, m = gr[g], MON_METRICS[MON_IDX[set.keys[g]]]
        local gy = y + (g - 1) * (GR_H + H.ROW_HEIGHT + 18)
        local cur, mn, avg, mx = monStats(m[1])
        helpers.safe(function() G.title:SetPos(H.PAD, gy); G.title:SetSize(w, H.ROW_HEIGHT) end)
        helpers.setText(G.title, H.gold(m[2]) .. H.lbl("  now ") .. H.val(mfmt(m, cur)) .. H.lbl("  min ") .. H.val(mfmt(m, mn))
            .. H.lbl("  avg ") .. H.val(mfmt(m, avg)) .. H.lbl("  max ") .. H.val(mfmt(m, mx)))
        helpers.setTip(G.title, m[6] .. " Source: " .. m[5] .. ".")
        local top = gy + H.ROW_HEIGHT
        local gw = w - AX
        helpers.safe(function() G.bg:SetPos(H.PAD + AX, top); G.bg:SetSize(gw, GR_H); G.mid:SetPos(H.PAD + AX, top + math.floor(GR_H / 2)); G.mid:SetSize(gw, 1) end)
        -- y range: padded min..max of the window so small changes stay visible
        local lo, hi = mn or 0, mx or 1
        if hi - lo < 1e-6 then lo, hi = lo - 1, hi + 1 end
        local pad = (hi - lo) * 0.1; lo, hi = math.max(0, lo - pad), hi + pad
        helpers.safe(function()
            G.ymax:SetPos(H.PAD, top - 4); G.ymax:SetSize(AX - 2, H.ROW_HEIGHT)
            G.ymin:SetPos(H.PAD, top + GR_H - H.ROW_HEIGHT + 4); G.ymin:SetSize(AX - 2, H.ROW_HEIGHT)
            G.x0:SetPos(H.PAD + AX, top + GR_H); G.x0:SetSize(80, 16)
            G.x1:SetPos(H.PAD + AX + gw - 30, top + GR_H); G.x1:SetSize(30, 16)
        end)
        helpers.setText(G.ymax, H.lbl(fmt(hi, hi < 10 and 1 or 0)))
        helpers.setText(G.ymin, H.lbl(fmt(lo, hi < 10 and 1 or 0)))
        helpers.setText(G.x0, H.lbl("-" .. mon.win .. " s"))
        helpers.setText(G.x1, H.lbl("now"))
        -- line: one column per sample; a 2 px segment from the previous value
        -- to this one, so the trace is continuous
        local h = mon.hist
        local first = math.max(1, #h - mon.win + 1)
        local step = gw / math.max(1, mon.win - 1)
        local prevY = nil
        for i = 1, MON_MAXWIN do
            local idx = first + i - 1
            local v = i <= mon.win and h[idx] and h[idx][m[1]] or nil
            local seg = G.seg[i]
            if type(v) ~= "number" then helpers.setHidden({ seg }, true); prevY = nil
            else
                local py = top + GR_H - 1 - math.floor((v - lo) / (hi - lo) * (GR_H - 2))
                local slot = mon.win - (#h - idx) - 1  -- right-aligned: newest at "now"
                local px = H.PAD + AX + math.floor(slot * step)
                local y1, y2 = py, prevY or py
                if y2 < y1 then y1, y2 = y2, y1 end
                helpers.safe(function() seg.hidden = false; seg:SetPos(px, y1); seg:SetSize(2, y2 - y1 + 2) end)
                prevY = py
            end
        end
    end
    return total
end
local function viewRes()
    local rows = {}
    for _, m in ipairs(MON_METRICS) do
        local cur, mn, avg, mx, n = monStats(m[1])
        local na = n == 0
        local why = nil
        if na then
            if (m[5] == "os.clock") and not perf.hasClock then why = "os.clock missing"
            elseif m[1] == "mem" and not mon.hasGC then why = "collectgarbage missing"
            elseif m[1] == "layer" then why = "layer not readable"
            else why = "waiting" end
        end
        local graphed = false
        for _, st in ipairs(MON_SETS) do for _, k in ipairs(st.keys) do if k == m[1] then graphed = st.name end end end
        rows[#rows + 1] = { H.val(m[2]), na and H.lbl(why) or H.val(mfmt(m, cur)), H.lbl(mfmt(m, mn)), H.lbl(mfmt(m, avg)), H.lbl(mfmt(m, mx)),
            H.lbl(m[5]), tip = m[6] .. " Source: " .. m[5] .. "." .. (graphed and (" Graphed in the " .. graphed .. " set.") or " Table only.") }
    end
    -- read-only client settings that cap performance
    for _, o in ipairs({ "MaxForegroundFps", "MaxBackgroundFps", "VSync" }) do
        local v = nil
        pcall(function() v = game.options[o].setting end)
        rows[#rows + 1] = { H.val("game.options." .. o), H.val(v ~= nil and tostring(v) or "-"), H.lbl(""), H.lbl(""), H.lbl(""), H.lbl("game.options (read)"),
            tip = "Client setting that caps or syncs the frame rate; read only, never changed." }
    end
    for _, s in ipairs({ { "GPU / process memory / CPU", "no API" }, { "Network ping", "no API" }, { "Other plugins' timings", "no API" }, { "Draw calls", "no API" } }) do
        rows[#rows + 1] = { H.lbl(s[1]), H.col(H.C_WARN, "not available"), H.lbl(""), H.lbl(""), H.lbl(""), H.lbl(s[2]),
            tip = "The plugin API exposes no way to read this, so it is not shown rather than guessed." }
    end
    return { cols = { { title = "Metric", flex = 2, min = 110 }, { title = "Now", w = 70 }, { title = "Min", w = 60 }, { title = "Avg", w = 60 },
            { title = "Max", w = 60 }, { title = "Source", flex = 1, min = 70 } },
        data = arr(rows),
        detail = function()
            local o = mon.lastOvh
            return { lines = { H.lbl("Sampled once a second over the last " .. mon.win .. " s (" .. #mon.hist .. " samples). Monitor overhead: ")
                .. H.val(o and (fmt(o, 3) .. " ms/s") or "-") .. H.lbl(", graphs redrawn once a second only while this tab is open.") } }
        end }
end

NT.sub = sub
NT.subTargets = subTargets
NT.viewSub = viewSub
NT.mon = mon
NT.MON_SETS = MON_SETS
NT.MON_MAXWIN = MON_MAXWIN
NT.gr = gr
NT.monDraw = monDraw
NT.monServer = monServer
NT.monSample = monSample
NT.placeGraphs = placeGraphs
NT.viewRes = viewRes
end)()
NT.hook.draw = NT.monDraw
NT.hook.server = NT.monServer
NT.hook.cost = function(d) NT.mon.acc.hcost = (NT.mon.acc.hcost or 0) + d end

do
-------------------------------------------------------------------------------
-- 18. World Render (0.2.14): client-side debug markers (ported from Rotten
-- Potato). Entity hiding is included. All off on load (not saved) and
-- switched off in PluginShutdown. Nothing is sent to the game.
-------------------------------------------------------------------------------
NT.WR = { hideNpcs = false, hidePlayers = false, aura = false, trail = false, beam = false, col = 1, rad = 2,
    pts = {}, acc = 0, myUid = nil, hidden = 0, drawOk = false, entOk = false }
local WR = NT.WR
WR.COLS = { { "Green", 0x55FF33FF }, { "Purple", 0xAA44FFFF }, { "Gold", 0xFFCC33FF }, { "Red", 0xFF3322FF }, { "Cyan", 0x33DDFFFF }, { "White", 0xFFFFFFFF } }
WR.RADS = { 200, 400, 800, 1600, 3200 }
local function wrV3(x, y, z) return Vector3.new(x, y, z) end
local function wrRing(c, r, n)
    local pts = {}
    for i = 0, n do local a = (i / n) * 2 * math.pi; pts[#pts + 1] = wrV3(c.x + math.cos(a) * r, c.y, c.z + math.sin(a) * r) end
    return pts
end
if _RDT_UNL then
    WR.entOk = pcall(function()
        Event.EntityDraw.Subscribe("rdtWorldEntity", function(ev)
            if not (WR.hideNpcs or WR.hidePlayers) then return true end
            local keep = true
            pcall(function()
                local t = ev.entityType
                if t == EntityType.PLAYER and WR.hidePlayers then
                    if WR.myUid == nil or ev.playerEntity.uid ~= WR.myUid then keep = false end
                elseif t == EntityType.NPC and WR.hideNpcs then keep = false end
            end)
            if not keep then WR.hidden = WR.hidden + 1 end
            return keep
        end)
    end)
end
local function wrDraw(ev)
    if not (WR.aura or WR.trail or WR.beam or WR.hidePlayers) then if #WR.pts > 0 then WR.pts = {} end; return end
    local e, pos = nil, nil
    pcall(function() if Player.IsAvailable() then e = Player.GetEntity() end end)
    if e == nil or helpers.offGame then return end
    pcall(function() WR.myUid = e.uid; pos = e.position end)
    if pos == nil then return end
    local dt = 0.02
    pcall(function() dt = ev.timeDeltaSecs or 0.02 end)
    local col = WR.COLS[WR.col][2]
    if WR.aura then
        pcall(function()
            local c, r = wrV3(pos.x, pos.y + 4, pos.z), WR.RADS[WR.rad]
            ShapeList.DrawLine({ positions = wrRing(c, r, 32), colour = col, lineWidth = 3.0, ignoreDepth = false })
            ShapeList.DrawLine({ positions = wrRing(c, 256, 16), colour = col, lineWidth = 2.0, ignoreDepth = false })
        end)
    end
    if WR.trail then
        WR.acc = WR.acc + dt
        if WR.acc > 0.15 then
            WR.acc = 0
            local last = WR.pts[#WR.pts]
            if last == nil or math.abs(last.x - pos.x) + math.abs(last.z - pos.z) > 32 then
                WR.pts[#WR.pts + 1] = wrV3(pos.x, pos.y + 20, pos.z)
                if #WR.pts > 60 then table.remove(WR.pts, 1) end
            end
        end
        if #WR.pts >= 2 then pcall(function() ShapeList.DrawLine({ positions = WR.pts, colour = col, lineWidth = 4.0 }) end) end
    elseif #WR.pts > 0 then WR.pts = {} end
    if WR.beam then
        pcall(function() ShapeList.DrawLine({ positions = { wrV3(pos.x, pos.y, pos.z), wrV3(pos.x, pos.y + 6000, pos.z) }, colour = col, lineWidth = 6.0 }) end)
    end
end
WR.drawOk = pcall(function() Event.Draw.Subscribe("rdtWorldDraw", function(ev) pcall(wrDraw, ev) end) end)
function WR.off() WR.hideNpcs, WR.hidePlayers, WR.aura, WR.trail, WR.beam, WR.pts = false, false, false, false, false, {} end
function WR.shutdown()
    WR.off()
    pcall(function() Event.EntityDraw.Unsubscribe("rdtWorldEntity") end)
    pcall(function() Event.Draw.Unsubscribe("rdtWorldDraw") end)
    pcall(function() Event.MiniMenuReady.Unsubscribe("rdtHoverReady"); helpers.worldHover = nil end)
end
local function onOff(v) return v and H.col(H.C_GOOD, "On") or H.lbl("Off") end
NT.viewWorld = function()
    local rows = {}
    if _RDT_UNL then
        rows[#rows + 1] = { H.val("Hide NPCs"), onOff(WR.hideNpcs), H.lbl("EntityDraw returns false for NPCs; they still exist."), tip = "Client-side only: NPCs are not drawn on your screen." }
        rows[#rows + 1] = { H.val("Hide other players"), onOff(WR.hidePlayers), H.lbl("Your own character stays visible."), tip = "Client-side only: other players are not drawn on your screen." }
        rows[#rows + 1] = { H.val("Entities skipped"), H.lbl(commas(WR.hidden)), H.lbl("draw calls skipped since load") }
    end
    rows[#rows + 1] = { H.val("Position ring"), onOff(WR.aura), H.lbl("radius " .. WR.RADS[WR.rad] .. " units (512 = 1 tile) plus a half-tile ring"), tip = "Debug marker for your world position and a distance radius (ShapeList.DrawLine)." }
    rows[#rows + 1] = { H.val("Path trail"), onOff(WR.trail), H.lbl(#WR.pts .. " of 60 points, one per 0.15 s while moving"), tip = "Debug marker for pathing: a line through where you walked." }
    rows[#rows + 1] = { H.val("Sky beam"), onOff(WR.beam), H.lbl("vertical line above your position"), tip = "Debug marker that shows where you are from far away." }
    rows[#rows + 1] = { H.val("APIs"), H.lbl(WR.drawOk and "Draw ok" or "Draw missing"), H.lbl("All off on load and unload. Nothing is sent to the game.") }
    return { cols = { { title = "Option", flex = 2, min = 100 }, { title = "State", w = 60 }, { title = "Note", flex = 3, min = 80 } }, data = arr(rows) }
end

-------------------------------------------------------------------------------
-- 19. Probe: walks every global table, lists all members
-- with their type (documented or not). "Call ()" runs a selected function
-- with no arguments after a Confirm click and shows what it returned.
-------------------------------------------------------------------------------
end
do
NT.PR = { rows = nil, sel = nil, out = "", pending = nil, filter = "" }
local PR = NT.PR
local function prScan()
    local rows = {}
    local names = {}
    for k, v in pairs(_G) do if type(k) == "string" then names[#names + 1] = k end end
    table.sort(names)
    for _, k in ipairs(names) do
        local v = _G[k]
        local tv = type(v)
        if tv == "table" or tv == "userdata" then
            local ok = pcall(function()
                local m = {}
                for k2, v2 in pairs(v) do if type(k2) == "string" then m[#m + 1] = { k2, type(v2) } end end
                table.sort(m, function(a, b) return a[1] < b[1] end)
                for _, e in ipairs(m) do rows[#rows + 1] = { k .. "." .. e[1], e[2], path = { k, e[1] } } end
            end)
            if not ok then rows[#rows + 1] = { k, tv .. " (not iterable)", path = { k } } end
        else rows[#rows + 1] = { k, tv, path = { k } } end
    end
    PR.rows = rows
end
local function prGet(path) local v = _G; for _, p in ipairs(path) do v = v[p] end; return v end
function PR.call(path)
    local ok, r = pcall(function()
        local f = prGet(path)
        local res = table.pack(f())
        local out = {}
        for i = 1, res.n do out[#out + 1] = tostring(res[i]) end
        return #out > 0 and table.concat(out, ", ") or "(no return value)"
    end)
    PR.out = (ok and "Returned: " or "Error: ") .. tostring(r)
end
NT.viewProbe = function()
    if PR.rows == nil then pcall(prScan) end
    local f = PR.filter:lower()
    local list = {}
    for _, r in ipairs(PR.rows or {}) do
        if f == "" or r[1]:lower():find(f, 1, true) then list[#list + 1] = r end
    end
    return { cols = { { title = "Name", flex = 3, min = 120 }, { title = "Type", w = 90 } },
        data = { count = #list, get = function(i) local r = list[i]; return { H.val(r[1]), H.lbl(r[2]) } end },
        onRow = function(i) PR.sel = list[i]; PR.out = "" end,
        detail = function()
            local s = PR.sel
            if not s then return { lines = { H.lbl(#list .. " members. Pick a row; functions can be called with no arguments (Call, then Confirm).") } } end
            return { lines = { H.val(s[1]) .. H.lbl("  (" .. s[2] .. ")"), H.lbl(PR.pending and "Press Confirm to call it with no arguments." or (PR.out ~= "" and PR.out or "")) } }
        end }
end

end

-------------------------------------------------------------------------------
-- 0.3.0: tabs that live in their own module files (rdt_mods.lua lists them).
-- Each module returns { name, cat, view, build(ui), tick, shutdown, onEvent }.
-------------------------------------------------------------------------------
NT.ctx = { H = H, helpers = helpers, arr = arr, kv = kv, commas = commas, fmt = fmt, plain = plain, untag = untag,
    secs = secs, unl = _RDT_UNL, PLUGIN_NAME = PLUGIN_NAME, SLUG = SLUG, logError = logError, perf = perf,
    readField = readField, refresh = function() refresh() end, root = function() return root end,
    cmdRun = function(t, c) NT.cmdRun(t, c) end, needsConfirm = function(t) return NT.needsConfirm(t) end,
    cmdFn = function() return NT.cmdFn() end, cmd = NT.cmd, ticks = function() return ticks end,
    reg = reg, tbl = function() return tbl end, VERSION = H.VERSION, EVENTS = EVENTS, ev = ev }
NT.mods = {}
pcall(function()
    local list = require("rdt_mods")
    for _, m in ipairs(list(NT.ctx)) do
        if type(m) == "table" and m.name and m.view then
            TABS[#TABS + 1] = m.name
            m.tab = #TABS
            NT.mods[#NT.mods + 1] = m
            for _, c in ipairs(CATG.CATS) do if c.name == (m.cat or "Debug") then c.tabs[#c.tabs + 1] = m.tab end end
        end
    end
end)
_RDT_HOOK.event = function(name, e) for _, m in ipairs(NT.mods) do if m.onEvent then pcall(m.onEvent, name, e) end end end
local VIEWS = { viewUI, viewPlug, viewEvents, viewBrowse, viewAudio, viewSettings, viewPerf, viewGrid, viewFit, viewReload, viewFaq,
    viewDiag, viewErrors, viewApi, viewCmd, NT.viewSub, NT.viewRes, NT.viewWorld, NT.viewProbe }
for _, m in ipairs(NT.mods) do VIEWS[m.tab] = function() return m.view(state.tab == m.tab) end end
local JUMPS = {}   -- 0.2.6: every tab gets the full pager

-------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------
local PREV = 64   -- review: 64px preview
local lastCopy = nil
local pages = {}
local function flow(items, y, gap)
    local avail = areaW()
    local x = 0
    for _, it in ipairs(items) do
        if x > 0 and x + it.w > avail then x = 0; y = y + H.BTN_H + gap end
        it.x, it.y = H.PAD + x, y
        helpers.safe(function() it.c:SetPos(it.x, it.y) end)
        x = x + it.w + gap
    end
    return y + H.BTN_H + 6
end

layout = function()
    if root == nil then return end
    local t0 = nil
    if perf.hasClock then pcall(function() t0 = os.clock() end) end
    local y = H.PAD + helpers.TITLE_HEIGHT + 4
    -- 0.2.6: category row, then the current category's tabs (filled highlight)
    do
        local ci = CATG.of(state.tab)
        y = flow(CATG.catBtns, y, 4) - 6 + 4
        local a = CATG.catBtns[ci]
        helpers.safe(function() CATG.catHi:SetPos(a.x - 2, a.y - 2); CATG.catHi:SetSize(a.w + 4, H.BTN_H + 4); CATG.catTint:SetPos(a.x, a.y); CATG.catTint:SetSize(a.w, H.BTN_H) end)
        local list = {}
        for i2, b in ipairs(tabBtns) do
            local show = CATG.of(i2) == ci
            helpers.setHidden({ b.c }, not show)
            if show then list[#list + 1] = b end
        end
        y = flow(list, y, 4) - 6 + 2
    end
    local a = tabBtns[state.tab]
    helpers.safe(function() tabHi:SetPos(a.x - 2, a.y - 2); tabHi:SetSize(a.w + 4, H.BTN_H + 4); CATG.tabTint:SetPos(a.x, a.y); CATG.tabTint:SetSize(a.w, H.BTN_H) end)
    helpers.safe(function() detail.div:SetPos(H.PAD, y - 2); detail.div:SetSize(areaW(), 1) end)
    y = y + 4
    local vis = {}
    for t, list in pairs(ctrls) do
        for _, it in ipairs(list) do
            local show = t == state.tab and (it.show == nil or it.show())
            helpers.setHidden({ it.c }, not show)
            if show then vis[#vis + 1] = it end
            if show and t == T_CMD and type(it.c) == "table" and rawget(it.c, "refresh") then pcall(it.c.refresh, it.c) end
        end
    end
    if #vis > 0 then y = flow(vis, y, 6) end
    -- the tab's table and detail view
    local ok, v = guarded("view " .. TABS[state.tab], VIEWS[state.tab])
    if not ok or type(v) ~= "table" then v = { cols = { { title = "Error", flex = 1 } }, data = arr({ { H.col(H.C_BAD, "this tab failed; see Error Log") } }) } end
    if v.data and v.data.get and not v.data.tipped then
        local get = v.data.get
        v.data.get = function(i)
            local r = get(i)
            if type(r) == "table" and r.tip == nil and r.tips == nil then
                r.tip = TIPS.rows[untag(r[1])] or TIPS.rows[untag(r[2] or "")]
                if r.tip == nil and state.tab == T_SET and setMode == "client" then
                    r.tip = "game.options." .. untag(r[1]) .. ": a client setting, read only. Value is its current setting number; Range is the lowest and highest it accepts."
                end
            end
            return r
        end
        v.data.tipped = true
    end
    tbl.keyPrefix = TABS[state.tab] .. (v.key and ("/" .. v.key) or "")
    tbl:setColumns(v.cols, v.data, v.onRow, v.icon)
    tbl.emptyMsg = v.empty or "Nothing to show"
    local d = nil
    if v.detail then local okd, dd = guarded("detail " .. TABS[state.tab], v.detail); if okd then d = dd end end
    local lineX, top = H.PAD, y
    local pv = d and d.preview
    helpers.safe(function() detail.box.hidden = pv == nil; detail.spr.hidden = true; detail.obj.hidden = true end)
    if pv then
        helpers.safe(function()
            detail.box:SetPos(H.PAD, y); detail.box:SetSize(PREV + 8, PREV + 8)
            local s = pv.item and detail.obj or detail.spr
            if pv.item then s:SetAssociatedObject(pv.id) else s.sprite = pv.spr end
            s:SetPos(H.PAD + 4, y + 4); s:SetSize(PREV, PREV); s.hidden = false
        end)
        lineX = H.PAD + PREV + 16
    end
    local n = 0
    for i = 1, DETAIL_N do
        local s = d and d.lines and d.lines[i]
        helpers.setHidden({ detail.lines[i] }, s == nil)
        if s then
            n = i
            helpers.safe(function() detail.lines[i]:SetPos(lineX, y + (i - 1) * H.ROW_HEIGHT); detail.lines[i]:SetSize(areaW() - (lineX - H.PAD), H.ROW_HEIGHT) end)
            helpers.setText(detail.lines[i], s)
        end
    end
    y = y + n * H.ROW_HEIGHT
    -- copy row: full width under the detail (and under the preview), same
    -- left edge and height as the controls and table, never above the tab bar
    if pv then y = math.max(y, top + PREV + 8) end
    local hasCopy = d ~= nil and d.copy ~= nil
    local c = hasCopy and helpers.cleanText(d.copy, 1000) or nil
    if c ~= lastCopy then lastCopy = c; detail.editing = false end
    helpers.setHidden({ detail.copyLbl, detail.copyBg, detail.copySel }, not hasCopy)
    helpers.setHidden({ detail.copy }, not (hasCopy and detail.editing))
    helpers.setHidden({ detail.copyShow }, not (hasCopy and not detail.editing))
    if hasCopy then
        local cy = math.max(y + 2, top)
        local fw = math.max(60, areaW() - 44 - 60)
        helpers.safe(function()
            detail.copyLbl:SetPos(H.PAD, cy)
            detail.copyBg:SetPos(H.PAD + 44, cy); detail.copyBg:SetSize(fw, H.BTN_H)
            detail.copyShow:SetPos(H.PAD + 44, cy); detail.copyShow:SetSize(fw, H.BTN_H)
            detail.copy:SetPos(H.PAD + 44, cy); detail.copy:SetSize(fw, H.BTN_H)
            detail.copySel:SetPos(H.PAD + 44 + fw + 4, cy)
        end)
        helpers.setText(detail.copyShow, H.val(c))
        helpers.setText(detail.copySel, detail.editing and "Done" or "Select", "label")
        pcall(function() if detail.copy.content ~= c then detail.copy.content = c end end)
        y = cy + H.BTN_H + 4
    end
    helpers.setHidden({ NT.moreBtn }, not (d ~= nil and d.more))
    if d ~= nil and d.more then
        local my = math.max(y + 2, top)
        helpers.safe(function() NT.moreBtn:SetPos(H.PAD, my) end)
        y = my + H.BTN_H + 4
    end
    if n > 0 or pv or hasCopy then y = y + 6 end
    if state.tab == T_GRID then placeGrid(y); y = y + GRID_H + 6 else placeGrid(nil) end
    if state.tab == T_FIT then placeFit(y); y = y + H.ROW_HEIGHT + 10 else placeFit(nil) end
    if state.tab == NT.T_RES then y = y + NT.placeGraphs(y) + 4 else NT.placeGraphs(nil) end
    -- 0.2.6: never run off the screen: fewer rows per page when the panel
    -- would reach the bottom of the game window (Commands overflowed).
    do
        local sh, r = helpers.screenH(), helpers.panelRect()
        local rows = Table.ROWS
        if sh and r then
            local room = sh - r.y - y - (H.ROW_HEIGHT + 2) - (6 + H.BTN_H + 8) - helpers.GRIP_STRIP - H.PAD
            rows = math.max(4, math.min(Table.ROWS, math.floor(room / H.ROW_HEIGHT)))
        end
        if tbl.visRows ~= rows then tbl.visRows = rows; if tbl.page > tbl:pages() then tbl.page = tbl:pages() end end
    end
    y = tbl:place(y, H.PAD, areaW(), JUMPS[state.tab])
    if settingsUI ~= nil then
        settingsUI.open = state.editOpen == true
        y = settingsUI:place(y)
    end
    helpers.fitHeight(y)
    if t0 then
        pcall(function()
            local c = perf.cost; c[#c + 1] = os.clock() - t0
            if #c > 50 then table.remove(c, 1) end
        end)
    end
end
refresh = function() pcall(layout) end
Table.gloss = function(title)
    title = untag(title or "")
    return TIPS.tabcols[TABS[state.tab] .. "|" .. title] or TIPS.cols[title] or TIPS.cols[(title:gsub("%s*%d+$", ""))]
end

local function selectTab(i)
    pages[state.tab] = tbl.page
    cmd.more, cmd.valArg = false, nil   -- 0.3.0: Commands More info resets on tab switch
    state.tab = i; save()
    tbl.page = pages[i] or 1
    tbl.selected = nil
    layout(); helpers.refit()
end
-- 0.5.1: X in the title bar backs out of a sub-view (Edit/settings, Commands
-- More info / value list, Plugin Analyser window detail) instead of closing
-- the whole panel. Same steps as the Back buttons. ui_helpers pcalls this.
helpers.onCloseSub = function()
    if helpers.closeEditIfOpen() then return true end
    if state.tab == T_CMD and cmd ~= nil and cmd.more then
        if cmd.valArg then cmd.valArg = nil else cmd.more = false end
        tbl.page = 1; tbl.selected = nil; refresh(); return true
    end
    if state.tab == T_PLUG and plug.mode == "layer" and plug.open ~= nil then
        plug.open = nil; sel[T_PLUG] = nil; tbl.page = 1; refresh(); return true
    end
    return false
end

-------------------------------------------------------------------------------
-- Build
-------------------------------------------------------------------------------
local function rect(parent, r, g, b, a)
    local c = nil
    pcall(function() c = ui.Rectangle.new(parent); c.fill = true; c.colour = Vector4.new(r, g, b, a) end)
    return c
end
-- 0.2.13: option pickers are RuneScape-style dropdowns (helpers.dropdown).
-- options: list or function returning a list of labels; get/set use indexes.
local function ddCtrl(tab, w, options, get, set, show, name, tip, onChange)
    local d = helpers.dropdown(root, 0, 0, w, H.BTN_H, { options = options, get = get, set = set, name = name, tip = tip,
        onChange = function() if onChange then onChange() end; refresh() end })
    ctrls[tab] = ctrls[tab] or {}
    ctrls[tab][#ctrls[tab] + 1] = { c = d, w = w, show = show }
    R(name or "dropdown", "Dropdown", d.box)
    return d
end
local function cycleBtn(tab, labels, get, set, w)
    local names = {}
    for _, l in ipairs(labels) do names[#names + 1] = l[2] end
    local function idx() for i, l in ipairs(labels) do if l[1] == get() then return i end end; return 1 end
    return ddCtrl(tab, w + 18, names, idx, function(i) set(labels[i][1]) end, nil, "view " .. tab,
        "Switch view: " .. table.concat(names, ", ") .. ".", function() tbl.page = 1; tbl.selected = nil end)
end

local function buildPanel(w)
    root = w
    tabHi = R("tab highlight", "Rectangle", rect(root, 0x5A/255, 0x4A/255, 0x2A/255, 1.0))
    CATG.catHi = R("category highlight", "Rectangle", rect(root, 0x7A/255, 0x60/255, 0x2A/255, 1.0))
    for i, c in ipairs(CATG.CATS) do
        local bw = tw(c.name) + 22
        local b = helpers.button(root, 0, 0, bw, H.BTN_H, c.name, function()
            if CATG.of(state.tab) ~= i then selectTab(c.tabs[1]) end
        end)
        CATG.catBtns[i] = { c = b, w = bw }
        helpers.setTip(b, CATG.TIP[c.name])
        R("category " .. c.name, "Button", b)
    end
    for i, name in ipairs(TABS) do
        local bw = tw(name) + 16
        local b = helpers.button(root, 0, 0, bw, H.BTN_H, name, function() selectTab(i) end)
        tabBtns[i] = { c = b, w = bw }
        R("tab " .. name, "Button", b)
    end
    detail.div = R("divider", "Rectangle", rect(root, 0.78, 0.70, 0.52, 0.9))
    -- filled selected state: a click-through gold tint over the chosen buttons
    for _, k in ipairs({ "cat", "tab" }) do
        local t = rect(root, 0xE0/255, 0xB0/255, 0x40/255, 0.28)
        helpers.safe(function() t.clickthrough = true; t.enabled = false end)
        if k == "cat" then CATG.catTint = t else CATG.tabTint = t end
    end

    -- 1 UI Inspector
    cycleBtn(T_UI, { { "summary", "Summary" }, { "components", "Components" } }, function() return uiMode end, function(v) uiMode = v end, 96)
    local frzB
    frzB = btn(T_UI, "Freeze", 64, function() frozen = not frozen; setLabel(frzB, frozen and "Live" or "Freeze") end)
    -- 2 Plugin Analyser
    cycleBtn(T_PLUG, { { "layer", "Plugin layer" }, { "hooks", "Opt-in hooks" }, { "limits", "What is possible" } },
        function() return plug.mode end, function(v) plug.mode = v end, 124)
    btn(T_PLUG, "Scan", 52, function() plugScan(); plug.open = nil; refresh() end, function() return plug.mode == "layer" end)
    btn(T_PLUG, "Back", 52, function() plug.open = nil; sel[T_PLUG] = nil; tbl.page = 1; refresh() end, function() return plug.mode == "layer" and plug.open ~= nil end)
    -- 3 Events
    cycleBtn(T_EV, { { "counts", "Counts" }, { "recent", "Recent" } }, function() return evMode end, function(v) evMode = v end, 70)
    local pauseB
    pauseB = btn(T_EV, "Pause", 60, function() ev.paused = not ev.paused; setLabel(pauseB, ev.paused and "Resume" or "Pause") end)
    btn(T_EV, "Clear", 52, function() ev.counts, ev.last, ev.log, ev.since = {}, {}, {}, secs(); refresh() end)
    -- 4 Sprite Browser
    cycleBtn(T_BROWSE, { { "sprite", "Sprites" }, { "item", "Items" }, { "cursor", "Cursors" } },
        function() return state.set end, function(v) state.set = v; save(); sel[T_BROWSE] = nil; br.lastN = -1 end, 72)
    brLetter = ddCtrl(T_BROWSE, 100, function() local L = {}; for i, l in ipairs(LETTERS) do L[i] = "Letter: " .. l end; return L end,
        function() return br.letter end, function(i) br.letter = i end, nil, "letter",
        ctrlTip("Letter"), function() brFilter(); tbl:go(1) end)
    brSearch = field(T_BROWSE, 160, "Search name or id", "browser search")
    brIdField = field(T_BROWSE, 80, "Go to ID", "id jump")
    btn(T_BROWSE, "Go", 36, function() brGoId(helpers.cleanInt(readField(brIdField, 8), 0, 9999999) or 0); refresh() end)
    -- 0.5.0: Model Sandbox (rdt_sandbox.lua) spawns the picked item's 3D model in the game view
    btn(T_BROWSE, "Spawn on screen", 110, function() pcall(function() local e = sel[T_BROWSE]; if e and NT.ctx.sandbox then NT.ctx.sandbox.spawn("item", e.id, e.name) end end); refresh() end,
        function() return state.set == "item" and sel[T_BROWSE] ~= nil end)
    -- 0.5.4: Give pre-fills the Give by ID tab (rdt_give.lua) with the picked item
    btn(T_BROWSE, "Give", 44, function() pcall(function() local e = sel[T_BROWSE]; if e and NT.ctx.give then NT.ctx.give(e.id); for _, m in ipairs(NT.mods) do if m.name == "Give by ID" then state.tab = m.tab end end end end); refresh() end,
        function() return state.set == "item" and sel[T_BROWSE] ~= nil end, "Give by ID")
    btn(T_BROWSE, "Keypad", 60, function() br.pad = not br.pad; refresh() end)
    local function padShow() pcall(function() brIdField.content = br.padStr end) end
    for dgt = 0, 9 do
        btn(T_BROWSE, tostring(dgt), 26, function() if #br.padStr < 7 then br.padStr = br.padStr .. dgt; padShow() end end, function() return br.pad end)
    end
    btn(T_BROWSE, "Del", 40, function() br.padStr = string.sub(br.padStr, 1, -2); padShow() end, function() return br.pad end)
    btn(T_BROWSE, "Clear", 48, function() br.padStr = ""; padShow() end, function() return br.pad end)
    -- review: the ID -1000..+1000 row was dropped; Go to ID covers it.
    -- 5 Audio
    cycleBtn(T_AUDIO, { { "sounds", "Sounds" }, { "volumes", "Volumes" }, { "bus", "Bus test" } }, function() return snd.mode end, function(v) snd.mode = v end, 76)
    sndSearch = field(T_AUDIO, 160, "Search sound or id", "sound search", function() return snd.mode == "sounds" end)
    -- 0.2.6: Bus picker (replaces Vol: the client mutes volumes below 1.0)
    do
        local buses = CATG.busList()
        local okBus = false
        for _, b in ipairs(buses) do if b == state.bus then okBus = true end end
        if not okBus then state.bus = "MASTER" end
        volBtn = ddCtrl(T_AUDIO, 150, function() local L = {}; for i, b in ipairs(CATG.busList()) do L[i] = "Bus: " .. b end; return L end,
            function() for i, b in ipairs(CATG.busList()) do if b == state.bus then return i end end; return 1 end,
            function(i) local L = CATG.busList(); if L[i] then state.bus = L[i]; save() end end,
            function() return snd.mode == "sounds" end, "__bus")
        helpers.setTip(volBtn, function()
            return (CATG.BUS_TIP[state.bus] or (state.bus .. ": a mixer sub-bus from audio.AudioBus; it may be silent if the game routes nothing from it.")) ..
                " Pick one of the " .. #CATG.busList() .. " buses the API exposes. Sounds play at full volume on that bus; the game's sliders set the level."
        end)
    end
    btn(T_AUDIO, "Stop all", 68, function() sndStopAll(); refresh() end)
    -- 6 Settings
    cycleBtn(T_SET, { { "plugin", "This plugin" }, { "client", "Client options" } }, function() return setMode end, function(v) setMode = v end, 110)
    setField = field(T_SET, 170, "Filter keys and options", "settings filter")
    -- 7 Perf
    btn(T_PERF, "Reset", 52, function() perfReset(); refresh() end)
    -- 8 Grid
    do local L = {}; for i, v in ipairs(STEPS) do L[i] = "Grid " .. v end
        ddCtrl(T_GRID, 80, L, function() return state.gridStep end, function(i) state.gridStep = i; save() end, nil, "grid step",
            "Grid spacing in interface units.") end
    preview.gridBg = R("grid area", "Rectangle", rect(root, 0.11, 0.10, 0.09, 0.94))
    preview.gv, preview.gh = {}, {}
    for i = 1, MAXV do preview.gv[i] = rect(root, 0.66, 0.64, 0.60, 0.35) end
    for i = 1, MAXH do preview.gh[i] = rect(root, 0.66, 0.64, 0.60, 0.35) end
    preview.dot = R("grid cursor", "Rectangle", rect(root, 1.0, 0.8, 0.27, 1.0))
    helpers.safe(function() preview.dot:SetSize(5, 5); preview.dot.hidden = true end)
    -- 9 Text fit
    fitField = field(T_FIT, 180, "Text to measure", "fit text")
    loadFonts()
    do local L = {}; for i, v in ipairs(FIT_WS) do L[i] = "Box " .. v end
        fitWBtn = ddCtrl(T_FIT, 80, L, function() return state.fitW end, function(i) state.fitW = i; save() end, nil, "fit width",
            "Width of the test box in interface units.") end
    preview.fitBg = R("fit box", "Rectangle", rect(root, 0.11, 0.10, 0.09, 0.94))
    preview.fitT = R("fit text", "Text", newText(root, 100))
    -- 10 Reload
    slugField = field(T_RELOAD, 170, "Plugin folder (" .. SLUG .. ")", "slug")
    -- 11 FAQ
    faqField = field(T_FAQ, 200, "Search questions and answers", "faq search")
    -- 12 Diagnostics
    btn(T_DIAG, "Run", 44, function() diagRun(); refresh() end)
    -- 13 Error log
    btn(T_ERR, "Clear", 52, function() errlog = {}; sel[13] = nil; refresh() end)
    btn(T_ERR, "Test error", 80, function()
        guarded("Test error button", function() error("deliberate test error (checks that capture and traces work)") end); refresh()
    end)
    -- 14 API Explorer
    cycleBtn(T_API, { { "members", "Members" }, { "events", "Events" }, { "try", "Try calls" }, { "gaps", "Known gaps" } }, function() return api.mode end, function(v) api.mode = v end, 80)
    api.field = field(T_API, 170, "Filter names", "api filter", function() return api.mode == "members" end)
    btn(T_API, "Reread", 60, function() api.rows = nil; refresh() end, function() return api.mode == "members" end)

    -- Commands
    local function selArgs(n) return function() return cmd.mode == "list" and not cmd.more and cmd.sel ~= nil and #cmd.sel[2] >= n and not cmd.pool(cmd.sel) end end
    cycleBtn(T_CMD, { { "list", "All" }, { "history", "History" } }, function() return cmd.mode end, function(v) cmd.mode = v; cmd.more, cmd.valArg = false, nil end, 84)
    cmd.arg1 = field(T_CMD, 130, "Argument 1", "cmd arg1", selArgs(1))
    cmd.arg2 = field(T_CMD, 120, "Argument 2", "cmd arg2", selArgs(2))
    -- 0.3.0: one control set per argument (up to 6) for cheat commands
    for pos = 1, 6 do
        local sl = {}
        cmd.slots[pos] = sl
        local function on(kinds) return function()
            if cmd.mode ~= "list" or cmd.more or not cmd.pool(cmd.sel) then return false end
            local k = cmd.kind(cmd.sel, pos)
            return k ~= nil and kinds[k] == true
        end end
        local function argName() local i = cmd.info(cmd.sel); local a = i and i.args[pos]; return a and a.name or ("argument " .. pos) end
        sl.dd = ddCtrl(T_CMD, 150, function()
                local L = { "Arg " .. pos .. ": pick " .. argName() }
                if cmd.sel then for _, v in ipairs(cmd.valsOf(cmd.sel, pos)) do L[#L + 1] = cmd.label(v) end end
                return L
            end, function()
                local vals = cmd.sel and cmd.valsOf(cmd.sel, pos) or {}
                local cur = cmd.tokv[pos]
                for j, v in ipairs(vals) do if v[1] == cur then return j + 1 end end
                return 1
            end, function(i)
                local v = cmd.sel and cmd.valsOf(cmd.sel, pos)[i - 1]
                cmd.tokv[pos] = v and v[1] or nil
                if cmd.kind(cmd.sel, pos) == "ddtext" then pcall(function() sl.f.content = v and v[1] or "" end) end
            end, on({ dd = true, ddtext = true }), "cmd dd " .. pos,
            "Pick a value for this argument; the number or word goes into the command.")
        sl.f = field(T_CMD, 96, "Argument " .. pos, "cmd slot " .. pos, on({ num = true, text = true, ddtext = true }))
        helpers.setTip(sl.f, function()
            local i = cmd.info(cmd.sel); local a = i and i.args[pos]
            if a == nil then return nil end
            return "Argument " .. pos .. ": " .. a.name .. " (" .. a.type .. (a.required and ", required" or ", optional") .. (a.default ~= "" and (", default " .. a.default) or "") .. "). " .. a.meaning
        end)
        local function bump(d)
            local n = tonumber(readField(sl.f, 20)) or 0
            n = math.max(0, math.floor(n + d))
            pcall(function() sl.f.content = tostring(n) end)
            refresh()
        end
        local mb = btn(T_CMD, "-", 20, function() bump(-1) end, on({ num = true }), "__cmdminus" .. pos)
        helpers.setTip(mb, "One less.")
        local pb = btn(T_CMD, "+", 20, function() bump(1) end, on({ num = true }), "__cmdplus" .. pos)
        helpers.setTip(pb, "One more.")
    end
    cmd.valF = field(T_CMD, 120, "Filter values", "cmd valfilter", function() return cmd.more == true and cmd.valArg ~= nil end)
    helpers.setTip(cmd.valF, "Type part of a value or name to narrow the list.")
    cmd.runB = btn(T_CMD, cmdFn() and "Run" or "Run (unavailable)", cmdFn() and 44 or 120, function()
        if cmdFn() == nil then cmd.note = "ExecuteConsoleCommand is not available in this client; Run is disabled."; refresh(); return end
        local text, err = cmdBuild()
        if text then cmdRun(text) else cmd.note = err end
        refresh()
    end, function() return cmd.mode == "list" end, "Run command")
    cmd.free = field(T_CMD, 170, "Type any console command", "cmd free")
    btn(T_CMD, "Run text", 64, function()
        if cmdFn() == nil then cmd.note = "ExecuteConsoleCommand is not available in this client; Run is disabled."; refresh(); return end
        cmdRun(cleanCmd(readField(cmd.free, 160))); refresh()
    end)
    btn(T_CMD, "Confirm", 64, function() if cmd.pending then cmdRun(cmd.pending, true) end; refresh() end, function() return cmd.pending ~= nil end)
    btn(T_CMD, "Cancel", 56, function() cmd.pending = nil; cmd.note = "Cancelled."; refresh() end, function() return cmd.pending ~= nil end)
    btn(T_CMD, "Clear", 52, function() cmd.hist = {}; sel[T_CMD] = nil; refresh() end, function() return cmd.mode == "history" end)
    do local b = btn(T_CMD, "More info", 70, function() cmd.more = true; cmd.valArg = nil; tbl.page = 1; tbl.selected = nil; refresh() end,
            function() return cmd.mode == "list" and cmd.sel ~= nil and not cmd.more end, "__cmdmore")
        helpers.setTip(b, "Explain every argument of the picked command: order, type, required or optional, default, meaning, valid values and an example.")
        b = btn(T_CMD, "Back", 48, function() if cmd.valArg then cmd.valArg = nil else cmd.more = false end; tbl.page = 1; tbl.selected = nil; refresh() end, function() return cmd.more == true end, "__cmdback")
        helpers.setTip(b, "Back to the command list.") end

    -- 16 Submission Check: target picker (this plugin, or a panel from the layer scan)
    local subB
    subB = ddCtrl(NT.T_SUB, 200, function()
            local L = {}
            for i, t in ipairs(NT.subTargets()) do L[i] = "Target: " .. (i == 1 and "this plugin" or (tostring(t.name):gsub("^Panel: ", ""))) end
            return L
        end, function() return NT.sub.target end, function(i) NT.sub.target = i; NT.sub.sel = nil end, nil, "__subtarget",
        "Pick what to check. This plugin gets every rule; other plugins' panels (found by Rescan) only get the layer checks, because plugins cannot read each other's files.",
        function() tbl.page = 1 end)
    btn(NT.T_SUB, "Rescan", 60, function() pcall(plugScan); NT.sub.target = 1; NT.sub.sel = nil; subB:refresh(); refresh() end, nil, "__subrescan")
    helpers.setTip(ctrls[NT.T_SUB][#ctrls[NT.T_SUB]].c, "Scan the shared plugin layer again for other plugins' panels.")
    -- 17 Resource Monitor: graph set and window length (typed seconds, 10-120)
    local setB
    do local L = {}; for i, m in ipairs(NT.MON_SETS) do L[i] = "Graphs: " .. m.name end
    setB = ddCtrl(NT.T_RES, 136, L, function() return NT.mon.set end, function(i) NT.mon.set = i; NT.mon.drawn = nil end, nil, "__resset") end
    helpers.setTip(setB.box, "Which two values to graph: Frames (FPS, worst frame), Ticks (logic rate, server tick), Memory (Lua heap, layer components), Cost (refresh, Draw handler).")
    local WR, PR = NT.WR, NT.PR
    -- 18 World Render: On/Off dropdowns, marker colour and ring radius
    do
        local function tog(label, key, w, tip)
            return ddCtrl(NT.T_WORLD, w, { label .. ": Off", label .. ": On" }, function() return WR[key] and 2 or 1 end,
                function(i) WR[key] = i == 2 end, nil, "world " .. key, tip)
        end
        if _RDT_UNL then
            tog("Hide NPCs", "hideNpcs", 130, "Hide every NPC on your screen only. They still exist in the game.")
            tog("Hide players", "hidePlayers", 140, "Hide other players on your screen only. You stay visible.")
        end
        tog("Ring", "aura", 96, "Position ring: a circle around you at the chosen radius (debug marker).")
        tog("Trail", "trail", 96, "Path trail: a line along where you walked (debug marker).")
        tog("Beam", "beam", 96, "Sky beam: a vertical line above you (debug marker).")
        local cl, rl = {}, {}
        for i, c in ipairs(WR.COLS) do cl[i] = "Colour: " .. c[1] end
        for i, r in ipairs(WR.RADS) do rl[i] = "Radius: " .. r end
        ddCtrl(NT.T_WORLD, 120, cl, function() return WR.col end, function(i) WR.col = i end, nil, "world colour", "Colour of the ring, trail and beam.")
        ddCtrl(NT.T_WORLD, 120, rl, function() return WR.rad end, function(i) WR.rad = i end, nil, "world radius", "Ring radius in world units (512 = 1 tile).")
        btn(NT.T_WORLD, "All off", 64, function() WR.off(); refresh() end, nil, "__worldoff")
        helpers.setTip(ctrls[NT.T_WORLD][#ctrls[NT.T_WORLD]].c, "Turn every World Render option off.")
    end
    -- 19 Probe
    if _RDT_UNL then
        PR.field = field(NT.T_PROBE, 170, "Filter names", "probe filter")
        btn(NT.T_PROBE, "Rescan", 60, function() PR.rows = nil; refresh() end, nil, "__probescan")
        btn(NT.T_PROBE, "Call ()", 60, function()
            if PR.sel and PR.sel[2] == "function" then PR.pending = PR.sel.path end; refresh()
        end, function() return PR.sel ~= nil and PR.sel[2] == "function" end, "__probecall")
        btn(NT.T_PROBE, "Confirm", 64, function() if PR.pending then PR.call(PR.pending); PR.pending = nil end; refresh() end,
            function() return PR.pending ~= nil end, "__probeconfirm")
        btn(NT.T_PROBE, "Cancel", 56, function() PR.pending = nil; refresh() end, function() return PR.pending ~= nil end, "__probecancel")
    end
    NT.mon.field = field(NT.T_RES, 50, "60", "res window")
    helpers.setTip(NT.mon.field, "Graph window in seconds. Type a number from 10 to 120; it applies within a second.")
    btn(NT.T_RES, "Reset", 52, function() NT.mon.hist = {}; NT.mon.drawn = nil; refresh() end, nil, "__resreset")
    helpers.setTip(ctrls[NT.T_RES][#ctrls[NT.T_RES]].c, "Clear the sampled history.")
    for g = 1, 2 do
        local G = { seg = {} }
        G.bg = R("graph " .. g, "Rectangle", rect(root, 0.11, 0.10, 0.09, 0.94))
        G.mid = rect(root, 0.66, 0.64, 0.60, 0.25)
        G.title = newText(root, 200); G.ymax = newText(root, 38); G.ymin = newText(root, 38); G.x0 = newText(root, 60); G.x1 = newText(root, 30)
        for i = 1, NT.MON_MAXWIN do
            G.seg[i] = rect(root, g == 1 and 1.0 or 0.45, g == 1 and 0.78 or 0.80, g == 1 and 0.27 or 1.0, 1.0)
            helpers.safe(function() G.seg[i].hidden = true; G.seg[i].clickthrough = true end)
        end
        helpers.setHidden({ G.bg, G.mid, G.title, G.ymax, G.ymin, G.x0, G.x1 }, true)
        NT.gr[g] = G
    end
    NT.gr.bg = true

    -- detail view
    detail.box = R("preview box", "Rectangle", rect(root, 0.11, 0.10, 0.09, 0.94))
    pcall(function() detail.spr = ui.Sprite.new(root); detail.spr.hidden = true end)
    pcall(function() detail.obj = ui.Sprite.new(root); detail.obj.hidden = true end)
    R("large preview (sprite)", "Sprite", detail.spr); R("large preview (item)", "Sprite", detail.obj)
    detail.lines = {}
    for i = 1, DETAIL_N do
        detail.lines[i] = newText(root, 200)
        helpers.track(detail.lines[i], "content", 2)
        R("detail " .. i, "Text", detail.lines[i])
    end
    -- Copy row (0.2.1): created hidden (0.2.0 created the field visible at
    -- 0,0, on top of the title and tab bar, until the first layout). The
    -- row shows the text shortened with an ellipsis (full text in the hover
    -- box); Select swaps in a text box holding the full text for copying.
    detail.copyLbl = newText(root, 44)
    helpers.safe(function() detail.copyLbl:SetSize(44, H.BTN_H); detail.copyLbl.hidden = true end)
    helpers.setText(detail.copyLbl, H.lbl("Copy"))
    detail.copyShow = newText(root, 200)
    helpers.safe(function() detail.copyShow:SetSize(200, H.BTN_H); detail.copyShow.hidden = true end)
    helpers.track(detail.copyShow, "content", 6)
    helpers.setTip(detail.copyShow, TIPS.ctrl["copy show"])
    detail.copyBg = rect(root, 0.07, 0.06, 0.05, 0.9)
    helpers.safe(function() detail.copyBg.hidden = true; detail.copyBg:MoveToBack() end)
    detail.copy = helpers.input(root, 0, 0, 200, H.BTN_H, "")
    helpers.safe(function() detail.copy.hidden = true end)
    helpers.setTip(detail.copy, "Full copy-ready text: click, select all, copy. It goes back to the short view when you pick another row.")
    detail.copySel = helpers.button(root, 0, 0, 56, H.BTN_H, "Select", function() detail.editing = not detail.editing; refresh() end)
    NT.moreBtn = helpers.button(root, 0, 0, 84, H.BTN_H, "More info", function()
        if NT.faqList == nil then return end
        local ok = FaqDialog.open(NT.faqList, NT.faqIdx or 1)
        if not ok then logError("Help dialog", "could not open the conversation window") end
    end)
    pcall(function() helpers.setTip(NT.moreBtn, "Open the whole conversation: the question and every reply, each with the Discord name of who posted it.") end)
    helpers.safe(function() detail.copySel.hidden = true end)
    helpers.setTip(detail.copySel, TIPS.ctrl["Select"])
    R("copy field", "InputField", detail.copy); R("copy text", "Text", detail.copyShow); R("copy select", "Button", detail.copySel)

    tbl = Table.new(root, R)
    tbl.afterRow = function() refresh() end
    -- 0.3.0: adjustable columns use the shared helpers.columns (widths in
    -- PersistentDB "colWidths"); Settings picks drag or < > buttons.
    helpers.common.colButtons = state.colBtn == true
    ddCtrl(T_SET, 130, { "Columns: drag", "Columns: < > buttons" }, function() return state.colBtn and 2 or 1 end,
        function(i) state.colBtn = i == 2; helpers.common.colButtons = state.colBtn; save(); pcall(helpers.refreshColumns) end, nil, "column resize",
        "Column resize: drag a header border, or show small < > buttons on each border.")
    do local b = btn(T_SET, "Reset all widths", 104, function() pcall(helpers.resetColumns); refresh() end, nil, "__colreset")
        helpers.setTip(b, "Put every column in every table back to its default width.") end
    -- 0.4.1: menu tile coords + item hover info (rdt_hover.lua), both on by default
    pcall(function() NT.hover = require("rdt_hover")({ helpers = helpers, state = state }) end)
    ddCtrl(T_SET, 150, { "Menu tile coords: on", "Menu tile coords: off" }, function() return state.menuCoords == false and 2 or 1 end,
        function(i) state.menuCoords = i == 1; save() end, nil, "menu coords",
        "Right-click menu: add an info line with the tile under the mouse (level, x, z, map square, local). It does nothing when clicked.")
    ddCtrl(T_SET, 150, { "Item hover info: on", "Item hover info: off" }, function() return state.itemHover == false and 2 or 1 end,
        function(i) state.itemHover = i == 1; save() end, nil, "item hover",
        "Show Item Name (ID) next to the pointer when hovering an item on the ground or in the inventory, bank or equipment.")
    tbl.onResize = function() refresh() end
    for _, m in ipairs(NT.mods) do
        if m.build then
            local tab = m.tab
            local okb, errb = pcall(m.build, {
                btn = function(label, w, fn, show, tip) local b = btn(tab, label, w, fn, show, "__m" .. label); if tip then helpers.setTip(b, tip) end; return b end,
                field = function(w, ph, name, show, tip) local f = field(tab, w, ph, name, show); if tip then helpers.setTip(f, tip) end; return f end,
                dd = function(w, opts, get, set, show, name, tip, onChange) return ddCtrl(tab, w, opts, get, set, show, name, tip, onChange) end,
            })
            if not okb then logError("build " .. m.name, tostring(errb)) end
        end
    end

    local items = helpers.commonItems(function() refresh() end)
    settingsUI = helpers.newSettings(root, items, 6)
    settingsUI.onChange = function() refresh() end
    helpers.editToggle(root, function() return state.editOpen == true end, function(v)
        state.editOpen = v; save(); layout(); helpers.refit()
    end)
    if state.tab < 1 or state.tab > #TABS then state.tab = 1 end
    layout(); helpers.refit()
end

-------------------------------------------------------------------------------
-- Ticks
-------------------------------------------------------------------------------
local window = nil
local lastQ = {}
local function polled(key, f, maxLen, onChange)
    local t = readField(f, maxLen)
    if t ~= lastQ[key] then lastQ[key] = t; onChange(t); return true end
    return false
end
helpers.subscribe(PLUGIN_NAME, "Logic", "rdtLogic", function()
    ticks = ticks + 1
    helpers.tickToast()
    if window == nil or root == nil then return end
    -- background scans (only once the tab has been opened)
    if browserReady then scanStep(state.set) end
    if sndReady then sndScan(); if sndSweep() and state.tab == T_AUDIO then refresh() end end
    local w = nil
    pcall(function() w = root.width end)
    if w ~= nil and w ~= lastW and not helpers.isResizing() then
        if lastW ~= nil then refresh() end
        lastW = w
    end
    -- 0.5.3 frame cost: the layer walk (up to 6000 components) only runs
    -- while the panel is open and expanded
    if ticks % 500 == 0 and not helpers.isCollapsed() then pcall(leakCheck) end
    pcall(Table.tick)
    for _, m in ipairs(NT.mods) do if m.tick then local okt, et = pcall(m.tick, state.tab == m.tab, ticks); if not okt then logError("tick " .. m.name, tostring(et)) end end end
    -- 0.2.7 Resource Monitor: one sample a second, always (cheap), so the
    -- graph has history when the tab is opened
    if ticks % 50 == 0 then
        if state.tab == NT.T_RES then
            if ticks % 250 == 0 then pcall(leakCheck) end
            local v = helpers.cleanInt(readField(NT.mon.field, 4), 10, NT.MON_MAXWIN)
            if v and v ~= NT.mon.win then NT.mon.win = v; NT.mon.drawn = nil end
        end
        pcall(NT.monSample)
    end
    -- 0.5.3 frame cost / layout stability: search fields are polled every
    -- 10 ticks, but the table is rebuilt only when something changed (a
    -- field) or on a slow timer for live tabs (every 25 ticks; Diagnostics
    -- every 250 because it walks the layer). Static tabs (docs, commands,
    -- settings) never refresh on a timer, so their layout cannot flip.
    -- Nothing runs while the panel is collapsed or hidden.
    if ticks % 10 == 0 then
        if helpers.isCollapsed() then return end
        local hid = false
        pcall(function() local b = helpers.winBox(); hid = b == nil or b.hidden == true end)
        if hid then return end
        local tab = state.tab
        local changed = false
        if tab == T_BROWSE then changed = polled("br", brSearch, 64, function(t) br.q = t; brFilter(); tbl.page = 1 end)
        elseif tab == T_AUDIO then changed = polled("snd", sndSearch, 64, function(t) snd.q = t; sndFilter(); tbl.page = 1 end)
        elseif tab == T_FAQ or tab == T_SET or tab == T_API or tab == T_FIT or tab == T_RELOAD then
            local f = ({ [T_FAQ] = faqField, [T_SET] = setField, [T_API] = api.field, [T_FIT] = fitField, [T_RELOAD] = slugField })[tab]
            changed = polled("f" .. tab, f, 120, function() tbl.page = 1 end)
        end
        if tab == T_UI and frozen then return end
        local static = tab == T_FAQ or tab == T_SET or tab == T_API or tab == T_RELOAD or tab == T_CMD
        local period = (tab == T_DIAG) and 250 or 30
        if changed or (not static and ticks % period == 0) then refresh() end
    end
end)

local function tryCreateWindow()
    if window ~= nil then return end
    window = helpers.createWindow(PLUGIN_NAME, 480, 200, 0.30, 0.15)
    if window ~= nil then
        local ok = guarded("building panel", buildPanel, window)
        helpers.raiseGrip()
        if not ok then helpers.log("[" .. PLUGIN_NAME .. "] ERROR building panel") end
        pcall(leakCheck)
    end
end

tryCreateWindow()

local retryTicks = 0
helpers.subscribe(PLUGIN_NAME, "Logic", "windowRetry", function()
    if window == nil then
        retryTicks = retryTicks + 1
        if retryTicks >= 50 then retryTicks = 0; tryCreateWindow() end
    end
end)

helpers.installRibbon(PLUGIN_NAME)
helpers.log("[" .. PLUGIN_NAME .. "] loaded")

function PluginShutdown()
    pcall(NT.WR.shutdown)
    for _, m in ipairs(NT.mods) do if m.shutdown then pcall(m.shutdown) end end
    FaqDialog.close()
    sndStopAll()
    save()
    helpers.destroyToast()
    helpers.destroyWindow()
end
