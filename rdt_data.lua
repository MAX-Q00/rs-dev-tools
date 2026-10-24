--[[ rdt_data.lua (0.5.1): static tables moved out of main.lua to keep its
  top-level locals well under the Lua 200-local limit. Data only; the few
  live-check closures use globals and ui_helpers only. ]]
local H = require("ui_helpers")
local D = {}
D.LIMITS = {
    { "Panels of other plugins", "yes, read only", "scan of the shared plugin layer: type, position, size, shown, text" },
    { "Which plugin owns a panel", "no", "the layer has no owner field; the title text is shown as a guess" },
    { "Other plugins' settings", "no", "PersistentDB is isolated per plugin" },
    { "Other plugins' files", "no", "no file API; require only loads this plugin's own files" },
    { "Other plugins' timings", "no", "no profiler API; only this plugin's own cost is timed" },
    { "List installed plugins", "no", "no API; the console command plist is for people" },
    { "Run console commands", "yes, in dev", "ExecuteConsoleCommand (API core; FAQ 3). The Commands tab runs one only when you click Run" },
    { "Layer ID usage", "yes", "component count on the plugin layer vs the 4096 dynamic ID limit (Diagnostics)" },
    { "Plugin's own report", "opt in", "a plugin returns devInfo from main.lua and is listed in optionalDependencies" },
}
D.HOOK_NAMES = { "world_event_timers", "gear_preset_checker", "slayer_task_tracker", "sound_browser", "cursor_sprite" }
D.VOL_OPTS = { "VolumeMaster", "VolumeMainEffects", "VolumeBackgroundEffects", "VolumeMainMusic", "VolumeSpeech", "VolumeLoginMusic" }
D.OPTIONS = { "AmbientOcclusion", "AnimationQuality", "AnisotropicFiltering", "AntialiasingMode",
    "AntialiasingQuality", "Bloom", "CanopyCutout", "CustomPlayerModelCount", "DOF", "DrawDistance",
    "EntityHighlights", "GameRenderScale", "GroundBlending", "GroundDecor", "LightingQuality",
    "ParticleQuality", "Reflections", "ShadowQuality", "Shadows", "SmoothClipFade", "Texturing",
    "MaxBackgroundFps", "MaxForegroundFps", "VolumetricLighting", "VSync", "VolumeBackgroundEffects",
    "VolumeLoginMusic", "VolumeMainEffects", "VolumeMainMusic", "VolumeMaster", "VolumeSpeech",
    "RemoveRoof", "CursorScale", "CutsceneSubtitles", "Language", "InterfaceScale", "Brightness",
    "ConsoleKey", "CustomCursors", "DeviceCapOverrides", "Diagnostics", "RichPresence", "HapticFeedback" }
D.API_NS = { "Event", "Plugin", "PluginPermissions", "PersistentDB", "Mouse", "Keyboard", "audio", "ui", "config", "id",
    "game", "http", "Vector2", "Vector3", "Vector4" }
D.TRIES = {
    { "Mouse.IsAvailable()", function() return Mouse.IsAvailable() end },
    { "Mouse.GetPosition()", function() local p = Mouse.GetPosition(); return p.x .. ", " .. p.y end },
    { "Plugin.HasPermission(httpAccess)", function() return Plugin.HasPermission(PluginPermissions.httpAccess) end },
    { "game.options.InterfaceScale.setting", function() return game.options.InterfaceScale.setting end },
    { "game.options.VolumeMaster.setting", function() return game.options.VolumeMaster.setting end },
    { "id.Sprite.FromID(1)", function() return id.Sprite.FromID(1) end },
    { "id.Sound.FromID(1)", function() return id.Sound.FromID(1) end },
    { "config.Obj.FromID(1).name", function() return config.Obj.FromID(1).name end },
    { "config.Cursor.FromID(0).spriteID", function() return config.Cursor.FromID(0).spriteID end },
    { "config.Font.FromID(font):GetStringWidth", function() return config.Font.FromID(H.FONT):GetStringWidth("Test") end },
    { "ui.Interfaces:GetComponent(plugin layer)", function() return tostring(ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP) ~= nil) end },
    { "PersistentDB:IterateEntries (count)", function() local n = 0; PersistentDB:IterateEntries(function() n = n + 1; return false end); return n end },
    { "os.clock()", function() return os.clock() end },
}
D.GAPS = {
    { "No os library (use Logic ticks to time)", 22, function() return type(rawget(_G, "os")) == "table" and "os present here" or "confirmed: os missing" end },
    { "ExecuteConsoleCommand exists (used by the Commands tab)", 3, function() return type(rawget(_G, "ExecuteConsoleCommand")) == "function" and "present" or "not present" end },
    { "requiredPermissions does not work; use optional", 1, nil },
    { "LocList.All() returns scenery only", 24, function() return type(rawget(_G, "LocList")) == "table" and "LocList present (not called)" or "LocList not global" end },
    { "Chat event fields are read only", 20, nil },
    { "No component text update events, no wait", 19, nil },
    { "Headerless group box: SetHeaderLayout(0,0,0,0,0) still shows a header", 14, nil },
    { "Two NPCEntityAdded listeners: second gets isValid false", 21, nil },
    { "Docs say valid, property is isValid", 23, nil },
    { "Sound volume below 1 reported as not playing", 28, nil },
    { "Drag coordinates scale on high DPI", 15, nil },
    { "No auto-focus for text inputs", 16, nil },
    { "Animations, gizmo perks, drop tables not exposed", 24, nil },
    { "Friends and FC lists only while their window is open", 24, nil },
    { "Library-made components not destroyed on reload", 13, nil },
    { "Dev plugins do not re-enable on login", 11, nil },
}
return D
