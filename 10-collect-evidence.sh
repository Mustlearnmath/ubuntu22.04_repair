#!/bin/bash
# 10-collect-evidence.sh
# ============================================================================
# Collect the exact evidence needed to diagnose why dbus / systemd-journald /
# systemd-logind fail to start. Run this in Recovery root shell, then push
# the result with 08-push-logs.sh.
#
#   Usage:
#     bash 10-collect-evidence.sh          # writes /root/evidence.txt
#     bash 08-push-logs.sh                 # then push it online
#
# All output is ASCII so it renders correctly in Recovery (no CJK font there).
# ============================================================================

set -u

[ "$(id -u)" -eq 0 ] || { echo "[!] Run as root."; exit 1; }

OUT=/root/evidence.txt
exec > >(tee "$OUT") 2>&1

hr() { echo; echo "==================== $* ===================="; }

# --- 0. remount rw (so 07 can actually persist its fixes) ---
hr "0. root mount state (check for 'ro'!)"
mount | grep ' / ' 2>&1
echo
findmnt -no OPTIONS / 2>&1
if findmnt -no OPTIONS / 2>/dev/null | grep -qE '(^|,)ro(,|$)'; then
  echo ">>> ROOT IS READ-ONLY. This is why 07's fixes did not persist!"
  echo ">>> Remounting rw now ..."
  mount -o remount,rw / 2>&1
  findmnt -no OPTIONS / 2>&1
fi

# --- 1. the three failing services, full status ---
hr "1. dbus / systemd-journald / systemd-logind status"
for u in dbus dbus.socket systemd-journald systemd-journald.socket systemd-logind; do
  echo
  echo "----- systemctl status $u -----"
  systemctl status "$u" --no-pager -l 2>&1 | head -25
done

# --- 2. are they masked? ---
hr "2. is-enabled / is-active for key units"
for u in dbus dbus.socket systemd-journald systemd-journald.socket \
         systemd-logind systemd-udevd systemd-user-sessions getty@tty1 gdm3; do
  printf '  %-28s enabled=%-10s active=%s\n' "$u" "$(systemctl is-enabled "$u" 2>&1)" "$(systemctl is-active "$u" 2>&1)"
done

# --- 3. why did they fail (this-boot journal) ---
hr "3. journal: this boot, these units"
journalctl -b -u dbus --no-pager 2>&1 | tail -40
echo
journalctl -b -u systemd-journald --no-pager 2>&1 | tail -40
echo
journalctl -b -u systemd-logind --no-pager 2>&1 | tail -40

# --- 4. previous boot errors (the real failed boot) ---
hr "4. journal: PREVIOUS boot errors (-b -1 -p err)"
journalctl -b -1 -p err --no-pager 2>&1 | tail -120

# --- 5. this boot errors ---
hr "5. journal: THIS boot errors (-b -p err)"
journalctl -b -p err --no-pager 2>&1 | tail -120

# --- 6. all failed units ---
hr "6. systemctl --failed"
systemctl --failed --no-pager 2>&1

# --- 7. drop-in overrides that might break things ---
hr "7. suspicious systemd drop-ins"
found=0
for f in /etc/systemd/system/*.service.d/*.conf /etc/systemd/system/*.socket.d/*.conf \
         /etc/systemd/system/systemd-logind.service.d/* /etc/systemd/system/systemd-journald.service.d/*; do
  [ -f "$f" ] || continue
  found=1
  echo "--- $f ---"
  sed 's/^/  /' "$f"
done
[ "$found" = 0 ] && echo "(none)"

hr "8. dbus / journald / logind config files (non-comment lines)"
for f in /etc/dbus-1/system.conf /etc/systemd/journald.conf /etc/systemd/logind.conf; do
  [ -f "$f" ] || { echo "  (missing: $f)"; continue; }
  echo "--- $f ---"
  grep -vE '^\s*(#|$)' "$f" 2>/dev/null || echo "  (all defaults)"
done

# --- 9. /run and /var permissions that these services need ---
hr "9. permissions of /run /var /run/dbus /run/log/journal"
stat -c '%n  %a  %U:%G' /run /var /run/dbus /run/log/journal /var/log/journal 2>&1
echo
ls -ld /run /run/dbus /run/log /run/log/journal /var/log/journal 2>&1

hr "10. disk space (journald fails when root is full)"
df -hT / /var /run 2>&1

hr "done"
echo "Evidence written to $OUT"
echo "Now run:  bash 08-push-logs.sh   to push it online"
