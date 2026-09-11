# logs/

这里存放**故障机现场证据**，由 [`08-push-logs.sh`](../08-push-logs.sh) 自动生成并推送。

每次运行会新建一个目录 `<主机名>-<时间戳>/`，里面包含：

| 文件 | 内容 |
|---|---|
| `snapshot.txt` | 现场快照：失败单元、`/dev` 与 tty 权限、logind/journald/dbus 日志、上次+本次启动的错误、gdm3、Xorg 报错、图标主题、DKMS/nvidia-smi、GRUB 默认项、磁盘 |
| `diagnosis.txt` | `01-diagnose.sh` 的完整 23 节只读诊断报告 |
| `fix-tty-login-*.log` | `07-fix-tty-and-login.sh` 的修复过程与真实报错 |
| `repair-*.log` | `02-repair.sh` 的修复过程 |
| `env-check.txt` | `06-check-cuda-torch-isaacsim.sh` 的 CUDA/torch/Isaac/ROS 体检 |
| `reinstall-ros.sh` | `04-list-missing-ros.sh` 生成的被误删 ROS 包清单 |
| `bash_history.txt` | root 的命令历史（便于复盘当时到底敲了什么） |

生成方式：

```bash
cd /root/ubuntu22.04_repair
sudo bash 08-push-logs.sh
```

> ⚠️ 这些文件可能包含**主机名、用户名、设备序列号、目录结构**等本机信息，本仓库是公开仓库，请注意别把隐私内容推上来（脚本不会收集 `/home` 里的个人文件）。
