# ubuntu22.04_repair

Ubuntu 22.04 + NVIDIA RTX 5070 Ti + CUDA 13 + ROS Humble + Isaac Sim 图形会话启动失败的修复工具集。

> **适用场景 1（本仓库最初用途）**：装搜狗输入法 / 升级 CUDA 后，登录界面提示 **"启动会话失败"** 或卡在 Ubuntu Logo；TTY 无法登录；新建用户也失败 → 系统级桌面依赖被 `apt autoremove` 误删。
>
> **适用场景 2（新增）**：执行过 `sudo chmod 666 /dev*/tty*` 之后，桌面图标大量丢失、重启后进不去登录界面、登录服务（systemd-logind）/ 日志服务启动失败。

---

## 🚑 事故 2：`sudo chmod 666 /dev*/tty*` 怎么修

### 这条命令到底改了什么

`/dev*/tty*` 在 bash 里会展开成 `/dev/tty`、`/dev/tty0` … `/dev/tty63`、`/dev/ttyS0`、`/dev/ttyUSB*`、`/dev/ttyACM*`、`/dev/ttyprintk` 等。它们原本有严格的属主/权限约定：

| 节点 | 正常权限 | 被改成 666 之后 |
|------|----------|-----------------|
| `/dev/tty` | `666 root:tty` | 无变化（本来就是 666） |
| `/dev/tty0` ~ `/dev/tty63`（虚拟终端） | `620 root:tty` | **变成所有用户可读写** |
| `/dev/ttyS0`、`/dev/ttyUSB*`、`/dev/ttyACM*`、`/dev/ttyprintk` | `660 root:tty` | **变成所有用户可读写** |

会出什么问题：

- **登录 / 会话服务（`systemd-logind`）** 管理虚拟终端时依赖上面这套约定（tty0..63 = `root:tty 620`）。被改成世界可读写后，登录服务、getty、会话创建都可能直接失败 → **GDM 拿不到会话 → 没有登录界面**。
- **串口类设备**（`ttyS*` / `ttyUSB*` / `ttyACM*`）权限被打乱，Arduino、串口调试、打印机之类的 udev 规则也一起失灵。
- 你同时遇到的 **"大量图标丢失"**，通常是 **桌面依赖 / 图标主题（hicolor、Adwaita、Yaru）被破坏**（常见于之前 `apt autoremove` 留下后遗症），或者 udev 规则没被重新应用。本次的 `07` / `02` 两个脚本都会覆盖。

### ⚠️ 一个重要的实话

`/dev` 在 Ubuntu 上是 **devtmpfs**：**设备节点在每次重启时由内核 + udev 重建，所以 `chmod 666 /dev/tty*` 的改动本身不会持久到重启之后。**

也就是说：如果你已经重启过还进不去桌面，说明**还叠加了别的问题**（登录/日志栈没起来、桌面依赖/图标主题缺失、GDM 卡在 Wayland、DKMS 模块没编译等）。

`00-run-all.sh` 会把这几类**一次性全修掉**，并且把诊断证据留在 `/root/diagnosis.txt`。`01-diagnose.sh` 的第 18~22 节专门验证这一点（会打印 `/dev` 的挂载类型和当前 tty 权限）。

### 最快的修法（clone 后一条命令）

```bash
cd /root/ubuntu22.04_repair
bash 00-run-all.sh          # 诊断 + 修 tty 权限 + 修登录/日志栈 + 修内核默认项 + 修桌面依赖
reboot
```

不想联网也能跑（跳过补装桌面依赖那步）：

```bash
bash 00-run-all.sh --no-desktop
```

只想先收证据：

```bash
bash 00-run-all.sh --diagnose-only     # 产物 /root/diagnosis.txt
```

### 万一脚本跑不起来（手工三行救命）

```bash
mount -o remount,rw /
chmod 666 /dev/tty ; chmod 620 /dev/tty[0-9]* ; chmod 660 /dev/tty[A-Za-z]*
reboot
```

---

## 🖥️ 怎么进入"Recovery root shell"（你说的那个 root 命令输入框）

### 步骤

1. **重启 / 开机**。
2. 在厂商 Logo 出现时**连续按 `Esc`**（UEFI 机器）；如果是老式 BIOS，**长按 `Shift`**。一直按到出现 **GRUB 菜单**（黑底/紫底，列着 `Ubuntu`、`Advanced options for Ubuntu`）。
   - 如果怎么按都不出菜单：见下面 FAQ「进不去 GRUB 菜单」。
3. 方向键选 **`Advanced options for Ubuntu`** → 回车。
4. 选名字里带 **`(recovery mode)`** 的那一项，例如
   `Ubuntu, with Linux 6.8.0-xx-generic (recovery mode)` → 回车。
   👉 **优先选 6.8 系列内核**（RTX 5070 Ti / Blackwell 需要 6.8，别选 5.15）。
5. 进入 **Recovery Menu**（蓝底菜单），用方向键选择：
   - 先选 **`network`  → Enable networking**，回车。
     这一步同时会**把根分区重新挂成可读写**，并且**只有联网才能 `git clone` / `apt`**。
   - 再选 **`root`  → Drop to root shell prompt**，回车 → 你看到 `root@主机名:~#` 提示符。
     **这就是你说的"指令 root 输入框"。**
   - 如果它问 root 密码：输入你设过的 root 密码。若你从没设过 root 密码，一般会直接进入。
6. 在这个 root shell 里跑：

```bash
mount -o remount,rw /        # 根分区默认只读，不做这步 git clone 会因为只读失败
ping -c 2 github.com         # 确认网络
cd /root
git clone https://github.com/Mustlearnmath/ubuntu22.04_repair.git
cd ubuntu22.04_repair
bash 00-run-all.sh
```

7. 跑完 `reboot`，正常启动即可。（Recovery Menu 里的 `resume` 也是"正常启动"。）

### 备选入口

- **TTY**：如果系统其实起来了、只是图形界面没出来，按 `Ctrl+Alt+F3` 切到文本终端，用你的账号登录，然后 `sudo bash 00-run-all.sh`。
- **`init=/bin/bash`**（应急，root 密码也丢了时）：GRUB 菜单里选中正常启动项按 `e` 编辑，在 `linux` 那行末尾加 `rw init=/bin/bash`，`Ctrl+X` 启动。此时 /dev 权限可以修，但**没有网络**，只能做第 2 步 tty 权限修正。
- **U 盘 Live 系统**：最后手段，需要手动 `chroot` 到硬盘系统再跑脚本。

---


## 🚨 内核选择（请先看这里）

你的硬件是 **RTX 5070 Ti（Blackwell 架构）**，必须用 NVIDIA 580+ 驱动。这要求内核 **≥ 6.8**。
**不要按某些旧教程把内核固定回 5.15** —— 5.15 装不上你现在的 NVIDIA DKMS 模块，会黑屏。

**本仓库推荐固定启动内核：你机器上最新的 `6.8.x`（脚本会自动挑 DKMS 已成功编译 nvidia 模块的那一个）**。

Recovery 进 root shell 后，跑 [05-fix-kernel-grub.sh](05-fix-kernel-grub.sh) 即可把 GRUB 默认项固定到正确的 6.8 内核。

---

## 📦 脚本清单与执行顺序

**一键入口**：[00-run-all.sh](00-run-all.sh) —— 依次跑 01 → 07 → 05 → 02，clone 后直接 `bash 00-run-all.sh` 就行。

| 顺序 | 脚本 | 作用 | 是否修改系统 |
|------|------|------|---------------|
| 入口 | [00-run-all.sh](00-run-all.sh) | 一键跑完下面 1~4 步（`--no-desktop` 可跳过联网步骤） | ✅ 见各脚本 |
| 1 | [01-diagnose.sh](01-diagnose.sh) | 收集证据，生成 `/root/diagnosis.txt`；含 /dev 权限、failed 单元、logind/journald 日志 | ❌ 只读 |
| 2 | [07-fix-tty-and-login.sh](07-fix-tty-and-login.sh) | **本次事故主角**：修 `/dev/tty*` 权限 + 修登录/日志栈（logind/journald/dbus/getty）+ 查图标主题 | ✅ 改系统（不装包） |
| 3 | [05-fix-kernel-grub.sh](05-fix-kernel-grub.sh) | 把 GRUB 默认内核固定为可用的 6.8 | ✅ 改 GRUB |
| 4 | [02-repair.sh](02-repair.sh) | 补桌面依赖、图标主题、禁 Wayland、清 fcitx/ibus 钩子、重建 DKMS | ✅ 改系统（需联网） |
| 5 | [04-list-missing-ros.sh](04-list-missing-ros.sh) | 从 apt history 还原被误删的 ROS 包清单 | ❌ 只生成清单 |
| 6 | [06-check-cuda-torch-isaacsim.sh](06-check-cuda-torch-isaacsim.sh) | 核对 CUDA / torch / Isaac Sim 是否完好 | ❌ 只读 |
| 7 | [99-backup-home.sh](99-backup-home.sh) | 备份 /home、conda、ros workspace | ❌ 只读外挂 |
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

### 3. 一键修复（推荐）

```bash
cd /root/ubuntu22.04_repair
bash 00-run-all.sh
```

它会依次做：诊断（`/root/diagnosis.txt`）→ 修 `/dev/tty*` 权限 + 登录/日志栈 → 固定 6.8 内核 → 补桌面依赖/图标主题。
没网时会自动跳过补包那步，其余照常。

### 4. 分步跑（想看清楚每一步时）

```bash
bash 01-diagnose.sh            # 只读，先看证据
cat /root/diagnosis.txt

bash 07-fix-tty-and-login.sh   # ★ 本次事故重点：/dev/tty* 权限 + logind/journald
bash 05-fix-kernel-grub.sh     # 固定 6.8 内核为默认启动项
bash 02-repair.sh              # 桌面依赖 + 图标主题（需联网）

reboot
```

也可以让 `07` 顺便把桌面依赖一起修：

```bash
bash 07-fix-tty-and-login.sh --with-desktop
```

### 5. 兜底（还进不去桌面才跑）

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

---

## ❓ FAQ / 排障

**Q1. 开机怎么按都进不去 GRUB 菜单？**
Ubuntu 默认把菜单藏起来了（`GRUB_TIMEOUT_STYLE=hidden` + `GRUB_TIMEOUT=0`）。开机时**连续快速敲 `Esc`**（UEFI）或**按住 `Shift`**（Legacy）。某些品牌的 BIOS 需要在开机 Logo 时先按 `F2`/`F12` 进固件界面再选启动项。另外：在 Recovery root shell 里跑过 `05-fix-kernel-grub.sh` 之后，菜单会变成显示 5 秒，以后就容易进了。

**Q2. 提示 `Read-only file system` / `git clone` 失败？**
Recovery 的根分区默认只读，先执行：

```bash
mount -o remount,rw /
```

（在 Recovery Menu 里先选过 `network` 的话一般已经自动 remount 了。）

**Q3. Recovery 里没网络？**
Recovery Menu 选 `network` → Enable networking；还不行就在 root shell 里：

```bash
ip link                     # 看网卡名
dhclient -v <网卡名>        # 手动取 IP
ping -c 2 github.com
```

**Q4. `git clone` 报 SSL/证书/时间错误？**

```bash
date                        # 时间对不对，错了就 date -s 修正
apt install --reinstall -y ca-certificates
```

**Q5. 重启后 `/dev/tty*` 还是 666？**
那说明你的 `/dev` 不是 `devtmpfs`（很少见，`findmnt /dev` 看 FSTYPE）。用 `07-fix-tty-and-login.sh` 修，并考虑加一个开机自检的 service 固定权限。

**Q6. "日志服务 / 登录服务"到底哪个挂了，我想自己查：**

```bash
systemctl --failed                              # 本次启动失败的单元
systemctl status systemd-logind systemd-journald dbus
journalctl -b -u systemd-logind | tail -50
journalctl -b -1 -p err | tail -80              # 上一次（故障那次）启动的错误
ls -l /dev/tty* /dev/console                    # tty 权限
```

**Q7. 这些脚本会不会动我的数据？**
不会。`01/04/06/99` 只读；`02/03/05/07` 只改系统配置与包，唯一会动的"用户目录"是 `/home/*/.cache` 里的会话缓存（会先备份 dconf）。`/home/r/`、`/home/ricky/`、conda、ROS 源码、Isaac Sim、CUDA 都不受影响。

**Q8. 怎么算修好了？**
能进 GDM 登录界面、能登录进 GNOME；再确认：

```bash
systemctl --failed            # 应该没有红色 failed
ls -l /dev/tty0               # crw--w---- root tty
nvidia-smi                    # 显卡正常
```

**Q9. 怎么把现场日志推回仓库给我看？**
见上面「🔄 root 模式下的 git 上推 / 下拉」，用 PAT 推 `diagnosis.txt` / `repair-*.log` 即可。

