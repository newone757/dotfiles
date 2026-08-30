# Keybinding audit: your 3.8.4 config vs Omarchy 4.0.1 defaults

Generated 2026-08-30 by diffing `~/.config/hypr/bindings.conf` against
`default/hypr/bindings/{applications,tiling,utilities}.lua` at tag `v4.0.1`.

**Headline: 21 of your ~30 custom bindings became Quattro defaults.**
You had been tracking upstream closely enough that your config largely
converged with what shipped. The real porting job is 6 bindings, not 30.

---

## ✅ Now defaults — do NOT re-add (21)

Identical key *and* identical action in Quattro:

| Binding | Action |
|---|---|
| `SUPER+RETURN` | Terminal |
| `SUPER+SHIFT+RETURN` | Browser |
| `SUPER+ALT+RETURN` | Tmux |
| `SUPER+SHIFT+F` | File manager |
| `SUPER+SHIFT+B` | Browser |
| `SUPER+SHIFT+ALT+B` | Browser (private) |
| `SUPER+SHIFT+M` | Music (Spotify) |
| `SUPER+SHIFT+ALT+M` | Music TUI (cliamp) |
| `SUPER+SHIFT+N` | Editor |
| `SUPER+SHIFT+D` | Docker |
| `SUPER+SHIFT+G` | Signal |
| `SUPER+SHIFT+O` | Obsidian |
| `SUPER+SHIFT+slash` | Passwords (1Password) |
| `SUPER+SHIFT+ALT+A` | Grok |
| `SUPER+SHIFT+C` | Calendar (hey.com) |
| `SUPER+SHIFT+E` | Email (hey.com) |
| `SUPER+SHIFT+Y` | YouTube |
| `SUPER+SHIFT+ALT+G` | WhatsApp |
| `SUPER+SHIFT+CTRL+G` | Google Messages |
| `SUPER+SHIFT+X` | X |
| `SUPER+SHIFT+ALT+X` | X Post |

Note the *syntax* changed even where behavior didn't — Quattro uses semantic
descriptors (`{ omarchy = "spotify" }`, `{ webapp = "..." }`, `{ tui = "...",
focus = true }`) instead of raw `exec` strings. Let the defaults handle these;
they'll keep working as upstream evolves.

---

## 🔧 Genuinely custom — ported into `bindings.lua` (6)

| Binding | Why it needs porting |
|---|---|
| `SUPER+SHIFT+A` → Claude | Quattro default is ChatGPT; needs unbind + rebind |
| `SUPER+SHIFT+R` → Reddit | Not a Quattro default |
| `SUPER+SHIFT+H` → Home (ha-fusion) | Not a Quattro default |
| `SUPER+Q` → Close window | Quattro closes with `SUPER+W`; needs unbind + rebind |
| `SUPER+SHIFT+T` → btop | Quattro moved `SUPER+T` to float/tile toggle |
| `SUPER+SHIFT+K` / `SUPER+SHIFT+L` → TV on/off | Custom scripts |

---

## ✅ Collisions — RESOLVED 2026-08-30

| Key | Decision | Result |
|---|---|---|
| `SUPER+SHIFT+A` | **Claude wins** | unbind default, rebind to claude.ai. ChatGPT left unbound. |
| `SUPER+W` / `SUPER+Q` | **`SUPER+Q` wins** | unbind Quattro's `SUPER+W`, close on `SUPER+Q`. |
| `SUPER+L` | **Full stock** | Quattro's *Toggle workspace layout*. No override. |
| `SUPER+CTRL+L` | **Full stock** | Quattro's *Lock system*. No override. |
| `SUPER+SHIFT+T` | **Dropped** | use Quattro's `SUPER+CTRL+T` for Activity/btop. |

Net: **3 overrides total** (`SHIFT+A`, `W`→`Q`, plus 3 additive bindings that
collide with nothing). Down from ~30 lines of custom config.

### The one consequence to handle

Taking full stock on the L keys means **`SUPER+CTRL+L` is a plain lock that
doesn't touch the TV.** So is every other lock path — idle timeout, the system
menu, `omarchy system lock`.

**Do not fix this with a keybinding override.** Fix it by driving TV power from
the *lock event* instead of the keystroke, so all lock paths behave identically.
That's what `lgpowercontrol-dbus-events.sh` already does — it listens on
`org.freedesktop.ScreenSaver` and is compositor-independent, which is precisely
why it stands a good chance of surviving Quattro untouched.

This decision makes that D-Bus daemon **load-bearing rather than optional**. It
is now the first thing to verify after upgrading:

```bash
# press SUPER+CTRL+L, then:
journalctl -t lgpowercontrol-dbus-events -f
```

If the Quickshell lock doesn't emit ScreenSaver signals, the fallback is to poll
`omarchy-hyprland-session-locked` from that same daemon. Either way the logic
lives in one place, off the compositor — which is the architecture the whole
upgrade has been pushing toward anyway.

`SUPER+GRAVE` stays bound to an explicit lock + TV off as a fallback while you
verify. It becomes redundant once the D-Bus path is confirmed.

---

## 🗑️ Retired — do not restore (2)

**`SUPER+CTRL+SHIFT+I`** "Restart idle daemon"
`hypridle` is uninstalled by the upgrade. There is no daemon to restart — idle
lives inside the Quickshell process. Quattro's `SUPER+CTRL+I` is
*Toggle locking on idle* (stay-awake), which is a different thing.

This binding existed because of a long-running intermittent idle bug on this
machine. Worth watching whether Quattro's rewritten idle path makes the
underlying problem moot — that would be a genuine win from the upgrade.

**Trailing `# Alt+Scroll to cycle browser tabs` comment**
There is no binding under it in your current config. Nothing to port.

---

## Commands verified present in 4.0.1

Every command your bindings invoke still exists, with one exception:

`omarchy-launch-webapp`, `omarchy-launch-or-focus`, `omarchy-launch-or-focus-webapp`,
`omarchy-launch-or-focus-tui`, `omarchy-launch-tui`, `omarchy-launch-editor`,
`omarchy-launch-browser`, `omarchy-cmd-terminal-cwd`, `omarchy-system-lock`,
`omarchy-system-wake`, `omarchy-hyprland-workspace-layout-toggle`,
`omarchy-brightness-keyboard`, `omarchy-launch-screensaver` — all ✅

`omarchy-cmd-screenshot` — ❌ **gone**, replaced by `omarchy-capture-screenshot`.
You don't currently bind it (it's in the cybex repo's bindings, not yours), so
no action needed — but note it if you copy anything from that clone.

---

## How to verify after upgrading

```bash
omarchy menu keybindings --print > /tmp/keybindings-after.txt
diff ~/pre-quattro-inventory/keybindings.txt /tmp/keybindings-after.txt
```

That diff is the honest answer to "what did I lose", and it's the check that
would have saved you the piecemeal rediscovery you hit on the MacBook.
