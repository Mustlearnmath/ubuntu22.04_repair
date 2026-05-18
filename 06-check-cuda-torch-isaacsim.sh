#!/bin/bash
# 06-check-cuda-torch-isaacsim.sh
# 进桌面之前可在 Recovery 跑（部分 GPU 项 chroot 限制下不准），
# 也强烈建议进桌面后再以普通用户身份跑一遍。
# 只读，不改任何东西。

OUT=/root/env-check.txt
exec > >(tee "$OUT") 2>&1

hr(){ echo; echo "================ $* ================"; }

hr "GPU & 驱动"
nvidia-smi 2>&1 | head -25 || echo "nvidia-smi 不可用"
echo
dpkg -l | grep -E 'nvidia-driver|nvidia-dkms|cuda-' | awk '{print $1,$2,$3}'

hr "CUDA"
ls -ld /usr/local/cuda* 2>/dev/null
for n in /usr/local/cuda*/bin/nvcc; do
  [ -x "$n" ] && { echo "--- $n ---"; "$n" --version; }
done

hr "CUDNN"
for f in /usr/lib/x86_64-linux-gnu/libcudnn*; do
  [ -e "$f" ] && ls -l "$f"
done | head -20
echo
dpkg -l | grep -i cudnn || echo "(无 cudnn 系统包，可能装在 conda 里)"

hr "用户级 conda / pip / torch / isaacsim"
for u in $(ls /home); do
  HOME_DIR=/home/$u
  echo "------------- 用户: $u -------------"

  for CONDA in $HOME_DIR/anaconda3 $HOME_DIR/miniconda3 $HOME_DIR/miniforge3; do
    [ -d "$CONDA" ] || continue
    echo "conda root: $CONDA"
    if [ -x "$CONDA/bin/conda" ]; then
      sudo -u "$u" "$CONDA/bin/conda" env list 2>/dev/null
      for env in $("$CONDA/bin/conda" env list 2>/dev/null | awk '/^[^#]/ && NF>=2 {print $NF}'); do
        [ -d "$env" ] || continue
        py="$env/bin/python"
        [ -x "$py" ] || continue
        echo "--- env $env ---"
        sudo -u "$u" "$py" -c "
import sys
print('python', sys.version.split()[0], sys.executable)
try:
    import torch
    print('torch', torch.__version__, 'cuda built:', torch.version.cuda, 'avail:', torch.cuda.is_available())
except Exception as e:
    print('torch: ', e)
try:
    import isaacsim
    print('isaacsim ok at', isaacsim.__file__)
except Exception as e:
    print('isaacsim:', e)
" 2>&1
      done
    fi
  done

  # Isaac Sim 独立安装
  for ISAAC in $HOME_DIR/isaacsim $HOME_DIR/.local/share/ov/pkg/isaac*; do
    [ -e "$ISAAC" ] && echo "Isaac Sim 包: $ISAAC"
  done
done

hr "ROS Humble"
ls -ld /opt/ros/* 2>/dev/null
if [ -f /opt/ros/humble/setup.bash ]; then
  echo "/opt/ros/humble 存在"
  dpkg -l 'ros-humble-*' 2>/dev/null | awk '/^ii/ {n++} END {print "已装 ros-humble 包数:", n+0}'
else
  echo "!! /opt/ros/humble 缺失"
fi

hr "fcitx / ibus 残留"
dpkg -l | grep -E 'fcitx|ibus|sogou' || echo "(干净)"

hr "完成"
echo "报告: $OUT"
