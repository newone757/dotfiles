# LG TV as primary monitor — power & HDMI handshake control

The LG TV is the primary display (`HDMI-A-2`, 3840x2160@120). Because it's a TV
rather than a monitor, it doesn't sleep/wake like a normal display — these scripts
make it behave like one.

| | |
|---|---|
| TV IP | `10.0.1.28` |
| MAC (WoL) | `00:a1:59:35:35:da` |
| Hyprland output | `HDMI-A-2` (HDMI 1 on the TV) |
| Secondary display | `DP-6` — Biomedical Systems Laboratory L2 touch strip |
| WebOS CLI | `bscpylgtv/bin/bscpylgtvcommand` (venv, gitignored — reinstall with `pip install --target ... bscpylgtv`) |

**This implementation works well.** It took several iterations to get there, and the
non-obvious findings below are the reason it works. Read them before changing
anything.

---

## Current design (rewritten Aug 2026)

Three idle stages, all driven by `hypridle` listeners in `~/.config/hypr/hypridle.conf`:

| Stage | Timeout | Action |
|---|---|---|
| Screensaver | 150s | `omarchy-launch-screensaver`, skipped if a browser Video Wake Lock is active |
| **Lock + blank** | 152s | `turn_screen_off` — TV **stays fully powered**, panel blanks. `dpms off DP-6` only |
| Safety lock | 3600s | Real `power_off`. Unconditional — catches "left the PC with video playing" |

Resume for all stages: `omarchy-system-wake; tv-on.sh`

### An earlier design was replaced — do not reintroduce it

Until May 2026 this used `power_off` plus
`hyprctl keyword monitor HDMI-A-2,disable` on every idle lock. **That is not what
runs now, and going back to it reintroduces bugs that were deliberately engineered
away:**

- **Why `turn_screen_off` instead of `power_off`** on the normal path: the TV stays
  fully powered, so resume is an instant `turn_screen_on` with no WoL race and no
  HDMI re-handshake. `power_off` is reserved for the 60-minute safety listener where
  real power savings are worth a slow wake.
- **Why HDMI-A-2 is left alone** (only `DP-6` gets DPMS'd): once the TV stays
  powered rather than being switched off, cutting its HDMI signal makes it display a
  "No Signal" banner instead of going quiet. The blank is scoped to WebOS instead.
- **Why the `sleep 3` before `turn_screen_off`:** sending it while the lock surface
  is still mid-setup on HDMI-A-2 triggers an HDMI renegotiation that flips the TV
  back to "signal active" and undoes the blank.

---

## Scripts

| Script | Role |
|---|---|
| **`tv-on.sh`** | **Primary resume path.** Takes a `flock`, reads `get_power_state`, then: `Active` → exit; `Screen Off` → fast-path `turn_screen_on`; otherwise → fall back to `wake-hdmi.sh` |
| `tv-off.sh` | Full `power_off` (deep standby) |
| `wake-hdmi.sh` | Cold-boot path: 3× WoL burst → unconditional 4s wait → poll `get_inputs` up to 10s → DPMS off/on cycle on HDMI-A-2 to force renegotiation |
| `wake-displays-on-activity.sh` | While locked, reads `libinput debug-events` for real input and wakes both displays early, without waiting for a full unlock |
| `lgpowercontrol-dbus-events.sh` | Listens on `org.freedesktop.ScreenSaver` for lock/unlock and powers the TV off/on. **Compositor-independent**, autostarted as a user unit |
| `wake-tv.sh` | **Vestigial.** Still uses the ruled-out `monitor,disable` handshake. Nothing references it — safe to delete |

### Why `wake-displays-on-activity.sh` exists

Hyprland suppresses monitor wake-on-input entirely while the session is held by
`ext-session-lock`. This affects **every** output, not just the TV — `DP-6` doesn't
auto-wake on activity while locked either; only Hyprland's own resume-on-unlock does.
`libinput` reads raw evdev directly, bypassing that suppression, so both wakes are
driven manually here.

---

## Hard-won findings

These cost real debugging time. They're still true.

- **`hyprctl keyword monitor HDMI-A-2,disable` does not drop the HDMI signal** at the
  hardware level. It stops the compositor rendering, but the TV stays "connected" and
  won't renegotiate. `hyprctl dispatch dpms off/on` **does** cut the signal and force
  EDID/TMDS renegotiation. The DPMS cycle is the real handshake fix.

- **`turn_screen_on` is NOT idempotent.** It hard-errors (`errorCode -102`,
  *"current sub state must be 'screen off'"*) if the TV is already `Active`. Always
  check `get_power_state` first — without that check, a redundant call right after
  the TV is already on fails its fast path and falls through to the slow WoL+DPMS
  sequence for no reason. `tv-on.sh` can be called more than once per wake (the
  activity watcher and the unlock fallback both fire), hence the `flock` too.

- **WebOS `get_inputs` `connected` is always true when the cable is plugged in.** It
  is not signal-sensitive. LG confirmed there is no public API that distinguishes
  "cable connected" from "signal active" — which is why detect-then-handshake was
  abandoned.

- **Port 3000 (WebOS WebSocket) stays open even when the TV is off** (soft standby),
  so a reachability check can return true before the TV is HDMI-ready. Hence the
  unconditional 4-second minimum wait in `wake-hdmi.sh` before polling.

- **CEC is unavailable** — the NVIDIA proprietary driver doesn't expose `/dev/cec*`.

- **Windows do not shuffle** when HDMI-A-2 is disabled for extended periods.

---

## ⚠️ Omarchy 4 "Quattro" breaks this

Quattro **deletes `hypridle` and `hyprlock`**. Specifically:

1. The three listeners above have no equivalent. Quattro's idle lives inside the
   Quickshell process and is configured by two integers in
   `~/.config/omarchy/shell.json` (`screensaver`, `lock`) — **no `on-timeout`
   command hook**. Available hooks are only `battery-low`, `font-set`, `post-boot`,
   `post-update`, `pre-refresh-pacman`, `theme-set`.
2. Every `pgrep -x hyprlock` check breaks **silently** — the process simply never
   exists, so guarded scripts exit at line one and do nothing.
3. `OMARCHY_LOCK_ONLY` no longer exists (zero references in 4.0.1).

**Migration path:** `lgpowercontrol-dbus-events.sh` is already event-driven off
`org.freedesktop.ScreenSaver` and compositor-independent, so it should survive — and
it becomes the load-bearing piece rather than a helper. Replace lock-state checks
with `omarchy-hyprland-session-locked` (exit `0` locked, `1` unlocked, `2`
undetermined; treat `2` as unlocked).

Ported scripts are staged at `machines/desktop/quattro-staging/lgpowercontrol/`.
Full plan: `machines/desktop/omarchy4-upgrade-plan.md`.

**Also note:** `~/.local/bin/screensaver-inhibit-watch` owns the
`org.freedesktop.ScreenSaver` D-Bus name — the same name
`lgpowercontrol-dbus-events.sh` listens on. On Quattro that's a potential conflict,
so it's quarantined in the staged `autostart.lua`. Bring the system up without it
first.
