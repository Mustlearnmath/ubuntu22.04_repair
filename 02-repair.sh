#!/bin/bash
# 02-repair.sh
# 对症修复 Ubuntu 22.04 + NVIDIA RTX 5070 Ti 桌面会话启动失败
# 处理：
#   - apt autoremove 误删的 GNOME/Ubuntu Desktop 依赖
#   - fcitx / ibus / 搜狗输入法残留钩子
#   - NVIDIA + GDM Wayland 卡 Logo（强制 X11）
#   - DKMS 在 6.8 内核上重建 nvidia 模块
#   - dpkg / AccountsService 缓存
# 安全：所有改动都打日志，关键配置先备份
# 用法：在 Recovery root shell 下，**确认已联网**，然后：
#       bash 02-repair.sh 2>&1 | tee /root/repair.log

set -u

[ "$(id -u)" -eq 0 ] || { echo "请用 root 跑"; exit 1; }

TS=$(date +%Y%m%d-%H%M%S)
LOG=/root/repair-"$TS".log
exec > >(tee -a "$LOG") 2>&1

step() { echo; echo "########## $* ##########"; }
backup() { [ -e "$1" ] && cp -a "$1" "$1.bak.$TS" && echo "已备份: $1 -> $1.bak.$TS"; }

step "0. 网络自检"
if ! ping -c 1 -W 3 archive.ubuntu.com >/dev/null 2>&1 \
   && ! ping -c 1 -W 3 mirrors.aliyun.com >/dev/null 2>&1; then
  echo "!! 网络不通。请回 Recovery 菜单选 Enable networking，再试。"
  exit 2
fi

step "1. 备份 /etc 关键文件"
mkdir -p /root/repair-backup-"$TS"
cp -a /etc/default/grub /root/repair-backup-"$TS"/ 2>/dev/null || true
cp -a /etc/gdm3 /root/repair-backup-"$TS"/ 2>/dev/null || true
cp -a /etc/lightdm /root/repair-backup-"$TS"/ 2>/dev/null || true
cp -a /etc/X11/Xsession.d /root/repair-backup-"$TS"/ 2>/dev/null || true
cp -a /etc/X11/default-display-manager /root/repair-backup-"$TS"/ 2>/dev/null || true
echo "备份目录: /root/repair-backup-$TS"

step "2. 修 dpkg 半装状态"
dpkg --configure -a || true
apt -y --fix-broken install || true

step "3. apt update"
apt update

step "4. 补装核心桌面 / X11 / 会话依赖（精确包名）"
# 不用 ubuntu-desktop 大水漫灌，只补图形会话最关键的几个
CORE_PKGS=(
  gnome-session
  gnome-session-bin
  gnome-shell
  mutter
  gdm3
  ubuntu-session
  ubuntu-settings
  gsettings-desktop-schemas
  gnome-settings-daemon
  gnome-control-center
  gnome-terminal
  nautilus
  xorg
  xserver-xorg
  xserver-xorg-core
  xserver-xorg-video-nvidia-580
  xinit
  dbus
  dbus-x11
  dbus-user-session
  accountsservice
  policykit-1
  network-manager
  network-manager-gnome
  lightdm
  lightdm-gtk-greeter
  fonts-dejavu
  fonts-noto-cjk
)
# 注意：xserver-xorg-video-nvidia-XXX 版本号要跟当前 driver 对得上；580 是你现在用的
apt install -y --no-install-recommends "${CORE_PKGS[@]}" || true
# 再 reinstall 一遍保证文件齐
apt install --reinstall -y gnome-session gnome-session-bin gnome-shell mutter gdm3 ubuntu-session dbus-x11 accountsservice || true

step "5. ubuntu-desktop 元包（防止还有遗漏）"
apt install -y ubuntu-desktop-minimal || true

step "6. 清理 fcitx / ibus / 搜狗 残留钩子"
# 删二进制包
apt purge -y 'fcitx*' 'sogou*' 2>/dev/null || true
# ibus 不删（它是 GNOME 默认），但要确保是干净的
apt install --reinstall -y ibus ibus-gtk ibus-gtk3 || true

# 清 X session 注入文件
for f in /etc/X11/Xsession.d/*fcitx* /etc/X11/Xsession.d/*sogou* \
         /etc/profile.d/*fcitx* /etc/profile.d/*sogou*; do
  [ -e "$f" ] && { echo "删: $f"; rm -f "$f"; }
done

# /etc/environment 里清 fcitx 残留环境变量
if grep -qE 'fcitx|sogou' /etc/environment 2>/dev/null; then
  backup /etc/environment
  sed -i '/fcitx/Id;/sogou/Id' /etc/environment
fi

# 用户家目录里的 autostart 残留
for u in $(ls /home/); do
  for f in /home/"$u"/.config/autostart/fcitx*.desktop \
           /home/"$u"/.config/autostart/sogou*.desktop \
           /home/"$u"/.xprofile /home/"$u"/.xinputrc; do
    if [ -f "$f" ] && grep -qE 'fcitx|sogou' "$f" 2>/dev/null; then
      echo "清理: $f"
      backup "$f"
      sed -i '/fcitx/Id;/sogou/Id' "$f" 2>/dev/null || rm -f "$f"
    fi
  done
done

# im-config 回默认
update-alternatives --set xinput-zh_CN /etc/X11/xinit/xinput.d/ibus 2>/dev/null || true
im-config -n ibus 2>/dev/null || true

step "7. NVIDIA + GDM 强制走 X11（关 Wayland）"
backup /etc/gdm3/custom.conf
if [ -f /etc/gdm3/custom.conf ]; then
  # 取消注释或新增
  if grep -q '^#\?WaylandEnable' /etc/gdm3/custom.conf; then
    sed -i 's/^#\?WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/custom.conf
  else
    sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm3/custom.conf
  fi
else
  cat > /etc/gdm3/custom.conf <<'EOF'
[daemon]
WaylandEnable=false
EOF
fi
echo "/etc/gdm3/custom.conf:"
cat /etc/gdm3/custom.conf

# NVIDIA 官方 hook 同步禁 Wayland
NV_RULE=/lib/udev/rules.d/61-gdm.rules
if [ -f "$NV_RULE" ]; then
  echo "$NV_RULE 已存在（NVIDIA 默认禁 Wayland 规则）"
fi

step "8. 修 xsessions 会话文件"
# 强制使用 X11 版 ubuntu 会话
if [ ! -f /usr/share/xsessions/ubuntu.desktop ]; then
  echo "ubuntu.desktop 缺失，重装 ubuntu-session"
  apt install --reinstall -y ubuntu-session
fi
# 看 Exec 是否指向真实文件
for f in /usr/share/xsessions/*.desktop; do
  ex=$(grep -m1 '^Exec=' "$f" | sed 's/^Exec=//' | awk '{print $1}')
  if [ -n "$ex" ] && [ ! -x "$ex" ]; then
    echo "!! $f 的 Exec=$ex 不可执行，尝试 reinstall 提供它的包"
    pkg=$(dpkg -S "$ex" 2>/dev/null | cut -d: -f1 | head -1)
    [ -n "$pkg" ] && apt install --reinstall -y "$pkg"
  fi
done
chmod 644 /usr/share/xsessions/*.desktop 2>/dev/null

step "9. 重建 NVIDIA DKMS 模块（覆盖所有已装内核）"
echo "当前 DKMS:"
dkms status || true
# 找出 nvidia 源码版本
NV_VER=$(dkms status 2>/dev/null | grep -oE 'nvidia(/| )[0-9.]+' | head -1 | grep -oE '[0-9.]+')
if [ -z "$NV_VER" ]; then
  NV_VER=$(ls /usr/src/ 2>/dev/null | grep -oE 'nvidia-[0-9.]+' | head -1 | sed 's/nvidia-//')
fi
echo "检测到 NVIDIA 源码版本: ${NV_VER:-未知}"

# 给所有 6.8 内核都装 headers，再 autoinstall
for k in $(ls /boot/vmlinuz-* | sed 's|/boot/vmlinuz-||' | grep -E '^6\.8'); do
  apt install -y "linux-headers-$k" 2>/dev/null || true
done
if [ -n "$NV_VER" ]; then
  for k in $(ls /boot/vmlinuz-* | sed 's|/boot/vmlinuz-||' | grep -E '^6\.8'); do
    dkms install -m nvidia -v "$NV_VER" -k "$k" --force 2>&1 | tail -10 || true
  done
fi
echo "重建后 DKMS:"
dkms status || true

step "10. 清 AccountsService / 会话缓存"
# AccountsService 用户配置缓存（不是用户数据），损坏会让会话起不来
if [ -d /var/lib/AccountsService/users ]; then
  cp -a /var/lib/AccountsService/users /root/repair-backup-"$TS"/AccountsService-users || true
  rm -f /var/lib/AccountsService/users/*
  echo "已清 /var/lib/AccountsService/users/"
fi
# 用户的 gdm/sessions cache
for u in $(ls /home/); do
  rm -rf /home/"$u"/.cache/gdm3 \
         /home/"$u"/.cache/sessions \
         /home/"$u"/.cache/mutter \
         /home/"$u"/.config/dconf/user.bak 2>/dev/null
  # 备份 dconf，避免极端 ID 损坏
  if [ -f /home/"$u"/.config/dconf/user ]; then
    cp -a /home/"$u"/.config/dconf/user /home/"$u"/.config/dconf/user.bak."$TS"
  fi
done

step "11. 选 GDM3 为默认 DM（LightDM 当前没修好）"
echo "/usr/sbin/gdm3" > /etc/X11/default-display-manager
# debconf 也同步
echo "gdm3 shared/default-x-display-manager select gdm3" | debconf-set-selections 2>/dev/null || true
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure gdm3 2>&1 | tail -5 || true
systemctl enable gdm3 || true

step "12. graphical.target 设为默认"
systemctl set-default graphical.target || true

step "13. 最终验证"
echo "DM 当前: $(cat /etc/X11/default-display-manager)"
echo "graphical 默认: $(systemctl get-default)"
echo "WaylandEnable:"
grep -i wayland /etc/gdm3/custom.conf || true
echo "ubuntu.desktop Exec:"
grep -m1 '^Exec=' /usr/share/xsessions/ubuntu.desktop 2>/dev/null
echo "gnome-session:"
ls -l /usr/bin/gnome-session 2>/dev/null
echo "DKMS:"
dkms status

step "完成"
echo "日志: $LOG"
echo "备份: /root/repair-backup-$TS"
echo
echo ">>> 现在执行: reboot <<<"
echo "如果重启后仍卡 Logo / 仍失败，跑 03-fallback-xfce.sh 装 XFCE 兜底"
