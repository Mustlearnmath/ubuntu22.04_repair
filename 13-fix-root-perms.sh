#!/bin/bash
# 13-fix-root-perms.sh
# ============================================================================
# Fix the root cause of "gdm3 fails to start / can't reach login screen":
#   the ROOT directory '/' (and possibly other dirs) lost its execute bit,
#   e.g. by an accidental `chmod 666 /` or `chmod -R` gone wrong.
#
# Symptom chain:
#   gdm -> ExecStartPre=/usr/share/gdm/generate-config
#        -> dconf: error while loading shared libraries: libdconf.so.1:
#           cannot open shared object file: Permission denied
#
# Because non-root users (gdm) cannot traverse '/' without the 'x' bit,
# every shared library is unreadable to them. root is unaffected, which is
# why root commands all worked while the login screen never appeared.
#
#   Usage (Recovery root shell):
#     bash 13-fix-root-perms.sh
#
# What it does:
#   1) audit permissions of / and other critical dirs
#   2) restore / to 755 (and other dirs that are wrongly world-writable)
#   3) verify gdm can load libdconf as the gdm user
#   4) optionally try to start gdm
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
  say "Root is read-only, remounting rw ..."
  mount -o remount,rw / 2>&1 || warn "remount failed: mount -o remount,rw /"
fi

# --- 1. audit ---
say "Auditing critical directory permissions ..."
BROKEN=0
for d in / /bin /sbin /lib /lib64 /var/run; do
  # skip symlinks: /bin /sbin /lib /lib64 /var/run are symlinks on Ubuntu
  [ -L "$d" ] && { echo "  (symlink, skip) $d"; continue; }
  mode=$(stat -c '%a' "$d" 2>/dev/null || echo '')
  [ -z "$mode" ] && continue
  if [ "$mode" != "755" ]; then
    echo "  BROKEN: $d = $mode (expected 755)"
    BROKEN=1
  else
    echo "  OK: $d = $mode"
  fi
done
echo

# --- 2. fix '/' specifically (the critical one) ---
say "Fixing root directory '/' to 755 ..."
chmod 755 / 2>&1 || warn "chmod / failed"
ok "  / = $(stat -c '%a' / 2>/dev/null)"
echo

# --- 3. verify gdm can load libdconf ---
say "Verifying gdm can load libdconf as user 'gdm' ..."
if command -v setpriv >/dev/null 2>&1 && command -v dconf >/dev/null 2>&1; then
  out=$(setpriv --reuid gdm --regid gdm --init-groups --no-new-privs \
                --inh-caps=-all --reset-env -- \
                dconf compile /tmp/gdm-test-dconf /usr/share/gdm/dconf 2>&1)
  rc=$?
  rm -f /tmp/gdm-test-dconf
  if [ $rc -eq 0 ]; then
    ok "PASS: gdm can now load shared libraries."
  else
    warn "STILL FAILING:"
    echo "$out" | sed 's/^/    /'
    warn "Check other parent dirs of /usr/lib/x86_64-linux-gnu for missing x bit."
  fi
else
  warn "setpriv or dconf not found; skipping verification."
fi
echo

# --- 4. try start gdm ---
say "Attempting to start gdm ..."
systemctl reset-failed gdm 2>/dev/null || true
systemctl start gdm 2>&1 | head -5 || true
sleep 3
echo "  gdm active: $(systemctl is-active gdm 2>&1)"
echo
ok "Done. If gdm is active, reboot and you should reach the login screen."
