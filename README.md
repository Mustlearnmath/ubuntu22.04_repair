# ubuntu22.04_repair

Ubuntu 22.04 + NVIDIA RTX 5070 Ti + CUDA 13 + ROS Humble + Isaac Sim 图形会话启动失败的修复工具集。

> **适用场景 1（本仓库最初用途）**：装搜狗输入法 / 升级 CUDA 后，登录界面提示 **"启动会话失败"** 或卡在 Ubuntu Logo；TTY 无法登录；新建用户也失败 → 系统级桌面依赖被 `apt autoremove` 误删。
>
> **适用场景 2（新增）**：执行过 `sudo chmod 666 /dev*/tty*` 之后，桌面图标大量丢失、重启后进不去登录界面、登录服务（systemd-logind）/ 日志服务启动失败。

---

## ⚡ 三步速查（马上要关机换系统？只看这一段就够）

> 这份 README 可以在故障机的 root shell 里直接看（不用浏览器）：
> `cd /root/ubuntu22.04_repair && less README.md`　（`q` 退出，`/` 搜索，空格翻页）

**第 1 步 · 进 GRUB**
开机时**连按 `Esc`**（UEFI）或**长按 `Shift`**（老 BIOS）→ 选 `Advanced options for Ubuntu` → 选带 **`(recovery mode)`** 的 **6.8** 内核。

**第 2 步 · 进 root shell**
在 **Recovery Menu**（蓝底）里：
先选 `network`（**Enable networking**，回车，等它显示 Finished 再回车）→ 再选 `root`（**Drop to root shell prompt**）→ 出现 `root@主机名:~#`。

**第 3 步 · 粘贴这几行**

```bash
mount -o remount,rw /      # 根分区默认只读，必须做
ping -c 2 github.com       # 确认网络通
cd /root
git clone https://github.com/Mustlearnmath/ubuntu22.04_repair.git
cd ubuntu22.04_repair
bash 00-run-all.sh         # 一键：诊断 + 修 /dev/tty* + 修登录/日志服务 + 修内核 + 修桌面
reboot
```

> 如果 `git clone` 报 `destination path already exists`（以前克隆过），改成：
> ```bash
> cd /root/ubuntu22.04_repair && git fetch origin && git reset --hard origin/main
> ```

**预期结果**：重启后出现登录界面 → 能进桌面、图标回来。
若没有 → 跑 `bash 03-fallback-xfce.sh` 再 `reboot`；还不行 → 按文末「📤 把证据带回来」操作。

**时间预算**（全程**不要断电**）：诊断 1~3 分钟；修 `/dev` 权限与登录服务 10 秒；固定内核 20 秒；补桌面依赖 3~15 分钟（看网速）。

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

### 逐屏对照（你会看到什么 / 没出现怎么办）

| 步骤 | 正常应该看到 | 没出现怎么办 |
|------|--------------|--------------|
| 1 开机按 `Esc`/`Shift` | 黑底/紫底 GRUB 菜单，含 `Ubuntu`、`Advanced options for Ubuntu` | 连按 `Esc` 不行就按住 `Shift`；仍不行见 FAQ Q1；实在不行用 `Ctrl+Alt+F3` 进 TTY |
| 2 进 recovery 内核 | 一堆内核启动信息后出现**蓝底 Recovery Menu** | 若卡住，改用同菜单里另一个 6.8 内核 |
| 3 选 `network` | 打印获取 DHCP 的信息，最后 `Finished, please press ENTER` | 若无网络信息 → 见下方"Recovery 里没网" |
| 4 选 `root` | `root@主机名:~#` 提示符 | 若问密码：输入你设过的 root 密码（没设过通常直接进） |
| 5 `mount -o remount,rw /` | **没有任何输出**（无输出就是成功） | 报错就照抄提示；`mount \| grep ' / '` 看是不是已经 `rw` |
| 6 `ping -c 2 github.com` | `2 packets transmitted, 2 received` | 见下方"Recovery 里没网" |
| 7 `git clone ...` | `Cloning into 'ubuntu22.04_repair'...` 然后完成 | 慢/超时可重试；目录已存在就 `git fetch origin && git reset --hard origin/main` |
| 8 `bash 00-run-all.sh` | 先刷一大屏诊断内容（**正常，不要以为卡了**），最后打印"完成 + 现在执行 reboot" | 某步报错也会继续跑完并留日志，把日志带回来 |
| 9 `reboot` | 重启，GRUB 里选第一项 `Ubuntu` 或等 5 秒自动进 | 直接黑屏/卡 Logo → 见「症状对照表」 |

### Recovery 里没网怎么办（按顺序试）

```bash
ip -br a                     # 看网卡名，例如 enp3s0 / wlp2s0
ip link set enp3s0 up        # 换成你的网卡名
dhclient -v enp3s0           # 手动取 IP
cat /etc/resolv.conf         # 如果这个文件是空的/没有 nameserver：
echo 'nameserver 223.5.5.5' >> /etc/resolv.conf
ping -c 2 github.com
```

> 有线网最稳；笔记本如果只连 Wi-Fi，Recovery 里只能用 `wpa_supplicant`（较麻烦），建议直接插网线。
> 若确实无法联网：先跑不需要网络的部分 `bash 00-run-all.sh --no-desktop`（能修 `/dev` 权限、登录服务和内核默认项），**进桌面后再**跑 `sudo bash 02-repair.sh` 补包。

### 别忘了这几条（血泪教训）

- ❌ **不要在 root shell 里跑 `apt autoremove` / `apt remove`** —— 上次"启动会话失败"就是被它误删了桌面依赖。
- ❌ **不要把内核固定回 5.15** —— RTX 5070 Ti 需要 6.8 + 驱动 580+。
- ❌ 不要 `chmod -R` / `chown -R` 去动 `/dev`、`/home`、`/usr`。
- ✅ 不确定就先只跑 `bash 00-run-all.sh --diagnose-only`，把 `/root/diagnosis.txt` 带回来再决定。
- ✅ 真要动大手术前先备份：`bash 99-backup-home.sh /mnt/usb`（把 U 盘挂到 /mnt/usb）。

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

## 📖 每个脚本到底做了什么（详细）

> 所有脚本都要求 **root**；都用 `tee` 写日志到 `/root/*.log`，出问题就把日志带回来。

### `00-run-all.sh` — 一键入口（推荐）
- **联网**：部分需要（第 4 步）
- **耗时**：5~20 分钟（大头是补包）
- **流程**：`0` 环境自检 + 自动 `remount rw` + 网络检测 → `1` 诊断 → `2` 修 `/dev/tty*` 与登录/日志栈 → `3` 固定 6.8 内核 → `4` 补桌面依赖/图标主题
- **参数**：`--no-desktop`（跳过第 4 步，离线可用）、`--diagnose-only`（只做诊断）
- **产物**：`/root/diagnosis.txt` + 各步自己的 `/root/*.log`

### `01-diagnose.sh` — 只读取证
- **联网**：不需要　**改系统**：不改
- **产物**：`/root/diagnosis.txt`（23 节）
- **本次事故重点看**：
  - 第 **18** 节：`/dev` 挂载类型（是 devtmpfs 吗）+ `tty` 权限 + 谁被改成"其他用户可写"
  - 第 **19** 节：failed / masked 单元、关键单元 enabled/active 状态、drop-in 覆盖文件、`logind.conf` 异常行
  - 第 **20** 节：`systemd-logind` / `journald` / `dbus` 日志 + **上一次启动（`-b -1`）的错误**
  - 第 **21** 节：journal 目录权限 + 日志完整性
  - 第 **22** 节：图标主题（hicolor / Adwaita / Yaru）+ 会话缓存
- **怎么看**：`less /root/diagnosis.txt`，输入 `/^18.` 直接跳到第 18 节

### `07-fix-tty-and-login.sh` — 本次事故的主角
- **联网**：不需要（加 `--with-desktop` 才需要）
- **耗时**：约 10 秒
- **做的事**：
  1. 快照 `/dev` 现状，判断是否 devtmpfs（决定这次 chmod 会不会持久）
  2. 恢复权限：`/dev/tty`→`666`、`/dev/tty0..63`→`620 root:tty`、`/dev/ttyS*/USB*/ACM*`→`660`；顺带校回 `/dev/console`、`/tmp`、`/var/tmp`、`/dev/shm`、`/run/lock`；再让 `udevadm trigger` 用系统规则重刷一遍
  3. 修登录/日志栈：`systemd-logind`、`systemd-journald`、`dbus`、`systemd-udevd`、`systemd-user-sessions`、`getty@tty1` —— **解除 mask、恢复 enable、`reset-failed`、现场 `start` 看真实报错**、清理可疑 drop-in
  4. 修 journal 目录权限（`root:systemd-journal` + `2755`，journal 文件 `0640`）
  5. 检查图标主题，缺了会告诉你装什么
  6. 检查 `default-display-manager` / `graphical.target` 并 `enable` 对应 DM
- **产物**：`/root/fix-tty-login-<时间戳>.log`
- **副作用**：只改设备节点模式 + systemd 单元状态；**不装包、不删数据**
- **重点看**：日志里"仍然失败的单元"和 `systemd-logind` 的报错 —— 那就是没修好的根因

### `05-fix-kernel-grub.sh` — 固定内核
- **联网**：不需要（但若某个 6.8 内核没装 headers，它会尝试 apt）
- **做的事**：遍历已装内核 → 找出 **DKMS 已编译出 nvidia 模块** 的最新 6.8 → 写进 `/etc/default/grub` 的 `GRUB_DEFAULT`（用 `submenu>entry` 写法）→ `update-grub`；同时设 `GRUB_SAVEDEFAULT=false`、`GRUB_TIMEOUT=5`、`TIMEOUT_STYLE=menu`（**以后开机容易进 GRUB 菜单**）
- **备份**：`/etc/default/grub.bak.<时间戳>`

### `02-repair.sh` — 桌面依赖大修（**需要联网**）
- **耗时**：3~15 分钟
- **做的事**：`dpkg --configure -a` → 补装 GNOME 会话/X11/GDM/D-Bus/字体 + **图标主题**（hicolor/Adwaita/Yaru/Humanity）并重建 `gtk-update-icon-cache` → `ubuntu-desktop-minimal` → 清 fcitx/搜狗钩子 → **禁 GDM Wayland（强制 X11）** → 校验 `xsessions` 会话文件 → 重建 NVIDIA DKMS → 清 AccountsService 与用户会话缓存 → 设 GDM3 为默认 DM → `graphical.target`
- **备份**：`/root/repair-backup-<时间戳>/`（grub、gdm3、lightdm、X11/Xsession.d、AccountsService 用户配置）
- **产物**：`/root/repair-<时间戳>.log`
- **注意**：包名不存在会自动跳过（不会因一个坏名字整体失败）

### `03-fallback-xfce.sh` — 兜底（GNOME 修不好时）
- 装 XFCE4 + LightDM 并把默认会话设为 xfce。**conda / ROS / Isaac Sim / CUDA 都不受影响**，进桌面后照常用。

### `04-list-missing-ros.sh` — 恢复 ROS 包清单
只读。扫 `/var/log/apt/history.log*` 里被 Remove/Purge 的 `ros-humble-*`，生成 `/root/reinstall-ros.sh`（**进桌面后**用 `sudo bash` 跑它）。

### `06-check-cuda-torch-isaacsim.sh` — 环境体检
只读。核对 `nvidia-smi` / CUDA / cuDNN / conda 环境里的 torch（含 `cuda.is_available()`）/ Isaac Sim / `/opt/ros/humble`。产物 `/root/env-check.txt`。

### `99-backup-home.sh` — 大手术前备份
`bash 99-backup-home.sh /mnt/usb`（先把 U 盘挂到 `/mnt/usb`）。备份 `/home`（排除 `.cache`/Trash/Downloads）、`/root`、`/etc`、dpkg 包清单、apt 日志、NVIDIA/CUDA 清单。

---

## ✅ 修好后怎么验证（重启进桌面后跑）

```bash
systemctl --failed                        # 期望：0 loaded units listed（没有红色 failed）
systemctl is-active systemd-logind systemd-journald dbus gdm3   # 期望全是 active
ls -l /dev/tty0 /dev/tty /dev/ttyS0       # 期望 620 root tty / 666 root tty / 660
ls /usr/share/icons/hicolor/index.theme   # 期望存在（图标丢失问题的直接指标）
nvidia-smi                                # 期望能列出 RTX 5070 Ti 和驱动 580+
cat /etc/X11/default-display-manager      # 期望 /usr/sbin/gdm3（或 lightdm）
nproc; free -h; df -h /                   # 顺带看下没爆盘（/ 满了也会起不来桌面）
```

想确认 `/dev` 权限是否"自愈"过：

```bash
findmnt -no FSTYPE /dev                   # 期望 devtmpfs
```

---

## 🧭 症状 → 该跑哪个脚本（决策树）

| 你看到的症状 | 最可能原因 | 跑什么 |
|---|---|---|
| 进不去登录界面 / 卡 Ubuntu Logo / 黑屏只有光标 | GDM 卡 Wayland、NVIDIA 驱动、内核不对 | `07` → `05` → `02`（即 `00-run-all.sh`） |
| 登录界面出现，输密码后**闪回登录界面** | 会话文件/dconf/AccountsService 缓存 | `02` |
| 提示 **"启动会话失败"** / 新建用户也进不去 | 桌面依赖被 `apt autoremove` 误删 | `02`（还不行 → `03`） |
| **日志服务 / 登录服务 failed**（本次事故） | `/dev/tty*` 权限被改坏、logind/journald 状态异常 | `07` |
| **桌面图标大量丢失** | 图标主题（hicolor/Adwaita/Yaru）损坏 | `07`（只看检查结果）+ `02`（修） |
| 串口 / Arduino / USB 转串口不认 | `ttyS*` `ttyUSB*` 权限被打乱 | `07` |
| 一个用户进不去、新建用户能进去 | 用户级配置问题 | `02`（清会话缓存那步） |
| 所有用户都进不去 | 系统级依赖/服务问题 | `02` → `03` |
| 进桌面后 ROS 包报缺失 | apt autoremove 误删 ROS | `04`，然后进桌面 `sudo bash /root/reinstall-ros.sh` |
| 怀疑显卡/CUDA/torch/Isaac 坏了 | 驱动或环境问题 | `06`（只读体检） |

---

## 📤 把证据带回来（给我，或给未来的你）

**A. 先在本机看**
```bash
less /root/diagnosis.txt                 # 23 节完整证据
ls -l /dev/tty* /dev/console             # 重启后的真实权限
journalctl -b -1 -p err --no-pager | tail -80   # 故障那次的错误
journalctl -b -u systemd-logind -u systemd-journald --no-pager | tail -60
systemctl --failed --no-pager
```

**B. 拷到 U 盘**（最省事，不需要网络）
```bash
lsblk                       # 找到 U 盘，例如 sdb1
mkdir -p /mnt/usb
mount /dev/sdb1 /mnt/usb
cp /root/diagnosis.txt /root/*.log /mnt/usb/
sync && umount /mnt/usb
```

**C. 推回 GitHub**（需要 PAT，见下文「🔄 root 模式下的 git 上推 / 下拉」）
```bash
cd /root/ubuntu22.04_repair
mkdir -p logs && cp /root/diagnosis.txt /root/*.log logs/
git add -A && git commit -m "recovery: 现场日志"
git push
```

**D. 只看关键几行也行**：把 `diagnosis.txt` 第 18~22 节、`systemctl --failed` 的输出、`journalctl -b -1 -p err` 的尾部拍照/抄下来即可。

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

**Q10. Recovery 模式里能直接进图形界面吗？**
不能。Recovery 只有文本 root shell，图形界面必须重启后**正常启动**才会出现。Recovery 的用途是"改东西 → reboot 验证"。

**Q11. 脚本跑到一半断了（断网/手滑 Ctrl+C），能重跑吗？**
能，全部脚本都是**幂等**的：修权限只改不对的值、装包会跳过已装的、GRUB 先备份再写、systemd 操作可重复。直接重跑 `bash 00-run-all.sh` 即可。

**Q12. `apt update` 很慢或 404？**
Recovery 里默认源可能慢。先确认网络（`ping archive.ubuntu.com`）。要换国内镜像可在**进桌面后**再改 `/etc/apt/sources.list`（备份原文件），别在恢复模式里手抖改源。

**Q13. 我担心动 GRUB 会影响 Windows 双系统启动项？**
不会。`05-fix-kernel-grub.sh` 只改 `/etc/default/grub` 里的 `GRUB_DEFAULT`（把默认项指向某个 6.8 内核），不删任何 menuentry、不动其他系统的引导。而且它先备份成 `/etc/default/grub.bak.<时间戳>`，随时可以改回来：`sudo cp /etc/default/grub.bak.* /etc/default/grub && sudo update-grub`。

**Q14. 忘记 root 密码 / Recovery 选 `root` 时要密码？**
Recovery 的 root shell 一般不需要密码。如果它真的要，而你又忘了，用 `init=/bin/bash` 应急入口（见上文「备选入口」）；或进桌面后用 `sudo passwd root` 重新设置。

**Q15. 以后怎么避免再次踩坑？**
`/dev` 里**千万别用 `chmod -R`**。给串口/USB 设备授权用：
```bash
sudo usermod -aG dialout $USER     # 串口（重新登录生效）
sudo usermod -aG plugdev $USER     # 有些设备
```
而不是 `chmod 666 /dev/ttyUSB0`（临时且危险）。

**Q16. 修完还是进不去，我该怎么办？**
按顺序：`07`（权限+服务）→ `02`（桌面依赖，需联网）→ `03`（XFCE 兜底）→ 收集证据（`01` + `journalctl -b -1 -p err`）带回来分析。**不要在没证据的情况下重装系统**，你的 conda / ROS / Isaac Sim 都还在。

**Q17. 我之前已经 clone 过这个仓库了，再跑一次 `git clone` 会更新吗？**
**不会。** 目标目录已存在时 git 会直接失败：

```
fatal: destination path 'ubuntu22.04_repair' already exists and is not an empty directory.
```

三选一：

**方案 A · 更新现有副本（推荐，最省流量）**
```bash
cd /root/ubuntu22.04_repair
git log --oneline -1                  # 先看自己现在是哪个版本
git fetch origin
git reset --hard origin/main          # 对齐远程最新（注意：丢弃本地未提交改动！）
chmod +x *.sh
ls -l 00-run-all.sh 07-fix-tty-and-login.sh    # 确认两个新脚本已到
bash 00-run-all.sh
```

**方案 B · 删掉重拉（最干净）**
```bash
cd /root
rm -rf ubuntu22.04_repair
git clone https://github.com/Mustlearnmath/ubuntu22.04_repair.git
cd ubuntu22.04_repair && bash 00-run-all.sh
```

**方案 C · 另拉一个新目录，不动旧的**
```bash
cd /root
git clone https://github.com/Mustlearnmath/ubuntu22.04_repair.git repair-new
cd repair-new && bash 00-run-all.sh
```

> ⚠️ 用方案 A 的 `git reset --hard` 之前，如果旧副本里存过你自己的日志（例如 `logs/diagnosis.txt`），先备份：`cp -r logs /root/old-logs`。
> 想"更新但保留本地改动"就用：`git stash && git pull --rebase && git stash pop`。
> 如果旧目录根本不是 git 仓库（当初下载的是 zip 包），`git fetch` 会报 `not a git repository` → 直接用**方案 B**。

**怎么确认拿到的是最新版**：`git log --oneline -1` 应显示 `36af906 docs: README 大幅扩写 …`（或更新），并且 `00-run-all.sh`、`07-fix-tty-and-login.sh` **两个文件必须存在**。

**Q18. 我完全不想用 git / clone 老是失败怎么办？**
在能上网的电脑上打开
`https://github.com/Mustlearnmath/ubuntu22.04_repair` → 绿色 **Code → Download ZIP** → 把 zip 拷到 U 盘 → 在 Ubuntu 里解压到 `/root`，然后：
```bash
cd /root/ubuntu22.04_repair-main
chmod +x *.sh
bash 00-run-all.sh
```
（zip 方式拿不到 git 历史，但脚本功能完全一样。）

