# Omarchy 3.8.4 → 4.x "Quattro" — Upgrade Plan

Machine: this desktop. Audited 2026-08-30.
Current: Omarchy **3.8.4**, Hyprland **0.56.0**, btrfs root w/ snapper + Limine, 710G free.

---

## TL;DR

Quattro is not a normal update. It:

- Replaces the **entire shell stack** with one Quickshell process — waybar, walker,
  mako, swayosd, **hyprlock**, **hypridle**, swaybg, polkit-gnome are all *uninstalled*.
- Converts Hyprland config from `.conf` to **Lua**. Your `~/.config/hypr/*.conf`
  files are **not auto-converted** — they are orphaned. Nothing rewrites them for you.
- Repackages Omarchy into pacman packages: `~/.local/share/omarchy` is moved to a
  `.bak` and becomes a symlink to `/usr/share/omarchy`.
- Is explicitly **one-way**: "You cannot downgrade from Quattro." Only rollback is a
  Limine btrfs snapshot.

Your customizations are heavy and concentrated exactly in what Quattro rebuilt.
Budget an afternoon, not ten minutes.

---

## What you actually have (audit results)

### 1. Dotfiles repo — YES, it exists and is good
`~/dotfiles` → `git@github.com:newone757/dotfiles.git`, GNU stow layout,
`machines/desktop/` + `machines/macbook-pro/`. Last commit: *"Sync desktop hypr
config + add lgpowercontrol scripts"*.

**Status: essentially in sync with live.** The only diffs are `.git/index` churn in
vendored theme repos and `omarchy/current/background`. Nothing important has drifted.

⚠️ It is **not** symlinked — the live files are real files, not stow symlinks. So it's
a snapshot/copy workflow, not a live link. Re-sync before you upgrade.

⚠️ Gaps in what it tracks: `~/.local/bin/` (auto-tile, screensaver-inhibit-watch,
theme-hook-update) and `~/.config/omarchy/hooks/theme-set.d/` are **not** in the repo.
Add them.

### 2. `~/omarchy-cybex` — you can ignore this
Third-party post-install script by "John Pals" (github.com/DigitalPals/omarchy-cybex),
cloned Oct 2025. It's *his* personal workflow, not yours.

**Nothing from it is active on your system:**
- keyd macOS shortcuts — service `inactive`, no `/etc/keyd`
- waycorner hot corners — not installed, not running
- Plymouth cybex theme — you're on `omarchy` theme
- starship / screensaver branding / waybar idle indicator — all differ from his
- His `bindings.conf` is completely different from yours

The one thing you took is `~/.local/bin/auto-tile`, which you've since modified
locally. **It is not a dependency. It won't affect the upgrade. You can delete the
clone** (keep `auto-tile` — that's yours now and it's referenced in `autostart.conf`).

### 3. The touchscreen — dead cable or dead touch controller. Not config, not the port.

**Video works, touch USB is silent.** That split is the whole diagnosis:

- `DRM: card2-DP-6: connected` — the panel is powered and driving video fine
- `hyprctl monitors` → `Biomedical Systems Laboratory L2 L2-20230810` present, enabled
- `hyprctl devices` → Touch section **empty**
- Nothing matching `bjyp` / touch in `/dev/input/by-id/` or `/sys/class/input/*/name`

**The port move (USB 2.0 → USB 3.x rear I/O) produced ZERO kernel events.** Not a
failed enumeration — *nothing at all*. For contrast, replugging the Lofree keyboard
minutes earlier logged a clean disconnect/reconnect/enumerate sequence. So the kernel
does log plug events on these ports; it simply never saw an electrical connect from
the touch panel on either one.

That rules out your port-type theory (a good instinct — touch controllers are USB 2.0
HID devices — but on xHCI a USB2 device in a USB3 socket routes to the companion USB2
root hub and works fine either way). It points at: **dead cable, dead touch controller,
or a bad connector at the panel end.** A fully open circuit produces exactly this
silence.

Separately, there's a wedged port: `usb2-port2` has logged
`Cannot enable. Maybe the USB cable is bad?` every ~4 seconds since
`Aug 03 22:08:20` — 58 seconds into a boot that's now 27 days old, **304 occurrences**.
That's the AMD 600-series chipset USB 3.2 controller (`0e:00.0`), and bus 002 has zero
devices on it. Plausibly the same root cause: the panel half-died on that port, wedged
it, and has been dead since.

Next steps, cheapest first:
1. **Reboot.** Clears the wedged xHCI port, and you want a clean reboot before the
   upgrade anyway. 27 days of a stuck port won't self-heal.
2. **Swap the USB cable.** Highest-probability fix given total silence.
3. Test the panel's touch USB on another machine to isolate cable vs. controller.
4. Check whether the panel needs separate power for its touch controller — many do.

Your Hyprland touch config is correct and staged for Quattro either way. Once the
device enumerates as `bjyp-l2-device-bjyp-l2-v1.10`, it maps to DP-6 with no work.
**This is fully independent of the Omarchy upgrade** — don't let it block or delay it.

### 4. Custom work inventory — what has to be migrated

| Area | Files | Quattro impact |
|---|---|---|
| **LG TV power control** | `~/.local/lgpowercontrol/*.sh` + hypridle listeners + 2 keybinds | 🔴 **Breaks hardest** |
| Keybindings | `~/.config/hypr/bindings.conf` (~40 binds) | 🟠 Rewrite to Lua |
| hypridle | `~/.config/hypr/hypridle.conf` (3 listeners, heavily commented) | 🔴 hypridle deleted |
| hyprlock | `~/.config/hypr/hyprlock.conf` | 🔴 hyprlock deleted |
| Trackpad gestures | `~/.config/hypr/scripts/trackpad-gestures` + user unit | 🟢 Independent, should survive |
| Screensaver inhibit | `~/.local/bin/screensaver-inhibit-watch` (owns `org.freedesktop.ScreenSaver`) | 🟠 Likely redundant/conflicting |
| auto-tile | `~/.local/bin/auto-tile` | 🟠 Verify against new window rules |
| Monitors | `monitors.conf` (4K120 TV + 1920x720 DP-6 touchbar) | 🟠 Rewrite to Lua |
| Workspace pinning | in `hyprland.conf` (ws1-5→HDMI-A-2, ws6→DP-6) | 🟠 Rewrite to Lua |
| NVIDIA env vars | in `hyprland.conf` | 🟠 Rewrite to Lua |
| Waybar | `config.jsonc` + `style.css` (~49 line diff) | ⚫ **Waybar is gone.** Rebuild as bar widgets |
| Walker | identical to stock | ⚫ Gone, merged into Omarchy menu |
| Theme hooks | `hooks/theme-set.d/` — 9 scripts (discord, gtk, qt6ct, spotify, zed, cursor, vscode, windsurf, steam) | 🟢 Hook system survives, same layout |
| Custom themes | 22 theme repos in `~/.config/omarchy/themes/` | 🟠 A migration re-stages themes; expect to re-apply |
| Shaders | `~/.config/hypr/shaders/` | 🟠 Verify |

---

## 🔴 The big one: LG TV power control

This is your most fragile customization and it has **no direct equivalent** in Quattro.

**What it depends on today:**
1. `hypridle` listeners with arbitrary `on-timeout` / `on-resume` shell commands —
   *hypridle is removed*. Quattro's idle lives inside Quickshell and is configured by
   two integers in `~/.config/omarchy/shell.json`:
   ```json
   { "version": 1, "idle": { "screensaver": 150, "lock": 300 } }
   ```
   **There is no `on-timeout` command hook.** Confirmed: Quattro's hook events are only
   `battery-low`, `font-set`, `post-boot`, `post-update`, `pre-refresh-pacman`,
   `theme-set`. No idle, no lock, no wake.
2. `pgrep -x hyprlock` — used in `wake-displays-on-activity.sh` and in your
   `SUPER+L` binding's wait loop. *hyprlock is removed.* Both will silently no-op.
3. `after_sleep_cmd` in `hypridle.conf` doing the WoL + monitor re-enable dance — gone.

**What survives and is your migration path:**
- `~/.local/lgpowercontrol/lgpowercontrol-dbus-events.sh` — this listens to
  `org.freedesktop.ScreenSaver` D-Bus signals, **not** hypridle. It's autostarted as a
  user unit and is architecturally independent. If Quattro's Quickshell lock emits
  standard ScreenSaver signals, **this keeps working**. Test this first — it may carry
  most of the load on its own.
- `omarchy-system-lock`, `omarchy-system-wake`, `omarchy-launch-screensaver` all still
  exist in 4.0.1.
- `omarchy-hyprland-session-locked` (new) — a lock-state query you can poll instead of
  `pgrep -x hyprlock`.
- `/usr/lib/systemd/system-sleep/` — still the right place for suspend/resume hooks.
- `omarchy-system-sleep-monitor` + `omarchy-sleep-lock.service` (new).

**Plan:** rebuild TV control as a small **standalone daemon** driven by D-Bus
lock/unlock signals rather than hooked into the compositor's idle daemon. That's more
robust anyway and would have survived this upgrade untouched.

---

## Pre-upgrade checklist

### A. Fix the touchscreen first (hardware)
Plug in the touch USB, confirm `hyprctl devices` shows a Touch device. Do this now so
it's a known-good baseline.

### B. Commit everything to dotfiles
```bash
cd ~/dotfiles
# add the untracked bits first:
mkdir -p machines/desktop/.local/bin machines/desktop/.config/omarchy/hooks
cp ~/.local/bin/{auto-tile,screensaver-inhibit-watch,screensaver-inhibited,theme-hook-update} \
   machines/desktop/.local/bin/
cp -r ~/.config/omarchy/hooks/theme-set ~/.config/omarchy/hooks/theme-set.d \
   machines/desktop/.config/omarchy/hooks/
# re-sync live configs
cp ~/.config/hypr/*.conf machines/desktop/.config/hypr/
cp -r ~/.config/hypr/scripts machines/desktop/.config/hypr/
cp ~/.config/waybar/config.jsonc ~/.config/waybar/style.css machines/desktop/.config/waybar/
git add -A && git commit -m "Pre-Quattro snapshot of Omarchy 3.8.4 config" && git push
git tag pre-quattro-3.8.4 && git push --tags
```
The `pre-quattro-3.8.4` tag is your reference for rewriting things in Lua.

### C. Package + system inventory (so you can diff after)
```bash
mkdir -p ~/pre-quattro-inventory && cd ~/pre-quattro-inventory
pacman -Qqe            > pkgs-explicit.txt
pacman -Qqm            > pkgs-aur.txt
systemctl --user list-unit-files --state=enabled > units-user.txt
systemctl list-unit-files --state=enabled        > units-system.txt
omarchy menu keybindings --print > keybindings.txt
hyprctl monitors > monitors.txt; hyprctl devices > devices.txt
omarchy debug --no-sudo --print > omarchy-debug.txt
cp /etc/pacman.conf /etc/pacman.d/mirrorlist /boot/limine.conf .
```
You have 32 AUR packages including `davinci-resolve`, `xrdp`, `coolercontrol`,
`streamcontroller`, `winboat-bin`. The upgrade runs `omarchy-update-aur-pkgs` — expect
some AUR churn against the new package set.

### D. Verify snapshot rollback actually works
This is your **only** rollback. Don't assume — verify:
```bash
sudo snapper -c root list          # confirm snapshots exist and are recent
sudo btrfs subvolume list /        # confirm layout
grep -i snapshot /boot/limine.conf # confirm Limine offers the snapshot menu
```
You have `limine-snapper-notify` running, so this is likely healthy. Confirm you can
*see* the "System Snapshots" entry at boot before you rely on it.

### E. Real backup of the irreplaceable
Snapshots are on the same disk. Off-machine copy of: `~/.ssh`, `~/.gnupg`,
`~/Projects`, `~/documents`, `~/dotfiles` (pushed ✅), browser profiles, and
`~/.local/lgpowercontrol/`. You have `~/unraid_backup` and a server at 10.0.1.10 —
use it.

### F. Read the release notes yourself
- https://github.com/basecamp/omarchy/releases/tag/v4.0.0
- Quattro manual (Lua config chapters + hooks)

---

## Upgrade procedure

`v4.0.1` is tagged and on the stable channel. Your 3.8.4 install does **not** yet have
`omarchy-upgrade-to-quattro` locally, but `origin/master` does — so:

```bash
# 1. Get current on 3.8.x first (pulls in the upgrade command)
omarchy update

# 2. Confirm the upgrade command landed
omarchy upgrade to quattro --help

# 3. Do it — on ethernet, with nothing else running
omarchy upgrade to quattro
```

**Never run `pacman -Syu` / `yay -Syu` directly.** Omarchy blocks it; it skips the
pre-update snapshot and migrations.

### What the script does (read from source, v4.0.1)
Creates a pre-upgrade snapshot → rewrites pacman mirrorlist/repos → removes the legacy
installer + conflicting packages → installs Quattro packages → normalizes Limine config
and **verifies `root=` is in the kernel cmdline** → moves `~/.local/share/omarchy` to
`.bak` and symlinks to `/usr/share/omarchy` (with a temporary shim so your live legacy
session doesn't explode mid-upgrade) → disables retired user units → removes retired
packages (`waybar`, `mako`, `walker`, `hypridle`, `hyprlock`, …) → runs migrations →
final `pacman -Syu` → reboot.

### 🚨 Two hard rules
1. **If it errors, DO NOT REBOOT.** The script says so explicitly: a half-upgraded
   machine "can leave it without a working network or desktop." Re-running is safe and
   resumes.
2. **Read the output before rebooting.** It prints
   `WARNING: You must address any errors in the above before rebooting.`

---

## Post-upgrade rebuild order

### 1. Boot & triage
Expect: default bar, default bindings, your `.conf` files present but **inert**.
```bash
omarchy debug --no-sudo --print
hyprctl configerrors
omarchy debug idle
```

### 2. Port Hyprland config to Lua
New structure — `~/.config/hypr/hyprland.lua` requires `hypr.monitors`, `hypr.input`,
`hypr.bindings`, `hypr.looknfeel`, `hypr.autostart` (all `.lua`).

Translation reference:
| 3.x `.conf` | 4.x `.lua` |
|---|---|
| `bind = SUPER, Q, killactive` | `o.bind("SUPER + Q", "Close", ...)` |
| `unbind = SUPER, W` | `hl.unbind("SUPER + W")` |
| `monitor = HDMI-A-2, 3840x2160@120, 0x0, 1` | `hl.monitor({ output = "HDMI-A-2", mode = "3840x2160@120", position = "0x0", scale = 1 })` |
| `input { ... }` | `hl.config({ input = { ... } })` |
| `windowrule = match:class X, ...` | `o.window("X", { ... })` |
| `env = FOO,bar` | `hl.env("FOO", "bar")` |
| `exec-once = cmd` | `o.launch_on_start("cmd")` (in `autostart.lua`) |

Good news: **almost every command your bindings call still exists in 4.0.1** —
`omarchy-launch-webapp`, `-or-focus`, `-or-focus-webapp`, `-or-focus-tui`,
`-launch-tui`, `-launch-editor`, `-launch-browser`, `-cmd-terminal-cwd`,
`-system-lock`, `-system-wake`, `-hyprland-workspace-layout-toggle`,
`-brightness-keyboard`. Only **`omarchy-cmd-screenshot` is gone** (→ `omarchy-capture-screenshot`).

### 3. Known binding conflicts to resolve
| Your 3.x binding | Quattro default | Action |
|---|---|---|
| `SUPER+CTRL+SHIFT+I` restart hypridle | — | **Delete.** hypridle is gone. `SUPER+Ctrl+I` is now `toggle idle` |
| `SUPER+L` custom lock+TV-off | `Super+Ctrl+L` = lock; `Super+L` = workspace layout | Rebind deliberately |
| `SUPER+CTRL+L` workspace layout toggle | Now the **lock** binding | Conflict — pick one |
| `SUPER+Q` killactive (you unbound `SUPER+W`) | Verify against new defaults | Re-check |
| `SUPER+SHIFT+K/L` TV on/off | — | Keep, point at rebuilt scripts |

### 4. Rebuild idle + TV control
```bash
# set timings
$EDITOR ~/.config/omarchy/shell.json   # {"idle":{"screensaver":150,"lock":300}}
```
Then, in order:
1. **Test whether `lgpowercontrol-dbus-events.sh` still fires.** Lock the machine
   (`Super+Ctrl+L`) and watch `journalctl -t lgpowercontrol-dbus-events -f`. If the
   Quickshell lock emits `org.freedesktop.ScreenSaver` signals, you're 80% done.
2. Replace every `pgrep -x hyprlock` with `omarchy-hyprland-session-locked`.
3. Re-evaluate `screensaver-inhibit-watch` — it *owns* `org.freedesktop.ScreenSaver`
   to defeat hypridle's dbus inhibit. Quattro's shell has its own inhibitor handling,
   so this may now **conflict**. Test with it disabled first.
4. Move TV power-off out of the compositor entirely — a standalone user service on
   D-Bus lock/unlock + a `/usr/lib/systemd/system-sleep/` hook for suspend/resume.

### 5. Rebuild the bar
Waybar config is dead weight. Your customizations were small (btop right-click,
weather interval 3600, bluetooth glyph order, idle indicator, 49-line CSS diff).
Rebuild with `omarchy bar` widgets + `~/.config/omarchy/shell.json`. Don't try to port
the CSS.

### 6. Verify the rest
- `systemctl --user status trackpad-gestures` (should be untouched)
- Re-apply theme: `omarchy theme set <name>` — a migration re-stages themes
- Theme hooks: layout is unchanged (`hooks/theme-set.d/`), but note Quattro adds
  `omarchy hook install <name> <script>`. Verify all 9 still run.
- Touchscreen: `omarchy toggle touchscreen` is now a first-class feature; the device
  name now lives in `~/.local/state/omarchy/toggles/hypr/touchscreen-disabled-name`
- NVIDIA: confirm your forced-nvidia env vars are still needed under 0.56+
- Terminal default changed **Alacritty → Foot**
- Wi-Fi: **iwd → NetworkManager** (you're wired, low risk)
- Privilege escalation → pkexec/polkit

---

## Staged work (done 2026-08-30, pre-upgrade)

`~/quattro-staging/` holds Lua configs written *before* the upgrade, so the
keybinding-rediscovery problem you hit on the MacBook doesn't repeat:

| File | Contents |
|---|---|
| `hypr/bindings.lua` | 6 genuinely-custom bindings + 2 flagged collisions |
| `hypr/input.lua` | Only real deltas from Quattro defaults; gestures, device maps |
| `hypr/monitors.lua` | TV + touch strip layout; workspace pinning flagged, not guessed |
| `hypr/autostart.lua` | trackpad-gestures, auto-tile; screensaver-inhibit-watch quarantined |
| `hypr/hyprland.lua.additions` | NVIDIA env vars to append (not a drop-in file) |
| `bindings-AUDIT.md` | Full 3.8.4-vs-4.0.1 binding diff |

**The big finding: 21 of your ~30 custom bindings are now Quattro defaults.** Your
config had converged with upstream. The real port is 6 bindings plus 2 collision
decisions — much smaller than it looked.

Copy them in *after* the upgrade, not before:
```bash
cp ~/quattro-staging/hypr/*.lua ~/.config/hypr/
# then hand-merge hyprland.lua.additions into the stock hyprland.lua
hyprctl reload && hyprctl configerrors
```

## Recommendation

**Go, once you've done A–F and rebooted.** 4.0.1 is out, your MacBook already
survived the same upgrade, and the binding port is far smaller than feared.

Your MacBook experience maps onto this machine as: *gestures were mostly handled
automatically* (matches — your trackpad daemon is a standalone systemd unit,
compositor-independent), and *keybindings needed piecemeal restoration* (now
pre-solved by the staged files above).

The one thing the MacBook did **not** rehearse is the LG TV / hypridle / waybar
cluster. That's where your remaining risk is concentrated, and it's the part to
budget real time for.

## Rollback
Reboot → Limine menu → **System Snapshots** → the snapshot taken immediately before
the upgrade. There is no `omarchy downgrade`.
