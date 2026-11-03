# Windows apps as their own windows (RemoteApp) — parked

Tried on 2026-11-02, then parked in favour of the full Windows desktop
(`omarchy-windows-vm-launch`, the "Windows" launcher entry). Nothing in this
folder is stowed; it is kept so the setup can be picked up again.

The look was good: Lightroom and Capture One each opened as a normal Hyprland
window, with the real app icon in the launcher, tiling and resizing like a
native app.

## What is here

| File | What it is |
|------|------------|
| `windows-app` | Launcher: `windows-app lightroom \| captureone \| 'C:\path.exe'`. Starts the VM if needed, opens one program via RDP RemoteApp. |
| `windows-lightroom.desktop`, `windows-captureone.desktop` | Launcher entries (`Exec=uwsm app -- windows-app ...`). |
| `icons/` | 256 px icons pulled from each exe's resources with `7z`. |
| `laptop-desktop-windows-app` | MacBook version over an SSH tunnel. Never tested. |
| `freerdp-sdl-patch/` | Patch and `build.sh` for FreeRDP's SDL client, plus a draft upstream issue (not filed). |

To bring it back: move `windows-app` to `../.local/bin/`, the `.desktop` files to
`../.local/share/applications/`, the icons to
`../.local/share/icons/hicolor/256x256/apps/` (keep `~/.local/share/icons` a real
directory so stow doesn't fold it), then `stow` the package again.

## Guest-side requirement

RemoteApp for programs that aren't on an allow list:
`../windows-guest/enable-remoteapp.reg` (`fDisabledAllowList=1`). It was
imported in the guest and is still set; it does nothing for the full desktop.

## What worked

- **Client:** `sdl-freerdp3` (native Wayland). Windows follow every Hyprland
  tile or float resize. Window class is `com.freerdp.client.sdl3`, title is
  the program's own.
- **Flyouts:** stock `sdl-freerdp3` hides Lightroom's sort-order flyout and the
  "…" overflow menu. Its RemoteApp code treats every layered popup that isn't
  next to another popup as a menu shadow (`shadow-rule suppressed ... ex=0x08080080`
  with `WLOG_FILTER=com.freerdp.client.sdl.rail:TRACE,com.freerdp.client.sdl.rail.window:TRACE`).
  The patch also shows layered windows that aren't `WS_EX_TRANSPARENT`. Built
  against 3.33.0 into `~/.local/opt/freerdp-sdl`, and the flyouts then worked.
- Native menus (File, Edit) worked even with the stock client. They are Wayland
  popups, so they never show in `hyprctl clients`; that is not evidence of a
  missing window.
- Capture One's "back up before closing?" dialog is an untitled window. Any rule
  that hides untitled windows hides it, and the quit then hangs.
- Lightroom imports from SD cards worked (the card shows in the shared folder under `media`,
  via Choose Folder).

## What didn't

- **`xfreerdp3`:** RemoteApp windows go through XWayland and Windows never sees a
  resize. With `/gfx:AVC444` the windows were black.
- **Sessions — the reason it was parked.** Windows 11 Pro allows one connection.
  The full desktop got its own session (3), separate from the RemoteApp session
  (2). Apps running in app mode weren't visible from the full desktop. That risks
  a second Lightroom on the same catalog, and switching modes brought up a
  full-screen Windows sign-in for a while. Using both modes side by side doesn't
  work cleanly; one mode or the other does.
- One RemoteApp connection carries every open app. Reconnecting for one app
  redraws all of them.
- **Seen twice, cause unknown:** while a dialog was open (Lightroom import), the
  main window drew only its top-left corner. Relaunching fixed it.
- The 35-second "Please wait for …\lonnie" screen came from autologon holding a
  console session. Fixed by `../windows-guest/disable-autologon.reg`, which helps
  the full desktop too.

## Ideas if this comes back

- Use RemoteApp only and drop the full-desktop entry, so there is only ever one
  session.
- Check whether FreeRDP upstream fixed the layered-popup rule. If so, drop the
  patch and use the packaged `sdl-freerdp3`. If not, file `upstream-issue.md`.
- The laptop would need the patched client built for aarch64.
