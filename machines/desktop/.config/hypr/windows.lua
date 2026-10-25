-- Custom window rules.
-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/

-- DP-6 colour sliders, launched by `dp6-color --webapp`.
-- Chromium-based browsers ignore --class under Wayland and derive the app_id
-- from the URL, so the window arrives as "brave-127.0.0.1__-Default".
-- Match the class, not the title: rules are evaluated when the window opens,
-- before the page has loaded and set its <title>. Matches are regex, not Lua patterns.
o.window("^brave-127\\.0\\.0\\.1__-Default$", { float = true, center = true, size = { 780, 900 } })

-- Windows VM (omarchy-windows-vm-launch / omarchy-windows-vm launch): open it
-- maximized so it fills the desktop even when single_window_aspect_ratio would
-- square a lone window. Maximized, not fullscreen: the bar and gaps stay, and
-- this is the same state Super+Alt+F ("Full width") toggles by hand.
o.window({ class = "^xfreerdp3?$", title = "^Windows VM - Omarchy$" }, { maximize = true })

-- Sunshine streaming: while a stream is live, Steam Big Picture and Proton games
-- open on the "stream" workspace (headless "sunshine" output) instead of the
-- desktop. Off otherwise, so local play is untouched. sunshine-stream-begin/end
-- flip them through the StreamRules global; the flag file keeps them correct if
-- the config reloads mid-stream.
local stream_flag = (os.getenv("XDG_RUNTIME_DIR") or "/run/user/1000") .. "/sunshine-streaming"

function StreamActive()
  local f = io.open(stream_flag, "r")
  if f then f:close() return true end
  return false
end

StreamRules = {
  hl.window_rule({ name = "stream-proton-games", match = { class = "^steam_app_.*" }, workspace = "name:stream" }),
  hl.window_rule({ name = "stream-big-picture", match = { class = "^steam$", title = "Big Picture" }, workspace = "name:stream" }),
}

function StreamSetRules(on)
  for _, r in ipairs(StreamRules) do r:set_enabled(on) end
end

StreamSetRules(StreamActive())

-- Rules only see a window's initial title. Steam can retitle its main window
-- into Big Picture, so catch that too.
hl.on("window.title", function(w)
  if w ~= nil and StreamActive() and w.class == "steam" and tostring(w.title):find("Big Picture", 1, true)
     and w.workspace and w.workspace.name ~= "stream" then
    hl.dispatch(hl.dsp.window.move({ workspace = "name:stream", window = "address:" .. w.address }))
  end
end)
