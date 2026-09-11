#!/bin/bash
# 01-diagnose.sh
# 只读诊断脚本：收集所有用于判断"为什么进不去桌面"的证据
# 适用于 Ubuntu 22.04 + NVIDIA + GNOME/LightDM
# 在 Recovery root shell 下运行
# 产物：/root/diagnosis.txt

OUT=/root/diagnosis.txt
exec > >(tee "$OUT") 2>&1

hr() { echo; echo "================ $* ================"; }
safe() { echo "\$ $*"; "$@" 2>&1 || true; echo; }

hr "0. 基本信息"
safe date
safe uname -a
safe lsb_release -a
safe cat /etc/os-release

hr "1. 磁盘 / Inode"
safe df -hT
safe df -i

hr "2. 内核列表 & 当前 GRUB 默认"
echo "已安装的 vmlinuz:"
ls -lh /boot/vmlinuz-* 2>/dev/null
echo
echo "已安装的内核包:"
dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/ {print $2,$3}'
echo
echo "GRUB 默认项 (/etc/default/grub 中 GRUB_DEFAULT):"
grep -E '^GRUB_DEFAULT|^GRUB_TIMEOUT|^GRUB_SAVEDEFAULT' /etc/default/grub
echo
echo "grub.cfg 中可见的 menuentry:"
grep -E "menuentry '|submenu '" /boot/grub/grub.cfg 2>/dev/null | head -40
echo
echo "上次启动的内核:"
uname -r

hr "3. NVIDIA 驱动 & DKMS"
safe nvidia-smi
echo "已安装 nvidia 包:"
dpkg -l | grep -E 'nvidia-(driver|dkms|kernel|utils|compute|firmware)' || true
echo
echo "DKMS 状态 (重点看每个内核下 nvidia 是否都 installed):"
safe dkms status
echo "已加载的内核模块 nvidia*:"
lsmod | grep -i nvidia || echo "(未加载)"

hr "4. CUDA"
echo "/usr/local 下的 cuda 目录:"
ls -ld /usr/local/cuda* 2>/dev/null
echo
if command -v nvcc >/dev/null 2>&1; then
  nvcc --version
else
  /usr/local/cuda/bin/nvcc --version 2>/dev/null || echo "未找到 nvcc"
fi
echo
echo "/etc/ld.so.conf.d/ 中 cuda 相关:"
ls /etc/ld.so.conf.d/ | grep -i cuda || true

hr "5. xsessions 会话文件（GNOME/Ubuntu/Wayland）"
ls -l /usr/share/xsessions/ 2>/dev/null
ls -l /usr/share/wayland-sessions/ 2>/dev/null
echo
echo "ubuntu.desktop 内容:"
cat /usr/share/xsessions/ubuntu.desktop 2>/dev/null || echo "(缺失)"
echo
echo "ubuntu-xorg.desktop 内容:"
cat /usr/share/xsessions/ubuntu-xorg.desktop 2>/dev/null || echo "(缺失)"
echo
echo "Exec= 指向的二进制是否存在 + 可执行:"
for f in /usr/share/xsessions/*.desktop /usr/share/wayland-sessions/*.desktop; do
  [ -f "$f" ] || continue
  ex=$(grep -m1 '^Exec=' "$f" | sed 's/^Exec=//' | awk '{print $1}')
  echo "  $f -> $ex"
  if [ -n "$ex" ]; then
    ls -l "$ex" 2>/dev/null || echo "    !! 不存在: $ex"
  fi
done

hr "6. 桌面核心二进制是否存在"
for b in gnome-session gnome-shell mutter gdm3 lightdm Xorg dbus-daemon Xwayland; do
  p=$(command -v "$b" 2>/dev/null)
  if [ -n "$p" ]; then
    ls -l "$p"
  else
    echo "!! 缺失: $b"
  fi
done

hr "7. Display Manager 状态"
echo "当前 DM:"
cat /etc/X11/default-display-manager 2>/dev/null
echo
systemctl status gdm3 --no-pager 2>/dev/null | head -20
echo
systemctl status lightdm --no-pager 2>/dev/null | head -20

hr "8. apt history —— 哪些包被 Remove / Purge（金钥匙！）"
echo "----- 最近 5 次 apt 事务，含 Remove/Purge -----"
zcat -f /var/log/apt/history.log* 2>/dev/null \
  | awk 'BEGIN{RS=""; ORS="\n\n"} /Remove:|Purge:/' \
  | tail -200
echo
echo "----- 被卸载过的 ros / gnome / fcitx / ibus / desktop 包名 -----"
zcat -f /var/log/apt/history.log* 2>/dev/null \
  | grep -E '^(Remove|Purge):' \
  | tr ',' '\n' \
  | grep -E 'ros-humble|gnome-|mutter|gdm|lightdm|ubuntu-desktop|fcitx|ibus|sogou|xorg' \
  | sort -u

hr "9. 输入法残留（fcitx / ibus / 搜狗）"
dpkg -l | grep -E 'fcitx|ibus|sogou' || echo "(无输入法包)"
echo
echo "/etc/X11/Xsession.d/ 中可疑钩子:"
ls -l /etc/X11/Xsession.d/ 2>/dev/null
grep -l -E 'fcitx|ibus|sogou|XMODIFIERS|GTK_IM_MODULE|QT_IM_MODULE' \
  /etc/X11/Xsession.d/* /etc/profile.d/* /etc/environment 2>/dev/null
echo
echo "im-config 当前:"
cat /etc/X11/xinit/xinputrc 2>/dev/null
ls -l /etc/alternatives/xinput-* 2>/dev/null

hr "10. D-Bus / AccountsService"
systemctl status dbus --no-pager 2>/dev/null | head -10
ls /var/lib/AccountsService/users/ 2>/dev/null
echo
echo "用户列表 /home:"
ls /home/

hr "11. LightDM 日志关键错误"
tail -120 /var/log/lightdm/lightdm.log 2>/dev/null | grep -E 'CRITICAL|WARNING|Failed|argv' || echo "(无 lightdm 日志)"
echo
echo "x-0-greeter.log 尾部:"
tail -60 /var/log/lightdm/x-0-greeter.log 2>/dev/null

hr "12. GDM 日志"
tail -120 /var/log/gdm3/*.log 2>/dev/null | tail -120
echo
journalctl -b -u gdm3 --no-pager 2>/dev/null | tail -60

hr "13. Xorg 日志关键报错"
for L in /var/log/Xorg.0.log /var/log/Xorg.1.log /home/*/.local/share/xorg/Xorg.0.log; do
  [ -f "$L" ] || continue
  echo "--- $L ---"
  grep -E '\(EE\)|\(WW\)' "$L" | head -40
done

hr "14. journalctl 上一次启动 -> 找 session/dbus/gdm/mutter 报错"
journalctl -b -p err --no-pager 2>/dev/null | tail -80

hr "15. dpkg 损坏 / 半装"
dpkg -l | awk '$1!="ii" && $1!="rc" {print $0}' | head -40
echo
echo "等待 dpkg --configure -a 的:"
dpkg --audit 2>&1 | head -20

hr "16. /home 占用 & 用户家目录是否完好"
du -sh /home/* 2>/dev/null
echo
for u in $(ls /home); do
  echo "--- /home/$u ---"
  ls -la /home/"$u" 2>/dev/null | head -15
done

hr "17. conda / Isaac Sim / ROS 简检"
for u in $(ls /home); do
  for d in anaconda3 miniconda3 isaacsim .local/share/ov; do
    [ -e /home/"$u"/"$d" ] && ls -ld /home/"$u"/"$d"
  done
done
echo
ls -ld /opt/ros/* 2>/dev/null

hr "18. ★ /dev 挂载类型 & tty 权限（chmod 666 /dev*/tty* 事故重点）"
echo "/dev 挂载："
findmnt -no FSTYPE,SOURCE,OPTIONS /dev 2>/dev/null || grep ' /dev ' /proc/mounts
DEVFS=$(findmnt -no FSTYPE /dev 2>/dev/null || awk '$2=="/dev"{print $3}' /proc/mounts)
if [ "$DEVFS" = "devtmpfs" ]; then
  echo ">>> /dev 是 devtmpfs：重启后内核+udev 会重建设备节点，chmod 本身不会持久。"
  echo ">>> 若重启后仍进不去桌面，真正原因多半在别处（看第 19/20 节）。"
else
  echo ">>> !! /dev 不是 devtmpfs（FSTYPE=${DEVFS:-未知}）：权限改动会持久，必须修回来。"
fi
echo
echo "tty / console 节点数字权限（标准：/dev/tty=666，tty0..63=620，ttyS*/USB=660，console=600）："
stat -c '%n  %a  %U:%G' /dev/tty /dev/tty[0-9]* /dev/tty[A-Za-z]* /dev/console 2>/dev/null
echo
ls -l /dev/tty /dev/tty[0-9]* /dev/tty[A-Za-z]* /dev/console 2>/dev/null
echo
echo "!! /dev 下『其他用户可写』的节点（正常只应有 null/zero/tty/ptmx 等少数几个）："
find /dev -maxdepth 1 \( -type c -o -type b \) -perm -0002 -printf '%m %u:%g %p\n' 2>/dev/null | sort | head -60
echo
echo "常见目录权限（正常：/tmp=1777 /var/tmp=1777 /dev/shm=1777 /run/lock=1777 /run=755）："
stat -c '%n  %a  %U:%G' /tmp /var/tmp /dev/shm /run/lock /run 2>/dev/null

hr "19. systemd 单元状态（failed / masked / enabled）"
echo "----- 本次启动失败的单元 -----"
systemctl --failed --no-pager 2>/dev/null
echo
echo "----- 被 mask 的单元 -----"
systemctl list-unit-files --state=masked --no-pager 2>/dev/null | head -30
echo
echo "----- 关键单元（state = enabled/disabled/masked，active = active/failed/inactive）-----"
for u in systemd-logind systemd-journald systemd-journald.socket systemd-udevd dbus dbus.socket \
         systemd-user-sessions getty@tty1 gdm3 lightdm display-manager rsyslog; do
  printf '  %-28s %-12s %s\n' "$u" "$(systemctl is-enabled "$u" 2>&1)" "$(systemctl is-active "$u" 2>&1)"
done
echo
echo "----- /etc/systemd/system 下的 drop-in 覆盖文件 -----"
ls -l /etc/systemd/system/*.d 2>/dev/null
ls -l /etc/systemd/system/*.service.d/*.conf /etc/systemd/system/*.socket.d/*.conf 2>/dev/null
echo
echo "----- logind.conf 非注释行 -----"
grep -vE '^\s*(#|$)' /etc/systemd/logind.conf 2>/dev/null || echo "(全部注释，默认配置)"
echo "----- journald.conf 非注释行 -----"
grep -vE '^\s*(#|$)' /etc/systemd/journald.conf 2>/dev/null || echo "(全部注释，默认配置)"

hr "20. logind / journald / dbus / DM 日志与上一次启动的错误"
echo "----- systemd-logind -----"
systemctl status systemd-logind --no-pager -l 2>/dev/null | head -20
journalctl -b -u systemd-logind --no-pager 2>/dev/null | tail -60
echo
echo "----- systemd-journald（即 logging / 日志服务）-----"
systemctl status systemd-journald --no-pager -l 2>/dev/null | head -20
journalctl -b -u systemd-journald --no-pager 2>/dev/null | tail -40
echo
echo "----- dbus -----"
journalctl -b -u dbus -u dbus.socket --no-pager 2>/dev/null | tail -30
echo
echo "----- 上一次启动的 warning/err（在 Recovery 里跑时，这里才是你真实故障的那次启动）-----"
journalctl -b -1 -p warning --no-pager 2>/dev/null | tail -100
echo
echo "----- /var/log/syslog 尾部 -----"
tail -60 /var/log/syslog 2>/dev/null

hr "21. journal 目录权限 & 日志完整性"
stat -c '%n  %a  %U:%G' /var/log/journal /run/log/journal 2>/dev/null
ls -ld /var/log/journal/* 2>/dev/null | head
echo
echo "/var/log 占用:"
du -sh /var/log 2>/dev/null
echo
echo "journal 自检:"
journalctl --verify --no-pager 2>&1 | tail -5

hr "22. 图标主题 / 会话缓存（图标丢失问题相关）"
ls -d /usr/share/icons/hicolor /usr/share/icons/Adwaita /usr/share/icons/Yaru 2>/dev/null
echo
ls -l /usr/share/icons/hicolor/index.theme 2>/dev/null || echo "!! 缺 /usr/share/icons/hicolor/index.theme —— 图标会大面积丢失"
echo
dpkg -l hicolor-icon-theme adwaita-icon-theme yaru-theme-icon 2>/dev/null | awk '/^ii/ {print $1,$2,$3}'
echo
which gtk-update-icon-cache 2>/dev/null || echo "!! 缺 gtk-update-icon-cache"
echo
for u in $(ls /home); do
  echo "--- /home/$u 会话缓存 ---"
  ls -ld /home/"$u"/.cache 2>/dev/null
  du -sh /home/"$u"/.cache 2>/dev/null
done

hr "完成"
echo "诊断报告已写入 $OUT"
echo "请把它贴出来或 git push 到仓库后让 AI 分析。"
