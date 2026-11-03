# Draft: FreeRDP issue (not filed)

**Title:** SDL3 RAIL: standalone layered popups (Lightroom flyout menus) suppressed as shadows

**Version:** 3.32.2 (Arch `freerdp 2:3.32.2-1`); the rule is unchanged in 3.33.0 and master.
**Client:** `sdl-freerdp3` RemoteApp (`/app:program:...`), Wayland (Hyprland).
**Server:** Windows 11 Pro (dockurr/windows), RemoteApp with `fDisabledAllowList=1`.

**What happens:** In Adobe Lightroom (cloud version), the sort-order flyout under
the filmstrip and the "..." overflow menu never appear. Native menus (File, Edit)
work. With `WLOG_FILTER='com.freerdp.client.sdl.rail*:TRACE'`, each click logs:

```
[DEBUG][com.freerdp.client.sdl.rail.window] - [reconcile]: shadow-rule suppressed id=0x000f0f1c 182x228 style=0x80000000 ex=0x08080080
[DEBUG][com.freerdp.client.sdl.rail.window] - [reconcile]: shadow-rule suppressed id=0x00130f1c 311x350 style=0x80000000 ex=0x08080080
```

`ex=0x08080080` is `WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TOOLWINDOW`: a layered
popup that takes input and has no adjoining popup, so the `drawable` check in
`SdlRailWindow::reconcile` (`_shadowAnchored || _overlay`) hides it.

**Suggested fix:** don't treat layered windows that take input as shadows. Window
shadows are click-through (`WS_EX_TRANSPARENT`). The local patch
(`sdl-rail-standalone-layered-popups.patch`) adds `|| (_exStyle & WS_EX_TRANSPARENT) == 0`
to that condition.

**Test result with the patch (3.33.0, 2026-11-02):** the sort flyout and the
"..." menu open and work; native menus are unchanged.
