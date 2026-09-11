#!/bin/bash
# 11-connect-wifi.sh
# ============================================================================
# Connect this machine to WiFi from a Recovery root shell.
#
#   Usage:
#     bash 11-connect-wifi.sh                    # default: CS-5G-wifi / 12345678
#     bash 11-connect-wifi.sh "MySSID" "pass"    # custom SSID / password
#     bash 11-connect-wifi.sh "MySSID" "pass" --off   # keep wired Ethernet up too
#
# What it does:
#   1) make sure the root filesystem is writable
#   2) find + unblock + bring up the wireless interface
#   3) DOWN all wired Ethernet interfaces (so traffic goes over WiFi).
#      Add --off to keep wired up.
#   4) connect with wpa_supplicant
#   5) get an IP via dhclient (fallback: dhcpcd)
#   6) verify with: ping -4 8.8.8.8
#
# All output is ASCII so it renders correctly in Recovery (no CJK font there).
# ============================================================================

set -u

[ "$(id -u)" -eq 0 ] || { echo "[!] Run as root."; exit 1; }

SSID="${1:-CS-2-5G}"
PASS="${2:-12345678}"
KEEP_ETH=0
for a in "$@"; do
  case "$a" in
    --off) KEEP_ETH=1 ;;
  esac
done

say()  { echo "[*] $*"; }
warn() { echo "[!] $*"; }
ok()   { echo "[+] $*"; }

# --- 0. remount root rw (Recovery shell usually mounts it read-only) ---
if findmnt -no OPTIONS / 2>/dev/null | grep -qE '(^|,)ro(,|$)'; then
  say "Root filesystem is read-only, remounting rw ..."
  mount -o remount,rw / 2>&1 || warn "remount failed, try manually: mount -o remount,rw /"
fi

# --- 0.1 self-heal root dir permission (accidental `chmod 666 /` breaks gdm) ---
ROOTMODE=$(stat -c '%a' / 2>/dev/null)
if [ "$ROOTMODE" != "755" ]; then
  warn "Root dir '/' is $ROOTMODE (should be 755). Fixing ..."
  chmod 755 / 2>&1 && ok "  / = $(stat -c '%a' /)"
fi

# --- 0.5 handle wired Ethernet ---
if [ "$KEEP_ETH" = 1 ]; then
  say "--off given: keeping wired Ethernet up."
else
  say "Taking down wired Ethernet interfaces (use --off to keep them up) ..."
  for i in /sys/class/net/*; do
    n=$(basename "$i")
    case "$n" in
      lo|wl*|wlan*) continue ;;   # skip loopback + wireless
      en*|eth*) ip link set "$n" down 2>&1 && say "  down: $n" ;;
    esac
  done
fi

# --- 1. find the wireless interface ---
find_iface() {
  local n
  for i in /sys/class/net/*; do
    n=$(basename "$i")
    # modern kernels expose a "wireless" subdir; older names start with wl*
    [ -d "$i/wireless" ] && { echo "$n"; return 0; }
    case "$n" in wl*|wlan*) echo "$n"; return 0;; esac
  done
  return 1
}

IFACE=$(find_iface 2>/dev/null)

# --- 2. if none found, try to unblock rfkill first ---
if [ -z "$IFACE" ]; then
  warn "No wireless interface found. Checking rfkill ..."
  if command -v rfkill >/dev/null 2>&1; then
    rfkill unblock wifi 2>/dev/null || true
    rfkill unblock all  2>/dev/null || true
    rfkill list 2>/dev/null || true
    sleep 1
    IFACE=$(find_iface 2>/dev/null)
  fi
fi

if [ -z "$IFACE" ]; then
  warn "Still no wireless interface (no wl*/wlan* device)."
  warn "Possible causes: driver not loaded, or this machine has no WiFi card."
  warn "Diagnose with:  lspci -k | grep -i network   and   ip link"
  exit 2
fi
ok "Wireless interface: $IFACE"

# --- 3. bring the interface up ---
ip link set "$IFACE" up 2>&1 || true
sleep 1
say "Interface state after 'up':"
ip link show "$IFACE" 2>&1 | sed 's/^/    /'

# --- 4. make sure wpa_supplicant exists ---
if ! command -v wpa_supplicant >/dev/null 2>&1; then
  warn "wpa_supplicant is not installed. Trying to install it ..."
  if ping -4 -c1 -W3 8.8.8.8 >/dev/null 2>&1; then
    apt-get update 2>&1 | tail -3
    apt-get install -y wpasupplicant 2>&1 | tail -5
  else
    warn "No network to install wpa_supplicant either. Aborting."
    exit 3
  fi
fi

# --- 5. write config and connect ---
CONF=/tmp/wpa_supplicant.conf
mkdir -p /run/wpa_supplicant

# prefer wpa_passphrase (robust quoting); fall back to manual heredoc
if command -v wpa_passphrase >/dev/null 2>&1; then
  wpa_passphrase "$SSID" "$PASS" > "$CONF" 2>/dev/null || {
    warn "wpa_passphrase failed (SSID too short?), writing manual config"
    cat > "$CONF" <<EOF
network={
    ssid="$SSID"
    psk="$PASS"
    key_mgmt=WPA-PSK
    scan_ssid=1
}
EOF
  }
  # add useful control interface + scan_ssid for hidden SSIDs
  sed -i '1i ctrl_interface=DIR=/run/wpa_supplicant GROUP=root' "$CONF" 2>/dev/null || true
else
  cat > "$CONF" <<EOF
ctrl_interface=DIR=/run/wpa_supplicant GROUP=root
update_config=1
network={
    ssid="$SSID"
    psk="$PASS"
    key_mgmt=WPA-PSK
    scan_ssid=1
}
EOF
fi
chmod 600 "$CONF"

# kill any stale instances from previous attempts
pkill -9 wpa_supplicant 2>/dev/null || true
pkill -9 dhclient 2>/dev/null || true
pkill -9 dhcpcd 2>/dev/null || true
sleep 1

say "Starting wpa_supplicant for '$SSID' ..."
wpa_supplicant -B -i "$IFACE" -c "$CONF" -D nl80211 2>&1 | sed 's/^/    /' || true
sleep 4

# show association status if tools are available
if command -v iw >/dev/null 2>&1; then
  iw dev "$IFACE" link 2>&1 | sed 's/^/    /' || true
elif command -v wpa_cli >/dev/null 2>&1; then
  wpa_cli -i "$IFACE" status 2>&1 | sed 's/^/    /' || true
fi

# --- 6. get an IP address ---
say "Requesting an IP address ..."
if command -v dhclient >/dev/null 2>&1; then
  dhclient -v "$IFACE" 2>&1 | tail -6 | sed 's/^/    /' || true
elif command -v dhcpcd >/dev/null 2>&1; then
  dhcpcd "$IFACE" 2>&1 | tail -6 | sed 's/^/    /' || true
else
  warn "No dhclient/dhcpcd found; cannot request an IP automatically."
fi

sleep 2
say "Final interface state:"
ip addr show "$IFACE" 2>&1 | sed 's/^/    /'

# --- 7. verify connectivity ---
if ping -4 -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
  IP=$(ip -4 -o addr show "$IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
  ok "SUCCESS: ping 8.8.8.8 works. You are online."
  ok "This machine's IP: ${IP:-unknown}"
  ok "Give this IP to the remote helper so they can SSH in."
else
  warn "ping 8.8.8.8 failed. Check the DHCP output above."
  warn "Retry with: bash 11-connect-wifi.sh"
  exit 4
fi
