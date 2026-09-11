#!/bin/bash
# 09-enable-ssh.sh
# ============================================================================
# Set up an SSH server on this machine so a remote helper can take over.
#
#   Usage (Recovery root shell):
#     bash 11-connect-wifi.sh        # 1) get online first (recommended)
#     bash 09-enable-ssh.sh          # 2) then enable SSH
#
# What it does:
#   1) remount root rw
#   2) install openssh-server if missing (needs network)
#   3) generate host keys
#   4) set/change the root password (interactive, hidden input)
#   5) start sshd manually (Recovery has no running systemd here)
#   6) print this machine's IP so you can hand it over
#
# All output is ASCII so it renders correctly in Recovery (no CJK font there).
# ============================================================================

set -u

[ "$(id -u)" -eq 0 ] || { echo "[!] Run as root."; exit 1; }

say()  { echo "[*] $*"; }
warn() { echo "[!] $*"; }
ok()   { echo "[+] $*"; }

# --- 0. remount root rw ---
if findmnt -no OPTIONS / 2>/dev/null | grep -qE '(^|,)ro(,|$)'; then
  say "Root filesystem is read-only, remounting rw ..."
  mount -o remount,rw / 2>&1 || warn "remount failed, try manually: mount -o remount,rw /"
fi

# --- 1. make sure sshd exists ---
if ! command -v sshd >/dev/null 2>&1 && [ ! -x /usr/sbin/sshd ]; then
  warn "openssh-server is not installed. Trying to install it ..."
  if ping -4 -c1 -W3 8.8.8.8 >/dev/null 2>&1; then
    echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
    apt-get update 2>&1 | tail -3
    apt-get install -y openssh-server 2>&1 | tail -6
  else
    warn "No network. Run 'bash 11-connect-wifi.sh' first, then rerun this script."
    exit 2
  fi
fi

# --- 2. host keys ---
if [ -x /usr/bin/ssh-keygen ]; then
  if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    say "Generating host keys ..."
    ssh-keygen -A 2>&1 | tail -5 || true
  fi
fi

# --- 3. set root password (interactive) ---
say "Set a root password for SSH login."
while :; do
  printf "New root password: "
  stty -echo; read -r PW1; stty echo; echo
  [ -n "$PW1" ] || { warn "Password cannot be empty."; continue; }
  printf "Retype password:   "
  stty -echo; read -r PW2; stty echo; echo
  [ "$PW1" = "$PW2" ] && break
  warn "Passwords do not match, try again."
done
if command -v chpasswd >/dev/null 2>&1; then
  echo "root:$PW1" | chpasswd && ok "root password updated."
else
  (echo "$PW1"; echo "$PW1") | passwd root 2>&1 | tail -2 || warn "passwd failed"
fi
unset PW1 PW2

# --- 4. start sshd manually ---
mkdir -p /run/sshd
pkill -9 sshd 2>/dev/null || true
sleep 1
say "Starting sshd ..."
/usr/sbin/sshd -o PermitRootLogin=yes -o PasswordAuthentication=yes -o UsePAM=yes 2>&1 | tail -3 || true

# confirm it is listening
sleep 1
if ss -tlnp 2>/dev/null | grep -q ':22 ' || netstat -tlnp 2>/dev/null | grep -q ':22 '; then
  ok "sshd is listening on port 22."
else
  warn "sshd may not be listening yet; check: ss -tlnp | grep :22"
fi

# --- 5. print connection info ---
say "Network interfaces and IPs:"
ip -4 -o addr show 2>/dev/null | awk '{print "    "$2"  "$4}' || ip addr 2>/dev/null
echo
ok "If you see a 192.168.x.x address above, give it (plus root password) to your helper."
ok "Helper connects with:  ssh root@<IP>"
