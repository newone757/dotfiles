# Screensaver inhibit bridge — planned work

**Status:** not started. Written 2026-09-05 after the screensaver kept firing
during a controller-only Steam session.

## Symptom

Playing a Steam game with a wireless controller, the screensaver activates on
the normal 150s timer as if the machine were idle. Keyboard and mouse sessions
are unaffected. This did not happen under Omarchy 3.8.4.

## Why it happens (all verified 2026-09-05)

Three facts stack up:

1. **Controller input is not seat activity.** Hyprland lists only the
   controller's *touchpad* as an input device
   (`guangzhou-...-wireless-controller-touchpad`). The sticks and buttons arrive
   as joystick events (`/dev/input/js0`–`js2`) that libinput does not treat as
   pointer/keyboard activity, so they never reset the compositor's idle timer.
   The compositor is correct that nothing has touched the seat.

2. **Steam's inhibit has no listener.** Steam suppresses the screensaver by
   calling `Inhibit` on `org.freedesktop.ScreenSaver` over D-Bus. Under Quattro
   **nothing owns that name** (`busctl --user list` → no owner), so the call
   goes nowhere.

3. **Quattro only honors Wayland inhibitors.** The shell's idle service sets
   `respectInhibitors: true`
   (`/usr/share/omarchy/shell/plugins/services/idle/Service.qml`), which is
   Quickshell's *Wayland* idle-inhibit handling — a different mechanism from the
   D-Bus name. The running game reports `inhibitingIdle=false` in
   `hyprctl clients`, so it holds no Wayland inhibitor either.

Net: nothing stops the timer, and the controller never resets it.

## Why 3.8.4 was fine

`~/.local/bin/screensaver-inhibit-watch` owned `org.freedesktop.ScreenSaver`,
counted active inhibit cookies into `/tmp/screensaver_inhibit_count`, and every
hypridle listener guarded on `screensaver-inhibited`. hypridle itself ran with
`ignore_dbus_inhibit = true` so it would not double-handle what the daemon
already decided.

That daemon was deliberately quarantined during the Quattro migration (commented
out in `~/.config/hypr/autostart.lua`) because it owns a D-Bus name that the TV
control also depended on, and the plan was to re-evaluate once the system was
up. This is the re-evaluation: it earns its place back, but **not unchanged**.

## Why simply re-enabling it does NOT work

The daemon is passive. It owns the name and writes a count; something else has
to read that count and act. That reader was hypridle, which no longer exists.
Quickshell never consults the file or the D-Bus name, so re-enabling the daemon
as-is changes nothing.

## The work

Turn the passive daemon into an active bridge: own `org.freedesktop.ScreenSaver`
as it does now, and on every transition between "zero inhibitors" and "one or
more", drive Omarchy's own idle toggle:

```
omarchy toggle idle stay-awake    # first inhibitor arrives
omarchy toggle idle allow-idle    # last inhibitor released
omarchy toggle idle status        # for reconciliation
```

(`omarchy toggle idle [toggle|stay-awake|allow-idle|status]` — confirmed present
in 4.0.1.)

Most of the work already exists in `machines/desktop/.local/bin/screensaver-inhibit-watch`
(68 lines, python-dbus): name ownership, cookie tracking, Inhibit/UnInhibit. It
already stores `(app_name, reason)` per cookie — currently only counted, never
inspected — so per-app policy is a small addition rather than a rewrite.

### Things to get right

- **Do not fight the user's manual toggle.** `SUPER+CTRL+I` sets the same state.
  Releasing the last inhibitor should not silently undo a stay-awake the user
  set by hand. Track whether the bridge was the one that enabled it.
- **Crash and restart safety.** If the bridge dies holding stay-awake, the
  machine never idles again. Reconcile against `omarchy toggle idle status` on
  startup and release on clean exit; consider a periodic sanity check.
- **Clients that never release.** A cookie leaks if an app exits without calling
  `UnInhibit`. The current daemon has no owner-tracking; watch
  `NameOwnerChanged` and drop cookies belonging to a departed client.
- **State file location.** `/tmp/screensaver_inhibit_count` predates the move to
  `~/.local/state`; if the file survives at all it belongs under
  `~/.local/state/omarchy/`.
- **Autostart.** Re-enable via `o.launch_on_start` in
  `~/.config/hypr/autostart.lua`, or preferably a user unit like
  lgpowercontrol.service, which is easier to inspect and restart.

### Policy decision to make first

Whether to honor **every** inhibitor or filter by app.

The Aug 2026 design honored all of them, deliberately — including Brave's
"Video Wake Lock", which is the inhibitor behind the original 2026-05
investigation where the screensaver never fired while a YouTube tab was open
(see the idle/sleep notes). By August that was considered correct: a playing
video should hold the screensaver off.

Quattro currently ignores all D-Bus inhibitors, which is why the Brave problem
appears solved — and the same reason Steam is broken. **They are the same
mechanism; you cannot fix Steam without deciding what Brave should do.**

Options:
- **Honor everything** — restores the Aug 2026 behavior exactly. Simplest, and
  matches what was already chosen once. Brave video will again hold off the
  screensaver.
- **Filter by `app_name` / `reason`** — e.g. honor Steam and media players,
  ignore `Video Wake Lock` from browsers. The data is already captured. More
  faithful to intent, but a list to maintain.

## Interim workarounds

- `SUPER+CTRL+I` ("Toggle locking on idle") before a gaming session. Works
  today; needs remembering, and needs turning back off.
- Raise `idle.screensaver` / `idle.lock` in `~/.config/omarchy/shell.json` past
  a typical session. Blunt — it weakens idle everywhere.

## Related

- `machines/desktop/.local/bin/screensaver-inhibit-watch` — the daemon to adapt
- `machines/desktop/.local/bin/screensaver-inhibited` — the `/tmp` count reader,
  obsolete once the bridge drives the toggle directly
- `machines/desktop/.config/hypr/autostart.lua` — where it is currently
  commented out, with the reasoning
