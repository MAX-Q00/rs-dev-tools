--[[
  dt_table.lua: the one shared table used by every RS Dev Tools tab.
  Header row (gold), divider, alternating row shading, consistent 6 px cell
  padding, aligned columns that adapt to the panel width, long cells
  shortened with an ellipsis (full text in the shared hover box), optional
  icon column, row click callback and a pager (Prev, page, Next, jumps).
  Column spec: { title = "Name", w = 60 } fixed, or { title, flex = 2, min = 60 }.
  Data: { count = n, get = function(i) return { cell1, cell2, ... } end }.
]]
local H = require("ui_helpers")
local T = {}
T.ROWS = 12
T.PAGE_BOX_W = 48
T.MAXC = 6
T.CELL_PAD = 6
local BG = { { 0x24/255, 0x21/255, 0x1E/255 }, { 0x2E/255, 0x2A/255, 0x26/255 } }

local function text(parent)
    local t = nil
    pcall(function()
        t = ui.Text.new(parent)
        t:SetSize(40, H.ROW_HEIGHT)
        t.font = H.FONT
        t.content = ""
        t:AlignTo(ui.AlignMode.TOPLEFT, ui.AlignMode.CENTRE)
        H.shadow(t)
    end)
    return t
end
local function rect(parent, r, g, b, a)
    local c = nil
    pcall(function() c = ui.Rectangle.new(parent); c.fill = true; c.colour = Vector4.new(r, g, b, a) end)
    return c
end

function T.new(root, register)
    local self = { root = root, cols = {}, data = { count = 0 }, page = 1, y = 0, w = 300,
        rows = {}, head = {}, jumpBtns = {}, onRow = nil, selected = nil, icons = nil }
    register = register or function() end
    self.listBg = rect(root, 0x1C/255, 0x1A/255, 0x17/255, 0.94)
    for r = 1, T.ROWS do
        local row = { bg = rect(root, 1, 1, 1, 0.92), cells = {}, icon = nil }
        row.bar = rect(root, 0xE0/255, 0xB0/255, 0x40/255, 1.0)   -- gold bar on the selected row
        H.safe(function() row.bg.hidden = true; row.bar.hidden = true end)
        self.rows[r] = row
    end
    for c = 1, T.MAXC do
        self.head[c] = text(root)
        H.track(self.head[c], "content", T.CELL_PAD)
        local cc = c
        if H.setTip then H.setTip(self.head[c], function() return self:colTip(cc) end) end
    end
    self.div = rect(root, 0.78, 0.70, 0.52, 0.9)
    self.emptyT = text(root)   -- 0.2.6: one centred line when a table is empty
    H.safe(function() self.emptyT.hidden = true end)
    for r = 1, T.ROWS do
        local row = self.rows[r]
        for c = 1, T.MAXC do
            local t = text(root)
            H.track(t, "content", T.CELL_PAD)
            H.blockClicks(t)
            pcall(function()
                t:Subscribe(ui.Hook.ONCLICK, "dtRow", function()
                    pcall(H.raiseWindow)
                    if row.index ~= nil and self.onRow then pcall(self.onRow, row.index); if self.afterRow then pcall(self.afterRow) end end
                end)
            end)
            row.cells[c] = t
            local cc = c
            if H.setTip then H.setTip(t, function() return self:cellTip(row, cc) end) end
            register("table r" .. r .. " c" .. c, "Text", t)
        end
        pcall(function()
            row.spr = ui.Sprite.new(root); row.spr:SetSize(18, 18); row.spr.hidden = true
            row.obj = ui.Sprite.new(root); row.obj:SetSize(18, 18); row.obj.hidden = true
        end)
    end
    self.prev = H.button(root, 0, 0, 40, H.BTN_H, "Prev", function() self:go(self.page - 1) end)
    self.next = H.button(root, 0, 0, 40, H.BTN_H, "Next", function() self:go(self.page + 1) end)
    if H.setTip then
        H.setTip(self.prev, "Previous page."); H.setTip(self.next, "Next page.")
    end
    -- 0.2.6: one pager everywhere: -100 -10 Prev Page [n] of N Next +10 +100.
    -- The page number is a click-to-type box (Enter or click away to jump).
    self.pageLbl = text(root); H.setText(self.pageLbl, H.lbl("Page"))
    self.pageText = text(root)   -- "of N"
    self.pageBox = H.input(root, 0, 0, T.PAGE_BOX_W, H.BTN_H, "1")
    if H.setTip then H.setTip(self.pageBox, "Current page. Click, type a page number and press Enter to jump there.") end
    pcall(function()
        self.pageBox:Subscribe(ui.Hook.ONCONTENTCHANGED, "dtPage", function(_, cause)
            if cause == ui.InputFieldActionResult.SUBMIT or cause == ui.InputFieldActionResult.SUBMIT_ON_FOCUS_LOSS then
                local t = ""
                pcall(function() t = tostring(self.pageBox.content or "") end)
                local n = H.cleanInt(H.cleanText(t, 8), 1, self:pages())
                self.pageShown = nil
                if n then self:go(n) else self:bind() end
                if self.afterPage then pcall(self.afterPage) end
            end
        end)
    end)
    for _, n in ipairs({ -100, -10, 10, 100 }) do
        local lbl = (n > 0 and "+" or "") .. n
        local w = #lbl * 8 + 14
        local b = H.button(root, 0, 0, w, H.BTN_H, lbl, function() self:go(self.page + n) end)
        if H.setTip then H.setTip(b, (n > 0 and "Forward " or "Back ") .. math.abs(n) .. " pages.") end
        self.jumpBtns[#self.jumpBtns + 1] = { n = n, w = w, c = b }
    end
    register("table header/rows", "Table", self.listBg)
    return setmetatable(self, { __index = T })
end

--- "4352" -> "4,352"
function T.comma(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
--- ID / # / numeric columns are right-aligned (col.align = "right" forces it).
function T:isNumCol(c)
    local col = self.cols[c]
    if col == nil then return false end
    if col.align == "right" then return true end
    if col.align == "left" then return false end
    local t = tostring(col.title or ""):gsub("<[^>]*>", "")
    return t == "ID" or t == "#" or t == "Id"
end
function T:pagerLabel()
    return "Page " .. T.comma(self.page) .. " of " .. T.comma(self:pages())
end
--- One centred row: [-100] [-10] [Prev] Page [n] of N [Next] [+10] [+100].
-- The jump buttons drop out (outermost first) when the row would not fit.
function T:placePager()
    if self.pagerY == nil then return end
    local ofs = "of " .. T.comma(self:pages())
    local ow = 40
    pcall(function() ow = math.floor(H.textWidthOf(H.FONT, ofs)) + 6 end)
    local lw = 34
    pcall(function() lw = math.floor(H.textWidthOf(H.FONT, "Page")) + 6 end)
    local core = 40 + 6 + lw + T.PAGE_BOX_W + 6 + ow + 6 + 40
    local J = self.jumpBtns
    local function jw(a, b) local t = 0; for i = a, b do t = t + J[i].w + 4 end; return t end
    local show = {}
    local avail = self.w or 300
    if self.showJumps ~= false and core + jw(1, #J) <= avail then for i = 1, #J do show[i] = true end
    elseif self.showJumps ~= false and core + jw(2, 3) <= avail then show[2], show[3] = true, true end
    local total = core
    for i = 1, #J do if show[i] then total = total + J[i].w + 4 end end
    local x = -math.floor(total / 2)
    local y = self.pagerY
    for i = 1, #J do H.setHidden({ J[i].c }, not show[i]) end
    H.safe(function()
        for i = 1, 2 do if show[i] then J[i].c:SetPos(x, y, 0.5, 0.0); x = x + J[i].w + 4 end end
        self.prev:SetPos(x, y, 0.5, 0.0); x = x + 46
        self.pageLbl:SetPos(x, y, 0.5, 0.0); self.pageLbl:SetSize(lw, H.BTN_H); x = x + lw
        self.pageBox:SetPos(x, y, 0.5, 0.0); x = x + T.PAGE_BOX_W + 6
        self.pageText:SetPos(x, y, 0.5, 0.0); self.pageText:SetSize(ow, H.BTN_H); x = x + ow + 6
        self.pageText:AlignTo(ui.AlignMode.TOPLEFT, ui.AlignMode.CENTRE)
        self.next:SetPos(x, y, 0.5, 0.0); x = x + 46
        for i = 3, 4 do if show[i] then J[i].c:SetPos(x, y, 0.5, 0.0); x = x + J[i].w + 4 end end
    end)
end

function T:nrows() return math.max(1, math.min(T.ROWS, self.visRows or T.ROWS)) end
function T:pages() return math.max(1, math.ceil((self.data.count or 0) / self:nrows())) end
function T:go(p) self.page = math.max(1, math.min(self:pages(), p)); self:bind() end

--- Column widths for the available width: fixed first, flex shares the rest;
-- when there is not enough room every column shrinks proportionally.
function T:widths(avail)
    local fixed, flex = 0, 0
    for _, c in ipairs(self.cols) do
        if c.w then fixed = fixed + c.w else fixed = fixed + (c.min or 40); flex = flex + (c.flex or 1) end
    end
    local spare = avail - fixed
    local out = {}
    for i, c in ipairs(self.cols) do
        local w = c.w or (c.min or 40)
        if spare > 0 and not c.w and flex > 0 then w = w + spare * (c.flex or 1) / flex end
        if spare < 0 then w = w * avail / fixed end
        out[i] = math.max(12, math.floor(w))
    end
    return out
end

-- Tooltips (0.2.1): a column explains itself with col.tip, else T.gloss
-- (set by main.lua) looks the title up. A row may carry cells.tip (whole
-- row) or cells.tips[c] (one cell); those win over the column's tip.
T.gloss = function() return nil end
function T:colTip(c)
    local col = self.cols[c]
    if col == nil then return nil end
    return col.tip or T.gloss(col.title, self)
end
function T:cellTip(row, c)
    local d = row.data
    if d == nil or self.cols[c] == nil then return nil end
    local t = (type(d.tips) == "table" and d.tips[c]) or d.tip
    if type(t) == "function" then local ok, v = pcall(t); t = ok and v or nil end
    return t or self:colTip(c)
end

function T:setColumns(cols, data, onRow, iconKind)
    self.cols, self.data, self.onRow, self.iconKind = cols or {}, data or { count = 0 }, onRow, iconKind
    if self.page > self:pages() then self.page = self:pages() end
end

--- Place everything starting at y; returns the y below the pager.
function T:place(y, x0, avail, showJumps)
    self.y, self.x0, self.w = y, x0, avail
    local ws = self:widths(avail)
    self.ws = ws
    local x = x0
    for c = 1, T.MAXC do
        local h = self.head[c]
        local col = self.cols[c]
        H.setHidden({ h }, col == nil)
        if col then
            H.safe(function() h:SetPos(x, y); h:SetSize(ws[c], H.ROW_HEIGHT) end)
            H.setText(h, H.gold(col.title or ""))
            x = x + ws[c]
        end
    end
    y = y + H.ROW_HEIGHT
    H.safe(function() self.div:SetPos(x0, y); self.div:SetSize(avail, 1) end)
    y = y + 2
    H.safe(function() self.listBg:SetPos(x0 - 4, y); self.listBg:SetSize(avail + 8, self:nrows() * H.ROW_HEIGHT) end)
    local nr = self:nrows()
    for r = 1, nr do
        local row = self.rows[r]
        row.y = y
        H.safe(function()
            local k = BG[(r % 2) + 1]
            row.bg.colour = Vector4.new(k[1], k[2], k[3], 0.92)
            row.bg:SetPos(x0 - 4, y); row.bg:SetSize(avail + 8, H.ROW_HEIGHT)
            row.bar:SetPos(x0 - 4, y); row.bar:SetSize(3, H.ROW_HEIGHT)
        end)
        local cx = x0
        for c = 1, T.MAXC do
            local t = row.cells[c]
            if self.cols[c] then
                local w = ws[c]
                local off = (c == 1 and self.iconKind) and 22 or 0
                local rightA = self:isNumCol(c)
                H.safe(function()
                    t:SetPos(cx + off, y); t:SetSize(math.max(8, w - off - (rightA and 6 or 0)), H.ROW_HEIGHT)
                    t:AlignTo(rightA and ui.AlignMode.BOTTOMRIGHT or ui.AlignMode.TOPLEFT, ui.AlignMode.CENTRE)
                end)
                cx = cx + w
            end
        end
        H.safe(function() row.spr:SetPos(x0, y + 1); row.obj:SetPos(x0, y + 1) end)
        y = y + H.ROW_HEIGHT
    end
    -- 0.2.6: pager pinned under the rows; panel bottom is 8 px below it
    local empty = (self.data.count or 0) == 0
    H.setHidden({ self.emptyT }, not empty)
    if empty then
        H.safe(function()
            self.emptyT:SetPos(x0, self.rows[1].y); self.emptyT:SetSize(avail, H.ROW_HEIGHT * 2)
            self.emptyT:AlignTo(ui.AlignMode.CENTRE, ui.AlignMode.CENTRE)
        end)
        H.setText(self.emptyT, H.lbl(self.emptyMsg or "Nothing to show"))
    end
    y = y + 6
    self.pagerY = y
    self.showJumps = showJumps ~= false
    self:placePager()
    y = y + H.BTN_H + 8
    self:bind()
    return y
end

function T:bind()
    local pages = self:pages()
    if self.page > pages then self.page = pages end
    for r = 1, T.ROWS do
        local row = self.rows[r]
        local i = (self.page - 1) * self:nrows() + r
        local cells = nil
        if r <= self:nrows() and i <= (self.data.count or 0) and self.data.get then
            local ok, v = pcall(self.data.get, i)
            cells = ok and v or { H.col(H.C_BAD, "error") }
        end
        row.index = cells and i or nil
        row.data = cells
        H.safe(function() row.bg.hidden = cells == nil; row.bar.hidden = not (cells and self.selected == i) end)
        if cells and self.selected == i then
            H.safe(function() row.bg.colour = Vector4.new(0x5A/255, 0x4A/255, 0x2A/255, 0.98) end)
        elseif cells then
            local k = BG[(r % 2) + 1]
            H.safe(function() row.bg.colour = Vector4.new(k[1], k[2], k[3], 0.92) end)
        end
        for c = 1, T.MAXC do
            local t = row.cells[c]
            local show = cells ~= nil and self.cols[c] ~= nil
            H.setHidden({ t }, not show)
            if show then H.setText(t, tostring(cells[c] or "")) end
        end
        -- icon column (sprites, items, cursors)
        local ic = cells and cells.icon
        H.safe(function()
            row.spr.hidden = true; row.obj.hidden = true
            if ic ~= nil and self.iconKind then
                if ic.item then row.obj:SetAssociatedObject(ic.id); row.obj.hidden = false
                elseif ic.spr then row.spr.sprite = ic.spr; row.spr.hidden = false end
            end
        end)
    end
    H.setHidden({ self.prev, self.next, self.pageText, self.pageLbl, self.pageBox }, false)
    H.setText(self.pageText, H.lbl("of " .. T.comma(self:pages())))
    if self.pageShown ~= self.page then self.pageShown = self.page; H.safe(function() self.pageBox.content = tostring(self.page) end) end
    self:placePager()
end

return T
