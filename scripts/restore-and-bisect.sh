#!/bin/bash
# restore-and-bisect.sh — A恢复内置7260 + B迷你模块二分定位 + C更新safeguard (root)
LOG=/home/etworker/driver/iwlwifi/logs/restore-bisect.log
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date '+%F %T') 恢复+二分 开始 (uid=$(id -u)) ==="
if [ "$(id -u)" != 0 ]; then echo "未以 root 运行"; exit 1; fi

echo "--- A. 恢复内置 7260 ---"
mkdir -p /var/backups/ampdu-experiment
if [ -d "/lib/modules/$(uname -r)/updates/dkms" ]; then
  mv "/lib/modules/$(uname -r)/updates/dkms" "/var/backups/ampdu-experiment/dkms-$(date +%s)"
  echo "实验模块已隔离至 /var/backups/ampdu-experiment/"
fi
depmod -a
modprobe -r iwlmvm iwlwifi 2>/dev/null
if modprobe iwlwifi; then echo "stock iwlwifi 已加载"; else echo "stock iwlwifi 加载失败!"; fi
sleep 5
nmcli device connect wlp1s0 2>&1 | tail -1
sleep 3
ping -c3 -W2 192.168.100.1 | tail -2

echo "--- B. 迷你模块二分 ---"
MMERR=$(mktemp)
if insmod /home/etworker/driver/iwlwifi/logs/minmod-test/minmod.ko 2>"$MMERR"; then
  echo "★RESULT: 迷你模块加载成功 → 内核接受同头文件编译的模块; 问题在实验模块自身构建细节"
  rmmod minmod
else
  echo "★RESULT: 迷你模块加载失败 → 内核拒绝一切外置模块(系统性头文件/内核不一致)"
  cat "$MMERR"
  echo "--- 内核日志中 minmod 相关行 ---"
  journalctl -k --since '-2 min' --no-pager 2>/dev/null | grep -iE 'minmod|this_module|module.*size|Exec format' | tail -5
fi
rm -f "$MMERR"

echo "--- C. 更新 safeguard ---"
cp /home/etworker/driver/iwlwifi/logs/wifi-safeguard.sh /usr/local/bin/wifi-safeguard.sh && echo "safeguard 已更新(路径bug修复版)"

echo "--- 当前网络状态 ---"
ip -br addr | grep -E 'wl|en'
echo "=== $(date '+%F %T') 结束 ==="
