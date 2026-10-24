--[[ rdt_mods.lua (0.4.0): the tabs that live in their own files. One edition:
  every module ships and loads. ]]
-- Each module is required by its literal name (no computed module names).
local PUBLIC = {
    { "rdt_events", function() return require("rdt_events") end },
    { "rdt_world", function() return require("rdt_world") end },
    { "rdt_tree", function() return require("rdt_tree") end },
    { "rdt_shapes", function() return require("rdt_shapes") end },
    { "rdt_db", function() return require("rdt_db") end },
    { "rdt_prof", function() return require("rdt_prof") end },
    { "rdt_perms", function() return require("rdt_perms") end },
    { "rdt_cover", function() return require("rdt_cover") end },
    { "rdt_sandbox", function() return require("rdt_sandbox") end },
    { "rdt_give", function() return require("rdt_give") end },
}
local EXTRA  -- formerly Unlimited-only
local UNLIMITED = {
    { "rdt_auto", function() return require("rdt_auto") end },
    { "rdt_visual", function() return require("rdt_visual") end },
    { "rdt_probe", function() return require("rdt_probe") end },
}
return function(ctx)
    local out = {}
    local function addMod(e)
        local ok, m = pcall(e[2])
        if ok and type(m) == "function" then
            local ok2, spec = pcall(m, ctx)
            if ok2 and type(spec) == "table" then out[#out + 1] = spec
            else ctx.logError("module " .. e[1], tostring(spec)) end
        elseif not ok then ctx.logError("module " .. e[1], tostring(m)) end
    end
    for _, e in ipairs(PUBLIC) do addMod(e) end
    for _, e in ipairs(UNLIMITED) do addMod(e) end
    return out
end
