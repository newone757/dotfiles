# Shared by omarchy-windows-vm-launch (full desktop) and windows-app (RemoteApp).
# Sourced, not run.
#
# Lifecycle goes through the stock tool's own privileged actions. The polkit rule
# /etc/polkit-1/rules.d/49-omarchy-windows-vm.rules (source in
# ~/dotfiles/system/desktop) makes exactly `__priv up_wait|status|down` prompt-
# free; without it pkexec simply asks, like the stock launcher does.

WINVM=/usr/bin/omarchy-windows-vm
WINVM_CREDENTIALS="$HOME/.config/windows/credentials"

winvm_priv() { pkexec "$WINVM" __priv "$@"; }

winvm_running() { [[ $(winvm_priv status 2>/dev/null) == running ]]; }

# Sets WIN_USER / WIN_PASS from the private file the stock installer writes.
winvm_credentials() {
  local key value
  WIN_USER="" WIN_PASS=""
  [[ -r $WINVM_CREDENTIALS ]] || return 1
  while IFS='=' read -r key value; do
    case $key in
    USERNAME) WIN_USER=$value ;;
    PASSWORD) WIN_PASS=$value ;;
    esac
  done <"$WINVM_CREDENTIALS"
  [[ -n $WIN_USER && -n $WIN_PASS ]]
}

# FreeRDP 3 tries Kerberos before NTLM; the stock /etc/krb5.conf points at MIT's
# sample realm and each connect then blocks ~23s off-network. Point it at a
# realm-less config so it falls straight through to NTLM. (Same as upstream.)
winvm_krb5() {
  local conf="$HOME/.config/windows/krb5.conf"
  mkdir -p "$(dirname "$conf")"
  [[ -f $conf ]] || printf '[libdefaults]\n  dns_lookup_kdc = false\n  dns_lookup_realm = false\n' >"$conf"
  export KRB5_CONFIG="$conf"
}

# Sets RDP_SCALE (possibly empty). Display scaling is sent to the guest
# per-connection, so each client picks its own size without touching Windows'
# own display setting. Keep the guest itself at 100% in Settings > Display >
# Scale -- a scale set *inside* Windows is a persistent per-user value that
# overrides this and follows you to every client.
#
# Override with ~/.config/windows/scale (a percentage, 100-500). Falls back to
# the focused monitor's Hyprland scale.
winvm_scale() {
  local scale_file="$HOME/.config/windows/scale" percent="" hypr device
  [[ -r $scale_file ]] && percent=$(tr -cd '0-9' <"$scale_file")
  if [[ -z $percent ]]; then
    hypr=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select (.focused == true) | .scale' 2>/dev/null)
    [[ -n $hypr ]] && percent=$(awk -v s="$hypr" 'BEGIN { print int(s * 100) }')
  fi
  ((percent >= 100 && percent <= 500)) 2>/dev/null || percent=100

  # /scale-desktop takes any percentage; /scale-device only accepts 100|140|180,
  # so snap it to the nearest legal step for Store/shell UI.
  if ((percent >= 160)); then
    device=180
  elif ((percent >= 120)); then
    device=140
  else
    device=100
  fi
  RDP_SCALE=""
  ((percent != 100)) && RDP_SCALE="/scale-desktop:$percent /scale-device:$device"
  return 0
}
