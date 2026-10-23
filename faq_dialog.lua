--[[
  faq_dialog.lua (RS Dev Tools 0.2.1): the Help/FAQ answer window.
  A separate draggable panel on the plugin layer: centred title, whole top
  bar drags, any click brings it to the front, X and Close, Prev and Next.
  The question is the heading; the answer is word-wrapped with no
  truncation and scrolls (Up / Down buttons and a scrollbar) when it is
  longer than the view. Code and commands from the answer are shown in a
  monospace block (when the client has a monospace font) with a Copy field.
  Source channel, date and frequency come from the FAQ file. All
  components are destroyed on Close and from PluginShutdown.
]]
local H = require("ui_helpers")
local D = {}
local W, HGT = 480, 460
local VIS = 13                      -- answer lines visible at once
local box, parts, cur, list, scroll, ansLines = nil, nil, nil, nil, 0, {}
local copyOpen = false   -- Copy button swaps the code block for a selectable field

local function plain(s) return (tostring(s or ""):gsub("[<>]", "")) end
local function tw(font, s) return H.textWidthOf(font, s) or (#s * 7) end
local function wrap(font, s, w)
    local out, line = {}, ""
    for word in tostring(s):gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and tw(font, try) > w then out[#out + 1] = line; line = word
        else line = try end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
end
local MONO = nil
local function monoFont()
    if MONO ~= nil then return MONO or nil end
    MONO = false
    pcall(function()
        for k, v in pairs(id.Font) do
            if type(k) == "string" and string.find(string.upper(k), "MONO", 1, true) and type(v) == "number" then MONO = v; break end
        end
    end)
    return MONO or nil
end
local function text(parent, font)
    local t = ui.Text.new(parent)
    t.font = font or H.FONT
    t.content = ""
    t:AlignTo(ui.AlignMode.TOPLEFT, ui.AlignMode.CENTRE)
    pcall(function() t.maxLines = 1 end)
    H.shadow(t)
    return t
end
local function rect(parent, r, g, b, a, fill)
    local c = ui.Rectangle.new(parent)
    c.fill = fill ~= false
    c.colour = Vector4.new(r, g, b, a)
    return c
end
local function front()
    pcall(function() box:MoveToFront() end)
end

function D.isOpen() return box ~= nil end

function D.close()
    if box ~= nil then pcall(function() box:Destroy() end) end
    if parts and parts.tipped then for _, c in ipairs(parts.tipped) do H.tips[c] = nil end end
    box, parts, cur = nil, nil, nil
end

local function bodyW() return W - 2 * H.PAD - 16 end

local function render()
    if box == nil or cur == nil then return end
    local e = list[cur]
    local RH = H.ROW_HEIGHT
    H.safe(function() parts.title.content = H.col(H.C_TITLE, "Help/FAQ  " .. cur .. " of " .. #list) end)
    local q = wrap(H.TITLE_FONT, "Q" .. tostring(e.n or "") .. ". " .. plain(e.q), W - 2 * H.PAD)
    for i = 1, 3 do H.safe(function() parts.q[i].content = q[i] and H.gold(q[i]) or ""; parts.q[i].hidden = q[i] == nil end) end
    if #q > 3 then H.safe(function() parts.q[3].content = H.gold(q[3] .. " " .. table.concat(q, " ", 4)) end) end
    local meta = plain(e.where or "")
    if (e.freq or "") ~= "" then meta = meta .. (meta ~= "" and "  |  " or "") .. "Asked: " .. plain(e.freq) end
    H.safe(function() parts.meta.content = H.lbl(meta ~= "" and meta or "source not recorded") end)
    local y = H.TITLE_HEIGHT + 8 + math.min(3, #q) * RH
    H.safe(function() parts.meta:SetPos(H.PAD, y) end)
    y = y + RH + 4
    -- answer, wrapped, scrolled
    ansLines = wrap(H.FONT, plain(e.a), bodyW())
    local maxS = math.max(0, #ansLines - VIS)
    if scroll > maxS then scroll = maxS end
    for i = 1, VIS do
        local l = ansLines[scroll + i]
        H.safe(function() parts.a[i]:SetPos(H.PAD, y + (i - 1) * RH); parts.a[i].content = l and H.val(l) or "" end)
    end
    local trackH = VIS * RH
    local sx = W - H.PAD - 12
    H.safe(function()
        parts.track:SetPos(sx, y + 20); parts.track:SetSize(12, trackH - 40)
        parts.up:SetPos(sx - 2, y); parts.dn:SetPos(sx - 2, y + trackH - 18)
        local frac = #ansLines > 0 and math.min(1, VIS / #ansLines) or 1
        local th = math.max(10, math.floor((trackH - 40) * frac))
        local ty = maxS > 0 and math.floor((trackH - 40 - th) * scroll / maxS) or 0
        parts.thumb:SetPos(sx + 2, y + 20 + ty); parts.thumb:SetSize(8, th)
        local show = maxS > 0
        parts.track.hidden, parts.thumb.hidden, parts.up.hidden, parts.dn.hidden = not show, not show, not show, not show
    end)
    y = y + trackH + 6
    -- code block
    local code = type(e.code) == "table" and e.code or {}
    local hasCode = #code > 0
    local font = monoFont() or H.FONT
    for i = 1, 3 do
        local c = code[i]
        if i == 3 and #code > 3 then c = c .. "  (+" .. (#code - 3) .. " more in Copy)" end
        H.safe(function()
            parts.code[i].font = font
            parts.code[i]:SetPos(H.PAD + 6, y + 2 + (i - 1) * RH); parts.code[i].content = c and H.col("e6d7b0", plain(c)) or ""
            parts.code[i].hidden = c == nil
        end)
    end
    local nc = math.min(3, #code)
    -- review: one code block plus a Copy button. Copy swaps the block for a
    -- selectable field (plugins have no clipboard API); Done swaps back.
    H.safe(function()
        parts.codeBg.hidden = not hasCode
        parts.codeBg:SetPos(H.PAD, y); parts.codeBg:SetSize(W - 2 * H.PAD - 72, nc * RH + 4)
        parts.copyBtn.hidden = not hasCode
        parts.copyBtn:SetPos(W - H.PAD - 64, y)
        H.setText(parts.copyBtn, copyOpen and "Done" or "Copy", "label")
        parts.copy.hidden = not (hasCode and copyOpen)
        for i = 1, 3 do if copyOpen then parts.code[i].hidden = true end end
    end)
    if hasCode then
        H.safe(function()
            parts.copy:SetPos(H.PAD, y); parts.copy:SetSize(W - 2 * H.PAD - 72, H.BTN_H)
            local c = H.cleanText(table.concat(code, " ; "), 1000)
            if parts.copy.content ~= c then parts.copy.content = c end
        end)
        y = y + math.max(nc * RH + 4, H.BTN_H) + 8
    end
    -- footer
    y = y + 2
    H.safe(function()
        parts.prev:SetPos(H.PAD, y); parts.next:SetPos(H.PAD + 64, y)
        parts.close:SetPos(W - H.PAD - 64, y)
        parts.pos.content = H.lbl(#ansLines > VIS and ("lines " .. (scroll + 1) .. "-" .. math.min(#ansLines, scroll + VIS) .. " of " .. #ansLines) or "")
        parts.pos:SetPos(H.PAD + 132, y)
        box:SetSize(W, y + H.BTN_H + H.PAD)
    end)
end

local function go(i)
    if list == nil or #list == 0 then return end
    cur = ((i - 1) % #list) + 1
    scroll = 0
    copyOpen = false
    render()
end

--- Open the dialog on entry index i of list (an array of FAQ entries).
function D.open(entries, i)
    list = entries
    if box == nil then
        local layer = H.ensureHoverLayer()
        if layer == nil then return false end
        local ok = pcall(function()
            box = ui.GroupBox.new(layer)
            box.stylesheetID = id.StyleSheet.DEFAULT
            box:SetHeaderLayout(0, 0, 0, 0, 0)
            box:SetSize(W, HGT)
            box:SetPos(-math.floor(W / 2), -math.floor(HGT / 2), 0.5, 0.5)
            pcall(function() box.colour = Vector4.new(0.62, 0.60, 0.58, 1.0) end)
            H.blockClicks(box)
            parts = { q = {}, a = {}, code = {}, tipped = {} }
            local body = rect(box, 0.07, 0.06, 0.045, 0.97); body:SetPos(2, 2); body:SetSize(-4, -4, 1.0, 1.0)   -- opaque
            local band = rect(box, 0.13, 0.11, 0.07, 0.85); band:SetPos(2, 2); band:SetSize(-4, H.TITLE_HEIGHT, 1.0, 0.0)
            for k, c in ipairs({ { 0, 34, 27, 19, 1.0 }, { 1, 87, 78, 46, 1.0 }, { 2, 73, 65, 42, 0.9 } }) do
                local fr = rect(box, c[2] / 255, c[3] / 255, c[4] / 255, c[5], false)
                fr:SetPos(c[1], c[1]); fr:SetSize(-2 * c[1], -2 * c[1], 1.0, 1.0); pcall(function() fr.outlineThickness = -1 end)
            end
            local rule = rect(box, 87 / 255, 78 / 255, 46 / 255, 1.0); rule:SetPos(3, H.TITLE_HEIGHT + 2); rule:SetSize(-6, 1, 1.0, 0.0)
            -- whole top bar drags (an empty Text takes the clicks), title centred on top of it
            local bar = ui.Text.new(box); bar:SetPos(2, 2); bar:SetSize(-32, H.TITLE_HEIGHT, 1.0, 0.0); bar.content = ""   -- stops short of X
            H.blockClicks(bar); H.makeDraggable(bar, box)
            parts.title = text(box, H.TITLE_FONT); parts.title:SetPos(30, 2); parts.title:SetSize(-60, H.TITLE_HEIGHT, 1.0, 0.0)
            parts.title:AlignTo(ui.AlignMode.CENTRE, ui.AlignMode.CENTRE)
            H.blockClicks(parts.title); H.makeDraggable(parts.title, box)
            parts.x = H.button(box, 0, 3, 20, 18, "X", function() D.close() end, true)
            parts.x:SetPos(-24, 3, 1.0, 0.0)
            for i2 = 1, 3 do
                parts.q[i2] = text(box, H.TITLE_FONT); parts.q[i2]:SetPos(H.PAD, H.TITLE_HEIGHT + 8 + (i2 - 1) * H.ROW_HEIGHT)
                parts.q[i2]:SetSize(W - 2 * H.PAD, H.ROW_HEIGHT)
            end
            parts.meta = text(box); parts.meta:SetSize(W - 2 * H.PAD, H.ROW_HEIGHT)
            H.setTip(parts.meta, "Where and when this was discussed in the plugin developer Discord, and how often it came up.")
            parts.tipped[#parts.tipped + 1] = parts.meta
            for i2 = 1, VIS do parts.a[i2] = text(box); parts.a[i2]:SetSize(bodyW(), H.ROW_HEIGHT) end
            parts.track = rect(box, 0.11, 0.10, 0.09, 0.94)
            parts.thumb = rect(box, 0.78, 0.70, 0.52, 0.9)
            parts.up = H.button(box, 0, 0, 16, 18, "^", function() scroll = math.max(0, scroll - 3); render() end, true)
            parts.dn = H.button(box, 0, 0, 16, 18, "v", function() scroll = scroll + 3; render() end, true)
            H.setTip(parts.up, "Scroll the answer up 3 lines."); H.setTip(parts.dn, "Scroll the answer down 3 lines.")
            parts.tipped[#parts.tipped + 1] = parts.up; parts.tipped[#parts.tipped + 1] = parts.dn
            parts.codeBg = rect(box, 0.07, 0.06, 0.05, 0.95)
            for i2 = 1, 3 do parts.code[i2] = text(box); parts.code[i2]:SetSize(W - 2 * H.PAD - 12, H.ROW_HEIGHT) end
            parts.copyBtn = H.button(box, 0, 0, 64, H.BTN_H, "Copy", function() copyOpen = not copyOpen; render() end)
            H.setTip(parts.copyBtn, "Show the code as a selectable field: click it, select all and copy.")
            parts.tipped[#parts.tipped + 1] = parts.copyBtn
            parts.copy = H.input(box, 0, 0, 200, H.BTN_H, "")
            H.setTip(parts.copy, "The code or commands from this answer, joined with ' ; '. Click, select all and copy.")
            parts.tipped[#parts.tipped + 1] = parts.copy
            parts.prev = H.button(box, 0, 0, 60, H.BTN_H, "Prev", function() go(cur - 1) end)
            parts.next = H.button(box, 0, 0, 60, H.BTN_H, "Next", function() go(cur + 1) end)
            parts.close = H.button(box, 0, 0, 64, H.BTN_H, "Close", function() D.close() end)
            parts.pos = text(box); parts.pos:SetSize(160, H.BTN_H)
            for _, c in ipairs({ box, bar, parts.prev, parts.next, parts.up, parts.dn, parts.copy }) do
                pcall(function() c:Subscribe(ui.Hook.ONCLICK, "faqFront", front) end)
            end
        end)
        if not ok then D.close(); return false end
    end
    front()
    go(i or 1)
    return true
end

return D
