#!/bin/bash
# 09-enable-ssh.sh
# ============================================================================
# Set up an SSH server on this machine so a remote helper can take over.
#
#   Usage (Recovery root shell):
#     bash 11-connect-wifi.sh        # 1) get online first (recommended)
#     bash 09-enable-ssh.sh          # 2) then enable SSH
#
# What it does (fully automatic, no interactive password step):
#   1) remount root rw
#   2) install openssh-server if missing (needs network)
#   3) generate host keys
#   4) install a built-in authorized key for the remote helper
#      (login does NOT depend on password/PAM, which breaks when
#       dbus / systemd-logind are down)
#   5) kill stale sshd, start with correct flags; if PAM rejects, retry UsePAM=no
#   6) print this machine's IP so you can hand it over
#
# All output is ASCII so it renders correctly in Recovery (no CJK font there).
# ============================================================================

set -u

[ "$(id -u)" -eq 0 ] || { echo "[!] Run as root."; exit 1; }

say()  { echo "[*] $*"; }
warn() { echo "[!] $*"; }
ok()   { echo "[+] $*"; }

# Remote helper's public key (paired with a private key on the helper's side).
HELPER_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHqmoGcvWCi4avGWa4jbyrjvAV4nBcw6v+Bie3BXR8vD repair@windows'

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

# --- 3. install helper authorized key (no password needed) ---
say "Installing helper authorized key ..."
mkdir -p /root/.ssh /run/sshd
printf '%s\n' "$HELPER_KEY" > /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
ok "authorized_keys:"
sed 's/^/    /' /root/.ssh/authorized_keys

# --- 4. kill stale sshd, then start with correct flags ---
pkill -9 sshd 2>/dev/null || true
sleep 1

say "Starting sshd (attempt 1: with PAM) ..."
/usr/sbin/sshd -o PermitRootLogin=yes -o PasswordAuthentication=yes \
               -o PubkeyAuthentication=yes -o UsePAM=yes 2>&1 | tail -3 || true
sleep 1

if ! (ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -q ':22 '; then
  warn "sshd not listening with PAM; retrying with UsePAM=no ..."
  pkill -9 sshd 2>/dev/null || true
  sleep 1
  /usr/sbin/sshd -o PermitRootLogin=yes -o PasswordAuthentication=yes \
                 -o PubkeyAuthentication=yes -o UsePAM=no 2>&1 | tail -3 || true
  sleep 1
fi

if (ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -q ':22 '; then
  ok "sshd is listening on port 22."
else
  warn "sshd STILL not listening on :22. Running config check ..."
  /usr/sbin/sshd -t 2>&1 | tail -8 || true
  warn "If a config error appears above, fix /etc/ssh/sshd_config then rerun this script."
fi

# --- 5. print connection info ---
say "Network interfaces and IPs:"
ip -4 -o addr show 2>/dev/null | awk '{print "    "$2"  "$4}' || ip addr 2>/dev/null
echo
ok "Helper key installed. Remote helper logs in with:  ssh -i <privkey> root@<IP>"
ok "No password is needed (key-based login)."
