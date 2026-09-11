#!/bin/bash
# ============================================================================
# 08-push-logs.sh —— 把现场证据（诊断报告 + 各脚本日志 + 现场快照）一键推回 GitHub
#
# 用途：修完还是有问题时，不用手抄日志，直接推上去在线看。
#
# 用法（Ubuntu 里，普通终端 / TTY / Recovery root shell 都行）：
#   cd /root/ubuntu22.04_repair
#   sudo bash 08-push-logs.sh
#
#   免交互写法：
#   GH_USER=Mustlearnmath GH_TOKEN=github_pat_xxx sudo -E bash 08-push-logs.sh
#
# 它会：
#   1) 现场抓一份快照：失败单元 / /dev 权限 / logind+journald+dbus 日志 /
#      上一次与本次启动的错误 / gdm3 / 图标主题 / DKMS+nvidia-smi / GRUB 默认项
#   2) 收集 /root 下所有脚本产生的报告与日志（diagnosis.txt 等）
#   3) 放进仓库 logs/<主机名>-<时间戳>/，commit 后推送到 origin main
#   4) 打印在线查看地址
#
# 安全说明：
#   * GitHub 不再支持密码推送，必须用 Personal Access Token (PAT)。
#   * token 通过临时 GIT_ASKPASS 脚本 + 环境变量一次性交给 git，
#     不会写进 .git/config、不会写进仓库文件、用完立即销毁。
#   * 推完建议清一下终端历史： history -c
# ============================================================================

set -u

REPO_SLUG="Mustlearnmath/ubuntu22.04_repair"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR" || { echo "!! 进不去脚本目录: $SCRIPT_DIR"; exit 1; }

step() { echo; echo "########## $* ##########"; }

step "0. 前置检查"
if ! command -v git >/dev/null 2>&1; then
  echo "!! 没装 git。先: apt update && apt install -y git"
  exit 1
fi
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "!! 当前目录不是 git 仓库：$SCRIPT_DIR"
  echo "   请先克隆： cd /root && git clone https://github.com/${REPO_SLUG}.git"
  exit 1
fi
echo "git: $(git --version)"
echo "仓库: $SCRIPT_DIR"
[ "$(id -u)" = 0 ] || echo "提示：当前不是 root，可能读不到 /root 下的日志（用 sudo 重跑最保险）"

HOST=$(hostname 2>/dev/null || echo unknown-host)
STAMP=$(date +%Y%m%d-%H%M%S)
DEST="logs/${HOST}-${STAMP}"
mkdir -p "$DEST"

step "1. 现场快照 -> $DEST/snapshot.txt"
SNAP="$DEST/snapshot.txt"
{
  echo "# 现场快照  $(date)"
  echo
  echo "## 主机 / 内核 / 系统"
  hostname
  uname -a
  head -3 /etc/os-release 2>&1
  echo
  echo "## 默认 target / 显示管理器"
  systemctl get-default 2>&1
  cat /etc/X11/default-display-manager 2>&1
  echo
  echo "## /dev 挂载 + tty 权限（本次事故重点）"
  findmnt -no FSTYPE,SOURCE,OPTIONS /dev 2>&1
  stat -c '%n  %a  %U:%G' /dev/tty /dev/tty[0-9]* /dev/tty[A-Za-z]* /dev/console 2>&1
  ls -l /dev/tty /dev/tty[0-9]* /dev/tty[A-Za-z]* /dev/console 2>&1
  echo
  echo "## 失败的 systemd 单元"
  systemctl --failed --no-pager 2>&1
  echo
  echo "## 关键单元（enabled/active）"
  for u in systemd-logind systemd-journald systemd-journald.socket systemd-udevd \
           dbus dbus.socket systemd-user-sessions getty@tty1 gdm3 lightdm display-manager; do
    printf '  %-28s %-12s %s\n' "$u" "$(systemctl is-enabled "$u" 2>&1)" "$(systemctl is-active "$u" 2>&1)"
  done
  echo
  echo "## logind / journald / dbus 本次启动日志"
  journalctl -b -u systemd-logind --no-pager 2>&1 | tail -40
  journalctl -b -u systemd-journald --no-pager 2>&1 | tail -20
  journalctl -b -u dbus --no-pager 2>&1 | tail -20
  echo
  echo "## 上一次启动的错误 journalctl -b -1 -p err"
  journalctl -b -1 -p err --no-pager 2>&1 | tail -120
  echo
  echo "## 本次启动的错误 journalctl -b -p err"
  journalctl -b -p err --no-pager 2>&1 | tail -120
  echo
  echo "## gdm3 日志"
  journalctl -b -u gdm3 --no-pager 2>&1 | tail -80
  echo
  echo "## Xorg 报错"
  for L in /var/log/Xorg.0.log /var/log/Xorg.1.log; do
    [ -f "$L" ] && { echo "--- $L ---"; grep -E '\(EE\)|\(WW\)' "$L" 2>&1 | head -40; }
  done
  echo
  echo "## 图标主题（图标丢失相关）"
  ls -l /usr/share/icons/hicolor/index.theme /usr/share/icons/Adwaita/index.theme 2>&1
  dpkg -l hicolor-icon-theme adwaita-icon-theme yaru-theme-icon 2>/dev/null | awk '/^ii/ {print $2,$3}'
  echo
  echo "## dpkg 半装 / 损坏"
  dpkg --audit 2>&1
  echo
  echo "## 内核 / DKMS /  GPU"
  uname -r
  dkms status 2>&1
  nvidia-smi 2>&1 | head -15
  echo
  echo "## GRUB 默认项"
  grep -E '^GRUB_DEFAULT|^GRUB_TIMEOUT|^GRUB_SAVEDEFAULT' /etc/default/grub 2>&1
  echo
  echo "## 磁盘"
  df -hT / /home /boot 2>&1
} > "$SNAP" 2>&1
echo "已写入 $(wc -l < "$SNAP") 行"

step "2. 收集 /root 下的报告与日志"
COUNT=0
for pat in /root/diagnosis.txt /root/evidence.txt /root/env-check.txt /root/reinstall-ros.sh \
           /root/repair-*.log /root/fix-tty-login-*.log /root/fallback-xfce-*.log; do
  for f in $pat; do
    [ -f "$f" ] || continue
    cp -f "$f" "$DEST/" 2>/dev/null && { echo "  + $(basename "$f")  ($(wc -c < "$f") 字节)"; COUNT=$((COUNT+1)); }
  done
done
echo "共收集 $COUNT 个文件"
if [ "$COUNT" = 0 ]; then
  echo
  echo "提示：没找到任何报告文件。想先有报告就跑一次诊断："
  echo "    bash 00-run-all.sh --diagnose-only      # 生成 /root/diagnosis.txt"
fi

# 复制一份命令历史（如果有）
[ -f /root/.bash_history ] && cp -f /root/.bash_history "$DEST/bash_history.txt" 2>/dev/null && echo "  + bash_history.txt"

step "3. 先对齐远程（避免推送被拒）"
git fetch origin main 2>&1 | tail -3 || true
git -c rebase.autoStash=true pull --rebase origin main 2>&1 | tail -5 || true
git log --oneline -1

step "4. 提交"
git add -A -- "$DEST"
if git diff --cached --quiet; then
  echo "没有新内容可提交（日志为空？）"
else
  git -c user.name="${GH_USER:-recovery-machine}" \
      -c user.email="${GH_USER:-recovery-machine}@users.noreply.github.com" \
      commit -m "logs: ${HOST} ${STAMP} 现场证据（快照 + 诊断报告 + 脚本日志）" 2>&1 | tail -5
fi

step "5. 推送到 GitHub"
U="${GH_USER:-}"
T="${GH_TOKEN:-}"
if [ -z "$T" ]; then
  echo "GitHub 已不支持密码推送，需要 Personal Access Token (PAT)："
  echo "  生成: https://github.com/settings/tokens?type=beta"
  echo "  选择仓库: ${REPO_SLUG}   权限: Contents = Read and write"
  echo
  if [ -z "$U" ]; then
    printf "GitHub 用户名 [Mustlearnmath]: "
    read -r U
    U="${U:-Mustlearnmath}"
  fi
  printf "粘贴 PAT（输入不回显）: "
  read -rs T
  echo
  [ -n "$T" ] || { echo "!! 没输入 token，取消推送。"; echo "   日志已在本地: $SCRIPT_DIR/$DEST"; exit 1; }
else
  [ -n "$U" ] || U="Mustlearnmath"
fi

# 用 GIT_ASKPASS 一次性喂凭据：不落盘、不进 .git/config
ASKPASS=$(mktemp) || { echo "!! mktemp 失败"; exit 1; }
cat > "$ASKPASS" <<'ASKEOF'
#!/bin/sh
case "$1" in
  *[Uu]sername*) printf '%s\n' "$ASK_USER" ;;
  *)             printf '%s\n' "$ASK_TOKEN" ;;
esac
ASKEOF
chmod 700 "$ASKPASS"

echo "推送中 ..."
OUT=$(ASK_USER="$U" ASK_TOKEN="$T" GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0 \
      git -c credential.helper= push origin HEAD:main 2>&1)
RC=$?
rm -f "$ASKPASS"
unset T ASK_TOKEN
printf '%s\n' "$OUT" | tail -12

step "6. 结果"
if [ "$RC" -eq 0 ]; then
  echo "✅ 推送成功！在线查看（手机/另一台电脑都能开）："
  echo "   目录:  https://github.com/${REPO_SLUG}/tree/main/${DEST}"
  echo "   快照:  https://raw.githubusercontent.com/${REPO_SLUG}/main/${DEST}/snapshot.txt"
  echo "   诊断:  https://raw.githubusercontent.com/${REPO_SLUG}/main/${DEST}/diagnosis.txt"
  echo
  echo "把上面两个 raw 链接发给我，我直接看。"
else
  echo "❌ 推送失败（上面有 git 的报错）。可能是："
  echo "  1) 网络连不上 GitHub —— 重试 / 插网线 / 换 DNS（echo 'nameserver 223.5.5.5' > /etc/resolv.conf）"
  echo "  2) token 不对或没给 Contents: Read and write 权限"
  echo "  3) token 粘贴时带了空格"
  echo
  echo "手动重试（把 <用户名> 和 <PAT> 换成你的，注意会出现在命令历史里，用完 history -c）："
  echo "  cd $SCRIPT_DIR"
  echo "  git remote set-url origin https://<用户名>:<PAT>@github.com/${REPO_SLUG}.git"
  echo "  git push origin HEAD:main"
  echo "  git remote set-url origin https://github.com/${REPO_SLUG}.git"
  echo
  echo "本地证据仍然完好，可直接拷 U 盘: $SCRIPT_DIR/$DEST"
fi
echo
echo "（建议执行 history -c 清掉历史里的 token）"
