#!/bin/bash
# 12-clean-journal.sh
# ============================================================================
# Reclaim disk space used by systemd journal and apt cache, and cap the
# journal size so it never grows back out of control.
#
#   Usage (Recovery root shell or normal TTY):
#     bash 12-clean-journal.sh
#
# What it does (all safe, no user data touched):
#   1) show current disk usage of / and /var/log
#   2) journalctl --disk-usage (before)
#   3) vacuum the journal: keep last 2 days, cap at 300M
#   4) set SystemMaxUse=300M in /etc/systemd/journald.conf.d/ so it persists
#   5) clean apt package cache (downloaded .deb files only, safe to remove)
#   6) show usage again (after)
#
# All output is ASCII so it renders correctly in Recovery (no CJK font there).
# ============================================================================

set -u

[ "$(id -u)" -eq 0 ] || { echo "[!] Run as root."; exit 1; }

say()  { echo "[*] $*"; }
warn() { echo "[!] $*"; }
ok()   { echo "[+] $*"; }

# --- 0. remount rw if needed ---
if findmnt -no OPTIONS / 2>/dev/null | grep -qE '(^|,)ro(,|$)'; then
  say "Root filesystem is read-only, remounting rw ..."
  mount -o remount,rw / 2>&1 || warn "remount failed, try manually: mount -o remount,rw /"
fi

# --- 1. before ---
say "Disk usage BEFORE:"
df -hT / /var/log 2>&1
echo
say "journal disk usage:"
journalctl --disk-usage 2>&1
echo

# --- 2. vacuum journal ---
say "Vacuuming journal (keep last 2 days, cap 300M) ..."
journalctl --vacuum-time=2d 2>&1
journalctl --vacuum-size=300M 2>&1
echo

# --- 3. persist a size cap so it never grows back ---
CONFD=/etc/systemd/journald.conf.d
mkdir -p "$CONFD"
cat > "$CONFD/10-size-limit.conf" <<'EOF'
# cap journal so it never fills the disk again
[Journal]
SystemMaxUse=300M
SystemKeepFree=1G
EOF
ok "Wrote $CONFD/10-size-limit.conf:"
sed 's/^/    /' "$CONFD/10-size-limit.conf"

# --- 4. clean apt cache (downloaded .deb only, safe) ---
say "Cleaning apt package cache ..."
apt-get clean 2>&1 | tail -2 || true

# --- 5. also clean old rotated logs if any ---
if command -v journalctl >/dev/null 2>&1; then
  : # vacuum above already handled journal
fi

# --- 6. after ---
say "Disk usage AFTER:"
df -hT / /var/log 2>&1
echo
say "journal disk usage after:"
journalctl --disk-usage 2>&1
echo

ok "Done. If root was 100% full before, services (dbus/logind/sshd) should now be able to start."
ok "Next:  bash 10-collect-evidence.sh   to check why dbus/logind failed (if still failing)."
