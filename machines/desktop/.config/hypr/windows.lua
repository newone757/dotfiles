-- Custom window rules.
-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/

-- DP-6 colour sliders, launched by `dp6-color --webapp`.
-- Chromium-based browsers ignore --class under Wayland and derive the app_id
-- from the URL, so the window arrives as "brave-127.0.0.1__-Default".
-- Match the class, not the title: rules are evaluated when the window opens,
-- before the page has loaded and set its <title>. Matches are regex, not Lua patterns.
o.window("^brave-127\\.0\\.0\\.1__-Default$", { float = true, center = true, size = { 780, 900 } })

-- Sunshine streaming: while a stream is live, Steam Big Picture and Proton games
-- open on the "stream" workspace (headless "sunshine" output) instead of the
-- desktop. Off otherwise, so local play is untouched. sunshine-stream-begin/end
-- flip them through the StreamRules global; the flag file keeps them correct if
-- the config reloads mid-stream.
local stream_flag = (os.getenv("XDG_RUNTIME_DIR") or "/run/user/1000") .. "/sunshine-streaming"

-- Not during a Desktop-app stream (sunshine-desktop-mode): the whole desktop is
-- on the stream then, so games should open in place.
local desktop_mode_flag = (os.getenv("XDG_RUNTIME_DIR") or "/run/user/1000") .. "/sunshine-desktop-mode"

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

function StreamActive()
  return exists(stream_flag) and not exists(desktop_mode_flag)
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

-- Bambu Studio: its popups (login sync prompt, etc.) can open off-screen,
-- leaving the main window blocked by an invisible modal dialog. Center them.
o.window({ class = "^BambuStudio$", float = true }, { center = true })

-- Windows VM full desktop (omarchy-windows-vm via xfreerdp): maximize it so
-- the single-window square aspect toggle doesn't shrink it to a 2160x2160
-- square on the TV. Maximized keeps the bar and gaps, unlike full screen.
-- A `maximize` window rule didn't take (xfreerdp is XWayland and sets its title
-- after mapping), so do it from events instead.
local function maximize_windows_vm(w)
  if w ~= nil and w.class == "xfreerdp" and tostring(w.title):find("^Windows VM")
     and (w.fullscreen or 0) == 0 then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", window = "address:" .. w.address }))
  end
end
hl.on("window.open", maximize_windows_vm)
hl.on("window.title", maximize_windows_vm)
