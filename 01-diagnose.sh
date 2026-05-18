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

hr "完成"
echo "诊断报告已写入 $OUT"
echo "请把它贴出来或 git push 到仓库后让 AI 分析。"
