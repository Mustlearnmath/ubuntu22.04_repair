# ubuntu22.04_repair

Ubuntu 22.04 + NVIDIA RTX 5070 Ti + CUDA 13 + ROS Humble + Isaac Sim 图形会话启动失败的修复工具集。

> 适用场景：装搜狗输入法 / 升级 CUDA 后，登录界面提示 **"启动会话失败"** 或卡在 Ubuntu Logo；TTY 无法登录；新建用户也失败 → 系统级桌面依赖被 `apt autoremove` 误删。

---

## 🚨 内核选择（请先看这里）

你的硬件是 **RTX 5070 Ti（Blackwell 架构）**，必须用 NVIDIA 580+ 驱动。这要求内核 **≥ 6.8**。
**不要按某些旧教程把内核固定回 5.15** —— 5.15 装不上你现在的 NVIDIA DKMS 模块，会黑屏。

**本仓库推荐固定启动内核：你机器上最新的 `6.8.x`（脚本会自动挑 DKMS 已成功编译 nvidia 模块的那一个）**。

Recovery 进 root shell 后，跑 [05-fix-kernel-grub.sh](05-fix-kernel-grub.sh) 即可把 GRUB 默认项固定到正确的 6.8 内核。

---

## 📦 脚本清单与执行顺序

| 顺序 | 脚本 | 作用 | 是否修改系统 |
|------|------|------|---------------|
| 1 | [01-diagnose.sh](01-diagnose.sh) | 收集证据，生成 `/root/diagnosis.txt` | ❌ 只读 |
| 2 | [05-fix-kernel-grub.sh](05-fix-kernel-grub.sh) | 把 GRUB 默认内核固定为可用的 6.8 | ✅ 改 GRUB |
| 3 | [02-repair.sh](02-repair.sh) | 补桌面依赖、禁 Wayland、清 fcitx/ibus 钩子、重建 DKMS | ✅ 改系统 |
| 4 | [04-list-missing-ros.sh](04-list-missing-ros.sh) | 从 apt history 还原被误删的 ROS 包清单 | ❌ 只生成清单 |
| 5 | [06-check-cuda-torch-isaacsim.sh](06-check-cuda-torch-isaacsim.sh) | 核对 CUDA / torch / Isaac Sim 是否完好 | ❌ 只读 |
| 6 | [99-backup-home.sh](99-backup-home.sh) | 备份 /home、conda、ros workspace | ❌ 只读外挂 |
| 兜底 | [03-fallback-xfce.sh](03-fallback-xfce.sh) | GNOME 修不好就装 XFCE 进桌面 | ✅ 装新桌面 |

---

## 🧰 在 Recovery root shell 下使用（包含网络、push、pull）

### 1. 确认网络

Recovery 菜单选 **Enable networking**，然后：

```bash
ping -c 2 github.com
git --version
```

> 如果 `ping` 不通：回 Recovery 菜单选 `Enable networking`；还不行就 `dhclient -v` 手动取 IP。

### 2. 首次拉取仓库

```bash
cd /root
git clone https://github.com/Mustlearnmath/ubuntu22.04_repair.git
cd ubuntu22.04_repair
chmod +x *.sh
```

### 3. 跑诊断

```bash
bash 01-diagnose.sh
cat /root/diagnosis.txt
```

把 `/root/diagnosis.txt` 内容贴给 AI（或我），再决定下一步。

### 4. 固定内核 + 修复

```bash
bash 05-fix-kernel-grub.sh    # 固定 6.8 内核为默认
bash 02-repair.sh              # 修复桌面依赖
reboot
```

### 5. 兜底（前两步还进不去桌面才跑）

```bash
bash 03-fallback-xfce.sh
reboot
```

---

## 🔄 root 模式下的 git 上推 / 下拉

### 下拉（更新脚本到最新）

```bash
cd /root/ubuntu22.04_repair
git pull
```

如果 `git pull` 报 `divergent branches` 或本地有修改，强制对齐远程：

```bash
cd /root/ubuntu22.04_repair
git fetch origin
git reset --hard origin/main
```

### 上推（你在故障机上改了脚本想推回去）

GitHub 不再支持密码，**必须用 Personal Access Token (PAT)**：

1. 在另一台机器/手机上访问 https://github.com/settings/tokens?type=beta
2. 生成 Fine-grained token，仓库选 `Mustlearnmath/ubuntu22.04_repair`，权限 **Contents: Read and write**。
3. 在故障机 root shell：

```bash
cd /root/ubuntu22.04_repair
git config user.email "ricky@local"
git config user.name  "ricky-recovery"

# 把 token 缓存进 URL（root 用户私有）
git remote set-url origin https://Mustlearnmath:<你的PAT>@github.com/Mustlearnmath/ubuntu22.04_repair.git

git add -A
git commit -m "recovery: 现场日志/补丁"
git push
```

> ⚠️ 推完日志后建议把 URL 改回不含 token 的版本：
> `git remote set-url origin https://github.com/Mustlearnmath/ubuntu22.04_repair.git`

---

## 🧪 协作流程（你在 Recovery、我在外面）

```
你（Recovery）             我（这边）
─────────────              ─────────────
git clone …
bash 01-diagnose.sh
cat /root/diagnosis.txt  ─►  分析 → 改 02-repair.sh → push
git pull
bash 02-repair.sh
reboot
✅ 进桌面
```

---

## 📁 个人数据与环境保全

- `/home/r/`、`/home/ricky/` 用户数据本来就没动过。
- `~/anaconda3` / `~/miniconda3`：环境完整，桌面修好后 `source ~/anaconda3/etc/profile.d/conda.sh` 即可。
- ROS workspace：源码在 `~/*_ws/src` 里，桌面修好后重新 `colcon build`。
- Isaac Sim：装在 `~/.local/share/ov/pkg/` 或 `~/isaacsim/`，桌面无关，本身完好。
- CUDA：装在 `/usr/local/cuda-13.0`，桌面无关。

万一 GNOME 修不好走 XFCE，**所有上面这些环境都不受影响**。
