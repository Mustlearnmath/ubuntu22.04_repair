#!/bin/bash
# 03-fallback-xfce.sh
# GNOME 实在修不好就用 XFCE + LightDM 兜底，保证能进图形界面
# 进去后 conda / ROS / Isaac Sim 全部能跑（这些和桌面环境无关）
# 之后你可以慢慢修 GNOME，或就一直用 XFCE

set -u
[ "$(id -u)" -eq 0 ] || { echo "请用 root 跑"; exit 1; }

TS=$(date +%Y%m%d-%H%M%S)
LOG=/root/fallback-xfce-"$TS".log
exec > >(tee -a "$LOG") 2>&1

echo "========== 装 XFCE4 + LightDM =========="
apt update
apt install -y --no-install-recommends \
    xfce4 xfce4-goodies xfce4-terminal \
    lightdm lightdm-gtk-greeter \
    network-manager-gnome \
    fonts-noto-cjk fonts-dejavu \
    dbus-x11 policykit-1 \
    xorg xserver-xorg

echo "========== 把 LightDM 设为默认 DM =========="
echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager
echo "lightdm shared/default-x-display-manager select lightdm" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure lightdm
systemctl disable gdm3 2>/dev/null || true
systemctl enable lightdm

echo "========== LightDM 默认会话设为 xfce =========="
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/60-xfce.conf <<'EOF'
[Seat:*]
user-session=xfce
greeter-session=lightdm-gtk-greeter
EOF

echo "========== graphical.target 默认 =========="
systemctl set-default graphical.target

echo
echo "========== 完成 =========="
echo "执行: reboot"
echo "登录界面右上角齿轮可选 XFCE Session"
