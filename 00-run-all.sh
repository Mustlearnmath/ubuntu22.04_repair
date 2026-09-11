#!/bin/bash
# 00-run-all.sh —— 一键修复入口
# ============================================================================
# 在 Recovery root shell 里 git clone 之后，只需要这一条命令：
#
#     bash 00-run-all.sh
#
# 执行顺序：
#   1) 01-diagnose.sh            只读收集证据 -> /root/diagnosis.txt
#   2) 07-fix-tty-and-login.sh   恢复 /dev/tty* 权限 + 修登录/日志服务（本次事故重点）
#   3) 05-fix-kernel-grub.sh     把 GRUB 默认启动项固定到能用的 6.8 内核
#   4) 02-repair.sh              补桌面依赖 + 图标主题 + 关 Wayland（需要联网）
#   最后提示 reboot
#
# 参数：
#   --no-desktop   跳过第 4 步（不联网也能跑完全流程）
#   --diagnose-only  只跑第 1 步
# ============================================================================

set -u

cd "$(dirname "$0")" || exit 1
chmod +x ./*.sh 2>/dev/null || true

RUN_DESKTOP=1
DIAG_ONLY=0
for a in "$@"; do
  case "$a" in
    --no-desktop)    RUN_DESKTOP=0 ;;
    --diagnose-only) DIAG_ONLY=1 ;;
    -h|--help)       sed -n '2,20p' "$0"; exit 0 ;;
  esac
done

banner() { echo; echo "==================== $* ===================="; }

[ "$(id -u)" -eq 0 ] || { echo "请用 root 运行（Recovery 菜单选 root，就是 root shell）"; exit 1; }

banner "0. 环境与网络自检"
echo "时间: $(date)"
uname -r
if findmnt -no OPTIONS / 2>/dev/null | grep -qE '(^|,)ro(,|$)'; then
  echo "根分区只读 -> remount rw"
  mount -o remount,rw / 2>&1 || echo "!! remount 失败，请手动: mount -o remount,rw /"
fi

NET=0
if ping -c1 -W3 archive.ubuntu.com >/dev/null 2>&1 || ping -c1 -W3 mirrors.aliyun.com >/dev/null 2>&1; then
  NET=1
  echo "网络: 可用"
else
  echo "网络: 不可用"
  echo "  -> 若要补装桌面依赖，请回 Recovery 菜单先选『network / Enable networking』再重跑本脚本"
fi

banner "1. 诊断（只读，产物 /root/diagnosis.txt）"
bash 01-diagnose.sh || true
echo
echo ">>> 证据已写入 /root/diagnosis.txt（可 cat 出来后发给我）"
if [ "$DIAG_ONLY" = 1 ]; then
  echo "（--diagnose-only，到此结束）"
  exit 0
fi

banner "2. 恢复 /dev/tty* 权限 + 修复登录/日志服务"
bash 07-fix-tty-and-login.sh || true

banner "3. 固定可用的 6.8 内核为 GRUB 默认项"
bash 05-fix-kernel-grub.sh || true

banner "4. 桌面依赖 / 图标主题 / X11 修复"
if [ "$RUN_DESKTOP" = 0 ]; then
  echo "（--no-desktop，跳过）"
elif [ "$NET" = 1 ]; then
  bash 02-repair.sh || true
else
  echo "跳过：没有网络。联网后单独执行: bash 02-repair.sh"
  echo "（或者在 Recovery 菜单里选 network 后重跑: bash 00-run-all.sh）"
fi

banner "完成"
cat <<'EOF'
下一步：
  1) reboot
  2) 还进不去桌面  ->  bash 03-fallback-xfce.sh  然后 reboot
  3) 想继续定位    ->  cat /root/diagnosis.txt  （发给我）
                        ls -l /dev/tty*
                        journalctl -b -p err | tail -50
EOF
