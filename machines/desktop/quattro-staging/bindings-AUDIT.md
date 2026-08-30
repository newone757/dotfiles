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

## ⚠️ Collisions to decide (2)

**`SUPER+L`** — you use it for lock + TV off.
Quattro binds it to *Toggle workspace layout* by default. Amusingly, that's
exactly what you had rebound `SUPER+CTRL+L` to, so upstream came to your
conclusion by a different route. Pick one; both are staged in `bindings.lua`
with the alternative commented.

**`SUPER+CTRL+L`** — you use it for workspace layout toggle.
Quattro uses it for **lock**. If you keep your old override, you shadow the
lock screen. Recommendation: drop your override entirely, use Quattro's
`SUPER+L` for layout and `SUPER+CTRL+L` for lock, and put lock+TV-off on
`SUPER+GRAVE` alone.

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
