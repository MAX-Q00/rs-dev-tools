-- Records components the FAQ dialog creates, dumps them as JSON-ish lines.
local objs = {}
local function newObj(kind, parent)
  local o = { kind = kind, parent = parent, x = 0, y = 0, w = 0, h = 0, props = {} }
  objs[#objs + 1] = o
  return setmetatable(o, { __index = function(t, k)
      if k == "SetPos" then return function(self, x, y) self.x, self.y = x or 0, y or 0 end end
      if k == "SetSize" then return function(self, w, h, fw, fh) self.w, self.h, self.fw, self.fh = w or 0, h or 0, fw, fh end end
      if k == "content" or k == "hidden" or k == "colour" or k == "font" then return rawget(t.props, k) end
      return function() return nil end
    end, __newindex = function(t, k, v) t.props[k] = v end })
end
local any = setmetatable({}, { __index = function() return 0 end })
ui = { Text = { new = function(p) return newObj("text", p) end }, Rectangle = { new = function(p) return newObj("rect", p) end },
  GroupBox = { new = function(p) return newObj("box", p) end }, TextInput = { new = function(p) return newObj("input", p) end },
  Button = { new = function(p) return newObj("button", p) end }, Sprite = { new = function(p) return newObj("sprite", p) end },
  Layer = { new = function(p) return newObj("layer", p) end }, InputField = { new = function(p) return newObj("input", p) end },
  AlignMode = any, Hook = any, Interfaces = { GetComponent = function() return newObj("layer") end } }
Vector4 = { new = function(r, g, b, a) return { r, g, b, a } end }
id = { Font = { P12 = 494 }, StyleSheet = any, Component = any, Sprite = any }
Event = setmetatable({}, { __index = function() return { Subscribe = function() end } end })
Mouse = any; game = any; config = any
package.path = "./?.lua;" .. package.path
local H = require("ui_helpers")
H.ensureHoverLayer = function() return newObj("layer") end
local D = require("faq_dialog")
local FAQ = require("faq_data")
local pick = tonumber(arg[1] or "35")
local idx = 1
for i, e in ipairs(FAQ) do if e.n == pick then idx = i end end
D.open(FAQ, idx)
local box
for _, o in ipairs(objs) do if o.kind == "box" then box = o end end
print(string.format("BOX %d %d", box.w, box.h))
for _, o in ipairs(objs) do
  if o.parent == box then
    local c = o.props.content
    print(string.format("%s|%d|%d|%d|%d|%s|%s|%s|%s", o.kind, o.x, o.y, o.w, o.h, tostring(o.props.hidden), tostring(c or ""):gsub("|", "/"),
      o.props.colour and table.concat(o.props.colour, ",") or "", tostring(o.fw or "")))
  end
end
