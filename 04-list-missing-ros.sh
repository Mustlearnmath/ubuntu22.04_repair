#!/bin/bash
# 04-list-missing-ros.sh
# 扫 apt history.log*，列出所有被 Remove/Purge 的 ros-humble-* 包
# 生成可直接执行的 apt install 命令到 /root/reinstall-ros.sh
# 安全：只读，只输出脚本，不安装

OUT=/root/reinstall-ros.sh

PKGS=$(zcat -f /var/log/apt/history.log* 2>/dev/null \
  | grep -E '^(Remove|Purge):' \
  | tr ',' '\n' \
  | grep -oE 'ros-humble-[a-z0-9.+-]+' \
  | sort -u)

if [ -z "$PKGS" ]; then
  echo "没在 apt history 里找到被卸载的 ros-humble-* 包"
  exit 0
fi

echo "找到以下被卸载的 ROS 包："
echo "$PKGS"

{
  echo "#!/bin/bash"
  echo "# 由 04-list-missing-ros.sh 生成于 $(date)"
  echo "set -e"
  echo "apt update"
  echo "apt install -y \\"
  echo "$PKGS" | sed 's/^/  /; s/$/ \\/' | sed '$ s/ \\$//'
} > "$OUT"
chmod +x "$OUT"

echo
echo "已生成: $OUT"
echo "进桌面后执行: sudo bash $OUT"
