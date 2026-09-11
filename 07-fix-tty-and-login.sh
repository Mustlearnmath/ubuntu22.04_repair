#!/bin/bash
# 07-fix-tty-and-login.sh
# ============================================================================
# 针对事故： sudo chmod 666 /dev*/tty*
#
#   症状：运行中大量图标丢失；重启后进不了登录界面；
#         登录服务（systemd-logind）/ 日志服务启动失败。
#
# 本脚本做什么（全程只在"值不对"时才改动，关键文件先备份）：
#   1) 记录 /dev 现状：挂载类型（devtmpfs?）+ tty 权限。判断这次 chmod 是否会持久
#   2) 把 /dev/tty* 及常见设备节点恢复成标准权限
#      （/dev/tty=666，tty0..tty63=620，ttyS*/USB/ACM=660，console=600，
#        /tmp|/var/tmp|/dev/shm|/run/lock=1777），并让 udev 重放规则
#   3) 修复登录/日志栈：systemd-logind、systemd-journald、dbus、systemd-udevd、
#      systemd-user-sessions、getty@tty1 —— 解除 mask、恢复 enable、reset-failed、
#      修 journal 目录权限、列出可疑 drop-in、并现场试着把它们拉起来看真实报错
#   4) 检查图标主题包（图标丢失的直接原因）
#   5) 检查默认显示管理器 / graphical.target
#
# 用法（Recovery root shell 或正常 TTY 里都行）：
#   bash 07-fix-tty-and-login.sh
#   bash 07-fix-tty-and-login.sh --with-desktop   # 顺便调用 02-repair.sh 补桌面依赖（需联网）
#
# 安全：不装包、不删用户数据、不改 /home；日志写 /root/fix-tty-login-<时间戳>.log
# ============================================================================

set -u

[ "$(id -u)" -eq 0 ] || { echo "请用 root 运行（Recovery 菜单里的 root shell 就是 root）"; exit 1; }

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WITH_DESKTOP=0
for a in "$@"; do
  case "$a" in
    --with-desktop) WITH_DESKTOP=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
  esac
done

TS=$(date +%Y%m%d-%H%M%S)
LOG=/root/fix-tty-login-"$TS".log
exec > >(tee -a "$LOG") 2>&1

step() { echo; echo "########## $* ##########"; }
have() { command -v "$1" >/dev/null 2>&1; }

# 只在当前权限与期望不符时修改
fix_perm() {                 # fix_perm <路径> <期望模式，如 620>
  local p="$1" want="$2" cur
  [ -e "$p" ] || return 0
  cur=$(stat -c '%a' "$p" 2>/dev/null) || return 0
  if [ "$cur" != "$want" ]; then
    echo "  修正: $p  $cur -> $want"
    chmod "$want" "$p" 2>/dev/null || echo "    (chmod 失败，忽略)"
  fi
  return 0
}

# 只有当『其他用户可写』时才改（末位是 2/3/6/7）
fix_world_writable() {       # fix_world_writable <路径> <安全模式>
  local p="$1" want="$2" cur
  [ -e "$p" ] || return 0
  cur=$(stat -c '%a' "$p" 2>/dev/null) || return 0
  case "$cur" in
    *[2367])
      echo "  修正(世界可写): $p  $cur -> $want"
      chmod "$want" "$p" 2>/dev/null || true
      ;;
  esac
  return 0
}

step "0. 环境自检"
echo "时间: $(date)"
uname -a
echo "systemd: $(systemctl --version 2>/dev/null | head -1)"
echo "默认 target: $(systemctl get-default 2>/dev/null)"

# Recovery root shell 的根分区默认只读，不 remount rw 的话后面所有修改都会失败
if findmnt -no OPTIONS / 2>/dev/null | grep -qE '(^|,)ro(,|$)'; then
  echo
  echo "根文件系统当前只读，尝试 remount rw ..."
  mount -o remount,rw / 2>&1 || echo "!! remount 失败，请手动执行: mount -o remount,rw /"
fi

step "1. /dev 现状快照（改动前）"
DEVFS=$(findmnt -no FSTYPE /dev 2>/dev/null || awk '$2=="/dev"{print $3}' /proc/mounts)
echo "/dev 挂载: ${DEVFS:-未知}  ($(findmnt -no SOURCE,OPTIONS /dev 2>/dev/null))"
echo
echo "tty 节点数字权限:"
stat -c '  %n  %a  %U:%G' /dev/tty /dev/tty[0-9]* /dev/tty[A-Za-z]* /dev/console 2>/dev/null
echo
echo "/dev 下『其他用户可写』的节点（正常只应有 null/zero/tty/ptmx 等几个）:"
find /dev -maxdepth 1 \( -type c -o -type b \) -perm -0002 -printf '  %m %u:%g %p\n' 2>/dev/null | sort | head -40
echo
if [ "$DEVFS" = "devtmpfs" ]; then
  echo ">>> /dev 是 devtmpfs：重启后设备节点由内核 + udev 重建，"
  echo "    所以 chmod 666 /dev/tty* 本身不会持久到重启之后。"
  echo "    也就是说：如果重启后仍然进不去桌面，真凶很可能在别处"
  echo "    （登录/日志服务、桌面依赖、GDM 配置）。本脚本下面几步都会覆盖。"
else
  echo ">>> !! 注意：/dev 不是 devtmpfs（FSTYPE=${DEVFS:-未知}），"
  echo "    权限改动会持久生效，第 2 步的修正对你就尤其重要。"
fi

step "2. 恢复 /dev 设备节点标准权限"
echo "标准值来自 /usr/lib/udev/rules.d/50-udev-default.rules："
echo "  /dev/tty            666  root:tty   （当前控制终端）"
echo "  /dev/tty0..tty63    620  root:tty   （虚拟终端，tty 组可写）"
echo "  /dev/ttyS*/USB/ACM  660  root:tty   （串口/USB 串口）"
echo "注：chmod 不改变属主，所以这里只需要把『模式』改回来。"
echo
fix_perm /dev/tty 666
for n in /dev/tty[0-9]*; do [ -e "$n" ] && fix_perm "$n" 620; done
for n in /dev/tty[A-Za-z]*; do [ -e "$n" ] && fix_perm "$n" 660; done

echo
echo "顺带把最容易一起被误改的常用节点校回标准值："
for d in null zero full random urandom; do fix_perm "/dev/$d" 666; done
fix_world_writable /dev/console 600
fix_perm /tmp 1777
fix_perm /var/tmp 1777
fix_perm /dev/shm 1777
fix_perm /run/lock 1777

# 让 udev 用自己的规则再刷一遍（比手改权威；udevd 没在跑时也不会报错）
if have udevadm; then
  echo
  echo "让 udev 重新应用规则 ..."
  udevadm control --reload-rules 2>&1 | tail -2 || true
  udevadm trigger --subsystem-match=tty --action=change 2>&1 | tail -2 || true
  udevadm settle --timeout=10 2>&1 | tail -2 || true
fi

echo
echo "改动后 tty 节点:"
stat -c '  %n  %a  %U:%G' /dev/tty /dev/tty[0-9]* /dev/tty[A-Za-z]* /dev/console 2>/dev/null

step "3. 修复登录 / 日志 systemd 单元"
CRIT_UNITS="systemd-udevd systemd-journald systemd-journald.socket systemd-logind dbus dbus.socket systemd-user-sessions getty@tty1"

echo "--- 3.1 解除被 mask 的关键单元 ---"
for u in $CRIT_UNITS; do
  st=$(systemctl is-enabled "$u" 2>&1)
  printf '  %-28s %s\n' "$u" "$st"
  case "$st" in
    masked*|*"masked"*)
      echo "     -> 解除 mask"
      systemctl unmask "$u" 2>&1 | sed 's/^/     /' || true
      ;;
  esac
done

echo
echo "--- 3.2 恢复开机自启（已 enable 的无副作用）---"
for u in systemd-udevd systemd-journald.socket systemd-logind dbus.socket systemd-user-sessions getty@tty1; do
  systemctl enable "$u" 2>&1 | sed 's/^/  /' || true
done

echo
echo "--- 3.3 清失败状态 ---"
systemctl reset-failed 2>&1 | sed 's/^/  /' || true

echo
echo "--- 3.4 现场把它们拉起来，看真实报错（这一步是定位关键）---"
for u in dbus.socket systemd-journald.socket systemd-logind systemd-user-sessions systemd-journald; do
  echo "  >>> systemctl start $u"
  systemctl start "$u" 2>&1 | sed 's/^/      /' || true
  printf '      %-28s %s\n' "$u" "$(systemctl is-active "$u" 2>&1)"
done
echo
echo "仍然失败的单元:"
systemctl --failed --no-pager 2>&1 | head -20
echo
for u in systemd-logind systemd-journald dbus; do
  echo "----- $u 状态/最近日志 -----"
  systemctl status "$u" --no-pager -l 2>&1 | head -15
  journalctl -b -u "$u" --no-pager 2>/dev/null | tail -15
done

step "4. 可疑的 systemd 覆盖文件（drop-in）"
found=0
for f in /etc/systemd/system/*.service.d/*.conf /etc/systemd/system/*.socket.d/*.conf \
         /etc/systemd/system/systemd-logind.service.d/* /etc/systemd/system/systemd-journald.service.d/*; do
  [ -f "$f" ] || continue
  found=1
  echo "--- $f ---"
  sed 's/^/  /' "$f"
done
[ "$found" = 0 ] && echo "(没有 drop-in 覆盖文件，干净)"
echo
echo "logind.conf 非注释行:"
grep -vE '^\s*(#|$)' /etc/systemd/logind.conf 2>/dev/null || echo "  (全部默认)"
echo "journald.conf 非注释行:"
grep -vE '^\s*(#|$)' /etc/systemd/journald.conf 2>/dev/null || echo "  (全部默认)"

step "5. journal 目录权限（日志服务起不来的常见原因）"
for d in /var/log/journal /run/log/journal; do
  [ -d "$d" ] || continue
  echo "$d : $(stat -c '%a %U:%G' "$d")"
  chown root:systemd-journal "$d" 2>/dev/null || true
  chmod 2755 "$d" 2>/dev/null || true
  find "$d" -type d -exec chmod 2755 {} + 2>/dev/null || true
  find "$d" -type f -name '*.journal*' -exec chown root:systemd-journal {} + 2>/dev/null || true
  find "$d" -type f -name '*.journal*' -exec chmod 0640 {} + 2>/dev/null || true
done
if have systemd-tmpfiles; then
  systemd-tmpfiles --create --prefix /var/log/journal 2>&1 | tail -5 || true
fi

step "6. 图标主题检查（你遇到过的『大量图标丢失』）"
ICON_OK=1
for i in /usr/share/icons/hicolor/index.theme /usr/share/icons/Adwaita/index.theme; do
  if [ -f "$i" ]; then
    echo "  OK  $i"
  else
    ICON_OK=0
    echo "  !!  缺失 $i"
  fi
done
have gtk-update-icon-cache && echo "  OK  gtk-update-icon-cache" || { ICON_OK=0; echo "  !!  缺 gtk-update-icon-cache"; }
echo
dpkg -l hicolor-icon-theme adwaita-icon-theme yaru-theme-icon 2>/dev/null | awk '/^ii/ {print "  ",$2,$3}'
if [ "$ICON_OK" = 0 ]; then
  echo
  echo ">>> 图标主题不完整。联网后执行（或直接跑 02-repair.sh）："
  echo "      apt update && apt install -y --reinstall hicolor-icon-theme adwaita-icon-theme yaru-theme-icon humanity-icon-theme gtk-update-icon-cache"
fi

step "7. 显示管理器 / 图形目标"
DM=$(cat /etc/X11/default-display-manager 2>/dev/null)
echo "默认 DM: ${DM:-（未设置）}"
case "$DM" in
  *gdm3*)    systemctl enable gdm3 2>&1 | sed 's/^/  /' || true ;;
  *lightdm*) systemctl enable lightdm 2>&1 | sed 's/^/  /' || true ;;
  *)         echo "  （没识别出 DM，保持原样；02-repair.sh 里会处理）" ;;
esac
echo "graphical.target 默认: $(systemctl get-default 2>/dev/null)"
systemctl set-default graphical.target 2>&1 | sed 's/^/  /' || true

step "8. 桌面依赖修复（可选）"
if [ "$WITH_DESKTOP" = 1 ]; then
  if [ -f "$SCRIPT_DIR/02-repair.sh" ]; then
    echo "调用 $SCRIPT_DIR/02-repair.sh （需要联网）"
    bash "$SCRIPT_DIR/02-repair.sh" || echo "!! 02-repair.sh 返回非 0，请查看它自己的日志"
  else
    echo "找不到 02-repair.sh，跳过"
  fi
else
  echo "未启用。若重启后仍进不去桌面，再依次执行："
  echo "  bash 02-repair.sh        # 补 GNOME/Ubuntu 桌面依赖 + 图标主题（需联网）"
  echo "  bash 03-fallback-xfce.sh # 还是不行就装 XFCE 兜底"
  echo "  （或直接 bash 00-run-all.sh 一键全流程）"
fi

step "完成"
echo "日志: $LOG"
echo
echo ">>> 现在执行: reboot <<<"
echo
echo "重启后如果还是进不去，请把这些贴给我 / 或推回仓库："
echo "  cat /root/diagnosis.txt          # 01-diagnose.sh 生成的完整证据"
echo "  ls -l /dev/tty*                  # 重启后的 tty 权限（验证是否自愈）"
echo "  journalctl -b -p err | tail -50  # 这次启动的错误"
