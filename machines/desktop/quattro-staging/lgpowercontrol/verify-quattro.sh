#!/bin/bash
# Post-upgrade verification for the LG TV control rebuild.
# Run this AFTER upgrading to Quattro, BEFORE trusting the daemon.
#
# Every check states what it assumes and what to do if it fails. Nothing here
# changes system state except the two interactive TV tests at the end, which
# prompt first.

BSCPYLGTV="$HOME/.local/lgpowercontrol/bscpylgtv/bin/bscpylgtvcommand"
TV_IP=10.0.1.28

pass=0; fail=0; warn=0
ok()   { echo "  ✅ $*"; ((pass++)); }
bad()  { echo "  ❌ $*"; ((fail++)); }
note() { echo "  ⚠️  $*"; ((warn++)); }

echo "=============================================="
echo " LG TV control — Quattro verification"
echo "=============================================="

# ---------------------------------------------------------------------------
echo
echo "[1] Commands the daemon depends on"
for c in omarchy-hyprland-session-locked hyprctl jq logger wakeonlan; do
  if command -v "$c" >/dev/null 2>&1; then ok "$c present"
  else bad "$c MISSING — daemon cannot work without it"; fi
done
[[ -x $BSCPYLGTV ]] && ok "bscpylgtvcommand present" \
  || bad "bscpylgtvcommand missing — reinstall the venv: pip install --target ... bscpylgtv"

# ---------------------------------------------------------------------------
echo
echo "[2] Lock-state detection (the daemon's single source of truth)"
omarchy-hyprland-session-locked 2>/dev/null
case $? in
  127) bad "command not found — you are not on Quattro yet, or the install is broken" ;;
  0) note "reports LOCKED — expected while unlocked. Re-run from an unlocked session." ;;
  1) ok "reports UNLOCKED, as expected right now" ;;
  2) note "reports UNDETERMINED (exit 2). Treated as unlocked. If this is
       persistent rather than transient, the daemon will never fire — check
       'hyprctl -j monitors' has a solitaryBlockedBy field." ;;
esac

# ---------------------------------------------------------------------------
echo
echo "[3] Idle configuration (Quattro owns this now, not hypridle)"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
if [[ -f $SHELL_JSON ]]; then
  ok "shell.json exists"
  if jq -e '.idle' "$SHELL_JSON" >/dev/null 2>&1; then
    echo "     idle config: $(jq -c '.idle' "$SHELL_JSON")"
    lock_to=$(jq -r '.idle.lock // 300' "$SHELL_JSON")
    echo "     -> set DEEP_AFTER_LOCK_SECS to $((3600 - lock_to)) to match the"
    echo "        old 3600s-of-idle deep power-off"
  else
    note "no 'idle' block — shell defaults apply (screensaver 150s, lock 300s)"
  fi
else
  note "shell.json not found; defaults apply. Create it to tune idle timings."
fi

# ---------------------------------------------------------------------------
echo
echo "[4] Retired 3.8.4 dependencies — these MUST be gone"
for c in hypridle hyprlock; do
  if command -v "$c" >/dev/null 2>&1; then
    note "$c still installed. Harmless if unused, but make sure nothing starts
       it — a second idle daemon would fight the Quickshell shell."
  else ok "$c gone, as expected"; fi
done
if grep -rlq 'pgrep -x hyprlock' "$HOME/.local/lgpowercontrol/" 2>/dev/null; then
  bad "'pgrep -x hyprlock' still present in lgpowercontrol scripts — these will
       FAIL SILENTLY (the process never exists). Copy the ported versions from
       quattro-staging/."
else
  ok "no stale 'pgrep -x hyprlock' checks remain"
fi

# ---------------------------------------------------------------------------
echo
echo "[5] D-Bus lock signals (does the OLD event-driven path still work?)"
if systemctl --user is-active app-lgpowercontrol\\x2ddbus\\x2devents@autostart.service >/dev/null 2>&1; then
  note "lgpowercontrol-dbus-events.sh is RUNNING alongside the new daemon.
       Both would drive the TV. Pick one — disable this if using the daemon."
else
  ok "old D-Bus watcher not running"
fi
echo "     To test whether Quickshell emits ScreenSaver signals at all:"
echo "       dbus-monitor --session \"interface='org.freedesktop.ScreenSaver'\" &"
echo "       # then lock with SUPER+CTRL+L and watch for a 'boolean true'"
echo "     If signals DO fire, the event-driven path is viable and cheaper"
echo "     than polling."

# ---------------------------------------------------------------------------
echo
echo "[6] screensaver-inhibit-watch conflict check"
if pgrep -f screensaver-inhibit-watch >/dev/null 2>&1; then
  note "screensaver-inhibit-watch is RUNNING. It OWNS org.freedesktop.ScreenSaver,
       the same name the D-Bus TV watcher listens on, and Quattro's shell has
       its own inhibitor handling. This is the quarantined daemon — stop it and
       re-test if lock/idle behaves oddly."
else
  ok "screensaver-inhibit-watch not running (correctly quarantined)"
fi

# ---------------------------------------------------------------------------
echo
echo "[7] Daemon install state"
[[ -x $HOME/.local/lgpowercontrol/lgpowercontrol-daemon.sh ]] \
  && ok "daemon script installed and executable" \
  || note "daemon not installed yet — copy from quattro-staging/lgpowercontrol/"
if systemctl --user list-unit-files lgpowercontrol.service >/dev/null 2>&1 &&
   systemctl --user is-enabled lgpowercontrol.service >/dev/null 2>&1; then
  ok "lgpowercontrol.service enabled"
  systemctl --user is-active lgpowercontrol.service >/dev/null 2>&1 \
    && ok "lgpowercontrol.service active" \
    || note "unit enabled but not active — check: systemctl --user status lgpowercontrol"
else
  note "lgpowercontrol.service not enabled yet"
fi

# ---------------------------------------------------------------------------
echo
echo "[8] TV reachability"
if timeout 3 "$BSCPYLGTV" "$TV_IP" get_power_state >/dev/null 2>&1; then
  ok "TV responding at $TV_IP — state: $(timeout 3 "$BSCPYLGTV" "$TV_IP" get_power_state 2>/dev/null | tr -d '\n')"
else
  note "TV not responding. It may simply be powered off (port 3000 stays open in
       soft standby, so this check is not conclusive either way)."
fi

# ---------------------------------------------------------------------------
echo
echo "=============================================="
echo " $pass passed, $warn warnings, $fail failures"
echo "=============================================="
echo
echo "Interactive tests (run manually — they change TV state):"
echo
echo "  A. Blank + restore, no lock involved:"
echo "       ~/.local/lgpowercontrol/tv-off.sh   # should power the TV off"
echo "       ~/.local/lgpowercontrol/tv-on.sh    # should bring it back"
echo
echo "  B. Full lock cycle with the daemon running:"
echo "       journalctl --user -t lgpowercontrol-daemon -f &"
echo "       # press SUPER+CTRL+L"
echo "       # expect: 'locked -- blanking panel' then the TV blanking ~3s later"
echo "       # unlock; expect: 'unlocked -- restoring displays'"
echo
echo "  C. Confirm the settle delay is still right:"
echo "     If the TV blanks then immediately un-blanks, BLANK_SETTLE_SECS is too"
echo "     short for the Quickshell lock. Raise it in the daemon and retry."
echo
echo "  D. Suspend/resume:"
echo "     Quattro ships omarchy-sleep-lock.service, so the session should be"
echo "     locked across suspend and the daemon's normal unlock path should"
echo "     restore the TV. Verify — if not, a /usr/lib/systemd/system-sleep/"
echo "     hook is needed, as under 3.8.4's after_sleep_cmd."

exit $(( fail > 0 ))
