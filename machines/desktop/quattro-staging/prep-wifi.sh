#!/bin/bash
# Pre-stage a NetworkManager WiFi profile from the current iwd credentials.
#
# WHY: Quattro removes iwd and switches to NetworkManager, but ships NO
# credential migration (verified against every migration in 4.0.1). The upgrade
# itself is safe — iwd is disabled but never stopped, so the connection survives
# the package transaction — but after the REBOOT, NetworkManager has no profile
# and the machine comes up with no network.
#
# NetworkManager reads /etc/NetworkManager/system-connections/ at startup, and
# doesn't care that it wasn't running when the file appeared. So writing the
# keyfile NOW means WiFi just works on the first Quattro boot, with no
# mid-upgrade window to catch and nothing to remember.
#
# Run BEFORE upgrading:   sudo ./prep-wifi.sh
# Idempotent — safe to re-run.

set -uo pipefail

NM_DIR=/etc/NetworkManager/system-connections
IWD_DIR=/var/lib/iwd
BACKUP_DIR="$HOME/pre-quattro-inventory"

if (( EUID != 0 )); then
  echo "Needs root to read $IWD_DIR and write $NM_DIR." >&2
  echo "Re-run: sudo $0" >&2
  exit 1
fi

[[ -d $IWD_DIR ]] || { echo "No $IWD_DIR — is iwd actually in use?" >&2; exit 1; }

shopt -s nullglob
psk_files=("$IWD_DIR"/*.psk)
(( ${#psk_files[@]} )) || { echo "No .psk files in $IWD_DIR — nothing to migrate." >&2; exit 1; }

# The interface to bind to. Left unset in the profile if it can't be determined,
# which makes the profile match any wifi device — usually what you want anyway.
WIFI_IFACE=$(basename "$(ls -d /sys/class/net/*/wireless 2>/dev/null | head -1 | xargs dirname 2>/dev/null)" 2>/dev/null)

mkdir -p "$NM_DIR"
staged=0

for f in "${psk_files[@]}"; do
  # iwd names the file after the SSID. Non-alphanumeric SSIDs get hex-encoded
  # as "=<hex>.psk"; handle the common plain case and warn on the encoded one.
  base=$(basename "$f" .psk)
  if [[ $base == =* ]]; then
    echo "SKIP: $f uses iwd's hex-encoded SSID form; decode it manually." >&2
    continue
  fi
  ssid=$base

  # Passphrase= is the plaintext; PreSharedKey= is the derived 64-hex PMK.
  # NetworkManager accepts either — psk= takes a passphrase OR a 64-hex key.
  pass=$(grep -oP '^Passphrase=\K.*'   "$f" 2>/dev/null | head -1)
  pmk=$( grep -oP '^PreSharedKey=\K.*' "$f" 2>/dev/null | head -1)
  secret="${pass:-$pmk}"

  if [[ -z $secret ]]; then
    echo "SKIP: no Passphrase= or PreSharedKey= in $f" >&2
    continue
  fi

  out="$NM_DIR/${ssid}.nmconnection"
  if [[ -e $out ]]; then
    echo "exists, leaving alone: $out"
    continue
  fi

  {
    echo "[connection]"
    echo "id=$ssid"
    echo "type=wifi"
    [[ -n ${WIFI_IFACE:-} ]] && echo "interface-name=$WIFI_IFACE"
    echo "autoconnect=true"
    echo "autoconnect-priority=10"
    echo
    echo "[wifi]"
    echo "mode=infrastructure"
    echo "ssid=$ssid"
    echo
    echo "[wifi-security]"
    echo "key-mgmt=wpa-psk"
    echo "psk=$secret"
    echo
    echo "[ipv4]"
    echo "method=auto"
    echo
    echo "[ipv6]"
    echo "method=auto"
    echo "addr-gen-mode=default"
  } >"$out"

  # NetworkManager REFUSES to load keyfiles that are group/world readable.
  chmod 600 "$out"
  chown root:root "$out"
  echo "staged: $out"
  ((staged++))
done

echo
echo "Staged $staged profile(s)."

# Keep an offline copy of the credentials with the rest of the inventory, so a
# machine that comes up with no network still has them reachable.
if [[ -d $BACKUP_DIR ]]; then
  cp -a "$IWD_DIR" "$BACKUP_DIR/iwd-credentials-backup" 2>/dev/null &&
    chmod -R go-rwx "$BACKUP_DIR/iwd-credentials-backup" &&
    echo "Backed up raw iwd credentials to $BACKUP_DIR/iwd-credentials-backup"
  echo "  (contains plaintext PSKs — it is chmod 700 and gitignored; do NOT commit)"
fi

cat <<'EOF'

Verify now (NetworkManager need not be installed for the file to be valid):
  sudo ls -l /etc/NetworkManager/system-connections/

After the upgrade completes, BEFORE rebooting, sanity-check NM sees it:
  nmcli connection show

If you still come up with no network after reboot:
  Ctrl+Alt+F2, log in, then:
    nmtui                                  # interactive
    nmcli device wifi list
    sudo nmcli device wifi connect "SSID" password 'PSK'
  Raw credentials remain at /var/lib/iwd/ (removing the iwd package does not
  delete them) and in the inventory backup above.

Wired fallback: borrowing the TV's ethernet run works, but note the TV then
loses network — bscpylgtvcommand and WoL cannot reach it, so TV power control
is untestable until the cable goes back.
EOF
