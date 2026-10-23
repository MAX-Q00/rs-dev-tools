--[[ rdt_events.lua (0.3.0) Event Payloads tab (Inspect): every documented
  event with a counter, events per second and the last payload. Read only:
  payloads are never changed. ChatMessage is only counted when chatAccess is
  granted. EntityDraw always returns true (it never hides anything). ]]
local ALL = { "Logic", "ServerLogic", "Draw", "OptionalDependencyChanged", "OptionalPermissionChanged", "KeyUp", "KeyDown",
    "KeyTyped", "VarTransmit", "ChatMessage", "PlayerEntityAdded", "PlayerEntityRemoved", "NPCEntityAdded", "NPCEntityRemoved",
    "ObjStackEntityAdded", "ObjStackEntityRemoved", "ObjStackEntityChanged", "WindowFocusChanged", "GameStateChanged", "EntityDraw",
    "WindowSizeChanged", "SkillTransmit", "RunEnergyTransmit", "RunWeightTransmit", "MiniMenuOpened", "MiniMenuClosed", "MiniMenuReady",
    "MiniMenuEntryAdded", "MiniMenuEntrySelected", "LocAdded", "LocRemoved", "LocCustomised", "LocAnimation", "InventoryAdded",
    "InventoryUpdated", "InventoryRemoved", "GrandExchangeOfferUpdated", "WorldCreated", "WorldUpdated", "RegionCreated", "RegionUpdated",
    "SettingsLayerReady", "ContentLayerReady" }
local FIELDS = { "logicTick", "timeDeltaSecs", "pluginIdentifier", "permissionName", "enabled", "isRepeat", "gameKey", "systemKey", "char",
    "modifiers", "timestamp", "var", "oldValue", "newValue", "chatType", "entityType", "uid", "objType", "count", "oldCount", "newCount",
    "isOwner", "focused", "hasFocus", "oldState", "newState", "oldWidth", "oldHeight", "newWidth", "newHeight", "skill", "oldXP", "newXP",
    "oldGameplayLevel", "newGameplayLevel", "newRunEnergy", "newRunWeight", "shapeType", "rotationType", "coordGrid", "overrideTransform",
    "animation", "animationDelay", "inv", "invType", "invID", "slot", "listing", "mapSquareMinX", "mapSquareMinZ", "mapSquareMaxX",
    "mapSquareMaxZ", "regionGridCorner", "regionGridWidth", "regionGridLength", "playerEntity", "npcEntity", "objStackEntity", "locEntity",
    "entity", "index", "label", "id" }
local PRIVATE = { chatMessage = true, senderNameUnfiltered = true, senderNameFiltered = true, senderNameSimple = true }
return function(ctx)
    local H = ctx.H
    local S = { n = {}, last = {}, pay = {}, rate = {}, prev = {}, sel = nil, subs = {}, paused = false, mode = 1 }
    local function brief(v)
        local t = type(v)
        if t == "number" then return (math.type and math.type(v) == "float") and string.format("%.3f", v) or tostring(v) end
        if t == "string" then return '"' .. ctx.plain(v:sub(1, 40)) .. '"' end
        if t == "boolean" then return tostring(v) end
        local s = ""
        pcall(function() s = ctx.plain(tostring(v)):sub(1, 40) end)
        pcall(function() if v.uid then s = s .. " uid " .. tostring(v.uid) end end)
        pcall(function() if v.configID then s = s .. " config " .. tostring(v.configID) end end)
        return s
    end
    local function capture(name, e)
        if S.paused then return end
        S.n[name] = (S.n[name] or 0) + 1
        S.last[name] = ctx.secs()
        if name == "Draw" or name == "Logic" or name == "EntityDraw" then
            if S.sel ~= name then return end
        end
        if type(e) ~= "table" and type(e) ~= "userdata" then S.pay[name] = {}; return end
        local p = {}
        for _, f in ipairs(FIELDS) do
            local ok, v = pcall(function() return e[f] end)
            if ok and v ~= nil and not PRIVATE[f] then p[#p + 1] = { f, brief(v) } end
        end
        S.pay[name] = p
    end
    local mine = {}
    for _, n in ipairs(ctx.EVENTS) do mine[n] = true end
    local function subscribe(n)
        if mine[n] or S.subs[n] then return end
        if n == "ChatMessage" then
            local ok = false
            pcall(function() ok = Plugin.HasPermission(PluginPermissions.chatAccess) end)
            if not ok then return end
        end
        local ok = pcall(function()
            Event[n].Subscribe("rdtEv2" .. n, function(e)
                pcall(capture, n, e)
                if n == "EntityDraw" then return true end
            end)
        end)
        S.subs[n] = ok and "yes" or "failed"
    end
    for _, n in ipairs(ALL) do subscribe(n) end
    local spec = { name = "Event Payloads", cat = "Inspect" }
    function spec.onEvent(name, e) if mine[name] then capture(name, e) end end
    function spec.tick(active, t)
        if t % 50 == 0 then
            for _, n in ipairs(ALL) do local c = S.n[n] or 0; S.rate[n] = c - (S.prev[n] or 0); S.prev[n] = c end
            if active then ctx.refresh() end
        end
    end
    function spec.shutdown()
        for n in pairs(S.subs) do pcall(function() Event[n].Unsubscribe("rdtEv2" .. n) end) end
    end
    function spec.build(ui)
        ui.dd(120, { "Show: all", "Show: seen", "Show: not seen" }, function() return S.mode end, function(i) S.mode = i end, nil, "events filter",
            "Which events to list: all documented events, only ones that fired, or ones that never fired.")
        ui.btn("Pause", 56, function() S.paused = not S.paused; ctx.refresh() end, nil, "Stop or resume counting.")
        ui.btn("Reset", 52, function() S.n, S.last, S.pay, S.rate, S.prev = {}, {}, {}, {}, {}; ctx.refresh() end, nil, "Clear every counter and payload.")
    end
    function spec.view()
        local rows = {}
        local now = ctx.secs()
        for _, n in ipairs(ALL) do
            local c = S.n[n] or 0
            if S.mode == 1 or (S.mode == 2 and c > 0) or (S.mode == 3 and c == 0) then
                local how = mine[n] and "Event Monitor" or (S.subs[n] == "yes" and "this tab" or (n == "ChatMessage" and "needs chatAccess" or (S.subs[n] or "-")))
                rows[#rows + 1] = { H.val(n), H.lbl(ctx.commas(c)), H.lbl(tostring(S.rate[n] or 0)),
                    H.lbl(S.last[n] and (string.format("%.0f", now - S.last[n]) .. " s ago") or "never"), H.lbl(how), ev = n }
            end
        end
        return { cols = { { title = "Event", flex = 2, min = 110 }, { title = "Count", w = 64, align = "right" }, { title = "Per s", w = 44, align = "right" },
                { title = "Last", w = 70 }, { title = "Subscribed by", flex = 1, min = 70 } },
            data = ctx.arr(rows), onRow = function(i) S.sel = rows[i].ev end,
            detail = function()
                if S.sel == nil then return { lines = { H.lbl((S.paused and "Paused. " or "") .. "Click an event to see the fields of its last payload (chat text and sender names are never shown).") } } end
                local L = { H.gold(S.sel) .. H.lbl("  last payload") }
                for _, p in ipairs(S.pay[S.sel] or {}) do if #L < 8 then L[#L + 1] = H.lbl(p[1] .. " = ") .. H.val(p[2]) end end
                if #L == 1 then L[2] = H.lbl("No payload fields captured yet (or the event has no payload).") end
                return { lines = L }
            end }
    end
    return spec
end
