#!/bin/bash
# 99-backup-home.sh
# 在动大手术（重装系统）之前把关键数据备份到指定挂载点
# 用法： bash 99-backup-home.sh /mnt/usb-backup
# 备份内容：
#   - /home/*  （排除 .cache / Trash / Downloads）
#   - /etc 关键配置
#   - apt 已装包清单（用于重装后还原）
#   - dpkg/grub/X11/gdm/lightdm 配置快照

set -e

DEST="${1:-}"
if [ -z "$DEST" ] || [ ! -d "$DEST" ]; then
  echo "用法: bash $0 <已挂载好的备份目录>"
  echo "例如: mount /dev/sdb1 /mnt/usb && bash $0 /mnt/usb"
  exit 1
fi

[ "$(id -u)" -eq 0 ] || { echo "请用 root 跑"; exit 1; }
command -v rsync >/dev/null || apt install -y rsync

TS=$(date +%Y%m%d-%H%M%S)
BK="$DEST/ubuntu-backup-$TS"
mkdir -p "$BK"
echo "备份到: $BK"

echo "== 1. /home =="
rsync -aHAX --info=progress2 \
  --exclude='.cache' \
  --exclude='.local/share/Trash' \
  --exclude='snap/*/common/.cache' \
  --exclude='Downloads' \
  /home/ "$BK/home/"

echo "== 2. /root =="
rsync -aHAX /root/ "$BK/root/" --exclude='.cache'

echo "== 3. /etc 快照 =="
tar czf "$BK/etc.tar.gz" /etc 2>/dev/null || true

echo "== 4. apt 已装包清单 =="
dpkg --get-selections > "$BK/dpkg-selections.txt"
apt-mark showmanual > "$BK/apt-manual.txt"
cp -a /var/log/apt "$BK/apt-log" 2>/dev/null || true

echo "== 5. 关键路径快照（/opt /usr/local） =="
ls -la /opt > "$BK/opt-listing.txt" 2>/dev/null
ls -la /usr/local > "$BK/usrlocal-listing.txt" 2>/dev/null
[ -d /opt/ros ] && ls /opt/ros > "$BK/ros-versions.txt"

echo "== 6. NVIDIA / CUDA =="
nvidia-smi > "$BK/nvidia-smi.txt" 2>&1 || true
dpkg -l | grep -E 'nvidia|cuda' > "$BK/nvidia-cuda-pkgs.txt" 2>&1 || true

echo
echo "完成。备份大小:"
du -sh "$BK"
