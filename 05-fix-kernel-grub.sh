#!/bin/bash
# 05-fix-kernel-grub.sh
# 把 GRUB 默认启动项固定到"装了 NVIDIA DKMS 的最新 6.8 内核"
# 适用于：你电脑里有 5.15 / 5.16 / 6.8.110 / 6.8.111 等多个内核，
#         但只有 6.8 系列才支持 RTX 5070（Blackwell, Driver 580+）
# 安全：会先备份 /etc/default/grub 到 /etc/default/grub.bak.<时间戳>

set -e

[ "$(id -u)" -eq 0 ] || { echo "请用 root 跑"; exit 1; }

echo "== 1. 列出所有已安装内核 =="
mapfile -t KERNS < <(ls /boot/vmlinuz-* 2>/dev/null | sed 's|/boot/vmlinuz-||' | sort -V)
printf '  %s\n' "${KERNS[@]}"
echo

echo "== 2. 在每个内核里检查 nvidia DKMS 模块是否已编译 =="
GOOD_KERN=""
# 优先挑最新的、且 nvidia 模块存在的 6.8.x
for k in $(printf '%s\n' "${KERNS[@]}" | grep -E '^6\.8' | sort -Vr); do
  # 看 DKMS 是不是 installed 到这个内核
  ok="no"
  if dkms status 2>/dev/null | grep -E "nvidia.*${k}.*installed" >/dev/null; then
    ok="yes"
  fi
  # 退一步：看内核 modules 目录里有没有 nvidia.ko*
  if [ "$ok" = "no" ] && find /lib/modules/"$k"/ -name 'nvidia*.ko*' 2>/dev/null | grep -q .; then
    ok="yes"
  fi
  echo "  $k -> nvidia 模块 = $ok"
  if [ "$ok" = "yes" ] && [ -z "$GOOD_KERN" ]; then
    GOOD_KERN="$k"
  fi
done

if [ -z "$GOOD_KERN" ]; then
  echo
  echo "!! 没有一个 6.8 内核已成功编译 nvidia 模块。"
  echo "   先 02-repair.sh 里会重新跑 dkms autoinstall，本步骤先选最新的 6.8 作为默认。"
  GOOD_KERN=$(printf '%s\n' "${KERNS[@]}" | grep -E '^6\.8' | sort -Vr | head -1)
fi

if [ -z "$GOOD_KERN" ]; then
  echo "!! 一个 6.8 内核都没有，请先 apt install linux-image-generic-hwe-22.04，本脚本中止"
  exit 2
fi

echo
echo "== 3. 选定默认内核: $GOOD_KERN =="

# Ubuntu 22.04 默认 grub.cfg 的菜单结构是:
#   menuentry 'Ubuntu' ...
#   submenu  'Advanced options for Ubuntu' ... {
#       menuentry 'Ubuntu, with Linux 6.8.111' ...
#       menuentry 'Ubuntu, with Linux 6.8.110' ...
#       ...
#   }
# GRUB_DEFAULT 推荐写成 'Advanced options for Ubuntu>Ubuntu, with Linux 6.8.111-xxx'

GRUB_CFG=/boot/grub/grub.cfg
[ -f "$GRUB_CFG" ] || { echo "!! 找不到 $GRUB_CFG"; exit 3; }

SUBMENU=$(grep -oE "submenu '[^']*Advanced options for Ubuntu[^']*'" "$GRUB_CFG" | head -1 | sed "s/^submenu '//;s/'$//")
ENTRY=$(grep -oE "menuentry 'Ubuntu, with Linux ${GOOD_KERN}[^']*'" "$GRUB_CFG" | head -1 | sed "s/^menuentry '//;s/'$//")

if [ -z "$SUBMENU" ] || [ -z "$ENTRY" ]; then
  echo "!! 没在 grub.cfg 里识别出 submenu/entry，回退用 index 方式"
  DEFAULT_LINE='GRUB_DEFAULT="1>0"'   # Advanced 第 1 项的第 0 个，通常就是最新
else
  DEFAULT_LINE="GRUB_DEFAULT=\"${SUBMENU}>${ENTRY}\""
fi

echo "将写入: $DEFAULT_LINE"

TS=$(date +%Y%m%d-%H%M%S)
cp -a /etc/default/grub /etc/default/grub.bak."$TS"
echo "已备份 /etc/default/grub -> /etc/default/grub.bak.$TS"

# 清掉旧的 GRUB_DEFAULT / GRUB_SAVEDEFAULT，写入新的
sed -i '/^GRUB_DEFAULT=/d;/^GRUB_SAVEDEFAULT=/d' /etc/default/grub
echo "$DEFAULT_LINE" >> /etc/default/grub
# 防止 saved 模式覆盖我们的默认
echo "GRUB_SAVEDEFAULT=false" >> /etc/default/grub
# 留点 timeout 方便你急救
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
grep -q '^GRUB_TIMEOUT_STYLE=' /etc/default/grub || echo 'GRUB_TIMEOUT_STYLE=menu' >> /etc/default/grub

echo
echo "== 4. 更新 grub =="
update-grub

echo
echo "== 完成 =="
echo "默认启动内核: $GOOD_KERN"
echo "如果想现场验证: cat /boot/grub/grub.cfg | grep -A1 'set default'"
